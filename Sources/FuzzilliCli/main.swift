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
import Fuzzilli

//
// Process commandline arguments.
//
let args = Arguments.parse(from: CommandLine.arguments)

if args["-h"] != nil || args["--help"] != nil || args.numPositionalArguments != 1 {
    print("""
Usage:
\(args.programName) [options] --profile=<profile> /path/to/jsshell

Options:
    --profile=name               : Select one of several preconfigured profiles.
                                   Available profiles: \(profiles.keys).
    --jobs=n                     : Total number of fuzzing jobs. This will start a main instance and n-1 worker instances.
    --engine=name                : The fuzzing engine to use. Available engines: "mutation" (default), "hybrid", "multi".
                                   Only the mutation engine should be regarded stable at this point.
    --corpus=name                : The corpus scheduler to use. Available schedulers: "basic" (default), "markov"
    --logLevel=level             : The log level to use. Valid values: "verbose", info", "warning", "error", "fatal" (default: "info").
    --maxIterations=n            : Run for the specified number of iterations (default: unlimited).
    --maxRuntimeInHours=n        : Run for the specified number of hours (default: unlimited).
    --timeout=n                  : Timeout in ms after which to interrupt execution of programs (default depends on the profile).
    --minMutationsPerSample=n    : Discard samples from the corpus only after they have been mutated at least this many times (default: 25).
    --minCorpusSize=n            : Keep at least this many samples in the corpus regardless of the number of times
                                   they have been mutated (default: 1000).
    --maxCorpusSize=n            : Only allow the corpus to grow to this many samples. Otherwise the oldest samples
                                   will be discarded (default: unlimited).
    --markovDropoutRate=p        : Rate at which low edge samples are not selected, in the Markov Corpus Scheduler,
                                   per round of sample selection. Used to ensure diversity between fuzzer instances
                                   (default: 0.10)
    --consecutiveMutations=n     : Perform this many consecutive mutations on each sample (default: 5).
    --minimizationLimit=p        : When minimizing interesting programs, keep at least this percentage of the original instructions
                                   regardless of whether they are needed to trigger the interesting behaviour or not.
                                   See Minimizer.swift for an overview of this feature (default: 0.0).
    --storagePath=path           : Path at which to store output files (crashes, corpus, etc.) to.
    --resume                     : If storage path exists, import the programs from the corpus/ subdirectory
    --overwrite                  : If storage path exists, delete all data in it and start a fresh fuzzing session
    --staticCorpus               : In this mode, we will just mutate the existing corpus and look for crashes.
                                   No new samples are added to the corpus, regardless of their coverage.
                                   This can be used to find different manifestations of bugs and
                                   also to try and reproduce a flaky crash or turn it into a deterministic one.
    --exportStatistics           : If enabled, fuzzing statistics will be collected and saved to disk in regular intervals.
                                   Requires --storagePath.
    --statisticsExportInterval=n : Interval in minutes for saving fuzzing statistics to disk (default: 10).
                                   Requires --exportStatistics.
    --importCorpusAll=path       : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                   All provided programs are included, even if they do not increase coverage.
                                   This is useful for searching for variants of existing bugs.
                                   Can be used alongside with importCorpusNewCov, and will run first
    --importCorpusNewCov=path    : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                   This only includes programs that increase coverage.
                                   This is useful for jump starting coverage for a wide range of JavaScript samples.
                                   Can be used alongside importCorpusAll, and will run second.
                                   Since all imported samples are asynchronously minimized, the corpus will show a smaller
                                   than expected size until minimization completes.
    --importCorpusMerge=path     : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                   This only keeps programs that increase coverage but does not attempt to minimize
                                   the samples. This is mostly useful to merge existing corpora from previous fuzzing
                                   sessions that will have redundant samples but which will already be minimized.
    --instanceType=type          : Specified the instance type for distributed fuzzing over a network.
                                   In distributed fuzzing, instances form a tree hierarchy, so the possible values are:
                                               root: Accept connections from other instances.
                                               leaf: Connect to a parent instance and synchronize with it.
                                       intermediate: Connect to a parent instance and synchronize with it but also accept incoming connections.
                                         standalone: Don't participate in distributed fuzzing (default).
                                   Note: it is *highly* recommended to run distributed fuzzing in an isolated network!
    --bindTo=host:port           : When running as a root or intermediate node, bind to this address (default: 127.0.0.1:1337).
    --connectTo=host:port        : When running as a leaf or intermediate node, connect to the parent instance at this address (default: 127.0.0.1:1337).
    --corpusSyncMode=mode        : How the corpus is synchronized during distributed fuzzing. Possible values:
                                                  up: newly discovered corpus samples are only sent to parent nodes but
                                                      not to chjild nodes. This way, the child nodes are forced to generate their
                                                      own corpus, which may lead to more diverse samples overall. However, parent
                                                      instances will still have the full corpus.
                                                down: newly discovered corpus samples are only sent to child nodes but not to
                                                      parent nodes. This may make sense when importing a corpus in the parent.
                                      full (default): newly discovered corpus samples are sent in both direction. This is the
                                                      default behaviour and will generally cause all instances in the network
                                                      to have very roughly the same corpus.
                                               none : corpus samples are not shared with any other instances in the network.
                                   Note: thread workers (--jobs=X) always fully synchronize their corpus.
    --diagnostics                : Enable saving of programs that failed or timed-out during execution. Also tracks
                                   executions on the current REPRL instance.
    --swarmTesting               : Enable Swarm Testing mode. The fuzzer will choose random weights for the code generators per process.
    --inspect                    : Enable inspection for generated programs. When enabled, additional .fuzzil.history files are written
                                   to disk for every interesting or crashing program. These describe in detail how the program was generated
                                   through mutations, code generation, and minimization.
    --argumentRandomization      : Enable JS engine argument randomization
""")
    exit(0)
}

