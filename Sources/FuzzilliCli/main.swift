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
    --logLevel=level             : The log level to use. Valid values: "verbose", "info", "warning", "error", "fatal" (default: "info").
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
    --importCorpus=path          : Imports an existing corpus of FuzzIL programs to build the initial corpus for fuzzing.
                                   The provided path must point to a directory, and all .fzil files in that directory will be imported.
    --corpusImportMode=mode      : The corpus import mode. Possible values:
                                             default : Keep samples that are interesting (e.g. those that increase code coverage) and minimize them (default).
                                                full : Keep all samples that execute successfully without minimization.
                                         unminimized : Keep samples that are interesting but do not minimize them.

    --instanceType=type          : Specifies the instance type for distributed fuzzing over a network.
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
    --additionalArguments=args   : Pass additional arguments to the JS engine. If multiple arguments are passed, they should be separated by a comma.
    --tag=tag                    : Optional string tag associated with this instance which will be stored in the settings.json file as well as in crashing samples.
                                   This can for example be used to remember the target revision that is being fuzzed.
    --wasm                       : Enable Wasm CodeGenerators (see WasmCodeGenerators.swift).

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
var profileName: String! = nil
if let val = args["--profile"], let p = profiles[val] {
    profile = p
    profileName = val
}
if profile == nil || profileName == nil {
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
let corpusImportPath = args["--importCorpus"]
let corpusImportModeName = args["--corpusImportMode"] ?? "default"
let instanceType = args["--instanceType"] ?? "standalone"
let corpusSyncMode = args["--corpusSyncMode"] ?? "full"
let diagnostics = args.has("--diagnostics")
let inspect = args.has("--inspect")
let swarmTesting = args.has("--swarmTesting")
let argumentRandomization = args.has("--argumentRandomization")
let additionalArguments = args["--additionalArguments"] ?? ""
let tag = args["--tag"]
let enableWasm = args.has("--wasm")

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

let corpusImportModeByName: [String: CorpusImportMode] = ["default": .interestingOnly(shouldMinimize: true), "full": .full, "unminimized": .interestingOnly(shouldMinimize: false)]
guard let corpusImportMode = corpusImportModeByName[corpusImportModeName] else {
    configError("Invalid corpus import mode \(corpusImportModeName)")
}

if corpusImportPath != nil && corpusImportMode == .full && corpusName == "markov" {
    // The markov corpus probably won't have edges associated with some samples, which will then never be mutated.
    configError("Markov corpus is not compatible with the .full corpus import mode")
}

guard !resume || corpusImportPath == nil else {
    configError("Cannot resume and import an existing corpus at the same time")
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

if staticCorpus && !(resume || isNetworkChildNode || corpusImportPath != nil) {
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

let codeGeneratorsToUse = if enableWasm {
    CodeGenerators + WasmCodeGenerators
} else {
    CodeGenerators
}


let standardCodeGenerators: [(CodeGenerator, Int)] = codeGeneratorsToUse.map {
    guard let weight = codeGeneratorWeights[$0.name] else {
        logger.fatal("Missing weight for code generator \($0.name) in CodeGeneratorWeights.swift")
    }
    return ($0, weight)
}
var codeGenerators: WeightedList<CodeGenerator> = WeightedList<CodeGenerator>([])

for (generator, var weight) in (additionalCodeGenerators + standardCodeGenerators) {
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

func loadCorpus(from dirPath: String) -> [Program] {
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir) && isDir.boolValue else {
        logger.fatal("Cannot import programs from \(dirPath), it is not a directory!")
    }

    var programs = [Program]()
    let fileEnumerator = FileManager.default.enumerator(atPath: dirPath)
    while let filename = fileEnumerator?.nextObject() as? String {
        guard filename.hasSuffix(".fzil") else { continue }
        let path = dirPath + "/" + filename
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let pb = try Fuzzilli_Protobuf_Program(serializedBytes: data)
            let program = try Program.init(from: pb)
            if !program.isEmpty {
                programs.append(program)
            }
        } catch {
            logger.error("Failed to load program \(path): \(error). Skipping")
        }
    }

    return programs
}

// When using multiple jobs, all Fuzzilli instances should use the same arguments for the JS shell, even if
// argument randomization is enabled. This way, their corpora are "compatible" and crashes that require
// (a subset of) the randomly chosen flags can be reproduced on the main instance.
let jsShellArguments = profile.processArgs(argumentRandomization) + additionalArguments.split(separator: ",").map(String.init)
logger.info("Using the following arguments for the target engine: \(jsShellArguments)")

func makeFuzzer(with configuration: Configuration) -> Fuzzer {
    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = REPRL(executable: jsShellPath, processArguments: jsShellArguments, processEnvironment: profile.processEnv, maxExecsBeforeRespawn: profile.maxExecsBeforeRespawn)

    /// The mutation fuzzer responsible for mutating programs from the corpus and evaluating the outcome.
    let disabledMutators = Set(profile.disabledMutators)
    var mutators = WeightedList([
        (ExplorationMutator(),                 3),
        (CodeGenMutator(),                     2),
        (SpliceMutator(),                      2),
        (ProbingMutator(),                     2),
        (InputMutator(typeAwareness: .loose),  2),
        (InputMutator(typeAwareness: .aware),  1),
        // Can be enabled for experimental use, ConcatMutator is a limited version of CombineMutator
        // (ConcatMutator(),                   1),
        (OperationMutator(),                   1),
        (CombineMutator(),                     1),
        // Include this once it does more than just remove unneeded try-catch
        // (FixupMutator()),                   1),
    ])
    let mutatorsSet = Set(mutators.map { $0.name })
    if !disabledMutators.isSubset(of: mutatorsSet) {
        configError("The following mutators in \(profileName!) profile's disabledMutators do not exist: \(disabledMutators.subtracting(mutatorsSet)). Please check and remove them from your profile configuration.")
    }
    if !disabledMutators.isEmpty {
        mutators = mutators.filter({ !disabledMutators.contains($0.name) })
    }
    logger.info("Enabled mutators: \(mutators.map { $0.name })")
    if mutators.isEmpty {
        configError("List of enabled mutators is empty. There needs to be at least one mutator available.")
    }

    // Engines to execute programs.
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
        // We explicitly want to start with the MutationEngine since we'll probably be finding
        // lots of new samples during early fuzzing. The samples generated by the HybridEngine tend
        // to be much larger than those from the MutationEngine and will therefore take much longer
        // to minimize, making the fuzzer less efficient.
        // For the same reason, we also use a relatively larger iterationsPerEngine value, so that
        // the MutationEngine can already find most "low-hanging fruits" in its first run.
        engine = MultiEngine(engines: engines, initialActive: mutationEngine, iterationsPerEngine: 10000)
    default:
        engine = MutationEngine(numConsecutiveMutations: consecutiveMutations)
    }

    // Add a post-processor if the profile defines one.
    if let postProcessor = profile.optionalPostProcessor {
        engine.registerPostProcessor(postProcessor)
    }

    // Program templates to use.
    var programTemplates = profile.additionalProgramTemplates

    // Filter out ProgramTemplates that will use Wasm if we have not enabled it.
    if !enableWasm {
        programTemplates = programTemplates.filter {
            !($0 is WasmProgramTemplate)
        }
    }

    for template in ProgramTemplates {
        guard let weight = programTemplateWeights[template.name] else {
            print("Missing weight for program template \(template.name) in ProgramTemplateWeights.swift")
            exit(-1)
        }

        programTemplates.append(template, withWeight: weight)
    }

    // The environment containing available builtins, property names, and method names.
    let environment = JavaScriptEnvironment(additionalBuiltins: profile.additionalBuiltins, additionalObjectGroups: profile.additionalObjectGroups)
    if !profile.additionalBuiltins.isEmpty {
        logger.verbose("Loaded additional builtins from profile: \(profile.additionalBuiltins.map { $0.key })")
    }
    if !profile.additionalObjectGroups.isEmpty {
        logger.verbose("Loaded additional ObjectGroups from profile: \(profile.additionalObjectGroups.map { $0.name })")
    }

    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: profile.codePrefix,
                                  suffix: profile.codeSuffix,
                                  ecmaVersion: profile.ecmaVersion,
                                  environment: environment)

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

    // Construct the fuzzer instance.
    return Fuzzer(configuration: configuration,
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

// The configuration of the main fuzzer instance.
let mainConfig = Configuration(arguments: CommandLine.arguments,
                               timeout: UInt32(timeout),
                               logLevel: logLevel,
                               startupTests: profile.startupTests,
                               minimizationLimit: minimizationLimit,
                               enableDiagnostics: diagnostics,
                               enableInspection: inspect,
                               staticCorpus: staticCorpus,
                               tag: tag)

let fuzzer = makeFuzzer(with: mainConfig)

// Create a "UI". We do this now, before fuzzer initialization, so
// we are able to print log messages generated during initialization.
let ui = TerminalUI(for: fuzzer)

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

// Remaining fuzzer initialization must happen on the fuzzer's dispatch queue.
fuzzer.sync {
    // Always want some statistics.
    fuzzer.addModule(Statistics())

    // Exit this process when the main fuzzer stops.
    fuzzer.registerEventListener(for: fuzzer.events.ShutdownComplete) { reason in
        if resume, let path = storagePath {
            // Check if we have an old_corpus directory on disk, this can happen if the user Ctrl-C's during an import.
            if FileManager.default.fileExists(atPath: path + "/old_corpus") {
                logger.info("Corpus import aborted. The old corpus is now in \(path + "/old_corpus").")
                logger.info("You can recover the old corpus by moving it to \(path + "/corpus").")
            }
        }
        exit(reason.toExitCode())
    }

    // Store samples to disk if requested.
    if let path = storagePath {
        if resume {
            // Move the old corpus to a new directory from which the files will be imported afterwards
            // before the directory is deleted.
            if FileManager.default.fileExists(atPath: path + "/old_corpus") {
                logger.fatal("Unexpected /old_corpus directory found! Was a previous import aborted? Please check if you need to recover the old corpus manually by moving to to /corpus or deleting it.")
            }
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

    // Resume a previous fuzzing session ...
    if resume, let path = storagePath {
        var corpus = loadCorpus(from: path + "/old_corpus")
        logger.info("Scheduling import of \(corpus.count) programs from previous fuzzing run.")

        // Reverse the order of the programs, so that older programs are imported first.
        corpus.reverse()

        fuzzer.registerEventListener(for: fuzzer.events.CorpusImportComplete) {
            // Delete the old corpus directory as soon as the corpus import is complete.
            try? FileManager.default.removeItem(atPath: path + "/old_corpus")
        }

        fuzzer.scheduleCorpusImport(corpus, importMode: .interestingOnly(shouldMinimize: false))  // We assume that the programs are already minimized
    }

    // ... or import an existing corpus.
    if let path = corpusImportPath {
        assert(!resume)
        let corpus = loadCorpus(from: path)
        guard !corpus.isEmpty else {
            logger.fatal("Cannot import an empty corpus.")
        }
        logger.info("Scheduling corpus import of \(corpus.count) programs with mode \(corpusImportModeName).")
        fuzzer.scheduleCorpusImport(corpus, importMode: corpusImportMode)
    }

    // Initialize the fuzzer, and run startup tests
    fuzzer.initialize()
    fuzzer.runStartupTests()

    // Start the main fuzzing job.
    fuzzer.start(runUntil: exitCondition)
}

// Add thread worker instances if requested
// Worker instances use a slightly different configuration, mostly just a lower log level.
let workerConfig = Configuration(arguments: CommandLine.arguments,
                                 timeout: UInt32(timeout),
                                 logLevel: .warning,
                                 startupTests: profile.startupTests,
                                 minimizationLimit: minimizationLimit,
                                 enableDiagnostics: false,
                                 enableInspection: inspect,
                                 staticCorpus: staticCorpus,
                                 tag: tag)

for _ in 1..<numJobs {
    let worker = makeFuzzer(with: workerConfig)
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

// Start dispatching tasks on the main queue.
RunLoop.main.run()
