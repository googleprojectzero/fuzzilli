// Copyright 2023 Google LLC
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

import XCTest
@testable import Fuzzilli

@discardableResult
func testExecuteScript(program: String, runner: JavaScriptExecutor) -> JavaScriptExecutor.Result {
    let result: JavaScriptExecutor.Result
    do {
        result = try runner.executeScript(program)
    } catch {
        fatalError("Could not execute Script")
    }
    return result
}

func testForOutput(program: String, runner: JavaScriptExecutor, outputString: String) {
    let result = testExecuteScript(program: program, runner: runner)
    XCTAssertEqual(result.output, outputString, "Error Output:\n" + result.error)
}

func testForErrorOutput(program: String, runner: JavaScriptExecutor, errorMessageContains errormsg: String) {
    let result = testExecuteScript(program: program, runner: runner)
    XCTAssert(result.output.contains(errormsg), "Error messages don't match, got:\n" + result.output)
}

class WasmSignatureConversionTests: XCTestCase {
    func testJsSignatureConversion() {
        XCTAssertEqual(ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1), (.wasmFuncRef, 1), (.wasmExternRef, 1)])), [.wasmi32] => .wasmi32)
        XCTAssertEqual(ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmf32, 1), (.wasmFuncRef, 1), (.wasmExternRef, 1)])), [.wasmf32] => .wasmi32)
    }
}

