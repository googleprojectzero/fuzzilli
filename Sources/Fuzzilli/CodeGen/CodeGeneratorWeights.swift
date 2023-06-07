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
    "ArrowFunctionGenerator":                   3,
    "GeneratorFunctionGenerator":               3,
    "AsyncFunctionGenerator":                   3,
    "AsyncArrowFunctionGenerator":              1,
    "AsyncGeneratorFunctionGenerator":          1,
    "ConstructorGenerator":                     5,
    "SubroutineReturnGenerator":                3,
    "YieldGenerator":                           2,
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
    "NamedVariableLoadGenerator":               3,
    "NamedVariableStoreGenerator":              3,
    "NamedVariableDefinitionGenerator":         3,
    "SuperMethodCallGenerator":                 20,

    // These will only be used inside class methods, and only if private properties were previously declared in that class.
    "PrivatePropertyRetrievalGenerator":        30,
    "PrivatePropertyAssignmentGenerator":       30,
    "PrivatePropertyUpdateGenerator":           15,
    "PrivateMethodCallGenerator":               20,

    // These will only be used inside class- or object literal methods.
    "SuperPropertyRetrievalGenerator":          20,
    "SuperPropertyAssignmentGenerator":         20,
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
]
