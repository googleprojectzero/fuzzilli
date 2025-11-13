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

func testForOutputRegex(program: String, runner: JavaScriptExecutor, outputPattern: String) {
    let result = testExecuteScript(program: program, runner: runner)
    let matches = result.output.matches(of: try! Regex(outputPattern))
    XCTAssertEqual(matches.isEmpty, false, "Output:\n\(result.output)\nExpected output:\n\(outputPattern)Error Output:\n\(result.error)")
}

func testForErrorOutput(program: String, runner: JavaScriptExecutor, errorMessageContains errormsg: String) {
    let result = testExecuteScript(program: program, runner: runner)
    XCTAssert(result.output.contains(errormsg) || result.error.contains(errormsg), "Error messages don't match, got stdout:\n\(result.output)\nstderr:\n\(result.error)")
}

class WasmSignatureConversionTests: XCTestCase {
    func testJsSignatureConversion() {
        XCTAssertEqual(ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1), (.wasmFuncRef, 1), (.wasmExternRef, 1)])), [.wasmi32] => [.wasmi32])
        XCTAssertEqual(ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmf32, 1), (.wasmFuncRef, 1), (.wasmExternRef, 1)])), [.wasmf32] => [.wasmi32])
    }

    func testWasmSignatureConversion() {
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmi32, .wasmi64] => [.wasmf32]), [.integer, .bigint] => .float)
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmi32, .wasmExnRef] => [.wasmf64]), [.integer, .jsAnything] => .float)
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmExternRef, .wasmFuncRef] => [.wasmf64, .wasmf64]), [.jsAnything, .function()] => .jsArray)
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmRef(.Index(), nullability: false), .wasmFuncRef] => [.wasmf64, .wasmf64]), [.jsAnything, .function()] => .jsArray)
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmRef(.Abstract(.WasmExtern), nullability: false), .wasmFuncRef] => [.wasmf64, .wasmf64]), [.jsAnything, .function()] => .jsArray)
        // TODO(cffsmith): Change this once we know how we want to represent .wasmSimd128 types in JS.
        XCTAssertEqual(ProgramBuilder.convertWasmSignatureToJsSignature([.wasmSimd128] => [.wasmSimd128]), [.jsAnything] => .jsAnything)
    }
}

