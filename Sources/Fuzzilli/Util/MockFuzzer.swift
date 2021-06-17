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

// Mock implementations of fuzzer components. For testing and benchmarking

struct MockExecution: Execution {
    let outcome: ExecutionOutcome
    let stdout: String
    let stderr: String
    let fuzzout: String
    let execTime: TimeInterval
}

class MockScriptRunner: ScriptRunner {
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

class MockEnvironment: ComponentBase, Environment {
    var interestingIntegers: [Int64] = [1, 2, 3, 4]
    var interestingFloats: [Double] = [1.1, 2.2, 3.3]
    var interestingStrings: [String] = ["foo", "bar"]
    var interestingRegExps: [String] = ["foo", "bar"]
    var interestingRegExpQuantifiers: [String] = ["foo", "bar"]

    var builtins: Set<String>
    var methodNames = Set(["m1", "m2"])
    var readPropertyNames = Set(["foo", "bar"])
    var writePropertyNames = Set(["foo", "bar"])
    var customPropertyNames = Set(["foo", "bar"])
    var customMethodNames = Set(["m1", "m2"])

    var intType = Type.integer
    var bigIntType = Type.bigint
    var regExpType = Type.regexp
    var floatType = Type.float
    var booleanType = Type.boolean
    var stringType = Type.string
    var objectType = Type.object()
    var arrayType = Type.object()

    func functionType(forSignature signature: FunctionSignature) -> Type {
        return .unknown
    }

    func type(ofBuiltin builtinName: String) -> Type {
        return builtinTypes[builtinName] ?? .unknown
    }

    var constructables: [String] {
        return ["blafoo"]
    }

    func type(ofProperty propertyName: String, on baseType: Type) -> Type {
        if let groupName = baseType.group {
            if let groupProperties = propertiesByGroup[groupName] {
                if let propertyType = groupProperties[propertyName] {
                    return propertyType
                }
            }
        }
        return .unknown
    }

    func signature(ofMethod methodName: String, on baseType: Type) -> FunctionSignature {
        if let groupName = baseType.group {
            if let groupMethods = methodsByGroup[groupName] {
                if let methodSignature = groupMethods[methodName] {
                    return methodSignature
                }
            }
        }
        return FunctionSignature.forUnknownFunction
    }

    let builtinTypes: [String: Type]
    let propertiesByGroup: [String: [String: Type]]
    let methodsByGroup: [String: [String: FunctionSignature]]

    init(builtins builtinTypes: [String: Type], propertiesByGroup: [String: [String: Type]] = [:], methodsByGroup: [String: [String: FunctionSignature]] = [:]) {
        self.builtinTypes = builtinTypes
        // Builtins must not be empty for now
        self.builtins = builtinTypes.isEmpty ? Set(["Foo", "Bar"]) : Set(builtinTypes.keys)
        self.propertiesByGroup = propertiesByGroup
        self.methodsByGroup = methodsByGroup
        super.init(name: "MockEnvironment")
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

    func evaluateAndIntersect(_ program: Program, with aspects: ProgramAspects) -> ProgramAspects? {
        return nil
    }

    func resetState() {}
}

/// Create a fuzzer instance usable for testing.
public func makeMockFuzzer(engine maybeEngine: FuzzEngine? = nil, runner maybeRunner: ScriptRunner? = nil, environment maybeEnvironment: Environment? = nil,
    evaluator maybeEvaluator: ProgramEvaluator? = nil, corpus maybeCorpus: Corpus? = nil, deterministicCorpus maybeDeterministicCorpus: Bool? = false,
    minDeterminismExecs maybeMinDeterminismExecs: Int = 3, maxDeterminismExecs maybeMaxDeterminismExecs: Int = 7) -> Fuzzer {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

    // The configuration of this fuzzer.
    let configuration = Configuration(logLevel: .warning)

    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = maybeRunner ?? MockScriptRunner()

    // the mutators to use for this fuzzing engine.
    let mutators = WeightedList<Mutator>([
        (CodeGenMutator(),   1),
        (OperationMutator(), 1),
        (InputMutator(),     1),
        (CombineMutator(),   1),
        (JITStressMutator(), 1),
    ])

    let engine = maybeEngine ?? MutationEngine(numConsecutiveMutations: 5)

    // The evaluator to score produced samples.
    let evaluator = maybeEvaluator ?? MockEvaluator()

    // The environment containing available builtins, property names, and method names.
    let environment = maybeEnvironment ?? MockEnvironment(builtins: ["Foo": .integer, "Bar": .object(), "Baz": .function()])

    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: "", suffix: "", inliningPolicy: InlineOnlyLiterals(), ecmaVersion: .es6)

    // Corpus managing interesting programs that have been found during fuzzing.
    let corpus = maybeCorpus ?? BasicCorpus(minSize: 1000, maxSize: 2000, minMutationsPerSample: 5)

    // Whether or not only deterministic samples should be added to the corpus
    let deterministicCorpus = maybeDeterministicCorpus ?? false

    // Minimizer to minimize crashes and interesting programs.
    let minimizer = Minimizer()

    // Use all builtin CodeGenerators, equally weighted
    let codeGenerators = WeightedList<CodeGenerator>(CodeGenerators.map { return ($0, 1) })

    // Use all builtin ProgramTemplates, equally weighted
    let programTemplates = WeightedList<ProgramTemplate>(ProgramTemplates.map { return ($0, 1) })

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
                        deterministicCorpus: deterministicCorpus,
                        minDeterminismExecs: maybeMinDeterminismExecs,
                        maxDeterminismExecs: maybeMaxDeterminismExecs,
                        minimizer: minimizer,
                        queue: DispatchQueue.main)

    fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
        print("[\(ev.label)] \(ev.message)")
    }

    fuzzer.initialize()
    return fuzzer
}
