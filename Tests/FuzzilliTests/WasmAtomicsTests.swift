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
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        var expectedOutput = ""

        let module = b.buildWasmModule { wasmModule in
            let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: false)
            let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: true)

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
            b.callFunction(outputFunc, withArgs: [r])
            expectedOutput += result + "\n"
        }

        let prog = b.finalize()
        let js = fuzzer.lifter.lift(prog)

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    /// Verifies the correctness of packed (narrow) atomic operations.
    func testAtomics8bit() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        var expectedOutput = ""

        let module = b.buildWasmModule {
            wasmModule in
            let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: false)
            let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: true)

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
            b.callFunction(outputFunc, withArgs: [r])
            expectedOutput += result + "\n"
        }

        let prog = b.finalize()
        let js = fuzzer.lifter.lift(prog)

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }

    /// Verifies that a misaligned atomic memory access correctly triggers a WebAssembly trap.
    func testAtomicsMisalignedTrap() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()
        var expectedOutput = ""

        let module = b.buildWasmModule {
            wasmModule in
            let unsharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: false)
            let sharedMemory = wasmModule.addMemory(minPages: 1, maxPages: 1, isShared: true)

            // Load operations

            for memory in [unsharedMemory, sharedMemory] {
                wasmModule.addWasmFunction(with: [] => []) { f, _ in
                    let address = f.consti32(1) // Unaligned for 4-byte access
                    // This should trap.
                    f.wasmAtomicLoad(memory: memory, address: address, loadType: .i32Load, offset: 0)
                }
            }

            // memory64
            for memory in [unsharedMemory, sharedMemory] {
                wasmModule.addWasmFunction(with: [] => []) { f, _ in
                    let address = f.consti32(4) // Unaligned for 8-byte access
                    // This should trap.
                    f.wasmAtomicLoad(memory: memory, address: address, loadType: .i64Load, offset: 0)
                }
            }

            // Store operations

            for memory in [unsharedMemory, sharedMemory] {
                wasmModule.addWasmFunction(with: [] => []) { f, _ in
                    let address = f.consti32(2) // Unaligned for 4-byte access
                    // This should trap.
                    let value = f.consti32(0x1337)
                    f.wasmAtomicStore(memory: memory, address: address, value: value, storeType: .i32Store, offset: 0)
                }
            }

            // memory64
            for memory in [unsharedMemory, sharedMemory] {
                wasmModule.addWasmFunction(with: [] => []) { f, _ in
                    let address = f.consti32(7) // Unaligned for 8-byte access
                    // This should trap.
                    let value = f.consti64(0xDEADBEEF)
                    f.wasmAtomicStore(memory: memory, address: address, value: value, storeType: .i64Store, offset: 0)
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

        let prog = b.finalize()
        let js = fuzzer.lifter.lift(prog)

        testForOutput(program: js, runner: runner, outputString: expectedOutput)
    }
}