class WasmFoundationTests: XCTestCase {
    func testFunction() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                    let constVar = function.consti32(1338)
                    return [constVar]
                }

                wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, arg in
                    let var64 = function.consti64(41)
                    let added = function.wasmi64BinOp(var64, arg[0], binOpKind: WasmIntegerBinaryOpKind.Add)
                    return [added]
                }

                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => [.wasmi64]) { function, label, arg in
                    let subbed = function.wasmi64BinOp(arg[0], arg[1], binOpKind: WasmIntegerBinaryOpKind.Sub)
                    return [subbed]
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
        }

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n42\n41\n")
    }

    func testFunctionLabel() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                    function.wasmBranchIf(args[0], to: label, args: args)
                    return [function.consti32(-1)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testFunctionMultiReturn() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                // Test branch if and fall-through.
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32, .wasmi64, .wasmf32]) { function, label, args in
                    function.wasmBranchIf(args[0], to: label, args: [function.consti32(1), function.consti64(2), function.constf32(3)])
                    return [function.consti32(4), function.consti64(5), function.constf32(6)]
                }
                // Test explicit return.
                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi64, .wasmf32]) { function, label, args in
                    function.wasmReturn([function.consti32(7), function.consti64(8), function.constf32(9)])
                    return [function.consti32(-1), function.consti64(-1), function.constf32(-1)]
                }
                // Test unconditional branch.
                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi64, .wasmf32]) { function, label, args in
                    function.wasmBranch(to: label, args: [function.consti32(10), function.consti64(11), function.constf32(12)])
                    return [function.consti32(-1), function.consti64(-1), function.constf32(-1)]
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            [
                b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)]),
                b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)]),
                b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: []),
                b.callMethod(module.getExportedMethod(at: 2), on: exports, withArgs: []),
            ].forEach {b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: $0)])}
        }
        testForOutput(program: jsProg, runner: runner, outputString: "1,2,3\n4,5,6\n7,8,9\n10,11,12\n")
    }

    func testExportNaming() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            // This test tests whether re-exported imports and module defined globals are re-ordered from the typer.
            let wasmGlobali32: Variable = b.createWasmGlobal(value: .wasmi32(1337), isMutable: true)
            XCTAssertEqual(b.type(of: wasmGlobali32), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmi32, isMutable: true)))

            let wasmGlobalf32: Variable = b.createWasmGlobal(value: .wasmf32(42.0), isMutable: false)
            XCTAssertEqual(b.type(of: wasmGlobalf32), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmf32, isMutable: false)))

            let module = b.buildWasmModule { wasmModule in
                // Imports are always before internal globals, this breaks the logic if we add a global and then import a global.
                wasmModule.addWasmFunction(with: [] => []) { fun, _, _  in
                    // This load forces an import
                    // This should be iwg0
                    fun.wasmLoadGlobal(globalVariable: wasmGlobalf32)
                    return []
                }
                // This adds an internally defined global, it should be wg0
                wasmModule.addGlobal(wasmGlobal: .wasmi64(4141), isMutable: true)
                wasmModule.addWasmFunction(with: [] => []) { fun, _, _  in
                    // This load forces an import
                    // This should be iwg1
                    fun.wasmLoadGlobal(globalVariable: wasmGlobali32)
                    return []
                }
            }

            let exports = module.loadExports()

            XCTAssertEqual(b.type(of: exports), .object(ofGroup: "_fuzz_WasmExports0", withProperties: ["iwg0", "iwg1", "wg0"], withMethods: ["w1", "w0"]))

            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            // Now let's actually see what the re-exported values are and see that the types don't match with what the programbuilder will see.
            // TODO: Is this an issue? will the programbuilder still be queriable for variables? I think so, it is internally consistent within the module...
            let firstExport = b.getProperty("iwg0", of: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: firstExport))])

            let secondExport = b.getProperty("wg0", of: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: secondExport))])

            let thirdExport = b.getProperty("iwg1", of: exports)
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: thirdExport))])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "42\n4141\n1337\n")
    }

    func testImports() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let functionA = b.buildPlainFunction(with: .parameters(.bigint)) { args in
                let varA = b.loadBigInt(1)
                let added = b.binary(varA, args[0], with: .Add)
                b.doReturn(added)
            }

            XCTAssertEqual(b.type(of: functionA).signature, [.bigint] => .bigint)

            let functionB = b.buildArrowFunction(with: .parameters(.integer)) { args in
                let varB = b.loadInt(2)
                let subbed = b.binary(varB, args[0], with: .Sub)
                b.doReturn(subbed)
            }
            // We are unable to determine that .integer - .integer == .integer here as INT_MAX + 1 => float
            XCTAssertEqual(b.type(of: functionB).signature, [.integer] => .number)

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, args in
                    // Manually set the availableTypes here for testing
                    let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionA).signature!, availableTypes: WeightedList([(.wasmi64, 1)]))
                    XCTAssertEqual(wasmSignature, [.wasmi64] => [.wasmi64])
                    let varA = function.wasmJsCall(function: functionA, withArgs: [args[0]], withWasmSignature: wasmSignature)!
                    return [varA]
                }

                wasmModule.addWasmFunction(with: [] => [.wasmf32]) { function, _, _ in
                    // Manually set the availableTypes here for testing
                    let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionB).signature!, availableTypes: WeightedList([(.wasmi32, 1), (.wasmf32, 1)]))
                    XCTAssertEqual(wasmSignature.parameterTypes.count, 1)
                    XCTAssert(wasmSignature.parameterTypes[0] == .wasmi32 || wasmSignature.parameterTypes[0] == .wasmf32)
                    XCTAssert(wasmSignature.outputTypes == [.wasmi32] || wasmSignature.outputTypes == [.wasmf32])
                    let varA = wasmSignature.parameterTypes[0] == .wasmi32 ? function.consti32(1337) : function.constf32(1337)
                    let varRet = function.wasmJsCall(function: functionB, withArgs: [varA], withWasmSignature: wasmSignature)!
                    return [varRet]
                }

                wasmModule.addWasmFunction(with: [] => [.wasmf32]) { function, _, _ in
                    let varA = function.constf32(1337.1)
                    let varRet = function.wasmJsCall(function: functionB, withArgs: [varA], withWasmSignature: [.wasmf32] => [.wasmf32])!
                    return [varRet]
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
        }

        testForOutput(program: jsProg, runner: runner, outputString: "3\n-1335\n-1335\n")
    }

    func testBasics() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                    [function.consti32(42)]
                }

                wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, arg in
                    let varA = function.consti64(41)
                    return [function.wasmi64BinOp(varA, arg[0], binOpKind: .Add)]
                }
            }

            let exports = module.loadExports()

            let res0 = b.callMethod(module.getExportedMethod(at: 0), on: exports)
            let integer = b.loadBigInt(1)
            let res1 = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [integer])

            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])
        }

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
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, params in
                let varA = function.consti64(1338)
                // reassign params[0] = varA
                function.wasmReassign(variable: params[0], to: varA)
                return [params[0]]
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, params in
                // reassign params[0] = params[0]
                function.wasmReassign(variable: params[0], to: params[0])
                return [params[0]]
            }

            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                let ctr = function.consti32(10)
                function.wasmBuildLoop(with: [] => []) { label, args in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    let result = function.wasmi32BinOp(ctr, function.consti32(1), binOpKind: .Sub)
                    function.wasmReassign(variable: ctr, to: result)
                    // The backedge, loop if we are not at zero yet.
                    let isNotZero = function.wasmi32CompareOp(ctr, function.consti32(0), using: .Ne)
                    function.wasmBranchIf(isNotZero, to: label)
                }
                return [ctr]
            }

            let tag = wasmModule.addTag(parameterTypes: [.wasmi32, .wasmi32])
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { _, _ in
                    function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123), function.consti32(456)])
                    function.WasmBuildLegacyCatch(tag: tag) { _, _, e in
                        // The exception values are e[0] = 123 and e[1] = 456.
                        function.wasmReassign(variable: e[0], to: e[1])
                        // The exception values should now be e[0] = 456, e[1] = 456.
                        function.wasmReturn(e[0])
                    }
                }
                function.wasmUnreachable()
                return [function.consti32(-1)]
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
        XCTAssertEqual(b.type(of: wasmGlobali64), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmi64, isMutable: true)))

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .wasmi64(1339), isMutable: true)


            // Function 0
            wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                // This forces an import of the wasmGlobali64
                function.wasmLoadGlobal(globalVariable: wasmGlobali64)
                return []
            }

            // Function 1
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                let varA = function.consti64(1338)
                let varB = function.consti64(4242)
                function.wasmStoreGlobal(globalVariable: global, to: varB)
                let global = function.wasmLoadGlobal(globalVariable: global)
                function.wasmStoreGlobal(globalVariable: wasmGlobali64, to: varA)
                return [global]
            }

            // Function 2
            wasmModule.addWasmFunction(with: [] => [.wasmf64]) { function, _, _ in
                let globalValue = function.wasmLoadGlobal(globalVariable: wasmGlobali64)
                let result = function.reinterpreti64Asf64(globalValue)
                return [result]
            }
        }

        let exports = module.loadExports()

        let _ = b.callMethod(module.getExportedMethod(at: 1), on: exports)
        let out = b.callMethod(module.getExportedMethod(at: 2), on: exports)

        let nameOfExportedGlobals = ["iwg0", "wg0"]
        let nameOfExportedFunctions = ["w0", "w1", "w2"]


        XCTAssertEqual(b.type(of: exports), .object(ofGroup: "_fuzz_WasmExports0", withProperties: nameOfExportedGlobals, withMethods: nameOfExportedFunctions))


        let value = b.getProperty("value", of: wasmGlobali64)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])

        let wg0 = b.getProperty(nameOfExportedGlobals[1], of: exports)
        let valueWg0 = b.getProperty("value", of: wg0)
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueWg0)])

        b.callFunction(outputFunc, withArgs: [out])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n4242\n6.61e-321\n")
    }

    func testGlobalExnRef() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            // Note that globals of exnref can only be defined in wasm, not in JS.
            let global = wasmModule.addGlobal(wasmGlobal: .exnref, isMutable: true)
            XCTAssertEqual(b.type(of: global), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmExnRef, isMutable: true)))

            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                let value = function.wasmLoadGlobal(globalVariable: global)
                return [function.wasmRefIsNull(value)]
            }

            // Throw an exception, catch it and store it in the global.
            wasmModule.addWasmFunction(with: [] => []) { function, label, args in
                let exnref = function.wasmBuildBlockWithResults(with: [] => [.wasmExnRef], args: []) { catchLabel, _ in
                    function.wasmBuildTryTable(with: [] => [], args: [catchLabel], catches: [.AllRef]) { _, _ in
                        function.WasmBuildThrow(tag: tagi32, inputs: [function.consti32(42)])
                        return []
                    }
                    return [function.wasmRefNull(type: .wasmExnRef)]
                }[0]
                function.wasmStoreGlobal(globalVariable: global, to: exnref)
                return []
            }

            // Rethrow the exception stored in the global, catch it and extract the integer.
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                let caughtValues = function.wasmBuildBlockWithResults(with: [] => [.wasmi32, .wasmExnRef], args: []) { catchLabel, _ in
                    function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchLabel], catches: [.Ref]) { _, _ in
                        function.wasmBuildThrowRef(exception: function.wasmLoadGlobal(globalVariable: global))
                        return []
                    }
                    return [function.consti32(-1), function.wasmRefNull(type: .wasmExnRef)]
                }
                return [caughtValues[0]]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        // The initial value is null --> prints "1".
        let out1 = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [out1])
        // Store an exnref in the global.
        b.callMethod(module.getExportedMethod(at: 1), on: exports)
        // The value is non-null --> prints "0".
        let out2 = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [out2])
        // Read the integer value stored in the exception stored in the global.
        let out3 = b.callMethod(module.getExportedMethod(at: 2), on: exports)
        b.callFunction(outputFunc, withArgs: [out3])
        // The global is also exported to JS but we can't get the exnref value.
        let global = b.getProperty("wg0", of: exports)
        b.buildTryCatchFinally {
            b.getProperty("value", of: global)
            b.callFunction(outputFunc, withArgs: [b.loadString("Not reached")])
        } catchBody: { e in
            b.callFunction(outputFunc, withArgs: [b.loadString("exception")])
        }
        // We can however import it into another wasm program and access its value there.
        let otherModule = b.buildWasmModule { wasmModule in
            // Rethrow the exception stored in the global, catch it and extract the integer.
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                let caughtValues = function.wasmBuildBlockWithResults(with: [] => [.wasmi32, .wasmExnRef], args: []) { catchLabel, _ in
                    function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchLabel], catches: [.Ref]) { _, _ in
                        function.wasmBuildThrowRef(exception: function.wasmLoadGlobal(globalVariable: global))
                        return []
                    }
                    return [function.consti32(-1), function.wasmRefNull(type: .wasmExnRef)]
                }
                return [caughtValues[0]]
            }
        }
        let otherExports = otherModule.loadExports()
        let out4 = b.callMethod(module.getExportedMethod(at: 0), on: otherExports)
        b.callFunction(outputFunc, withArgs: [out4])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1\n0\n42\nexception\n42\n")
    }

    func testGlobalExternRef() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .externref, isMutable: true)
            XCTAssertEqual(b.type(of: global), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmExternRef, isMutable: true)))

            wasmModule.addWasmFunction(with: [] => [.wasmExternRef]) { function, label, args in
                [function.wasmLoadGlobal(globalVariable: global)]
            }

            wasmModule.addWasmFunction(with: [.wasmExternRef] => []) { function, label, args in
                function.wasmStoreGlobal(globalVariable: global, to: args[0])
                return []
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let loadGlobal = module.getExportedMethod(at: 0)
        let storeGlobal = module.getExportedMethod(at: 1)
        // The initial value is "null".
        b.callFunction(outputFunc, withArgs: [b.callMethod(loadGlobal, on: exports)])
        // Store a string in the global.
        b.callMethod(storeGlobal, on: exports, withArgs: [b.loadString("Hello!")])
        // The value is now "Hello!".
        b.callFunction(outputFunc, withArgs: [b.callMethod(loadGlobal, on: exports)])
        // The same value is returned from JS when accessing it via the .value property.
        let global = b.getProperty("wg0", of: exports)
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "null\nHello!\nHello!\n")
    }

    func testGlobalExternRefFromJS() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let global: Variable = b.createWasmGlobal(value: .externref, isMutable: true)
        XCTAssertEqual(b.type(of: global), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmExternRef, isMutable: true)))

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        // The initial value is "undefined" (because we didn't provide an explicit initialization).
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])
        // Store a string in the global.
        b.setProperty("value", of: global, to: b.loadString("Hello!"))
        // The value is now "Hello!".
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "undefined\nHello!\n")
    }

    func testGlobalI31Ref() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .i31ref, isMutable: true)
            XCTAssertEqual(b.type(of: global), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmI31Ref, isMutable: true)))

            wasmModule.addWasmFunction(with: [] => [.wasmI31Ref]) { function, label, args in
                [function.wasmLoadGlobal(globalVariable: global)]
            }

            wasmModule.addWasmFunction(with: [.wasmI31Ref] => []) { function, label, args in
                function.wasmStoreGlobal(globalVariable: global, to: args[0])
                return []
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let loadGlobal = module.getExportedMethod(at: 0)
        let storeGlobal = module.getExportedMethod(at: 1)
        // The initial value is "null".
        b.callFunction(outputFunc, withArgs: [b.callMethod(loadGlobal, on: exports)])
        // Store a number in the global.
        b.callMethod(storeGlobal, on: exports, withArgs: [b.loadInt(-42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod(loadGlobal, on: exports)])
        // The same value is returned from JS when accessing it via the .value property.
        let global = b.getProperty("wg0", of: exports)
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "null\n-42\n-42\n")
    }

    func testGlobalI31RefFromJS() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let global: Variable = b.createWasmGlobal(value: .i31ref, isMutable: true)
        XCTAssertEqual(b.type(of: global), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmI31Ref, isMutable: true)))

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        // The initial value is "null" (because we didn't provide an explicit initialization).
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])
        // Store a number in the global.
        b.setProperty("value", of: global, to: b.loadInt(-42))
        b.callFunction(outputFunc, withArgs: [b.getProperty("value", of: global)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "null\n-42\n")
    }

    func importedTableTestCase(isTable64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let javaScriptTable = b.createWasmTable(elementType: .wasmExternRef, limits: Limits(min: 5, max: 25), isTable64: isTable64)
        XCTAssertEqual(b.type(of: javaScriptTable), .wasmTable(wasmTableType: WasmTableType(elementType: .wasmExternRef, limits: Limits(min: 5, max: 25), isTable64: isTable64, knownEntries: [])))

        let object = b.createObject(with: ["a": b.loadInt(41), "b": b.loadInt(42)])

        // Set a value into the table
        b.callMethod("set", on: javaScriptTable, withArgs: [isTable64 ? b.loadBigInt(1) : b.loadInt(1), object])

        let module = b.buildWasmModule { wasmModule in
            let tableRef = wasmModule.addTable(elementType: .wasmExternRef, minSize: 2, isTable64: isTable64)

            wasmModule.addWasmFunction(with: [] => [.wasmExternRef]) { function, _, _ in
                let offset = isTable64 ? function.consti64(0) : function.consti32(0)
                var ref = function.wasmTableGet(tableRef: tableRef, idx: offset)
                let offset1 = isTable64 ? function.consti64(1) : function.consti32(1)
                function.wasmTableSet(tableRef: tableRef, idx: offset1, to: ref)
                ref = function.wasmTableGet(tableRef: tableRef, idx: offset1)
                let otherRef = function.wasmTableGet(tableRef: javaScriptTable, idx: offset1)
                return [otherRef]
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

    func testImportedTable32() throws {
        try importedTableTestCase(isTable64: false)
    }

    func testImportedTable64() throws {
        try importedTableTestCase(isTable64: true)
    }

    func defineTable(isTable64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .warning, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters()) { _ in
            b.doReturn(b.loadBigInt(11))
        }

        let module = b.buildWasmModule { wasmModule in
            let wasmFunction = wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, params in
                [function.wasmi32BinOp(params[0], function.consti32(1), binOpKind: .Add)]
            }
            wasmModule.addTable(elementType: .wasmFuncRef,
                                minSize: 10,
                                definedEntries: [.init(indexInTable: 0, signature: [.wasmi32] => [.wasmi32]), .init(indexInTable: 1, signature: [] => [.wasmi64])],
                                definedEntryValues: [wasmFunction, jsFunction],
                                isTable64: isTable64)
        }

        let exports = module.loadExports()

        let table = b.getProperty("wt0", of: exports)

        XCTAssertEqual(b.type(of: exports), .object(ofGroup: "_fuzz_WasmExports0", withProperties: ["wt0"], withMethods: ["w0", "iw0"]))

        let importedFunction = b.getProperty("iw0", of: exports)

        XCTAssertEqual(b.type(of: importedFunction), .function([] => .bigint))

        // This is the table type that we expect to see on the exports based on the dynamic object group typing.
        let tableType = ILType.wasmTable(wasmTableType: WasmTableType(elementType: .wasmFuncRef, limits: Limits(min: 10), isTable64: isTable64, knownEntries: [
            .init(indexInTable: 0, signature: [.wasmi32] => [.wasmi32]),
            .init(indexInTable: 1, signature: [] => [.wasmi64])

        ]))
        XCTAssertEqual(b.type(of: table), tableType)

        let tableElement0 = b.callMethod("get", on: table, withArgs: [isTable64 ? b.loadBigInt(0) : b.loadInt(0)])
        let tableElement1 = b.callMethod("get", on: table, withArgs: [isTable64 ? b.loadBigInt(1) : b.loadInt(1)])

        let output0 = b.callFunction(tableElement0, withArgs: [b.loadInt(42)])
        let output1 = b.callFunction(tableElement1, withArgs: [])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [output0])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: output1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "43\n11\n")
    }

    func testDefineTable32() throws {
        try defineTable(isTable64: false)
    }

    func testDefineTable64() throws {
        try defineTable(isTable64: true)
    }

    func testCallIndirect() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters(.bigint)) { params in
            b.doReturn(b.binary(params[0], b.loadBigInt(42), with: .Add))
        }

        let module = b.buildWasmModule { wasmModule in
            let wasmFunction = wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64, .wasmi64]) { function, label, params in
                return [params[0], function.consti64(1)]
            }
            let table = wasmModule.addTable(elementType: .wasmFuncRef,
                                            minSize: 10,
                                            definedEntries: [.init(indexInTable: 0, signature: [.wasmi64] => [.wasmi64, .wasmi64]), .init(indexInTable: 1, signature: [.wasmi64] => [.wasmi64])],
                                            definedEntryValues: [wasmFunction, jsFunction],
                                            isTable64: false)
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { fn, label, params in
                let results = fn.wasmCallIndirect(signature: [.wasmi64] => [.wasmi64, .wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
                return [fn.wasmi64BinOp(results[0], results[1], binOpKind: .Add)]
            }
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { fn, label, params in
                fn.wasmCallIndirect(signature: [.wasmi64] => [.wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
            }

        }

        let exports = module.loadExports()

        let callIndirectSig0 = b.getProperty(module.getExportedMethod(at: 1), of: exports)
        let result0 = b.callFunction(callIndirectSig0, withArgs: [b.loadInt(0), b.loadBigInt(10)])
        let callIndirectSig1 = b.getProperty(module.getExportedMethod(at: 2), of: exports)
        let result1 = b.callFunction(callIndirectSig1, withArgs: [b.loadInt(1), b.loadBigInt(10)])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "11\n52\n")
    }

    func testCallIndirectMultiModule() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters(.bigint)) { params in
            b.doReturn(b.binary(params[0], b.loadBigInt(42), with: .Add))
        }

        let module = b.buildWasmModule { wasmModule in
            let wasmFunction = wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64, .wasmi64]) { function, label, params in
                return [params[0], function.consti64(1)]
            }
            wasmModule.addTable(elementType: .wasmFuncRef,
                minSize: 10,
                definedEntries: [.init(indexInTable: 0, signature: [.wasmi64] => [.wasmi64, .wasmi64]), .init(indexInTable: 1, signature: [.wasmi64] => [.wasmi64])],
                definedEntryValues: [wasmFunction, jsFunction],
                isTable64: false)
        }

        let table = b.getProperty("wt0", of: module.loadExports())
        let tableType = ILType.wasmTable(wasmTableType: WasmTableType(elementType: .wasmFuncRef, limits: Limits(min: 10), isTable64: false, knownEntries: [
            .init(indexInTable: 0, signature: [.wasmi64] => [.wasmi64, .wasmi64]),
            .init(indexInTable: 1, signature: [.wasmi64] => [.wasmi64])
        ]))
        XCTAssertEqual(b.type(of: table), tableType)
        let module2 = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { fn, label, params in
                let results = fn.wasmCallIndirect(signature: [.wasmi64] => [.wasmi64, .wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
                return [fn.wasmi64BinOp(results[0], results[1], binOpKind: .Add)]
            }

            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { fn, label, params in
                fn.wasmCallIndirect(signature: [.wasmi64] => [.wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
            }

            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmFuncRef]) { function, label, params in
                [function.wasmTableGet(tableRef: table, idx: params[0])]
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64, .wasmi64]) { function, label, params in
                [params[0], params[0]]
            }
        }

        let exports = module2.loadExports()

        // We should also see the re-exported table here.
        let reexportedTable = b.getProperty("iwt0", of: exports)

        // This is the table type that we expect to see on the exports based on the dynamic object group typing.
        let reexportedTableType = ILType.wasmTable(wasmTableType: WasmTableType(elementType: .wasmFuncRef, limits: Limits(min: 10), isTable64: false, knownEntries: [
            .init(indexInTable: 0, signature: [.wasmi64] => [.wasmi64, .wasmi64]),
            .init(indexInTable: 1, signature: [.wasmi64] => [.wasmi64])

        ]))
        XCTAssertEqual(b.type(of: reexportedTable), reexportedTableType)


        let callIndirectSig0 = b.getProperty(module2.getExportedMethod(at: 0), of: exports)
        let result0 = b.callFunction(callIndirectSig0, withArgs: [b.loadInt(0), b.loadBigInt(10)])
        let callIndirectSig1 = b.getProperty(module2.getExportedMethod(at: 1), of: exports)
        let result1 = b.callFunction(callIndirectSig1, withArgs: [b.loadInt(1), b.loadBigInt(10)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result1)])

        let exportedTableGet = b.getProperty(module2.getExportedMethod(at: 2), of: exports)
        let wasmFuncRef = b.callFunction(exportedTableGet, withArgs: [b.loadInt(0)])
        let resultCallFuncRef = b.callFunction(wasmFuncRef, withArgs: [b.loadBigInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: resultCallFuncRef)])

        // It is also possible to change the slot and perform the call_indirect now pointing to a
        // different function as long as signatures still match.
        b.callMethod("set", on: table, withArgs: [b.loadInt(0), b.getProperty(module2.getExportedMethod(at: 3), of: exports)])
        let resultNew = b.callFunction(callIndirectSig0, withArgs: [b.loadInt(0), b.loadBigInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: resultNew)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "11\n52\n42,1\n84\n")
    }

    func testCallDirect() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let callee = wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => [.wasmi32]) { function, label, params in
                return [function.wasmi32BinOp(params[0], params[1], binOpKind: .Sub)]
            }

            let calleeMultiResult = wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { function, label, params in
                return [function.consti32(100), function.consti32(200)]
            }

            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, params in
                let callResult = function.wasmCallDirect(signature: [.wasmi32, .wasmi32] => [.wasmi32], function: callee, functionArgs: [params[0], function.consti32(1)])
                let multiResult = function.wasmCallDirect(signature: [] => [.wasmi32, .wasmi32], function: calleeMultiResult, functionArgs: [])
                let sum1 = function.wasmi32BinOp(multiResult[0], multiResult[1], binOpKind: .Add)
                return [function.wasmi32BinOp(sum1, callResult[0], binOpKind: .Add)]
            }
        }

        let exports = module.loadExports()
        let wasmFunction = b.getProperty(module.getExportedMethod(at: 2), of: exports)
        let result = b.callFunction(wasmFunction, withArgs: [b.loadInt(42)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [result])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "341\n")
    }

    func testReturnCallDirect() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let callee = wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { function, label, params in
                return [function.consti32(100), function.consti32(200)]
            }

            wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { function, label, params in
                function.wasmReturnCallDirect(signature: [] => [.wasmi32, .wasmi32], function: callee, functionArgs: [])
                return [function.consti32(-1), function.consti32(-1)]
            }
        }

        let exports = module.loadExports()
        let wasmFunction = b.getProperty(module.getExportedMethod(at: 1), of: exports)
        let result = b.callFunction(wasmFunction, withArgs: [b.loadInt(42)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(result)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "100,200\n")
    }

    func testReturnCallIndirect() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters(.bigint)) { params in
            b.doReturn(b.binary(params[0], b.loadBigInt(42), with: .Add))
        }

        let module = b.buildWasmModule { wasmModule in
            let wasmFunction = wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64, .wasmi64]) { function, label, params in
                return [params[0], function.consti64(1)]
            }
            let table = wasmModule.addTable(elementType: .wasmFuncRef,
                                            minSize: 10,
                                            definedEntries: [.init(indexInTable: 0, signature: [.wasmi64] => [.wasmi64, .wasmi64]), .init(indexInTable: 1, signature: [.wasmi64] => [.wasmi64])],
                                            definedEntryValues: [wasmFunction, jsFunction],
                                            isTable64: false)
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64, .wasmi64]) { fn, label, params in
                fn.wasmReturnCallIndirect(signature: [.wasmi64] => [.wasmi64, .wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
                return [fn.consti64(-1), fn.consti64(-1)]
            }
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { fn, label, params in
                fn.wasmReturnCallIndirect(signature: [.wasmi64] => [.wasmi64], table: table, functionArgs: [params[1]], tableIndex: params[0])
                return [fn.consti64(-1)]
            }
        }

        let exports = module.loadExports()

        let callIndirectSig0 = b.getProperty(module.getExportedMethod(at: 1), of: exports)
        let result0 = b.callFunction(callIndirectSig0, withArgs: [b.loadInt(0), b.loadBigInt(10)])
        let callIndirectSig1 = b.getProperty(module.getExportedMethod(at: 2), of: exports)
        let result1 = b.callFunction(callIndirectSig1, withArgs: [b.loadInt(1), b.loadBigInt(10)])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])

        testForOutput(program: jsProg, runner: runner, outputString: "10,1\n52\n")
    }

    // Test every memory testcase for both memory32 and memory64.

    func importedMemoryTestCase(isShared: Bool, isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmMemory: Variable = b.createWasmMemory(minPages: 10, maxPages: 20, isShared: isShared, isMemory64: isMemory64)
        XCTAssertEqual(b.type(of: wasmMemory), .wasmMemory(limits: Limits(min: 10, max: 20), isShared: isShared, isMemory64: isMemory64))

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                let value = function.consti32(1337)
                let offset = isMemory64 ? function.consti64(10) : function.consti32(10)
                function.wasmMemoryStore(memory: wasmMemory, dynamicOffset: offset, value: value, storeType: .I32StoreMem, staticOffset: 0)
                let val = function.wasmMemoryLoad(memory: wasmMemory, dynamicOffset: offset, loadType: .I64LoadMem, staticOffset: 0)
                return [val]
            }
        }

        let viewBuiltin = b.createNamedVariable(forBuiltin: "DataView")
        XCTAssertEqual(b.type(of: b.getProperty("buffer", of: wasmMemory)), .jsArrayBuffer | .jsSharedArrayBuffer)
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
        try importedMemoryTestCase(isShared: false, isMemory64: false)
        try importedMemoryTestCase(isShared: true, isMemory64: false)
    }

    func testImportedMemory64() throws {
        try importedMemoryTestCase(isShared: false, isMemory64: true)
        try importedMemoryTestCase(isShared: true, isMemory64: true)
    }

    func defineMemory(isShared: Bool, isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isShared: isShared, isMemory64: isMemory64)
            let memoryTypeInfo = b.type(of: memory).wasmMemoryType!

            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                let value = function.consti64(1337)
                let storeOffset = function.memoryArgument(8, memoryTypeInfo)
                function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: .I64StoreMem, staticOffset: 2)
                let loadOffset = function.memoryArgument(10, memoryTypeInfo)
                let val = function.wasmMemoryLoad(memory: memory, dynamicOffset: loadOffset, loadType: .I32LoadMem, staticOffset: 0)
                return [val]
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForOutput(program: jsProg, runner: runner, outputString: "1337\n")
    }

    func testDefineMemory32() throws {
        try defineMemory(isShared: false, isMemory64: false)
        try defineMemory(isShared: true, isMemory64: false)
    }

    func testDefineMemory64() throws {
        try defineMemory(isShared: false, isMemory64: true)
        try defineMemory(isShared: true, isMemory64: true)
    }

    func simpleDataSegmentInit(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: isMemory64)
                let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
                let segment = wasmModule.addDataSegment(segment: [UInt8]("---AAAABBBB".utf8))

                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in
                    let i32 = f.consti32
                    let memIdx: (Int64) -> Variable = { v in f.memoryArgument(v, memoryTypeInfo) }
                    f.wasmMemoryInit(dataSegment: segment, memory: memory, memoryOffset: memIdx(16), dataSegmentOffset: i32(3), nrOfBytesToUpdate: i32(8))
                    return [f.wasmMemoryLoad(memory: memory, dynamicOffset: memIdx(16), loadType: .I64LoadMem, staticOffset: 0)]

                }
            }

            let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])
        }

        // "AAAABBBB" -> 0x4242424241414141
        testForOutput(program: jsProg, runner: runner, outputString: "4774451407296217409\n")
    }

    func testDataSegmentWithMemory32() throws {
        try simpleDataSegmentInit(isMemory64: false)
    }

    func testDataSegmentWithMemory64() throws {
        try simpleDataSegmentInit(isMemory64: true)
    }

    func testDropDataSegment() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            b.buildWasmModule { wasmModule in
                let segment = wasmModule.addDataSegment(segment: [0xAA])

                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    f.wasmDropDataSegment(dataSegment: segment)
                    return []
                }
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    func testDropDataSegmentTwoTimes() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            b.buildWasmModule { wasmModule in
                let segment = wasmModule.addDataSegment(segment: [0xAA])

                wasmModule.addWasmFunction(with: [] => []) {
                    f, _, _ in
                    f.wasmDropDataSegment(dataSegment: segment)
                    f.wasmDropDataSegment(dataSegment: segment)
                    return []
                }
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    func testInitSingleMemoryFromTwoSegments(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let memory = wasmModule.addMemory(minPages: 1, isMemory64: isMemory64)
                let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
                let segment1 = wasmModule.addDataSegment(segment: [UInt8]("AAAA".utf8))
                let segment2 = wasmModule.addDataSegment(segment: [UInt8]("BBBB".utf8))

                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in
                    let i32 = f.consti32
                    let memIdx: (Int64) -> Variable = { v in f.memoryArgument(v, memoryTypeInfo) }
                    f.wasmMemoryInit(dataSegment: segment1, memory: memory, memoryOffset: memIdx(0), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(4))
                    f.wasmMemoryInit(dataSegment: segment2, memory: memory, memoryOffset: memIdx(4), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(4))
                    return [f.wasmMemoryLoad(memory: memory, dynamicOffset: memIdx(0), loadType: .I64LoadMem, staticOffset: 0)]
                }
            }

            let res = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])
        }

        // "AAAABBBB" -> 0x4242424241414141
        testForOutput(program: jsProg, runner: runner, outputString: "4774451407296217409\n")
    }

    func testInitSingleMemoryFromTwoSegments32() throws {
        try testInitSingleMemoryFromTwoSegments(isMemory64: false)
    }

    func testInitSingleMemoryFromTwoSegments64() throws {
        try testInitSingleMemoryFromTwoSegments(isMemory64: true)
    }

    func testInitTwoMemoriesFromOneSegment(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let memory1 = wasmModule.addMemory(minPages: 1, isMemory64: isMemory64)
                let memoryTypeInfo = b.type(of: memory1).wasmMemoryType!
                let memory2 = wasmModule.addMemory(minPages: 1, isMemory64: isMemory64)
                let segment = wasmModule.addDataSegment(segment: [UInt8]("AAAABBBB".utf8))

                wasmModule.addWasmFunction(with: [] => [.wasmi64, .wasmi64]) { f, _, _ in
                    let i32 = f.consti32
                    let memIdx: (Int64) -> Variable = { v in f.memoryArgument(v, memoryTypeInfo) }
                    f.wasmMemoryInit(dataSegment: segment, memory: memory1, memoryOffset: memIdx(0), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(8))
                    f.wasmMemoryInit(dataSegment: segment, memory: memory2, memoryOffset: memIdx(0), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(8))
                    let val1 = f.wasmMemoryLoad(memory: memory1, dynamicOffset: memIdx(0), loadType: .I64LoadMem, staticOffset: 0)
                    let val2 = f.wasmMemoryLoad(memory: memory2, dynamicOffset: memIdx(0), loadType: .I64LoadMem, staticOffset: 0)
                    return [val1, val2]
                }
            }

            let res = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])
        }

        // "AAAABBBB" -> 0x4242424241414141
        testForOutput(program: jsProg, runner: runner, outputString: "4774451407296217409,4774451407296217409\n")
    }

    func testInitTwoMemoriesFromOneSegment32() throws {
        try testInitTwoMemoriesFromOneSegment(isMemory64: false)
    }

    func testInitTwoMemoriesFromOneSegment64() throws {
        try testInitTwoMemoriesFromOneSegment(isMemory64: true)
    }

    func testMemoryInitOutOfBoundsMemory(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let memory = wasmModule.addMemory(minPages: 1, isMemory64: isMemory64)
                let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
                let segment = wasmModule.addDataSegment(segment: [0xAA])

                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    // Memory size is one page (65536 bytes), so this should be out of bounds.
                    let i32 = f.consti32
                    let memIdx: (Int64) -> Variable = { v in f.memoryArgument(v, memoryTypeInfo) }
                    f.wasmMemoryInit(dataSegment: segment, memory: memory, memoryOffset: memIdx(65536), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(1))
                    return []
                }
            }
            b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        }

        testForErrorOutput(program: jsProg, runner: runner, errorMessageContains: "RuntimeError: memory access out of bounds")
    }

    func testMemoryInitOutOfBoundsMemory32() throws {
        try testMemoryInitOutOfBoundsMemory(isMemory64: false)
    }

    func testMemoryInitOutOfBoundsMemory64() throws {
        try testMemoryInitOutOfBoundsMemory(isMemory64: true)
    }

    func testMemoryInitOutOfBoundsSegment(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let memory = wasmModule.addMemory(minPages: 1, isMemory64: isMemory64)
                let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
                let segment = wasmModule.addDataSegment(segment: [0xAA])

                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    // Data segment size is 1, so this should be out of bounds.
                    let i32 = f.consti32
                    let memIdx: (Int64) -> Variable = { v in f.memoryArgument(v, memoryTypeInfo) }
                    f.wasmMemoryInit(dataSegment: segment, memory: memory, memoryOffset: memIdx(0), dataSegmentOffset: i32(0), nrOfBytesToUpdate: i32(2))
                    return []
                }
            }
            b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        }

        testForErrorOutput(program: jsProg, runner: runner, errorMessageContains: "RuntimeError: memory access out of bounds")
    }

    func testMemoryInitOutOfBoundsSegment32() throws {
        try testMemoryInitOutOfBoundsSegment(isMemory64: false)
    }

    func testMemoryInitOutOfBoundsSegment64() throws {
        try testMemoryInitOutOfBoundsSegment(isMemory64: true)
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

            wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                let value = function.consti64(1337)
                let storeOffset = function.consti64(1 << 32)
                function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: .I64StoreMem, staticOffset: 2)
                return []
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
                wasmModule.addWasmFunction(with: [] => [loadType.numberType()]) { function, _, _ in
                    let loadOffset = isMemory64 ? function.consti64(9) : function.consti32(9)
                    let val = function.wasmMemoryLoad(memory: memory, dynamicOffset: loadOffset, loadType: loadType, staticOffset: 0)
                    return [val]
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
                wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    let storeOffset = isMemory64 ? function.consti64(13) : function.consti32(13)
                    let value = switch storeType.numberType() {
                        case .wasmi32: function.consti32(8)
                        case .wasmi64: function.consti64(8)
                        case .wasmf32: function.constf32(8.4)
                        case .wasmf64: function.constf64(8.4)
                        case .wasmSimd128: function.constSimd128(value: Array(0..<16))
                        default: fatalError("Non-existent value to be stored")
                    }
                    function.wasmMemoryStore(memory: memory, dynamicOffset: storeOffset, value: value, storeType: storeType, staticOffset: 2)
                    return []
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

    func multiMemory(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let memory0: Variable = b.createWasmMemory(minPages: 10, maxPages: 20, isMemory64: isMemory64)
        XCTAssertEqual(b.type(of: memory0), .wasmMemory(limits: Limits(min: 10, max: 20), isShared: false, isMemory64: isMemory64))

        let module = b.buildWasmModule { wasmModule in
            let memory1 = wasmModule.addMemory(minPages: 2, isMemory64: isMemory64)
            let memory2 = wasmModule.addMemory(minPages: 2, isMemory64: isMemory64)
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                let offset = isMemory64 ? function.consti64(Int64(42)) : function.consti32(Int32(42))
                function.wasmMemoryStore(memory: memory0, dynamicOffset: offset, value: function.constf32(1.0), storeType: .F32StoreMem, staticOffset: 0)
                function.wasmMemoryStore(memory: memory1, dynamicOffset: offset, value: function.constf64(2.0), storeType: .F64StoreMem, staticOffset: 0)
                function.wasmMemoryStore(memory: memory2, dynamicOffset: offset, value: function.consti32(3), storeType: .I32StoreMem, staticOffset: 0)
                let load0 = function.wasmMemoryLoad(memory: memory0, dynamicOffset: offset, loadType: .F32LoadMem, staticOffset: 0)
                let load1 = function.wasmMemoryLoad(memory: memory1, dynamicOffset: offset, loadType: .F64LoadMem, staticOffset: 0)
                let load2 = function.wasmMemoryLoad(memory: memory2, dynamicOffset: offset, loadType: .I32LoadMem, staticOffset: 0)

                let trunc0 = function.truncatef32Toi32(load0, isSigned: true)
                let trunc1 = function.truncatef64Toi32(load1, isSigned: true)

                let sum = function.wasmi32BinOp(
                    function.wasmi32BinOp(trunc0, trunc1, binOpKind: .Add),
                    load2, binOpKind: .Add)
                return [sum]
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "6\n")
    }

    func testMultiMemory32() throws {
        try multiMemory(isMemory64: false)
    }

    func testMultiMemory64() throws {
        try multiMemory(isMemory64: true)
    }

    func memorySize(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let memoryA = b.createWasmMemory(minPages: 7, maxPages: 7, isShared: false, isMemory64: isMemory64)

        let module = b.buildWasmModule { wasmModule in
            let memoryB = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: isMemory64)
            let memoryC = wasmModule.addMemory(minPages: 0, maxPages: 1, isMemory64: isMemory64)
            [memoryA, memoryB, memoryC].forEach { memory in
                let addrType: ILType = isMemory64 ? .wasmi64 : .wasmi32
                wasmModule.addWasmFunction(with: [] => [addrType, addrType, addrType]) { function, label, args in
                    let growBy = isMemory64 ? function.consti64(1) : function.consti32(1)
                    return [
                        function.wasmMemorySize(memory: memory),
                        function.wasmMemoryGrow(memory: memory, growByPages: growBy),
                        function.wasmMemorySize(memory: memory),
                    ]
                }
            }
        }

        (0..<3).forEach {
            let res = b.callMethod(module.getExportedMethod(at: $0), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])
        }

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForOutput(program: jsProg, runner: runner, outputString: "7,-1,7\n5,5,6\n0,0,1\n")
    }

    func testMemorySize32() throws {
        try memorySize(isMemory64: false)
    }

    func testMemorySize64() throws {
        try memorySize(isMemory64: true)
    }

    func memoryBulkOperations(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addMemory(minPages: 1, maxPages: 2, isMemory64: isMemory64)
            let memory = wasmModule.addMemory(minPages: 1, maxPages: 2, isMemory64: isMemory64)
            let memoryTypeInfo = b.type(of: memory).wasmMemoryType!

            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                let fillOffset = function.memoryArgument(100, memoryTypeInfo)
                let byteToSet = function.consti32(0xAA)
                let nrOfBytesToUpdate = function.memoryArgument(4, memoryTypeInfo)
                function.wasmMemoryFill(memory: memory, offset: fillOffset, byteToSet: byteToSet, nrOfBytesToUpdate: nrOfBytesToUpdate)
                let loadOffset =  function.memoryArgument(102, memoryTypeInfo)
                let val = function.wasmMemoryLoad(memory: memory, dynamicOffset: loadOffset, loadType: .I32LoadMem, staticOffset: 0)
                return [val]
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        testForOutput(program: jsProg, runner: runner, outputString: "43690\n") // 0x 00 00 AA AA
    }

    func testMemoryBulkOperations32() throws {
        try memoryBulkOperations(isMemory64: false)
    }

    func testMemoryBulkOperations64() throws {
        try memoryBulkOperations(isMemory64: true)
    }

    func memoryCopy(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { wasmModule in
                let mem1 = wasmModule.addMemory(minPages: 1, maxPages: 2, isMemory64: isMemory64)
                let mem2 = wasmModule.addMemory(minPages: 1, maxPages: 2, isMemory64: isMemory64)
                let memTypeInfo = b.type(of: mem1).wasmMemoryType!

                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32, .wasmi32]) { function, _, _ in
                    let setValueAtOffset = { (value: Int32, offsetValue: Int64) -> () in
                        let valToSet = function.consti32(value)
                        let offset = function.memoryArgument(offsetValue, memTypeInfo)
                        function.wasmMemoryStore(memory: mem1, dynamicOffset: offset, value: valToSet, storeType: .I32StoreMem, staticOffset: 0)
                    }
                    setValueAtOffset(111, 4)
                    setValueAtOffset(222, 8)
                    setValueAtOffset(333, 12)

                    let dstOffset = function.memoryArgument(128, memTypeInfo)
                    let srcOffset = function.memoryArgument(8, memTypeInfo)
                    let size = function.memoryArgument(4, memTypeInfo)
                    function.wasmMemoryCopy(dstMemory: mem2, srcMemory: mem1, dstOffset: dstOffset, srcOffset: srcOffset, size: size)

                    let loadAtOffset = { (offsetValue: Int64) -> Variable in
                        let dynamicOffset = function.memoryArgument(offsetValue, memTypeInfo)
                        return function.wasmMemoryLoad(memory: mem2, dynamicOffset: dynamicOffset, loadType: .I32LoadMem, staticOffset: 0)
                    }
                    return [loadAtOffset(124), loadAtOffset(128), loadAtOffset(132)]
                }
            }

            let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res0)])
        }

        testForOutput(program: jsProg, runner: runner, outputString: "0,222,0\n")
    }

    func testMemoryCopy32() throws {
        try memoryCopy(isMemory64: false)
    }

    func testMemoryCopy64() throws {
        try memoryCopy(isMemory64: true)
    }

    func wasmSimdLoadStore(isMemory64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let testCases: [((ProgramBuilder.WasmModule, Variable) -> Void, String)] = [
            // Test v128.load.
            ({wasmModule, memory in
                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                    value: function.consti64(3), storeType: .I64StoreMem, staticOffset: 0)
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(8),
                    value: function.consti64(6), storeType: .I64StoreMem, staticOffset: 0)

                    let val = function.wasmSimdLoad(kind: .LoadS128, memory: memory,
                        dynamicOffset: const(0), staticOffset: 0)
                    let sum = function.wasmi64BinOp(
                        function.wasmSimdExtractLane(kind: .I64x2, val, 0),
                        function.wasmSimdExtractLane(kind: .I64x2, val, 1), binOpKind: .Add)
                    return [sum]
                }
            }, "9"),
            // Test v128.store.
            ({wasmModule, memory in
                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I64x2, function.consti64(21))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 0)
                    let loadValue1 = function.wasmMemoryLoad(memory: memory,
                        dynamicOffset: const(0), loadType: .I64LoadMem, staticOffset: 0)
                    let loadValue2 = function.wasmMemoryLoad(memory: memory,
                        dynamicOffset: const(8), loadType: .I64LoadMem, staticOffset: 0)
                    return [function.wasmi64BinOp(loadValue1, loadValue2, binOpKind: .Add)]
                }
            }, "42"),
            // Test v128.load8x8_s.
            ({wasmModule, memory in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I8x16, function.consti32(-1))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load8x8S, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: .I16x8S, loaded, $0)}
                }
            }, "-1,-1,-1,-1,-1,-1,-1,-1"),
            // Test v128.load8x8_u.
            ({wasmModule, memory in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I8x16, function.consti32(255))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load8x8U, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: .I16x8U, loaded, $0)}
                }
            }, "255,255,255,255,255,255,255,255"),
            // Test v128.load16x4_s.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I16x8, function.consti32(-2))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load16x4S, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: .I32x4, loaded, $0)}
                }
            }, "-2,-2,-2,-2"),
            // Test v128.load16x4_u.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I16x8, function.consti32(65432))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load16x4U, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: .I32x4, loaded, $0)}
                }
            }, "65432,65432,65432,65432"),
            // Test v128.load32x2_s.
            ({wasmModule, memory in
                let returnType = (0..<2).map {_ in ILType.wasmi64}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(kind: .I32x4, function.consti32(-3))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load32x2S, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<2).map {function.wasmSimdExtractLane(kind: .I64x2, loaded, $0)}
                }
            }, "-3,-3"),
            // Test v128.load32x2_u.
            ({wasmModule, memory in
                let returnType = (0..<2).map {_ in ILType.wasmi64}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    let storeValue = function.wasmSimdSplat(
                        kind: .I32x4, function.consti32(-171510507))
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: storeValue, storeType: .S128StoreMem, staticOffset: 16)
                    let loaded = function.wasmSimdLoad(kind: .Load32x2U, memory: memory,
                        dynamicOffset: const(16), staticOffset: 0)
                    return (0..<2).map {function.wasmSimdExtractLane(kind: .I64x2, loaded, $0)}
                }
            }, "4123456789,4123456789"),
            // Test v128.load8_splat.
            ({wasmModule, memory in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(7), storeType: .I32StoreMem8, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load8Splat, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: .I8x16S, loaded, $0)}
                }
            }, "7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7"),
            // Test v128.load16_splat.
            ({wasmModule, memory in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(8), storeType: .I32StoreMem16, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load16Splat, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: .I16x8S, loaded, $0)}
                }
            }, "8,8,8,8,8,8,8,8"),
            // Test v128.load32_splat.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(9), storeType: .I32StoreMem, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load32Splat, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: .I32x4, loaded, $0)}
                }
            }, "9,9,9,9"),
            // Test v128.load64_splat.
            ({wasmModule, memory in
                let returnType = (0..<2).map {_ in ILType.wasmi64}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti64(10), storeType: .I64StoreMem, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load64Splat, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<2).map {function.wasmSimdExtractLane(kind: .I64x2, loaded, $0)}
                }
            }, "10,10"),
            // Test v128.load32_zero.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(11), storeType: .I32StoreMem, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load32Zero, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: .I32x4, loaded, $0)}
                }
            }, "11,0,0,0"),
            // Test v128.load64_zero.
            ({wasmModule, memory in
                let returnType = (0..<2).map {_ in ILType.wasmi64}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti64(12), storeType: .I64StoreMem, staticOffset: 32)
                    let loaded = function.wasmSimdLoad(kind: .Load64Zero, memory: memory,
                        dynamicOffset: const(32), staticOffset: 0)
                    return (0..<2).map {function.wasmSimdExtractLane(kind: .I64x2, loaded, $0)}
                }
            }, "12,0"),
            // Test v128.load8_lane and v128.store8_lane.
            ({wasmModule, memory in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(13), storeType: .I32StoreMem8, staticOffset: 64)
                    let splat = function.wasmSimdSplat(kind: .I8x16, function.consti32(42))
                    let loaded = function.wasmSimdLoadLane(kind: .Load8, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: splat, lane: 15)
                    function.wasmSimdStoreLane(kind: .Store8, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, from: loaded, lane: 15)
                    let reloaded = function.wasmSimdLoadLane(kind: .Load8, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: loaded, lane: 1)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: .I8x16U, reloaded, $0)}
                }
            }, "42,13,42,42,42,42,42,42,42,42,42,42,42,42,42,13"),
            // Test v128.load16_lane and v128.store16_lane.
            ({wasmModule, memory in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(14), storeType: .I32StoreMem16, staticOffset: 64)
                    let splat = function.wasmSimdSplat(kind: .I16x8, function.consti32(42))
                    let loaded = function.wasmSimdLoadLane(kind: .Load16, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: splat, lane: 7)
                    function.wasmSimdStoreLane(kind: .Store16, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, from: loaded, lane: 7)
                    let reloaded = function.wasmSimdLoadLane(kind: .Load16, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: loaded, lane: 1)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: .I16x8U, reloaded, $0)}
                }
            }, "42,14,42,42,42,42,42,14"),
            // Test v128.load32_lane and v128.store32_lane.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti32(15), storeType: .I32StoreMem, staticOffset: 64)
                    let splat = function.wasmSimdSplat(kind: .I32x4, function.consti32(42))
                    let loaded = function.wasmSimdLoadLane(kind: .Load32, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: splat, lane: 3)
                    function.wasmSimdStoreLane(kind: .Store32, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, from: loaded, lane: 3)
                    let reloaded = function.wasmSimdLoadLane(kind: .Load32, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: loaded, lane: 1)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: .I32x4, reloaded, $0)}
                }
            }, "42,15,42,15"),
            // Test v128.load64_lane and v128.store64_lane.
            ({wasmModule, memory in
                let returnType = (0..<4).map {_ in ILType.wasmi64}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let const = isMemory64 ? function.consti64 : {function.consti32(Int32($0))}
                    function.wasmMemoryStore(memory: memory, dynamicOffset: const(0),
                        value: function.consti64(16), storeType: .I64StoreMem, staticOffset: 64)
                    let splat = function.wasmSimdSplat(kind: .I64x2, function.consti64(42))
                    let loaded = function.wasmSimdLoadLane(kind: .Load64, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: splat, lane: 1)
                    function.wasmSimdStoreLane(kind: .Store64, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, from: loaded, lane: 1)
                    let reloaded = function.wasmSimdLoadLane(kind: .Load64, memory: memory,
                        dynamicOffset: const(0), staticOffset: 64, into: loaded, lane: 0)
                    return [
                        function.wasmSimdExtractLane(kind: .I64x2, loaded, 0),
                        function.wasmSimdExtractLane(kind: .I64x2, loaded, 1),
                        function.wasmSimdExtractLane(kind: .I64x2, reloaded, 0),
                        function.wasmSimdExtractLane(kind: .I64x2, reloaded, 1)]
                }
            }, "42,16,16,16"),
        ]

        let module = b.buildWasmModule { wasmModule in
            let memory = wasmModule.addMemory(minPages: 5, maxPages: 12, isMemory64: isMemory64)
            for (createWasmFunction, _) in testCases {
                createWasmFunction(wasmModule, memory)
            }
        }

        for (i, _) in testCases.enumerated() {
            let res = b.callMethod(module.getExportedMethod(at: i), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"),
                withArgs: [b.callMethod("toString", on: res)])
        }

        let jsProg = fuzzer.lifter.lift(b.finalize())
        let expected = testCases.map {$0.1}.joined(separator: "\n") + "\n"
        testForOutput(program: jsProg, runner: runner, outputString: expected)
    }

    func testWasmSimdLoadStoreOnMemory32() throws {
        try wasmSimdLoadStore(isMemory64: false)
    }

    func testWasmSimdLoadStoreOnMemory64() throws {
        try wasmSimdLoadStore(isMemory64: true)
    }

    func wasmSimdSplatAndExtractLane(splat: WasmSimdSplat.Kind,
                                     extractLane: WasmSimdExtractLane.Kind,
                                     replaceLane: WasmSimdReplaceLane.Kind) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(splat.laneType(), extractLane.laneType())
        XCTAssertEqual(extractLane.laneCount(), replaceLane.laneCount())

        let module = b.buildWasmModule { wasmModule in
            let sig = [splat.laneType()] => (0..<extractLane.laneCount()).map {_ in extractLane.laneType()}
            wasmModule.addWasmFunction(with: sig) { function, label, args in
                var simdVal = function.wasmSimdSplat(kind: splat, args[0])
                // Replace each lane with the previous lane + 1.
                for i in 1..<extractLane.laneCount() {
                    let val = function.wasmSimdExtractLane(kind: extractLane, simdVal, i-1)
                    let sum = switch extractLane.laneType() {
                        case .wasmi32:
                            function.wasmi32BinOp(val, function.consti32(1), binOpKind: .Add)
                        case .wasmi64:
                            function.wasmi64BinOp(val, function.consti64(1), binOpKind: .Add)
                        case .wasmf32:
                            function.wasmf32BinOp(val, function.constf32(1), binOpKind: .Add)
                        case .wasmf64:
                            function.wasmf64BinOp(val, function.constf64(1), binOpKind: .Add)
                        default:
                            fatalError("invalid lane type \(extractLane.laneType())")
                    }
                    simdVal = function.wasmSimdReplaceLane(kind: replaceLane, simdVal, sum, i)
                }
                // Finally extract all the lanes and return them.
                return (0..<extractLane.laneCount()).map {function.wasmSimdExtractLane(kind: extractLane, simdVal, $0)}
            }
        }

        let arg = extractLane.laneType() == .wasmi64 ? b.loadBigInt(7): b.loadInt(7)
        let res = b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports(), withArgs: [arg])
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.callMethod("toString", on: res)])

        let jsProg = fuzzer.lifter.lift(b.finalize())
        let expected = (0..<extractLane.laneCount()).map {String(7 + $0)}.joined(separator: ",")
        testForOutput(program: jsProg, runner: runner, outputString: "\(expected)\n")
    }

    func testWasmSimdSplatExtractAndReplaceLane() throws {
        for (splat, extractLane, replaceLane) in [
            (WasmSimdSplat.Kind.I8x16, WasmSimdExtractLane.Kind.I8x16S, WasmSimdReplaceLane.Kind.I8x16),
            (WasmSimdSplat.Kind.I8x16, WasmSimdExtractLane.Kind.I8x16U, WasmSimdReplaceLane.Kind.I8x16),
            (WasmSimdSplat.Kind.I16x8, WasmSimdExtractLane.Kind.I16x8S, WasmSimdReplaceLane.Kind.I16x8),
            (WasmSimdSplat.Kind.I16x8, WasmSimdExtractLane.Kind.I16x8U, WasmSimdReplaceLane.Kind.I16x8),
            (WasmSimdSplat.Kind.I32x4, WasmSimdExtractLane.Kind.I32x4, WasmSimdReplaceLane.Kind.I32x4),
            (WasmSimdSplat.Kind.I64x2, WasmSimdExtractLane.Kind.I64x2, WasmSimdReplaceLane.Kind.I64x2),
        ] {
            try wasmSimdSplatAndExtractLane(splat: splat, extractLane: extractLane, replaceLane: replaceLane)
        }
    }

    func testWasmSimd128() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        // note: only works on little-endian platforms
        let uint16ArrayToByteArray: ([UInt16]) -> [UInt8] = { uint16Array in
        return uint16Array.flatMap { value -> [UInt8] in
                let highByte = UInt8((value >> 8) & 0xFF)
                let lowByte = UInt8(value & 0xFF)
                return [lowByte, highByte]
            }
        }

        let floatToByteArray = { (values: [Float]) -> [UInt8] in
            assert(values.count == 4)
            var byteArray: [UInt8] = []
            for value in values {
                var bits = value.bitPattern.littleEndian
                let data = Data(bytes: &bits, count: MemoryLayout<UInt32>.size)
                byteArray.append(contentsOf: data)
            }
            return byteArray
        }

        let doubleToByteArray = { (values: [Double]) -> [UInt8] in
            assert(values.count == 2)
            var byteArray: [UInt8] = []
            for value in values {
                var bits = value.bitPattern.littleEndian
                let data = Data(bytes: &bits, count: MemoryLayout<UInt64>.size)
                byteArray.append(contentsOf: data)
            }
            return byteArray
        }


        let testCases: [((ProgramBuilder.WasmModule) -> Void, String)] = [
            // Test q15mulr_sat_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([16383, 16384, 32767, 65535, 65535, 32765, UInt16(bitPattern: -32768), 32768]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([16384, 16384, 32767, 65535, 32768, 1, UInt16(bitPattern: -32768), 1]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.q15mulr_sat_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "8192,8192,32766,0,1,1,32767,-1"),
            // // Test narrow_s
            ({wasmModule in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 128, 256, 0, 1, 128, 256]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([-1, -128, -129, -256, -1, -128, -129, -256].map( {UInt16(bitPattern: $0)})))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i8x16, WasmSimd128IntegerBinOpKind.narrow_s)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I8x16S, result, $0)}
                }
            }, "0,1,127,127,0,1,127,127,-1,-128,-128,-128,-1,-128,-128,-128"),
            // Test narrow_u
            ({wasmModule in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 127, 128, 255, 256, 512, 1024]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 127, 128, 255, 256, 512, 1024]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i8x16, WasmSimd128IntegerBinOpKind.narrow_u)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I8x16U, result, $0)}
                }
            }, "0,1,127,128,255,255,255,255,0,1,127,128,255,255,255,255"),
            // Test shl
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 4, 8, 9, 16, 18]))
                    let varB = function.consti32(1)
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.shl)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "0,2,4,8,16,18,32,36"),
            // Test shr_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 4, 8, 9, UInt16(bitPattern: -16), 18]))
                    let varB = function.consti32(1)
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.shr_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "0,0,1,2,4,4,-8,9"),
            // Test shr_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 4, 8, 9, UInt16(bitPattern: -16), 18]))
                    let varB = function.consti32(1)
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.shr_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "0,0,1,2,4,4,32760,9"),
            // Test add
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 9, 10, 11, 12, 13, 14, 32767]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.add)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "8,10,12,14,16,18,20,-32762"),
            // Test add_sat_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray(
                        [UInt16(bitPattern: -32768), 32767, UInt16(bitPattern: -32768), UInt16(bitPattern: -32768), 32767, 32767, 32767, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray(
                        [UInt16(bitPattern: -32768), 32767, UInt16(bitPattern: -1), 1, 1, UInt16(bitPattern: -1), UInt16(bitPattern: -2), 4]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.add_sat_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "-32768,32767,-32768,-32767,32767,32766,32765,11"),
            // Test add_sat_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray(
                        [65534, 65534, 65534, 8, 9, 10, 11, 12]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray(
                        [0, 1, 2, 3, 4, 5, 6, 7]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.add_sat_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "65534,65535,65535,11,13,15,17,19"),
            // Test sub
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([UInt16(bitPattern:-2), 3, 6, 9, 12, 15, 18, 21]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([32767, 0, 1, 2, 3, 4, 5, 6]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.sub)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "32767,3,5,7,9,11,13,15"),
            // Test sub_sat_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([UInt16(bitPattern:-2), 32000, 6, 9, 12, 15, 18, 21]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([32767, UInt16(bitPattern:-1000), 1, 2, 3, 4, 5, 6]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.sub_sat_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "-32768,32767,5,7,9,11,13,15"),
            // Test sub_sat_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 3, 6, 9, 12, 15, 18, 21]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([1, 0, 1, 2, 3, 4, 5, 6]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.sub_sat_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "0,3,5,7,9,11,13,15"),
            // Test mul
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 9, 10, 11, 12, 13, 14, 15]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.mul)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "0,9,20,33,48,65,84,105"),
            // Test min_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 65535]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 9, 10, 11, 12, 13, 14, 65534]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.min_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "0,1,2,3,4,5,6,65534"),
            // Test min_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 8, 0, UInt16(bitPattern:-8), 4, UInt16(bitPattern:-5), 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 0, UInt16(bitPattern:-8), 0, 0, UInt16(bitPattern:-12), 13, 14]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.min_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "0,0,-8,-8,0,-12,6,7"),
            // Test max_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 65535]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 9, 10, 11, 12, 13, 14, 65534]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.max_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "8,9,10,11,12,13,14,65535"),
            // Test max_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 8, 0, UInt16(bitPattern:-8), 4, UInt16(bitPattern:-5), 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 0, UInt16(bitPattern:-8), 0, 0, UInt16(bitPattern:-12), 13, 14]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.max_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "8,8,0,0,4,-5,13,14"),
            // Test dot_i16x8_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 4, 5, UInt16(bitPattern: -4), 5, 32767, 32767]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([2, 3, 6, 7, 6, UInt16(bitPattern: -7), 32767, 32767]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i32x4, WasmSimd128IntegerBinOpKind.dot_i16x8_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "3,59,-59,2147352578"),
            // Test avgr_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 10, 12, 14, 16, 18, 20, 22]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.avgr_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "4,6,7,9,10,12,13,15"),
            // Test extmul_low_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, UInt16(bitPattern:-7)]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, UInt16(bitPattern: -10), 12, 14, 16, 18, 20, 22]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i32x4, WasmSimd128IntegerBinOpKind.extmul_low_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "0,-10,24,42"),
            // Test extmul_high_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, UInt16(bitPattern:-7)]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, UInt16(bitPattern: -10), 12, 14, 16, 18, 20, 22]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i32x4, WasmSimd128IntegerBinOpKind.extmul_high_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "64,90,120,-154"),
            // Test extmul_low_u
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 256, 2, 3, 4, 5, 6, 7]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, 256, 12, 14, 16, 18, 20, 22]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i32x4, WasmSimd128IntegerBinOpKind.extmul_low_u)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "0,65536,24,42"),
            // Test extmul_high_u
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([0, 1, 2, 3, 4, 5, 6, 256]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([8, UInt16(bitPattern: -10), 12, 14, 16, 18, 20, 65535]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i32x4, WasmSimd128IntegerBinOpKind.extmul_high_u)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "64,90,120,16776960"),
            // Test relaxed_swizzle.
            ({wasmModule in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: [1, 4, 6, 5, 6, 4, 3, 2, 1, 9, 23, 24, 43, 20, 11, 6])
                    let varB = function.constSimd128(value: [255, 3, 2, 1, 0, 4, 2, 3, 1, 14, 26, 11, 13, 7, 9, 6])
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i8x16, WasmSimd128IntegerBinOpKind.relaxed_swizzle)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I8x16S, result, $0)}
                }
            }, "0,5,6,4,1,6,6,5,4,11,(23|0),24,20,2,9,3"),
            // Test relaxed_q15mulr_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([16383, 16384, 32767, 65535, 65535, 32765, UInt16(bitPattern: -32768), 32768]))
                    let varB = function.constSimd128(value: uint16ArrayToByteArray([16384, 16384, 32767, 65535, 32768, 1, UInt16(bitPattern: -32768), 1]))
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.relaxed_q15_mulr_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "8192,8192,32766,0,1,1,(-32768|32767),-1"),
            // Test relaxed_dot_i8x16_i7x16_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 127, 127])
                    let varB = function.constSimd128(value:
                        [10, 20, UInt8(bitPattern:-30), 40, 100, UInt8(bitPattern:-100), 50, UInt8(bitPattern:-50), 10, 20, UInt8(bitPattern:-30), 40, 50, UInt8(bitPattern:-50), 100, UInt8(bitPattern:-6)])
                    let result = function.wasmSimd128IntegerBinOp(varA, varB, WasmSimd128Shape.i16x8, WasmSimd128IntegerBinOpKind.relaxed_dot_i8x16_i7x16_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "50,(70|838),(-100|1436),(-50|1998),(290|1998),(150|2966),(-50|3534),(11938|32767)"),
            // Test extadd_pairwise_i8x16_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [1, 2, 3, 4, UInt8(bitPattern:-1), UInt8(bitPattern:-2), UInt8(bitPattern:-3), UInt8(bitPattern:-4), 127, 127,
                         UInt8(bitPattern:-128), UInt8(bitPattern:-128), 10, UInt8(bitPattern:-10), 20, UInt8(bitPattern:-20)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extadd_pairwise_i8x16_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "3,7,-3,-7,254,-256,0,0"),
            // Test extadd_pairwise_i8x16_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: [1, 2, 3, 4, 255, 255, 128, 128, 10, 20, 30, 40, 50, 60, 70, 80])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extadd_pairwise_i8x16_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "3,7,510,256,30,70,110,150"),
            // Test extadd_pairwise_i16x8_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([1, 2, 3, 4, 32767, 32767, UInt16(bitPattern: -32768), UInt16(bitPattern: -32768)]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.extadd_pairwise_i16x8_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "3,7,65534,-65536"),
            // Test extadd_pairwise_i16x8_u
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([1, 2, 3, 4, 65535, 65535, 32768, 32768]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.extadd_pairwise_i16x8_u)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "3,7,131070,65536"),
            // Test abs
            // Note: abs(Int16.min) is Int16.min in Wasm.
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([1, UInt16(bitPattern: -1), 0, UInt16(bitPattern: -32768), 32767, UInt16(bitPattern: -32767), 10, UInt16(bitPattern: -10)]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.abs)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "1,1,0,-32768,32767,32767,10,10"), // abs(-32768) is -32768 in Wasm SIMD i16x8.abs
            // Test neg
            // Note: neg(Int16.min) is Int16.min in Wasm.
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: uint16ArrayToByteArray([1, UInt16(bitPattern: -1), 0, UInt16(bitPattern: -32768), 32767, 10, UInt16(bitPattern: -10), UInt16(bitPattern: -32767)]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.neg)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "-1,1,0,-32768,-32767,-10,10,32767"),
            // Test popcnt
            ({wasmModule in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [0, 1, 3, 7, 15, 255, 127, UInt8(bitPattern:-1), 128, UInt8(bitPattern:-2), UInt8(bitPattern:-3), UInt8(bitPattern:-4), UInt8(bitPattern:-5),
                        UInt8(bitPattern:-6), UInt8(bitPattern:-7), UInt8(bitPattern:-8)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i8x16, WasmSimd128IntegerUnOpKind.popcnt)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I8x16U, result, $0)} // Popcnt result is unsigned
                }
            }, "0,1,2,3,4,8,7,8,1,7,7,6,7,6,6,5"),
            // Test extend_low_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [UInt8(bitPattern: -1), 2, 3, 4, 5, 6, 7, 8,
                        UInt8(bitPattern: -1), UInt8(bitPattern: -2), UInt8(bitPattern: -3), UInt8(bitPattern: -4), UInt8(bitPattern: -5), UInt8(bitPattern: -6), UInt8(bitPattern: -7), UInt8(bitPattern: -8)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extend_low_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "-1,2,3,4,5,6,7,8"),
            // Test extend_high_s
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [1, 2, 3, 4, 5, 6, 7, 8,
                        UInt8(bitPattern: -1), UInt8(bitPattern: -2), UInt8(bitPattern: -3), UInt8(bitPattern: -4), UInt8(bitPattern: -5), UInt8(bitPattern: -6), UInt8(bitPattern: -7), UInt8(bitPattern: -8)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extend_high_s)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8S, result, $0)}
                }
            }, "-1,-2,-3,-4,-5,-6,-7,-8"),
            // Test extend_low_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [UInt8(bitPattern: -1), 2, 3, 4, 5, 6, 7, 8,
                        UInt8(bitPattern: -1), UInt8(bitPattern: -2), UInt8(bitPattern: -3), UInt8(bitPattern: -4), UInt8(bitPattern: -5), UInt8(bitPattern: -6), UInt8(bitPattern: -7), UInt8(bitPattern: -8)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extend_low_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "255,2,3,4,5,6,7,8"),
            // Test extend_high_u
            ({wasmModule in
                let returnType = (0..<8).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [1, 2, 3, 4, 5, 6, 7, 8,
                        UInt8(bitPattern: -1), UInt8(bitPattern: -2), UInt8(bitPattern: -3), UInt8(bitPattern: -4), UInt8(bitPattern: -5), UInt8(bitPattern: -6), UInt8(bitPattern: -7), UInt8(bitPattern: -8)])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i16x8, WasmSimd128IntegerUnOpKind.extend_high_u)
                    return (0..<8).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I16x8U, result, $0)}
                }
            }, "255,254,253,252,251,250,249,248"),
            // Test all_true positive
            ({wasmModule in
                let returnType = (0..<2).map {_ in ILType.wasmi32 }
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i8x16, WasmSimd128IntegerUnOpKind.all_true)
                    return [result, result] // hack to not confuse JS code extracting the result, as it always expects an array
                }
            }, "1,1"),
            // Test all_true negative
            ({wasmModule in
                let returnType = (0..<2).map {_ in ILType.wasmi32 }
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i8x16, WasmSimd128IntegerUnOpKind.all_true)
                    return [result, result]
                }
            }, "0,0"),
            // Test bitmask
            ({wasmModule in
                let returnType = (0..<2).map {_ in ILType.wasmi32 }
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value:
                        [255, 200, 2, 230, 8, 16, 64, 127, 128, 129, 150, 180, 0, 1, 4, 8])
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i8x16, WasmSimd128IntegerUnOpKind.bitmask)
                    return [result, result]
                }
            }, "3851,3851"),
            // Test relaxed_trunc_f32x4_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0 / 0.0, 1.5, -2.5, Float.greatestFiniteMagnitude]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f32x4_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "(0|-2147483648),1,-2,(2147483647|-2147483648)"),
            // Test relaxed_trunc_f32x4_u
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0 / 0.0, 1.5, -2.5, Float.greatestFiniteMagnitude]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f32x4_u)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "(0|-1),1,(0|-1),-1"), // note: we use -1 to denote UINT32_MAX as it is pain to make .wasmi32 represented as unsigned integer
            // Test relaxed_trunc_f64x2_s_zero corner cases
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: doubleToByteArray([0.0 / 0.0, Double.greatestFiniteMagnitude]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f64x2_s_zero)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "(0|-2147483648),(2147483647|-2147483648),0,0"),
            // Test relaxed_trunc_f64x2_s_zero standard cases
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: doubleToByteArray([-3.5, 7.6]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f64x2_s_zero)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "-3,7,0,0"),
            // Test relaxed_trunc_f64x2_u_zero corner cases
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: doubleToByteArray([0.0 / 0.0, Double.greatestFiniteMagnitude]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f64x2_u_zero)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "(0|-1),(0|-1),0,0"), // note: we use -1 to denote UINT32_MAX as it is pain to make .wasmi32 represented as unsigned integer
            // Test relaxed_trunc_f64x2_u_zero standard cases
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: doubleToByteArray([-3.5, 7.6]))
                    let result = function.wasmSimd128IntegerUnOp(varA, WasmSimd128Shape.i32x4, WasmSimd128IntegerUnOpKind.relaxed_trunc_f64x2_u_zero)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            }, "(0|-1),7,0,0"), // note: we use -1 to denote UINT32_MAX as it is pain to make .wasmi32 represented as unsigned integer
            // Test float add
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 1.5, 2.6, 3.7]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 5.9, 7.0, 8.1]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.add)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"4.80,7.40,9.60,11.80"),
            // Test float sub
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([4.8, 1.5, 7.0, 8.1]))
                    let varB = function.constSimd128(value: floatToByteArray([0.0, 5.9, 2.6, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.sub)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"4.80,-4.40,4.40,4.40"),
            // Test float mul
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([4.8, 1.5, 7.0, 8.1]))
                    let varB = function.constSimd128(value: floatToByteArray([0.0, 5.9, 2.6, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.mul)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"0,8.85,18.20,29.97"),
            // Test float div
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 1.5, 7.0, 8.1]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 5.9, 2.6, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.div)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"0,0.25,2.69,2.19"),
            // Test float min
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.min)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"0,1.50,NaN,NaN"),
            // Test float max
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.max)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"4.80,5.90,NaN,NaN"),
            // Test float pmin
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.pmin)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"0,1.50,7,NaN"),
            // Test float pmax
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.pmax)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"4.80,5.90,7,NaN"),
            // Test float relaxed_min
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.relaxed_min)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"0,1.50,(NaN|7),(NaN|3.70)"),
            // Test float relaxed_max
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 0.0 / 0.0]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 0.0 / 0.0, 3.7]))
                    let result = function.wasmSimd128FloatBinOp(varA, varB, WasmSimd128Shape.f32x4, WasmSimd128FloatBinOpKind.relaxed_max)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"4.80,5.90,(NaN|7),(NaN|3.70)"),
             // Test madd
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 8.1]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 2.7, 3.7]))
                    let varC = function.constSimd128(value: floatToByteArray([9.2, 10.3, 11.4, 12.5]))
                    let result = function.wasmSimd128FloatTernaryOp(varA, varB, varC, WasmSimd128Shape.f32x4, WasmSimd128FloatTernaryOpKind.madd)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"9.20,19.15,30.30,42.47"),
            // Test nmadd
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmf32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: floatToByteArray([0.0, 5.9, 7.0, 8.1]))
                    let varB = function.constSimd128(value: floatToByteArray([4.8, 1.5, 2.7, 3.7]))
                    let varC = function.constSimd128(value: floatToByteArray([9.2, 10.3, 11.4, 12.5]))
                    let result = function.wasmSimd128FloatTernaryOp(varA, varB, varC, WasmSimd128Shape.f32x4, WasmSimd128FloatTernaryOpKind.nmadd)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.F32x4, result, $0)}
                }
            },"9.20,1.45,-7.50,-17.47"),
            // Test relaxed_laneselect
            ({wasmModule in
                let returnType = (0..<16).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: [34, 23, 27, 164, 4, 123, 34, 23, 27, 164, 4, 123, 34, 23, 27, 164])
                    let varB = function.constSimd128(value: [42, 24, 160, 35, 24, 28, 42, 24, 160, 35, 24, 28, 42, 24, 160, 35])
                    let varC = function.constSimd128(value: [255, 0, 128, 129, 20, 65, 255, 0, 128, 129, 20, 65, 255, 0, 128, 129])
                    let result = function.wasmSimd128IntegerTernaryOp(varA, varB, varC, WasmSimd128Shape.i8x16, WasmSimd128IntegerTernaryOpKind.relaxed_laneselect)
                    return (0..<16).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I8x16U, result, $0)}
                }
            },"34,24,(32|27),(162|164),(12|24),(93|28),34,24,(32|27),(162|164),(12|24),(93|28),34,24,(32|27),(162|164)"),
            // Test relaxed_dot_i8x16_i7x16_add_s
            ({wasmModule in
                let returnType = (0..<4).map {_ in ILType.wasmi32}
                wasmModule.addWasmFunction(with: [] => returnType) { function, label, args in
                    let varA = function.constSimd128(value: [34, 23, 27, 124, 4, 123, 34, 23, 27, 124, 4, 123, 34, 23, 27, 124])
                    let varB = function.constSimd128(value: [42, 24, 160, 35, 24, 28, 42, 24, 120, 35, 24, 28, 42, 24, 120, 35])
                    let varC = function.constSimd128(value: [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0]) // i32x4 vector in fact
                    let result = function.wasmSimd128IntegerTernaryOp(varA, varB, varC, WasmSimd128Shape.i32x4, WasmSimd128IntegerTernaryOpKind.relaxed_dot_i8x16_i7x16_add_s)
                    return (0..<4).map {function.wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind.I32x4, result, $0)}
                }
            },"(3729|10641),5522,11123,9564")
        ]

        let module = b.buildWasmModule { wasmModule in
            for(createWasmFunction, _) in testCases {
                createWasmFunction(wasmModule)
            }
        }

        for (i, _) in testCases.enumerated() {
            let print = b.createNamedVariable(forBuiltin: "output")
            let number = b.createNamedVariable(forBuiltin: "Number")

            let setFormat = b.buildArrowFunction(with: .parameters(n: 1)) { args in
                b.buildIfElse(b.callMethod("isInteger", on: number, withArgs: [args[0]])) {
                    b.doReturn(args[0])
                } elseBody: {
                    b.doReturn(b.callMethod("toFixed", on: args[0], withArgs: [b.loadInt(2)]))
                }
            }

            let rawValues = b.callMethod(module.getExportedMethod(at: i), on: module.loadExports())

            b.callFunction(print, withArgs:
                [b.callMethod("join", on: b.callMethod("map", on:rawValues, withArgs: [setFormat]))]
            )
        }

        let jsProg = fuzzer.lifter.lift(b.finalize())
        let expected = testCases.map {$0.1}.joined(separator: "\n") + "\n"
        testForOutputRegex(program: jsProg, runner: runner, outputPattern: expected)
    }

    func testLoops() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                // Test if we can break from this block
                // We should expect to have executed the first wasmReassign which sets marker to 11
                let marker = function.consti64(10)
                function.wasmBuildBlock(with: [] => [], args: []) { label, args in
                    let a = function.consti64(11)
                    function.wasmReassign(variable: marker, to: a)
                    function.wasmBuildBlock(with: [] => [], args: []) { _, _ in
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

                function.wasmBuildLoop(with: [] => []) { label, args in
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
                return [function.wasmi64BinOp(variable, marker, binOpKind: .Add)]
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
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => [.wasmi32]) { function, label, args in
                let loopResult = function.wasmBuildLoop(with: [.wasmi32, .wasmi32] => [.wasmi32, .wasmi32], args: args) { loopLabel, loopArgs in
                    let incFirst = function.wasmi32BinOp(loopArgs[0], function.consti32(1), binOpKind: .Add)
                    let incSecond = function.wasmi32BinOp(loopArgs[1], function.consti32(2), binOpKind: .Add)
                    let condition = function.wasmi32CompareOp(incFirst, incSecond, using: .Gt_s)
                    function.wasmBranchIf(condition, to: loopLabel, args: [incFirst, incSecond])
                    return [incFirst, incSecond]
                }
                function.wasmBuildIfElse(function.wasmi32CompareOp(loopResult[1], function.consti32(20), using: .Ne), hint: .None) {
                    function.wasmUnreachable()
                }
                return [loopResult[0]]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let variable = args[0]
                let condVariable = function.consti32(10);
                let result = function.consti32(0);

                let comp = function.wasmi32CompareOp(variable, condVariable, using: .Lt_s)

                function.wasmBuildIfElse(comp, hint: .None, ifBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Add)
                    function.wasmReassign(variable: result, to: tmp)
                }, elseBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOpKind: .Sub)
                    function.wasmReassign(variable: result, to: tmp)
                })

                return [result]
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
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { function, label, args in
                let inputs = [args[1], function.consti64(3)]
                function.wasmBuildIfElse(args[0], signature: [.wasmi64, .wasmi64] => [], args: inputs, inverted: false) { label, ifArgs in
                    function.wasmReturn(ifArgs[0])
                } elseBody: {label, ifArgs in
                    function.wasmReturn(function.wasmi64BinOp(ifArgs[0], ifArgs[1], binOpKind: .Shl))
                }
                return [function.consti64(-1)]
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
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => [.wasmi32]) { function, label, args in
                function.wasmBuildIfElse(args[0], signature: [.wasmi32] => [], args: [args[1]], inverted: false) { ifLabel, ifArgs in
                    function.wasmBranchIf(ifArgs[0], to: ifLabel)
                    function.wasmReturn(function.consti32(100))
                } elseBody: {elseLabel, ifArgs in
                    function.wasmBranchIf(ifArgs[0], to: elseLabel)
                    function.wasmReturn(function.consti32(200))
                }
                return [function.consti32(300)]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) { function, label, args in
                let blockResult = function.wasmBuildIfElseWithResult(args[0], signature: [] => [.wasmi64, .wasmi64], args: []) {label, args in
                    return [function.consti64(123), function.consti64(10)]
                } elseBody: {label, args in
                    return [function.consti64(321), function.consti64(10)]
                }
                let sum = function.wasmi64BinOp(blockResult[0], blockResult[1], binOpKind: .Add)
                return [sum]
            }
        }
        let exports = module.loadExports()
        let outTrue = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: outTrue)])
        let outFalse = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: outFalse)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "133\n331\n")
    }

    func testBranchHints() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        // Use a JS function so that we have an imported function (causing all function indices to
        // shift which is relevant for the branch hint section.)
        let jsReturnOne = b.buildPlainFunction(with: .parameters()) { _ in
            b.doReturn(b.loadInt(1))
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in

                function.wasmBuildIfElse(function.wasmi32EqualZero(args[0]), hint: .Unlikely) {
                    let one = function.wasmJsCall(function: jsReturnOne, withArgs: [],
                        withWasmSignature: [] => [.wasmi32])!
                    function.wasmReturn(one)
                }
                let cond = function.wasmi32CompareOp(args[0], function.consti32(4), using: .Gt_s)
                function.wasmBuildIfElse(cond, hint: .Likely) {
                    function.wasmReturn(function.consti32(2))
                }
                function.wasmBranchIf(
                    function.wasmi32CompareOp(args[0], function.consti32(1), using: .Eq),
                    to: label, args: [function.consti32(3)], hint: .Likely)
                return [function.consti32(4)]
            }
        }
        let exports = module.loadExports()
        let out0 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out0)])
        let out5 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(5)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out5)])
        let out1 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out1)])
        let out3 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(3)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out3)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "1\n2\n3\n4\n")
    }

    func testTryVoid() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    function.wasmReturn(function.consti64(42))
                }
                return [function.consti64(-1)]
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
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    // Manually set the availableTypes here for testing.
                    let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(b.type(of: functionA).signature!, availableTypes: WeightedList([]))
                    function.wasmJsCall(function: functionA, withArgs: [], withWasmSignature: wasmSignature)
                    function.wasmUnreachable()
                } catchAllBody: { label in
                    function.wasmReturn(function.consti64(123))
                }
                return [function.consti64(-1)]
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
                wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                    function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
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
                    return [function.consti64(-1)]
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
        let throwTag = b.createWasmTag(parameterTypes: [.wasmi64, .wasmi32])
        let otherTag = b.createWasmTag(parameterTypes: [.wasmi32])
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
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
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
                return [function.consti64(-1)]
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
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { tryLabel, _ in
                    function.WasmBuildThrow(tag: tag, inputs: [])
                    function.WasmBuildLegacyCatch(tag: tag) { catchLabel, exceptionLabel, args in
                        function.wasmBranch(to: catchLabel)
                    }
                }
                return [function.consti32(42)]
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
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildBlock(with: [] => [], args: []) { blockLabel, _ in
                    function.wasmBuildLegacyTry(with: [] => [], args: []) { tryLabel, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [])
                    } catchAllBody: { label in
                        function.wasmBranch(to: blockLabel)
                    }
                    function.wasmReturn(function.consti32(-1))
                }
                return [function.consti32(42)]
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
        let parameterTypes = [ILType.wasmi32]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, param in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                    function.wasmBuildIfElse(param[0], hint: .None) {
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
                return [function.consti32(-1)]
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
        let tag = b.createWasmTag(parameterTypes: [.wasmi64, .wasmi32])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                let argI32 = function.consti32(123)
                let argI64 = function.consti64(321)
                function.wasmBuildLegacyTry(with: [.wasmi64, .wasmi32] => [], args: [argI64, argI32]) { label, args in
                    XCTAssert(b.type(of: label).Is(.anyLabel))
                    XCTAssertEqual(b.type(of: args[0]), .wasmi64)
                    XCTAssertEqual(b.type(of: args[1]), .wasmi32)
                    function.WasmBuildThrow(tag: tag, inputs: args)
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        let result = function.wasmi64BinOp(args[0], function.extendi32Toi64(args[1], isSigned: true), binOpKind: .Add)
                        function.wasmReturn(result)
                    }
                }
                function.wasmUnreachable()
                return [function.consti64(-1)]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let contant42 = function.consti64(42)
                let result = function.wasmBuildLegacyTryWithResult(with: [.wasmi32] => [.wasmi32, .wasmi64], args: args, body: { label, args in
                    function.wasmBuildIfElse(function.wasmi32EqualZero(args[0]), hint: .None) {
                        function.WasmBuildThrow(tag: tagVoid, inputs: [])
                    }
                    function.wasmBuildIfElse(function.wasmi32CompareOp(args[0], function.consti32(1), using: .Eq), hint: .None) {
                        function.WasmBuildThrow(tag: tagi32, inputs: [function.consti32(100)])
                    }
                    function.wasmBuildIfElse(function.wasmi32CompareOp(args[0], function.consti32(2), using: .Eq), hint: .None) {
                        function.WasmBuildThrow(tag: tagi32Other, inputs: [function.consti32(200)])
                    }
                    return [args[0], contant42]
                }, catchClauses: [
                    (tagi32, {label, exception, args in
                        return [args[0], contant42]
                    }),
                    (tagi32Other, {label, exception, args in
                        let value = function.wasmi32BinOp(args[0], function.consti32(2), binOpKind: .Add)
                        function.wasmBranch(to: label, args: [value, contant42])
                        return [function.consti32(-1), function.consti64(-1)]
                    }),
                ], catchAllBody: { _ in
                    return [function.consti32(900), contant42]
                })
                function.wasmBuildIfElse(function.wasmi64CompareOp(result[1], contant42, using: .Ne), hint: .None) {
                    function.wasmUnreachable()
                }
                return [result[0]]
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
        let tag = b.createWasmTag(parameterTypes: [.wasmi32])
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
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { tryLabel, _ in
                    // Even though we have a try-catch_all, the delegate "skips" this catch block. The delegate acts as
                    // if the exception was thrown by the block whose label is passed into it.
                    function.wasmBuildLegacyTry(with: [] => [], args: []) { unusedLabel, _ in
                        let val = function.consti32(42)
                        function.wasmBuildLegacyTryDelegate(with: [.wasmi32] => [], args: [val], body: {label, args in
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
                return [function.consti32(-1)]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testTryDelegateWithResults() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildBlock(with: [] => [], args: []) { label, _ in
                    let val = function.consti32(42)
                    let result = function.wasmBuildLegacyTryDelegateWithResult(with: [.wasmi32] => [.wasmi32, .wasmi32], args: [val], body: {tryLabel, args in
                        return [args[0], function.consti32(10)]
                    }, delegate: label)
                    function.wasmReturn(function.wasmi32BinOp(result[0], result[1], binOpKind: .Add))
                }
                function.wasmUnreachable()
                return [function.consti32(-1)]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "52\n")
    }

    func testTryCatchRethrow() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tag = b.createWasmTag(parameterTypes: [.wasmi32])
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
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                    function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123)])
                        function.wasmUnreachable()
                        function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                            function.wasmBuildLegacyRethrow(exception)
                        }
                    }
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        function.wasmReturn(args[0])
                    }
                }
                function.wasmUnreachable()
                return [function.consti32(-1)]
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
        let tag = b.createWasmTag(parameterTypes: [.wasmi32])
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
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, _, _ in
                function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                    function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                        function.WasmBuildThrow(tag: tag, inputs: [function.consti32(123)])
                        function.WasmBuildLegacyCatch(tag: tag) { label, outerException, args in
                            function.wasmBuildLegacyTry(with: [] => [], args: []) { label, _ in
                                function.WasmBuildThrow(tag: tag, inputs: [function.consti32(456)])
                                function.wasmUnreachable()
                                function.WasmBuildLegacyCatch(tag: tag) { label, innerException, args in
                                    // There are two "active" exceptions:
                                    // outerException: [123: i32]
                                    // innerException: [456: i32]
                                    function.wasmBuildLegacyRethrow(outerException)
                                }
                            }
                        }
                    }
                    function.WasmBuildLegacyCatch(tag: tag) { label, exception, args in
                        function.wasmReturn(args[0])
                    }
                }
                function.wasmUnreachable()
                return [function.consti32(-1)]
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
            wasmModule.addWasmFunction(with: [] => [.wasmf64]) { function, _, _ in
                let argI32 = function.consti32(12345)
                let argF64 = function.constf64(543.21)
                function.wasmBuildBlock(with: [.wasmi32, .wasmf64] => [], args: [argI32, argF64]) { blockLabel, args in
                    XCTAssertEqual(args.count, 2)
                    let result = function.wasmf64BinOp(function.converti32Tof64(args[0], isSigned: true), args[1], binOpKind: .Add)
                    function.wasmReturn(result)
                }
                function.wasmUnreachable()
                return [function.constf64(-1)]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "12888.21\n")
    }

    func testBlockWithResults() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, _, _ in
                let blockResult = function.wasmBuildBlockWithResults(with: [.wasmi32] => [.wasmi64, .wasmi32], args: [function.consti32(1234)]) { blockLabel, args in
                    return [function.extendi32Toi64(args[0], isSigned: true), args[0]]
                }
                let sum = function.wasmi64BinOp(blockResult[0],
                    function.extendi32Toi64(blockResult[1], isSigned: true), binOpKind: .Add)
                return [sum]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "2468\n")
    }

    func testBranchWithParameter() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let blockResult = function.wasmBuildBlockWithResults(with: [.wasmi32] => [.wasmi32, .wasmi64], args: args) { blockLabel, blockArgs in
                    function.wasmBranchIf(blockArgs[0], to: blockLabel, args: [function.wasmi32BinOp(blockArgs[0], args[0], binOpKind: .Add), function.consti64(1)])
                    function.wasmBranch(to: blockLabel, args: [function.consti32(12345), function.consti64(54321)])
                    return [function.consti32(-1), function.consti64(0)]
                }
                let sum = function.wasmi32BinOp(blockResult[0], function.wrapi64Toi32(blockResult[1]), binOpKind: .Add)
                return [sum]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut2 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "85\n66666\n")
    }

    func testBranchTableVoid() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                function.wasmBuildBlock(with: [] => [], args: []) { label1, _ in
                    function.wasmBuildBlock(with: [] => [], args: []) { label2, _ in
                        function.wasmBranchTable(on: args[0], labels: [label1, label2], args: [])
                    }
                    function.wasmReturn(function.consti32(2))
                }
                return [function.consti32(1)]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut2 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut2)])
        let wasmOut3 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(-1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut3)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [])
        testForOutput(program: jsProg, runner: runner, outputString: "1\n2\n2\n")
    }

    func testBranchTableWithArguments() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32, .wasmi64] => [.wasmi64]) { function, label, args in
                // Fuzzilli doesn't have support for handling stack-polymorphic cases after
                // non-returning instructions like br_table or return.
                let dummy = [function.consti64(-1), function.consti64(-1)]
                let block1Result = function.wasmBuildBlockWithResults(with: [] => [.wasmi64, .wasmi64], args: []) { label1, _ in
                    let block2Result = function.wasmBuildBlockWithResults(with: [] => [.wasmi64, .wasmi64], args: []) { label2, _ in
                        let block3Result = function.wasmBuildBlockWithResults(with: [] => [.wasmi64, .wasmi64], args: []) { label3, _ in
                            function.wasmBranchTable(on: args[0], labels: [label1, label2, label3],
                                args: [args[1], function.extendi32Toi64(args[0], isSigned: false)])
                            return dummy
                        }
                        function.wasmReturn(function.wasmi64BinOp(block3Result[0], block3Result[1], binOpKind: .Add))
                        return dummy
                    }
                    function.wasmReturn(function.wasmi64BinOp(block2Result[0], function.consti64(2), binOpKind: .Add))
                    return dummy
                }
                return [function.wasmi64BinOp(block1Result[0], function.consti64(1), binOpKind: .Add)]
            }
        }
        let exports = module.loadExports()
        for val in [0, 1, 2, 100] {
            let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports,
                withArgs: [b.loadInt(Int64(val)), b.loadBigInt(42)])
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [])
        testForOutput(program: jsProg, runner: runner, outputString: "43\n44\n44\n142\n")
    }

    func testTryTableNoCatch() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) { function, label, args in
                let blockResult = function.wasmBuildTryTable(with: [.wasmi32, .wasmi64] => [.wasmi64, .wasmi32], args: [args[0], function.consti64(1234)], catches: []) { tryLabel, tryArgs in
                    let isZero = function.wasmi32CompareOp(tryArgs[0], function.consti32(0), using: .Eq)
                    function.wasmBranchIf(isZero, to: tryLabel, args: [function.consti64(10), function.consti32(20)])
                    return [tryArgs[1], tryArgs[0]]
                }
                let sum = function.wasmi64BinOp(blockResult[0],
                    function.extendi32Toi64(blockResult[1], isSigned: true), binOpKind: .Add)
                return [sum]
            }
        }
        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut1 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "30\n1235\n")
    }

    func testTryTable() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tagVoid = b.createWasmTag(parameterTypes: [])
        let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                function.wasmBuildBlock(with: [] => [], args: []) { catchAllNoRefLabel, _ in
                    let catchNoRefI32 = function.wasmBuildBlockWithResults(with: [] => [.wasmi32], args: []) { catchNoRefLabel, _ in
                        function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchNoRefLabel, catchAllNoRefLabel], catches: [.NoRef, .AllNoRef]) { _, _ in
                            function.wasmBuildIfElse(function.wasmi32EqualZero(args[0]), hint: .None) {
                                function.WasmBuildThrow(tag: tagVoid, inputs: [])
                            } elseBody: {
                                function.WasmBuildThrow(tag: tagi32, inputs: [args[0]])
                            }
                            return []
                        }
                        return [function.consti32(-1)]
                    }
                    function.wasmReturn(catchNoRefI32[0])
                }
                return [function.consti32(100)]
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut1 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(123)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "100\n123\n")
    }

    func testTryTableRef() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let tagVoid = b.createWasmTag(parameterTypes: [])
        let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                function.wasmBuildBlockWithResults(with: [] => [.wasmExnRef], args: []) { catchAllRefLabel, _ in
                    let catchRefI32 = function.wasmBuildBlockWithResults(with: [] => [.wasmi32, .wasmExnRef], args: []) { catchRefLabel, _ in
                        function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchRefLabel, catchAllRefLabel], catches: [.Ref, .AllRef]) { _, _ in
                            function.wasmBuildIfElse(function.wasmi32EqualZero(args[0]), hint: .None) {
                                function.WasmBuildThrow(tag: tagVoid, inputs: [])
                            } elseBody: {
                                function.WasmBuildThrow(tag: tagi32, inputs: [args[0]])
                            }
                            return []
                        }
                        return [function.consti32(-1), function.wasmRefNull(type: .wasmExnRef)]
                    }
                    function.wasmReturn(catchRefI32[0])
                    return [function.wasmRefNull(type: .wasmExnRef)]
                }
                return [function.consti32(100)]
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let wasmOut1 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(123)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut1)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "100\n123\n")
    }

    func tagExportedToDifferentWasmModule(defineInWasm: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        let tagFromJS = b.createWasmTag(parameterTypes: [defineInWasm ? .wasmi64 : .wasmi32])
        let moduleThrow = b.buildWasmModule { wasmModule in
            let tagFromWasm = wasmModule.addTag(parameterTypes: [defineInWasm ? .wasmi32 : .wasmi64])
            wasmModule.addWasmFunction(with: [.wasmi32] => []) { function, label, args in
                function.WasmBuildThrow(tag: defineInWasm ? tagFromWasm : tagFromJS, inputs: [args[0]])
                return []
            }
            // Unused function that forces usage of the js tag if not used in the previous function.
            // (So that both get exported.)
            wasmModule.addWasmFunction(with: [.wasmi64] => []) { function, label, args in
                function.WasmBuildThrow(tag: defineInWasm ? tagFromJS : tagFromWasm, inputs: [args[0]])
                return []
            }
        }

        let throwFct = b.getProperty("w0", of: moduleThrow.loadExports())
        XCTAssertEqual(b.type(of: throwFct), .function([.integer] => .nullish))
        let wasmTagExported = b.getProperty("wex0", of: moduleThrow.loadExports())
        // The re-exported tag is prefixed with the `i` for `imported`.
        let jsTagExported = b.getProperty("iwex0", of: moduleThrow.loadExports())
        let wasmTagExportedType = ILType.object(ofGroup: "WasmTag", withWasmType: WasmTagType([defineInWasm ? .wasmi32 : .wasmi64]))
        let jsTagExportedType = ILType.object(ofGroup: "WasmTag", withWasmType: WasmTagType([defineInWasm ? .wasmi64 : .wasmi32]))
        XCTAssertEqual(b.type(of: wasmTagExported), wasmTagExportedType)
        XCTAssertEqual(b.type(of: jsTagExported), jsTagExportedType)
        let tagToUse = defineInWasm ? wasmTagExported : jsTagExported

        let moduleCatch = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi32]) { function, label, args in
                let catchNoRefI32 = function.wasmBuildBlockWithResults(with: [] => [.wasmi32], args: []) { catchNoRefLabel, _ in
                    // The usage of tagToUse in the try_table below is the interesting part of
                    // this test case: It triggers an import of the tag exported by the previous
                    // module and expects that we have all the correct information about it
                    // (including the tag's parameter types.)
                    function.wasmBuildTryTable(with: [] => [], args: [tagToUse, catchNoRefLabel], catches: [.NoRef]) { _, _ in
                        function.wasmJsCall(function: throwFct, withArgs: [function.consti32(42)], withWasmSignature: [.wasmi32] => [])
                        return []
                    }
                    return [function.consti32(-1)]
                }
                return [catchNoRefI32[0]]
            }
        }

        let catchFct = b.getProperty("w0", of: moduleCatch.loadExports())
        let result = b.callFunction(catchFct, withArgs: [throwFct])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: result)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testTagExportedToDifferentWasmModule() throws {
        try tagExportedToDifferentWasmModule(defineInWasm: true)
    }

    func testImportedTagReexportedToDifferentWasmModule() throws {
        try tagExportedToDifferentWasmModule(defineInWasm: false)
    }

    // Test that defining a Wasm tag in JS with all supported abstract ref types does not fail.
    func testTagAllRefTypesInJS() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        // Assumption: All types but the bottom (null) types are supported in the JS API.
        let supportedTypes = WasmAbstractHeapType.allCases.filter {!$0.isBottom()}.map { heapType in
            ILType.wasmRef(.Abstract(heapType), nullability:true)
        }
        b.createWasmTag(parameterTypes: supportedTypes)
        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        // The "funcref" type name is only available with the reflection proposal. Otherwise the
        // name has to be "anyfunc".
        XCTAssert(jsProg.contains("\"anyfunc\""))
        // We just expect the JS execution not throwing an exception.
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    func testThrowRef() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        let printInteger = b.buildPlainFunction(with: .parameters(.integer)) { args in
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: args[0])])
        }

        let tagi32 = b.createWasmTag(parameterTypes: [.wasmi32])
        let module = b.buildWasmModule { wasmModule in
            // Inner function that throws, catches and then rethrows the value.
            let callee = wasmModule.addWasmFunction(with: [.wasmi32] => []) { function, label, args in
                let caughtValues = function.wasmBuildBlockWithResults(with: [] => [.wasmi32, .wasmExnRef], args: []) { catchRefLabel, _ in
                    function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchRefLabel], catches: [.Ref]) { _, _ in
                        function.WasmBuildThrow(tag: tagi32, inputs: [args[0]])
                        return []
                    }
                    return [function.consti32(0), function.wasmRefNull(type: .wasmExnRef)]
                }
                // Print the caught i32 value.
                function.wasmJsCall(function: printInteger, withArgs: [caughtValues[0]], withWasmSignature: [.wasmi32] => [])
                // To rethrow the exception, perform a throw_ref with the exnref.
                function.wasmBuildThrowRef(exception: caughtValues[1])
                return []
            }

            // Outer function that calls the inner function and catches the rethrown exception.
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let caughtValues = function.wasmBuildBlockWithResults(with: [] => [.wasmi32], args: []) { catchLabel, _ in
                    function.wasmBuildTryTable(with: [] => [], args: [tagi32, catchLabel], catches: [.NoRef]) { _, _ in
                        function.wasmCallDirect(signature: [.wasmi32] => [], function: callee, functionArgs: args)
                        return []
                    }
                    return [function.consti32(-1)]
                }
                return caughtValues
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\n")
    }

    func testUnreachable() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                function.wasmUnreachable()
                return []
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) { function, label, args in
                [function.wasmSelect(on: args[0],
                    trueValue: function.consti64(123), falseValue: function.consti64(321))]
            }

            wasmModule.addWasmFunction(with: [.wasmi32, .wasmExternRef, .wasmExternRef] => [.wasmExternRef]) { function, label, args in
                [function.wasmSelect(on: args[0], trueValue: args[1], falseValue: args[2])]
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

    func testSelectIndexType() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let arrayi32 = b.wasmDefineTypeGroup {
            [b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]
        }[0]

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let arrayA = function.wasmArrayNewFixed(arrayType: arrayi32, elements: [function.consti32(123)])
                let arrayB = function.wasmArrayNewFixed(arrayType: arrayi32, elements: [function.consti32(-321)])
                let array = function.wasmSelect(on: args[0], trueValue: arrayA, falseValue: arrayB)
                return [function.wasmArrayGet(array: array, index: function.consti32(0))]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut1 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut1)])
        let wasmOut2 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "-321\n123\n")
    }

    // This test covers a bug where imported functions were not accounted for correctly when
    // lifting a direct call to a non-imported wasm function.
    func testCallDirectJSCall() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        let printMessage = b.buildPlainFunction(with: .parameters(.integer)) { args in
            b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.loadString("This should never be called!"))])
        }

        let module = b.buildWasmModule { wasmModule in
            let callee = wasmModule.addWasmFunction(with: [.wasmi32] => []) { function, label, args in
                return []
            }
            // Outer function that is supposed to call callee.
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                // This direct call accidentally got wrongly lifted to calling the imported js function (printMessage).
                function.wasmCallDirect(signature: [.wasmi32] => [], function: callee, functionArgs: args)
                function.wasmReturn(function.consti32(42))
                // This call is unreachable and only exists here to trigger the import of the printMessage function.
                function.wasmJsCall(function: printMessage, withArgs: [args[0]], withWasmSignature: [.wasmi32] => [])
                return [function.consti32(-1)]
            }
        }

        let exports = module.loadExports()
        let wasmOut = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])
        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testReexportedJSFunction() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .warning, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let jsFunction = b.buildPlainFunction(with: .parameters()) { _ in
            b.doReturn(b.loadBigInt(42))
        }

        let moduleA = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                function.wasmReturn(function.consti64(-1))
                return [function.wasmJsCall(function: jsFunction,
                    withArgs: [], withWasmSignature: [] => [.wasmi64])!]
            }
        }

        let exportsA = moduleA.loadExports()
        let reexportedJSFct = b.getProperty("iw0", of: exportsA)
        // Test that the type system knows about the re-exported function, so that it is
        // discoverable by code generators.
        XCTAssert(b.type(of: exportsA).Is(
            .object(ofGroup: nil, withProperties: [], withMethods: ["w0", "iw0"])))
        XCTAssert(b.type(of: reexportedJSFct).Is(.function([] => .bigint)))

        let moduleB = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                [function.wasmJsCall(function: reexportedJSFct,
                    withArgs: [], withWasmSignature: [] => [.wasmi64])!]
            }
        }
        let exportsB = moduleB.loadExports()

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOutA = b.callMethod("iw0", on: exportsA, withArgs: [])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOutA)])
        let wasmOutB = b.callMethod("w0", on: exportsB)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOutB)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\n")
    }

    func testDefineElementSegments() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            b.buildWasmModule { wasmModule in
                let f1 = wasmModule.addWasmFunction(with: [] => []) { _, _, _ in return []}
                let f2 = wasmModule.addWasmFunction(with: [] => []) { _, _, _ in return []}
                wasmModule.addElementSegment(elements: [])
                wasmModule.addElementSegment(elements: [f1])
                wasmModule.addElementSegment(elements: [f1, f2])
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    func testDropElementSegments() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            b.buildWasmModule { wasmModule in
                let function = wasmModule.addWasmFunction(with: [] => []) { _, _, _ in return []}
                let segment = wasmModule.addElementSegment(elements: [function])
                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    f.wasmDropElementSegment(elementSegment: segment)
                    return []
                }
            }
        }
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }

    func wasmTableInit(isTable64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { module in
                let f1 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(1)]}
                let f2 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(2)]}
                let f3 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(3)]}

                module.addTable(elementType: .wasmFuncRef,
                    minSize: 10,
                    definedEntries: [],
                    definedEntryValues: [],
                    isTable64: isTable64)
                let table2  = module.addTable(elementType: .wasmFuncRef,
                    minSize: 10,
                    definedEntries: [],
                    definedEntryValues: [],
                    isTable64: isTable64)
                module.addElementSegment(elements: [])
                let elemSegment2 = module.addElementSegment(elements: [f3, f3, f1, f2])

                module.addWasmFunction(with: [] => [.wasmi64, .wasmi64]) { f, _, _ in
                    let tableOffset = { (i: Int) in isTable64 ? f.consti64(Int64(i)) : f.consti32(Int32(i))}
                    f.wasmTableInit(elementSegment: elemSegment2, table: table2, tableOffset: tableOffset(5), elementSegmentOffset: f.consti32(2), nrOfElementsToUpdate: f.consti32(2))
                    let callIndirect = { (table: Variable, idx: Int) in 
                        let idxVar = isTable64 ? f.consti64(Int64(idx)) : f.consti32(Int32(idx))
                        return f.wasmCallIndirect(signature: [] => [.wasmi64], table: table, functionArgs: [], tableIndex: idxVar)
                    }
                    return callIndirect(table2, 5)  + callIndirect(table2, 6)
                }
            }
            let res = b.callMethod(module.getExportedMethod(at: 3), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.arrayToStringForTesting(res)])
       }

       testForOutput(program: jsProg, runner: runner, outputString: "1,2\n")
    }

    func testTableInit32() throws {
        try wasmTableInit(isTable64: false)
    }

    func testTableInit64() throws {
        try wasmTableInit(isTable64: true)
    }

    func wasmTableCopy(isTable64: Bool) throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let jsProg = buildAndLiftProgram() { b in
            let module = b.buildWasmModule { module in
                let f1 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(1)]}
                let f2 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(2)]}
                let f3 = module.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in return [f.consti64(3)]}

                let table1 = module.addTable(elementType: .wasmFuncRef,
                    minSize: 10,
                    definedEntries: [],
                    definedEntryValues: [],
                    isTable64: isTable64)
                let table2  = module.addTable(elementType: .wasmFuncRef,
                    minSize: 10,
                    definedEntries: (0..<4).map { WasmTableType.IndexInTableAndWasmSignature.init(indexInTable: $0, signature: [] => [.wasmi64]) },
                    definedEntryValues: [f3, f3, f1, f2],
                    isTable64: isTable64)

                module.addWasmFunction(with: [] => [.wasmi64, .wasmi64]) { f, _, _ in
                    let const = { (i: Int) in isTable64 ? f.consti64(Int64(i)) : f.consti32(Int32(i))}
                    f.wasmTableCopy(dstTable: table1, srcTable: table2, dstOffset: const(1), srcOffset: const(2), count: const(2))
                    let callIndirect = { (table: Variable, idx: Int) in 
                        let idxVar = isTable64 ? f.consti64(Int64(idx)) : f.consti32(Int32(idx))
                        return f.wasmCallIndirect(signature: [] => [.wasmi64], table: table, functionArgs: [], tableIndex: idxVar)
                    }
                    return callIndirect(table1, 1) + callIndirect(table1, 2)
                }
            }
            let res = b.callMethod(module.getExportedMethod(at: 3), on: module.loadExports())
            b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [b.arrayToStringForTesting(res)])
       }

       testForOutput(program: jsProg, runner: runner, outputString: "1,2\n")
    }

    func testTableCopy32() throws {
        try wasmTableCopy(isTable64: false)
    }

    func testTableCopy64() throws {
        try wasmTableCopy(isTable64: true)
    }
}

