import Algorithms
import Foundation
import Testing

@testable import Fuzzilli

@Suite(.enabled { JavaScriptExecutor() != nil })
struct WasmCustomDescriptorsTests {
    let config = Configuration(
        logLevel: .error, enableInspection: true, enableCustomDescriptors: true)

    @Test func testDescriptorAndDescribes() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],

                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )
                return [described, descriptor]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    for type in types {
                        _ = function.wasmRefNull(typeDef: type)
                    }
                    return []
                }
            }
            let _ = module.loadExports()
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    @Test func testSubtypeValidation() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],

                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )

                let describedSub = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(type: .wasmi32, mutability: true),
                        WasmStructTypeDescription.Field(type: .wasmf64, mutability: false),
                    ],
                    superTypeDef: described
                )
                let descriptorSub = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(type: .wasmi32, mutability: true),
                        WasmStructTypeDescription.Field(type: .wasmf64, mutability: false),
                    ],
                    superTypeDef: descriptor,
                    describes: describedSub
                )
                return [described, descriptor, describedSub, descriptorSub]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    for type in types {
                        _ = function.wasmRefNull(typeDef: type)
                    }
                    return []
                }
            }
            let _ = module.loadExports()
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    @Test func testGenerateSubtypeOnDescribed() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],

                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )

                let describedSub = b.generateSubtype(for: described)
                return [described, descriptor, describedSub]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    for type in types {
                        _ = function.wasmRefNull(typeDef: type)
                    }
                    return []
                }
            }
            let _ = module.loadExports()
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    @Test func testGenerateSubtypeOnDescriptor() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],

                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )

                let descriptorSub = b.generateSubtype(for: descriptor)

                let describedSubDesc =
                    (b.type(of: descriptorSub).wasmTypeDefinition?.description
                    as! WasmStructTypeDescription).describes!
                let describedSub = b.findVariable {
                    b.type(of: $0).wasmTypeDefinition?.description == describedSubDesc
                }!

                return [described, descriptor, descriptorSub, describedSub]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(
                    with: [] => [.wasmi32, .wasmi32, .wasmi32, .wasmi32]
                ) { function, _, _ in
                    let val42 = function.consti32(42)
                    let val43 = function.consti32(43)
                    let val44 = function.consti32(44)

                    let descriptorInst = function.wasmStructNew(
                        structType: types[1], fields: [val43])
                    let describedInst = function.wasmStructNewDesc(
                        structType: types[0], descriptor: descriptorInst, fields: [val42])
                    let fetchedDesc = function.wasmRefGetDesc(theStruct: describedInst)

                    let v0 = function.wasmStructGet(theStruct: describedInst, fieldIndex: 0)
                    let v1 = function.wasmStructGet(theStruct: fetchedDesc, fieldIndex: 0)

                    let subDescInst = function.wasmStructNewDefault(structType: types[2])
                    function.wasmStructSet(theStruct: subDescInst, fieldIndex: 0, value: val44)
                    let defaultDescribedInst = function.wasmStructNewDefaultDesc(
                        structType: types[3], descriptor: subDescInst)

                    let v2 = function.wasmStructGet(theStruct: defaultDescribedInst, fieldIndex: 0)
                    let fetchedSubDesc = function.wasmRefGetDesc(theStruct: defaultDescribedInst)
                    let v3 = function.wasmStructGet(theStruct: fetchedSubDesc, fieldIndex: 0)

                    return [v0, v1, v2, v3]
                }
            }
            let exports = module.loadExports()
            let res = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [res])
        }
        testForOutput(program: jsProg, runner: runner, outputString: "42,43,0,44\n")
    }

    @Test func testExactTypeOutputs() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let structType = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],

                )
                let arrayType = b.wasmDefineArrayType(
                    elementType: .wasmi32,
                    mutability: true
                )
                return [structType, arrayType]
            }
            let structType = types[0]
            let arrayType = types[1]

            let module = b.buildWasmModule { wasmModule in
                let funcRef = wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    let i32 = function.consti32(42)

                    let structInst = function.wasmStructNew(structType: structType, fields: [i32])
                    #expect(b.type(of: structInst).wasmReferenceType?.kind.isExact == true)

                    let structInstDefault = function.wasmStructNewDefault(structType: structType)
                    #expect(b.type(of: structInstDefault).wasmReferenceType?.kind.isExact == true)

                    let nonNullRef = function.wasmRefAsNonNull(structInstDefault)
                    #expect(b.type(of: nonNullRef).wasmReferenceType?.kind.isExact == true)

                    let arrayInstFixed = function.wasmArrayNewFixed(
                        arrayType: arrayType, elements: [i32, i32])
                    #expect(b.type(of: arrayInstFixed).wasmReferenceType?.kind.isExact == true)

                    let arrayInstDefault = function.wasmArrayNewDefault(
                        arrayType: arrayType, size: i32)
                    #expect(b.type(of: arrayInstDefault).wasmReferenceType?.kind.isExact == true)

                    return []
                }

                let _ = wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    let ref = function.wasmRefFunc(funcRef)
                    #expect(b.type(of: ref).wasmReferenceType?.kind.isExact == true)

                    let nullRef = function.wasmRefNull(typeDef: structType)
                    #expect(b.type(of: nullRef).wasmReferenceType?.kind.isExact == true)

                    return []
                }
            }
            let _ = module.loadExports()
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    @Test func testGlobalIndexExactTyped() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let fuzzer = makeMockFuzzer(config: config, environment: JavaScriptEnvironment())
        let jsProg = fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let structType = b.wasmDefineTypeGroup {
                [
                    b.wasmDefineStructType(
                        fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                        indexTypes: [],
                        isFinal: true
                    )
                ]
            }[0]

            let module = b.buildWasmModule { wasmModule in
                let global = wasmModule.addGlobal(
                    wasmGlobal: .indexExactRef, isMutable: true, typeDef: structType)

                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let i32 = function.consti32(42)
                    let structInst = function.wasmStructNew(structType: structType, fields: [i32])
                    function.wasmStoreGlobal(globalVariable: global, to: structInst)

                    let loadedStruct = function.wasmLoadGlobal(globalVariable: global)
                    let loadedI32 = function.wasmStructGet(theStruct: loadedStruct, fieldIndex: 0)
                    return [loadedI32]
                }
            }

            let exports = module.loadExports()
            let res = b.callMethod(module.getExportedMethod(at: 0), on: exports)

            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [res])

            let prog = b.finalize()
            return fuzzer.lifter.lift(prog)
        }

        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    @Test func testRefCastDescEq() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let superType = b.wasmDefineStructType(fields: [])
                let superTypeDescriptor = b.wasmDefineStructType(
                    fields: [],
                    describes: superType
                )
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    superTypeDef: superType
                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    superTypeDef: superTypeDescriptor,
                    describes: described
                )
                return [described, descriptor, superType, superTypeDescriptor]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let i32 = function.consti32(42)

                    let descriptorInst = function.wasmStructNew(structType: types[1], fields: [i32])
                    let describedInst = function.wasmStructNewDesc(
                        structType: types[0], descriptor: descriptorInst, fields: [i32])
                    #expect(b.type(of: descriptorInst).wasmReferenceType?.kind.isExact == true)
                    #expect(b.type(of: describedInst).wasmReferenceType?.kind.isExact == true)

                    let castDescribed = function.wasmRefCastDescEq(
                        describedInst, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(isExact: false), nullability: true))
                    #expect(b.type(of: castDescribed).wasmReferenceType?.kind.isExact == false)
                    let v0 = function.wasmStructGet(theStruct: castDescribed, fieldIndex: 0)

                    let castDescribedNonNull = function.wasmRefCastDescEq(
                        describedInst, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(isExact: true), nullability: false))
                    #expect(
                        b.type(of: castDescribedNonNull).wasmReferenceType?.kind.isExact == true)
                    let v1 = function.wasmStructGet(
                        theStruct: castDescribedNonNull, fieldIndex: 0)

                    let abstractRef = function.wasmRefCast(
                        describedInst, refType: ILType.wasmRef(.WasmStruct, nullability: false))
                    let castFromAbstract = function.wasmRefCastDescEq(
                        abstractRef, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(isExact: false), nullability: false))
                    #expect(b.type(of: castFromAbstract).wasmReferenceType?.kind.isExact == false)
                    let v2 = function.wasmStructGet(theStruct: castFromAbstract, fieldIndex: 0)

                    let superTypeRef = function.wasmRefCast(
                        describedInst, refType: ILType.wasmRef(.Index(), nullability: false),
                        typeDef: types[2])
                    let castFromSupertype = function.wasmRefCastDescEq(
                        superTypeRef, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(isExact: false), nullability: false))
                    #expect(b.type(of: castFromSupertype).wasmReferenceType?.kind.isExact == false)
                    let v3 = function.wasmStructGet(theStruct: castFromSupertype, fieldIndex: 0)

                    let nullRef = function.wasmRefNull(typeDef: types[0])
                    let castNull = function.wasmRefCastDescEq(
                        nullRef, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(isExact: true), nullability: true))
                    #expect(b.type(of: castNull).wasmReferenceType?.kind.isExact == true)
                    let isNull = function.wasmRefIsNull(castNull)

                    let inexactDesc = function.wasmRefCast(
                        descriptorInst,
                        refType: ILType.wasmRef(.Index(isExact: false), nullability: false),
                        typeDef: types[1]
                    )
                    #expect(b.type(of: inexactDesc).wasmReferenceType?.kind.isExact == false)
                    let castWithInexactDesc = function.wasmRefCastDescEq(
                        describedInst, descriptorRef: inexactDesc,
                        targetRefType: ILType.wasmRef(.Index(isExact: false), nullability: false)
                    )
                    #expect(
                        b.type(of: castWithInexactDesc).wasmReferenceType?.kind.isExact == false)

                    let sum1 = function.wasmi32BinOp(v0, v1, binOpKind: .Add)
                    let sum2 = function.wasmi32BinOp(sum1, v2, binOpKind: .Add)
                    let sum3 = function.wasmi32BinOp(sum2, v3, binOpKind: .Add)
                    let sum = function.wasmi32BinOp(sum3, isNull, binOpKind: .Add)
                    return [sum]
                }
            }
            let exports = module.loadExports()
            let res = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [res])
        }
        testForOutput(program: jsProg, runner: runner, outputString: "169\n")
    }

    @Test func testRefCastDescEqNullTraps() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(fields: [])
                let descriptor = b.wasmDefineStructType(
                    fields: [],
                    describes: described
                )
                return [described, descriptor]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    let descriptorInst = function.wasmStructNew(structType: types[1], fields: [])
                    let nullRef = function.wasmRefNull(typeDef: types[0])
                    _ = function.wasmRefCastDescEq(
                        nullRef, descriptorRef: descriptorInst,
                        targetRefType: ILType.wasmRef(.Index(), nullability: false))
                    return []
                }
            }
            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            b.buildTryCatchFinally {
                let _ = b.callMethod(module.getExportedMethod(at: 0), on: exports)
                b.callFunction(outputFunc, withArgs: [b.loadString("Not reached")])
            } catchBody: { e in
                b.callFunction(outputFunc, withArgs: [b.loadString("trapped")])
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "trapped\n")
    }
    @Test func testBranchOnCastDescEq() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmf64, mutability: true)],
                    describes: described
                )
                return [described, descriptor]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let structVal = function.consti32(42)
                    let descVal = function.constf64(13.37)
                    let fallbackStructVal = function.consti32(100)
                    let fallbackDescVal = function.constf64(200.0)

                    let descriptorInst = function.wasmStructNew(
                        structType: types[1], fields: [descVal])
                    let describedInst = function.wasmStructNewDesc(
                        structType: types[0], descriptor: descriptorInst, fields: [structVal])

                    let abstractRef = function.wasmRefCast(
                        describedInst, refType: ILType.wasmRef(.WasmStruct, nullability: false))

                    let structTypeDesc =
                        b.type(of: types[0]).wasmTypeDefinition!.description
                        as! WasmStructTypeDescription

                    // 1. Exact descriptor with exact target
                    let resultExact = function.wasmBuildBlockWithResults(
                        with: [] => [
                            ILType.wasmIndexRef(structTypeDesc, nullability: false, isExact: true)
                        ],
                        args: []
                    ) { blockLabel, _ in
                        let _ = function.wasmBranchOnCastDescEq(
                            abstractRef, descriptorRef: descriptorInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: true), nullability: false),
                            to: blockLabel, args: [])

                        let descriptorInst2 = function.wasmStructNew(
                            structType: types[1], fields: [fallbackDescVal])
                        let describedInst2 = function.wasmStructNewDesc(
                            structType: types[0], descriptor: descriptorInst2,
                            fields: [fallbackStructVal])
                        return [describedInst2]
                    }
                    #expect(b.type(of: resultExact[0]).wasmReferenceType?.kind.isExact == true)
                    let v0 = function.wasmStructGet(theStruct: resultExact[0], fieldIndex: 0)

                    // 2. Exact descriptor with inexact target
                    let resultInexactWithExactDesc = function.wasmBuildBlockWithResults(
                        with: [] => [
                            ILType.wasmIndexRef(structTypeDesc, nullability: false, isExact: false)
                        ],
                        args: []
                    ) { blockLabel, _ in
                        let _ = function.wasmBranchOnCastDescEq(
                            abstractRef, descriptorRef: descriptorInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: false), nullability: false),
                            to: blockLabel, args: [])

                        let descriptorInst2 = function.wasmStructNew(
                            structType: types[1], fields: [fallbackDescVal])
                        let describedInst2 = function.wasmStructNewDesc(
                            structType: types[0], descriptor: descriptorInst2,
                            fields: [fallbackStructVal])
                        return [describedInst2]
                    }
                    #expect(
                        b.type(of: resultInexactWithExactDesc[0]).wasmReferenceType?.kind.isExact
                            == false)
                    let v1 = function.wasmStructGet(
                        theStruct: resultInexactWithExactDesc[0], fieldIndex: 0)

                    // 3. Inexact descriptor with inexact target
                    let inexactDesc = function.wasmRefCast(
                        descriptorInst,
                        refType: ILType.wasmRef(.Index(isExact: false), nullability: false),
                        typeDef: types[1]
                    )
                    #expect(b.type(of: inexactDesc).wasmReferenceType?.kind.isExact == false)

                    let resultInexactWithInexactDesc = function.wasmBuildBlockWithResults(
                        with: [] => [
                            ILType.wasmIndexRef(structTypeDesc, nullability: false, isExact: false)
                        ],
                        args: []
                    ) { blockLabel, _ in
                        let _ = function.wasmBranchOnCastDescEq(
                            abstractRef, descriptorRef: inexactDesc,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: false), nullability: false),
                            to: blockLabel, args: [])

                        let descriptorInst2 = function.wasmStructNew(
                            structType: types[1], fields: [fallbackDescVal])
                        let describedInst2 = function.wasmStructNewDesc(
                            structType: types[0], descriptor: descriptorInst2,
                            fields: [fallbackStructVal])
                        return [describedInst2]
                    }
                    #expect(
                        b.type(of: resultInexactWithInexactDesc[0]).wasmReferenceType?.kind.isExact
                            == false)
                    let v2 = function.wasmStructGet(
                        theStruct: resultInexactWithInexactDesc[0], fieldIndex: 0)

                    let sum1 = function.wasmi32BinOp(v0, v1, binOpKind: .Add)
                    let sum2 = function.wasmi32BinOp(sum1, v2, binOpKind: .Add)

                    // 4. Exact descriptor with exact target, but inexact label
                    let resultInexactLabelWithExactTarget = function.wasmBuildBlockWithResults(
                        with: [] => [
                            ILType.wasmIndexRef(structTypeDesc, nullability: false, isExact: false)
                        ],
                        args: []
                    ) { blockLabel, _ in
                        let _ = function.wasmBranchOnCastDescEq(
                            abstractRef, descriptorRef: descriptorInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: true), nullability: false),
                            to: blockLabel, args: [])

                        let descriptorInst2 = function.wasmStructNew(
                            structType: types[1], fields: [fallbackDescVal])
                        let describedInst2 = function.wasmStructNewDesc(
                            structType: types[0], descriptor: descriptorInst2,
                            fields: [fallbackStructVal])
                        return [describedInst2]
                    }
                    #expect(
                        b.type(of: resultInexactLabelWithExactTarget[0]).wasmReferenceType?.kind
                            .isExact == false)
                    let v3 = function.wasmStructGet(
                        theStruct: resultInexactLabelWithExactTarget[0], fieldIndex: 0)

                    let sum = function.wasmi32BinOp(sum2, v3, binOpKind: .Add)
                    return [sum]
                }
            }
            let exports = module.loadExports()
            let res = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [res])
        }
        testForOutput(program: jsProg, runner: runner, outputString: "168\n")
    }
    @Test func testBranchOnCastDescEqFail() throws {
        let runner = JavaScriptExecutor(withArguments: ["--wasm-custom-descriptors"])!
        let jsProg = buildAndLiftProgram(config: config) { b in
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmf32, mutability: true)],
                    describes: described
                )
                return [described, descriptor]
            }

            let module = b.buildWasmModule { wasmModule in
                let _ = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let i32 = function.consti32(42)
                    let f32 = function.constf32(13.37)

                    let descriptorInst = function.wasmStructNew(structType: types[1], fields: [f32])
                    let describedInst = function.wasmStructNewDesc(
                        structType: types[0], descriptor: descriptorInst, fields: [i32])

                    let abstractRef = function.wasmRefCast(
                        describedInst, refType: ILType.wasmRef(.WasmStruct, nullability: false))

                    // 1. Exact descriptor with exact target (cast succeeds -> fallthrough)
                    let resultExact = function.wasmBuildBlockWithResults(
                        with: [] => [.wasmi32, ILType.wasmRef(.WasmAny, nullability: false)],
                        args: []
                    ) { blockLabel, _ in
                        let i32_100 = function.consti32(100)
                        let casted = function.wasmBranchOnCastDescEqFail(
                            abstractRef, descriptorRef: descriptorInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: true), nullability: false),
                            to: blockLabel, args: [i32_100])

                        #expect(b.type(of: casted[1]).wasmReferenceType?.kind.isExact == true)
                        let v = function.wasmStructGet(theStruct: casted[1], fieldIndex: 0)
                        return [v, abstractRef]
                    }
                    let v0 = resultExact[0]

                    // 2. Exact descriptor with inexact target (cast succeeds -> fallthrough)
                    let resultInexactWithExactDesc = function.wasmBuildBlockWithResults(
                        with: [] => [.wasmi32, ILType.wasmRef(.WasmAny, nullability: false)],
                        args: []
                    ) { blockLabel, _ in
                        let i32_100 = function.consti32(100)
                        let casted = function.wasmBranchOnCastDescEqFail(
                            abstractRef, descriptorRef: descriptorInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: false), nullability: false),
                            to: blockLabel, args: [i32_100])

                        #expect(b.type(of: casted[1]).wasmReferenceType?.kind.isExact == false)
                        let v = function.wasmStructGet(theStruct: casted[1], fieldIndex: 0)
                        return [v, abstractRef]
                    }
                    let v1 = resultInexactWithExactDesc[0]

                    // 3. Inexact descriptor with inexact target (cast succeeds -> fallthrough)
                    let inexactDesc = function.wasmRefCast(
                        descriptorInst,
                        refType: ILType.wasmRef(.Index(isExact: false), nullability: false),
                        typeDef: types[1]
                    )
                    #expect(b.type(of: inexactDesc).wasmReferenceType?.kind.isExact == false)

                    let resultInexactWithInexactDesc = function.wasmBuildBlockWithResults(
                        with: [] => [.wasmi32, ILType.wasmRef(.WasmAny, nullability: false)],
                        args: []
                    ) { blockLabel, _ in
                        let i32_100 = function.consti32(100)
                        let casted = function.wasmBranchOnCastDescEqFail(
                            abstractRef, descriptorRef: inexactDesc,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: false), nullability: false),
                            to: blockLabel, args: [i32_100])

                        #expect(b.type(of: casted[1]).wasmReferenceType?.kind.isExact == false)
                        let v = function.wasmStructGet(theStruct: casted[1], fieldIndex: 0)
                        return [v, abstractRef]
                    }
                    let v2 = resultInexactWithInexactDesc[0]

                    // 4. Cast fails -> branch taken to blockLabel
                    let otherDescInst = function.wasmStructNew(structType: types[1], fields: [f32])

                    let resultBranchTaken = function.wasmBuildBlockWithResults(
                        with: [] => [.wasmi32, ILType.wasmRef(.WasmAny, nullability: false)],
                        args: []
                    ) { blockLabel, _ in
                        let i32_100 = function.consti32(100)
                        let casted = function.wasmBranchOnCastDescEqFail(
                            abstractRef, descriptorRef: otherDescInst,
                            targetRefType: ILType.wasmRef(
                                .Index(isExact: true), nullability: false),
                            to: blockLabel, args: [i32_100])

                        let fallback = function.consti32(999)
                        return [fallback, casted[1]]
                    }
                    let v3 = resultBranchTaken[0]

                    let sum1 = function.wasmi32BinOp(v0, v1, binOpKind: .Add)
                    let sum2 = function.wasmi32BinOp(sum1, v2, binOpKind: .Add)
                    let sum = function.wasmi32BinOp(sum2, v3, binOpKind: .Add)
                    return [sum]
                }
            }
            let exports = module.loadExports()
            let res = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [res])
        }
        testForOutput(program: jsProg, runner: runner, outputString: "226\n")
    }

    @Test func testSplicingCustomDescriptorSubtypeIntoTypeGroup() throws {
        let fuzzer = makeMockFuzzer(config: config, environment: JavaScriptEnvironment())
        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            var splicePoint = -1

            b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)]
                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )

                splicePoint = b.indexOfNextInstruction()
                let describedSub = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(type: .wasmi32, mutability: true),
                        WasmStructTypeDescription.Field(
                            type: .wasmRef(.Index(), nullability: true), mutability: false),
                    ],
                    indexTypes: [descriptor],
                    superTypeDef: described
                )
                let descriptorSub = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    superTypeDef: descriptor,
                    describes: describedSub
                )
                return [described, descriptor, describedSub, descriptorSub]
            }

            let donor = b.finalize()

            let hostBuilder = fuzzer.makeBuilder()
            hostBuilder.wasmDefineTypeGroup(recursiveGenerator: {
                #expect(hostBuilder.splice(from: donor, at: splicePoint, mergeDataFlow: false))
            })
            _ = hostBuilder.finalize()
        }
    }

    @Test func testSplicingDownstreamConsumerOfCustomDescriptor() throws {
        let fuzzer = makeMockFuzzer(config: config, environment: JavaScriptEnvironment())
        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let types = b.wasmDefineTypeGroup {
                let described = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)]
                )
                let descriptor = b.wasmDefineStructType(
                    fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)],
                    describes: described
                )
                return [described, descriptor]
            }

            b.buildWasmModule { wasmModule in
                _ = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let i32 = function.consti32(42)
                    let descriptorInst = function.wasmStructNew(structType: types[1], fields: [i32])
                    _ = function.wasmStructNewDesc(
                        structType: types[0], descriptor: descriptorInst, fields: [i32])
                    return [i32]
                }
            }
            let splicePoint = b.indexOfNextInstruction() - 1

            let donor = b.finalize()

            let hostBuilder = fuzzer.makeBuilder()
            #expect(hostBuilder.splice(from: donor, at: splicePoint))
            _ = hostBuilder.finalize()
        }
    }
}