class WasmFoundationTests: XCTestCase {
    func testFunction() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: Signature(expects: [], returns: ILType.wasmi32)) { function, _ in
                let constVar = function.consti32(1338)
                function.wasmReturn(constVar)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64]), returns: .wasmi64)) { function, arg in
                let var64 = function.consti64(41)
                let added = function.wasmi64BinOp(var64, arg[0], binOpKind: WasmIntegerBinaryOpKind.Add)
                function.wasmReturn(added)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64, .wasmi64]), returns: .wasmi64)) { function, arg in
                let subbed = function.wasmi64BinOp(arg[0], arg[1], binOpKind: WasmIntegerBinaryOpKind.Sub)
                function.wasmReturn(subbed)
            }
        }

        let exports = module.loadExports()

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports)

        let num = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [num])

        let res2 = b.callMethod(module.getExportedMethod(at: 2), on: exports, withArgs: [res1, num])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n42\n41\n")
    }

    func testExportNaming() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        // This test tests whether re-exported imports and module defined globals are re-ordered from the typer.
        let wasmGlobali32: Variable = b.createWasmGlobal(value: .wasmi32(1337), isMutable: true)
        assert(b.type(of: wasmGlobali32) == .object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: WasmGlobalType(valueType: ILType.wasmi32, isMutable: true)))

        let wasmGlobalf32: Variable = b.createWasmGlobal(value: .wasmf32(42.0), isMutable: false)
        assert(b.type(of: wasmGlobalf32) == .object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: WasmGlobalType(valueType: ILType.wasmf32, isMutable: false)))

        let module = b.buildWasmModule { wasmModule in
            // Imports are always before internal globals, this breaks the logic if we add a global and then import a global.
            wasmModule.addWasmFunction(with: [] => .nothing) { fun, _  in
                // This load forces an import
                fun.wasmLoadGlobal(globalVariable: wasmGlobalf32)
            }
            wasmModule.addGlobal(wasmGlobal: .wasmi64(4141), isMutable: true)
            wasmModule.addWasmFunction(with: [] => .nothing) { fun, _  in
                // This load forces an import
                fun.wasmLoadGlobal(globalVariable: wasmGlobali32)
            }
        }

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1), WasmLifter.nameOfGlobal(2)]

        let exports = module.loadExports()

        assert(b.type(of: exports) == .object(withProperties: nameOfExportedGlobals, withMethods: ["w1", "w0"]))

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        // Now let's actually see what the re-exported values are and see that the types don't match with what the programbuilder will see.
        // TODO: Is this an issue? will the programbuilder still be queriable for variables? I think so, it is internally consistent within the module....
        let firstExport = b.getProperty(nameOfExportedGlobals[0], of: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: firstExport))])

        let secondExport = b.getProperty(nameOfExportedGlobals[1], of: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: secondExport))])

        let thirdExport = b.getProperty(nameOfExportedGlobals[2], of: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: thirdExport))])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n4141\n1337\n")
    }

    func testImports() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let functionA = b.buildPlainFunction(with: .parameters(.bigint)) { args in
            let varA = b.loadBigInt(1)
            let added = b.binary(varA, args[0], with: .Add)
            b.doReturn(added)
        }

        assert(b.type(of: functionA).signature == [.bigint] => .bigint)

        let functionB = b.buildArrowFunction(with: .parameters(.integer)) { args in
            let varB = b.loadInt(2)
            let subbed = b.binary(varB, args[0], with: .Sub)
            b.doReturn(subbed)
        }
        // We are unable to determine that .integer - .integer == .integer here as INT_MAX + 1 => float
        assert(b.type(of: functionB).signature == [.integer] => .number)

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                // Manually set the availableTypes here for testing
                let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionA).signature!, availableTypes: WeightedList([(.wasmi64, 1)]))
                assert(wasmSignature == [.wasmi64] => .wasmi64)
                let varA = function.wasmJsCall(function: functionA, withArgs: [args[0]], withWasmSignature: wasmSignature)!
                function.wasmReturn(varA)
            }

            wasmModule.addWasmFunction(with: [] => .wasmf32) { function, _ in
                // Manually set the availableTypes here for testing
                let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionB).signature!, availableTypes: WeightedList([(.wasmi32, 1), (.wasmf32, 1)]))
                assert(wasmSignature.parameters.count == 1)
                assert(wasmSignature.parameters[0] == .wasmi32 || wasmSignature.parameters[0] == .wasmf32)
                assert(wasmSignature.outputType == .wasmi32 || wasmSignature.outputType == .wasmf32)
                let varA = wasmSignature.parameters[0] == .wasmi32 ? function.consti32(1337) : function.constf32(1337)
                let varRet = function.wasmJsCall(function: functionB, withArgs: [varA], withWasmSignature: wasmSignature)!
                function.wasmReturn(varRet)
            }

            wasmModule.addWasmFunction(with: [] => .wasmf32) { function, _ in
                let varA = function.constf32(1337.1)
                let varRet = function.wasmJsCall(function: functionB, withArgs: [varA], withWasmSignature: [.wasmf32] => .wasmf32)!
                function.wasmReturn(varRet)
            }
        }

        let exports = module.loadExports()

        let val = b.loadBigInt(2)
        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [val])
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: exports)
        let res2 = b.callMethod(module.getExportedMethod(at: 2), on: exports)

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])
        // We do not control whether the JS function is imported with a floating point or an integer type, so the
        // fractional digits might be lost. Round the result to make the output predictable.
        let res2Rounded = b.callFunction(b.createNamedVariable(forBuiltin: "Math.round"), withArgs: [res2])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res2Rounded)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "3\n-1335\n-1335\n")
    }

    func testBasics() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([]), returns: .wasmi32)) { function, _ in
                let varA = function.consti32(42)
                function.wasmReturn(varA)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64]), returns: .wasmi64)) { function, arg in
                let varA = function.consti64(41)
                let added = function.wasmi64BinOp(varA, arg[0], binOpKind: .Add)
                function.wasmReturn(added)
            }
        }

        let exports = module.loadExports()

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        let integer = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [integer])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\n")
    }

    func testReassigns() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                let varA = function.consti64(1338)
                // reassign params[0] = varA
                function.wasmReassign(variable: params[0], to: varA)
                function.wasmReturn(params[0])
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                // reassign params[0] = params[0]
                function.wasmReassign(variable: params[0], to: params[0])
                function.wasmReturn(params[0])
            }

            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                let ctr = function.consti32(10)
                function.wasmBuildLoop(with: [] => .nothing) { label, args in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    let result = function.wasmi32BinOp(ctr, function.consti32(1), binOpKind: .Sub)
                    function.wasmReassign(variable: ctr, to: result)
                    // The backedge, loop if we are not at zero yet.
                    let isNotZero = function.wasmi32CompareOp(ctr, function.consti32(0), using: .Ne)
                    function.wasmBranchIf(isNotZero, to: label)
                }
                function.wasmReturn(ctr)
            }

            let tag = wasmModule.addTag(parameterTypes: [.wasmi32, .wasmi32])
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { _, _ in
                    function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123), function.consti32(456)])
                    function.WasmBuildLegacyCatch(tag: tag) { _, _, e in
                        // The exception values are e[0] = 123 and e[1] = 456.
                        function.wasmReassign(variable: e[0], to: e[1])
                        // The exception values should now be e[0] = 456, e[1] = 456.
                        function.wasmReturn(e[0])
                    }
                }
                function.wasmUnreachable()
            }
        }

        let exports = module.loadExports()

        let out = b.callMethod("w0", on: exports, withArgs: [b.loadBigInt(10)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out)])

        b.callMethod("w1", on: exports, withArgs: [b.loadBigInt(20)])

        let outLoop = b.callMethod("w2", on: exports, withArgs: [])
        b.callFunction(outputFunc, withArgs: [outLoop])

        let outCatchReassign = b.callMethod("w3", on: exports, withArgs: [])
        b.callFunction(outputFunc, withArgs: [outCatchReassign])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n0\n456\n")
    }

    func testGlobals() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmGlobali64: Variable = b.createWasmGlobal(value: .wasmi64(1337), isMutable: true)
        assert(b.type(of: wasmGlobali64) == .object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: WasmGlobalType(valueType: ILType.wasmi64, isMutable: true)))

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .wasmi64(1339), isMutable: true)


            // Function 0
            wasmModule.addWasmFunction(with: [] => .nothing) { function, _ in
                // This forces an import of the wasmGlobali64
                function.wasmLoadGlobal(globalVariable: wasmGlobali64)
            }

            // Function 1
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let varA = function.consti64(1338)
                let varB = function.consti64(4242)
                function.wasmStoreGlobal(globalVariable: global, to: varB)
                let global = function.wasmLoadGlobal(globalVariable: global)
                function.wasmStoreGlobal(globalVariable: wasmGlobali64, to: varA)
                function.wasmReturn(global)
            }

            // Function 2
            wasmModule.addWasmFunction(with: [] => .wasmf64) { function, _ in
                let globalValue = function.wasmLoadGlobal(globalVariable: wasmGlobali64)
                let result = function.reinterpreti64Asf64(globalValue)
                function.wasmReturn(result)
            }
        }

        let exports = module.loadExports()

        let _ = b.callMethod(module.getExportedMethod(at: 1), on: exports)
        let out = b.callMethod(module.getExportedMethod(at: 2), on: exports)

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1)]
        let nameOfExportedFunctions = [WasmLifter.nameOfFunction(0), WasmLifter.nameOfFunction(1), WasmLifter.nameOfFunction(2)]

        assert(b.type(of: exports) == .object(withProperties: nameOfExportedGlobals, withMethods: nameOfExportedFunctions))


        let value = b.getProperty("value", of: wasmGlobali64)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])

        let wg0 = b.getProperty(nameOfExportedGlobals[0], of: exports)
        let valueWg0 = b.getProperty("value", of: wg0)
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueWg0)])

        b.callFunction(outputFunc, withArgs: [out])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n4242\n6.61e-321\n")
    }

    func testTables() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let javaScriptTable = b.createWasmTable(elementType: .wasmExternRef, limits: Limits(min: 5, max: 25))

        let object = b.createObject(with: ["a": b.loadInt(41), "b": b.loadInt(42)])

        // Set a value into the table
        b.callMethod("set", on: javaScriptTable, withArgs: [b.loadInt(1), object])

        let module = b.buildWasmModule { wasmModule in
            let tableRef = wasmModule.addTable(elementType: .wasmExternRef, minSize: 2)

            wasmModule.addWasmFunction(with: [] => .wasmExternRef) { function, _ in
                let offset = function.consti32(0)
                var ref = function.wasmTableGet(tableRef: tableRef, idx: offset)
                let offset1 = function.consti32(1)
                function.wasmTableSet(tableRef: tableRef, idx: offset1, to: ref)
                ref = function.wasmTableGet(tableRef: tableRef, idx: offset1)
                let otherRef = function.wasmTableGet(tableRef: javaScriptTable, idx: offset1)
                function.wasmReturn(otherRef)
            }
        }

        let exports = module.loadExports()

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports)

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let json = b.createNamedVariable(forBuiltin: "JSON")
        b.callFunction(outputFunc, withArgs: [b.callMethod("stringify", on: json, withArgs: [res0])])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "{\"a\":41,\"b\":42}\n")
    }

    func testDefinedTables() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters()) { _ in
            b.doReturn(b.loadBigInt(11))
        }

        let module = b.buildWasmModule { wasmModule in
            let wasmFunction = wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, params in
                function.wasmReturn(function.wasmi32BinOp(params[0], function.consti32(1), binOpKind: .Add))
            }
            wasmModule.addTable(elementType: .wasmFuncRef, minSize: 10, definedEntryIndices: [0, 1], definedEntryValues: [wasmFunction, jsFunction])
        }

        let exports = module.loadExports()

        let table = b.getProperty("wt0", of: exports)

        let tableElement0 = b.callMethod("get", on: table, withArgs: [b.loadInt(0)])
        let tableElement1 = b.callMethod("get", on: table, withArgs: [b.loadInt(1)])

        let output0 = b.callFunction(tableElement0, withArgs: [b.loadInt(42)])
        let output1 = b.callFunction(tableElement1, withArgs: [])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [output0])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: output1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "43\n11\n")
    }

    // Test every memory testcase for both memory32 and memory64.

    func importedMemoryTestCase(isMemory64: Bool) throws {
        let runner = isMemory64 ? try GetJavaScriptExecutorOrSkipTest(type: .user, withArguments: ["--experimental-wasm-memory64"])
                                : try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmMemory: Variable = b.createWasmMemory(minPages: 10, maxPages: 20, isMemory64: isMemory64)
        assert(b.type(of: wasmMemory) == .wasmMemory(limits: Limits(min: 10, max: 20), isShared: false, isMemory64: isMemory64))

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let value = function.consti32(1337)
                let offset = isMemory64 ? function.consti64(10) : function.consti32(10)
                function.wasmMemoryStore(memory: wasmMemory, dynamicOffset: offset, value: value, storeType: .I32StoreMem, staticOffset: 0)
                let val = function.wasmMemoryLoad(memory: wasmMemory, dynamicOffset: offset, loadType: .I64LoadMem, staticOffset: 0)
                function.wasmReturn(val)
            }
        }

        let viewBuiltin = b.createNamedVariable(forBuiltin: "DataView")
        assert(b.type(of: b.getProperty("buffer", of: wasmMemory)) == (.jsArrayBuffer | .jsSharedArrayBuffer))
        let view = b.construct(viewBuiltin, withArgs: [b.getProperty("buffer", of: wasmMemory)])

        // Read the value of the memory.
        let value = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let exports = module.loadExports()

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports)

        let valueAfter = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueAfter)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1337\n0\n1337\n")
    }

    func testImportedMemory32() throws {
        try importedMemoryTestCase(isMemory64: false)
    }

    func testImportedMemory64() throws {
        try importedMemoryTestCase(isMemory64: true)
    }

    func defineMemory(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: isMemory64)

            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                let value = function.consti64(1337)
                let storeOffset = isMemory64 ? function.consti64(8) : function.consti32(8)
                function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: .I64StoreMem, staticOffset: 2)
                let loadOffset = isMemory64 ? function.consti64(10) : function.consti32(10)
                let val = function.wasmMemoryLoad(memory: memory, dynamicOffset: loadOffset, loadType: .I32LoadMem, staticOffset: 0)
                function.wasmReturn(val)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForOutput(program: jsProg, runner: runner, outputString: "1337\n")
    }

    func testDefineMemory32() throws {
        try defineMemory(isMemory64: false)
    }

    func testDefineMemory64() throws {
        try defineMemory(isMemory64: true)
    }

    func testMemory64Index() throws{
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: true)

            wasmModule.addWasmFunction(with: [] => .nothing) { function, _ in
                let value = function.consti64(1337)
                let storeOffset = function.consti64(1 << 32)
                function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: .I64StoreMem, staticOffset: 2)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForErrorOutput(program: jsProg, runner: runner, errorMessageContains: "RuntimeError: memory access out of bounds")
    }

    // This test doesn't check the result of the Wasm loads, just exectues them.
    func allMemoryLoadTypesExecution(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 1, maxPages: 10, isMemory64: isMemory64)

            // Create a Wasm function for every memory load type.
            for loadType in WasmMemoryLoadType.allCases {
                wasmModule.addWasmFunction(with: [] => loadType.numberType()) { function, _ in
                    let loadOffset = isMemory64 ? function.consti64(9) : function.consti32(9)
                    let val = function.wasmMemoryLoad(memory: memory, dynamicOffset: loadOffset, loadType: loadType, staticOffset: 0)
                    function.wasmReturn(val)
                }
            }
        }

        for idx in 0..<WasmMemoryLoadType.allCases.count {
            let res = b.callMethod(module.getExportedMethod(at: idx), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])
        }
        let jsProg = fuzzer.lifter.lift(b.finalize())
        testExecuteScript(program: jsProg, runner: runner)
    }

    func testAllMemoryLoadTypesExecutionOnMemory32() throws {
        try allMemoryLoadTypesExecution(isMemory64: false)
    }

    func testAllMemoryLoadTypesExecutionOnMemory64() throws {
        try allMemoryLoadTypesExecution(isMemory64: true)
    }

    // This test doesn't check the result of the Wasm stores, just exectues them.
    func allMemoryStoreTypesExecution(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 2, isMemory64: isMemory64)
            // Create a Wasm function for every memory load type.
            for storeType in WasmMemoryStoreType.allCases {
                wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                    let storeOffset = isMemory64 ? function.consti64(13) : function.consti32(13)
                    let value = switch storeType.numberType() {
                        case .wasmi32: function.consti32(8)
                        case .wasmi64: function.consti64(8)
                        case .wasmf32: function.constf32(8.4)
                        case .wasmf64: function.constf64(8.4)
                        default: fatalError("Non-existent value to be stored")
                    }
                    function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: storeType, staticOffset: 2)
                }
            }
        }

        for idx in 0..<WasmMemoryStoreType.allCases.count {
            let res = b.callMethod(module.getExportedMethod(at: idx), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])
        }
        let jsProg = fuzzer.lifter.lift(b.finalize())
        testExecuteScript(program: jsProg, runner: runner)
    }

    func testAllMemoryStoreTypesExecutionOnMemory32() throws {
        try allMemoryStoreTypesExecution(isMemory64: false)
    }

    func testAllMemoryStoreTypesExecutionOnMemory64() throws {
        try allMemoryStoreTypesExecution(isMemory64: true)
    }

    func wasmSimdLoad(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: isMemory64)

            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                value: function.consti64(3), storeType: .I64StoreMem, staticOffset: 0)
                function.wasmMemoryStore(memory: memory, dynamicOffset: const(8),
                value: function.consti64(6), storeType: .I64StoreMem, staticOffset: 0)

                let val = function.wasmSimdLoad(kind: .LoadS128, memory: memory,
                    dynamicOffset: const(0), staticOffset: 0)
                let sum = function.wasmi64BinOp(function.wasmI64x2ExtractLane(val, 0),
                    function.wasmI64x2ExtractLane(val, 1), binOpKind: .Add)
                function.wasmReturn(sum)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForOutput(program: jsProg, runner: runner, outputString: "9\n")
    }

    func testWasmSimdLoadOnMemory32() throws {
        try wasmSimdLoad(isMemory64: false)
    }

    func testWasmSimdLoadOnMemory64() throws {
        try wasmSimdLoad(isMemory64: true)
    }

    func testLoops() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                // Test if we can break from this block
                // We should expect to have executed the first wasmReassign which sets marker to 11
                let marker = function.consti64(10)
                function.wasmBuildBlock(with: [] => .nothing, args: []) { label, args in
                    let a = function.consti64(11)
                    function.wasmReassign(variable: marker, to: a)
                    function.wasmBuildBlock(with: [] => .nothing, args: []) { _, _ in
                        // TODO: write codegenerators that use this somehow.
                        // Break to the outer block, this verifies that we can break out of nested block
                        function.wasmBranch(to: label)
                    }
                    let b = function.consti64(12)
                    function.wasmReassign(variable: marker, to: b)
                }

                // Do a simple loop that adds 2 to this variable 10 times.
                let variable = function.consti64(1337)
                let ctr = function.consti32(0)
                let max = function.consti32(10)
                let one = function.consti32(1)

                function.wasmBuildLoop(with: [] => .nothing) { label, args in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    let result = function.wasmi32BinOp(ctr, one, binOpKind: .Add)
                    let varUpdate = function.wasmi64BinOp(variable, function.consti64(2), binOpKind: .Add)
                    function.wasmReassign(variable: ctr, to: result)
                    function.wasmReassign(variable: variable, to: varUpdate)
                    let comp = function.wasmi32CompareOp(ctr, max, using: .Lt_s)
                    function.wasmBranchIf(comp, to: label)
                }

                // Now combine the result of the break and the loop into one and return it.
                // This should return 1337 + 20 == 1357, 1357 + 11 = 1368
                let result = function.wasmi64BinOp(variable, marker, binOpKind: .Add)

                function.wasmReturn(result)
            }
        }

        let exports = module.loadExports()

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1368\n")
    }

    func testLoopWithParametersAndResult() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                let loopResult = function.wasmBuildLoop(with: [.wasmi32, .wasmi32] => .wasmi32, args: args) { loopLabel, loopArgs in
                    let incFirst = function.wasmi32BinOp(loopArgs[0], function.consti32(1), binOpKind: .Add)
                    let incSecond = function.wasmi32BinOp(loopArgs[1], function.consti32(2), binOpKind: .Add)
                    let condition = function.wasmi32CompareOp(incFirst, incSecond, using: .Gt_s)
                    function.wasmBranchIf(condition, to: loopLabel, args: [incFirst, incSecond])
                    return incFirst
                }
                function.wasmReturn(loopResult)
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(10), b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "20\n")
    }

    func testIfs() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let variable = args[0]
                let condVariable = function.consti32(10);
                let result = function.consti32(0);

                let comp = function.wasmi32CompareOp(variable, condVariable, using: .Lt_s)

                function.wasmBuildIfElse(comp, ifBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Add)
                    function.wasmReassign(variable: result, to: tmp)
                }, elseBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Sub)
                    function.wasmReassign(variable: result, to: tmp)
                })

                function.wasmReturn(result)
            }
        }

        let exports = module.loadExports()

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1337)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1327\n")
    }

    func testIfElseWithParameters() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => .wasmi64) { function, args in
                let inputs = [args[1], function.consti64(3)]
                function.wasmBuildIfElse(args[0], signature: [.wasmi64, .wasmi64] => .nothing, args: inputs) { label, ifArgs in
                    function.wasmReturn(ifArgs[0])
                } elseBody: {label, ifArgs in
                    function.wasmReturn(function.wasmi64BinOp(ifArgs[0], ifArgs[1], binOpKind: .Shl))
                }
                function.wasmUnreachable()
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1), b.loadBigInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0), b.loadBigInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n8\n")
    }

    func testIfElseLabels() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                function.wasmBuildIfElse(args[0], signature: [.wasmi32] => .nothing, args: [args[1]]) { ifLabel, ifArgs in
                    function.wasmBranchIf(ifArgs[0], to: ifLabel)
                    function.wasmReturn(function.consti32(100))
                } elseBody: {elseLabel, ifArgs in
                    function.wasmBranchIf(ifArgs[0], to: elseLabel)
                    function.wasmReturn(function.consti32(200))
                }
                function.wasmReturn(function.consti32(300))
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        let runAndPrint = {args in
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: args)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        }

        runAndPrint([b.loadInt(1), b.loadInt(0)]) // 100
        runAndPrint([b.loadInt(1), b.loadInt(1)]) // 300
        runAndPrint([b.loadInt(0), b.loadInt(0)]) // 200
        runAndPrint([b.loadInt(0), b.loadInt(1)]) // 300

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "100\n300\n200\n300\n")
    }

    func testIfElseWithResult() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi64) { function, args in
                let blockResult = function.wasmBuildIfElseWithResult(args[0], signature: [] => .wasmi64, args: []) {label, args in
                    return function.consti64(123)
                } elseBody: {label, args in
                    return function.consti64(321)
                }
                function.wasmReturn(blockResult)
            }
        }
        let exports = module.loadExports()
        let outTrue = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: outTrue)])
        let outFalse = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: outFalse)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "123\n321\n")
    }

    func testTryVoid() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    function.wasmReturn(function.consti64(42))
                }
                function.wasmUnreachable()
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testTryCatchAll() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        // JS function that throws.
        let functionA = b.buildPlainFunction(with: .parameters()) { _ in
            b.throwException(b.loadInt(3))
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    // Manually set the availableTypes here for testing.
                    let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionA).signature!, availableTypes: WeightedList([]))
                    function.wasmJsCall(function: functionA, withArgs: [], withWasmSignature: wasmSignature)
                    function.wasmUnreachable()
                } catchAllBody: { label in
                    function.wasmReturn(function.consti64(123))
                }
                function.wasmUnreachable()
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "123\n")
    }

    func testTryCatchJSException() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        // JS function that throws.
        let functionA = b.buildPlainFunction(with: .parameters()) { _ in
            b.throwException(b.loadInt(3))
        }

        // Wrap the actual test in a "WebAssembly.JSTag !== undefined" to skip the test if not supported by the runner.
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let jstag = b.createWasmJSTag()
        let supportsJSTag = b.compare(jstag, with: b.loadUndefined(), using: .strictNotEqual)
        b.buildIfElse(supportsJSTag) {
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                        XCTAssert(b.type(of: label).Is(.anyLabel))
                        let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionA).signature!, availableTypes: WeightedList([]))
                        function.wasmJsCall(function: functionA, withArgs: [], withWasmSignature: wasmSignature)
                        function.wasmUnreachable()
                        function.WasmBuildLegacyCatch(tag: jstag) { label, exception, args in
                            function.wasmReturn(function.consti64(123))
                        }
                    } catchAllBody: { label in
                        function.wasmUnreachable()
                    }
                    function.wasmUnreachable()
                }
            }
            let exports = module.loadExports()
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        } elseBody: {
            // WebAssembly.JSTag is not supported by the runner, just create the expected result.
            b.callFunction(outputFunc, withArgs: [b.loadString("123")])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "123\n")
    }

    func testTryCatchWasmException() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let throwTag = b.createWasmTag(parameterTypes: [Parameter.wasmi64, Parameter.wasmi32])
        let otherTag = b.createWasmTag(parameterTypes: [Parameter.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            /* Pseudo-code:
                function () -> i64 {
                    try {
                        throw throwTag(123, 234);
                        unreachable();
                    } catch (exception: otherTag) {
                        unreachable();
                    } catch (exception: throwTag) {
                        return exception.0 + exception.1;
                    } catch (...) {
                        unreachable();
                    }
                }
            */
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    function.WasmBuildThrow(tag: throwTag, inputs: [function.consti64(123), function.consti32(234)])
                    function.wasmUnreachable()
                    function.WasmBuildLegacyCatch(tag: otherTag) { label, exception, args in
                        function.wasmUnreachable()
                    }
                    function.WasmBuildLegacyCatch(tag: throwTag) { label, exception, args in
                        let result = function.wasmi64BinOp(args[0], function.extendi32Toi64(args[1], isSigned: true), binOpKind: .Add)
                        function.wasmReturn(result)
                    }
                } catchAllBody: { label in
                    function.wasmUnreachable()
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "357\n")
    }

    func testBranchInCatch() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { tryLabel, _ in
                    function.WasmBuildThrow(tag: tag, inputs: [])
                    function.WasmBuildLegacyCatch(tag: tag) { catchLabel, exceptionLabel, args in
                        function.wasmBranch(to: catchLabel)
                    }
                }
                function.wasmReturn(function.consti32(42))
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testBranchInCatchAll() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildBlock(with: [] => .nothing, args: []) { blockLabel, _ in
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { tryLabel, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [])
                    } catchAllBody: { label in
                        function.wasmBranch(to: blockLabel)
                    }
                    function.wasmReturn(function.consti32(-1))
                }
                function.wasmReturn(function.consti32(42))
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }


    func testTryCatchWasmExceptionNominal() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let parameterTypes = [Parameter.wasmi32]
        let importedTag = b.createWasmTag(parameterTypes: parameterTypes)
        let module = b.buildWasmModule { wasmModule in
            let definedTag = wasmModule.addTag(parameterTypes: parameterTypes)

            /* Pseudo-code:
                function (param: i32) -> i32 {
                    try {
                        if (param) {
                            throw definedTag(param);
                        } else {
                            throw importedTag(123);
                        }
                        unreachable();
                    } catch (exception: importedTag) {
                        return exception.0 + 1;
                    } catch (exception: definedTag) {
                        return exception.0 + 4;
                    } catch (...) {
                        unreachable();
                    }
                    unreachable();
                }
            */
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, param in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    function.wasmBuildIfElse(param[0]) {
                        function.WasmBuildThrow(tag: definedTag, inputs: [param[0]])
                    } elseBody: {
                        function.WasmBuildThrow(tag: importedTag, inputs: [function.consti32(123)])
                    }
                    function.wasmUnreachable()
                    function.WasmBuildLegacyCatch(tag: importedTag) { label, exception, args in
                        function.wasmReturn(function.wasmi32BinOp(args[0], function.consti32(1), binOpKind: .Add))
                    }
                    function.WasmBuildLegacyCatch(tag: definedTag) { label, exception, args in
                        function.wasmReturn(function.wasmi32BinOp(args[0], function.consti32(4), binOpKind: .Add))
                    }
                } catchAllBody: { label in
                    function.wasmUnreachable()
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmFct = module.getExportedMethod(at: 0)
        // Passing in 0 takes the else branch that throws 123 with the importedTag.
        // The catch block for the importedTag then adds 1 and JS prints 124.
        let wasmOut = b.callMethod(wasmFct, on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        // Passing 42 takes the true branch that throws 42 with the definedTag.
        // The catch block for the definedTag adds 4 and JS prints 46.
        let wasmOut2 = b.callMethod(wasmFct, on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "124\n46\n")
    }

    func testTryWithBlockParameters() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [Parameter.wasmi64, Parameter.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let argI32 = function.consti32(123)
                let argI64 = function.consti64(321)
                function.wasmBuildLegacyTry(with: [.wasmi64, .wasmi32] => .nothing, args: [argI64, argI32]) { label, args in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    XCTAssert(b.type(of: args[0]).Is(.wasmi64))
                    XCTAssert(b.type(of: args[1]).Is(.wasmi32))
                    function.WasmBuildThrow(tag: tag, inputs: args)
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        let result = function.wasmi64BinOp(args[0], function.extendi32Toi64(args[1], isSigned: true), binOpKind: .Add)
                        function.wasmReturn(result)
                    }
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "444\n")
    }

    func testTryWithBlockParametersAndResult() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tagVoid = b.createWasmTag(parameterTypes: [])
        let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])
        let tagi32Other = b.createWasmTag(parameterTypes: [.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let result = function.wasmBuildLegacyTryWithResult(with: [.wasmi32] => .wasmi32, args: args, body: { label, args in
                    function.wasmBuildIfElse(function.wasmi32EqualZero(args[0])) {
                        function.WasmBuildThrow(tag: tagVoid, inputs: [])
                    }
                    function.wasmBuildIfElse(function.wasmi32CompareOp(args[0], function.consti32(1), using: .Eq)) {
                        function.WasmBuildThrow(tag: tagi32, inputs: [function.consti32(100)])
                    }
                    function.wasmBuildIfElse(function.wasmi32CompareOp(args[0], function.consti32(2), using: .Eq)) {
                        function.WasmBuildThrow(tag: tagi32Other, inputs: [function.consti32(200)])
                    }
                    return args[0]
                }, catchClauses: [
                    (tagi32, {label, exception, args in
                        return args[0]
                    }),
                    (tagi32Other, {label, exception, args in
                        let value = function.wasmi32BinOp(args[0], function.consti32(2), binOpKind: .Add)
                        function.wasmBranch(to: label, args: [value])
                        return function.consti32(-1)
                    }),
                ], catchAllBody: { _ in
                    return function.consti32(900)
                })
                function.wasmReturn(result)
            }
        }
        let exports = module.loadExports()

        var expectedString = ""
        // Note that in the comments below "returns" means that this will be passed on as a result
        // to the EndTry block. At the end of the wasm function it performs a wasm return of the
        // result of the EndTry.
        for (input, expected) in [
                // input 0 throws tagVoid which is not caught, so the catchAllBody returns 900.
                (0, 900),
                // input 1 throws tagi32(100) which is caught by a catch clause that returns the
                // tag argument.
                (1, 100),
                // input 2 throws tagi32Other(200) which is caught by a catch clause that branches
                // to the end of its block adding 2 to the tag argument.
                (2, 202),
                // input 3 doesn't throw anything, the try body returns the value directly, meaning
                // the value "falls-through" from the try body to the endTry operation.
                (3, 3)] {
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(Int64(input))])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
            expectedString += "\(expected)\n"
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: expectedString)
    }

    func testTryDelegate() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [Parameter.wasmi32])
        let module = b.buildWasmModule { wasmModule in

            /* Pseudo-code:
                function () -> i32 {
                    tryLabel: try {
                        unusedLabel: try {
                            let val = 42;
                            try {
                                throw tag(val);
                            } delegate tryLabel; // The throw above will be "forwarded" to the tryLabel block.
                            unreachable();
                        } catch(...) {
                            unreachable; // The delegate will skip this catch.
                        }
                    } catch (exception: tag) {
                        return exeption.0; // returns 42.
                    }
                    unreachable();
                }
            */
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { tryLabel, _ in
                    // Even though we have a try-catch_all, the delegate "skips" this catch block. The delegate acts as
                    // if the exception was thrown by the block whose label is passed into it.
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { unusedLabel, _ in
                        let val = function.consti32(42)
                        function.wasmBuildLegacyTryDelegate(with: [.wasmi32] => .nothing, args: [val], body: {label, args in
                            function.WasmBuildThrow(tag: tag, inputs: args)
                        }, delegate: tryLabel)
                        function.wasmUnreachable()
                    } catchAllBody: { label in
                        function.wasmUnreachable()
                    }
                    function.wasmUnreachable()
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        function.wasmReturn(args[0])
                    }
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testTryCatchRethrow() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [Parameter.wasmi32])
        let module = b.buildWasmModule { wasmModule in

            /* Pseudo-code:
                function () -> i32 {
                    try {
                        try {
                            throw tag(123);
                            unreachable();
                        } catch (exception: tag) {
                            rethrow exception;
                        }
                    } catch (exception: tag) {
                        return exception.0; // returns 123;
                    }
                    unreachable();
                }
            */
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123)])
                        function.wasmUnreachable()
                        function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                            function.wasmBuildRethrow(exception)
                        }
                    }
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        function.wasmReturn(args[0])
                    }
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "123\n")
    }

    func testTryCatchRethrowOuter() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [Parameter.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            /* Pseudo-code:
                function () -> i32 {
                    try {
                        try {
                            throw tag(123);
                        } catch (outerException: tag) {
                            try {
                                throw tag(456);
                            } catch (innerException: tag) {
                                rethrow outerException;
                            }
                        }
                    } catch (exception: tag) {
                        return exception.0; // returns 123
                    }
                }
            */
            wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123)])
                        function.WasmBuildLegacyCatch(tag: tag) { label, outerException, args in
                            function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                                function.WasmBuildThrow(tag: tag, inputs: [function.consti32(456)])
                                function.wasmUnreachable()
                                function.WasmBuildLegacyCatch(tag: tag) { label, innerException, args in
                                    // There are two "active" exceptions:
                                    // outerException: [123: i32]
                                    // innerException: [456: i32]
                                    function.wasmBuildRethrow(outerException)
                                }
                            }
                        }
                    }
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        function.wasmReturn(args[0])
                    }
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "123\n")
    }

    func testBlockWithParameters() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmf64) { function, _ in
                let argI32 = function.consti32(12345)
                let argF64 = function.constf64(543.21)
                function.wasmBuildBlock(with: [.wasmi32, .wasmf64] => .nothing, args: [argI32, argF64]) { blockLabel, args in
                    assert(args.count == 2)
                    let result = function.wasmf64BinOp(function.converti32Tof64(args[0], isSigned: true), args[1], binOpKind: .Add)
                    function.wasmReturn(result)
                }
                function.wasmUnreachable()
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "12888.21\n")
    }

    func testBlockWithResult() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let blockResult = function.wasmBuildBlockWithResult(with: [.wasmi32] => .wasmi64, args: [function.consti32(12345)]) { blockLabel, args in
                    return function.extendi32Toi64(args[0], isSigned: true)
                }
                function.wasmReturn(blockResult)
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "12345\n")
    }

    func testBranchWithParameter() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let blockResult = function.wasmBuildBlockWithResult(with: [.wasmi32] => .wasmi32, args: args) { blockLabel, blockArgs in
                    // TODO(mliedtke): A branch to the function end should also be allowed but
                    // unfortunately a function doesn't have a label in FuzzIL, yet.
                    function.wasmBranchIf(blockArgs[0], to: blockLabel, args: [function.wasmi32BinOp(blockArgs[0], args[0], binOpKind: .Add)])
                    function.wasmBranch(to: blockLabel, args: [function.consti32(12345)])
                    return function.consti32(-1)
                }
                function.wasmReturn(blockResult)
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut2 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "84\n12345\n")
    }

    func testUnreachable() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                function.wasmUnreachable()
            }
        }

        let exports = module.loadExports()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.buildTryCatchFinally {
            b.callMethod(module.getExportedMethod(at: 0), on: exports)
            b.callFunction(outputFunc, withArgs: [b.loadString("Not reached")])
        } catchBody: { e in
            b.callFunction(outputFunc, withArgs: [b.loadString("Caught wasm trap")])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "Caught wasm trap\n")
    }

    func testSelect() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi64) { function, args in
                function.wasmReturn(function.wasmSelect(type: .wasmi64, on: args[0],
                    trueValue: function.consti64(123), falseValue: function.consti64(321)))
            }

            wasmModule.addWasmFunction(with: [.wasmi32, .wasmExternRef, .wasmExternRef] => .wasmExternRef) { function, args in
                function.wasmReturn(function.wasmSelect(type: .wasmExternRef, on: args[0], trueValue: args[1], falseValue: args[2]))
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        // Select with i64.
        var wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        // Select with externref.
        let hello = b.loadString("Hello")
        let world = b.loadString("World")
        wasmOut = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [b.loadInt(1), hello, world])
        b.callFunction(outputFunc, withArgs: [wasmOut])
        wasmOut = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [b.loadInt(0), hello, world])
        b.callFunction(outputFunc, withArgs: [wasmOut])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "321\n123\nHello\nWorld\n")
    }
}