// Helper function that prints out an error message, then exits the process.
func configError(_ msg: String) -> Never {
    print(msg)
    exit(-1)
}

let jsShellPath = args[0]

if !FileManager.default.fileExists(atPath: jsShellPath) {
    configError("Invalid JS shell path \"\(jsShellPath)\", file does not exist")
}

var profile: Profile! = nil
if let val = args["--profile"], let p = profiles[val] {
    profile = p
}
if profile == nil {
    configError("Please provide a valid profile with --profile=profile_name. Available profiles: \(profiles.keys)")
}

let numJobs = args.int(for: "--jobs") ?? 1
let logLevelName = args["--logLevel"] ?? "info"
let engineName = args["--engine"] ?? "mutation"
let corpusName = args["--corpus"] ?? "basic"
let maxIterations = args.int(for: "--maxIterations") ?? -1
let maxRuntimeInHours = args.int(for: "--maxRuntimeInHours") ?? -1
let timeout = args.int(for: "--timeout") ?? profile.timeout
let minMutationsPerSample = args.int(for: "--minMutationsPerSample") ?? 25
let minCorpusSize = args.int(for: "--minCorpusSize") ?? 1000
let maxCorpusSize = args.int(for: "--maxCorpusSize") ?? Int.max
let markovDropoutRate = args.double(for: "--markovDropoutRate") ?? 0.10
let consecutiveMutations = args.int(for: "--consecutiveMutations") ?? 5
let minimizationLimit = args.double(for: "--minimizationLimit") ?? 0.0
let storagePath = args["--storagePath"]
var resume = args.has("--resume")
let overwrite = args.has("--overwrite")
let staticCorpus = args.has("--staticCorpus")
let exportStatistics = args.has("--exportStatistics")
let statisticsExportInterval = args.uint(for: "--statisticsExportInterval") ?? 10
let corpusImportAllPath = args["--importCorpusAll"]
let corpusImportCovOnlyPath = args["--importCorpusNewCov"]
let corpusImportMergePath = args["--importCorpusMerge"]
let instanceType = args["--instanceType"] ?? "standalone"
let corpusSyncMode = args["--corpusSyncMode"] ?? "full"
let diagnostics = args.has("--diagnostics")
let inspect = args.has("--inspect")
let swarmTesting = args.has("--swarmTesting")
let randomizingArguments = args.has("--argumentRandomization")

