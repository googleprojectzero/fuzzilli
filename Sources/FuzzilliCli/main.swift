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
    --profile=name              : Select one of several preconfigured profiles.
                                  Available profiles: \(profiles.keys).
    --jobs=n                    : Total number of fuzzing jobs. This will start one master thread and n-1 worker threads. Experimental!
    --engine=name               : The fuzzing engine to use. Available engines: "mutation" (default), "hybrid", "multi".
                                  Only the mutation engine should be regarded stable at this point.
    --corpus=name               : The corpus scheduler to use. Available schedulers: "basic" (default), "markov"
    --minDeterminismExecs=n     : The minimum number of times a new sample will be executed when checking determinism (default: 3)
    --maxDeterminismExecs=n     : The maximum number of times a new sample will be executed when checking determinism (default: 50)
    --noDeterministicCorpus     : Don't ensure that samples added to the corpus behave deterministically.
    --maxResetCount=n           : The number of times a non-deterministic edge is reset before it is ignored in subsequent executions.
                                  Only used as part of --deterministicCorpus.
    --logLevel=level            : The log level to use. Valid values: "verbose", info", "warning", "error", "fatal"
                                  (default: "info").
    --numIterations=n           : Run for the specified number of iterations (default: unlimited).
    --timeout=n                 : Timeout in ms after which to interrupt execution of programs (default: 250).
    --minMutationsPerSample=n   : Discard samples from the corpus after they have been mutated at least this
                                  many times (default: 16).
    --minCorpusSize=n           : Keep at least this many samples in the corpus regardless of the number of times
                                  they have been mutated (default: 1024).
    --maxCorpusSize=n           : Only allow the corpus to grow to this many samples. Otherwise the oldest samples
                                  will be discarded (default: unlimited).
    --markovDropoutRate=n       : Rate at which low edge samples are not selected, in the Markov Corpus Scheduler,
                                  per round of sample selection. Used to ensure diversity between fuzzer instances
                                  (default: 0.10)
    --consecutiveMutations=n    : Perform this many consecutive mutations on each sample (default: 5).
    --minimizationLimit=n       : When minimizing corpus samples, keep at least this many instructions in the
                                  program. See Minimizer.swift for an overview of this feature (default: 0).
    --storagePath=path          : Path at which to store output files (crashes, corpus, etc.) to.
    --resume                    : If storage path exists, import the programs from the corpus/ subdirectory
    --overwrite                 : If storage path exists, delete all data in it and start a fresh fuzzing session
    --exportStatistics          : If enabled, fuzzing statistics will be collected and saved to disk every 10 minutes.
                                  Requires --storagePath.
    --importCorpusAll=path      : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                  All provided programs are included, even if they do not increase coverage.
                                  This is useful for searching for variants of existing bugs.
                                  Can be used alongside wtih importCorpusNewCov, and will run first
    --importCorpusNewCov=path   : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                  This only includes programs that increase coverage.
                                  This is useful for jump starting coverage for a wide range of JavaScript samples.
                                  Can be used alongside importCorpusAll, and will run second.
                                  Since all imported samples are asynchronously minimized, the corpus will show a smaller
                                  than expected size until minimization completes.
    --importCorpusMerge=path    : Imports a corpus of protobufs to start the initial fuzzing corpus.
                                  This only keeps programs that increase coverage but does not attempt to minimize
                                  the samples. This is mostly useful to merge existing corpora from previous fuzzing
                                  sessions that will have redundant samples but which will already be minimized.
    --networkMaster=host:port   : Run as master and accept connections from workers over the network. Note: it is
                                  *highly* recommended to run network fuzzers in an isolated network!
    --networkWorker=host:port   : Run as worker and connect to the specified master instance.
    --dontFuzz                  : If used, this instace will not perform fuzzing. Can be useful for master instances.
    --noAbstractInterpretation  : Disable abstract interpretation of FuzzIL programs during fuzzing. See
                                  Configuration.swift for more details.
    --collectRuntimeTypes       : Collect runtime type information for programs that are added to the corpus.
    --diagnostics               : Enable saving of programs that failed or timed-out during execution. Also tracks
                                  executions on the current REPRL instance.
    --inspect=opt1,opt2,...     : Enable inspection options. The following options are available:
                                      history: Additional .fuzzil.history files are written to disk for every program.
                                               These describe in detail how the program was generated through mutations,
                                               code generation, and minimization
                                        types: Programs written to disk also contain variable type information as
                                               determined by Fuzzilli as comments
                                          all: All of the above