class WasmNumericalTests: XCTestCase {
    // Integer BinaryOperations
    func testi64BinaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmIntegerBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => .wasmi64) { function, args in
                    let result = function.wasmi64BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        let addFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Mul.rawValue))
        let divSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_s.rawValue))
        let divUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_u.rawValue))
        let remSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_s.rawValue))
        let remUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_u.rawValue))
        let andFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.And.rawValue))
        let orFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Or.rawValue))
        let xorFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Xor.rawValue))
        let shlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shl.rawValue))
        let shrSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_s.rawValue))
        let shrUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_u.rawValue))
        let rotlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotl.rawValue))
        let rotrFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotr.rawValue))

        // 1n + 1n = 2n
        ExpectEq(addFunc, [b.loadBigInt(1), b.loadBigInt(1)], "2")

        // 1n - 1n = 0n
        ExpectEq(subFunc, [b.loadBigInt(1), b.loadBigInt(1)], "0")

        // 2n * 4n = 8n
        ExpectEq(mulFunc, [b.loadBigInt(2), b.loadBigInt(4)], "8")

        // -8n / -4n = 2n
        ExpectEq(divSFunc, [b.loadBigInt(-8), b.loadBigInt(-4)], "2")

        // This -16 will be represented by a big unsigned number and then dividing it by 4 should be 4611686018427387900n
        // -16n / 4n = 4611686018427387900n
        ExpectEq(divUFunc, [b.loadBigInt(-16), b.loadBigInt(4)], "4611686018427387900")

        // -17n % 4n = -1n
        ExpectEq(remSFunc, [b.loadBigInt(-17), b.loadBigInt(4)], "-1")

        // -17n (which is 18446744073709551599n) % 4n = 3n
        ExpectEq(remUFunc, [b.loadBigInt(-17), b.loadBigInt(4)], "3")

        // 1n & 3n = 1n
        ExpectEq(andFunc, [b.loadBigInt(1), b.loadBigInt(3)], "1")

        // 1n | 4n = 5n
        ExpectEq(orFunc, [b.loadBigInt(1), b.loadBigInt(4)], "5")

        // 3n ^ 5n = 6n
        ExpectEq(xorFunc, [b.loadBigInt(3), b.loadBigInt(5)], "6")

        // 3n << 5n = 96n
        ExpectEq(shlFunc, [b.loadBigInt(3), b.loadBigInt(5)], "96")

        // -3n >> 1n = -2n
        ExpectEq(shrSFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "-2")

        // -3n (18446744073709551613n) >> 1n = 9223372036854775806n
        ExpectEq(shrUFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "9223372036854775806")

        // -3n rotl 1n = -5n
        ExpectEq(rotlFunc, [b.loadBigInt(-3), b.loadBigInt(1)], "-5")

        // 1n rotr 1n = -9223372036854775808n
        ExpectEq(rotrFunc, [b.loadBigInt(1), b.loadBigInt(1)], "-9223372036854775808")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32BinaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmIntegerBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Mul.rawValue))
        let divSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_s.rawValue))
        let divUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Div_u.rawValue))
        let remSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_s.rawValue))
        let remUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rem_u.rawValue))
        let andFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.And.rawValue))
        let orFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Or.rawValue))
        let xorFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Xor.rawValue))
        let shlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shl.rawValue))
        let shrSFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_s.rawValue))
        let shrUFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Shr_u.rawValue))
        let rotlFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotl.rawValue))
        let rotrFunc = module.getExportedMethod(at: Int(WasmIntegerBinaryOpKind.Rotr.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1 = 2
        ExpectEq(addFunc, [b.loadInt(1), b.loadInt(1)], "2")

        // 1 - 1 = 0
        ExpectEq(subFunc, [b.loadInt(1), b.loadInt(1)], "0")

        // 2 * 4 = 8
        ExpectEq(mulFunc, [b.loadInt(2), b.loadInt(4)], "8")

        // -8 / -4 = 2
        ExpectEq(divSFunc, [b.loadInt(-8), b.loadInt(-4)], "2")

        // -16 / 4 = 1073741820
        ExpectEq(divUFunc, [b.loadInt(-16), b.loadInt(4)], "1073741820")

        // -17 % 4 = -1
        ExpectEq(remSFunc, [b.loadInt(-17), b.loadInt(4)], "-1")

        // -17 % 4 = 3
        ExpectEq(remUFunc, [b.loadInt(-17), b.loadInt(4)], "3")

        // 1 & 3 = 1
        ExpectEq(andFunc, [b.loadInt(1), b.loadInt(3)], "1")

        // 1 | 4 = 5
        ExpectEq(orFunc, [b.loadInt(1), b.loadInt(4)], "5")

        // 3 ^ 5 = 6
        ExpectEq(xorFunc, [b.loadInt(3), b.loadInt(5)], "6")

        // 3 << 5 = 96
        ExpectEq(shlFunc, [b.loadInt(3), b.loadInt(5)], "96")

        // -3 >> 1 = -2
        ExpectEq(shrSFunc, [b.loadInt(-3), b.loadInt(1)], "-2")

        // -3 >> 1 = 2147483646
        ExpectEq(shrUFunc, [b.loadInt(-3), b.loadInt(1)], "2147483646")

        // -3 rotl 1 = -5
        ExpectEq(rotlFunc, [b.loadInt(-3), b.loadInt(1)], "-5")

        // 1 rotr 1 = -2147483648
        ExpectEq(rotrFunc, [b.loadInt(1), b.loadInt(1)], "-2147483648")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Binary Operations
    func testf64BinaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmFloatBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => .wasmf64) { function, args in
                    let result = function.wasmf64BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Mul.rawValue))
        let divFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Div.rawValue))
        let minFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Min.rawValue))
        let maxFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Max.rawValue))
        let copysignFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Copysign.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1.05 = 2.05
        ExpectEq(addFunc, [b.loadFloat(1), b.loadFloat(1.05)], "2.05")

        // 1.05 - 1 = 0.050000000000000044
        ExpectEq(subFunc, [b.loadFloat(1.05), b.loadFloat(1)], "0.050000000000000044")

        // 2.5 * 4 = 10
        ExpectEq(mulFunc, [b.loadFloat(2.5), b.loadFloat(4)], "10")

        // -11 / -2.5 = 4.4
        ExpectEq(divFunc, [b.loadFloat(-11), b.loadFloat(-2.5)], "4.4")

        // Min(-3.1, 4.25) = -3.1
        ExpectEq(minFunc, [b.loadFloat(-3.1), b.loadFloat(4.25)], "-3.1")

        // Max(5.3, 5.31) = 5.31
        ExpectEq(maxFunc, [b.loadFloat(5.3), b.loadFloat(5.31)], "5.31")

        // Copies the sign of the second number, onto the first number.
        // CopySign(-3.1, 4.2) = 3.1
        ExpectEq(copysignFunc, [b.loadFloat(-3.1), b.loadFloat(4.2)], "3.1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32BinaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per binary operator.
        let module = b.buildWasmModule { wasmModule in
            for binOp in WasmFloatBinaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => .wasmf32) { function, args in
                    let result = function.wasmf32BinOp(args[0], args[1], binOpKind: binOp)
                    function.wasmReturn(result)
                }
            }
        }

        let addFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Add.rawValue))
        let subFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Sub.rawValue))
        let mulFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Mul.rawValue))
        let divFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Div.rawValue))
        let minFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Min.rawValue))
        let maxFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Max.rawValue))
        let copysignFunc = module.getExportedMethod(at: Int(WasmFloatBinaryOpKind.Copysign.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 + 1.05 = 2.049999952316284
        ExpectEq(addFunc, [b.loadFloat(1), b.loadFloat(1.05)], "2.049999952316284")

        // 1.05 - 1 = 0.04999995231628418
        ExpectEq(subFunc, [b.loadFloat(1.05), b.loadFloat(1)], "0.04999995231628418")

        // 2.5 * 4 = 10
        ExpectEq(mulFunc, [b.loadFloat(2.5), b.loadFloat(4)], "10")

        // -11 / -2.5 = 4.400000095367432
        ExpectEq(divFunc, [b.loadFloat(-11), b.loadFloat(-2.5)], "4.400000095367432")

        // Min(-3.1, 4.25) = -3.0999999046325684
        ExpectEq(minFunc, [b.loadFloat(-3.1), b.loadFloat(4.25)], "-3.0999999046325684")

        // Max(5.3, 5.31) = 5.309999942779541
        ExpectEq(maxFunc, [b.loadFloat(5.3), b.loadFloat(5.31)], "5.309999942779541")

        // Copies the sign of the second number, onto the first number.
        // CopySign(-3.1, 4.2) = 3.0999999046325684
        ExpectEq(copysignFunc, [b.loadFloat(-3.1), b.loadFloat(4.2)], "3.0999999046325684")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Integer Unary Operations
    func testi64UnaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmIntegerUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                    let result = function.wasmi64UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let clzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Clz.rawValue))
        let ctzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Ctz.rawValue))
        let popcntFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Popcnt.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Clz(1n) = 63n
        ExpectEq(clzFunc, [b.loadBigInt(1)], "63")

        // Ctz(2n) = 1n
        ExpectEq(ctzFunc, [b.loadBigInt(2)], "1")

        // Popcnt(130n) = 2n
        ExpectEq(popcntFunc, [b.loadBigInt(130)], "2")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32UnaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmIntegerUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let clzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Clz.rawValue))
        let ctzFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Ctz.rawValue))
        let popcntFunc = module.getExportedMethod(at: Int(WasmIntegerUnaryOpKind.Popcnt.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Clz(1) = 31
        ExpectEq(clzFunc, [b.loadInt(1)], "31")

        // Ctz(2) = 1
        ExpectEq(ctzFunc, [b.loadInt(2)], "1")

        // Popcnt(130) = 2
        ExpectEq(popcntFunc, [b.loadInt(130)], "2")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Unary Operations
    func testf64UnaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmFloatUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64] => .wasmf64) { function, args in
                    let result = function.wasmf64UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let absFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Abs.rawValue))
        let negFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Neg.rawValue))
        let ceilFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Ceil.rawValue))
        let floorFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Floor.rawValue))
        let truncFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Trunc.rawValue))
        let nearestFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Nearest.rawValue))
        let sqrtFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Sqrt.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Abs(-1.3) = 1.3
        ExpectEq(absFunc, [b.loadFloat(-1.3)], "1.3")

        // Neg(3.1) = -3.1
        ExpectEq(negFunc, [b.loadFloat(3.1)], "-3.1")

        // Ceil(3.1) = 4
        ExpectEq(ceilFunc, [b.loadFloat(3.1)], "4")

        // Floor(3.9) = 3
        ExpectEq(floorFunc, [b.loadFloat(3.9)], "3")

        // Trunc(3.6) = 3
        ExpectEq(truncFunc, [b.loadFloat(3.6)], "3")

        // Nearest(3.501) = 4
        ExpectEq(nearestFunc, [b.loadFloat(3.501)], "4")

        // Sqrt(9) = 3
        ExpectEq(sqrtFunc, [b.loadFloat(9)], "3")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32UnaryOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per unary operator.
        let module = b.buildWasmModule { wasmModule in
            for unOp in WasmFloatUnaryOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32] => .wasmf32) { function, args in
                    let result = function.wasmf32UnOp(args[0], unOpKind: unOp)
                    function.wasmReturn(result)
                }
            }
        }

        let absFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Abs.rawValue))
        let negFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Neg.rawValue))
        let ceilFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Ceil.rawValue))
        let floorFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Floor.rawValue))
        let truncFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Trunc.rawValue))
        let nearestFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Nearest.rawValue))
        let sqrtFunc = module.getExportedMethod(at: Int(WasmFloatUnaryOpKind.Sqrt.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // Abs(-1.3) = 1.2999999523162842
        ExpectEq(absFunc, [b.loadFloat(-1.3)], "1.2999999523162842")

        // Neg(3.1) = -3.0999999046325684
        ExpectEq(negFunc, [b.loadFloat(3.1)], "-3.0999999046325684")

        // Ceil(3.1) = 4
        ExpectEq(ceilFunc, [b.loadFloat(3.1)], "4")

        // Floor(3.9) = 3
        ExpectEq(floorFunc, [b.loadFloat(3.9)], "3")

        // Trunc(3.6) = 3
        ExpectEq(truncFunc, [b.loadFloat(3.6)], "3")

        // Nearest(3.501) = 4
        ExpectEq(nearestFunc, [b.loadFloat(3.501)], "4")

        // Sqrt(9) = 3
        ExpectEq(sqrtFunc, [b.loadFloat(9)], "3")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Integer Comparison Operations
    func testi64ComparisonOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmIntegerCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => .wasmi32) { function, args in
                    let result = function.wasmi64CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi32) { function, args in
                let result = function.wasmi64EqualZero(args[0])
                function.wasmReturn(result)
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ne.rawValue))
        let ltSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_s.rawValue))
        let ltUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_u.rawValue))
        let gtSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_s.rawValue))
        let gtUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_u.rawValue))
        let leSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_s.rawValue))
        let leUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_u.rawValue))
        let geSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_s.rawValue))
        let geUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_u.rawValue))

        // This function is added separately at the end above.
        let eqzFunc = module.getExportedMethod(at: WasmIntegerCompareOpKind.allCases.count)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1n == 2n = 0
        ExpectEq(eqFunc, [b.loadBigInt(1), b.loadBigInt(2)], "0")

        // 1n != 2n = 1
        ExpectEq(neFunc, [b.loadBigInt(1), b.loadBigInt(2)], "1")

        // -1n < 2n = 1
        ExpectEq(ltSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n < 2n = 0
        ExpectEq(ltUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // 2n < 2n = 0
        ExpectEq(ltUFunc, [b.loadBigInt(2), b.loadBigInt(2)], "0")

        // -1n > 2n = 0
        ExpectEq(gtSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n > 2n = 1
        ExpectEq(gtUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n <= 2n = 1
        ExpectEq(leSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n <= 2n = 0
        ExpectEq(leUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n >= 2n = 0
        ExpectEq(geSFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "0")

        // -1n >= 2n = 1
        ExpectEq(geUFunc, [b.loadBigInt(-1), b.loadBigInt(2)], "1")

        // -1n == 0n = 0
        ExpectEq(eqzFunc, [b.loadBigInt(-1)], "0")

        // 0n == 0n = 1
        ExpectEq(eqzFunc, [b.loadBigInt(0)], "1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testi32ComparisonOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmIntegerCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => .wasmi32) { function, args in
                    let result = function.wasmi32CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let result = function.wasmi32EqualZero(args[0])
                function.wasmReturn(result)
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ne.rawValue))
        let ltSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_s.rawValue))
        let ltUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Lt_u.rawValue))
        let gtSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_s.rawValue))
        let gtUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Gt_u.rawValue))
        let leSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_s.rawValue))
        let leUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Le_u.rawValue))
        let geSFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_s.rawValue))
        let geUFunc = module.getExportedMethod(at: Int(WasmIntegerCompareOpKind.Ge_u.rawValue))

        // This function is added separately at the end above.
        let eqzFunc = module.getExportedMethod(at: WasmIntegerCompareOpKind.allCases.count)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1 == 2 = 0
        ExpectEq(eqFunc, [b.loadInt(1), b.loadInt(2)], "0")

        // 1 != 2 = 1
        ExpectEq(neFunc, [b.loadInt(1), b.loadInt(2)], "1")

        // -1 < 2 = 1
        ExpectEq(ltSFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 < 2 = 0
        ExpectEq(ltUFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // 2 < 2 = 0
        ExpectEq(ltUFunc, [b.loadInt(2), b.loadInt(2)], "0")

        // -1 > 2 = 0
        ExpectEq(gtSFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 > 2 = 1
        ExpectEq(gtUFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 <= 2 = 1
        ExpectEq(leSFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 <= 2 = 0
        ExpectEq(leUFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 >= 2 = 0
        ExpectEq(geSFunc, [b.loadInt(-1), b.loadInt(2)], "0")

        // -1 >= 2 = 1
        ExpectEq(geUFunc, [b.loadInt(-1), b.loadInt(2)], "1")

        // -1 == 0 = 0
        ExpectEq(eqzFunc, [b.loadInt(-1)], "0")

        // 0 == 0 = 1
        ExpectEq(eqzFunc, [b.loadInt(0)], "1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Float Comparison Operations
    func testf64ComparisonOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmFloatCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => .wasmi32) { function, args in
                    let result = function.wasmf64CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ne.rawValue))
        let ltFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Lt.rawValue))
        let gtFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Gt.rawValue))
        let leFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Le.rawValue))
        let geFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ge.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1.9 == 1.9 = 1
        ExpectEq(eqFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "1")

        // 1.9 != 1.9 = 0
        ExpectEq(neFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "0")

        // -1.9 < -2 = 0
        ExpectEq(ltFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "0")

        // -1.9 > -2 = 1
        ExpectEq(gtFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "1")

        // -1.9 <= -1.9 = 1
        ExpectEq(leFunc, [b.loadFloat(-1.9), b.loadFloat(-1.9)], "1")

        // -1 >= 2.1 = 0
        ExpectEq(geFunc, [b.loadFloat(-1), b.loadFloat(2.1)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testf32ComparisonOperations() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // One function per compare operator.
        let module = b.buildWasmModule { wasmModule in
            for compOp in WasmFloatCompareOpKind.allCases {
                // Instantiate a function for each operator
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => .wasmi32) { function, args in
                    let result = function.wasmf32CompareOp(args[0], args[1], using: compOp)
                    function.wasmReturn(result)
                }
            }
        }

        let eqFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Eq.rawValue))
        let neFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ne.rawValue))
        let ltFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Lt.rawValue))
        let gtFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Gt.rawValue))
        let leFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Le.rawValue))
        let geFunc = module.getExportedMethod(at: Int(WasmFloatCompareOpKind.Ge.rawValue))

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        // 1.9 == 1.9 = 1
        ExpectEq(eqFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "1")

        // 1.9 != 1.9 = 0
        ExpectEq(neFunc, [b.loadFloat(1.9), b.loadFloat(1.9)], "0")

        // -1.9 < -2 = 0
        ExpectEq(ltFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "0")

        // -1.9 > -2 = 1
        ExpectEq(gtFunc, [b.loadFloat(-1.9), b.loadFloat(-2)], "1")

        // -1.9 <= -1.9 = 1
        ExpectEq(leFunc, [b.loadFloat(-1.9), b.loadFloat(-1.9)], "1")

        // -1 >= 2.1 = 0
        ExpectEq(geFunc, [b.loadFloat(-1), b.loadFloat(2.1)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    // Numerical Conversion Operations
    func testWrappingi64toi32() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi32) { function, args in
                let result = function.wrapi64Toi32(args[0])
                function.wasmReturn(result)
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(module.getExportedMethod(at: 0), [b.loadBigInt(1)], "1")
        ExpectEq(module.getExportedMethod(at: 0), [b.loadBigInt(1 << 42)], "0")
        ExpectEq(module.getExportedMethod(at: 0), [b.loadBigInt(1 << 32 | 10)], "10")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testFloatTruncationToi32() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi32) { function, args in
                let result = function.truncatef32Toi32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi32) { function, args in
                let result = function.truncatef32Toi32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi32) { function, args in
                let result = function.truncatef64Toi32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi32) { function, args in
                let result = function.truncatef64Toi32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let truncatef32toi32SignedFunc = module.getExportedMethod(at: 0)
        let truncatef32toi32UnsignedFunc = module.getExportedMethod(at: 1)
        let truncatef64toi32SignedFunc = module.getExportedMethod(at: 2)
        let truncatef64toi32UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(truncatef32toi32SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncatef32toi32SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncatef32toi32UnsignedFunc, [b.loadFloat(1.2)], "1")
        // This will raise a runtime error as it is unrepresentable in integer range.
        // We cannot represent -1.2 as an unsigned integer.
        //ExpectEq(truncatef32toi32UnsignedFunc, [b.loadFloat(-1.2)], "")

        ExpectEq(truncatef64toi32SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncatef64toi32SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncatef64toi32UnsignedFunc, [b.loadFloat(1.2)], "1")
        // This will raise a runtime error as it is unrepresentable in integer range.
        // We cannot represent -1.2 as an unsigned integer.
        //ExpectEq(truncatef64toi32UnsignedFunc, [b.loadFloat(-1.2)], "")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testExtendingToi64() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi64) { function, args in
                let result = function.extendi32Toi64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi64) { function, args in
                let result = function.extendi32Toi64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let extendi32SignedFunc = module.getExportedMethod(at: 0)
        let extendi32UnsignedFunc = module.getExportedMethod(at: 1)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(extendi32SignedFunc, [b.loadInt(123)], "123")
        ExpectEq(extendi32SignedFunc, [b.loadInt(-123)], "-123")
        ExpectEq(extendi32UnsignedFunc, [b.loadInt(123)], "123")
        ExpectEq(extendi32UnsignedFunc, [b.loadInt(-123)], "4294967173")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testFloatTruncationToi64() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi64) { function, args in
                let result = function.truncatef32Toi64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi64) { function, args in
                let result = function.truncatef32Toi64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi64) { function, args in
                let result = function.truncatef64Toi64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi64) { function, args in
                let result = function.truncatef64Toi64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let truncatef32toi64SignedFunc = module.getExportedMethod(at: 0)
        let truncatef32toi64UnsignedFunc = module.getExportedMethod(at: 1)
        let truncatef64toi64SignedFunc = module.getExportedMethod(at: 2)
        let truncatef64toi64UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(truncatef32toi64SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncatef32toi64SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncatef32toi64UnsignedFunc, [b.loadFloat(1.2)], "1")
        // This will raise a runtime error as it is unrepresentable in integer range.
        // We cannot represent -1.2 as an unsigned integer.
        // ExpectEq(truncatef32toi64UnsignedFunc, [b.loadFloat(-1.2)], "")

        ExpectEq(truncatef64toi64SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncatef64toi64SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncatef64toi64UnsignedFunc, [b.loadFloat(1.2)], "1")
        // This will raise a runtime error as it is unrepresentable in integer range.
        // We cannot represent -1.2 as an unsigned integer.
        //ExpectEq(truncatef64toi64UnsignedFunc, [b.loadFloat(-1.2)], "")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testConversionTof32() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmf32) { function, args in
                let result = function.converti32Tof32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmf32) { function, args in
                let result = function.converti32Tof32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmf32) { function, args in
                let result = function.converti64Tof32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmf32) { function, args in
                let result = function.converti64Tof32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let converti32tof32SignedFunc = module.getExportedMethod(at: 0)
        let converti32tof32UnsignedFunc = module.getExportedMethod(at: 1)
        let converti64tof32SignedFunc = module.getExportedMethod(at: 2)
        let converti64tof32UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(converti32tof32SignedFunc, [b.loadInt(1)], "1")
        ExpectEq(converti32tof32SignedFunc, [b.loadInt(-1)], "-1")
        ExpectEq(converti32tof32UnsignedFunc, [b.loadInt(1)], "1")
        ExpectEq(converti32tof32UnsignedFunc, [b.loadInt(-1)], "4294967296")

        ExpectEq(converti64tof32SignedFunc, [b.loadBigInt(1)], "1")
        ExpectEq(converti64tof32SignedFunc, [b.loadBigInt(-1)], "-1")
        ExpectEq(converti64tof32UnsignedFunc, [b.loadBigInt(1)], "1")
        ExpectEq(converti64tof32UnsignedFunc, [b.loadBigInt(-1)], "18446744073709552000")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testPromotionAndDemotionOfFloats() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmf64) { function, args in
                let result = function.promotef32Tof64(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmf32) { function, args in
                let result = function.demotef64Tof32(args[0])
                function.wasmReturn(result)
            }
        }

        let promotionFunc = module.getExportedMethod(at: 0)
        let demotionFunc = module.getExportedMethod(at: 1)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(promotionFunc, [b.loadFloat(1.2)], "1.2000000476837158")
        ExpectEq(demotionFunc, [b.loadFloat(1.2)], "1.2000000476837158")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testConversionTof64() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmf64) { function, args in
                let result = function.converti32Tof64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmf64) { function, args in
                let result = function.converti32Tof64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmf64) { function, args in
                let result = function.converti64Tof64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmf64) { function, args in
                let result = function.converti64Tof64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let converti32tof64SignedFunc = module.getExportedMethod(at: 0)
        let converti32tof64UnsignedFunc = module.getExportedMethod(at: 1)
        let converti64tof64SignedFunc = module.getExportedMethod(at: 2)
        let converti64tof64UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(converti32tof64SignedFunc, [b.loadInt(1)], "1")
        ExpectEq(converti32tof64SignedFunc, [b.loadInt(-1)], "-1")
        ExpectEq(converti32tof64UnsignedFunc, [b.loadInt(1)], "1")
        ExpectEq(converti32tof64UnsignedFunc, [b.loadInt(-1)], "4294967295")

        ExpectEq(converti64tof64SignedFunc, [b.loadBigInt(1)], "1")
        ExpectEq(converti64tof64SignedFunc, [b.loadBigInt(-1)], "-1")
        ExpectEq(converti64tof64UnsignedFunc, [b.loadBigInt(1)], "1")
        ExpectEq(converti64tof64UnsignedFunc, [b.loadBigInt(-1)], "18446744073709552000")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testReinterpretAs() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi32) { function, args in
                let result = function.reinterpretf32Asi32(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi64) { function, args in
                let result = function.reinterpretf64Asi64(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmf32) { function, args in
                let result = function.reinterpreti32Asf32(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmf64) { function, args in
                let result = function.reinterpreti64Asf64(args[0])
                function.wasmReturn(result)
            }
        }

        let f32Asi32Func = module.getExportedMethod(at: 0)
        let f64Asi64Func = module.getExportedMethod(at: 1)
        let i32Asf32Func = module.getExportedMethod(at: 2)
        let i64Asf64Func = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(f32Asi32Func, [b.loadFloat(1.2)], "1067030938")
        ExpectEq(f64Asi64Func, [b.loadFloat(1.2)], "4608083138725491507")
        ExpectEq(i32Asf32Func, [b.loadInt(1067030938)], "1.2000000476837158")
        ExpectEq(i64Asf64Func, [b.loadBigInt(4608083138725491507)], "1.2")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testSignExtension() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let result = function.signExtend8Intoi32(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let result = function.signExtend16Intoi32(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                let result = function.signExtend8Intoi64(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                let result = function.signExtend16Intoi64(args[0])
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, args in
                let result = function.signExtend32Intoi64(args[0])
                function.wasmReturn(result)
            }
        }

        let signExtend8Intoi32Func = module.getExportedMethod(at: 0)
        let signExtend16Intoi32Func = module.getExportedMethod(at: 1)
        let signExtend8Intoi64Func = module.getExportedMethod(at: 2)
        let signExtend16Intoi64Func = module.getExportedMethod(at: 3)
        let signExtend32Intoi64Func = module.getExportedMethod(at: 4)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String)in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(signExtend8Intoi32Func, [b.loadInt(0xff)], "-1")
        ExpectEq(signExtend8Intoi32Func, [b.loadInt(0xff08)], "8")

        ExpectEq(signExtend16Intoi32Func, [b.loadInt(0xfffe)], "-2")
        ExpectEq(signExtend16Intoi32Func, [b.loadInt(0xff0001)], "1")

        ExpectEq(signExtend8Intoi64Func, [b.loadBigInt(0xff)], "-1")
        ExpectEq(signExtend8Intoi64Func, [b.loadBigInt(0xff08)], "8")

        ExpectEq(signExtend16Intoi64Func, [b.loadBigInt(0xfffe)], "-2")
        ExpectEq(signExtend16Intoi64Func, [b.loadBigInt(0xff0001)], "1")

        ExpectEq(signExtend32Intoi64Func, [b.loadBigInt(0xfffffffe)], "-2")
        ExpectEq(signExtend32Intoi64Func, [b.loadBigInt(0xff00000001)], "1")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testFloatSaturatingTruncationToi32() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi32) { function, args in
                let result = function.truncateSatf32Toi32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi32) { function, args in
                let result = function.truncateSatf32Toi32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi32) { function, args in
                let result = function.truncateSatf64Toi32(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi32) { function, args in
                let result = function.truncateSatf64Toi32(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let truncateSatf32toi32SignedFunc = module.getExportedMethod(at: 0)
        let truncateSatf32toi32UnsignedFunc = module.getExportedMethod(at: 1)
        let truncateSatf64toi32SignedFunc = module.getExportedMethod(at: 2)
        let truncateSatf64toi32UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(truncateSatf32toi32SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf32toi32SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncateSatf32toi32UnsignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf32toi32UnsignedFunc, [b.loadFloat(-1.2)], "0")

        ExpectEq(truncateSatf64toi32SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf64toi32SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncateSatf64toi32UnsignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf64toi32UnsignedFunc, [b.loadFloat(-1.2)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }

    func testFloatSaturatingTruncationToi64() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi64) { function, args in
                let result = function.truncateSatf32Toi64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => .wasmi64) { function, args in
                let result = function.truncateSatf32Toi64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi64) { function, args in
                let result = function.truncateSatf64Toi64(args[0], isSigned: true)
                function.wasmReturn(result)
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => .wasmi64) { function, args in
                let result = function.truncateSatf64Toi64(args[0], isSigned: false)
                function.wasmReturn(result)
            }
        }

        let truncateSatf32toi64SignedFunc = module.getExportedMethod(at: 0)
        let truncateSatf32toi64UnsignedFunc = module.getExportedMethod(at: 1)
        let truncateSatf64toi64SignedFunc = module.getExportedMethod(at: 2)
        let truncateSatf64toi64UnsignedFunc = module.getExportedMethod(at: 3)

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        var outputString = ""

        let ExpectEq = { (function: String, arguments: [Variable], output: String) in
            let result = b.callMethod(function, on: exports, withArgs: arguments)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])
            outputString += output + "\n"
        }

        ExpectEq(truncateSatf32toi64SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf32toi64SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncateSatf32toi64UnsignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf32toi64UnsignedFunc, [b.loadFloat(-1.2)], "0")

        ExpectEq(truncateSatf64toi64SignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf64toi64SignedFunc, [b.loadFloat(-1.2)], "-1")
        ExpectEq(truncateSatf64toi64UnsignedFunc, [b.loadFloat(1.2)], "1")
        ExpectEq(truncateSatf64toi64UnsignedFunc, [b.loadFloat(-1.2)], "0")

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: outputString)
    }
}