guard numJobs >= 1 else {
    configError("Must have at least 1 job")
}

var exitCondition = Fuzzer.ExitCondition.none
guard maxIterations == -1 || maxRuntimeInHours == -1 else {
    configError("Must only specify one of --maxIterations and --maxRuntimeInHours")
}
if maxIterations != -1 {
    exitCondition = .iterationsPerformed(maxIterations)
} else if maxRuntimeInHours != -1 {
    exitCondition = .timeFuzzed(Double(maxRuntimeInHours) * Hours)
}

let logLevelByName: [String: LogLevel] = ["verbose": .verbose, "info": .info, "warning": .warning, "error": .error, "fatal": .fatal]
guard let logLevel = logLevelByName[logLevelName] else {
    configError("Invalid log level \(logLevelName)")
}

let validEngines = ["mutation", "hybrid", "multi"]
guard validEngines.contains(engineName) else {
    configError("--engine must be one of \(validEngines)")
}

let validCorpora = ["basic", "markov"]
guard validCorpora.contains(corpusName) else {
    configError("--corpus must be one of \(validCorpora)")
}

if corpusName != "markov" && args.double(for: "--markovDropoutRate") != nil {
    configError("The markovDropoutRate setting is only compatible with the markov corpus")
}

if markovDropoutRate < 0 || markovDropoutRate > 1 {
    print("The markovDropoutRate must be between 0 and 1")
}

if corpusName == "markov" && (args.int(for: "--maxCorpusSize") != nil || args.int(for: "--minCorpusSize") != nil
    || args.int(for: "--minMutationsPerSample") != nil ) {
    configError("--maxCorpusSize, --minCorpusSize, --minMutationsPerSample are not compatible with the Markov corpus")
}

if corpusImportAllPath != nil && corpusName == "markov" {
    // The markov corpus probably won't have edges associated with some samples, which will then never be mutated.
    configError("Markov corpus is not compatible with --importCorpusAll")
}

if (resume || overwrite) && storagePath == nil {
    configError("--resume and --overwrite require --storagePath")
}

if corpusName == "markov" && staticCorpus {
    configError("Markov corpus is not compatible with --staticCorpus")
}

if let path = storagePath {
    let directory = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    if !directory.isEmpty && !resume && !overwrite {
        configError("Storage path \(path) exists and is not empty. Please specify either --resume or --overwrite or delete the directory manually")
    }
}

if resume && overwrite {
    configError("Must only specify one of --resume and --overwrite")
}

if exportStatistics && storagePath == nil {
    configError("--exportStatistics requires --storagePath")
}

if statisticsExportInterval <= 0 {
    configError("statisticsExportInterval needs to be > 0")
}

if args.has("--statisticsExportInterval") && !exportStatistics  {
    configError("statisticsExportInterval requires --exportStatistics")
}

if minCorpusSize < 1 {
    configError("--minCorpusSize must be at least 1")
}

if maxCorpusSize < minCorpusSize {
    configError("--maxCorpusSize must be larger than --minCorpusSize")
}

if minimizationLimit < 0 || minimizationLimit > 1 {
    configError("--minimizationLimit must be between 0 and 1")
}

let validInstanceTypes = ["root", "leaf", "intermediate", "standalone"]
guard validInstanceTypes.contains(instanceType) else {
    configError("--instanceType must be one of \(validInstanceTypes)")
}
var isNetworkParentNode = instanceType == "root" || instanceType == "intermediate"
var isNetworkChildNode = instanceType == "leaf" || instanceType == "intermediate"

if args.has("--bindTo") && !isNetworkParentNode {
    configError("--bindTo is only valid for the \"root\" and \"intermediate\" instanceType")
}
if args.has("--connectTo") && !isNetworkChildNode {
    configError("--connectTo is only valid for the \"leaf\" and \"intermediate\" instanceType")
}

func parseAddress(_ argName: String) -> (String, UInt16) {
    var result: (ip: String, port: UInt16) = ("127.0.0.1", 1337)
    if let address = args[argName] {
        if let parsedAddress = Arguments.parseHostPort(address) {
            result = parsedAddress
        } else {
            configError("Argument \(argName) must be of the form \"host:port\"")
        }
    }
    return result
}

