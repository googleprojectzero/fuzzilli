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
    --consecutiveMutations=n    : Perform this many consecutive mutations on each sample (default: 5).
    --minimizationLimit=n       : When minimizing corpus samples, keep at least this many instructions in the
                                  program. See Minimizer.swift for an overview of this feature (default: 0).
    --storagePath=path          : Path at which to store runtime files (crashes, corpus, etc.) to.
    --exportState               : If enabled, the internal state of the fuzzer will be writen to disk every
                                  6 hours. Requires --storagePath.
    --importState=path          : Import a previously exported fuzzer state and resuming fuzzing from it.
    --networkMaster=host:port   : Run as master and accept connections from workers over the network. Note: it is
                                  *highly* recommended to run network fuzzers in an isolated network!
    --networkWorker=host:port   : Run as worker and connect to the specified master instance.
""")
    exit(0)
}

let jsShellPath = args[0]

var profile: Profile! = nil
if let val = args["--profile"], let p = profiles[val] {
    profile = p
}
if profile == nil {
    print("Please provide a valid profile with --profile=profile_name. Available profiles: \(profiles.keys)")
    exit(-1)
}

let logLevelName = args["--logLevel"] ?? "info"
let numIterations = args.int(for: "--numIterations") ?? -1
let timeout = args.int(for: "--timeout") ?? 250
let minMutationsPerSample = args.int(for: "--minMutationsPerSample") ?? 16
let minCorpusSize = args.int(for: "--minCorpusSize") ?? 1024
let maxCorpusSize = args.int(for: "--maxCorpusSize") ?? Int.max
let consecutiveMutations = args.int(for: "--consecutiveMutations") ?? 5
let minimizationLimit = args.uint(for: "--minimizationLimit") ?? 0
let storagePath = args["--storagePath"]
let exportState = args.has("--exportState")
let stateImportFile = args["--importState"]

let logLevelByName: [String: LogLevel] = ["verbose": .verbose, "info": .info, "warning": .warning, "error": .error, "fatal": .fatal]
guard let logLevel = logLevelByName[logLevelName] else {
    print("Invalid log level \(logLevelName)")
    exit(-1)
}

if exportState && storagePath == nil {
    print("--exportState requires --storagePath")
    exit(-1)
}

if maxCorpusSize < minCorpusSize {
    print("--maxCorpusSize must be larger than --minCorpusSize")
    exit(-1)
}

var networkMasterParams: (String, UInt16)? = nil
if let val = args["--networkMaster"] {
    if let params = parseHostPort(val) {
        networkMasterParams = params
    } else {
        print("Argument --networkMaster must be of the form \"host:port\"")
        exit(-1)
    }
}

var networkWorkerParams: (String, UInt16)? = nil
if let val = args["--networkWorker"] {
    if let params = parseHostPort(val) {
        networkWorkerParams = params
    } else {
        print("Argument --networkWorker must be of the form \"host:port\"")
        exit(-1)
    }
}

// Make it easy to detect typos etc. in command line arguments
if args.unusedOptionals.count > 0 {
    print("Invalid arguments: \(args.unusedOptionals)")
    exit(-1)
}

//
// Construct a fuzzer instance.
//

// The configuration of this fuzzer.
let config = Configuration(timeout: UInt32(timeout),
                           logLevel: logLevel,
                           crashTests: profile.crashTests,
                           isMaster: networkMasterParams != nil,
                           isWorker: networkWorkerParams != nil,
                           minimizationLimit: minimizationLimit)

// A script runner to execute JavaScript code in an instrumented JS engine.
let runner = REPRL(executable: jsShellPath, processArguments: profile.processArguments, processEnvironment: profile.processEnv)

/// The core fuzzer responsible for mutating programs from the corpus and evaluating the outcome.
let mutators: [Mutator] = [
    // Increase probability of insertion mutator as it tends to produce invalid samples more frequently.
    InsertionMutator(),
    InsertionMutator(),
    InsertionMutator(),
    
    OperationMutator(),
    InputMutator(),
    SpliceMutator(),
    CombineMutator(),
    JITStressMutator(),
]
let core = FuzzerCore(mutators: mutators, numConsecutiveMutations: consecutiveMutations)

// Code generators to use.
let codeGenerators = defaultCodeGenerators + profile.additionalCodeGenerators

// The evaluator to score produced samples.
let evaluator = ProgramCoverageEvaluator(runner: runner)

// The environment containing available builtins, property names, and method names.
let environment = JavaScriptEnvironment(builtins: profile.builtins, propertyNames: profile.propertyNames, methodNames: profile.methodNames)

// A lifter to translate FuzzIL programs to JavaScript.
let lifter = JavaScriptLifter(prefix: profile.codePrefix, suffix: profile.codeSuffix, inliningPolicy: InlineOnlyLiterals())

// Corpus managing interesting programs that have been found during fuzzing.
let corpus = Corpus(minSize: minCorpusSize, maxSize: maxCorpusSize, minMutationsPerSample: minMutationsPerSample)

// Minimizer to minimize crashes and interesting programs.
let minimizer = Minimizer()

// Construct the fuzzer instance.
let fuzzer = Fuzzer(configuration: config,
                    scriptRunner: runner,
                    coreFuzzer: core,
                    codeGenerators: codeGenerators,
                    evaluator: evaluator,
                    environment: environment,
                    lifter: lifter,
                    corpus: corpus,
                    minimizer: minimizer)

// Create a "UI". We do this now, before fuzzer initialization, so
// we are able to print log messages generated during initialization.
let ui = TerminalUI(for: fuzzer)

// Remaining fuzzer initialization must happen on the fuzzer's task queue.
fuzzer.queue.addOperation {
    let logger = fuzzer.makeLogger(withLabel: "Cli")

    // Always want some statistics.
    fuzzer.addModule(Statistics())

    // Store samples to disk if requested.
    if let path = storagePath {
        let stateExportInterval = exportState ? 6 * Hours : nil
        fuzzer.addModule(Storage(for: fuzzer, storageDir: path, stateExportInterval: stateExportInterval))
    }

    // Synchronize over the network if requested.
    if let (listenHost, listenPort) = networkMasterParams {
        fuzzer.addModule(NetworkMaster(for: fuzzer, address: listenHost, port: listenPort))
    }
    if let (masterHost, masterPort) = networkWorkerParams {
        fuzzer.addModule(NetworkWorker(for: fuzzer, hostname: masterHost, port: masterPort))
    }

    // Check for potential misconfiguration.
    if !config.isWorker && storagePath == nil {
        logger.warning("No filesystem storage configured, found crashes will be discarded!")
    }

    // Initialize the fuzzer.
    fuzzer.initialize()

    // Import a previously exported state if requested.
    if let path = stateImportFile {
        do {
            let decoder = JSONDecoder()
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let state = try decoder.decode(Fuzzer.State.self, from: data)
            try fuzzer.importState(state)
            logger.info("Successfully imported previous state. Corpus now contains \(fuzzer.corpus.size) elements")
        } catch {
            logger.fatal("Failed to import state: \(error.localizedDescription)")
        }
    }

    // And start fuzzing.
    fuzzer.start(runFor: numIterations)
    
    // Exit this process when the fuzzer stops.
    fuzzer.events.ShutdownComplete.observe {
        exit(0)
    }
}

// Install signal handlers to terminate the fuzzer gracefully.
var signalSources: [OperationSource] = []
for sig in [SIGINT, SIGTERM] {
    // Seems like we need this so the dispatch sources work correctly?
    signal(sig, SIG_IGN)
    
    signalSources.append(OperationSource.forReceivingSignal(sig, on: fuzzer.queue) {
        fuzzer.stop()
    })
}

// Start dispatching tasks on the main queue.
RunLoop.main.run()