// TODO(cffsmith): these tests test specific splicing around WasmJsCall instructions. We should also add some regular Wasm splicing tests.
class WasmSpliceTests: XCTestCase {
    func testWasmJSCallSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()

        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadInt(42))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, args in
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                splicePoint = b.indexOfNextInstruction()
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
            }
        }

        let original = b.finalize()

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, _ in
                let _ = function.constf32(42.42)
                b.splice(from: original, at: splicePoint, mergeDataFlow: true)
            }
        }

        let actual = b.finalize()

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, _ in
                let _ = function.constf32(42.42)
            }
        }

        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testWasmJSCallSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()

        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadInt(42))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, args in
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                splicePoint = b.indexOfNextInstruction()
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
            }
        }

        let original = b.finalize()

        b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadString("AB"))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, _ in
                let _ = function.constf64(42.42)
                b.splice(from: original, at: splicePoint, mergeDataFlow: true)
            }
        }

        let actual = b.finalize()

        b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadString("AB"))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => .nothing) { function, _ in
                let _ = function.constf64(42.42)
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
            }
        }

        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }
}

class WasmJSPITests: XCTestCase {
    func testJSPI() throws {
        // We need to have the right arguments here and we need a shell that supports jspi.
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .user, withArguments: ["--wasm-staging", "--expose-gc"])

        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        // This is a function that returns a promise.
        let function = b.buildAsyncFunction(with: .parameters(n: 1)) { args in
            b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
            let json = b.createNamedVariable(forBuiltin: "JSON")
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("stringify", on: json, withArgs: [args[0]])])
            b.doReturn(b.loadInt(1))
        }

        // Wrap the JS function for JSPI use.
        let importFunction = b.wrapSuspending(function: function)
        XCTAssert(b.type(of: importFunction).Is(.object(ofGroup: "WebAssembly.SuspendableObject")))

        // Now lets build the module
        let module = b.buildWasmModule { m in
            m.addWasmFunction(with: [.wasmExternRef] => .wasmi32) { f, args in
                let ret = f.wasmJsCall(function: importFunction, withArgs: args, withWasmSignature: [.wasmExternRef] => .wasmi32)
                f.wasmReturn(ret!)
            }
        }

        let exports = module.loadExports()
        let exportRef = b.getProperty(module.getExportedMethod(at: 0), of: exports)

        let exportFunc = b.wrapPromising(function: exportRef)

        let obj = b.createObject(with: ["a": b.loadInt(42)])

        let res = b.callFunction(exportFunc, withArgs: [obj])

        let arrowFunc = b.buildArrowFunction(with: .parameters(n: 1)) { args in
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: args[0])])
        }

        b.callMethod("then", on: res, withArgs: [arrowFunc])

        let outputString = "{\"a\":42}\n1\n"

        let program = b.finalize()
        let jsProgram = fuzzer.lifter.lift(program, withOptions: .includeComments)

        testForOutput(program: jsProgram, runner: runner, outputString: outputString)
    }
}
