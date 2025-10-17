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

// Mock implementations of fuzzer components for testing.

struct MockExecution: Execution {
    let outcome: ExecutionOutcome
    let stdout: String
    let stderr: String
    let fuzzout: String
    let execTime: TimeInterval
}

class MockScriptRunner: ScriptRunner {
    var processArguments: [String] = []
    var env: [(String, String)] = []

    func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        return MockExecution(outcome: .succeeded,
                             stdout: "",
                             stderr: "",
                             fuzzout: "",
                             execTime: TimeInterval(0.1))
    }

    func setEnvironmentVariable(_ key: String, to value: String) {}

    func initialize(with fuzzer: Fuzzer) {}

    var isInitialized: Bool {
        return true
    }
}

class MockEvaluator: ProgramEvaluator {
    func evaluate(_ execution: Execution) -> ProgramAspects? {
        return nil
    }

    func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
        return nil
    }

    func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
        return false
    }

    var currentScore: Double {
        return 13.37
    }

    func initialize(with fuzzer: Fuzzer) {}

    var isInitialized: Bool {
        return true
    }

    func exportState() -> Data {
        return Data()
    }

    func importState(_ state: Data) {}

    func computeAspectIntersection(of program: Program, with aspects: ProgramAspects) -> ProgramAspects? {
        return nil
    }

    func resetState() {}
}

/// Create a fuzzer instance usable for testing.
public func makeMockFuzzer(config maybeConfiguration: Configuration? = nil, engine maybeEngine: FuzzEngine? = nil, runner maybeRunner: ScriptRunner? = nil, environment maybeEnvironment: JavaScriptEnvironment? = nil, evaluator maybeEvaluator: ProgramEvaluator? = nil, corpus maybeCorpus: Corpus? = nil, codeGenerators additionalCodeGenerators : [(CodeGenerator, Int)] = [], queue: DispatchQueue? = nil) -> Fuzzer {
    // The configuration of this fuzzer.
    let configuration = maybeConfiguration ?? Configuration(logLevel: .warning)

    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = maybeRunner ?? MockScriptRunner()

    // the mutators to use for this fuzzing engine.
    let mutators = WeightedList<Mutator>([
        (CodeGenMutator(),                    1),
        (OperationMutator(),                  1),
        (InputMutator(typeAwareness: .loose), 1),
        (CombineMutator(),                    1),
    ])

    let engine = maybeEngine ?? MutationEngine(numConsecutiveMutations: 5)

    // The evaluator to score produced samples.
    let evaluator = maybeEvaluator ?? MockEvaluator()

    // The environment containing available builtins, property names, and method names.
    let environment = maybeEnvironment ?? JavaScriptEnvironment()

    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: "", suffix: "", ecmaVersion: .es6, environment: environment, alwaysEmitVariables: configuration.forDifferentialFuzzing)

    // Corpus managing interesting programs that have been found during fuzzing.
    let corpus = maybeCorpus ?? BasicCorpus(minSize: 1000, maxSize: 2000, minMutationsPerSample: 5)

    // Minimizer to minimize crashes and interesting programs.
    let minimizer = Minimizer()

    // Use all builtin CodeGenerators
    let codeGenerators = WeightedList<CodeGenerator>(
        (CodeGenerators + WasmCodeGenerators).map {
            guard let weight = codeGeneratorWeights[$0.name] else {
                fatalError("Missing weight for CodeGenerator \($0.name) in CodeGeneratorWeights.swift")
            }
            return ($0, weight)
        } + additionalCodeGenerators)

    // Use all builtin ProgramTemplates
    let programTemplates = WeightedList<ProgramTemplate>(ProgramTemplates.map { return ($0, programTemplateWeights[$0.name]!) })

    // Construct the fuzzer instance.
    let fuzzer = Fuzzer(configuration: configuration,
                        scriptRunner: runner,
                        engine: engine,
                        mutators: mutators,
                        codeGenerators: codeGenerators,
                        programTemplates: programTemplates,
                        evaluator: evaluator,
                        environment: environment,
                        lifter: lifter,
                        corpus: corpus,
                        minimizer: minimizer,
                        queue: queue ?? DispatchQueue.main)

    let initializeFuzzer =  {
        fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
            print("[\(ev.label)] \(ev.message)")
        }

        fuzzer.initialize()
    }
    // If a DispatchQueue was provided by the caller, initialize the fuzzer
    // there. Otherwise initialize it directly.
    if let queue {
        queue.sync {initializeFuzzer()}
    } else {
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        initializeFuzzer()
    }

    return fuzzer
}
