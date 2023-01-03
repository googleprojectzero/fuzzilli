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
    public private(set) var engine: FuzzEngine
    /// During initial corpus generation, the current engine will be a GenerativeEngine while this will keep a reference to the "real" engine to use after corpus generation.
    private var nextEngine: FuzzEngine?

    /// The active code generators. It is possible to change these (temporarily) at runtime. This is e.g. done by some ProgramTemplates.
    public var codeGenerators: WeightedList<CodeGenerator>

    /// The active program templates. These are only used if the HybridEngine is enabled.
    public let programTemplates: WeightedList<ProgramTemplate>

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

    /// The minimizer to shrink programs that cause crashes or trigger new interesting behaviour.
    public let minimizer: Minimizer

    public enum Phase {
        // Importing and minimizing an existing corpus
        case corpusImport
        // When starting with an empty corpus, we will do some initial corpus generation using the GenerativeEngine
        case initialCorpusGeneration
        // Regular fuzzing using the configured FuzzEngine
        case fuzzing
    }

    /// The current phase of the fuzzer
    public private(set) var phase: Phase = .fuzzing

    /// The modules active on this fuzzer.
    var modules = [String: Module]()

    /// The DispatchQueue  this fuzzer operates on.
    /// This could in theory be publicly exposed, but then the stopping logic wouldn't work correctly anymore and would probably need to be implemented differently.
    private let queue: DispatchQueue

    /// DispatchGroup to group all tasks related to a fuzzing iteration together and thus be able to determine when they have all finished.
    /// The next fuzzing iteration will only be performed once all tasks in this group have finished. As such, this group can generally be used
    /// for all (long running) tasks during which it doesn't make sense to perform fuzzing.
    private let fuzzGroup = DispatchGroup()

    /// The logger instance for the main fuzzer.
    private var logger: Logger

    /// State management.
    private var maxIterations = -1
    private var iterations = 0
    private var iterationOfLastInteratingSample = 0

    private var iterationsSinceLastInterestingProgram: Int {
        assert(iterations >= iterationOfLastInteratingSample)
        return iterations - iterationOfLastInteratingSample
    }

    /// Fuzzer instances can be looked up from a dispatch queue through this key. See below.
    private static let dispatchQueueKey = DispatchSpecificKey<Fuzzer>()

    /// List of trivial CodeGenerators that don't require inputs and generate simple values that can subsequently be used.
    public let trivialCodeGenerators: [CodeGenerator] = [
            CodeGenerators.get("IntegerGenerator"),
            CodeGenerators.get("StringGenerator"),
            CodeGenerators.get("FloatGenerator"),
        ]

    /// Constructs a new fuzzer instance with the provided components.
    public init(
        configuration: Configuration, scriptRunner: ScriptRunner, engine: FuzzEngine, mutators: WeightedList<Mutator>,
        codeGenerators: WeightedList<CodeGenerator>, programTemplates: WeightedList<ProgramTemplate>, evaluator: ProgramEvaluator,
        environment: Environment, lifter: Lifter, corpus: Corpus, minimizer: Minimizer, queue: DispatchQueue? = nil
    ) {
        let uniqueId = UUID()
        self.id = uniqueId
        self.queue = queue ?? DispatchQueue(label: "Fuzzer \(uniqueId)", target: DispatchQueue.global())

        self.config = configuration
        self.events = Events()
        self.timers = Timers(queue: self.queue)
        self.engine = engine
        self.mutators = mutators
        self.codeGenerators = codeGenerators
        self.programTemplates = programTemplates
        self.evaluator = evaluator
        self.environment = environment
        self.lifter = lifter
        self.corpus = corpus
        self.runner = scriptRunner
        self.minimizer = minimizer
        self.logger = Logger(withLabel: "Fuzzer")

        // Register this fuzzer instance with its queue so that it is possible to
        // obtain a reference to the Fuzzer instance when running on its queue.
        // This creates a reference cycle, but Fuzzer instances aren't expected
        // to be deallocated, so this is ok.
        self.queue.setSpecific(key: Fuzzer.dispatchQueueKey, value: self)
    }

    /// Returns the fuzzer for the active DispatchQueue.
    public static var current: Fuzzer? {
        return DispatchQueue.getSpecific(key: Fuzzer.dispatchQueueKey)
    }

    /// Schedule work on this fuzzer's dispatch queue.
    public func async(do block: @escaping () -> ()) {
        queue.async {
            guard !self.isStopped else { return }
            block()
        }
    }

    /// Schedule work on this fuzzer's dispatch queue and wait for its completion.
    public func sync(do block: () -> ()) {
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

        // Install a watchdog to monitor utilization instances.
        var lastCheck = Date()
        timers.scheduleTask(every: 1 * Minutes) {
            // Monitor responsiveness
            let now = Date()
            let interval = now.timeIntervalSince(lastCheck)
            lastCheck = now
            if interval > 180 {
                self.logger.warning("Fuzzer appears unresponsive (watchdog only triggered after \(Int(interval))s instead of 60s).")
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

        self.maxIterations = maxIterations

        // There could currently be minimization tasks scheduled from a corpus import.
        // Wait for these to complete before actually starting to fuzz.
        fuzzGroup.notify(queue: queue) { self.startFuzzing() }
    }

    private func startFuzzing() {
        dispatchPrecondition(condition: .onQueue(queue))

        // When starting with an empty corpus, perform initial corpus generation using the GenerativeEngine.
        if corpus.isEmpty {
            logger.info("Empty corpus detected. Switching to the GenerativeEngine to perform initial corpus generation")
            startInitialCorpusGeneration()
        }

        logger.info("Let's go!")

        if config.isFuzzing {
            fuzzOne()
        }
    }

    /// Shuts down this fuzzer.
    public func shutdown(reason: ShutdownReason) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !isStopped else { return }

        // No more scheduled tasks will execute after this point.
        isStopped = true
        timers.stop()

        logger.info("Shutting down due to \(reason)")
        dispatchEvent(events.Shutdown, data: reason)

        dispatchEvent(events.ShutdownComplete, data: reason)
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

        if enableDropout && probability(config.dropoutRate) {
            return
        }

        let execution = execute(program)
        switch execution.outcome {
        case .crashed(let termsig):
            // Here we explicitly deal with the possibility that an interesting sample
            // from another instance triggers a crash in this instance.
            processCrash(program, withSignal: termsig, withStderr: execution.stderr, withStdout: execution.stdout, origin: origin, withExectime: execution.execTime)

        case .succeeded:
            if let aspects = evaluator.evaluate(execution) {
                processMaybeInteresting(program, havingAspects: aspects, origin: origin)
            }

        default:
            break
        }
    }

    /// Imports a crashing program into this fuzzer.
    ///
    /// Similar to importProgram, but will make sure to generate a CrashFound event even if the crash does not reproduce.
    public func importCrash(_ program: Program, origin: ProgramOrigin) {
        dispatchPrecondition(condition: .onQueue(queue))

        let execution = execute(program)
        if case .crashed(let termsig) = execution.outcome {
            processCrash(program, withSignal: termsig, withStderr: execution.stderr, withStdout: execution.stdout, origin: origin, withExectime: execution.execTime)
        } else {
            // Non-deterministic crash
            dispatchEvent(events.CrashFound, data: (program, behaviour: .flaky, isUnique: true, origin: origin))
        }
    }

    /// When importing a corpus, this determines how valid samples are added to the corpus
    public enum CorpusImportMode {
        /// All valid programs are added to the corpus. This is intended to aid in finding
        /// variants of existing bugs. Programs are not minimized before inclusion.
        case all

        /// Only programs that increase coverage are included in the fuzzing corpus.
        /// These samples are intended as a solid starting point for the fuzzer.
        case interestingOnly(shouldMinimize: Bool)
    }

    /// Imports multiple programs into this fuzzer.
    ///
    /// This will import each program in the given array into this fuzzer while potentially discarding
    /// some percentage of the programs if dropout is enabled.
    public func importCorpus(_ corpus: [Program], importMode: CorpusImportMode, enableDropout: Bool = false) {
        dispatchPrecondition(condition: .onQueue(queue))
        for (count, program) in corpus.enumerated() {
            if count % 500 == 0 {
                logger.info("Imported \(count) of \(corpus.count)")
            }
            // Regardless of the import mode, we need to execute and evaluate the program first to update the evaluator state
            let execution = execute(program)
            guard execution.outcome == .succeeded else { continue }
            let maybeAspects = evaluator.evaluate(execution)

            switch importMode {
            case .all:
                self.corpus.add(program, maybeAspects ?? ProgramAspects(outcome: .succeeded))
            case .interestingOnly(let shouldMinimize):
                if let aspects = maybeAspects {
                    processMaybeInteresting(program, havingAspects: aspects, origin: .corpusImport(shouldMinimize: shouldMinimize))
                }
            }
        }

        if case .interestingOnly(let shouldMinimize) = importMode, shouldMinimize {
            // The corpus is being minimized now. Schedule a task to signal when the corpus import has really finished
            phase = .corpusImport
            fuzzGroup.notify(queue: queue) {
                self.logger.info("Corpus import and minimization completed. Corpus now contains \(self.corpus.size) programs")
                self.phase = .fuzzing
            }
        }
    }

    /// All programs currently in the corpus.
    public func exportCorpus() -> [Program] {
        return corpus.allPrograms()
    }

    /// Exports the internal state of this fuzzer.
    ///
    /// The state returned by this function can be passed to the importState method to restore
    /// the state. This can be used to synchronize different fuzzer instances and makes it
    /// possible to resume a previous fuzzing run at a later time.
    /// Note that for this to work, the instances need to be configured identically, i.e. use
    /// the same components (in particular, corpus) and the same build of the target engine.
    public func exportState() throws -> Data {
        dispatchPrecondition(condition: .onQueue(queue))

        if supportsFastStateSynchronization {
            let state = try Fuzzilli_Protobuf_FuzzerState.with {
                $0.corpus = try corpus.exportState()
                $0.evaluatorState = evaluator.exportState()
            }
            return try state.serializedData()
        } else {
            // Just export all samples in the current corpus
            return try encodeProtobufCorpus(exportCorpus())
        }
    }

    /// Import a previously exported fuzzing state.
    public func importState(from data: Data) throws {
        dispatchPrecondition(condition: .onQueue(queue))

        if supportsFastStateSynchronization {
            let state = try Fuzzilli_Protobuf_FuzzerState(serializedData: data)
            try corpus.importState(state.corpus)
            try evaluator.importState(state.evaluatorState)
        } else {
            let corpus = try decodeProtobufCorpus(data)
            importCorpus(corpus, importMode: .interestingOnly(shouldMinimize: false))
        }
    }

    /// Whether the internal state of this fuzzer instance can be serialized and restored elsewhere, e.g. on a worker instance.
    private var supportsFastStateSynchronization: Bool {
        // We might eventually need to check that the other relevant components
        // (in particular the evaluator) support this as well, but currenty all
        // of them do.
        return corpus.supportsFastStateSynchronization
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

        let script = lifter.lift(program)

        dispatchEvent(events.PreExecute, data: program)
        let execution = runner.run(script, withTimeout: timeout ?? config.timeout)
        dispatchEvent(events.PostExecute, data: execution)

        return execution
    }

    /// Process a program that appears to have interesting aspects.
    /// This function will first determine which (if any) of the interesting aspects are triggered reliably, then schedule the program for minimization and inclusion in the corpus.
    /// Returns true if this program was interesting (i.e. had at least some interesting aspects that are triggered reliably), false if not.
    @discardableResult
    func processMaybeInteresting(_ program: Program, havingAspects aspects: ProgramAspects, origin: ProgramOrigin) -> Bool {
        var aspects = aspects

        // Determine which (if any) aspects of the program are triggered deterministially.
        // For that, the sample is executed at a few more times and the intersection of the interesting aspects of each execution is computed.
        // Once that intersection is stable, the remaining aspects are considered to be triggered deterministic.
        let minAttempts = 5
        let maxAttempts = 50
        var didConverge = false
        var attempt = 0
        repeat {
            attempt += 1
            if attempt > maxAttempts {
                logger.warning("Sample did not converage after \(maxAttempts) attempts. Discarding it")
                return false
            }

            guard let intersection = evaluator.computeAspectIntersection(of: program, with: aspects) else {
                // This likely means that no aspects are triggered deterministically, so discard this sample.
                return false
            }

            // Since evaluateAndIntersect will only ever return aspects that are equivalent to, or a subset of,
            // the provided aspects, we can check if they are identical by comparing their sizes
            didConverge = aspects.count == intersection.count
            aspects = intersection
        } while !didConverge || attempt < minAttempts

        if origin == .local {
            iterationOfLastInteratingSample = iterations
        }

        // Determine whether the program needs to be minimized, then, using this helper function, dispatch the appropriate
        // event and insert the sample into the corpus.
        func finishProcessing(_ program: Program) {
            if config.enableInspection {
                if origin == .local {
                    program.comments.add("Program is interesting due to \(aspects)", at: .footer)
                } else {
                    program.comments.add("Imported program is interesting due to \(aspects)", at: .footer)
                }
            }
            assert(!program.code.contains(where: { $0.op is JsInternalOperation }))
            dispatchEvent(events.InterestingProgramFound, data: (program, origin))
            corpus.add(program, aspects)
        }

        if !origin.requiresMinimization() {
            finishProcessing(program)
        } else {
            // Minimization should be performed as part of the fuzzing dispatch group. This way, the next fuzzing iteration
            // will only start once the curent sample has been fully processed and inserted into the corpus.
            fuzzGroup.enter()
            minimizer.withMinimizedCopy(program, withAspects: aspects, limit: config.minimizationLimit) { minimizedProgram in
                self.fuzzGroup.leave()
                finishProcessing(minimizedProgram)
            }
        }
        return true
    }

    /// Process a program that causes a crash.
    func processCrash(_ program: Program, withSignal termsig: Int, withStderr stderr: String, withStdout stdout: String, origin: ProgramOrigin, withExectime exectime: TimeInterval) {
        func processCommon(_ program: Program) {
            let hasCrashInfo = program.comments.at(.footer)?.contains("CRASH INFO") ?? false
            if !hasCrashInfo {
                program.comments.add("CRASH INFO\n==========\n", at: .footer)
                program.comments.add("TERMSIG: \(termsig)\n", at: .footer)
                program.comments.add("STDERR:\n" + stderr, at: .footer)
                program.comments.add("STDOUT:\n" + stdout, at: .footer)
                program.comments.add("ARGS: \(runner.processArguments.joined(separator: " "))\n", at: .footer)
                program.comments.add("EXECUTION TIME: \(Int(exectime * 1000)) ms", at: .footer)
            }
            assert(program.comments.at(.footer)?.contains("CRASH INFO") ?? false)

            // Check for uniqueness only after minimization
            let execution = execute(program, withTimeout: self.config.timeout * 2)
            if case .crashed = execution.outcome {
                let isUnique = evaluator.evaluateCrash(execution) != nil
                dispatchEvent(events.CrashFound, data: (program, .deterministic, isUnique, origin))
            } else {
                dispatchEvent(events.CrashFound, data: (program, .flaky, true, origin))
            }
        }

        if !origin.requiresMinimization() {
            return processCommon(program)
        }

        fuzzGroup.enter()
        minimizer.withMinimizedCopy(program, withAspects: ProgramAspects(outcome: .crashed(termsig))) { minimizedProgram in
            self.fuzzGroup.leave()
            processCommon(minimizedProgram)
        }
    }

    /// Constructs a new ProgramBuilder using this fuzzing context.
    public func makeBuilder(forMutating parent: Program? = nil, mode: ProgramBuilder.Mode = .aggressive) -> ProgramBuilder {
        dispatchPrecondition(condition: .onQueue(queue))
        // Program ancestor chains are only constructed if inspection mode is enabled
        let parent = config.enableInspection ? parent : nil
        return ProgramBuilder(for: self, parent: parent, mode: mode)
    }

    /// Performs one round of fuzzing.
    private func fuzzOne() {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(config.isFuzzing)

        guard !self.isStopped else { return }

        guard maxIterations == -1 || iterations < maxIterations else {
            return shutdown(reason: .finished)
        }
        iterations += 1

        engine.fuzzOne(fuzzGroup)

        if phase == .initialCorpusGeneration {
            // Perform initial corpus generation until we haven't found a new interesting sample in the last N
            // iterations. The rough order of magnitude of N has been determined experimentally: run two instances with
            // different values (e.g. 10 and 100) for roughly the same number of iterations (approximately until both
            // have finished the initial corpus generation), then compare the corpus size and coverage.
            if iterationsSinceLastInterestingProgram > 100 {
                guard !corpus.isEmpty else {
                    logger.fatal("Initial corpus generation failed, corpus is still empty. Is the evaluator working correctly?")
                }
                logger.info("Initial corpus generation finished. Corpus now contains \(corpus.size) elements")
                finishInitialCorpusGeneration()
            }
        }

        // Do the next fuzzing iteration as soon as all tasks related to the current iteration are finished.
        fuzzGroup.notify(queue: queue) {
            self.fuzzOne()
        }
    }

    private func startInitialCorpusGeneration() {
        nextEngine = engine
        engine = GenerativeEngine()
        engine.initialize(with: self)
        phase = .initialCorpusGeneration
    }

    private func finishInitialCorpusGeneration() {
        engine = nextEngine!
        nextEngine = nil
        phase = .fuzzing
    }

    /// Constructs a non-trivial program. Useful to measure program execution speed.
    private func makeComplexProgram() -> Program {
        let b = makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 2)) { params in
            let x = b.loadProperty("x", of: params[0])
            let y = b.loadProperty("y", of: params[0])
            let s = b.binary(x, y, with: .Add)
            let p = b.binary(s, params[1], with: .Mul)
            b.doReturn(p)
        }

        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(1000), .Add, b.loadInt(1)) { i in
            let x = b.loadInt(42)
            let y = b.loadInt(43)
            let arg1 = b.createObject(with: ["x": x, "y": y])
            let arg2 = i
            b.callFunction(f, withArgs: [arg1, arg2])
        }

        return b.finalize()
    }

    // Verifies that the fuzzer is not creating a large number of core dumps
    public func checkCoreFileGeneration() {
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
    }

    /// Runs a number of startup tests to check whether everything is configured correctly.
    public func runStartupTests() {
        assert(isInitialized)

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

        var maxExecutionTime: TimeInterval = 0
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

        // Determine recommended timeout value (rounded up to nearest multiple of 10ms)
        let maxExecutionTimeMs = (Int(maxExecutionTime * 1000 + 9) / 10) * 10
        let recommendedTimeout = 10 * maxExecutionTimeMs
        logger.info("Recommended timeout: at least \(recommendedTimeout)ms. Current timeout: \(config.timeout)ms")

        // Check if we can receive program output
        b = makeBuilder()
        let str = b.loadString("Hello World!")
        b.doPrint(str)
        let output = execute(b.finalize()).fuzzout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output != "Hello World!" {
            logger.warning("Cannot receive FuzzIL output (got \"\(output)\" instead of \"Hello World!\")")
        }

        logger.info("Startup tests finished successfully")
    }
}
