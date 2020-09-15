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

    /// Has this fuzzer been stopped?
    public private(set) var isStopped = false

    /// The configuration used by this fuzzer.
    public let config: Configuration

    /// The list of events that can be dispatched on this fuzzer instance.
    public let events: Events

    /// Timer API for this fuzzer.
    public let timers: Timers

    /// The script runner used to execute generated scripts.
    public let runner: ScriptRunner

    /// The fuzzer engine producing new programs from existing ones and executing them.
    public let engine: FuzzEngine

    /// The active code generators.
    public let codeGenerators: WeightedList<CodeGenerator>

    /// The mutators used by the engine.
    public let mutators: WeightedList<Mutator>

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

    /// The DispatchQueue  this fuzzer operates on.
    /// This could in theory be publicly exposed, but then the stopping logic wouldn't work correctly anymore and would probably need to be implemented differently.
    private let queue: DispatchQueue

    /// DispatchGroup to group all tasks related to a fuzzing iterations together and thus be able to determine when they have all finished.
    /// The next fuzzing iteration will only be performed once all tasks in this group have finished. As such, this group can generally be used
    /// for all (long running) tasks during which it doesn't make sense to perform fuzzing.
    private let fuzzGroup = DispatchGroup()

    /// The logger instance for the main fuzzer.
    private var logger: Logger! = nil

    /// State management.
    private var maxIterations = -1
    private var iterations = 0

    /// Constructs a new fuzzer instance with the provided components.
    public init(
        configuration: Configuration, scriptRunner: ScriptRunner, engine: FuzzEngine, mutators: WeightedList<Mutator>,
        codeGenerators: WeightedList<CodeGenerator>, evaluator: ProgramEvaluator, environment: Environment,
        lifter: Lifter, corpus: Corpus, minimizer: Minimizer, queue: DispatchQueue? = nil
    ) {
        // Ensure collect runtime types mode is not enabled without abstract interpreter.
        assert(!configuration.collectRuntimeTypes || configuration.useAbstractInterpretation)

        let uniqueId = UUID()
        self.id = uniqueId
        self.queue = queue ?? DispatchQueue(label: "Fuzzer \(uniqueId)")
        self.config = configuration
        self.events = Events()
        self.timers = Timers(queue: self.queue)
        self.engine = engine
        self.mutators = mutators
        self.codeGenerators = codeGenerators
        self.evaluator = evaluator
        self.environment = environment
        self.lifter = lifter
        self.corpus = corpus
        self.runner = scriptRunner
        self.minimizer = minimizer
    }

    /// Schedule work on this fuzzer's dispatch queue.
    public func async(block: @escaping () -> ()) {
        queue.async {
            guard !self.isStopped else { return }
            block()
        }
    }

    /// Schedule work on this fuzzer's dispatch queue and wait for its completion.
    public func sync(block: () -> ()) {
        queue.sync {
            guard !self.isStopped else { return }
            block()
        }
    }

    /// Adds a module to this fuzzer. Can only be called before the fuzzer is initialized.
    public func addModule(_ module: Module) {
        assert(!isInitialized)
        assert(modules[module.name] == nil)
        modules[module.name] = module
    }

    /// Initializes this fuzzer.
    ///
    /// This will initialize all components and modules, causing event listeners to be registerd,
    /// timers to be scheduled, communication channels to be established, etc. After initialization,
    /// task may already be scheduled on this fuzzer's dispatch queue.
    public func initialize() {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(!isInitialized)

        logger = makeLogger(withLabel: "Fuzzer")

        // Initialize the script runner first so we are able to execute programs.
        runner.initialize(with: self)

        // Then initialize all components.
        engine.initialize(with: self)
        evaluator.initialize(with: self)
        environment.initialize(with: self)
        corpus.initialize(with: self)
        minimizer.initialize(with: self)

        // Finally initialize all modules.
        for module in modules.values {
            module.initialize(with: self)
        }

        // Install a watchdog to monitor utilization of master instances.
        if config.isMaster {
            var lastCheck = Date()
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
            }
        }

        dispatchEvent(events.Initialized)
        logger.info("Initialized")
        isInitialized = true
    }

    /// Starts the fuzzer and runs for the specified number of iterations.
    ///
    /// This must be called after initializing the fuzzer.
    /// Use -1 for maxIterations to run indefinitely.
    public func start(runFor maxIterations: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(isInitialized)
        assert(!corpus.isEmpty)

        self.maxIterations = maxIterations
        logger.info("Let's go!")

        if config.isFuzzing {
            // Start fuzzing
            queue.async {
               self.fuzzOne()
            }
        }
    }

    /// Stops this fuzzer.
    public func stop() {
        dispatchPrecondition(condition: .onQueue(queue))

        logger.info("Shutting down")
        dispatchEvent(events.Shutdown)

        // No more scheduled tasks will execute after this point.
        isStopped = true
        timers.stop()

        dispatchEvent(events.ShutdownComplete)
    }

    /// Registers a new listener for the given event.
    public func registerEventListener<T>(for event: Event<T>, listener: @escaping Event<T>.EventListener) {
        dispatchPrecondition(condition: .onQueue(queue))
        event.addListener(listener)
    }

    /// Dispatches an event.
    public func dispatchEvent<T>(_ event: Event<T>, data: T) {
        dispatchPrecondition(condition: .onQueue(queue))
        for listener in event.listeners {
            listener(data)
        }
    }

    /// Dispatches an event.
    public func dispatchEvent(_ event: Event<Void>) {
        dispatchEvent(event, data: ())
    }

    /// Imports a potentially interesting program into this fuzzer.
    ///
    /// When importing, the program will be treated like one that was generated by this fuzzer. As such it will
    /// be executed and evaluated to determine whether it results in previously unseen, interesting behaviour.
    /// When dropout is enabled, a configurable percentage of programs will be ignored during importing. This
    /// mechanism can help reduce the similarity of different fuzzer instances.
    public func importProgram(_ program: Program, enableDropout: Bool = false, origin: ProgramOrigin) {
        dispatchPrecondition(condition: .onQueue(queue))
        internalImportProgram(program, enableDropout: enableDropout, isCrash: false, origin: origin)
    }

    /// Imports a crashing program into this fuzzer.
    ///
    /// Similar to importProgram, but will make sure to generate a CrashFound event even if the crash does not reproduce.
    public func importCrash(_ program: Program, origin: ProgramOrigin) {
        dispatchPrecondition(condition: .onQueue(queue))
        internalImportProgram(program, enableDropout: false, isCrash: true, origin: origin)
    }

    /// When importing a corpus, this determines how valid samples are added to the corpus
    public enum CorpusImportMode {
        /// All valid samples are added to the corpus. This is intended to aid in finding
        /// variants of existing bugs. Cases are not minimized before inclusion.
        case includeAll
        /// Only imported samples that increase coverage are included in the fuzzing
        /// corpus. These samples are intended as a solid start point based on a
        /// range of Javascript samples. Cases that do increase the coverage are minimized.
        case newCoverageOnly
    }

    /// Imports multiple programs into this fuzzer.
    ///
    /// This will import each program in the given array into this fuzzer while potentially discarding
    /// some percentage of the programs if dropout is enabled.
    public func importCorpus(_ corpus: [Program], importMode: CorpusImportMode, enableDropout: Bool = false) {
        dispatchPrecondition(condition: .onQueue(queue))
        var count = 1
        for program in corpus {
            // Regardless of the import mode, we need to execute and evaluate the program first to update the evaluator state
            let execution = execute(program)
            let maybeAspects = evaluator.evaluate(execution)

            switch importMode {
            case .includeAll:
                processInteresting(program, havingAspects: ProgramAspects(outcome: .succeeded), origin: .corpusImport(shouldMinimize: false))
            case .newCoverageOnly:
                if let aspects = maybeAspects {
                    processInteresting(program, havingAspects: aspects, origin: .corpusImport(shouldMinimize: true))
                }
            }
            if count % 500 == 0 {
                logger.info("Imported \(count) of \(corpus.count)")
            }
            count += 1
        }
        if importMode == .newCoverageOnly {
            fuzzGroup.notify(queue: queue) {
                self.logger.info("Initial corpus minimization complete, resulting in \(self.corpus.size) programs in corpus")
            }
        }
    }

    /// Import a program from somewhere. The imported program will be treated like a freshly generated one.
    ///
    /// - Parameters:
    ///   - program: The program to import.
    ///   - doDropout: If true, the sample is discarded with a small probability. This can be useful to desynchronize multiple instances a bit.
    ///   - isCrash: Whether the program is a crashing sample in which case a crash event will be dispatched in any case.
    ///   - alwaysAddToCorpus: Whether the program should be added to the corpus regardless of whether it increases coverage.
    private func internalImportProgram(_ program: Program, enableDropout: Bool, isCrash: Bool, origin: ProgramOrigin) {
        if enableDropout && probability(config.dropoutRate) {
            return
        }

        let execution = execute(program)
        var didCrash = false

        switch execution.outcome {
        case .crashed(let termsig):
            processCrash(program, withSignal: termsig, origin: origin)
            didCrash = true

        case .succeeded:
            if let aspects = evaluator.evaluate(execution) {
                processInteresting(program, havingAspects: aspects, origin: origin)
            }
        default:
            break
        }

        if !didCrash && isCrash {
            dispatchEvent(events.CrashFound, data: (program, behaviour: .flaky, signal: 0, isUnique: true, origin: origin))
        }
    }

    /// Exports the internal state of this fuzzer.
    ///
    /// The state returned by this function can be passed to the importState method to restore
    /// the state. This can be used to synchronize different fuzzer instances and makes it
    /// possible to resume a previous fuzzing run at a later time.
    public func exportState() throws -> Data {
        dispatchPrecondition(condition: .onQueue(queue))

        let state = try Fuzzilli_Protobuf_FuzzerState.with {
            $0.corpus = try corpus.exportState()
            $0.evaluatorState = evaluator.exportState()
        }
        return try state.serializedData()
    }

    /// Import a previously exported fuzzing state.
    public func importState(from data: Data) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        let state = try Fuzzilli_Protobuf_FuzzerState(serializedData: data)
        try evaluator.importState(state.evaluatorState)
        try corpus.importState(state.corpus)
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
        dispatchPrecondition(condition: .onQueue(queue))
        assert(runner.isInitialized)

        dispatchEvent(events.PreExecute, data: program)

        let script: String
        if config.speedTestMode {
            script = lifter.lift(makeComplexProgram(), withOptions: .minify)
        } else {
            script = lifter.lift(program, withOptions: .minify)
        }
        let execution = runner.run(script, withTimeout: timeout ?? config.timeout)

        dispatchEvent(events.PostExecute, data: execution)

        return execution
    }

    private func inferMissingTypes(in program: Program) {
        var ai = AbstractInterpreter(for: self.environment)
        let runtimeTypes = program.types.onlyRuntimeTypes().indexedByInstruction(for: program)
        var types = ProgramTypes()

        for instr in program.code {
            let typeChanges = ai.execute(instr)

            for (variable, type) in typeChanges {
                types.setType(of: variable, to: type, after: instr.index, quality: .inferred)
            }
            // Overwrite interpreter types with recently collected runtime types
            for (variable, type) in runtimeTypes[instr.index] {
                ai.setType(of: variable, to: type)
                types.setType(of: variable, to: type, after: instr.index, quality: .runtime)
            }
        }

        program.types = types
    }

    /// Collect and save runtime types of variables in program
    private func collectRuntimeTypes(for program: Program) {
        assert(program.typeCollectionStatus == .notAttempted)
        let script = lifter.lift(program, withOptions: .collectTypes)
        let execution = runner.run(script, withTimeout: 30 * config.timeout)
        // JS prints lines alternating between variable name and its type
        let fuzzout = execution.fuzzout
        let lines = fuzzout.split(whereSeparator: \.isNewline)

        if execution.outcome == .succeeded {
            do {
                var lineNumber = 0
                while lineNumber < lines.count {
                    let variable = Variable(number: Int(lines[lineNumber])!), instrCount = Int(lines[lineNumber + 1])!
                    lineNumber += 2
                    // Parse (instruction, type) pairs for given variable
                    for i in stride(from: lineNumber, to: lineNumber + 2 * instrCount, by: 2) {
                        let proto = try Fuzzilli_Protobuf_Type(jsonUTF8Data: lines[i+1].data(using: .utf8)!)
                        let runtimeType = try Type(from: proto)
                        program.types.setType(of: variable, to: runtimeType, after: Int(lines[i])!, quality: .runtime)
                    }
                    lineNumber = lineNumber + 2 * instrCount
                }
            } catch {
                logger.warning("Could not deserialize runtime types: \(error)")
                if config.diagnostics {
                    logger.warning("Fuzzout:\n\(fuzzout)")
                }
            }
        } else {
            logger.warning("Execution for type collection did not succeeded, outcome: \(execution.outcome)")
            if config.diagnostics, case .failed = execution.outcome {
                logger.warning("Stdout:\n\(execution.stdout)")
            }
        }
        // Save result of runtime types collection to Program
        program.typeCollectionStatus = TypeCollectionStatus(from: execution.outcome)
    }

    func updateTypeInformation(for program: Program) {
        if config.collectRuntimeTypes {
            collectRuntimeTypes(for: program)
        }
        // New static types are needed either if program does not have any type info (e.g. was minimized)
        // or we collected runtime types and statical inference can be improved now
        let newTypesNeeded = !program.hasTypeInformation || config.collectRuntimeTypes
        if config.useAbstractInterpretation && newTypesNeeded {
            inferMissingTypes(in: program)
        }
    }

    /// Process a program that has interesting aspects.
    func processInteresting(_ program: Program, havingAspects aspects: ProgramAspects, origin: ProgramOrigin) {
        if !origin.requiresMinimization() {
            var newTypeCollectionRun = false
            if program.typeCollectionStatus == .notAttempted {
                updateTypeInformation(for: program)
                newTypeCollectionRun = true
            }
            return dispatchEvent(events.InterestingProgramFound, data: (program, origin, newTypeCollectionRun))
        }

        fuzzGroup.enter()
        minimizer.withMinimizedCopy(program, withAspects: aspects, usingMode: .normal) { minimizedProgram in
            self.fuzzGroup.leave()
            // Minimization invalidates any existing runtime type information, so always collect them now
            self.updateTypeInformation(for: minimizedProgram)
            self.dispatchEvent(self.events.InterestingProgramFound, data: (minimizedProgram, origin, true))
        }
    }

    /// Process a program that causes a crash.
    func processCrash(_ program: Program, withSignal termsig: Int, origin: ProgramOrigin) {
        fuzzGroup.enter()
        minimizer.withMinimizedCopy(program, withAspects: ProgramAspects(outcome: .crashed(termsig)), usingMode: .aggressive) { minimizedProgram in
            self.fuzzGroup.leave()
            // Check for uniqueness only after minimization
            let execution = self.execute(minimizedProgram, withTimeout: self.config.timeout * 2)
            if case .crashed = execution.outcome {
                let isUnique = self.evaluator.evaluateCrash(execution) != nil
                self.dispatchEvent(self.events.CrashFound, data: (minimizedProgram, .deterministic, termsig, isUnique, origin))
            } else {
                self.dispatchEvent(self.events.CrashFound, data: (minimizedProgram, .flaky, termsig, true, origin))
            }
        }
    }

    /// Constructs a new ProgramBuilder using this fuzzing context.
    public func makeBuilder(mode: ProgramBuilder.Mode = .aggressive) -> ProgramBuilder {
        dispatchPrecondition(condition: .onQueue(queue))
        let interpreter = config.useAbstractInterpretation ? AbstractInterpreter(for: self.environment) : nil
        return ProgramBuilder(for: self, interpreter: interpreter, mode: mode)
    }

    /// Constructs a logger that generates log messages on this fuzzer.
    ///
    /// - Parameter label: The label for the logger.
    /// - Returns: The new Logger instance.
    public func makeLogger(withLabel label: String) -> Logger {
        dispatchPrecondition(condition: .onQueue(queue))
        return Logger(handler: logHandler, label: label, minLevel: config.logLevel)
    }

    /// Log message handler for loggers associated with this fuzzer, dispatches the events.Log event.
    private func logHandler(level: LogLevel, label: String, message: String) {
        dispatchEvent(events.Log, data: (id, level, label, message))
    }

    /// Performs one round of fuzzing.
    private func fuzzOne() {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(config.isFuzzing)

        guard maxIterations == -1 || iterations < maxIterations else {
            stop()
            return
        }
        iterations += 1

        engine.fuzzOne(fuzzGroup)

        // Do the next fuzzing iteration as soon as all tasks related to the current iteration are finished.
        fuzzGroup.notify(queue: queue) {
            guard !self.isStopped else { return }
            self.fuzzOne()
        }
    }

    /// Constructs a non-trivial program. Useful to measure program execution speed.
    private func makeComplexProgram() -> Program {
        let b = makeBuilder()

        let f = b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { params in
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

        return b.finalize()
    }

    /// Runs a number of startup tests to check whether everything is configured correctly.
    public func runStartupTests() {
        assert(isInitialized)

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
        var execution = execute(Program())
        guard case .succeeded = execution.outcome else {
            logger.fatal("Cannot execute programs (exit code must be zero when no exception was thrown). Are the command line flags valid?")
        }

        // Check if we can detect failed executions (i.e. an exception was thrown)
        var b = self.makeBuilder()
        let exception = b.loadInt(42)
        b.throwException(exception)
        execution = execute(b.finalize())
        guard case .failed = execution.outcome else {
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
            execution = execute(b.finalize())
            guard case .crashed = execution.outcome else {
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
        b.doPrint(str)
        let output = execute(b.finalize()).fuzzout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output != "Hello World!" {
            logger.warning("Cannot receive FuzzIL output (got \"\(output)\" instead of \"Hello World!\")")
        }

        // Check if we can collect runtime types if enabled
        if config.collectRuntimeTypes {
            b = self.makeBuilder()
            b.binary(b.loadInt(42), b.loadNull(), with: .Add)
            let program = b.finalize()

            collectRuntimeTypes(for: program)
            // First 2 variables are inlined and abstractInterpreter will take care ot these types
            let expectedTypes = ProgramTypes(
                from: VariableMap([0: (.integer, .inferred), 1: (.undefined, .inferred), 2: (.integer, .runtime)]),
                in: program
            )
            guard program.types == expectedTypes, program.typeCollectionStatus == .success else {
                logger.fatal("Cannot collect runtime types (got \"\(program.types)\" instead of \"\(expectedTypes)\")")
            }
        }

        logger.info("Startup tests finished successfully")
    }
}