""")
    exit(0)
}

let jsShellPath = args[0]

if !FileManager.default.fileExists(atPath: jsShellPath) {
    print("Invalid JS shell path \"\(jsShellPath)\", file does not exist")
    exit(-1)
}

var profile: Profile! = nil
if let val = args["--profile"], let p = profiles[val] {
    profile = p
}
if profile == nil {
    print("Please provide a valid profile with --profile=profile_name. Available profiles: \(profiles.keys)")
    exit(-1)
}

let numJobs = args.int(for: "--jobs") ?? 1
let logLevelName = args["--logLevel"] ?? "info"
let engineName = args["--engine"] ?? "mutation"
let corpusName = args["--corpus"] ?? "basic"
let minDeterminismExecs = args.int(for: "--minDeterminismExecs") ?? 3
let maxDeterminismExecs = args.int(for: "--maxDeterminismExecs") ?? 50
let noDeterministicCorpus = args.has("--noDeterministicCorpus")
let maxResetCount = args.int(for: "--maxResetCount") ?? 500
let numIterations = args.int(for: "--numIterations") ?? -1
let timeout = args.int(for: "--timeout") ?? 250
let minMutationsPerSample = args.int(for: "--minMutationsPerSample") ?? 16
let minCorpusSize = args.int(for: "--minCorpusSize") ?? 1024
let maxCorpusSize = args.int(for: "--maxCorpusSize") ?? Int.max
let markovDropoutRate = args.double(for: "--markovDropoutRate") ?? 0.10
let consecutiveMutations = args.int(for: "--consecutiveMutations") ?? 5
let minimizationLimit = args.uint(for: "--minimizationLimit") ?? 0
let storagePath = args["--storagePath"]
var resume = args.has("--resume")
let overwrite = args.has("--overwrite")
let exportStatistics = args.has("--exportStatistics")
let corpusImportAllPath = args["--importCorpusAll"]
let corpusImportCovOnlyPath = args["--importCorpusNewCov"]
let corpusImportMergePath = args["--importCorpusMerge"]
let disableAbstractInterpreter = args.has("--noAbstractInterpretation")
let dontFuzz = args.has("--dontFuzz")
let collectRuntimeTypes = args.has("--collectRuntimeTypes")
let diagnostics = args.has("--diagnostics")
let inspect = args["--inspect"]

guard numJobs >= 1 else {
    print("Must have at least 1 job")
    exit(-1)
}

let logLevelByName: [String: LogLevel] = ["verbose": .verbose, "info": .info, "warning": .warning, "error": .error, "fatal": .fatal]
guard let logLevel = logLevelByName[logLevelName] else {
    print("Invalid log level \(logLevelName)")
    exit(-1)
}

let validEngines = ["mutation", "hybrid", "multi"]
guard validEngines.contains(engineName) else {
    print("--engine must be one of \(validEngines)")
    exit(-1)
}

let validCorpora = ["basic", "markov"]
guard validCorpora.contains(corpusName) else {
    print("--corpus must be one of \(validCorpora)")
    exit(-1)
}

if corpusName != "markov" && args.double(for: "--markovDropoutRate") != nil {
    print("The markovDropoutRate setting is only compatible with the markov corpus")
    exit(-1)
}

if corpusName == "markov" && (args.int(for: "--maxCorpusSize") != nil || args.int(for: "--minCorpusSize") != nil 
    || args.int(for: "--minMutationsPerSample") != nil ) {
    print("--maxCorpusSize, --minCorpusSize, --minMutationsPerSample are not compatible with the Markov corpus")
    exit(-1)
}

if corpusName == "markov" && noDeterministicCorpus {
    print("Markov corpus requires determinism. Remove --noDeterministicCorpus")
    exit(-1)
}

if corpusImportAllPath != nil && corpusName == "markov" {
    // The markov corpus probably won't have edges associated with some samples, which will then never be mutated.
    print("Markov corpus is not compatible with --importCorpusAll")
    exit(-1)
}

if noDeterministicCorpus && (args.int(for: "--minDeterminismExecs") != nil || args.int(for: "--maxDeterminismExecs") != nil || args.int(for: "--maxResetCount") != nil) {
    print("--minDeterminismExecs, --maxDeterminismExecs, --maxResetCount are incompatible with --noDeterministicCorpus")
    exit(-1)
}

if minDeterminismExecs <= 0 || maxDeterminismExecs <= 0 || minDeterminismExecs > maxDeterminismExecs {
    print("minDeterminismExecs and maxDeterminismExecs need to be > 0 and minDeterminismExecs <= maxDeterminismExecs")
    exit(-1)
}

if maxResetCount <= maxDeterminismExecs || maxResetCount < 500 {
    print("maxResetCount should be greater than maxDeterminismExecs and decently high (at least 500)")
    print(-1)
}

if (resume || overwrite) && storagePath == nil {
    print("--resume and --overwrite require --storagePath")
    exit(-1)
}

if let path = storagePath {
    let directory = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    if !directory.isEmpty && !resume && !overwrite {
        print("Storage path \(path) exists and is not empty. Please specify either --resume or --overwrite or delete the directory manually")
        exit(-1)
    }
}

if resume && overwrite {
    print("Must only specify one of --resume and --overwrite")
    exit(-1)
}

if exportStatistics && storagePath == nil {
    print("--exportStatistics requires --storagePath")
    exit(-1)
}

if minCorpusSize < 1 {
    print("--minCorpusSize must be at least 1")
    exit(-1)
}

if maxCorpusSize < minCorpusSize {
    print("--maxCorpusSize must be larger than --minCorpusSize")
    exit(-1)
}

var networkMasterParams: (String, UInt16)? = nil
if let val = args["--networkMaster"] {
    if let params = Arguments.parseHostPort(val) {
        networkMasterParams = params
    } else {
        print("Argument --networkMaster must be of the form \"host:port\"")
        exit(-1)
    }
}

var networkWorkerParams: (String, UInt16)? = nil
if let val = args["--networkWorker"] {
    if let params = Arguments.parseHostPort(val) {
        networkWorkerParams = params
    } else {
        print("Argument --networkWorker must be of the form \"host:port\"")
        exit(-1)
    }
}

var inspectionOptions = InspectionOptions()
if let optionList = inspect {
    let options = optionList.components(separatedBy: ",")
    for option in options {
        switch option {
        case "history":
            inspectionOptions.insert(.history)
        case "types":
            inspectionOptions.insert(.types)
        case "all":
            inspectionOptions = .all
        default:
            print("Unknown inspection feature: \(option)")
            exit(-1)
        }
    }
}

// Make it easy to detect typos etc. in command line arguments
if args.unusedOptionals.count > 0 {
    print("Invalid arguments: \(args.unusedOptionals)")
    exit(-1)
}

// Forbid this configuration as runtime types collection requires the AbstractInterpreter
if disableAbstractInterpreter, collectRuntimeTypes {
    print(
        """
        It is not possible to disable abstract interpretation and enable runtime types collection at the same time.
        Remove at least one of the arguments:
        --noAbstractInterpretation
        --collectRuntimeTypes
        """
    )
    exit(-1)
}

//
// Construct a fuzzer instance.
//

func makeFuzzer(for profile: Profile, with configuration: Configuration) -> Fuzzer {
    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = REPRL(executable: jsShellPath, processArguments: profile.processArguments, processEnvironment: profile.processEnv)

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

    // Code generators to use.
    let disabledGenerators = Set(profile.disabledCodeGenerators)
    var codeGenerators = profile.additionalCodeGenerators
    for generator in CodeGenerators {
        if disabledGenerators.contains(generator.name) {
            continue
        }
        guard let weight = codeGeneratorWeights[generator.name] else {
            print("Missing weight for code generator \(generator.name) in CodeGeneratorWeights.swift")
            exit(-1)
        }

        codeGenerators.append(generator, withWeight: weight)
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
                                  inliningPolicy: InlineOnlyLiterals(),
                                  ecmaVersion: profile.ecmaVersion)

    // The evaluator to score produced samples.
    let evaluator = ProgramCoverageEvaluator(runner: runner, maxResetCount: UInt64(maxResetCount))

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
        (CodeGenMutator(),                  3),
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
                  deterministicCorpus: !noDeterministicCorpus,
                  minDeterminismExecs: minDeterminismExecs,
                  maxDeterminismExecs: maxDeterminismExecs,
                  minimizer: minimizer)
}

// The configuration of this fuzzer.
let config = Configuration(timeout: UInt32(timeout),
                           logLevel: logLevel,
                           crashTests: profile.crashTests,
                           isMaster: networkMasterParams != nil,
                           isWorker: networkWorkerParams != nil,
                           isFuzzing: !dontFuzz,
                           minimizationLimit: minimizationLimit,
                           useAbstractInterpretation: !disableAbstractInterpreter,
                           collectRuntimeTypes: collectRuntimeTypes,
                           enableDiagnostics: diagnostics,
                           inspection: inspectionOptions)

let fuzzer = makeFuzzer(for: profile, with: config)

// Create a "UI". We do this now, before fuzzer initialization, so
// we are able to print log messages generated during initialization.
let ui = TerminalUI(for: fuzzer)

let logger = Logger(withLabel: "Cli")

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
            // The corpus directory mus be empty. We already checked this above, so just assert here
            let directory = (try? FileManager.default.contentsOfDirectory(atPath: path + "/corpus")) ?? []
            assert(directory.isEmpty)
        }

        fuzzer.addModule(Storage(for: fuzzer,
                                 storageDir: path,
                                 statisticsExportInterval: exportStatistics ? 10 * Minutes : nil
        ))
    }

    // Synchronize over the network if requested.
    if let (listenHost, listenPort) = networkMasterParams {
        fuzzer.addModule(NetworkMaster(for: fuzzer, address: listenHost, port: listenPort))
    }
    if let (masterHost, masterPort) = networkWorkerParams {
        fuzzer.addModule(NetworkWorker(for: fuzzer, hostname: masterHost, port: masterPort))
    }

    // Synchronize with thread workers if requested.
    if numJobs > 1 {
        fuzzer.addModule(ThreadMaster(for: fuzzer))
    }

    // Check for potential misconfiguration.
    if !config.isWorker && storagePath == nil {
        logger.warning("No filesystem storage configured, found crashes will be discarded!")
    }

    // Exit this process when the main fuzzer stops.
    fuzzer.registerEventListener(for: fuzzer.events.ShutdownComplete) { reason in
        exit(reason.toExitCode())
    }

    // Initialize the fuzzer, and run startup tests
    fuzzer.initialize()
    fuzzer.runStartupTests()
}

// Add thread worker instances if requested
//
// This happens here, before any corpus is imported, so that any imported programs are
// forwarded to the ThreadWorkers automatically when they are deemed interesting.
//
// This must *not* happen on the main fuzzer's queue since workers perform synchronous
// operations on the master's dispatch queue.
var instances = [fuzzer]
for _ in 1..<numJobs {
    let worker = makeFuzzer(for: profile, with: config)
    instances.append(worker)
    let g = DispatchGroup()

    g.enter()
    worker.sync {
        worker.addModule(Statistics())
        worker.addModule(ThreadWorker(forMaster: fuzzer))
        worker.registerEventListener(for: worker.events.Initialized) { g.leave() }
        worker.initialize()
    }

    // Wait for the worker to be fully initialized
    g.wait()
}

// Import a corpus if requested and start the main fuzzer instance.
fuzzer.sync {
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
        logger.info("Resuming previous fuzzing session. Importing programs from corpus directory now. This may take some time")
        let corpus = loadCorpus(from: path + "/old_corpus")

        // Delete the old corpus directory now
        try? FileManager.default.removeItem(atPath: path + "/old_corpus")

        fuzzer.importCorpus(corpus, importMode: .interestingOnly(shouldMinimize: false))  // We assume that the programs are already minimized
        logger.info("Successfully resumed previous state. Corpus now contains \(fuzzer.corpus.size) elements")
    }

    // Import a full corpus if requested
    if let path = corpusImportAllPath {
        let corpus = loadCorpus(from: path)
        logger.info("Starting All-corpus import of \(corpus.count) programs. This may take some time")
        fuzzer.importCorpus(corpus, importMode: .all)
        logger.info("Successfully imported \(path). Corpus now contains \(fuzzer.corpus.size) elements")
    }

    // Import a coverage-only corpus if requested
    if let path = corpusImportCovOnlyPath {
        var corpus = loadCorpus(from: path)
        // Sorting the corpus helps avoid minimizing large programs that produce new coverage due to small snippets also included by other, smaller samples
        corpus.sort(by: { $0.size < $1.size })
        logger.info("Starting Cov-only corpus import of \(corpus.count) programs. This may take some time")
        fuzzer.importCorpus(corpus, importMode: .interestingOnly(shouldMinimize: true))
        logger.info("Successfully imported \(path). Samples will be added to the corpus once they are minimized")
    }
    
    // Import and merge an existing corpus if requested
    if let path = corpusImportMergePath {
        let corpus = loadCorpus(from: path)
        logger.info("Starting corpus merge of \(corpus.count) programs. This may take some time")
        fuzzer.importCorpus(corpus, importMode: .interestingOnly(shouldMinimize: false))
        logger.info("Successfully imported \(path). Corpus now contains \(fuzzer.corpus.size) elements")
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

#if !os(Windows)
// Install signal handler for SIGUSR1 to print the next program that is generated.
signal(SIGUSR1, SIG_IGN)
let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: DispatchQueue.main)
source.setEventHandler {
    ui.printNextGeneratedProgram = true
}
source.activate()
signalSources.append(source)
#endif

// Finally, start fuzzing.
for fuzzer in instances {
    fuzzer.sync {
        fuzzer.start(runFor: numIterations)
    }
}

// Start dispatching tasks on the main queue.
RunLoop.main.run()
