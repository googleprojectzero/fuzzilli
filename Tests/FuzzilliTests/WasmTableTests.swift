// Copyright 2025 Google LLC
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
struct WasmTableTests {
    @Test func testTableSizeAndGrow() throws {
        let runner = JavaScriptExecutor()!
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                let table = wasmModule.addTable(
                    elementType: .wasmFuncRef(), minSize: 10, maxSize: 20, isTable64: false)

                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                    let size = f.wasmTableSize(table: table)
                    return [size]
                }
                expectedOutput += "10\n"

                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { f, _, _ in
                    let initialValue = f.wasmRefNull(type: .wasmFuncRef())
                    let growBy = f.consti32(5)
                    let oldSize = f.wasmTableGrow(table: table, with: initialValue, by: growBy)
                    let newSize = f.wasmTableSize(table: table)
                    return [oldSize, newSize]
                }
                expectedOutput += "10,15\n"
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            let w0 = b.getProperty("w0", of: exports)
            let r0 = b.callFunction(w0)
            b.callFunction(outputFunc, withArgs: [r0])

            let w1 = b.getProperty("w1", of: exports)
            let r1 = b.callFunction(w1)
            b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(r1)])
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    // The typer has to predict the names under which the lifted module exports its tables
    // (including re-exported imported ones), check that they match the actual exports.
    @Test func testTyperKnowsTableExportNames() throws {
        let runner = JavaScriptExecutor()!
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            // Outputs the names of all exports and the length of all exported tables, and records
            // the output expected based on the typer's view of the exports.
            func outputExports(of module: ProgramBuilder.WasmModule) {
                let exports = module.loadExports()
                let exportsType = b.type(of: exports)
                let object = b.createNamedVariable(forBuiltin: "Object")
                let names = b.callMethod("keys", on: object, withArgs: [exports])
                let sortedNames = b.callMethod("sort", on: names)
                b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(sortedNames)])
                let expectedNames = exportsType.properties.union(exportsType.methods).sorted()
                expectedOutput += expectedNames.joined(separator: ",") + "\n"
                for name in exportsType.properties.sorted() {
                    guard let tableType = b.type(ofProperty: name, on: exports).wasmTableType
                    else { continue }
                    let length = b.getProperty("length", of: b.getProperty(name, of: exports))
                    let line = b.binary(b.loadString("\(name).length="), length, with: .Add)
                    b.callFunction(outputFunc, withArgs: [line])
                    expectedOutput += "\(name).length=\(tableType.limits.min)\n"
                }
            }

            // The element segment used by table.init is not a table.
            let module = b.buildWasmModule { wasmModule in
                let function = wasmModule.addWasmFunction(with: [] => []) { _, _, _ in [] }
                let table = wasmModule.addTable(
                    elementType: .wasmFuncRef(), minSize: 10, isTable64: false)
                let segment = wasmModule.addElementSegment(elements: [function])
                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    let zero = f.consti32(0)
                    f.wasmTableInit(
                        elementSegment: segment, table: table, tableOffset: zero,
                        elementSegmentOffset: zero, elementCount: zero)
                    return []
                }
                wasmModule.addTable(elementType: .wasmExternRef(), minSize: 5, isTable64: false)
            }
            outputExports(of: module)

            // The table used by call_indirect is imported and therefore re-exported.
            let funcRefTable = b.createWasmTable(
                elementType: .wasmFuncRef(), limits: Limits(min: 3), isTable64: false)
            let externRefTable = b.createWasmTable(
                elementType: .wasmExternRef(), limits: Limits(min: 7), isTable64: false)
            let importingModule = b.buildWasmModule { wasmModule in
                let signature = wasmModule.wasmDefineAdHocSignatureType(signature: [] => [])
                wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                    let zero = f.consti32(0)
                    f.wasmCallIndirect(
                        signatureDef: signature, table: funcRefTable, functionArgs: [],
                        tableIndex: zero)
                    f.wasmTableGet(tableRef: externRefTable, idx: zero)
                    return []
                }
            }
            outputExports(of: importingModule)
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    @Test func testTableInitAndCopy() throws {
        let runner = JavaScriptExecutor()!
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                let f0 = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                    return [f.consti32(42)]
                }
                let f1 = wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                    return [f.consti32(1337)]
                }
                let elementSegment = wasmModule.addElementSegment(elements: [f0, f1])
                let table1 = wasmModule.addTable(
                    elementType: .wasmFuncRef(), minSize: 5, maxSize: 10, isTable64: false)
                let table2 = wasmModule.addTable(
                    elementType: .wasmFuncRef(), minSize: 5, maxSize: 10, isTable64: false)

                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                    f.wasmTableInit(
                        elementSegment: elementSegment, table: table1,
                        tableOffset: f.consti32(1), elementSegmentOffset: f.consti32(0),
                        elementCount: f.consti32(2))
                    f.wasmTableCopy(
                        dstTable: table2, srcTable: table1,
                        dstOffset: f.consti32(3), srcOffset: f.consti32(2),
                        count: f.consti32(1))
                    let sigDef = f.wasmDefineAdHocSignatureType(signature: [] => [.wasmi32])
                    return f.wasmCallIndirect(
                        signatureDef: sigDef, table: table2,
                        functionArgs: [], tableIndex: f.consti32(3))
                }
                expectedOutput += "1337\n"
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            let w2 = b.getProperty("w2", of: exports)
            let res = b.callFunction(w2)
            b.callFunction(outputFunc, withArgs: [res])
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }
}
