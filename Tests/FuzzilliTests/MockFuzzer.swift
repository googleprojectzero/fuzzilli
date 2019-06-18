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

fileprivate class MockScriptRunner: ScriptRunner {
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

fileprivate class MockEvaluator: ProgramEvaluator {
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
func makeMockFuzzer() -> Fuzzer {
    // The configuration of this fuzzer.
    let configuration = Configuration()
    
    // A script runner to execute JavaScript code in an instrumented JS engine.
    let runner = MockScriptRunner()
    
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
    let evaluator = MockEvaluator()
    
    // The environment containing available builtins, property names, and method names.
    let environment = JavaScriptEnvironment(builtins: ["Foo", "Bar", "Baz"], propertyNames: ["a", "b", "c", "d", "e"], methodNames: ["m1", "m2", "m3", "m4", "m5"])
    
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
