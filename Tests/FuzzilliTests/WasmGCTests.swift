// Copyright 2026 Google LLC
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

import Testing

@testable import Fuzzilli

@Suite(.enabled { JavaScriptExecutor() != nil })
struct WasmGCTests {
    @Test func testArray() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroup = b.wasmDefineTypeGroup {
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                let arrayOfArrays = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: false), mutability: true,
                    indexType: arrayi32)
                return [arrayi32, arrayOfArrays]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let array = function.wasmArrayNewFixed(
                        arrayType: typeGroup[0],
                        elements: [
                            function.consti32(42),
                            function.consti32(43),
                            function.consti32(44),
                        ])
                    let arrayOfArrays = function.wasmArrayNewFixed(
                        arrayType: typeGroup[1], elements: [array])
                    let innerArray = function.wasmArrayGet(
                        array: arrayOfArrays, index: function.consti32(0))
                    function.wasmArraySet(
                        array: innerArray, index: function.consti32(1),
                        element: function.consti32(100))
                    return [function.wasmArrayGet(array: innerArray, index: function.consti32(1))]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "100\n")
    }

    @Test func testArrayPacked() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroup = b.wasmDefineTypeGroup {
                let arrayi8 = b.wasmDefineArrayType(elementType: .wasmPackedI8, mutability: true)
                let arrayi16 = b.wasmDefineArrayType(elementType: .wasmPackedI16, mutability: true)
                return [arrayi8, arrayi16]
            }

            let module = b.buildWasmModule { wasmModule in
                for type in typeGroup {
                    wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32, .wasmi32]) {
                        function, label, args in
                        let array = function.wasmArrayNewFixed(
                            arrayType: type,
                            elements: [
                                function.consti32(-100),
                                function.consti32(0),
                            ])
                        function.wasmArraySet(
                            array: array, index: function.consti32(1),
                            element: function.consti32(42))
                        return [
                            function.wasmArrayGet(
                                array: array, index: function.consti32(0), isSigned: true),
                            function.wasmArrayGet(
                                array: array, index: function.consti32(0), isSigned: false),
                            function.wasmArrayGet(
                                array: array, index: function.consti32(1), isSigned: true),
                        ]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            var wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
            wasmOut = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "-100,156,42\n-100,65436,42\n")
    }

    @Test func testArrayNewDefault() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroup = b.wasmDefineTypeGroup {
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                let arrayf64 = b.wasmDefineArrayType(elementType: .wasmf64, mutability: false)
                return [arrayi32, arrayf64]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let array1 = function.wasmArrayNewDefault(
                        arrayType: typeGroup[0], size: function.consti32(3))
                    let array2 = function.wasmArrayNewDefault(
                        arrayType: typeGroup[1], size: function.consti32(2))
                    let sum = function.wasmi32BinOp(
                        function.wasmArrayGet(array: array1, index: function.consti32(0)),
                        function.truncatef64Toi32(
                            function.wasmArrayGet(array: array2, index: function.consti32(1)),
                            isSigned: true),
                        binOpKind: .Add)
                    return [sum]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "0\n")
    }

    @Test func testArrayLen() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                return [b.wasmDefineArrayType(elementType: .wasmi32, mutability: false)]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let arraySize3 = function.wasmArrayNewDefault(
                        arrayType: arrayType, size: function.consti32(3))
                    let arraySize7 = function.wasmArrayNewDefault(
                        arrayType: arrayType, size: function.consti32(7))
                    let result = function.wasmi32BinOp(
                        function.wasmArrayLen(arraySize3),
                        function.wasmArrayLen(arraySize7),
                        binOpKind: .Mul)
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "21\n")
    }

    @Test func testTypeDefWithSuperType() throws {
        let runner = JavaScriptExecutor()!

        let jsProg = buildAndLiftProgram { b in
            let types = b.wasmDefineTypeGroup {
                let superStruct = b.wasmDefineStructType(
                    fields: [.init(type: .wasmi32, mutability: true)],
                    isFinal: false)
                let subStruct = b.wasmDefineStructType(
                    fields: [
                        .init(type: .wasmi32, mutability: true),
                        .init(type: .wasmi64, mutability: true),
                    ], superTypeDef: superStruct, isFinal: false)

                let superArray = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: false,
                    indexType: superStruct, isFinal: false)
                let subArray = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: false,
                    indexType: subStruct, superTypeDef: superArray, isFinal: true)

                return [superStruct, subStruct, superArray, subArray]
            }

            let superStructType = types[0]
            let subStructType = types[1]
            let superArrayType = types[2]
            let subArrayType = types[3]

            let superStructRefType = b.type(of: superStructType).wasmTypeDefinition!
                .getReferenceTypeTo(nullability: true)
            let superArrayRefType = b.type(of: superArrayType).wasmTypeDefinition!
                .getReferenceTypeTo(nullability: true)

            let module = b.buildWasmModule { module in
                let upcastFunc = module.addWasmFunction(
                    with: [] => [superStructRefType, superArrayRefType]
                ) {
                    function, label, args in
                    let subStructInstance = function.wasmStructNewDefault(
                        structType: subStructType)
                    function.wasmStructSet(
                        theStruct: subStructInstance, fieldIndex: 0, value: function.consti32(1337))
                    let subArrayInstance = function.wasmArrayNewDefault(
                        arrayType: subArrayType, size: function.consti32(42))
                    return [subStructInstance, subArrayInstance]
                }

                module.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { function, label, args in
                    let instances = function.wasmCallDirect(function: upcastFunc, functionArgs: [])
                    let structInstance = instances[0]
                    let arrayInstance = instances[1]
                    let structField = function.wasmStructGet(
                        theStruct: structInstance, fieldIndex: 0)
                    let arrayLen = function.wasmArrayLen(arrayInstance)
                    return [structField, arrayLen]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(wasmOut)])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "1337,42\n")
    }

    @Test func testFindVariableFinal() throws {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let types = b.wasmDefineTypeGroup {
                let superStruct = b.wasmDefineStructType(
                    fields: [.init(type: .wasmi32, mutability: true)],
                    isFinal: false)
                let subStruct = b.wasmDefineStructType(
                    fields: [
                        .init(type: .wasmi32, mutability: true)
                    ], superTypeDef: superStruct, isFinal: true)

                return [superStruct, subStruct]
            }

            let superDef = types[0]
            let subDef = types[1]

            // Check that `findVariable()` doesn't return a final type definition
            // when searching for a non-final type definition.
            let superDefType = b.type(of: superDef)
            let foundVariable = b.findVariable(satisfying: { b.type(of: $0).Is(superDefType) })
            #expect(foundVariable == superDef)
            #expect(foundVariable != subDef)
        }
    }

    @Test func testSignatureTypeDefWithSuperType() throws {
        let runner = JavaScriptExecutor()!

        let jsProg = buildAndLiftProgram { b in
            let types = b.wasmDefineTypeGroup {
                let superStructType = b.wasmDefineStructType(
                    fields: [.init(type: .wasmi32, mutability: true)])
                let subStructType = b.wasmDefineStructType(
                    fields: [
                        .init(type: .wasmi32, mutability: true),
                        .init(type: .wasmi64, mutability: true),
                    ], superTypeDef: superStructType)

                // Parameters are contravariant, return types are covariant.
                // Super signature: [ref subStruct] => [ref superStruct]
                let superSignatureType = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true)] => [
                        .wasmRef(.Index(), nullability: true)
                    ],
                    indexTypes: [subStructType, superStructType])
                // Sub signature: [ref superStruct] => [ref subStruct]
                let subSignatureType = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true)] => [
                        .wasmRef(.Index(), nullability: true)
                    ],
                    indexTypes: [superStructType, subStructType],
                    superTypeDef: superSignatureType)

                return [superStructType, subStructType, superSignatureType, subSignatureType]
            }

            let superStructType = types[0]
            let subStructType = types[1]
            let superSignatureType = types[2]
            let subSignatureType = types[3]

            // This test casts a subFuncRef to a superFuncRef and calls it on a subStructInstance.
            let module = b.buildWasmModule { module in
                let subFunc = module.addWasmFunction(signature: subSignatureType) {
                    function, label, args in
                    // Downcast args[0] from superStructType to subStructType and return it.
                    let castResult = function.wasmRefCast(
                        args[0], refType: .wasmRef(.Index(), nullability: true),
                        typeDef: subStructType)
                    return [castResult]
                }

                module.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let subStructInstance = function.wasmStructNewDefault(structType: subStructType)
                    function.wasmStructSet(
                        theStruct: subStructInstance, fieldIndex: 0, value: function.consti32(42))

                    let subFuncRef = function.wasmRefFunc(subFunc)
                    let superFuncRef = function.wasmRefCast(
                        subFuncRef, refType: .wasmRef(.Index(), nullability: true),
                        typeDef: superSignatureType)
                    let structInstance = function.wasmCallRef(
                        functionRef: superFuncRef, functionArgs: [subStructInstance])[0]
                    #expect(
                        b.type(of: structInstance)
                            == b.type(of: superStructType).wasmTypeDefinition!.getReferenceTypeTo(
                                nullability: true))
                    return [function.wasmStructGet(theStruct: structInstance, fieldIndex: 0)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testCallIndirectWithSuperTypeSignature() throws {
        let runner = JavaScriptExecutor()!

        let jsProg = buildAndLiftProgram { b in
            let types = b.wasmDefineTypeGroup {
                let superStructType = b.wasmDefineStructType(
                    fields: [.init(type: .wasmi32, mutability: true)])
                let subStructType = b.wasmDefineStructType(
                    fields: [
                        .init(type: .wasmi32, mutability: true),
                        .init(type: .wasmi64, mutability: true),
                    ], superTypeDef: superStructType)

                // Super signature: [ref null subStruct] => [ref null superStruct]
                let superSignatureType = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true)] => [
                        .wasmRef(.Index(), nullability: true)
                    ],
                    indexTypes: [subStructType, superStructType])
                // Sub signature: [ref null superStruct] => [ref null subStruct]
                let subSignatureType = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true)] => [
                        .wasmRef(.Index(), nullability: true)
                    ],
                    indexTypes: [superStructType, subStructType],
                    superTypeDef: superSignatureType)

                return [superStructType, subStructType, superSignatureType, subSignatureType]
            }

            let superStructType = types[0]
            let subStructType = types[1]
            let superSignatureType = types[2]
            let subSignatureType = types[3]

            // This test calls a function with the sub signature from a table using call_indirect
            // with the super signature.
            let module = b.buildWasmModule { module in
                let subFunc = module.addWasmFunction(signature: subSignatureType) {
                    function, label, args in
                    let castResult = function.wasmRefCast(
                        args[0], refType: .wasmRef(.Index(), nullability: true),
                        typeDef: subStructType)
                    return [castResult]
                }
                let table = module.addTable(
                    elementType: .wasmFuncRef(), minSize: 1,
                    definedSignatures: [subFunc, subSignatureType], isTable64: false)

                module.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let subStructInstance = function.wasmStructNewDefault(structType: subStructType)
                    function.wasmStructSet(
                        theStruct: subStructInstance, fieldIndex: 0, value: function.consti32(42))
                    let results = function.wasmCallIndirect(
                        signatureDef: superSignatureType, table: table,
                        functionArgs: [subStructInstance], tableIndex: function.consti32(0))
                    #expect(
                        b.type(of: results[0])
                            == b.type(of: superStructType).wasmTypeDefinition!.getReferenceTypeTo(
                                nullability: true))
                    return [function.wasmStructGet(theStruct: results[0], fieldIndex: 0)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testStruct() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let types = b.wasmDefineTypeGroup {
                let structOfi32 = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
                let structOfStruct = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(
                            type: .wasmRef(.Index(), nullability: true), mutability: true)
                    ], indexTypes: [structOfi32])
                return [structOfi32, structOfStruct]
            }
            let structOfi32 = types[0]
            let structOfStruct = types[1]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let innerStruct = function.wasmStructNewDefault(structType: structOfi32)
                    function.wasmStructSet(theStruct: innerStruct, fieldIndex: 0, value: args[0])
                    let outerStruct = function.wasmStructNewDefault(structType: structOfStruct)
                    function.wasmStructSet(
                        theStruct: outerStruct, fieldIndex: 0, value: innerStruct)
                    let retrievedInnerStruct = function.wasmStructGet(
                        theStruct: outerStruct, fieldIndex: 0)
                    let retrievedValue = function.wasmStructGet(
                        theStruct: retrievedInnerStruct, fieldIndex: 0)
                    return [retrievedValue]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testStructNew() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let types = b.wasmDefineTypeGroup {
                let structOfi32 = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
                let structOfStruct = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(
                            type: .wasmRef(.Index(), nullability: true), mutability: true)
                    ], indexTypes: [structOfi32])
                return [structOfi32, structOfStruct]
            }
            let structOfi32 = types[0]
            let structOfStruct = types[1]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let innerStruct = function.wasmStructNew(
                        structType: structOfi32, fields: [args[0]])
                    let outerStruct = function.wasmStructNew(
                        structType: structOfStruct, fields: [innerStruct])
                    let retrievedInnerStruct = function.wasmStructGet(
                        theStruct: outerStruct, fieldIndex: 0)
                    let retrievedValue = function.wasmStructGet(
                        theStruct: retrievedInnerStruct, fieldIndex: 0)
                    return [retrievedValue]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let program = b.finalize()
            return fuzzer.lifter.lift(program)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testStructPacked() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let structType = b.wasmDefineTypeGroup {
                return [
                    b.wasmDefineStructType(
                        fields: [
                            WasmStructTypeDescription.Field(type: .wasmPackedI8, mutability: true),
                            WasmStructTypeDescription.Field(type: .wasmPackedI8, mutability: true),
                            WasmStructTypeDescription.Field(type: .wasmPackedI16, mutability: true),
                        ])
                ]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => Array(repeating: .wasmi32, count: 6)) {
                    function, label, args in
                    let structObj = function.wasmStructNewDefault(structType: structType)
                    function.wasmStructSet(
                        theStruct: structObj, fieldIndex: 0, value: function.consti32(-100))
                    function.wasmStructSet(
                        theStruct: structObj, fieldIndex: 1, value: function.consti32(42))
                    function.wasmStructSet(
                        theStruct: structObj, fieldIndex: 2, value: function.consti32(-10_000))
                    return [
                        function.wasmStructGet(theStruct: structObj, fieldIndex: 0, isSigned: true),
                        function.wasmStructGet(
                            theStruct: structObj, fieldIndex: 0, isSigned: false),
                        function.wasmStructGet(theStruct: structObj, fieldIndex: 1, isSigned: true),
                        function.wasmStructGet(
                            theStruct: structObj, fieldIndex: 1, isSigned: false),
                        function.wasmStructGet(theStruct: structObj, fieldIndex: 2, isSigned: true),
                        function.wasmStructGet(
                            theStruct: structObj, fieldIndex: 2, isSigned: false),
                    ]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(
            program: jsProg, runner: runner, outputString: "-100,156,42,42,-10000,55536\n")
    }

    @Test func testSignature() throws {
        let runner = JavaScriptExecutor()!
        let jsProg = buildAndLiftProgram { b in
            let typeGroup = b.wasmDefineTypeGroup {
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                let selfRef = b.wasmDefineForwardOrSelfReference()
                let signature = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true), .wasmi32] => [
                        .wasmi32, .wasmRef(.Index(), nullability: true),
                    ],
                    indexTypes: [arrayi32, selfRef])
                return [arrayi32, signature]
            }

            // TODO(pawkra): add shared ref variant.
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmFuncRef()]) { function, label, args in
                    // TODO(mliedtke): Do something more useful with the signature type than
                    // defining a null value for it and testing that it's implicitly convertible to
                    // .wasmFuncRef.
                    // TODO(mliedtke): Also properly test for self and forward references in both
                    // parameter and return types as well as type group dependencies once signatures
                    // are usable with more interesting operations.
                    [function.wasmRefNull(typeDef: typeGroup[1])]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [wasmOut])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "null\n")
    }

    @Test func testLoopWithWasmGCSignature() throws {
        let runner = JavaScriptExecutor()!
        let jsProg = buildAndLiftProgram { b in

            let typeGroup = b.wasmDefineTypeGroup {
                let arrayType = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                let signature = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true)]
                        => [.wasmRef(.Index(), nullability: true)],
                    indexTypes: [arrayType, arrayType])
                return [arrayType, signature]
            }
            let arrayType = typeGroup[0]
            let loopSignature = typeGroup[1]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let index = function.consti32(0)
                    let array = function.wasmArrayNewFixed(
                        arrayType: arrayType,
                        elements: [function.consti32(1)])
                    let arrayResult = function.wasmBuildLoop(with: loopSignature, args: [array]) {
                        loopLabel, args in
                        let val = function.wasmArrayGet(array: args[0], index: index)
                        let newVal = function.wasmi32BinOp(val, val, binOpKind: .Add)
                        function.wasmArraySet(array: args[0], index: index, element: newVal)
                        let cond = function.wasmi32CompareOp(
                            newVal, function.consti32(50), using: .Lt_s)
                        function.wasmBranchIf(cond, to: loopLabel, args: [args[0]])
                        return args
                    }[0]
                    return [function.wasmArrayGet(array: arrayResult, index: index)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [wasmOut])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "64\n")
    }

    @Test func testLoopWithAdHocWasmGCSignature() throws {
        let runner = JavaScriptExecutor()!
        let jsProg = buildAndLiftProgram { b in

            let structType = b.wasmDefineTypeGroup {
                [
                    b.wasmDefineStructType(
                        fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    )
                ]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let structVal = function.wasmStructNewDefault(structType: structType)
                    function.wasmStructSet(
                        theStruct: structVal, fieldIndex: 0, value: function.consti32(1))
                    let signature = [b.type(of: structVal)] => [.wasmi32]
                    // This loop creates a new struct on each iteration just for having different
                    // values on the loop entry and the loop backedge (`br_if`).
                    return function.wasmBuildLoop(with: signature, args: [structVal]) {
                        loopLabel, args in
                        let val = function.wasmStructGet(theStruct: args[0], fieldIndex: 0)
                        let newVal = function.wasmi32BinOp(val, val, binOpKind: .Add)
                        let newStruct = function.wasmStructNewDefault(structType: structType)
                        function.wasmStructSet(theStruct: newStruct, fieldIndex: 0, value: newVal)
                        let cond = function.wasmi32CompareOp(
                            newVal, function.consti32(50), using: .Lt_s)
                        function.wasmBranchIf(cond, to: loopLabel, args: [newStruct])
                        return [newVal]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [wasmOut])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "64\n")
    }

    @Test func testSelfReferenceType() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                let selfReference = b.wasmDefineForwardOrSelfReference()
                let arrayOfSelf = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: false,
                    indexType: selfReference)
                return [arrayOfSelf]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    // We can arbitrarily nest these self-referencing arrays.
                    let array1 = function.wasmArrayNewDefault(
                        arrayType: arrayType, size: function.consti32(12))
                    let array2 = function.wasmArrayNewFixed(
                        arrayType: arrayType, elements: [array1])
                    let array3 = function.wasmArrayNewFixed(
                        arrayType: arrayType, elements: [array2])
                    let zero = function.consti32(0)
                    let innerArray = function.wasmArrayGet(
                        array: function.wasmArrayGet(array: array3, index: zero),
                        index: zero)
                    return [function.wasmArrayLen(innerArray)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "12\n")
    }

    @Test func testForwardReferenceType() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroup = b.wasmDefineTypeGroup {
                let forwardReference = b.wasmDefineForwardOrSelfReference()
                let arrayOfArrayi32 = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: false,
                    indexType: forwardReference)
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                b.wasmResolveForwardReference(forwardReference, to: arrayi32)
                return [arrayOfArrayi32, arrayi32]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let arrayi32 = function.wasmArrayNewFixed(
                        arrayType: typeGroup[1], elements: [function.consti32(42)])
                    let arrayOfArrayi32 = function.wasmArrayNewFixed(
                        arrayType: typeGroup[0], elements: [arrayi32])
                    let zero = function.consti32(0)
                    let result = function.wasmArrayGet(
                        array: function.wasmArrayGet(array: arrayOfArrayi32, index: zero),
                        index: zero)
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testForwardOrSelfReferenceResolveMultipleTimes() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroup = b.wasmDefineTypeGroup {
                let forwardReference = b.wasmDefineForwardOrSelfReference()
                let arrayOfArrayi32 = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: true,
                    indexType: forwardReference)
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                b.wasmResolveForwardReference(forwardReference, to: arrayi32)
                let arrayOfArrayOfArrayi32 = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: true,
                    indexType: forwardReference)
                b.wasmResolveForwardReference(forwardReference, to: arrayOfArrayi32)
                // Here the forward reference acts as a self reference as we don't resolve it again.
                let arraySelf = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: true,
                    indexType: forwardReference)

                return [arrayOfArrayi32, arrayi32, arrayOfArrayOfArrayi32, arraySelf]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let arrayi32 = function.wasmArrayNewFixed(
                        arrayType: typeGroup[1], elements: [function.consti32(42)])
                    let arrayOfArrayi32 = function.wasmArrayNewFixed(
                        arrayType: typeGroup[0], elements: [arrayi32])
                    let arrayOfArrayOfArrayi32 = function.wasmArrayNewFixed(
                        arrayType: typeGroup[2], elements: [arrayOfArrayi32])
                    let zero = function.consti32(0)
                    let result = function.wasmArrayGet(
                        array: function.wasmArrayGet(
                            array: function.wasmArrayGet(
                                array: arrayOfArrayOfArrayi32,
                                index: zero),
                            index: zero),
                        index: zero)
                    return [result]
                }

                // This function doesn't really do anything testable, so this test case only verifies
                // that we produce valid Wasm (which means that the type group above was generated as
                // desired.)
                wasmModule.addWasmFunction(with: [] => []) { function, label, args in
                    let arraySelf = function.wasmArrayNewFixed(
                        arrayType: typeGroup[3],
                        elements: [
                            function.wasmRefNull(typeDef: typeGroup[3])
                        ])
                    // We can also store the arraySelf as an element into iself as the forwardReference
                    // got reset to a selfReference after the wasmResolveForwardReference() operation.
                    function.wasmArraySet(
                        array: arraySelf, index: function.consti32(0), element: arraySelf)
                    return []
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testDependentTypeGroups() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroupA = b.wasmDefineTypeGroup {
                return [b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]
            }
            let typeGroupB = b.wasmDefineTypeGroup {
                let typeWithDependency = b.wasmDefineArrayType(
                    elementType: .wasmRef(.Index(), nullability: true), mutability: false,
                    indexType: typeGroupA[0])
                let arrayi64 = b.wasmDefineArrayType(elementType: .wasmi64, mutability: true)
                return [arrayi64, typeWithDependency]
            }

            // Note that even though the module doesn't use typeGroupA nor any type dependent on
            // typeGroupA, it still needs to import both typegroups.
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                    let arrayi64 = function.wasmArrayNewFixed(
                        arrayType: typeGroupB[0], elements: [function.consti64(42)])
                    let result = function.wasmArrayGet(array: arrayi64, index: function.consti32(0))
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testRefFunc() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                let f1 = wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    return [function.wasmi32BinOp(args[0], function.consti32(1), binOpKind: .Add)]
                }
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) {
                    function, label, args in
                    let ref = function.wasmRefFunc(f1)
                    let callResult = function.wasmCallRef(functionRef: ref, functionArgs: args)[0]
                    return [callResult]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [b.loadInt(41)])
            b.callFunction(outputFunc, withArgs: [wasmOut])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testRefNullIndexTypes() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                [b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let refNull = function.wasmRefNull(typeDef: arrayType)
                    return [function.wasmRefIsNull(refNull)]
                }
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let array = function.wasmArrayNewFixed(arrayType: arrayType, elements: [])
                    return [function.wasmRefIsNull(array)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            for i in 0..<2 {
                let wasmOut = b.callMethod(
                    module.getExportedMethod(at: i), on: exports, withArgs: [])
                b.callFunction(outputFunc, withArgs: [wasmOut])
            }

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1\n0\n")
    }

    @Test(arguments: [true, false])
    func testRefNullAbstractTypes(sharedRef: Bool) throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-shared"])!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let (jsProg, expected) = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let unsupportedHeapType: Set<WasmAbstractHeapType> =
                sharedRef ? [.WasmFunc, .WasmNoFunc, .WasmExn, .WasmNoExn] : []
            let supportedHeapTypes = Array(
                Set(WasmAbstractHeapType.allCases).subtracting(unsupportedHeapType))

            let module = b.buildWasmModule { wasmModule in
                for heapType in supportedHeapTypes {
                    let valueType = ILType.wasmRef(heapType, shared: sharedRef, nullability: true)
                    if heapType.isUsableInJS() {
                        // ref.null <heapType>
                        wasmModule.addWasmFunction(with: [] => [valueType]) {
                            function, label, args in
                            [function.wasmRefNull(type: valueType)]
                        }
                    }
                    // ref.is_null(ref.null <heapType>)
                    wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                        [function.wasmRefIsNull(function.wasmRefNull(type: valueType))]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let exportedFctCount =
                supportedHeapTypes.count
                + supportedHeapTypes.count { $0.isUsableInJS() }
            for i in 0..<exportedFctCount {
                let wasmOut = b.callMethod(
                    module.getExportedMethod(at: i), on: exports, withArgs: [])
                b.callFunction(outputFunc, withArgs: [wasmOut])
            }

            let prog = b.finalize()
            // In JS all null values look the same (they are the same).
            return (
                fuzzer.lifter.lift(prog),
                supportedHeapTypes.map { $0.isUsableInJS() ? "null\n1\n" : "1\n" }.joined()
            )
        }
        testForOutput(program: jsProg, runner: runner, outputString: expected)
    }

    @Test func testRefEq() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmEqRef(), .wasmEqRef()] => [.wasmi32]) {
                    function, label, args in
                    return [function.wasmRefEq(args[0], args[1])]
                }
                wasmModule.addWasmFunction(with: [] => [.wasmEqRef()]) { function, label, args in
                    return [function.wasmArrayNewFixed(arrayType: arrayType, elements: [])]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            let array = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [])
            let otherArray = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [])

            let wasmRefEq = module.getExportedMethod(at: 0)
            let cases = [
                b.callMethod(wasmRefEq, on: exports, withArgs: [b.loadInt(1), b.loadInt(1)]),
                b.callMethod(wasmRefEq, on: exports, withArgs: [b.loadInt(0), b.loadInt(1)]),
                b.callMethod(wasmRefEq, on: exports, withArgs: [array, array]),
                b.callMethod(wasmRefEq, on: exports, withArgs: [array, otherArray]),
            ]

            for input in cases { b.callFunction(outputFunc, withArgs: [input]) }

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1\n0\n1\n0\n")
    }

    @Test func testRefAsNonNull() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                let signature = [.wasmAnyRef()] => [.wasmRefAny()]
                wasmModule.addWasmFunction(with: signature) { function, label, args in
                    return [function.wasmRefAsNonNull(args[0])]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmFuncName = module.getExportedMethod(at: 0)
            // Non-null input will just return its same non-null value.
            b.callFunction(
                outputFunc,
                withArgs: [
                    b.callMethod(wasmFuncName, on: exports, withArgs: [b.loadInt(42)])
                ])
            // Null input will trap.
            b.buildTryCatchFinally {
                b.callMethod(wasmFuncName, on: exports, withArgs: [b.loadNull()])
                b.callFunction(outputFunc, withArgs: [b.loadString("unreachable")])
            } catchBody: { exception in
                b.callFunction(outputFunc, withArgs: [b.loadString("caught exception")])
            }

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\ncaught exception\n")
    }

    @Test(arguments: [true, false])
    func testi31Ref(shared: Bool) throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-shared"])!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let i31RefT = ILType.wasmI31Ref(shared: shared)

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [i31RefT]) { function, label, args in
                    [function.wasmRefI31(args[0], shared: shared)]
                }
                wasmModule.addWasmFunction(with: [i31RefT] => [.wasmi32, .wasmi32]) {
                    function, label, args in
                    [
                        function.wasmI31Get(args[0], isSigned: true),
                        function.wasmI31Get(args[0], isSigned: false),
                    ]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let positiveI31 = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
            let negativeI31 = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(-42)])
            // An i31ref converts to a JS number.
            b.callFunction(outputFunc, withArgs: [positiveI31])
            b.callFunction(outputFunc, withArgs: [negativeI31])

            let positiveResults = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [positiveI31])
            let negativeResults = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [negativeI31])
            b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(positiveResults)])
            b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(negativeResults)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(
            program: jsProg, runner: runner, outputString: "42\n-42\n42,42\n-42,2147483606\n")
    }

    @Test func testExternAnyConversions() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmRefExtern()]) {
                    function, label, args in
                    // As ref.i31 produces a non null `ref i31`, the result of extern.convert_any is a
                    // non-nullable `ref extern`.
                    let result = function.wasmExternConvertAny(function.wasmRefI31(args[0]))
                    #expect(b.type(of: result) == .wasmRefExtern())
                    return [result]
                }

                wasmModule.addWasmFunction(with: [.wasmRefExtern()] => [.wasmRefAny()]) {
                    function, label, args in
                    let result = function.wasmAnyConvertExtern(args[0])
                    #expect(b.type(of: result) == .wasmRefAny())
                    return [result]
                }

                wasmModule.addWasmFunction(with: [] => [.wasmExternRef()]) {
                    function, label, args in
                    let result = function.wasmExternConvertAny(
                        function.wasmRefNull(type: .wasmNullRef()))
                    #expect(b.type(of: result) == .wasmExternRef())
                    return [result]
                }

                wasmModule.addWasmFunction(with: [] => [.wasmAnyRef()]) { function, label, args in
                    let result = function.wasmAnyConvertExtern(
                        function.wasmRefNull(type: .wasmNullExternRef()))
                    #expect(b.type(of: result) == .wasmAnyRef())
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            for i in 0..<4 {
                let result = b.callMethod(
                    module.getExportedMethod(at: i), on: exports, withArgs: [b.loadInt(42)])
                b.callFunction(outputFunc, withArgs: [result])
            }

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\nnull\nnull\n")
    }

    @Test func testRefTest() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                b.wasmDefineArrayType(elementType: .wasmi32, mutability: false)
            }[0]
            let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let array = function.wasmArrayNewFixed(arrayType: arrayType, elements: [])
                    let null = function.wasmRefNull(type: .wasmArrayRef())
                    let refType = ILType.wasmRef(.Index(), nullability: false)
                    let refNullType = ILType.wasmRef(.Index(), nullability: true)
                    let results = [
                        function.wasmRefTest(array, refType: refType, typeDef: arrayType),
                        function.wasmRefTest(null, refType: refType, typeDef: arrayType),
                        function.wasmRefTest(array, refType: refNullType, typeDef: arrayType),
                        function.wasmRefTest(null, refType: refNullType, typeDef: arrayType),
                    ]
                    let result = results.reduce(
                        function.consti32(0),
                        { acc, r in
                            let shifted = function.wasmi32BinOp(
                                acc, function.consti32(10), binOpKind: WasmIntegerBinaryOpKind.Mul)
                            return function.wasmi32BinOp(
                                shifted, r, binOpKind: WasmIntegerBinaryOpKind.Add)
                        })
                    return [result]
                }
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let array = function.wasmArrayNewFixed(arrayType: arrayType, elements: [])
                    let result = function.wasmRefTest(array, refType: .wasmEqRef())
                    return [result]
                }
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let ref = function.wasmRefI31(function.consti32(0))
                    let refType = ILType.wasmRef(.Index(), nullability: false)
                    let result = function.wasmRefTest(ref, refType: refType, typeDef: arrayType)
                    return [result]
                }
                wasmModule.addWasmFunction(with: [.wasmRefExtern()] => [.wasmi32]) {
                    function, label, args in
                    let result = function.wasmRefTest(args[0], refType: .wasmNullExternRef())
                    return [result]
                }
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let exnref = function.wasmBuildBlockWithResults(
                        with: [] => [.wasmExnRef()], args: []
                    ) { catchLabel, _ in
                        function.wasmBuildTryTable(
                            with: [] => [], args: [catchLabel], catches: [.AllRef]
                        ) { _, _ in
                            function.WasmBuildThrow(tag: tagi32, inputs: [function.consti32(42)])
                            return []
                        }
                        return [function.wasmRefNull(type: .wasmExnRef())]
                    }[0]
                    let result = function.wasmRefTest(exnref, refType: .wasmExnRef())
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            for method in module.getExportedMethods() {
                let result = b.callMethod(method.0, on: exports, withArgs: [b.loadInt(42)])
                b.callFunction(outputFunc, withArgs: [result])
            }

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1011\n1\n0\n0\n1\n")
    }

    @Test func testRefCast() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arrayType = b.wasmDefineTypeGroup {
                b.wasmDefineArrayType(elementType: .wasmi32, mutability: false)
            }[0]

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmArrayRef()]) {
                    function, label, args in
                    let array = function.wasmArrayNewFixed(
                        arrayType: arrayType, elements: [args[0]])
                    return [array]
                }
                wasmModule.addWasmFunction(with: [.wasmEqRef()] => [.wasmi32]) {
                    function, label, args in
                    let (refType, nonNullRefType, abstractRefType) = (
                        ILType.wasmRef(.Index(), nullability: true),
                        ILType.wasmRef(.Index(), nullability: false),
                        ILType.wasmRef(
                            .Abstract(HeapTypeInfo(.WasmArray, shared: false)), nullability: true),
                    )
                    let arrays = [
                        function.wasmRefCast(args[0], refType: refType, typeDef: arrayType),
                        function.wasmRefCast(args[0], refType: nonNullRefType, typeDef: arrayType),
                        function.wasmRefCast(args[0], refType: abstractRefType),
                    ]
                    let value1 = function.wasmArrayGet(
                        array: arrays[0], index: function.consti32(0))
                    let value2 = function.wasmArrayGet(
                        array: arrays[1], index: function.consti32(0))
                    return [
                        function.wasmi32BinOp(
                            value1, value2, binOpKind: WasmIntegerBinaryOpKind.Add)
                    ]
                }
                wasmModule.addWasmFunction(with: [.wasmExternRef()] => [.wasmRefExtern()]) {
                    function, label, args in
                    let cast = function.wasmRefCast(args[0], refType: .wasmRefExtern())
                    return [cast]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let arrayRef = b.callMethod(
                module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(21)])
            let result = b.callMethod(
                module.getExportedMethod(at: 1), on: exports, withArgs: [arrayRef])
            b.callFunction(outputFunc, withArgs: [result])
            let ext = b.callMethod(
                module.getExportedMethod(at: 2), on: exports, withArgs: [b.loadInt(5)])
            b.callFunction(outputFunc, withArgs: [ext])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n5\n")
    }

    @Test func testRefCastError() throws {
        let runner = JavaScriptExecutor()!
        let jsProg = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmFuncRef()]) { function, label, args in
                    let funcref = function.wasmRefNull(type: ILType.wasmFuncRef())
                    let nullFuncType = ILType.wasmRef(
                        .Abstract(HeapTypeInfo.init(.WasmFunc, shared: false)), nullability: false)
                    let cast = function.wasmRefCast(funcref, refType: nullFuncType)
                    return [cast]
                }
            }
            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            b.buildTryCatchFinally {
                let _ = b.callMethod(module.getExportedMethod(at: 0), on: exports)
                b.callFunction(outputFunc, withArgs: [b.loadString("Not reached")])
            } catchBody: { e in
                b.callFunction(outputFunc, withArgs: [b.loadString("exception")])
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "exception\n")
    }

    @Test func testBranchOnNull() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmAnyRef()] => [.wasmi32]) {
                    f, functionLabel, params in
                    let ref = params[0]
                    f.wasmBranchOnNull(ref, to: functionLabel, args: [f.consti32(20)])
                    return [f.consti32(30)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            let out1 = b.callMethod(main, on: exports, withArgs: [b.loadNull()])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1)])

            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "20\n30\n")
    }

    @Test func testBranchOnNullWithArgs() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmAnyRef(), .wasmi32] => [.wasmi32]) {
                    f, functionLabel, params in
                    let ref = params[0]
                    let arg = params[1]
                    let results = f.wasmBranchOnNull(ref, to: functionLabel, args: [arg])

                    let reboundArg = results[0]
                    let nonNullRef = results[1]
                    let isNull = f.wasmRefIsNull(nonNullRef)

                    // Return arg + 1000 + isNull.
                    let sum = f.wasmi32BinOp(reboundArg, f.consti32(1000), binOpKind: .Add)
                    return [f.wasmi32BinOp(sum, isNull, binOpKind: .Add)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            // Case 1: ref is null. Branches to functionLabel with 1337. Output: 1337
            let out1 = b.callMethod(main, on: exports, withArgs: [b.loadNull(), b.loadInt(1337)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1)])

            // Case 2: ref is not null. Does not branch. Output: 42 + 1000 + 0 = 1042
            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100), b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1337\n1042\n")
    }

    @Test func testBranchOnNullToOuterBlockWithArgs() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmAnyRef(), .wasmi32] => [.wasmi32]) {
                    f, functionLabel, params in
                    let ref = params[0]
                    let arg = params[1]
                    return f.wasmBuildBlockWithResults(with: [] => [.wasmi32], args: []) {
                        blockLabel, _ in
                        f.wasmBranchOnNull(ref, to: functionLabel, args: [arg])
                        return [f.consti32(30)]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            let out1 = b.callMethod(main, on: exports, withArgs: [b.loadNull(), b.loadInt(1337)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1)])

            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100), b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1337\n30\n")
    }

    @Test func testBranchOnCast() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let structType = b.wasmDefineTypeGroup {
                b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
            }[0]

            let module = b.buildWasmModule { wasmModule in
                let unresolvedType = ILType.wasmRef(.Index(), nullability: true)
                wasmModule.addWasmFunction(
                    with: [.wasmAnyRef()] => [.wasmi32, unresolvedType], indexTypes: [structType]
                ) {
                    f, functionLabel, params in
                    let ref = params[0]

                    let results = f.wasmBranchOnCast(
                        ref, targetRefType: unresolvedType, to: functionLabel,
                        args: [f.consti32(42)],
                        typeDef: structType)

                    let reboundArg = results[0]
                    let originalRef = results[1]
                    let isNull = f.wasmRefIsNull(originalRef)
                    let isNotNull = f.wasmi32BinOp(isNull, f.consti32(1), binOpKind: .Xor)
                    let sum1 = f.wasmi32BinOp(reboundArg, f.consti32(1000), binOpKind: .Add)
                    let sum2 = f.wasmi32BinOp(sum1, isNotNull, binOpKind: .Add)

                    let s = f.wasmStructNew(structType: structType, fields: [f.consti32(99)])
                    return [sum2, s]
                }

                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmAnyRef()]) {
                    f, _, params in
                    let s = f.wasmStructNew(structType: structType, fields: [params[0]])
                    return [s]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)
            let makeStruct = module.getExportedMethod(at: 1)

            let s = b.callMethod(makeStruct, on: exports, withArgs: [b.loadInt(55)])
            let out1 = b.callMethod(main, on: exports, withArgs: [s])
            let out1_0 = b.getProperty("0", of: out1)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1_0)])

            let i31 = b.loadInt(1)
            let out2 = b.callMethod(main, on: exports, withArgs: [i31])
            let out2_0 = b.getProperty("0", of: out2)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2_0)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n1043\n")
    }

    @Test func testBranchOnCastFail() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let structType = b.wasmDefineTypeGroup {
                b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
            }[0]

            let module = b.buildWasmModule { wasmModule in
                let unresolvedType = ILType.wasmRef(.Index(), nullability: true)

                wasmModule.addWasmFunction(
                    with: [.wasmAnyRef()] => [.wasmi32, .wasmAnyRef()], indexTypes: []
                ) {
                    f, functionLabel, params in
                    let ref = params[0]

                    let results = f.wasmBranchOnCastFail(
                        ref, targetRefType: unresolvedType, to: functionLabel,
                        args: [f.consti32(42)],
                        typeDef: structType)

                    let reboundArg = results[0]
                    let castedRef = results[1]
                    let isCorrectlyTyped = f.wasmRefTest(
                        castedRef, refType: unresolvedType, typeDef: structType)
                    let sum = f.wasmi32BinOp(reboundArg, isCorrectlyTyped, binOpKind: .Add)

                    return [sum, castedRef]
                }

                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmAnyRef()]) {
                    f, _, params in
                    let s = f.wasmStructNew(structType: structType, fields: [params[0]])
                    return [s]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)
            let makeStruct = module.getExportedMethod(at: 1)

            let s = b.callMethod(makeStruct, on: exports, withArgs: [b.loadInt(55)])
            let out1 = b.callMethod(main, on: exports, withArgs: [s])
            let out1_0 = b.getProperty("0", of: out1)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1_0)])

            let i31 = b.loadInt(1)
            let out2 = b.callMethod(main, on: exports, withArgs: [i31])
            let out2_0 = b.getProperty("0", of: out2)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2_0)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "43\n42\n")
    }

    @Test func testBranchOnNonNull() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(
                    with: [.wasmAnyRef()] => [.wasmi32, .wasmRef(.WasmAny, nullability: false)]
                ) {
                    f, functionLabel, params in
                    let ref = params[0]
                    f.wasmBranchOnNonNull(ref, to: functionLabel, args: [f.consti32(1)])
                    let nonNullRef = f.wasmRefI31(f.consti32(42), shared: false)
                    return [f.consti32(2), nonNullRef]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            let out1: Variable = b.callMethod(main, on: exports, withArgs: [b.loadNull()])
            let outString1 = b.callMethod("toString", on: out1)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString1)])

            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100)])
            let outString2 = b.callMethod("toString", on: out2)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "2,42\n1,100\n")
    }

    @Test func testBranchOnNonNullWithArgs() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(
                    with: [.wasmAnyRef(), .wasmi32] => [
                        .wasmi32, .wasmRef(.WasmAny, nullability: false),
                    ]
                ) {
                    f, functionLabel, params in
                    let ref = params[0]
                    let arg = params[1]
                    let results = f.wasmBranchOnNonNull(ref, to: functionLabel, args: [arg])

                    let reboundArg = results[0]
                    let sum = f.wasmi32BinOp(reboundArg, f.consti32(1000), binOpKind: .Add)
                    let nonNullRef = f.wasmRefI31(f.consti32(1), shared: false)
                    return [sum, nonNullRef]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            // Case 1: ref is null. Does not branch. Output: 1337 + 1000 = 2337
            let out1 = b.callMethod(main, on: exports, withArgs: [b.loadNull(), b.loadInt(1337)])
            let outString1 = b.callMethod("toString", on: out1)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString1)])

            // Case 2: ref is not null. Branches to functionLabel with 42. Output: 42
            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100), b.loadInt(42)])
            let outString2 = b.callMethod("toString", on: out2)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "2337,1\n42,100\n")
    }

    @Test func testBranchOnNonNullToOuterBlockWithArgs() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(
                    with: [.wasmAnyRef(), .wasmi32] => [
                        .wasmi32, .wasmRef(.WasmAny, nullability: false),
                    ]
                ) {
                    f, functionLabel, params in
                    let ref = params[0]
                    let arg = params[1]
                    return f.wasmBuildBlockWithResults(
                        with: [] => [.wasmi32, .wasmRef(.WasmAny, nullability: false)], args: []
                    ) {
                        blockLabel, _ in
                        f.wasmBranchOnNonNull(ref, to: functionLabel, args: [arg])
                        let nonNullRef = f.wasmRefI31(f.consti32(1), shared: false)
                        return [f.consti32(30), nonNullRef]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let main = module.getExportedMethod(at: 0)

            // Case 1: ref is null. Does not branch. Output: 30
            let out1 = b.callMethod(main, on: exports, withArgs: [b.loadNull(), b.loadInt(1337)])
            let outString1 = b.callMethod("toString", on: out1)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString1)])

            // Case 2: ref is not null. Branches to functionLabel with 42. Output: 42
            let out2 = b.callMethod(main, on: exports, withArgs: [b.loadInt(100), b.loadInt(42)])
            let outString2 = b.callMethod("toString", on: out2)
            b.callFunction(
                outputFunc, withArgs: [b.callMethod("toString", on: outString2)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "30,1\n42,100\n")
    }

    @Test func testSubtypeInDifferentTypeGroup() throws {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let typeGroupA = b.wasmDefineTypeGroup {
                let superStruct = b.wasmDefineStructType(
                    fields: [.init(type: .wasmi32, mutability: true)])
                return [superStruct]
            }
            let typeGroupB = b.wasmDefineTypeGroup {
                let subStruct = b.wasmDefineStructType(
                    fields: [
                        .init(type: .wasmi32, mutability: true),
                        .init(type: .wasmi64, mutability: true),
                    ], superTypeDef: typeGroupA[0])
                return [subStruct]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    let structObj = function.wasmStructNew(
                        structType: typeGroupB[0],
                        fields: [function.consti32(42), function.consti64(1337)])
                    let result = function.wasmStructGet(theStruct: structObj, fieldIndex: 0)
                    return [result]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }
}
