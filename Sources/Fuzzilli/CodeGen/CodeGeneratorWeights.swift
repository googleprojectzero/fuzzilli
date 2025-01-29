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

/// Default weights for the builtin code generators.
public let codeGeneratorWeights = [
    // Value generators. These are used to bootstrap code
    // generation and therefore control the types of variables
    // available at the start of code generation.
    "IntegerGenerator":                         20,
    "RegExpGenerator":                          5,
    "BigIntGenerator":                          10,
    "FloatGenerator":                           10,
    "StringGenerator":                          10,
    "BooleanGenerator":                         2,
    "UndefinedGenerator":                       1,
    "NullGenerator":                            1,
    "NamedVariableGenerator":                   10,
    "ArrayGenerator":                           10,
    "FloatArrayGenerator":                      10,
    "IntArrayGenerator":                        10,
    "TypedArrayGenerator":                      20,
    "BuiltinObjectInstanceGenerator":           10,
    "ObjectBuilderFunctionGenerator":           10,
    "ObjectConstructorGenerator":               10,
    "ClassDefinitionGenerator":                 20,
    "TrivialFunctionGenerator":                 10,

    // Regular code generators.
    "ThisGenerator":                            3,
    "ArgumentsAccessGenerator":                 3,
    "FunctionWithArgumentsAccessGenerator":     2,
    "BuiltinGenerator":                         10,
    "BuiltinOverwriteGenerator":                3,
    "LoadNewTargetGenerator":                   3,
    "DisposableVariableGenerator":              5,
    "AsyncDisposableVariableGenerator":         5,

    "ObjectLiteralGenerator":                   10,
    // The following generators determine how frequently different
    // types of fields are generated in object literals.
    "ObjectLiteralPropertyGenerator":           20,
    "ObjectLiteralElementGenerator":            5,
    "ObjectLiteralComputedPropertyGenerator":   5,
    "ObjectLiteralCopyPropertiesGenerator":     5,
    "ObjectLiteralPrototypeGenerator":          5,
    "ObjectLiteralMethodGenerator":             5,
    "ObjectLiteralComputedMethodGenerator":     3,
    "ObjectLiteralGetterGenerator":             3,
    "ObjectLiteralSetterGenerator":             3,

    // The following generators determine how frequently different
    // types of fields are generated in class definitions.
    "ClassConstructorGenerator":                10,   // Will only run if no constructor exists yet
    "ClassInstancePropertyGenerator":           5,
    "ClassInstanceElementGenerator":            5,
    "ClassInstanceComputedPropertyGenerator":   5,
    "ClassInstanceMethodGenerator":             10,
    "ClassInstanceGetterGenerator":             3,
    "ClassInstanceSetterGenerator":             3,
    "ClassStaticPropertyGenerator":             3,
    "ClassStaticElementGenerator":              3,
    "ClassStaticComputedPropertyGenerator":     3,
    "ClassStaticInitializerGenerator":          3,
    "ClassStaticMethodGenerator":               5,
    "ClassStaticGetterGenerator":               2,
    "ClassStaticSetterGenerator":               2,
    "ClassPrivateInstancePropertyGenerator":    5,
    "ClassPrivateInstanceMethodGenerator":      5,
    "ClassPrivateStaticPropertyGenerator":      5,
    "ClassPrivateStaticMethodGenerator":        5,


    "ObjectWithSpreadGenerator":                2,
    "ArrayWithSpreadGenerator":                 2,
    "TemplateStringGenerator":                  1,
    "StringNormalizeGenerator":                 1,
    "PlainFunctionGenerator":                   15,
    "StrictModeFunctionGenerator":              3,
    "ArrowFunctionGenerator":                   3,
    "GeneratorFunctionGenerator":               3,
    "AsyncFunctionGenerator":                   3,
    "AsyncArrowFunctionGenerator":              1,
    "AsyncGeneratorFunctionGenerator":          1,
    "ConstructorGenerator":                     5,
    "SubroutineReturnGenerator":                3,
    "YieldGenerator":                           5,
    "YieldEachGenerator":                       5,
    "AwaitGenerator":                           2,
    "PropertyRetrievalGenerator":               20,
    "PropertyAssignmentGenerator":              20,
    "PropertyUpdateGenerator":                  10,
    "PropertyRemovalGenerator":                 5,
    "PropertyConfigurationGenerator":           10,
    "ElementRetrievalGenerator":                20,
    "ElementAssignmentGenerator":               20,
    "ElementUpdateGenerator":                   7,
    "ElementRemovalGenerator":                  5,
    "ElementConfigurationGenerator":            10,
    "TypeTestGenerator":                        5,
    "InstanceOfGenerator":                      5,
    "InGenerator":                              3,
    "ComputedPropertyRetrievalGenerator":       20,
    "ComputedPropertyAssignmentGenerator":      20,
    "ComputedPropertyUpdateGenerator":          7,
    "ComputedPropertyRemovalGenerator":         5,
    "ComputedPropertyConfigurationGenerator":   10,
    "FunctionCallGenerator":                    30,
    "FunctionCallWithSpreadGenerator":          3,
    "ConstructorCallGenerator":                 20,
    "ConstructorCallWithSpreadGenerator":       3,
    "MethodCallGenerator":                      30,
    "MethodCallWithSpreadGenerator":            3,
    "ComputedMethodCallGenerator":              10,
    "ComputedMethodCallWithSpreadGenerator":    3,
    "UnaryOperationGenerator":                  10,
    "BinaryOperationGenerator":                 40,
    "TernaryOperationGenerator":                5,
    "ReassignmentGenerator":                    40,
    "UpdateGenerator":                          20,
    "DupGenerator":                             2,
    "DestructArrayGenerator":                   5,
    "DestructArrayAndReassignGenerator":        5,
    "DestructObjectGenerator":                  5,
    "DestructObjectAndReassignGenerator":       5,
    "WithStatementGenerator":                   3,
    "ComparisonGenerator":                      10,
    "SuperMethodCallGenerator":                 20,

    // These will only be used inside class methods, and only if private properties were previously declared in that class.
    "PrivatePropertyRetrievalGenerator":        30,
    "PrivatePropertyAssignmentGenerator":       30,
    "PrivatePropertyUpdateGenerator":           15,
    "PrivateMethodCallGenerator":               20,

    // These will only be used inside class- or object literal methods.
    "SuperPropertyRetrievalGenerator":          20,
    "SuperPropertyAssignmentGenerator":         20,
    "ComputedSuperPropertyRetrievalGenerator":  20,
    "ComputedSuperPropertyAssignmentGenerator": 20,
    "SuperPropertyUpdateGenerator":             10,

    "IfElseGenerator":                          10,
    "CompareWithIfElseGenerator":               15,
    "SwitchBlockGenerator":                     5,
    "SwitchDefaultCaseGenerator":               3,
    "SwitchCaseGenerator":                      5,
    "WhileLoopGenerator":                       15,
    "DoWhileLoopGenerator":                     15,
    "SimpleForLoopGenerator":                   10,
    "ComplexForLoopGenerator":                  10,
    "ForInLoopGenerator":                       10,
    "ForOfLoopGenerator":                       10,
    "ForOfWithDestructLoopGenerator":           3,
    "RepeatLoopGenerator":                      10,
    "SwitchCaseBreakGenerator":                 5,
    "LoopBreakGenerator":                       5,
    "ContinueGenerator":                        5,
    "TryCatchGenerator":                        5,
    "ThrowGenerator":                           1,
    "BlockStatementGenerator":                  1,

    // Special generators
    "WellKnownPropertyLoadGenerator":           5,
    "WellKnownPropertyStoreGenerator":          5,
    "PrototypeAccessGenerator":                 10,
    "PrototypeOverwriteGenerator":              10,
    "CallbackPropertyGenerator":                10,
    "MethodCallWithDifferentThisGenerator":     5,
    "WeirdClassGenerator":                      10,
    "ProxyGenerator":                           10,
    "LengthChangeGenerator":                    5,
    "ElementKindChangeGenerator":               5,
    "PromiseGenerator":                         3,
    "EvalGenerator":                            3,
    "NumberComputationGenerator":               40,
    "ImitationGenerator":                       30,
    "ResizableArrayBufferGenerator":            5,
    "GrowableSharedArrayBufferGenerator":       5,
    "FastToSlowPropertiesGenerator":            10,
    "IteratorGenerator":                        5,
    "ConstructWithDifferentNewTargetGenerator": 5,
    "ObjectHierarchyGenerator":                 10,
    "ApiConstructorCallGenerator":              15,
    "ApiMethodCallGenerator":                   15,
    "ApiFunctionCallGenerator":                 15,
    "VoidGenerator":                            1,

    // JS generators for wasm features (e.g. APIs on the WebAssembly global object).
    "WasmGlobalGenerator":                      4,
    "WasmMemoryGenerator":                      4,
    "WasmTagGenerator":                         4,
    "WasmLegacyTryCatchComplexGenerator":       5,

    //
    // Wasm generators
    //

    // This weight is important as we need to have a module for the other generators to work.
    // As they all require .wasm context.
    "WasmModuleGenerator":                      35,
    "WasmDefineMemoryGenerator":                8,
    "WasmMemoryLoadGenerator":                  10,
    "WasmMemoryStoreGenerator":                 10,
    "WasmDefineGlobalGenerator":                2,
    "WasmDefineTableGenerator":                 2,
    "WasmGlobalStoreGenerator":                 2,
    "WasmGlobalLoadGenerator":                  2,
    "WasmReassignmentGenerator":                2,
    "WasmDefineTagGenerator":                   4,

    // Primitive Value Generators
    "WasmLoadi32Generator":                     4,
    "WasmLoadi64Generator":                     4,
    "WasmLoadf32Generator":                     4,
    "WasmLoadf64Generator":                     4,
    "WasmLoadPrimitivesGenerator":              4,

    // Numerical Operations Generators
    "Wasmi32BinOpGenerator":                    5,
    "Wasmi64BinOpGenerator":                    5,
    "Wasmf32BinOpGenerator":                    5,
    "Wasmf64BinOpGenerator":                    5,

    "Wasmi32UnOpGenerator":                     5,
    "Wasmi64UnOpGenerator":                     5,
    "Wasmf32UnOpGenerator":                     5,
    "Wasmf64UnOpGenerator":                     5,

    "Wasmi32CompareOpGenerator":                5,
    "Wasmi64CompareOpGenerator":                5,
    "Wasmf32CompareOpGenerator":                5,
    "Wasmf64CompareOpGenerator":                5,
    "Wasmi32EqzGenerator":                      5,
    "Wasmi64EqzGenerator":                      5,

    // Numerical Conversion Generators
    "WasmWrapi64Toi32Generator":                5,
    "WasmTruncatef32Toi32Generator":            5,
    "WasmTruncatef64Toi32Generator":            5,
    "WasmExtendi32Toi64Generator":              5,
    "WasmTruncatef32Toi64Generator":            5,
    "WasmTruncatef64Toi64Generator":            5,
    "WasmConverti32Tof32Generator":             5,
    "WasmConverti64Tof32Generator":             5,
    "WasmDemotef64Tof32Generator":              5,
    "WasmConverti32Tof64Generator":             5,
    "WasmConverti64Tof64Generator":             5,
    "WasmPromotef32Tof64Generator":             5,
    "WasmReinterpretGenerator":                 15,
    "WasmSignExtendIntoi32Generator":           5,
    "WasmSignExtendIntoi64Generator":           7,
    "WasmTruncateSatf32Toi32Generator":         5,
    "WasmTruncateSatf64Toi32Generator":         5,
    "WasmTruncateSatf32Toi64Generator":         5,
    "WasmTruncateSatf64Toi64Generator":         5,

    // Control Flow Generators
    "WasmFunctionGenerator":                    30,
    "WasmIfElseGenerator":                      15,
    "WasmIfElseWithSignatureGenerator":         10,
    "WasmReturnGenerator":                      15,
    "WasmBlockGenerator":                       8,
    "WasmBlockWithSignatureGenerator":          8,
    "WasmLoopGenerator":                        8,
    "WasmLoopWithSignatureGenerator":           8,
    "WasmLegacyTryCatchGenerator":              8,
    "WasmLegacyTryCatchWithResultGenerator":    8,
    "WasmLegacyTryDelegateGenerator":           8,
    "WasmThrowGenerator":                       2,
    "WasmRethrowGenerator":                     10,
    "WasmBranchGenerator":                      6,
    "WasmBranchIfGenerator":                    6,
    "WasmJsCallGenerator":                      30,

    // Simd Generators
    "ConstSimd128Generator":                    5,
    "WasmSimd128IntegerUnOpGenerator":          5,
    "WasmSimd128IntegerBinOpGenerator":         5,
    "WasmSimd128FloatUnOpGenerator":            5,
    "WasmSimd128FloatBinOpGenerator":           5,
    "WasmSimd128CompareGenerator":              5,
    "WasmI64x2SplatGenerator":                  5,
    "WasmI64x2ExtractLaneGenerator":            5,
    "WasmSimdLoadGenerator":                    5,

    "WasmSelectGenerator":                      10,
]
