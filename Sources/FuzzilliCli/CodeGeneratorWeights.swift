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

import Fuzzilli

/// Assigned weights for the builtin code generators.
let codeGeneratorWeights = [
    // Base generators
    "IntegerGenerator":                     2,
    "RegExpGenerator":                      1,
    "BigIntGenerator":                      2,
    "FloatGenerator":                       1,
    "StringGenerator":                      1,
    "BooleanGenerator":                     1,
    "UndefinedGenerator":                   1,
    "NullGenerator":                        1,
    "BuiltinGenerator":                     5,
    "ObjectGenerator":                      10,
    "ArrayGenerator":                       10,
    "ObjectWithSpreadGenerator":            5,
    "ArrayWithSpreadGenerator":             5,
    "PlainFunctionGenerator":               15,
    "StrictFunctionGenerator":              1,
    "ArrowFunctionGenerator":               3,
    "GeneratorFunctionGenerator":           3,
    "AsyncFunctionGenerator":               3,
    "AsyncArrowFunctionGenerator":          1,
    "AsyncGeneratorFunctionGenerator":      1,
    "FunctionReturnGenerator":              3,
    "YieldGenerator":                       2,
    "AwaitGenerator":                       2,
    "PropertyRetrievalGenerator":           20,
    "PropertyAssignmentGenerator":          40,
    "PropertyRemovalGenerator":             5,
    "ElementRetrievalGenerator":            20,
    "ElementAssignmentGenerator":           20,
    "ElementRemovalGenerator":              5,
    "TypeTestGenerator":                    5,
    "InstanceOfGenerator":                  5,
    "InGenerator":                          3,
    "ComputedPropertyRetrievalGenerator":   20,
    "ComputedPropertyAssignmentGenerator":  20,
    "ComputedPropertyRemovalGenerator":     5,
    "FunctionCallGenerator":                30,
    "FunctionCallWithSpreadGenerator":      10,
    "MethodCallGenerator":                  40,
    "ConstructorCallGenerator":             25,
    "UnaryOperationGenerator":              25,
    "BinaryOperationGenerator":             40,
    "DupGenerator":                         2,
    "ReassignmentGenerator":                25,
    "WithStatementGenerator":               5,
    "LoadFromScopeGenerator":               4,
    "StoreToScopeGenerator":                4,
    "ComparisonGenerator":                  10,
    "ClassGenerator":                       20,
    "SuperMethodCallGenerator":             20,
    "SuperPropertyOperationGenerator":      10,
    "IfElseGenerator":                      25,
    "WhileLoopGenerator":                   20,
    "DoWhileLoopGenerator":                 20,
    "ForLoopGenerator":                     20,
    "ForInLoopGenerator":                   10,
    "ForOfLoopGenerator":                   10,
    "BreakGenerator":                       5,
    "ContinueGenerator":                    5,
    "TryCatchGenerator":                    5,
    "ThrowGenerator":                       1,
    "BlockStatementGenerator":              1,
    
    // Special generators
    "WellKnownPropertyLoadGenerator":       5,
    "WellKnownPropertyStoreGenerator":      5,
    "TypedArrayGenerator":                  10,
    "FloatArrayGenerator":                  5,
    "IntArrayGenerator":                    5,
    "ObjectArrayGenerator":                 5,
    "PrototypeAccessGenerator":             15,
    "PrototypeOverwriteGenerator":          15,
    "CallbackPropertyGenerator":            15,
    "PropertyAccessorGenerator":            15,
    "MethodCallWithDifferentThisGenerator": 5,
    "ProxyGenerator":                       15,
    "LengthChangeGenerator":                5,
    "ElementKindChangeGenerator":           5,
    "PromiseGenerator":                     3,
    "EvalGenerator":                        3,
]
