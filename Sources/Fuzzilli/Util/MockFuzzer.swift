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
    var interestingRegExps: [(pattern: String, incompatibleFlags: RegExpFlags)] = [(pattern: "foo", incompatibleFlags: .empty), (pattern: "bar", incompatibleFlags: .empty)]
    var interestingRegExpQuantifiers: [String] = ["foo", "bar"]

    var builtins: Set<String>
    var builtinProperties = Set(["foo", "bar"])
    var builtinMethods = Set(["baz", "bla"])
    var customProperties = Set(["a", "b", "c", "d"])
    var customMethods = Set(["m", "n"])

    var intType = ILType.integer
    var bigIntType = ILType.bigint
    var regExpType = ILType.regexp
    var floatType = ILType.float
    var booleanType = ILType.boolean
    var stringType = ILType.string
    var emptyObjectType = ILType.object()
    var arrayType = ILType.object(ofGroup: "Array")
    var argumentsType = ILType.object(ofGroup: "Arguments")
    var generatorType = ILType.object(ofGroup: "Generator")
    var promiseType = ILType.object(ofGroup: "Promise")

    func functionType(forSignature signature: Signature) -> ILType {
        return .anything
    }

    func hasBuiltin(_ name: String) -> Bool {
        return builtinTypes.keys.contains(name)
    }

    func hasGroup(_ name: String) -> Bool {
        return propertiesByGroup.keys.contains(name)
    }

    func type(ofBuiltin builtinName: String) -> ILType {
        return builtinTypes[builtinName] ?? .anything
    }

    func type(ofGroup groupName: String) -> ILType {
        return .anything
    }

    func getProducingMethods(ofType type: ILType) -> [(group: String, method: String)] {
        return []
    }

    func getProducingProperties(ofType type: ILType) -> [(group: String, property: String)] {
        return []
    }

    func getSubtypes(ofType type: ILType) -> [ILType] {
        return [type]
    }

    public func isSubtype(_ type: ILType, of parent: ILType) -> Bool {
        return type.Is(parent)
    }

    var constructables: [String] {
        return ["blafoo"]
    }

    func type(ofProperty propertyName: String, on baseType: ILType) -> ILType {
        if let groupName = baseType.group {
            if let groupProperties = propertiesByGroup[groupName] {
                if let propertyType = groupProperties[propertyName] {
                    return propertyType
                }
            }
        }
        return .anything
    }

    func signatures(ofMethod methodName: String, on baseType: ILType) -> [Signature] {
        if let groupName = baseType.group {
            if let groupMethods = methodsByGroup[groupName] {
                if let methodSignature = groupMethods[methodName] {
                    return [methodSignature]
                }
            }
        }
        return [.forUnknownFunction]
    }

    let builtinTypes: [String: ILType]
    let propertiesByGroup: [String: [String: ILType]]
    let methodsByGroup: [String: [String: Signature]]

    init(builtins builtinTypes: [String: ILType], propertiesByGroup: [String: [String: ILType]] = [:], methodsByGroup: [String: [String: Signature]] = [:]) {
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

    func computeAspectIntersection(of program: Program, with aspects: ProgramAspects) -> ProgramAspects? {
        return nil
    }

    func resetState() {}
}

/// Create a fuzzer instance usable for testing.
public func makeMockFuzzer(config maybeConfiguration: Configuration? = nil, engine maybeEngine: FuzzEngine? = nil, runner maybeRunner: ScriptRunner? = nil, environment maybeEnvironment: Environment? = nil, evaluator maybeEvaluator: ProgramEvaluator? = nil, corpus maybeCorpus: Corpus? = nil) -> Fuzzer {
    dispatchPrecondition(condition: .onQueue(DispatchQueue.main))

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
    let environment = maybeEnvironment ?? MockEnvironment(builtins: ["Foo": .integer, "Bar": .object(), "Baz": .function()])

    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: "", suffix: "", ecmaVersion: .es6, environment: environment)

    // Corpus managing interesting programs that have been found during fuzzing.
    let corpus = maybeCorpus ?? BasicCorpus(minSize: 1000, maxSize: 2000, minMutationsPerSample: 5)

    // Minimizer to minimize crashes and interesting programs.
    let minimizer = Minimizer()

    // Use all builtin CodeGenerators
    let codeGenerators = WeightedList<CodeGenerator>(CodeGenerators.map { return ($0, codeGeneratorWeights[$0.name]!) } + WasmCodeGenerators.map { return ($0, codeGeneratorWeights[$0.name]!) })

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
                        queue: DispatchQueue.main)

    fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
        print("[\(ev.label)] \(ev.message)")
    }

    fuzzer.initialize()

    // Tests can also rely on the corpus not being empty
    let b = fuzzer.makeBuilder()
    b.buildPrefix()
    b.build(n: 50, by: .generating)
    corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

    return fuzzer
}