class WasmGCTests: XCTestCase {
    func testArray() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroup = b.wasmDefineTypeGroup {
            let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
            let arrayOfArrays = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: false), mutability: true, indexType: arrayi32)
            return [arrayi32, arrayOfArrays]
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let array = function.wasmArrayNewFixed(arrayType: typeGroup[0], elements: [
                    function.consti32(42),
                    function.consti32(43),
                    function.consti32(44),
                ])
                let arrayOfArrays = function.wasmArrayNewFixed(arrayType: typeGroup[1], elements: [array])
                let innerArray = function.wasmArrayGet(array: arrayOfArrays, index: function.consti32(0))
                function.wasmArraySet(array: innerArray, index: function.consti32(1), element: function.consti32(100))
                return [function.wasmArrayGet(array: innerArray, index: function.consti32(1))]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "100\n")
    }

    func testArrayPacked() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroup = b.wasmDefineTypeGroup {
            let arrayi8 = b.wasmDefineArrayType(elementType: .wasmPackedI8, mutability: true)
            let arrayi16 = b.wasmDefineArrayType(elementType: .wasmPackedI16, mutability: true)
            return [arrayi8, arrayi16]
        }

        let module = b.buildWasmModule { wasmModule in
            for type in typeGroup {
                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32, .wasmi32]) { function, label, args in
                    let array = function.wasmArrayNewFixed(arrayType: type, elements: [
                        function.consti32(-100),
                        function.consti32(0),
                    ])
                    function.wasmArraySet(array: array, index: function.consti32(1),
                                          element: function.consti32(42))
                    return [
                        function.wasmArrayGet(array: array, index: function.consti32(0), isSigned: true),
                        function.wasmArrayGet(array: array, index: function.consti32(0), isSigned: false),
                        function.wasmArrayGet(array: array, index: function.consti32(1), isSigned: true),
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
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "-100,156,42\n-100,65436,42\n")
    }

    func testArrayNewDefault() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroup = b.wasmDefineTypeGroup {
            let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
            let arrayf64 = b.wasmDefineArrayType(elementType: .wasmf64, mutability: false)
            return [arrayi32, arrayf64]
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let array1 = function.wasmArrayNewDefault(arrayType: typeGroup[0], size: function.consti32(3))
                let array2 = function.wasmArrayNewDefault(arrayType: typeGroup[1], size: function.consti32(2))
                let sum = function.wasmi32BinOp(
                    function.wasmArrayGet(array: array1, index: function.consti32(0)),
                    function.truncatef64Toi32(function.wasmArrayGet(array: array2, index: function.consti32(1)), isSigned: true),
                    binOpKind: .Add)
                return [sum]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "0\n")
    }

    func testArrayLen() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let arrayType = b.wasmDefineTypeGroup {
            return [b.wasmDefineArrayType(elementType: .wasmi32, mutability: false)]
        }[0]

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let arraySize3 = function.wasmArrayNewDefault(arrayType: arrayType, size: function.consti32(3))
                let arraySize7 = function.wasmArrayNewDefault(arrayType: arrayType, size: function.consti32(7))
                let result = function.wasmi32BinOp(
                    function.wasmArrayLen(arraySize3),
                    function.wasmArrayLen(arraySize7),
                    binOpKind: .Mul)
                return [result]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "21\n")
    }

    func testStruct() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let types = b.wasmDefineTypeGroup {
            let structOfi32 = b.wasmDefineStructType(fields: [WasmStructTypeDescription.Field(type: .wasmi32, mutability: true)], indexTypes: [])
            let structOfStruct = b.wasmDefineStructType(fields: [WasmStructTypeDescription.Field(type: .wasmRef(.Index(), nullability: true), mutability: true)], indexTypes: [structOfi32])
            return [structOfi32, structOfStruct]
        }
        let structOfi32 = types[0]
        let structOfStruct = types[1]

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let innerStruct = function.wasmStructNewDefault(structType: structOfi32)
                function.wasmStructSet(theStruct: innerStruct, fieldIndex: 0, value: args[0])
                let outerStruct = function.wasmStructNewDefault(structType: structOfStruct)
                function.wasmStructSet(theStruct: outerStruct, fieldIndex: 0, value: innerStruct)
                let retrievedInnerStruct = function.wasmStructGet(theStruct: outerStruct, fieldIndex: 0)
                let retrievedValue = function.wasmStructGet(theStruct: retrievedInnerStruct, fieldIndex: 0)
                return [retrievedValue]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testStructPacked() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let structType = b.wasmDefineTypeGroup {
            return [b.wasmDefineStructType(fields: [
                WasmStructTypeDescription.Field(type: .wasmPackedI8, mutability: true),
                WasmStructTypeDescription.Field(type: .wasmPackedI8, mutability: true),
                WasmStructTypeDescription.Field(type: .wasmPackedI16, mutability: true),
            ], indexTypes: [])]
        }[0]

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => Array(repeating: .wasmi32, count: 6)) { function, label, args in
                let structObj = function.wasmStructNewDefault(structType: structType)
                function.wasmStructSet(theStruct: structObj, fieldIndex: 0, value: function.consti32(-100))
                function.wasmStructSet(theStruct: structObj, fieldIndex: 1, value: function.consti32(42))
                function.wasmStructSet(theStruct: structObj, fieldIndex: 2, value: function.consti32(-10_000))
                return [
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 0, isSigned: true),
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 0, isSigned: false),
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 1, isSigned: true),
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 1, isSigned: false),
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 2, isSigned: true),
                    function.wasmStructGet(theStruct: structObj, fieldIndex: 2, isSigned: false),
                ]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "-100,156,42,42,-10000,55536\n")
    }

    func testSignature() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let jsProg = buildAndLiftProgram { b in
            let typeGroup = b.wasmDefineTypeGroup {
                let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
                let selfRef = b.wasmDefineForwardOrSelfReference()
                let signature = b.wasmDefineSignatureType(
                    signature: [.wasmRef(.Index(), nullability: true), .wasmi32] =>
                        [.wasmi32, .wasmRef(.Index(), nullability: true)],
                    indexTypes: [arrayi32, selfRef])
                return [arrayi32, signature]
            }

            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => [.wasmFuncRef]) { function, label, args in
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

    func testSelfReferenceType() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let arrayType = b.wasmDefineTypeGroup {
            let selfReference = b.wasmDefineForwardOrSelfReference()
            let arrayOfSelf = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: false, indexType: selfReference)
            return [arrayOfSelf]
        }[0]

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                // We can arbitrarily nest these self-referencing arrays.
                let array1 = function.wasmArrayNewDefault(arrayType: arrayType, size: function.consti32(12))
                let array2 = function.wasmArrayNewFixed(arrayType: arrayType, elements: [array1])
                let array3 = function.wasmArrayNewFixed(arrayType: arrayType, elements: [array2])
                let zero = function.consti32(0)
                let innerArray = function.wasmArrayGet(
                        array: function.wasmArrayGet(array: array3, index: zero),
                        index: zero)
                return [function.wasmArrayLen(innerArray)]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "12\n")
    }

    func testForwardReferenceType() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroup = b.wasmDefineTypeGroup {
            let forwardReference = b.wasmDefineForwardOrSelfReference()
            let arrayOfArrayi32 = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: false, indexType: forwardReference)
            let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
            b.wasmResolveForwardReference(forwardReference, to: arrayi32)
            return [arrayOfArrayi32, arrayi32]
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let arrayi32 = function.wasmArrayNewFixed(arrayType: typeGroup[1], elements: [function.consti32(42)])
                let arrayOfArrayi32 = function.wasmArrayNewFixed(arrayType: typeGroup[0], elements: [arrayi32])
                let zero = function.consti32(0)
                let result = function.wasmArrayGet(
                        array: function.wasmArrayGet(array: arrayOfArrayi32, index: zero),
                        index: zero)
                return [result]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testForwardOrSelfReferenceResolveMultipleTimes() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroup = b.wasmDefineTypeGroup {
            let forwardReference = b.wasmDefineForwardOrSelfReference()
            let arrayOfArrayi32 = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: true, indexType: forwardReference)
            let arrayi32 = b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
            b.wasmResolveForwardReference(forwardReference, to: arrayi32)
            let arrayOfArrayOfArrayi32 = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: true, indexType: forwardReference)
            b.wasmResolveForwardReference(forwardReference, to: arrayOfArrayi32)
            // Here the forward reference acts as a self reference as we don't resolve it again.
            let arraySelf = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: true, indexType: forwardReference)

            return [arrayOfArrayi32, arrayi32, arrayOfArrayOfArrayi32, arraySelf]
        }

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                let arrayi32 = function.wasmArrayNewFixed(arrayType: typeGroup[1], elements: [function.consti32(42)])
                let arrayOfArrayi32 = function.wasmArrayNewFixed(arrayType: typeGroup[0], elements: [arrayi32])
                let arrayOfArrayOfArrayi32 = function.wasmArrayNewFixed(arrayType: typeGroup[2], elements: [arrayOfArrayi32])
                let zero = function.consti32(0)
                let result = function.wasmArrayGet(
                        array: function.wasmArrayGet(array: function.wasmArrayGet(
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
                let arraySelf = function.wasmArrayNewFixed(arrayType: typeGroup[3], elements: [
                    function.wasmRefNull(typeDef: typeGroup[3])
                ])
                // We can also store the arraySelf as an element into iself as the forwardReference
                // got reset to a selfReference after the wasmResolveForwardReference() operation.
                function.wasmArraySet(array: arraySelf, index: function.consti32(0), element: arraySelf)
                return []
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testDependentTypeGroups() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let typeGroupA = b.wasmDefineTypeGroup {
            return [b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]
        }
        let typeGroupB = b.wasmDefineTypeGroup {
            let typeWithDependency = b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: true), mutability: false, indexType: typeGroupA[0])
            let arrayi64 = b.wasmDefineArrayType(elementType: .wasmi64, mutability: true)
            return [arrayi64, typeWithDependency]
        }

        // Note that even though the module doesn't use typeGroupA nor any type dependent on
        // typeGroupA, it still needs to import both typegroups.
        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, args in
                let arrayi64 = function.wasmArrayNewFixed(arrayType: typeGroupB[0], elements: [function.consti64(42)])
                let result = function.wasmArrayGet(array: arrayi64, index: function.consti32(0))
                return [result]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: exports)
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [.includeComments])
        testForOutput(program: jsProg, runner: runner, outputString: "42\n")
    }

    func testRefNullIndexTypes() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let arrayType = b.wasmDefineTypeGroup {[b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]}[0]

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
            let wasmOut = b.callMethod(module.getExportedMethod(at: i), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [wasmOut])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "1\n0\n")
    }

    func testRefNullAbstractTypes() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--experimental-wasm-exnref"])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            for heapType in WasmAbstractHeapType.allCases {
                let valueType = ILType.wasmRef(.Abstract(heapType), nullability: true)
                if heapType.isUsableInJS() {
                    // ref.null <heapType>
                    wasmModule.addWasmFunction(with: [] => [valueType]) { function, label, args in
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
        let exportedFctCount = WasmAbstractHeapType.allCases.count
                             + WasmAbstractHeapType.allCases.count {$0.isUsableInJS()}
        for i in 0..<exportedFctCount {
            let wasmOut = b.callMethod(module.getExportedMethod(at: i), on: exports, withArgs: [])
            b.callFunction(outputFunc, withArgs: [wasmOut])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        // In JS all null values look the same (they are the same).
        let expected = WasmAbstractHeapType.allCases.map {$0.isUsableInJS() ? "null\n1\n" : "1\n"}.joined()
        testForOutput(program: jsProg, runner: runner, outputString: expected)
    }

    func testI31Ref() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmI31Ref]) { function, label, args in
                [function.wasmRefI31(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmI31Ref] => [.wasmi32, .wasmi32]) { function, label, args in
                [function.wasmI31Get(args[0], isSigned: true),
                 function.wasmI31Get(args[0], isSigned: false)]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let positiveI31 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
        let negativeI31 = b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(-42)])
        // An i31ref converts to a JS number.
        b.callFunction(outputFunc, withArgs: [positiveI31])
        b.callFunction(outputFunc, withArgs: [negativeI31])

        let positiveResults = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [positiveI31])
        let negativeResults = b.callMethod(module.getExportedMethod(at: 1), on: exports, withArgs: [negativeI31])
        b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(positiveResults)])
        b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(negativeResults)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n-42\n42,42\n-42,2147483606\n")
    }

    func testExternAnyConversions() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmRefExtern]) { function, label, args in
                // As ref.i31 produces a non null `ref i31`, the result of extern.convert_any is a
                // non-nullable `ref extern`.
                let result = function.wasmExternConvertAny(function.wasmRefI31(args[0]))
                XCTAssertEqual(b.type(of: result), .wasmRefExtern)
                return [result]
            }

            wasmModule.addWasmFunction(with: [.wasmRefExtern] => [.wasmRefAny]) { function, label, args in
                let result = function.wasmAnyConvertExtern(args[0])
                XCTAssertEqual(b.type(of: result), .wasmRefAny)
                return [result]
            }

            wasmModule.addWasmFunction(with: [] => [.wasmExternRef]) { function, label, args in
                let result = function.wasmExternConvertAny(function.wasmRefNull(type: .wasmNullRef))
                XCTAssertEqual(b.type(of: result), .wasmExternRef)
                return [result]
            }

            wasmModule.addWasmFunction(with: [] => [.wasmAnyRef]) { function, label, args in
                let result = function.wasmAnyConvertExtern(function.wasmRefNull(type: .wasmNullExternRef))
                XCTAssertEqual(b.type(of: result), .wasmAnyRef)
                return [result]
            }
        }

        let exports = module.loadExports()
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        for i in 0..<4 {
            let result = b.callMethod(module.getExportedMethod(at: i), on: exports, withArgs: [b.loadInt(42)])
            b.callFunction(outputFunc, withArgs: [result])
        }

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\nnull\nnull\n")
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
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => [.wasmi64]) { function, label, args in
                    [function.wasmi64BinOp(args[0], args[1], binOpKind: binOp)]
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
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => [.wasmi32]) { function, label, args in
                    [function.wasmi32BinOp(args[0], args[1], binOpKind: binOp)]
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
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => [.wasmf64]) { function, label, args in
                    [function.wasmf64BinOp(args[0], args[1], binOpKind: binOp)]
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
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => [.wasmf32]) { function, label, args in
                    [function.wasmf32BinOp(args[0], args[1], binOpKind: binOp)]
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
                wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, args in
                    [function.wasmi64UnOp(args[0], unOpKind: unOp)]
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
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                    [function.wasmi32UnOp(args[0], unOpKind: unOp)]
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
                wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmf64]) { function, label, args in
                    [function.wasmf64UnOp(args[0], unOpKind: unOp)]
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
                wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmf32]) { function, label, args in
                    [function.wasmf32UnOp(args[0], unOpKind: unOp)]
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
                wasmModule.addWasmFunction(with: [.wasmi64, .wasmi64] => [.wasmi32]) { function, label, args in
                    [function.wasmi64CompareOp(args[0], args[1], using: compOp)]
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi32]) { function, label, args in
                [function.wasmi64EqualZero(args[0])]
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
                wasmModule.addWasmFunction(with: [.wasmi32, .wasmi32] => [.wasmi32]) { function, label, args in
                    [function.wasmi32CompareOp(args[0], args[1], using: compOp)]
                }
            }

            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                [function.wasmi32EqualZero(args[0])]
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
                wasmModule.addWasmFunction(with: [.wasmf64, .wasmf64] => [.wasmi32]) { function, label, args in
                    [function.wasmf64CompareOp(args[0], args[1], using: compOp)]
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
                wasmModule.addWasmFunction(with: [.wasmf32, .wasmf32] => [.wasmi32]) { function, label, args in
                    [function.wasmf32CompareOp(args[0], args[1], using: compOp)]
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
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi32]) { function, label, args in
                [function.wrapi64Toi32(args[0])]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi32]) { function, label, args in
                [function.truncatef32Toi32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi32]) { function, label, args in
                [function.truncatef32Toi32(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi32]) { function, label, args in
                [function.truncatef64Toi32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi32]) { function, label, args in
                [function.truncatef64Toi32(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) { function, label, args in
                [function.extendi32Toi64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) { function, label, args in
                [function.extendi32Toi64(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi64]) { function, label, args in
                [function.truncatef32Toi64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi64]) { function, label, args in
                [function.truncatef32Toi64(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi64]) { function, label, args in
                [function.truncatef64Toi64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi64]) { function, label, args in
                [function.truncatef64Toi64(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmf32]) { function, label, args in
                [function.converti32Tof32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmf32]) { function, label, args in
                [function.converti32Tof32(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmf32]) { function, label, args in
                [function.converti64Tof32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmf32]) { function, label, args in
                [function.converti64Tof32(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmf64]) { function, label, args in
                return [function.promotef32Tof64(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmf32]) { function, label, args in
                [function.demotef64Tof32(args[0])]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmf64]) { function, label, args in
                [function.converti32Tof64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmf64]) { function, label, args in
                [function.converti32Tof64(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmf64]) { function, label, args in
                [function.converti64Tof64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmf64]) { function, label, args in
                [function.converti64Tof64(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi32]) { function, label, args in
                [function.reinterpretf32Asi32(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi64]) { function, label, args in
                [function.reinterpretf64Asi64(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmf32]) { function, label, args in
                [function.reinterpreti32Asf32(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmf64]) { function, label, args in
                [function.reinterpreti64Asf64(args[0])]
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
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                [function.signExtend8Intoi32(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi32]) { function, label, args in
                [function.signExtend16Intoi32(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, args in
                [function.signExtend8Intoi64(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, args in
                [function.signExtend16Intoi64(args[0])]
            }
            wasmModule.addWasmFunction(with: [.wasmi64] => [.wasmi64]) { function, label, args in
                [function.signExtend32Intoi64(args[0])]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi32]) { function, label, args in
                [function.truncateSatf32Toi32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi32]) { function, label, args in
                [function.truncateSatf32Toi32(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi32]) { function, label, args in
                [function.truncateSatf64Toi32(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi32]) { function, label, args in
                [function.truncateSatf64Toi32(args[0], isSigned: false)]
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
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi64]) { function, label, args in
                [function.truncateSatf32Toi64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf32] => [.wasmi64]) { function, label, args in
                [function.truncateSatf32Toi64(args[0], isSigned: false)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi64]) { function, label, args in
                [function.truncateSatf64Toi64(args[0], isSigned: true)]
            }
            wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmi64]) { function, label, args in
                [function.truncateSatf64Toi64(args[0], isSigned: false)]
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
            module.addWasmFunction(with: [] => []) { function, label, args in
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                splicePoint = b.indexOfNextInstruction()
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
                return []
            }
        }

        let original = b.finalize()

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { function, _, _ in
                let _ = function.constf32(42.42)
                b.splice(from: original, at: splicePoint, mergeDataFlow: true)
                return []
            }
        }

        let actual = b.finalize()

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { function, _, _ in
                let _ = function.constf32(42.42)
                return []
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
            module.addWasmFunction(with: [] => []) { function, label, args in
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                splicePoint = b.indexOfNextInstruction()
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
                return []
            }
        }

        let original = b.finalize()

        b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadString("AB"))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { function, _, _ in
                let _ = function.constf64(42.42)
                b.splice(from: original, at: splicePoint, mergeDataFlow: true)
                return []
            }
        }

        let actual = b.finalize()

        b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadString("AB"))
        }

        b.buildWasmModule { module in
            module.addWasmFunction(with: [] => []) { function, _, _ in
                let _ = function.constf64(42.42)
                let argument = function.consti32(1337)
                let signature = ProgramBuilder.convertJsSignatureToWasmSignature([.number] => .integer, availableTypes: WeightedList([(.wasmi32, 1)]))
                function.wasmJsCall(function: f, withArgs: [argument], withWasmSignature: signature)
                return []
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
        XCTAssertEqual(b.type(of: importFunction), .object(ofGroup: "WasmSuspendingObject"))

        // Now lets build the module
        let module = b.buildWasmModule { m in
            m.addWasmFunction(with: [.wasmExternRef] => [.wasmi32]) { f, label, args in
                [f.wasmJsCall(function: importFunction, withArgs: args, withWasmSignature: [.wasmExternRef] => [.wasmi32])!]
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

    func testImportingExports() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmGlobali64: Variable = b.createWasmGlobal(value: .wasmi64(1337), isMutable: true)
        XCTAssertEqual(b.type(of: wasmGlobali64), .object(ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"], withWasmType: WasmGlobalType(valueType: ILType.wasmi64, isMutable: true)))

        let module = b.buildWasmModule { wasmModule in
            // Function 0, modifies the imported global.
            wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                let varA = function.consti64(1338)
                function.wasmStoreGlobal(globalVariable: wasmGlobali64, to: varA)
                return []
            }
        }

        let exports = module.loadExports()

        let nameOfExportedGlobals = ["iwg0"]
        let wg0 = b.getProperty(nameOfExportedGlobals[0], of: exports)
        XCTAssertEqual(b.type(of: wg0).wasmGlobalType!.valueType, .wasmi64)

        let module2 = b.buildWasmModule { wasmModule in
            // Function 0
            wasmModule.addWasmFunction(with: [] => [.wasmi64]) { function, label, _ in
                // This forces an import of the wasmGlobali64
                return [function.wasmLoadGlobal(globalVariable: wg0)]
            }
        }

        let exports2 = module2.loadExports()
        let global2 = b.getProperty(nameOfExportedGlobals[0], of: exports2)
        XCTAssertEqual(b.type(of: global2).wasmGlobalType!.valueType, .wasmi64)

        // This just returns the global
        let out = b.callMethod(module2.getExportedMethod(at: 0), on: exports2)

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out)])

        // Change the global through the first module
        b.callMethod(module.getExportedMethod(at: 0), on: exports)

        // This just returns the global again.
        let out2 = b.callMethod(module2.getExportedMethod(at: 0), on: exports2)
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out2)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1337\n1338\n")
    }
}
