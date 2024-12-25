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

    /// The active code generators. It is possible to change these (temporarily) at runtime. This is e.g. done by some ProgramTemplates.
    public private(set) var codeGenerators: WeightedList<CodeGenerator>

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

    /// The engine used for initial corpus generation (if performed).
    public let corpusGenerationEngine = GenerativeEngine()

    /// The possible states of a fuzzer.
    public enum State {
        // Initial state of the fuzzer. Will be changed to one of the below states during
        // initialization.
        case uninitialized

        // When running as a child node for distributed fuzzing, indicates that we're waiting
        // for our parent node to send as our initial corpus.
        // Child nodes remain in this state (and do effectively nothing) until they have
        // received a corpus (containing at least one program) from their parent node.
        case waiting

        // Importing and potentially minimizing an existing corpus.
        case corpusImport

        // Generating an initial corpus. Used when no existing corpus is imported and when
        // this instance isn't configured to receive a corpus from its parent node.
        case corpusGeneration

        // Fuzzing with the configured engine.
        case fuzzing
    }

    /// The current state of this fuzzer.
    public private(set) var state: State = .uninitialized

    private func changeState(to newState: State) {
        logger.info("Changing state from \(state) to \(newState)")

        // Some state transitions are forbidden, check for those here.
        assert(newState != .uninitialized)      // We never transition into .uninitialized
        assert(newState != .waiting || state == .uninitialized)     // We're only transitioning into .waiting during initialization
        assert(state != .fuzzing)   // Currently we never transition out of .fuzzing (although we could allow scheduling a corpus import while already fuzzing)

        state = newState
    }

    /// Start time of this fuzzing session
    private let startTime = Date()

    /// Returns the uptime of this fuzzer as TimeInterval.
    public func uptime() -> TimeInterval {
        return -startTime.timeIntervalSinceNow
    }

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

    public enum ExitCondition {
        // Fuzz indefinitely.
        case none
        // Fuzz until a specified number of iterations have been performed.
        case iterationsPerformed(Int)
        // Fuzz for a specified amount of time.
        case timeFuzzed(TimeInterval)
    }

    /// How long to fuzz?
    private var exitCondition = ExitCondition.none

    /// State management.
    private var iterations = 0
    private var iterationOfLastInteratingSample = 0

    /// Currently active corpus import job, if any.
    private var currentCorpusImportJob = CorpusImportJob(corpus: [], mode: .full)

    private var iterationsSinceLastInterestingProgram: Int {
        assert(iterations >= iterationOfLastInteratingSample)
        return iterations - iterationOfLastInteratingSample
    }

    /// Fuzzer instances can be looked up from a dispatch queue through this key. See below.
    private static let dispatchQueueKey = DispatchSpecificKey<Fuzzer>()

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

    /// Set the CodeGenerators (and their respecitve weight) to use when generating new code.
    public func setCodeGenerators(_ generators: WeightedList<CodeGenerator>) {
        guard generators.contains(where: { $0.isValueGenerator }) else {
            fatalError("Code generators must contain at least one value generator")
        }
        self.codeGenerators = generators
    }

    /// Adds a module to this fuzzer. Can only be called before the fuzzer is initialized.
    public func addModule(_ module: Module) {
        assert(!isInitialized)
        assert(modules[module.name] == nil)

        modules[module.name] = module

        // We only allow one instance of certain modules.
        assert(modules.values.filter( { $0 is DistributedFuzzingChildNode }).count <= 1)
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
        corpusGenerationEngine.initialize(with: self)

        // Finally initialize all modules.
        for module in modules.values {
            module.initialize(with: self)
        }

        // Install a watchdog to monitor the utilization of this instance.
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

        // Install a timer to monitor for faulty code generators and program templates.
        timers.scheduleTask(every: 5 * Minutes) {
            for generator in self.codeGenerators {
                if generator.totalSamples >= 100 && generator.correctnessRate < 0.05 {
                    self.logger.warning("Code generator \(generator.name) might be broken. Correctness rate is only \(generator.correctnessRate * 100)% after \(generator.totalSamples) generated samples")
                }
            }
            for template in self.programTemplates {
                if template.totalSamples >= 100 && template.correctnessRate < 0.05 {
                    self.logger.warning("Program template \(template.name) might be broken. Correctness rate is only \(template.correctnessRate * 100)% after \(template.totalSamples) generated samples")
                }
            }
        }

        // Determine our initial state if necessary.
        assert(state == .uninitialized || state == .corpusImport)
        if state == .uninitialized {
            let isChildNode = modules.values.contains(where: { $0 is DistributedFuzzingChildNode })
            if isChildNode {
                // We're a child node, so wait until we've received some kind of corpus from our parent node.
                // We'll change our state when we're synchronized with our parent, see updateStateAfterSynchronizingWithParentNode() below.
                changeState(to: .waiting)
            } else {
                // Start with corpus generation.
                assert(corpus.isEmpty)
                changeState(to: .corpusGeneration)
            }
        }

        dispatchEvent(events.Initialized)
        logger.info("Initialized")
        isInitialized = true
    }

    /// Determine the new state of this fuzzer after synchronizing with its parent node during distributed fuzzing.
    ///
    /// This method is expected to be called by child node modules during distributed fuzzing when they have connected
    /// to their parent node and synchronized this fuzzer's state with that of the parent node. This method will then
    /// determine the appropriate new state (typically .fuzzing) and dispatch the Synchronized event.
    public func updateStateAfterSynchronizingWithParentNode() {
        if state != .waiting {
            // Nothing to do
            return
        }

        if corpus.isEmpty && config.staticCorpus {
            // This is a bit unfortunate: we are synchronized with our parent, which is presumably
            // doing a corpus import, but haven't received any samples yet, so can't start fuzzing.
            // Since we'll receive corpus samples as they are imported by our parent, we simply
            // stay in the .waiting mode for some more time...
            logger.info("Waiting some more time to receive corpus samples from parent instance...")
            return timers.runAfter(15 * Seconds, updateStateAfterSynchronizingWithParentNode)
        } else if corpus.isEmpty {
            // Even after synchronizing with our parent node, we may still be left with an empty corpus.
            // This can for example happen if the parent is configured to not share its corpus with its children,
            // or because it itself still has an empty corpus. In that case, we simply do corpus generation.
            changeState(to: .corpusGeneration)
        } else {
            changeState(to: .fuzzing)
        }

        // We only dispatch the Synchronized event once, when we do the .waiting -> someOtherState transition.
        assert(state != .waiting)
        dispatchEvent(events.Synchronized)
    }

    /// Starts the fuzzer and runs for the specified number of iterations.
    ///
    /// This must be called after initializing the fuzzer.
    /// Use -1 for maxIterations to run indefinitely.
    public func start(runUntil exitCondition: ExitCondition = .none) {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(isInitialized)

        self.exitCondition = exitCondition

        logger.info("Let's go!")

        fuzzOne()
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

    /// Dispatches an event, potentially with some data attached to the event.
    public func dispatchEvent<T>(_ event: Event<T>, data: T) {
        dispatchPrecondition(condition: .onQueue(queue))
        for listener in event.listeners {
            listener(data)
        }
    }
    private func dispatchEvent(_ event: Event<Void>) {
        dispatchEvent(event, data: ())
    }

    /// Tuple containing the result of importing a program.
    public typealias ImportResult = (wasImported: Bool, executionOutcome: ExecutionOutcome)

    /// Imports a potentially interesting program into this fuzzer.
    ///
    /// When importing, the program will be treated like one that was generated by this fuzzer. As such it will
    /// be executed and evaluated to determine whether it results in previously unseen, interesting behaviour.
    /// When dropout is enabled, a configurable percentage of programs will be ignored during importing. This
    /// mechanism can help reduce the similarity of different fuzzer instances.
    @discardableResult
    public func importProgram(_ program: Program, origin: ProgramOrigin, enableDropout: Bool = false) -> ImportResult {
        dispatchPrecondition(condition: .onQueue(queue))

        if enableDropout && probability(config.dropoutRate) {
            return ImportResult(wasImported: false, executionOutcome: .succeeded)
        }

        let execution = execute(program, purpose: .programImport)

        var wasImported = false
        switch execution.outcome {
        case .crashed(let termsig):
            // Here we explicitly deal with the possibility that an interesting sample
            // from another instance triggers a crash in this instance.
            processCrash(program, withSignal: termsig, withStderr: execution.stderr, withStdout: execution.stdout, origin: origin, withExectime: execution.execTime)


        case .succeeded:
            if let aspects = evaluator.evaluate(execution) {
                wasImported = processMaybeInteresting(program, havingAspects: aspects, origin: origin)
            }

            if case .corpusImport(let mode) = origin, mode == .full, !wasImported {
                // We're performing a full corpus import, so the sample still needs to be added to our corpus even though it doesn't trigger any new behaviour.
                corpus.add(program, ProgramAspects(outcome: .succeeded))
                // We also dispatch the InterestingProgramFound event here since we technically found an interesting program, but also so that the program is forwarded to child nodes.
                dispatchEvent(events.InterestingProgramFound, data: (program, origin))
                wasImported = true
            }

        default:
            break
        }

        return ImportResult(wasImported: wasImported, executionOutcome: execution.outcome)
    }

    /// Imports a crashing program into this fuzzer.
    ///
    /// Similar to importProgram, but will make sure to generate a CrashFound event even if the crash does not reproduce.
    public func importCrash(_ program: Program, origin: ProgramOrigin) {
        dispatchPrecondition(condition: .onQueue(queue))

        let execution = execute(program, purpose: .programImport)
        if case .crashed(let termsig) = execution.outcome {
            processCrash(program, withSignal: termsig, withStderr: execution.stderr, withStdout: execution.stdout, origin: origin, withExectime: execution.execTime)
        } else {
            // Non-deterministic crash
            dispatchEvent(events.CrashFound, data: (program, behaviour: .flaky, isUnique: true, origin: origin))
        }
    }

    /// Helper function for removing calls to certain functions from a Program.
    ///
    /// This is useful for example for importing programs that contain function calls to functions that are
    /// not available in the fuzzing enviroment.
    /// Internally, this function simply replace all uses of the specified functions with calls to a dummy function.
    /// We then rely on minimization to remove the actual call instructions (or any other uses).
    ///
    /// The function names may contain the wildcard character `*`, but _only_ as last character, in which case
    /// a prefix match will be performed instead of a string comparison.
    ///
    /// TODO We could consider moving this function into a "ProgramTransformations" or similar static class if we
    /// have other program transformations that could go there as well.
    private func removeCallsTo(_ filteredFunctions: [String], from program: Program) -> Program {
        func shouldRemoveUsesOf(_ name: String) -> Bool {
            for filteredFunction in filteredFunctions {
                if filteredFunction.last == "*" {
                    if name.starts(with: filteredFunction.dropLast()) {
                        return true
                    }
                } else {
                    assert(!filteredFunction.contains("*"))
                    if name == filteredFunction {
                        return true
                    }
                }
            }
            return false
        }

        let b = makeBuilder()

        let dummy = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
        var variablesToReplaceWithDummy = VariableSet()
        b.adopting(from: program) {
            for instr in program.code {
                var removeInstruction = false
                switch instr.op.opcode {
                case .createNamedVariable(let op):
                    if op.declarationMode == .none && shouldRemoveUsesOf(op.variableName) {
                        removeInstruction = true
                        variablesToReplaceWithDummy.insert(instr.output)
                    }
                default:
                    break
                }

                if !removeInstruction {
                    let inouts = instr.inouts.map({ variablesToReplaceWithDummy.contains($0) ? dummy : b.adopt($0) })
                    let newInstr = Instruction(instr.op, inouts: inouts, flags: instr.flags)
                    b.append(newInstr)
                }
            }
        }

        let foundAnyFunctionsToRemove = !variablesToReplaceWithDummy.isEmpty
        if foundAnyFunctionsToRemove {
            return b.finalize()
        } else {
            // Just return the original program to avoid adding a dummy function when it isn't needed
            return program
        }
    }

    /// Imports and potentially modifies a  program into this fuzzer
    ///
    /// For the most part, this is similar to `importProgram`. However, if the imported program fails to execute
    /// (e.g. because it throws a runtime exception), then this function will try to "fix" the program so that it
    /// executes successfully and can be imported.
    private static let maxProgramImportFixupAttempts = 3
    public func importProgramWithFixup(_ originalProgram: Program, origin: ProgramOrigin) -> (result: ImportResult, fixupAttempts: Int) {
        var program = originalProgram
        var result = importProgram(program, origin: origin)

        // Only attempt fixup if the program failed to execute successfully. In particular, ignore timeouts and
        // crashes here, but also take into account that not all successfully executing programs will be imported.
        if !result.executionOutcome.isFailure() {
            return (result, 0)
        }
        assert(!result.wasImported)

        let b = makeBuilder()

        // First attempt at fixing the program: remove known test functions from the program which are
        // available in the unit test environment but not in the default environment.
        let filteredFunctions = [
            // Functions used in V8's test suite
            "assert*",
            "print*",
            // Functions used in Mozilla's test suite
            "startTest",
            "enterFunc",
            "exitFunc",
            "report*",
            "options*",
        ]
        program = removeCallsTo(filteredFunctions, from: program)
        result = importProgram(program, origin: origin)
        if !result.executionOutcome.isFailure() {
            return (result, 1)
        }
        assert(!result.wasImported)

        // Second attempt at fixing the program: enable guards (try-catch) for all guardable operations, then
        // remove all guards that aren't needed (because no exception is thrown).
        for instr in program.code {
            var newOp = instr.op
            if let op = instr.op as? GuardableOperation {
                newOp = GuardableOperation.enableGuard(of: op)
            }
            b.append(Instruction(newOp, inouts: instr.inouts, flags: instr.flags))
        }
        program = b.finalize()
        if let result = currentCorpusImportJob.fixupMutator.mutate(program, for: self) {
            program = result
        }
        result = importProgram(program, origin: origin)
        if !result.executionOutcome.isFailure() {
            return (result, 2)
        }
        assert(!result.wasImported)

        // Third and final attempt at fixing up the program: simply wrap the entire program in a try-catch block.
        b.buildTryCatchFinally(tryBody: {
            b.adopting(from: program) {
                for instr in program.code {
                    b.adopt(instr)
                }
            }
        }, catchBody: { _ in })
        program = b.finalize()

        result = importProgram(program, origin: origin)
        assert(Fuzzer.maxProgramImportFixupAttempts == 3)
        return (result, 3)
    }

    /// Schedules the given corpus of programs to be imported into this fuzzer.
    ///
    /// Corpus import happens asynchronously as it may take a considerable amount of time (each program
    /// needs to be executed and possibly minimized). During corpus import, the current progress can be
    /// obtained from corpusImportProgress().
    public func scheduleCorpusImport(_ corpus: [Program], importMode: CorpusImportMode, enableDropout: Bool = false) {
        dispatchPrecondition(condition: .onQueue(queue))
        // Currently we only allow corpus import when the fuzzer is still uninitialized.
        // If necessary, this can be changed, but we'd need to be able to correctly handle the .waiting -> .corpusImport state transition.
        assert(state == .uninitialized)

        guard state != .corpusImport && currentCorpusImportJob.isFinished else {
            // TODO support this
            return logger.error("Cannot currently schedule multiple corpus imports")
        }

        guard !corpus.isEmpty else {
            // Nothing to do.
            return
        }

        // In the default corpus import mode (where we only keep interesting samples), the order
        // of imported programs matters as earlier samples may cause later samples to not be
        // added to the corpus (because they no longer add any new coverage). To not create an
        // artifical bias due to the order/filenames, we shuffle the corpus here.
        let shuffledCorpus = corpus.shuffled()

        currentCorpusImportJob = CorpusImportJob(corpus: shuffledCorpus, mode: importMode)
        changeState(to: .corpusImport)
    }

    /// Computes and returns the corpus import progress as percentage.
    public func corpusImportProgress() -> Double {
        assert(state == .corpusImport)
        return currentCorpusImportJob.progress()
    }

    /// Executes a program.
    ///
    /// This will first lift the given FuzzIL program to the target language, then use the configured script runner to execute it.
    ///
    /// - Parameters:
    ///   - program: The FuzzIL program to execute.
    ///   - timeout: The timeout after which to abort execution. If nil, the default timeout of this fuzzer will be used.
    ///   - purpose: The purpose of this program execution.
    /// - Returns: An Execution structure representing the execution outcome.
    public func execute(_ program: Program, withTimeout timeout: UInt32? = nil, purpose: ExecutionPurpose) -> Execution {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(runner.isInitialized)

        let script = lifter.lift(program)

        dispatchEvent(events.PreExecute, data: (program, purpose))
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

            // If we're running in static corpus mode, we only add programs to our corpus during corpus import.
            if !config.staticCorpus || origin.isFromCorpusImport() {
                corpus.add(program, aspects)
            }
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
                program.comments.add("CRASH INFO", at: .footer)
                program.comments.add("==========", at: .footer)
                if let tag = config.tag {
                    program.comments.add("INSTANCE TAG: \(tag)", at: .footer)
                }
                program.comments.add("TERMSIG: \(termsig)", at: .footer)
                program.comments.add("STDERR:", at: .footer)
                program.comments.add(stderr.trimmingCharacters(in: .newlines), at: .footer)
                program.comments.add("STDOUT:", at: .footer)
                program.comments.add(stdout.trimmingCharacters(in: .newlines), at: .footer)
                program.comments.add("FUZZER ARGS: \(config.arguments.joined(separator: " "))", at: .footer)
                program.comments.add("TARGET ARGS: \(runner.processArguments.joined(separator: " "))", at: .footer)
                program.comments.add("CONTRIBUTORS: \(program.contributors.map({ $0.name }).joined(separator: ", "))", at: .footer)
                program.comments.add("EXECUTION TIME: \(Int(exectime * 1000))ms", at: .footer)
            }
            assert(program.comments.at(.footer)?.contains("CRASH INFO") ?? false)

            // Check for uniqueness only after minimization
            let execution = execute(program, withTimeout: self.config.timeout * 2, purpose: .checkForDeterministicBehavior)
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
    public func makeBuilder(forMutating parent: Program? = nil) -> ProgramBuilder {
        dispatchPrecondition(condition: .onQueue(queue))
        // Program ancestor chains are only constructed if inspection mode is enabled
        let parent = config.enableInspection ? parent : nil
        return ProgramBuilder(for: self, parent: parent)
    }

    /// Performs one round of fuzzing.
    private func fuzzOne() {
        dispatchPrecondition(condition: .onQueue(queue))
        assert(currentCorpusImportJob.isFinished || state == .corpusImport)

        guard !self.isStopped else { return }

        // Check if we are done fuzzing.
        switch exitCondition {
        case .none:
            break
        case .iterationsPerformed(let maxIterations):
            if iterations > maxIterations {
                return shutdown(reason: .finished)
            }
        case .timeFuzzed(let maxRuntime):
            if uptime() > maxRuntime {
                return shutdown(reason: .finished)
            }
        }

        switch state {
        case .uninitialized:
            fatalError("This state should never be observed here")

        case .waiting:
            // Nothing to do, we're waiting for our parent node to send us a corpus.
            // To avoid idle spinning, just sleep for a short while
            Thread.sleep(forTimeInterval: 5 * Seconds)

            if uptime() > 15 * Minutes {
                logger.fatal("Did not receive a corpus from our parent node within 15 minutes")
            }

        case .corpusImport:
            assert(!currentCorpusImportJob.isFinished)
            let program = currentCorpusImportJob.nextProgram()

            if currentCorpusImportJob.numberOfProgramsProcessedSoFar % 500 == 0 {
                logger.info("Corpus import progress: processed \(currentCorpusImportJob.numberOfProgramsProcessedSoFar) of \(currentCorpusImportJob.totalNumberOfProgramsToImport) programs")
            }

            let (result, fixupAttempts) = importProgramWithFixup(program, origin: .corpusImport(mode: currentCorpusImportJob.importMode))
            currentCorpusImportJob.notifyImportOutcome(result, fixupAttempts: fixupAttempts)

            if currentCorpusImportJob.isFinished {
                logger.info("Corpus import finished:")
                logger.info("\(currentCorpusImportJob.numberOfProgramsThatExecutedSuccessfullyDuringImport)/\(currentCorpusImportJob.totalNumberOfProgramsToImport) programs executed successfully")
                logger.info("    Of which \(currentCorpusImportJob.numberOfProgramsThatWereImport) programs were added to the corpus")
                logger.info("\(currentCorpusImportJob.numberOfProgramsThatNeededFixup)/\(currentCorpusImportJob.totalNumberOfProgramsToImport) programs needed fixup during import")
                logger.info("    \(currentCorpusImportJob.numberOfProgramsThatNeededOneFixupAttempt) succeeded after attempt 1")
                logger.info("    \(currentCorpusImportJob.numberOfProgramsThatNeededTwoFixupAttempts) succeeded after attempt 2")
                logger.info("    \(currentCorpusImportJob.numberOfProgramsThatNeededThreeFixupAttempts) succeeded after attempt 3")
                logger.info("\(currentCorpusImportJob.numberOfProgramsThatFailedDuringImport)/\(currentCorpusImportJob.totalNumberOfProgramsToImport) programs failed to execute (even after fixup) and weren't imported")
                logger.info("\(currentCorpusImportJob.numberOfProgramsThatTimedOutDuringImport)/\(currentCorpusImportJob.totalNumberOfProgramsToImport) programs timed out and weren't imported")

                let successRatio = Double(currentCorpusImportJob.numberOfProgramsThatExecutedSuccessfullyDuringImport) / Double(currentCorpusImportJob.totalNumberOfProgramsToImport)
                let failureRatio = 1.0 - successRatio
                if failureRatio >= 0.25 {
                    logger.warning("\(String(format: "%.2f", failureRatio * 100))% of imported programs failed to execute successfully and therefore couldn't be imported.")
                }

                dispatchEvent(events.CorpusImportComplete)
                changeState(to: .fuzzing)
            }

        case .corpusGeneration:
            // We should never perform corpus generation if we're using a static corpus.
            assert(!config.staticCorpus)

            iterations += 1
            corpusGenerationEngine.fuzzOne(fuzzGroup)

            // Perform initial corpus generation until we haven't found a new interesting sample in the last N
            // iterations. The rough order of magnitude of N has been determined experimentally: run two instances with
            // different values (e.g. 10 and 100) for roughly the same number of iterations (approximately until both
            // have finished the initial corpus generation), then compare the corpus size and coverage.
            if iterationsSinceLastInterestingProgram > 100 {
                guard !corpus.isEmpty else {
                    logger.fatal("Initial corpus generation failed, corpus is still empty. Is the evaluator working correctly?")
                }
                logger.info("Initial corpus generation finished. Corpus now contains \(corpus.size) elements")
                changeState(to: .fuzzing)
            }

        case .fuzzing:
            iterations += 1
            engine.fuzzOne(fuzzGroup)
        }

        // Perform the next iteration as soon as all tasks related to the current iteration are finished.
        fuzzGroup.notify(queue: queue) {
            self.fuzzOne()
        }
    }

    /// Constructs a non-trivial program. Useful to measure program execution speed.
    private func makeComplexProgram() -> Program {
        let b = makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 2)) { params in
            let x = b.getProperty("x", of: params[0])
            let y = b.getProperty("y", of: params[0])
            let s = b.binary(x, y, with: .Add)
            let p = b.binary(s, params[1], with: .Mul)
            b.doReturn(p)
        }

        b.buildRepeatLoop(n: 1000) { i in
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

        // Check if we can execute programs
        var execution = execute(Program(), purpose: .startup)
        guard case .succeeded = execution.outcome else {
            logger.fatal("Cannot execute programs (exit code must be zero when no exception was thrown, but execution outcome was \(execution.outcome)). Are the command line flags valid?")
        }

        // Check if we can detect failed executions (i.e. an exception was thrown)
        var b = makeBuilder()
        let exception = b.loadInt(42)
        b.throwException(exception)
        execution = execute(b.finalize(), purpose: .startup)
        guard case .failed = execution.outcome else {
            logger.fatal("Cannot detect failed executions (exit code must be nonzero when an uncaught exception was thrown, but execution outcome was \(execution.outcome))")
        }

        var maxExecutionTime: TimeInterval = 0
        // Dispatch a non-trivial program and measure its execution time
        let complexProgram = makeComplexProgram()
        for _ in 0..<5 {
            let execution = execute(complexProgram, purpose: .startup)
            maxExecutionTime = max(maxExecutionTime, execution.execTime)
        }

        // Check if the profile's startup tests pass.
        var hasAnyCrashTests = false
        for (test, expectedResult) in config.startupTests {
            b = makeBuilder()
            b.eval(test)
            execution = execute(b.finalize(), purpose: .startup)

            switch expectedResult {
            case .shouldSucceed where execution.outcome != .succeeded:
                logger.fatal("Testcase \"\(test)\" did not execute successfully")
            case .shouldCrash where !execution.outcome.isCrash():
                logger.fatal("Testcase \"\(test)\" did not crash")
            case .shouldNotCrash where execution.outcome.isCrash():
                logger.fatal("Testcase \"\(test)\" unexpectedly crashed")
            default:
                // Test passed
                break
            }

            if expectedResult == .shouldCrash {
                // In this case, also measure the execution time here to make sure that
                // we don't set our timeout too low to detect crashes.
                maxExecutionTime = max(maxExecutionTime, execution.execTime)
                hasAnyCrashTests = true
            }
        }

        if !hasAnyCrashTests {
            logger.warning("Cannot check if crashes are detected as there are no startup tests that should cause a crash")
        }

        // Determine recommended timeout value (rounded up to nearest multiple of 10ms)
        let maxExecutionTimeMs = (Int(maxExecutionTime * 1000 + 9) / 10) * 10
        let recommendedTimeout = 10 * maxExecutionTimeMs
        logger.info("Recommended timeout: at least \(recommendedTimeout)ms. Current timeout: \(config.timeout)ms")

        // Check if we can receive program output
        b = makeBuilder()
        let str = b.loadString("Hello World!")
        b.doPrint(str)
        let output = execute(b.finalize(), purpose: .startup).fuzzout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output != "Hello World!" {
            logger.warning("Cannot receive FuzzIL output (got \"\(output)\" instead of \"Hello World!\")")
        }

        logger.info("Startup tests finished successfully")
    }

    /// A pending corpus import job together with some statistics.
    private struct CorpusImportJob {
        private var corpusToImport: [Program]

        let importMode: CorpusImportMode
        let totalNumberOfProgramsToImport: Int

        // We use a fixup mutator for fixing imported programs that throw an exception.
        let fixupMutator = FixupMutator(name: "CorpusImportFixupMutator")

        private(set) var numberOfProgramsProcessedSoFar = 0
        private(set) var numberOfProgramsThatExecutedSuccessfullyDuringImport = 0
        private(set) var numberOfProgramsThatWereImport = 0
        private(set) var numberOfProgramsThatFailedDuringImport = 0
        private(set) var numberOfProgramsThatTimedOutDuringImport = 0
        private(set) var numberOfProgramsThatNeededOneFixupAttempt = 0
        private(set) var numberOfProgramsThatNeededTwoFixupAttempts = 0
        private(set) var numberOfProgramsThatNeededThreeFixupAttempts = 0

        var numberOfProgramsThatNeededFixup: Int {
            assert(Fuzzer.maxProgramImportFixupAttempts == 3)
            return numberOfProgramsThatNeededOneFixupAttempt + numberOfProgramsThatNeededTwoFixupAttempts + numberOfProgramsThatNeededThreeFixupAttempts
        }

        init(corpus: [Program], mode: CorpusImportMode) {
            self.corpusToImport = corpus.reversed()         // Programs are taken from the end.
            self.importMode = mode
            self.totalNumberOfProgramsToImport = corpus.count
        }

        var isFinished: Bool {
            return corpusToImport.isEmpty
        }

        mutating func nextProgram() -> Program {
            assert(!isFinished)
            numberOfProgramsProcessedSoFar += 1
            return corpusToImport.removeLast()
        }

        mutating func notifyImportOutcome(_ result: ImportResult, fixupAttempts: Int) {
            switch result.executionOutcome {
            case .crashed:
                assert(!result.wasImported)
                // This is unexpected so we don't track these
                break
            case .failed:
                assert(!result.wasImported)
                numberOfProgramsThatFailedDuringImport += 1
            case .succeeded:
                numberOfProgramsThatExecutedSuccessfullyDuringImport += 1
                if result.wasImported {
                    numberOfProgramsThatWereImport += 1
                }
                switch fixupAttempts {
                case 0: break
                case 1: numberOfProgramsThatNeededOneFixupAttempt += 1
                case 2: numberOfProgramsThatNeededTwoFixupAttempts += 1
                case 3: numberOfProgramsThatNeededThreeFixupAttempts += 1
                default: fatalError("Unexpected number of fixup rounds: \(fixupAttempts)")
                }
            case .timedOut:
                assert(!result.wasImported)
                numberOfProgramsThatTimedOutDuringImport += 1
            }
        }

        func progress() -> Double {
            let numberOfProgramsToImport = Double(totalNumberOfProgramsToImport)
            let numberOfProgramsAlreadyProcessed = Double(numberOfProgramsProcessedSoFar)
            return numberOfProgramsAlreadyProcessed / numberOfProgramsToImport
        }
    }
}
