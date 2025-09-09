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

import XCTest
@testable import Fuzzilli

class WasmTableTests: XCTestCase {
    func testTableSizeAndGrow() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                let table = wasmModule.addTable(elementType: .wasmFuncRef, minSize: 10, maxSize: 20, isTable64: false)

                wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                    let size = f.wasmTableSize(table: table)
                    return [size]
                }
                expectedOutput += "10\n"

                wasmModule.addWasmFunction(with: [] => [.wasmi32, .wasmi32]) { f, _, _ in
                    let initialValue = f.wasmRefNull(type: .wasmFuncRef)
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
}
