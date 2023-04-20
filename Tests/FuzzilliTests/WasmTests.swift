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

func testForOutput(program: String, runner: JavaScriptExecutor, outputString: String) {
        let result: JavaScriptExecutor.Result
        do {
            result = try runner.executeScript(program)
        } catch {
            fatalError("Could not execute Script")
        }

        XCTAssertEqual(result.output, outputString)
}

class WasmFoundationTests: XCTestCase {
    func testFunction() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

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
                let added = function.wasmi64BinOp(var64, arg[0], binOperator: BinaryOperator.Add)
                function.wasmReturn(added)
            }

            wasmModule.addWasmFunction(with: Signature(expects: ParameterList([.wasmi64, .wasmi64]), returns: .wasmi64)) { function, arg in
                let subbed = function.wasmi64BinOp(arg[0], arg[1], binOperator: BinaryOperator.Sub)
                function.wasmReturn(subbed)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let num = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable(), withArgs: [num])

        let res2 = b.callMethod(module.getExportedMethod(at: 2), on: module.getModuleVariable(), withArgs: [res1, num])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res2)])


        let prog = b.finalize()

        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "1338\n42\n41\n")
    }

    func testExportNaming() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()


        // This test tests whether re-exported imports and module defined globals are re-ordered from the typer.
        let wasmGlobali32: Variable = b.createWasmGlobal(wasmGlobal: .wasmi32(1337), isMutable: true)
        assert(b.type(of: wasmGlobali32) == .object(ofGroup: "WasmGlobal.i32"))

        let wasmGlobalf32: Variable = b.createWasmGlobal(wasmGlobal: .wasmf32(42.0), isMutable: true)

        let module = b.buildWasmModule { wasmModule in
            // Imports are always before internal globals, this breaks the logic if we add a global and then import a global.
            wasmModule.addGlobal(importing: wasmGlobalf32)
            wasmModule.addGlobal(wasmGlobal: .wasmi64(4141), isMutable: true)
            wasmModule.addGlobal(importing: wasmGlobali32)

        }

        print("Module has type: \(b.type(of: module.getModuleVariable()))")

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1), WasmLifter.nameOfGlobal(2)]

        assert(b.type(of: module.getModuleVariable()) == .object(withProperties: nameOfExportedGlobals))

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        // Now let's actually see what the re-exported values are and see that the types don't match with what the programbuilder will see.
        // TODO: Is this an issue? will the programbuilder still be queriable for variables? I think so, it is internally consistent within the module....
        let firstExport = b.getProperty(nameOfExportedGlobals[0], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: firstExport))])

        let secondExport = b.getProperty(nameOfExportedGlobals[1], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: secondExport))])

        let thirdExport = b.getProperty(nameOfExportedGlobals[2], of: module.getModuleVariable())
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: b.getProperty("value", of: thirdExport))])


        let prog = b.finalize()

        let lifter = FuzzILLifter()
        let jsProg = fuzzer.lifter.lift(prog)

        print(lifter.lift(prog))
        print(jsProg)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n4141\n1337\n")
    }

    func testImports() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

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
                let varA = function.wasmJsCall(function: functionA, withArgs: [args[0]])
                function.wasmReturn(varA)
            }

            wasmModule.addWasmFunction(with: [] => .wasmf32) { function, _ in
                let varA = function.consti32(1337)
                let varRet = function.wasmJsCall(function: functionB, withArgs: [varA])
                function.wasmReturn(varRet)
            }
        }

        let val = b.loadBigInt(2)
        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable(), withArgs: [val])
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable())

        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])


        let prog = b.finalize()

        let lifter = FuzzILLifter()
        let jsProg = fuzzer.lifter.lift(prog)

        print(lifter.lift(prog))
        print(jsProg)

        testForOutput(program: jsProg, runner: runner, outputString: "3\n-1335\n")

    }

    func testBasics() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

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
                let added = function.wasmi64BinOp(varA, arg[0], binOperator: .Add)
                function.wasmReturn(added)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())
        let integer = b.loadBigInt(1)
        let res1 = b.callMethod(module.getExportedMethod(at: 1), on: module.getModuleVariable(), withArgs: [integer])


        let outputFunc = b.createNamedVariable(forBuiltin: "output")

        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res1)])

        let prog = b.finalize()

        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        let jsProg = fuzzer.lifter.lift(prog)

        testForOutput(program: jsProg, runner: runner, outputString: "42\n42\n")
    }

    func testReassigns() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                let varA = function.consti64(1338)
                // reassign params[0] = varA
                function.wasmReassign(variable: params[0], to: varA)
                function.wasmReturn(params[0])
            }

            let globA = wasmModule.addGlobal(wasmGlobal: .wasmi64(1337), isMutable: true)
            let globB = wasmModule.addGlobal(wasmGlobal: .wasmi64(1338), isMutable: true)

            wasmModule.addWasmFunction(with: [] => .nothing) { function, _ in
                function.wasmReassign(variable:  globA, to: globB)
            }

            wasmModule.addWasmFunction(with: [.wasmi64] => .wasmi64) { function, params in
                // reassign params[0] = params[0]
                function.wasmReassign(variable: params[0], to: params[0])
                function.wasmReturn(params[0])
            }

        }

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callMethod("w1", on: module.getModuleVariable(), withArgs: [b.loadBigInt(10)])

        let out = b.callMethod("w0", on: module.getModuleVariable(), withArgs: [b.loadBigInt(10)])
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: out)])

        let _ = b.callMethod("w2", on: module.getModuleVariable(), withArgs: [b.loadBigInt(20)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))


        testForOutput(program: jsProg, runner: runner, outputString: "1338\n")
    }

    func testGlobals() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let wasmGlobali64: Variable = b.createWasmGlobal(wasmGlobal: .wasmi64(1337), isMutable: true)
        assert(b.type(of: wasmGlobali64) == .object(ofGroup: "WasmGlobal.i64"))

        let module = b.buildWasmModule { wasmModule in
            let global = wasmModule.addGlobal(wasmGlobal: .wasmi64(1339), isMutable: true)
            let importedGlobal = wasmModule.addGlobal(importing: wasmGlobali64)

            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let varA = function.consti64(1338)
                let varB = function.consti64(4242)
                function.wasmStoreGlobal(globalVariable: global, to: varB)
                let global = function.wasmLoadGlobal(globalVariable: global)
                function.wasmStoreGlobal(globalVariable: importedGlobal, to: varA)
                function.wasmReturn(global)
            }
        }

        let _ = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())
        print("Module has type: \(b.type(of: module.getModuleVariable()))")

        let nameOfExportedGlobals = [WasmLifter.nameOfGlobal(0), WasmLifter.nameOfGlobal(1)]
        let nameOfExportedFunctions = [WasmLifter.nameOfFunction(0)]

        assert(b.type(of: module.getModuleVariable()) == .object(withProperties: nameOfExportedGlobals, withMethods: nameOfExportedFunctions))


        let value = b.getProperty("value", of: wasmGlobali64)
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])

        let wg0 = b.getProperty(nameOfExportedGlobals[0], of: module.getModuleVariable())
        let valueWg0 = b.getProperty("value", of: wg0)
        let _ = b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueWg0)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))


        testForOutput(program: jsProg, runner: runner, outputString: "1338\n4242\n")
    }

    func testTables() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let javaScriptTable = b.createWasmTable(tableType: .externRefTable, minSize: 10, maxSize: 20)

        let object = b.createObject(with: ["a": b.loadInt(41), "b": b.loadInt(42)])

        // Set a value into the table
        b.callMethod("set", on: javaScriptTable, withArgs: [b.loadInt(1), object])

        let module = b.buildWasmModule { wasmModule in
            // Imports are always before internal tables, this breaks the logic if we add a table and then import a table.
            // TODO: Track imports and tables?
            let tableRef = wasmModule.addTable(tableType: .wasmFuncRef, minSize: 2)
            let javaScriptTableRef = wasmModule.addTable(importing: javaScriptTable)

            wasmModule.addWasmFunction(with: [] => .wasmExternRef) { function, _ in
                let offset = function.consti32(0)
                var ref = function.wasmTableGet(tableRef: tableRef, idx: offset)
                let offset1 = function.consti32(1)
                function.wasmTableSet(tableRef: tableRef, idx: offset1, to: ref)
                ref = function.wasmTableGet(tableRef: tableRef, idx: offset1)
                let otherRef = function.wasmTableGet(tableRef: javaScriptTableRef, idx: offset1)
                function.wasmReturn(otherRef)
            }
        }

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        let json = b.createNamedVariable(forBuiltin: "JSON")
        b.callFunction(outputFunc, withArgs: [b.callMethod("stringify", on: json, withArgs: [res0])])


        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        testForOutput(program: jsProg, runner: runner, outputString: "{\"a\":41,\"b\":42}\n")
    }

    func testMemories() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let ten = b.loadInt(10)
        let twenty = b.loadInt(20)

        let config = b.createObject(with: ["initial": ten, "maximum": twenty])
        let wasm = b.createNamedVariable(forBuiltin: "WebAssembly")
        let wasmMemoryConstructor = b.getProperty("Memory", of: wasm)
        let javaScriptVar = b.construct(wasmMemoryConstructor, withArgs: [config])


        let module = b.buildWasmModule { wasmModule in
            let memoryRef = wasmModule.addMemory(importing: javaScriptVar)

            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                let value = function.consti32(1337)
                let base = function.consti32(0)
                function.wasmMemorySet(memoryRef: memoryRef, base: base, offset:10, value: value)
                let val = function.wasmMemoryGet(memoryRef: memoryRef, type: .wasmi64, base: base, offset: 10)
                function.wasmReturn(val)
            }
        }

        let viewBuiltin = b.createNamedVariable(forBuiltin: "DataView")
        let view = b.construct(viewBuiltin, withArgs: [b.getProperty("buffer", of: javaScriptVar)])

        // Read the value of the memory.
        let value = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let res0 = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())

        let valueAfter = b.callMethod("getUint32", on: view, withArgs: [b.loadInt(10), b.loadBool(true)])

        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: res0)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: value)])
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: valueAfter)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        testForOutput(program: jsProg, runner: runner, outputString: "1337\n0\n1337\n")
    }


    func testLoops() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                // Test if we can break from this block
                // We should expect to have executed the first wasmReassign which sets marker to 11
                let marker = function.consti64(10)
                function.wasmBuildBlock(with: Signature(withParameterCount: 0)) { label, args in
                    let a = function.consti64(11)
                    function.wasmReassign(variable: marker, to: a)
                    function.wasmBuildBlock(with: Signature(withParameterCount: 0)) { _, _ in
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

                function.wasmBuildLoop(with: Signature(withParameterCount: 0)) { label, args in
                    let result = function.wasmi32BinOp(ctr, one, binOperator: .Add)
                    let varUpdate = function.wasmi64BinOp(variable, function.consti64(2), binOperator: .Add)
                    function.wasmReassign(variable: ctr, to: result)
                    function.wasmReassign(variable: variable, to: varUpdate)
                    let comp = function.wasmi32CompareOp(ctr, max, using: .Lt_s)
                    function.wasmBranchIf(comp, to: label)
                }

                // Now combine the result of the break and the loop into one and return it.
                // This should return 1337 + 20 == 1357, 1357 + 11 = 1368
                let result = function.wasmi64BinOp(variable, marker, binOperator: .Add)

                function.wasmReturn(result)
            }
        }

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable())
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        testForOutput(program: jsProg, runner: runner, outputString: "1368\n")
    }

    func testIfs() {
        let runner = JavaScriptExecutor()!
        let liveTestConfig = Configuration(enableInspection: true)

        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())

        let b = fuzzer.makeBuilder()

        let module = b.buildWasmModule { wasmModule in
            wasmModule.addWasmFunction(with: [.wasmi32] => .wasmi32) { function, args in
                let variable = args[0]
                let condVariable = function.consti32(10);
                let result = function.consti32(0);

                let comp = function.wasmi32CompareOp(variable, condVariable, using: .Lt_s)

                function.wasmBuildIfElse(comp, ifBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOperator: .Add)
                    function.wasmReassign(variable: result, to: tmp)
                }, elseBody: {
                    let tmp = function.wasmi32BinOp(variable, condVariable, binOperator: .Sub)
                    function.wasmReassign(variable: result, to: tmp)
                })

                function.wasmReturn(result)
            }
        }

        let wasmOut = b.callMethod(module.getExportedMethod(at: 0), on: module.getModuleVariable(), withArgs: [b.loadInt(1337)])
        let outputFunc = b.createNamedVariable(forBuiltin: "output")
        b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: wasmOut)])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog)
        let lifter = FuzzILLifter()
        print(lifter.lift(prog))

        testForOutput(program: jsProg, runner: runner, outputString: "1327\n")
    }
}
