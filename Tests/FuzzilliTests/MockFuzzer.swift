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
@testable import Fuzzilli

class MockScriptRunner: ScriptRunner {
    func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        return Execution(script: script,
                         pid: 1337,
                         outcome: .succeeded,
                         termsig: 0,
                         output: "",
                         execTime: 42)
    }
    
    func setEnvironmentVariable(_ key: String, to value: String) {}
    
    func initialize(with fuzzer: Fuzzer) {}
    
    var isInitialized: Bool {
        return true
    }
}

class MockEnvironment: ComponentBase, Environment {
    var interestingIntegers: [Int] = [1, 2, 3, 4]
    
    var interestingFloats: [Double] = [1.1, 2.2, 3.3]
    
    var interestingStrings: [String] = ["foo", "bar"]
    
    
    var builtins: Set<String>
    
    var methodNames = Set(["m1", "m2"])
    
    var readPropertyNames = Set(["foo", "bar"])
    
    var writePropertyNames = Set(["foo", "bar"])
    
    var customPropertyNames = Set(["foo", "bar"])
    
    
    var intType = Type.integer
    
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
}

/// Create a fuzzer instance usable for testing.
func makeMockFuzzer(runner maybeRunner: ScriptRunner? = nil, environment maybeEnvironment: Environment? = nil, evaluator maybeEvaluator: ProgramEvaluator? = nil) -> Fuzzer {
    // The configuration of this fuzzer.
    let configuration = Configuration()
    
    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = maybeRunner ?? MockScriptRunner()
    
    /// The core fuzzer responsible for mutating programs from the corpus and evaluating the outcome.
    let mutators: [Mutator] = [
        InsertionMutator(),
        OperationMutator(),
        InputMutator(),
        SpliceMutator(),
        CombineMutator(),
        JITStressMutator(),
    ]
    let core = FuzzerCore(mutators: mutators, numConsecutiveMutations: 5)
    
    // The evaluator to score produced samples.
    let evaluator = maybeEvaluator ?? MockEvaluator()
    
    // The environment containing available builtins, property names, and method names.
    let environment = maybeEnvironment ?? MockEnvironment(builtins: ["Foo": .integer, "Bar": .object(), "Baz": .function()])
    
    // A lifter to translate FuzzIL programs to JavaScript.
    let lifter = JavaScriptLifter(prefix: "", suffix: "", inliningPolicy: InlineOnlyLiterals())
    
    // Corpus managing interesting programs that have been found during fuzzing.
    let corpus = Corpus(minSize: 1000, maxSize: 2000, minMutationsPerSample: 5)
    
    // Minimizer to minimize crashes and interesting programs.
    let minimizer = Minimizer()
    
    // Construct the fuzzer instance.
    let fuzzer = Fuzzer(configuration: configuration,
                        scriptRunner: runner,
                        coreFuzzer: core,
                        codeGenerators: testCodeGenerators,
                        evaluator: evaluator,
                        environment: environment,
                        lifter: lifter,
                        corpus: corpus,
                        minimizer: minimizer,
                        queue: OperationQueue.main)
    
    fuzzer.initialize()
    return fuzzer
}

/// Code generators to use during testing.
fileprivate let testCodeGenerators = WeightedList<CodeGenerator>([
    // Base generators
    (IntegerLiteralGenerator,            1),
    (FloatLiteralGenerator,              1),
    (StringLiteralGenerator,             1),
    (BooleanLiteralGenerator,            1),
    (UndefinedValueGenerator,            1),
    (NullValueGenerator,                 1),
    (BuiltinGenerator,                   1),
    (ObjectLiteralGenerator,             1),
    (ArrayLiteralGenerator,              1),
    (ObjectLiteralWithSpreadGenerator,   1),
    (ArrayLiteralWithSpreadGenerator,    1),
    (FunctionDefinitionGenerator,        1),
    (FunctionReturnGenerator,            1),
    (PropertyRetrievalGenerator,         1),
    (PropertyAssignmentGenerator,        1),
    (PropertyRemovalGenerator,           1),
    (ElementRetrievalGenerator,          1),
    (ElementAssignmentGenerator,         1),
    (ElementRemovalGenerator,            1),
    (TypeTestGenerator,                  1),
    (InstanceOfGenerator,                1),
    (InGenerator,                        1),
    (ComputedPropertyRetrievalGenerator, 1),
    (ComputedPropertyAssignmentGenerator,1),
    (ComputedPropertyRemovalGenerator,   1),
    (FunctionCallGenerator,              1),
    (FunctionCallWithSpreadGenerator,    1),
    (MethodCallGenerator,                1),
    (ConstructorCallGenerator,           1),
    (UnaryOperationGenerator,            1),
    (BinaryOperationGenerator,           1),
    (PhiGenerator,                       1),
    (ReassignmentGenerator,              1),
    (WithStatementGenerator,             1),
    (LoadFromScopeGenerator,             1),
    (StoreToScopeGenerator,              1),
    (ComparisonGenerator,                1),
    (IfStatementGenerator,               1),
    (WhileLoopGenerator,                 1),
    (DoWhileLoopGenerator,               1),
    (ForLoopGenerator,                   1),
    (ForInLoopGenerator,                 1),
    (ForOfLoopGenerator,                 1),
    (BreakGenerator,                     1),
    (ContinueGenerator,                  1),
    (TryCatchGenerator,                  1),
    (ThrowGenerator,                     1),
    (WellKnownPropertyLoadGenerator,     1),
    (WellKnownPropertyStoreGenerator,    1),
    (TypedArrayGenerator,                1),
    (FloatArrayGenerator,                1),
    (IntArrayGenerator,                  1),
    (ObjectArrayGenerator,               1),
    (PrototypeAccessGenerator,           1),
    (PrototypeOverwriteGenerator,        1),
    (CallbackPropertyGenerator,          1),
    (PropertyAccessorGenerator,          1),
    (ProxyGenerator,                     1),
    (LengthChangeGenerator,              1),
    (ElementKindChangeGenerator,         1),
    ])
