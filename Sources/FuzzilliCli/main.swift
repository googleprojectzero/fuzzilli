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
    --profile=name              : Select one of several preconfigured profiles. Available profiles: \(profiles.keys).
    --numIterations=n           : Run for the specified number of iterations only.
    --timeout                   : Timeout in ms after which to interrupt execution of programs (default: 250).
    --minCorpusSize=n           : Keep this many samples in the corpus at all times (default: 1024).
    --minMutationsPerSample=n   : Discard samples from the corpus only after they have been mutated at least this many times (default: 16).
    --consecutiveMutations=n    : Perform this many consecutive mutations on each sample (default: 5).
    --minimizationLimit=n       : When minimizing corpus samples, keep at least this many instructions in the program. See Minimizer.swift for an overview of this feature (default: 0).
    --storagePath=path          : Path at which to store runtime files (crashes, corpus, etc.) to.
    --exportCorpus=true/false   : Whether to export the entire corpus to disk in regular intervals (only if storage is enabled, default: false).
    --importCorpus=path         : Import an existing corpus before starting the fuzzer.
    --networkMaster=host:port   : Run as master and accept connections from workers over the network.
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

let numIterations = args.int(for: "--numIterations") ?? -1
let timeout = args.int(for: "--timeout") ?? 250
let minCorpusSize = args.int(for: "--minCorpusSize") ?? 1024
let minMutationsPerSample = args.int(for: "--minMutationsPerSample") ?? 16
let consecutiveMutations = args.int(for: "--consecutiveMutations") ?? 5
let minimizationLimit = args.uint(for: "--minimizationLimit") ?? 0
let storagePath = args["--storagePath"]
let exportCorpus = args.bool(for: "--exportCorpus") ?? false
let corpusPath = args["--importCorpus"]

var networkMasterParams: (String, UInt16)? = nil
if let val = args["--networkMaster"] {
    if let params = parseHostPort(val) {
        networkMasterParams = params
    } else {
        print("Argument --networkMaster must be of the form \"host:port\"")
    }
}

var networkWorkerParams: (String, UInt16)? = nil
if let val = args["--networkWorker"] {
    if let params = parseHostPort(val) {
        networkWorkerParams = params
    } else {
        print("Argument --networkWorker must be of the form \"host:port\"")
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
let configuration = Configuration(timeout: UInt32(timeout),
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
let corpus = Corpus(minSize: minCorpusSize, minMutationsPerSample: minMutationsPerSample)

// Minimizer to minimize crashes and interesting programs.
let minimizer = Minimizer()

// Construct the fuzzer instance.
let fuzzer = Fuzzer(id: 0,
                    queue: DispatchQueue.main,          // Run on the main queue
                    configuration: configuration,
                    scriptRunner: runner,
                    coreFuzzer: core,
                    codeGenerators: codeGenerators,
                    evaluator: evaluator,
                    environment: environment,
                    lifter: lifter,
                    corpus: corpus,
                    minimizer: minimizer)

let logger = fuzzer.makeLogger(withLabel: "Cli")

// Add optional modules.

// Always want some statistics.
fuzzer.addModule(Statistics())

// Store samples to disk if requested.
if let path = storagePath {
    fuzzer.addModule(Storage(for: fuzzer, storageDir: path, exportCorpus: exportCorpus))
}

// Synchronize over the network if requested.
if let (listenHost, listenPort) = networkMasterParams {
    fuzzer.addModule(NetworkMaster(for: fuzzer, address: listenHost, port: listenPort))
}
if let (masterHost, masterPort) = networkWorkerParams {
    fuzzer.addModule(NetworkWorker(for: fuzzer, hostname: masterHost, port: masterPort))
}

// Create a "UI".
let ui = TerminalUI(for: fuzzer)

// Check for potential misconfiguration.
if !configuration.isWorker && storagePath == nil {
    logger.warning("No filesystem storage configured, found crashes will be discarded!")
}

// Initialize the fuzzer.
fuzzer.initialize()

// Import an existing corpus if requested.
if let path = corpusPath {
    do {
        let decoder = JSONDecoder()
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let corpus = try decoder.decode([Program].self, from: data)
        fuzzer.importCorpus(corpus)
        print("Imported \(corpus.count) samples")
    } catch {
        print("Failed to import corpus")
        exit(-1)
    }
}

// And start fuzzing.
fuzzer.start(runFor: numIterations)

// Seems like we need this so the dispatch sources below work correctly?
signal(SIGINT, SIG_IGN)

// Install signal handlers on the main thread.
var signalSources: [DispatchSourceSignal] = []
signalSources.append(DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.main))
signalSources.append(DispatchSource.makeSignalSource(signal: SIGTERM, queue: DispatchQueue.main))
for source in signalSources {
    source.setEventHandler {
        fuzzer.shutdown()
        exit(0)
    }
    source.resume()
}

// Start dispatching tasks on the main queue.
RunLoop.main.run()
