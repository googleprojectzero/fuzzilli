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

// Unit tests for the WebAssembly atomics operations.
class WasmAtomicsTests: XCTestCase {
    /// A basic sanity check for 32-bit and 64-bit atomic load and store operations, on both shared and unshared memory.
    func testAtomicLoadStore() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule { wasmModule in
                let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: false)
                let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: true)

                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                        let valueToStore = f.consti32(1337)
                        let address = f.consti32(8)
                        f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: .i32Store, offset: 0)
                        let loadedValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: .i32Load, offset: 0)
                        return [loadedValue]
                    }
                }

                // memory64
                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in
                        let valueToStore = f.consti64(0x1122334455667788)
                        let address = f.consti32(16)
                        f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: .i64Store, offset: 0)
                        let loadedValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: .i64Load, offset: 0)
                        return [loadedValue]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            let expectedResults = [
                "1337",
                "1337",
                "1234605616436508552",
                "1234605616436508552",
            ]

            for (i, result) in expectedResults.enumerated() {
                let w = b.getProperty("w\(i)", of: exports)
                let r = b.callFunction(w)
                b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: r)])
                expectedOutput += result + "\n"
            }
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    /// Verifies the correctness of packed (narrow) atomic operations.
    func testAtomics8bit() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule {
                wasmModule in
                let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: false)
                let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: true)

                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => [.wasmi32]) { f, _, _ in
                        // The store will wrap this to 0xFF
                        let valueToStore = f.consti32(0x123456FF)
                        let address = f.consti32(4)

                        f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: .i32Store8, offset: 0)
                        // The load will zero-extend 0xFF to 255
                        let loadedValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: .i32Load8U, offset: 0)
                        return [loadedValue]
                    }
                }

                // memory64
                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => [.wasmi64]) { f, _, _ in
                        // The store will wrap this to 0xEF
                        let valueToStore = f.consti64(0x1234567890ABCDEF)
                        let address = f.consti32(4)

                        f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: .i64Store8, offset: 0)
                        // The load will zero-extend 0xEF to 239
                        let loadedValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: .i64Load8U, offset: 0)
                        return [loadedValue]
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            let expectedResults = ["255", "255", "239", "239"]
            for (i, result) in expectedResults.enumerated() {
                let w = b.getProperty("w\(i)", of: exports)
                let r = b.callFunction(w)
                b.callFunction(outputFunc, withArgs: [b.callMethod("toString", on: r)])
                expectedOutput += result + "\n"
            }
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    /// Verifies that a misaligned atomic memory access correctly triggers a WebAssembly trap.
    func testAtomicsMisalignedTrap() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""

        let js = buildAndLiftProgram { b in
            let module = b.buildWasmModule {
                wasmModule in
                let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: false)
                let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: true)

                // Load operations

                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                        let address = f.consti32(1) // Unaligned for 4-byte access
                        // This should trap.
                        f.wasmAtomicLoad(memory: memory, address: address, loadType: .i32Load, offset: 0)
                        return []
                    }
                }

                // memory64
                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                        let address = f.consti32(4) // Unaligned for 8-byte access
                        // This should trap.
                        f.wasmAtomicLoad(memory: memory, address: address, loadType: .i64Load, offset: 0)
                        return []
                    }
                }

                // Store operations

                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                        let address = f.consti32(2) // Unaligned for 4-byte access
                        // This should trap.
                        let value = f.consti32(0x1337)
                        f.wasmAtomicStore(memory: memory, address: address, value: value, storeType: .i32Store, offset: 0)
                        return []
                    }
                }

                // memory64
                for memory in [unsharedMemory, sharedMemory] {
                    wasmModule.addWasmFunction(with: [] => []) { f, _, _ in
                        let address = f.consti32(7) // Unaligned for 8-byte access
                        // This should trap.
                        let value = f.consti64(0xDEADBEEF)
                        f.wasmAtomicStore(memory: memory, address: address, value: value, storeType: .i64Store, offset: 0)
                        return []
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            for i in 0..<8 {
                let w = b.getProperty("w\(i)", of: exports)
                b.buildTryCatchFinally {
                    b.callFunction(w)
                } catchBody: { _ in
                    b.callFunction(outputFunc, withArgs: [b.loadString("Caught trap!")])
                }
                expectedOutput += "Caught trap!\n"
            }
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    func testAtomicRMWs() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""
        var expectedResults: [String] = []

        let js = buildAndLiftProgram { b in
            let testCases: [(
                op: WasmAtomicRMWType,
                storeType: WasmAtomicStoreType,
                loadType: WasmAtomicLoadType,
                valueType: ILType
            )] =
                [.i32Add, .i32Sub, .i32And, .i32Or, .i32Xor, .i32Xchg]
                .map { ($0, .i32Store, .i32Load, .wasmi32) } +
                [.i32Add8U, .i32Sub8U, .i32And8U, .i32Or8U, .i32Xor8U, .i32Xchg8U]
                .map { ($0, .i32Store8, .i32Load8U, .wasmi32) } +
                [.i32Add16U, .i32Sub16U, .i32And16U, .i32Or16U, .i32Xor16U, .i32Xchg16U]
                .map { ($0, .i32Store16, .i32Load16U, .wasmi32) } +
                [.i64Add, .i64Sub, .i64And, .i64Or, .i64Xor, .i64Xchg]
                .map { ($0, .i64Store, .i64Load, .wasmi64) } +
                [.i64Add8U, .i64Sub8U, .i64And8U, .i64Or8U, .i64Xor8U, .i64Xchg8U]
                .map { ($0, .i64Store8, .i64Load8U, .wasmi64) } +
                [.i64Add16U, .i64Sub16U, .i64And16U, .i64Or16U, .i64Xor16U, .i64Xchg16U]
                .map { ($0, .i64Store16, .i64Load16U, .wasmi64) } +
                [.i64Add32U, .i64Sub32U, .i64And32U, .i64Or32U, .i64Xor32U, .i64Xchg32U]
                .map { ($0, .i64Store32, .i64Load32U, .wasmi64) }

            let initialValue: Int64 = 12
            let operand: Int64 = 10

            let module = b.buildWasmModule { wasmModule in
                let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: false)
                let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: true)

                for memory in [unsharedMemory, sharedMemory] {
                    for (op, storeType, loadType, valueType) in testCases {
                        let returnType = valueType
                        wasmModule.addWasmFunction(with: [] => [returnType, returnType]) { f, _, _ in
                            let valueToStore = (valueType == .wasmi32) ? f.consti32(Int32(initialValue)) : f.consti64(initialValue)
                            let rhs = (valueType == .wasmi32) ? f.consti32(Int32(operand)) : f.consti64(operand)
                            let lhs = f.consti32(8)
                            f.wasmAtomicStore(memory: memory, address: lhs, value: valueToStore, storeType: storeType, offset: 0)
                            let originalValue = f.wasmAtomicRMW(memory: memory, lhs: lhs, rhs: rhs, op: op, offset: 0)
                            let finalValue = f.wasmAtomicLoad(memory: memory, address: lhs, loadType: loadType, offset: 0)
                            return [originalValue, finalValue]
                        }

                        let expectedFinal = switch op {
                        case .i32Add, .i32Add8U, .i32Add16U, .i64Add, .i64Add8U, .i64Add16U, .i64Add32U:
                            initialValue + operand
                        case .i32Sub, .i32Sub8U, .i32Sub16U, .i64Sub, .i64Sub8U, .i64Sub16U, .i64Sub32U:
                            initialValue - operand
                        case .i32And, .i32And8U, .i32And16U, .i64And, .i64And8U, .i64And16U, .i64And32U:
                            initialValue & operand
                        case .i32Or, .i32Or8U, .i32Or16U, .i64Or, .i64Or8U, .i64Or16U, .i64Or32U:
                            initialValue | operand
                        case .i32Xor, .i32Xor8U, .i32Xor16U, .i64Xor, .i64Xor8U, .i64Xor16U, .i64Xor32U:
                            initialValue ^ operand
                        case .i32Xchg, .i32Xchg8U, .i32Xchg16U, .i64Xchg, .i64Xchg8U, .i64Xchg16U, .i64Xchg32U:
                            operand
                        }
                        expectedResults.append("\(initialValue),\(expectedFinal)\n")
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            for (i, results) in expectedResults.enumerated() {
                let w = b.getProperty("w\(i)", of: exports)
                let r = b.callFunction(w)
                b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(r)])
                expectedOutput += results
            }
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    func testAtomicCmpxchg() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        var expectedOutput = ""
        var expectedResults: [String] = []

        let js = buildAndLiftProgram { b in
            let testCases: [(
                op: WasmAtomicCmpxchgType,
                storeType: WasmAtomicStoreType,
                loadType: WasmAtomicLoadType,
                valueType: ILType
            )] = [
                (.i32Cmpxchg, .i32Store, .i32Load, .wasmi32),
                (.i32Cmpxchg8U, .i32Store8, .i32Load8U, .wasmi32),
                (.i32Cmpxchg16U, .i32Store16, .i32Load16U, .wasmi32),
                (.i64Cmpxchg, .i64Store, .i64Load, .wasmi64),
                (.i64Cmpxchg8U, .i64Store8, .i64Load8U, .wasmi64),
                (.i64Cmpxchg16U, .i64Store16, .i64Load16U, .wasmi64),
                (.i64Cmpxchg32U, .i64Store32, .i64Load32U, .wasmi64),
            ]

            let initialValue: Int64 = 12
            let replacement: Int64 = 10

            let module = b.buildWasmModule { wasmModule in
                let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: false)
                let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 4, isShared: true)

                for memory in [unsharedMemory, sharedMemory] {
                    for (op, storeType, loadType, valueType) in testCases {
                        let returnType = valueType
                        // Successful exchange
                        wasmModule.addWasmFunction(with: [] => [returnType, returnType]) { f, _, _ in
                            let valueToStore = (valueType == .wasmi32) ? f.consti32(Int32(initialValue)) : f.consti64(initialValue)
                            let expected = valueToStore
                            let replacement = (valueType == .wasmi32) ? f.consti32(Int32(replacement)) : f.consti64(replacement)
                            let address = f.consti32(8)
                            f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: storeType, offset: 0)
                            let originalValue = f.wasmAtomicCmpxchg(memory: memory, address: address, expected: expected, replacement: replacement, op: op, offset: 0)
                            let finalValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: loadType, offset: 0)
                            return [originalValue, finalValue]
                        }
                        expectedResults.append("\(initialValue),\(replacement)\n")

                        // Unsuccessful exchange
                        wasmModule.addWasmFunction(with: [] => [returnType, returnType]) { f, _, _ in
                            let valueToStore = (valueType == .wasmi32) ? f.consti32(Int32(initialValue)) : f.consti64(initialValue)
                            let expected = (valueType == .wasmi32) ? f.consti32(Int32(initialValue - 1)) : f.consti64(initialValue - 1)
                            let replacement = (valueType == .wasmi32) ? f.consti32(Int32(replacement)) : f.consti64(replacement)
                            let address = f.consti32(8)
                            f.wasmAtomicStore(memory: memory, address: address, value: valueToStore, storeType: storeType, offset: 0)
                            let originalValue = f.wasmAtomicCmpxchg(memory: memory, address: address, expected: expected, replacement: replacement, op: op, offset: 0)
                            let finalValue = f.wasmAtomicLoad(memory: memory, address: address, loadType: loadType, offset: 0)
                            return [originalValue, finalValue]
                        }
                        expectedResults.append("\(initialValue),\(initialValue)\n")
                    }
                }
            }

            let exports = module.loadExports()
            let outputFunc = b.createNamedVariable(forBuiltin: "output")

            for (i, results) in expectedResults.enumerated() {
                let w = b.getProperty("w\(i)", of: exports)
                let r = b.callFunction(w)
                b.callFunction(outputFunc, withArgs: [b.arrayToStringForTesting(r)])
                expectedOutput += results
            }
        }

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }
}