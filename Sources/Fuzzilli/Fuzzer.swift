// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

public class Fuzzer {
    /// Id of this fuzzer.
    public let id: UUID
    
    /// Has this fuzzer been initialized?
    public private(set) var isInitialized = false

    /// The configuration used by this fuzzer.
    public let config: Configuration
    
    /// The OperationQueue that this fuzzer operates on.
    public let queue: OperationQueue
    
    /// The list of events that can be dispatched on this fuzzer instance.
    public let events: Events
    
    /// Timer API for this fuzzer.
    public let timers: Timers
    
    /// The script runner used to execute generated scripts.
    public let runner: ScriptRunner
    
    /// The core fuzzer producing new programs from existing ones and executing them.
    public let core: FuzzerCore
    
    /// The active code generators.
    public let codeGenerators: WeightedList<CodeGenerator>
    
    /// The evaluator to score generated programs.
    public let evaluator: ProgramEvaluator
    
    /// The model of the target environment.
    public let environment: Environment
    
    /// The lifter to translate FuzzIL programs to the target language.
    public let lifter: Lifter
    
    /// The corpus of "interesting" programs found so far.
    public let corpus: Corpus
    
    // The minimizer to shrink programs that cause crashes or trigger new interesting behaviour.
    public let minimizer: Minimizer
    
    /// The modules active on this fuzzer.
    var modules = [String: Module]()
    
    /// The logger instance to use for the main fuzzer.
    private let logger: Logger
    
    /// State management.
    private var maxIterations = -1
    private var iterations = 0

    /// Constructs a new fuzzer instance with the provided components.
    public init(configuration: Configuration, scriptRunner: ScriptRunner, coreFuzzer: FuzzerCore, codeGenerators: WeightedList<CodeGenerator>, evaluator: ProgramEvaluator, environment: Environment, lifter: Lifter, corpus: Corpus, minimizer: Minimizer, queue: OperationQueue? = nil) {
        self.id = UUID()
        self.queue = queue ?? OperationQueue()
        self.queue.maxConcurrentOperationCount = 1
        self.queue.name = "Fuzzer \(id)"
        self.config = configuration
        self.events = Events(self.queue)
        self.timers = Timers(queue: self.queue)
        self.logger = Logger(creator: id, logEvent: events.Log, label: "Fuzzer", minLevel: config.logLevel)
        self.core = coreFuzzer
        self.codeGenerators = codeGenerators
        self.evaluator = evaluator
        self.environment = environment
        self.lifter = lifter
        self.corpus = corpus
        self.runner = scriptRunner
        self.minimizer = minimizer
    }
    
    /// Adds a module to this fuzzer. Can only be called before the fuzzer is initialized.
    public func addModule(_ module: Module) {
        precondition(!isInitialized)
        precondition(modules[module.name] == nil)
        assert(OperationQueue.current == queue)
        modules[module.name] = module
    }

    /// Starts the fuzzer and runs for the specified number of iterations.
    ///
    /// This must be called after initializing the fuzzer.
    /// Use -1 for maxIterations to run indefinitely.
    public func start(runFor maxIterations: Int) {
        precondition(isInitialized)
        assert(OperationQueue.current == queue)
        
        self.maxIterations = maxIterations
        
        self.runStartupTests()
        
        logger.info("Let's go!")
        
        // Start fuzzing
        queue.addOperation {
           self.fuzzOne()
        }
    }
    
    /// Stops this fuzzer.
    public func stop() {
        assert(OperationQueue.current == queue)
        
        logger.info("Shutting down")
        events.Shutdown.dispatch()
        
        // Stop any pending or future tasks now
        queue.cancelAllOperations()
        queue.isSuspended = true
        
        events.ShutdownComplete.dispatch()
    }
    