var addressToBindTo: (ip: String, port: UInt16) = parseAddress("--bindTo")
var addressToConnectTo: (ip: String, port: UInt16) = parseAddress("--connectTo")

let corpusSyncModeByName: [String: CorpusSynchronizationMode] = ["up": .up, "down": .down, "full": .full, "none": .none]
guard let corpusSyncMode = corpusSyncModeByName[corpusSyncMode] else {
    configError("Invalid corpus synchronization mode \(corpusSyncMode)")
}

if staticCorpus && !(resume || isNetworkChildNode || corpusImportAllPath != nil || corpusImportCovOnlyPath != nil || corpusImportMergePath != nil) {
    configError("Static corpus requires this instance to import a corpus or to participate in distributed fuzzing as a child node")
}

// Make it easy to detect typos etc. in command line arguments
if args.unusedOptionals.count > 0 {
    configError("Invalid arguments: \(args.unusedOptionals)")
}

// Initialize the logger such that we can print to the screen.
let logger = Logger(withLabel: "Cli")

///
/// Chose the code generator weights.
///

if swarmTesting {
    logger.info("Choosing the following weights for Swarm Testing mode.")
    logger.info("Weight | CodeGenerator")
}

let disabledGenerators = Set(profile.disabledCodeGenerators)
let additionalCodeGenerators = profile.additionalCodeGenerators
let regularCodeGenerators: [(CodeGenerator, Int)] = CodeGenerators.map {
    guard let weight = codeGeneratorWeights[$0.name] else {
        logger.fatal("Missing weight for code generator \($0.name) in CodeGeneratorWeights.swift")
    }
    return ($0, weight)
}
var codeGenerators: WeightedList<CodeGenerator> = WeightedList<CodeGenerator>([])

for (generator, var weight) in (additionalCodeGenerators + regularCodeGenerators) {
    if disabledGenerators.contains(generator.name) {
        continue
    }

    if swarmTesting {
        weight = Int.random(in: 1...30)
        logger.info(String(format: "%6d | \(generator.name)", weight))
    }

    codeGenerators.append(generator, withWeight: weight)
}

//
// Construct a fuzzer instance.
//

func makeFuzzer(for profile: Profile, with configuration: Configuration) -> Fuzzer {
    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = REPRL(executable: jsShellPath, processArguments: profile.getProcessArguments(randomizingArguments), processEnvironment: profile.processEnv, maxExecsBeforeRespawn: profile.maxExecsBeforeRespawn)

    let engine: FuzzEngine
    switch engineName {
    case "hybrid":
        engine = HybridEngine(numConsecutiveMutations: consecutiveMutations)
    case "multi":
        let mutationEngine = MutationEngine(numConsecutiveMutations: consecutiveMutations)
        let hybridEngine = HybridEngine(numConsecutiveMutations: consecutiveMutations)
        let engines = WeightedList<FuzzEngine>([
            (mutationEngine, 1),
            (hybridEngine, 1),
        ])
        engine = MultiEngine(engines: engines, initialActive: hybridEngine, iterationsPerEngine: 1000)
    default:
        engine = MutationEngine(numConsecutiveMutations: consecutiveMutations)
    }

    // Program templates to use.
    var programTemplates = profile.additionalProgramTemplates
    for template in ProgramTemplates {
        guard let weight = programTemplateWeights[template.name] else {
            print("Missing weight for program template \(template.name) in ProgramTemplateWeights.swift")
            exit(-1)
        }

        programTemplates.append(template, withWeight: weight)
    }

    // The environment containing available builtins, property names, and method names.
    let environment = JavaScriptEnvironment(additionalBuiltins: profile.additionalBuiltins, additionalObjectGroups: [])

    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: profile.codePrefix,
                                  suffix: profile.codeSuffix,
                                  ecmaVersion: profile.ecmaVersion)

    // The evaluator to score produced samples.
    let evaluator = ProgramCoverageEvaluator(runner: runner)

    // Corpus managing interesting programs that have been found during fuzzing.
    let corpus: Corpus
    switch corpusName {
    case "basic":
        corpus = BasicCorpus(minSize: minCorpusSize, maxSize: maxCorpusSize, minMutationsPerSample: minMutationsPerSample)
    case "markov":
        corpus = MarkovCorpus(covEvaluator: evaluator as ProgramCoverageEvaluator, dropoutRate: markovDropoutRate)
    default:
        logger.fatal("Invalid corpus name provided")
    }

    // Minimizer to minimize crashes and interesting programs.
    let minimizer = Minimizer()

    /// The mutation fuzzer responsible for mutating programs from the corpus and evaluating the outcome.
    let mutators = WeightedList([
        (ExplorationMutator(),              3),
        (CodeGenMutator(),                  2),
        (SpliceMutator(),                   2),
        (ProbingMutator(),                  2),
        (InputMutator(isTypeAware: false),  2),
        (InputMutator(isTypeAware: true),   1),
        // Can be enabled for experimental use, ConcatMutator is a limited version of CombineMutator
        // (ConcatMutator(),                1),
        (OperationMutator(),                1),
        (CombineMutator(),                  1),
        (JITStressMutator(),                1),
    ])

    // Construct the fuzzer instance.
    return Fuzzer(configuration: config,
                  scriptRunner: runner,
                  engine: engine,
                  mutators: mutators,
                  codeGenerators: codeGenerators,
                  programTemplates: programTemplates,
                  evaluator: evaluator,
                  environment: environment,
                  lifter: lifter,
                  corpus: corpus,
                  minimizer: minimizer)
}