    /// Initializes this fuzzer.
    ///
    /// This will initialize all components and modules, causing event listeners to be registerd,
    /// timers to be scheduled, communication channels to be established, etc. After initialization,
    /// task may already be scheduled on this fuzzer's dispatch queue.
    public func initialize() {
        precondition(!isInitialized)
        assert(OperationQueue.current == queue)
        
        // Initialize the script runner first so we are able to execute programs.
        runner.initialize(with: self)
        
        // Then initialize all components.
        core.initialize(with: self)
        evaluator.initialize(with: self)
        environment.initialize(with: self)
        lifter.initialize(with: self)
        corpus.initialize(with: self)
        minimizer.initialize(with: self)
        
        // Finally initialize all modules.
        for module in modules.values {
            module.initialize(with: self)
        }
        
        /// Populate the corpus if necessary.
        if corpus.isEmpty {
            let b = makeBuilder()
            
            let objectConstructor = b.loadBuiltin("Object")
            b.callFunction(objectConstructor, withArgs: [])
            
            let program = b.finish()
            
            corpus.add(program)
        }
        
        // Install a watchdog to monitor utilization of master instances.
        if config.isMaster {
            var lastCheck = Date()
            var lastReset = 0
            timers.scheduleTask(every: 1 * Minutes) {
                // Monitor responsiveness
                let now = Date()
                let interval = now.timeIntervalSince(lastCheck)
                lastCheck = now
                // Currently, minimization can take a very long time (up to a few minutes on slow CPUs for
                // big samples). As such, the fuzzer would quickly be regarded as unresponsive by this metric.
                // Ideally, it would be possible to split minimization into multiple smaller tasks or otherwise
                // reduce its impact on the responsiveness of the fuzzer. But for now we just use a very large
                // tolerance interval here...
                if interval > 180 {
                    self.logger.warning("Fuzzing master appears unresponsive (watchdog only triggered after \(Int(interval))s instead of 60s). This is usually fine but will slow down synchronization a bit")
                }
                
                // Monitor utilization. If the size of the operation queue hasn't fallen
                // below 5 for 15 minutes in a row, then we might be overloaded.
                let currentQueueSize = self.queue.operationCount
                if currentQueueSize < 5 {
                    lastReset = 0
                } else {
                    lastReset += 1
                    if lastReset >= 15 {
                        self.logger.warning("Fuzzing master appears overloaded (pending tasks: \(currentQueueSize)). Maybe reduce the number of workers")
                        lastReset = 0
                    }
                }
            }
        }
        
        events.Initialized.dispatch()
        logger.info("Initialized")
        isInitialized = true
    }
    
    /// Imports a potentially interesting program into this fuzzer.
    ///
    /// When importing, the program will be treated like one that was generated by this fuzzer. As such it will
    /// be executed and evaluated to determine whether it results in previously unseen, interesting behaviour.
    /// When dropout is enabled, a configurable percentage of programs will be ignored during importing. This
    /// mechanism can help reduce the similarity of different fuzzer instances.
    public func importProgram(_ program: Program, withDropout applyDropout: Bool = false) {
        core.importProgram(program, withDropout: applyDropout)
    }
    
    /// Imports a crashing program into this fuzzer.
    ///
    /// Similar to importProgram, but will make sure to generate a CrashFound event even if the crash does not reproduce.
    public func importCrash(_ program: Program) {
        core.importProgram(program, withDropout: false, isCrash: true)
    }
    
    /// Imports multiple programs into this fuzzer.
    ///
    /// This will import each program in the given array into this fuzzer while potentially discarding
    /// some percentage of the programs if dropout is enabled.
    public func importCorpus(_ corpus: [Program], withDropout applyDropout: Bool = false) {
        for program in corpus {
            core.importProgram(program, withDropout: applyDropout)
        }
    }
    
    /// Exports the internal state of this fuzzer.
    ///
    /// The state returned by this function can be passed to the importState method to restore
    /// the state. This can be used to synchronize different fuzzer instances and makes it
    /// possible to resume a previous fuzzing run at a later time.
    public func exportState() -> State {
        return State(corpus: corpus.exportState(), evaluatorState: evaluator.exportState())
    }
    
    /// Import a previously exported fuzzing state.
    ///
    /// If importing fails, this method will throw a Fuzzilli.RuntimeError.
    public func importState(_ state: State) throws {
        try corpus.importState(state.corpus)
        try evaluator.importState(state.evaluatorState)
    }
    
    /// Executes a program.
    ///
    /// This will first lift the given FuzzIL program to the target language, then use the configured script runner to execute it.
    ///
    /// - Parameters:
    ///   - program: The FuzzIL program to execute.
    ///   - timeout: The timeout after which to abort execution. If nil, the default timeout of this fuzzer will be used.
    /// - Returns: An Execution structure representing the execution outcome.
    public func execute(_ program: Program, withTimeout timeout: UInt32? = nil) -> Execution {
        assert(runner.isInitialized)
        assert(OperationQueue.current == queue)
        
        events.PreExecute.dispatch(with: program)
        
        let script: String
        if config.speedTestMode {
            script = lifter.lift(makeComplexProgram())
        } else {
            script = lifter.lift(program)
        }
        let execution = runner.run(script, withTimeout: timeout ?? config.timeout)
        
        events.PostExecute.dispatch(with: execution)
        
        return execution
    }
    
    /// Constructs a new ProgramBuilder using this fuzzing context.
    public func makeBuilder() -> ProgramBuilder {
        return ProgramBuilder(for: self)
    }
    
    /// Constructs a logger that generates log messages on this fuzzer.
    ///
    /// - Parameter label: The label for the logger.
    /// - Returns: The new Logger instance.
    public func makeLogger(withLabel label: String) -> Logger {
        return Logger(creator: id, logEvent: events.Log, label: label, minLevel: config.logLevel)
    }
    
    /// Performs one round of fuzzing.
    private func fuzzOne() {
        guard maxIterations == -1 || iterations < maxIterations else {
            return
        }
        iterations += 1
        
        core.fuzzOne()
        
        // Fuzz another one.
        // We only want do actual fuzzing if there is nothing else to do. For that
        // reason we enqueue the corresponding operations with low priority.
        let op = BlockOperation(block: self.fuzzOne)
        op.queuePriority = .veryLow
        queue.addOperation(op)
    }

    /// Constructs a non-trivial program. Useful to measure program execution speed.
    private func makeComplexProgram() -> Program {
        let b = makeBuilder()
        
        let f = b.defineFunction(numParameters: 2, isJSStrictMode: false, hasRestParam: false) { params in
            let x = b.loadProperty("x", of: params[0])
            let y = b.loadProperty("y", of: params[0])
            let s = b.binary(x, y, with: .Add)
            let p = b.binary(s, params[1], with: .Mul)
            b.doReturn(value: p)
        }
        
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(1000), .Add, b.loadInt(1)) { i in
            let x = b.loadInt(42)
            let y = b.loadInt(43)
            let arg1 = b.createObject(with: ["x": x, "y": y])
            let arg2 = i
            b.callFunction(f, withArgs: [arg1, arg2])
        }
        
        return b.finish()
    }
    
    /// Runs a number of startup tests to check whether everything is configured correctly.
    private func runStartupTests() {
        guard !config.speedTestMode else {
            logger.info("Skipping startup tests due to speed test mode")
            return
        }
        
        #if os(Linux)
        do {
            let corePattern = try String(contentsOfFile: "/proc/sys/kernel/core_pattern", encoding: String.Encoding.ascii)
            if !corePattern.hasPrefix("|/bin/false") {
                logger.fatal("Please run: sudo sysctl -w 'kernel.core_pattern=|/bin/false'")
            }
        } catch {
            logger.warning("Could not check core dump behaviour. Please ensure core_pattern is set to '|/bin/false'")
        }
        #endif
        
        // Check if we can execute programs
        if execute(Program()).outcome != .succeeded {
            logger.fatal("Cannot execute programs (exit code must be zero when no exception was thrown). Are the command line flags valid?")
        }
        
        // Check if we can detect failed executions (i.e. an exception was thrown)
        var b = self.makeBuilder()
        let exception = b.loadInt(42)
        b.throwException(exception)
        if execute(b.finish()).outcome != .failed {
            logger.fatal("Cannot detect failed executions (exit code must be nonzero when an uncaught exception was thrown)")
        }
        
        var maxExecutionTime: UInt = 0
        // Dispatch a non-trivial program and measure its execution time
        let complexProgram = makeComplexProgram()
        for _ in 0..<5 {
            let execution = execute(complexProgram)
            maxExecutionTime = max(maxExecutionTime, execution.execTime)
        }
        
        // Check if we can detect crashes and measure their execution time
        for test in config.crashTests {
            b = makeBuilder()
            b.eval(test)
            let execution = execute(b.finish())
            if execution.outcome != .crashed {
                logger.fatal("Testcase \"\(test)\" did not crash")
            }
            maxExecutionTime = max(maxExecutionTime, execution.execTime)
        }
        if config.crashTests.isEmpty {
            logger.warning("Cannot check if crashes are detected")
        }
        
        // Determine recommended timeout value
        let recommendedTimeout = 10 * ((Double(maxExecutionTime) * 10) / 10).rounded()
        logger.info("Recommended timeout: at least \(Int(recommendedTimeout))ms. Current timeout: \(config.timeout)ms")
        
        // Check if we can receive program output
        b = makeBuilder()
        let str = b.loadString("Hello World!")
        b.print(str)
        if execute(b.finish()).output.trimmingCharacters(in: .whitespacesAndNewlines) != "Hello World!" {
            logger.warning("Cannot receive FuzzIL output")
        }
        
        logger.info("Startup tests finished successfully")
    }
    
    /// The internal state of a fuzzer.
    ///
    /// Can be exported and later imported again or used to synchronize workers.
    public struct State: Codable {
        // Really only the corpus and the evaluator have permanent state.
        public let corpus: [Program]
        public let evaluatorState: Data
    }
}