// The configuration of this fuzzer.
let config = Configuration(timeout: UInt32(timeout),
                           logLevel: logLevel,
                           crashTests: profile.crashTests,
                           minimizationLimit: minimizationLimit,
                           enableDiagnostics: diagnostics,
                           enableInspection: inspect,
                           staticCorpus: staticCorpus)

let fuzzer = makeFuzzer(for: profile, with: config)

// Create a "UI". We do this now, before fuzzer initialization, so
// we are able to print log messages generated during initialization.
let ui = TerminalUI(for: fuzzer)

// Remaining fuzzer initialization must happen on the fuzzer's dispatch queue.
fuzzer.sync {
    // Always want some statistics.
    fuzzer.addModule(Statistics())

    // Check core file generation on linux, prior to moving corpus file directories
    fuzzer.checkCoreFileGeneration()

    // Store samples to disk if requested.
    if let path = storagePath {
        if resume {
            // Move the old corpus to a new directory from which the files will be imported afterwards
            // before the directory is deleted.
            do {
                try FileManager.default.moveItem(atPath: path + "/corpus", toPath: path + "/old_corpus")
            } catch {
                logger.info("Nothing to resume from: \(path)/corpus does not exist")
                resume = false
            }
        } else if overwrite {
            logger.info("Deleting all files in \(path) due to --overwrite")
            try? FileManager.default.removeItem(atPath: path)
        } else {
            // The corpus directory must be empty. We already checked this above, so just assert here
            let directory = (try? FileManager.default.contentsOfDirectory(atPath: path + "/corpus")) ?? []
            assert(directory.isEmpty)
        }

        fuzzer.addModule(Storage(for: fuzzer,
                                 storageDir: path,
                                 statisticsExportInterval: exportStatistics ? Double(statisticsExportInterval) * Minutes : nil
        ))
    }

    // Synchronize over the network if requested.
    if isNetworkParentNode {
        fuzzer.addModule(NetworkParent(for: fuzzer, address: addressToBindTo.ip, port: addressToBindTo.port, corpusSynchronizationMode: corpusSyncMode))
    }
    if isNetworkChildNode {
        fuzzer.addModule(NetworkChild(for: fuzzer, hostname: addressToConnectTo.ip, port: addressToConnectTo.port, corpusSynchronizationMode: corpusSyncMode))
    }

    // Synchronize with thread workers if requested.
    if numJobs > 1 {
        fuzzer.addModule(ThreadParent(for: fuzzer))
    }

    // Check for potential misconfiguration.
    if !isNetworkChildNode && storagePath == nil {
        logger.warning("No filesystem storage configured, found crashes will be discarded!")
    }

    // Exit this process when the main fuzzer stops.
    fuzzer.registerEventListener(for: fuzzer.events.ShutdownComplete) { reason in
        exit(reason.toExitCode())
    }

    // Schedule a corpus import if requested.
    func loadCorpus(from dirPath: String) -> [Program] {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dirPath, isDirectory:&isDir) || !isDir.boolValue {
            logger.fatal("Cannot import programs from \(dirPath), it is not a directory!")
        }

        var programs = [Program]()
        let fileEnumerator = FileManager.default.enumerator(atPath: dirPath)
        while let filename = fileEnumerator?.nextObject() as? String {
            guard filename.hasSuffix(".fuzzil.protobuf") else { continue }
            let path = dirPath + "/" + filename
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let pb = try Fuzzilli_Protobuf_Program(serializedData: data)
                let program = try Program.init(from: pb)
                programs.append(program)
            } catch {
                logger.error("Failed to load program \(path): \(error). Skipping")
            }
        }

        return programs
    }

    // Resume a previous fuzzing session if requested
    if resume, let path = storagePath {
        logger.info("Resuming previous fuzzing session. Importing programs from corpus directory now. This may take some time...")
        var corpus = loadCorpus(from: path + "/old_corpus")

        // Reverse the order of the programs, so that older programs are imported first.
        corpus.reverse()

        // Delete the old corpus directory now
        try? FileManager.default.removeItem(atPath: path + "/old_corpus")

        fuzzer.scheduleCorpusImport(corpus, importMode: .interestingOnly(shouldMinimize: false))  // We assume that the programs are already minimized
    }

    // Import a full corpus if requested
    if let path = corpusImportAllPath {
        let corpus = loadCorpus(from: path)
        logger.info("Starting All-corpus import of \(corpus.count) programs. This may take some time...")
        fuzzer.scheduleCorpusImport(corpus, importMode: .all)
    }

    // Import a coverage-only corpus if requested
    if let path = corpusImportCovOnlyPath {
        var corpus = loadCorpus(from: path)
        // Sorting the corpus helps avoid minimizing large programs that produce new coverage due to small snippets also included by other, smaller samples
        corpus.sort(by: { $0.size < $1.size })
        logger.info("Starting Cov-only corpus import of \(corpus.count) programs. This may take some time...")
        fuzzer.scheduleCorpusImport(corpus, importMode: .interestingOnly(shouldMinimize: true))
    }

    // Import and merge an existing corpus if requested
    if let path = corpusImportMergePath {
        let corpus = loadCorpus(from: path)
        logger.info("Starting corpus merge of \(corpus.count) programs. This may take some time...")
        fuzzer.scheduleCorpusImport(corpus, importMode: .interestingOnly(shouldMinimize: false))
    }

    // Initialize the fuzzer, and run startup tests
    fuzzer.initialize()
    fuzzer.runStartupTests()

    // Start the main fuzzing job.
    fuzzer.start(runUntil: exitCondition)
}

// Add thread worker instances if requested
for _ in 1..<numJobs {
    let worker = makeFuzzer(for: profile, with: config)
    worker.async {
        // Wait some time between starting workers to reduce the load on the main instance.
        // If we start the workers right away, they will all very quickly find new coverage
        // and send lots of (probably redundant) programs to the main instance.
        let minDelay = 1 * Minutes
        let maxDelay = 10 * Minutes
        let delay = Double.random(in: minDelay...maxDelay)
        Thread.sleep(forTimeInterval: delay)

        worker.addModule(Statistics())
        worker.addModule(ThreadChild(for: worker, parent: fuzzer))
        worker.initialize()
        worker.start()
    }
}

// Install signal handlers to terminate the fuzzer gracefully.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    // Seems like we need this so the dispatch sources work correctly?
    signal(sig, SIG_IGN)

    let source = DispatchSource.makeSignalSource(signal: sig, queue: DispatchQueue.main)
    source.setEventHandler {
        fuzzer.async {
            fuzzer.shutdown(reason: .userInitiated)
        }
    }
    source.activate()
    signalSources.append(source)
}

// Start dispatching tasks on the main queue.
RunLoop.main.run()
