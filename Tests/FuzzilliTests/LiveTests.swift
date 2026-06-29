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

class LiveTests: XCTestCase {
    enum ExecutionResult {
        case failed(failureMessage: String)
        case succeeded
    }

    // Set to true to log failing programs
    static let VERBOSE = false

    /// Meta-test ensuring that the test framework can successfully terminate an endless loop.
    func testEndlessLoopTermination() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let results = try Self.runLiveTest(iterations: 1, withRunner: runner, timeoutInSeconds: 1) {
            b in
            b.loadInt(123)  // prefix

            let module = b.buildWasmModule { module in
                module.addWasmFunction(with: [] => []) { function, label, args in
                    function.wasmBuildLoop(with: [] => [], args: []) { label, args in
                        function.wasmBranch(to: label)
                        return []
                    }
                    return []
                }
            }
            b.callMethod(module.getExportedMethod(at: 0), on: module.loadExports(), withArgs: [])
        }
        assert(results.failureRate == 1)
        assert(results.failureMessages.count == 1)
    }

    func testValueGeneration() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest()

        let results = try Self.runLiveTest(withRunner: runner) { b in
            b.buildPrefix()
        }

        // We expect a maximum of 15% of ValueGeneration to fail
        checkFailureRate(testResults: results, maxFailureRate: 0.15)
    }

    func testWasmCodeGenerationAndCompilation() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(
            type: .any,
            withArguments: [
                "--experimental-fuzzing", "--wasm-allow-mixed-eh-for-testing",
                "--experimental-wasm-acquire-release",
            ]
        )

        let results = try Self.runLiveTest(withRunner: runner) { b in
            // Fuzzilli can't handle situations where there aren't any variables available.
            // Calling buildPrefix() however would significantly increase the error rate due to
            // the prefix itself failing. Instead we just create a dummy integer to bypass these
            // checks for having a prefix.
            b.loadInt(123)
            // Make sure we have some wasm-gc types that can be used by the wasm module.
            b.wasmDefineTypeGroup {
                b.build(n: 5)
            }
            // Make sure that we have at least one JavaScript function that we can call.
            b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.doReturn(b.binary(args[0], b.loadInt(1), with: .Add))
            }
            // Make at least one Wasm global available
            b.createWasmGlobal(value: .wasmi32(1337), isMutable: true)
            // Make at least one Wasm tag of each kind available.
            b.createWasmJSTag()
            b.createWasmTag(parameterTypes: [.wasmi32, .wasmf64])

            b.buildWasmModule { module in
                module.addMemory(
                    minPages: 2, maxPages: probability(0.5) ? nil : 5, isMemory64: probability(0.5))
                let signature = b.randomWasmSignature()
                module.addWasmFunction(with: signature) { function, label, args in
                    b.build(n: 40)
                    return signature.outputTypes.map {
                        b.randomVariable(ofType: $0) ?? function.generateRandomWasmVar(ofType: $0)!
                    }
                }
            }
        }

        // We expect a maximum of 1% of Wasm compilation attempts to fail.
        checkFailureRate(testResults: results, maxFailureRate: 0.01)
    }

    func testWasmCodeGenerationAndCompilationAndExecution() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(
            type: .any,
            withArguments: [
                "--experimental-fuzzing", "--wasm-allow-mixed-eh-for-testing",
                "--experimental-wasm-acquire-release",
            ]
        )

        let results = try Self.runLiveTest(withRunner: runner) { b in
            // Fuzzilli can't handle situations where there aren't any variables available.
            // Calling buildPrefix() however would significantly increase the error rate due to
            // the prefix itself failing. Instead we just create a dummy integer to bypass these
            // checks for having a prefix.
            b.loadInt(123)
            // Make sure we have some wasm-gc types that can be used by the wasm module.
            b.wasmDefineTypeGroup {
                b.build(n: 5)
            }
            // Make sure that we have at least one JavaScript function that we can call.
            let jsFunction = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.doReturn(args[0])
            }
            // Make at least one Wasm global available
            b.createWasmGlobal(value: .wasmi32(1337), isMutable: true)
            // Make at least one Wasm tag of each kind available.
            b.createWasmJSTag()
            b.createWasmTag(parameterTypes: [.wasmi32, .wasmf64])

            let wasmSignature = b.randomWasmSignature()
            let m = b.buildWasmModule { module in
                module.addMemory(
                    minPages: 2, maxPages: probability(0.5) ? nil : 5, isMemory64: probability(0.5))
                module.addWasmFunction(with: wasmSignature) { function, label, args in
                    b.build(n: 40)
                    return wasmSignature.outputTypes.map {
                        b.randomVariable(ofType: $0) ?? function.generateRandomWasmVar(ofType: $0)!
                    }
                }
            }

            // The wasm exception handling proposal contains instructions to deliberately trigger
            // exceptions. Catch these exceptions here to not treat them as test failures.
            b.buildTryCatchFinally {
                // TODO(manoskouk): Once we support wasm-gc types in signatures, we'll need
                // something more sophisticated.
                // TODO(pawkra): support shared refs.
                let args = wasmSignature.parameterTypes.map {
                    switch $0 {
                    case .wasmi64:
                        return b.loadBigInt(123)
                    case ILType.wasmFuncRef():
                        return jsFunction
                    case ILType.wasmNullExternRef(), ILType.wasmNullFuncRef(), ILType.wasmNullRef():
                        return b.loadNull()
                    case ILType.wasmExternRef(), ILType.wasmAnyRef():
                        return b.createObject(with: [:])
                    default:
                        return b.loadInt(321)
                    }
                }
                b.callMethod(m.getExportedMethod(at: 0), on: m.loadExports(), withArgs: args)
            } catchBody: { exception in
                let wasmGlobal = b.createNamedVariable(forBuiltin: "WebAssembly")
                let wasmException = b.getProperty("Exception", of: wasmGlobal)
                b.buildIf(b.unary(.LogicalNot, b.testInstanceOf(exception, wasmException))) {
                    b.throwException(exception)
                }
            }
        }

        // TODO(mliedtke): Figure out how to handle ref.cast and lower it.
        // We expect a maximum of 35% of Wasm execution attempts to fail.
        checkFailureRate(testResults: results, maxFailureRate: 0.35)
    }

    func testBinaryenWasmCodeGenerationAndCompilation() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(
            type: .any,
            withArguments: [
                "--wasm-staging", "--wasm-allow-mixed-eh-for-testing",
                "--experimental-fuzzing",
            ]
        )

        guard findWasmOptInPath() != nil else {
            throw XCTSkip(
                "wasm-opt not found in PATH. To run this test, please ensure that the directory containing wasm-opt is added to your PATH environment variable. Skipping test for now."
            )
        }

        let results = try Self.runLiveTest(withRunner: runner) { b in
            b.loadInt(123)  // dummy prefix
            if runBinaryenWasmGenerator(b: b) == nil {
                let errorMsg = b.loadString("BinaryenWasmGenerator failed to generate Wasm module")
                b.throwException(errorMsg)
            }
        }

        // For now, we expect a maximum of 10% of Wasm compilation attempts to fail.
        checkFailureRate(testResults: results, maxFailureRate: 0.1)
    }

    func testBinaryenWasmCodeGenerationAndCompilationAndExecution() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(
            type: .any,
            withArguments: [
                "--wasm-staging", "--wasm-allow-mixed-eh-for-testing",
                "--experimental-fuzzing",
            ]
        )

        guard findWasmOptInPath() != nil else {
            throw XCTSkip(
                "wasm-opt not found in PATH. To run this test, please ensure that the directory containing wasm-opt is added to your PATH environment variable. Skipping test for now."
            )
        }

        let results = try Self.runLiveTest(withRunner: runner) { b in
            b.loadInt(123)  // dummy prefix

            guard let metadata = runBinaryenWasmGenerator(b: b) else {
                let errorMsg = b.loadString("BinaryenWasmGenerator failed to generate Wasm module")
                b.throwException(errorMsg)
                return
            }

            // The last instruction in our generator was `b.getProperty("exports", of: instance)`.
            let exports = b.lastInstruction().output

            Self.generateACallToWasmExport(b: b, metadata: metadata, exports: exports)
        }

        // For now, we expect a maximum of 50% of Wasm execution attempts to fail.
        checkFailureRate(testResults: results, maxFailureRate: 0.50)
    }

    func testBinaryenWasmMutator() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(
            type: .any,
            withArguments: [
                "--wasm-staging", "--wasm-allow-mixed-eh-for-testing",
                "--experimental-fuzzing",
            ]
        )

        guard let wasmOptPath = findWasmOptInPath() else {
            throw XCTSkip("wasm-opt not found in PATH")
        }

        let liveTestConfig = Configuration(
            logLevel: .error,
            enableInspection: true,
            wasmOptPath: wasmOptPath
        )
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let mutator = BinaryenWasmMutator()

        let results = try Self.runLiveTest(withRunner: runner) { b in
            // Generate program in a separate builder.
            let genBuilder = fuzzer.makeBuilder()
            guard let metadata = runBinaryenWasmGenerator(b: genBuilder) else {
                let errorMsg = b.loadString("BinaryenWasmGenerator failed to generate Wasm module")
                b.throwException(errorMsg)
                return
            }
            let program = genBuilder.finalize()

            // Verify original metadata.
            var originalMetadata: WasmModuleMetadata? = nil
            for instr in program.code {
                if let op = instr.op as? RawWasmModule {
                    originalMetadata = op.metadata
                    break
                }
            }
            XCTAssertNotNil(originalMetadata, "Generated program should contain a Wasm module")

            // Mutate the program.
            let mutBuilder = fuzzer.makeBuilder(forMutating: program)
            guard let mutatedProgram = mutator.mutate(program, using: mutBuilder, for: fuzzer)
            else {
                fatalError("Mutator failed to produce program")
            }

            // Verify metadata preservation.
            var mutatedMetadata: WasmModuleMetadata? = nil
            for instr in mutatedProgram.code {
                if let op = instr.op as? RawWasmModule {
                    mutatedMetadata = op.metadata
                    break
                }
            }
            XCTAssertNotNil(mutatedMetadata, "Mutated program should contain a Wasm module")
            XCTAssertEqual(
                originalMetadata, mutatedMetadata,
                "Wasm metadata should NOT have changed after mutation")

            // Append the mutated program onto the ProgramBuilder.
            b.append(mutatedProgram)

            // Generate a call to the exported Wasm function.
            let exports = b.lastInstruction().output
            Self.generateACallToWasmExport(b: b, metadata: metadata, exports: exports)
        }

        checkFailureRate(testResults: results, maxFailureRate: 0.65)
    }

    // The closure can use the ProgramBuilder to emit a program of a specific
    // shape that is then executed with the given runner. We then check that
    // we stay below the maximum failure rate over the given number of iterations.
    static func runLiveTest(
        iterations n: Int = 250, withRunner runner: JavaScriptExecutor, timeoutInSeconds: Int = 5,
        body: (ProgramBuilder) -> Void
    ) throws -> (failureRate: Double, failureMessages: [String: Int]) {
        let liveTestConfig = Configuration(
            logLevel: .error,
            enableInspection: true,
            wasmOptPath: findWasmOptInPath()
        )

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        var failures = 0
        var failureMessages = [String: Int]()

        var failureDirectory: URL? = nil

        if ProcessInfo.processInfo.environment["FUZZILLI_TEST_DEBUG"] != nil {
            failureDirectory = FileManager().temporaryDirectory.appendingPathComponent(
                "fuzzilli_livetest_failures")
            print("Saving LiveTest failures to \(String(describing: failureDirectory!)).")
            do {
                try? FileManager.default.removeItem(at: failureDirectory!)
                try FileManager.default.createDirectory(
                    at: failureDirectory!, withIntermediateDirectories: true)
            } catch {}
        }

        var programs = [(program: Program, jsProgram: String)]()
        // Pre-allocate this so that we don't need a lock in the `concurrentPerform`.
        var results = [ExecutionResult?](repeating: nil, count: n)

        for _ in 0..<n {
            let b = fuzzer.makeBuilder()

            body(b)

            let program = b.finalize()
            let jsProgram = fuzzer.lifter.lift(program)

            programs.append((program, jsProgram))
        }

        DispatchQueue.concurrentPerform(iterations: n) { i in
            let result = executeAndParseResults(
                program: programs[i], runner: runner, timeoutInSeconds: timeoutInSeconds)
            results[i] = result
        }

        for (i, result) in results.enumerated() {
            switch result! {
            case .failed(let message):
                if let path = failureDirectory {
                    programs[i].program.storeToDisk(
                        atPath: path.appendingPathComponent("failure_\(i).fzil").path)
                }
                failures += 1
                failureMessages[message] = (failureMessages[message] ?? 0) + 1
            case .succeeded:
                break
            }
        }

        let failureRate = Double(failures) / Double(n)

        return (failureRate, failureMessages)
    }

    func checkFailureRate(
        testResults: (failureRate: Double, failureMessages: [String: Int]), maxFailureRate: Double
    ) {
        if testResults.failureRate >= maxFailureRate {
            var message =
                "Failure rate is too high. Should be below \(String(format: "%.2f", maxFailureRate * 100))% but we observed \(String(format: "%.2f", testResults.failureRate * 100))%\n"
            message += "Observed failures:\n"
            for (signature, count) in testResults.failureMessages.sorted(by: { $0.value > $1.value }
            ) {
                message += "    \(count)x \(signature)\n"
            }
            if ProcessInfo.processInfo.environment["FUZZILLI_TEST_DEBUG"] == nil {
                message +=
                    "If you want to dump failing programs to disk you can set FUZZILLI_TEST_DEBUG=1 in your environment."
            }
            XCTFail(message)
        }
    }

    static func executeAndParseResults(
        program: (program: Program, jsProgram: String), runner: JavaScriptExecutor,
        timeoutInSeconds: Int
    ) -> ExecutionResult {

        do {
            let result = try runner.executeScript(
                program.jsProgram,
                withTimeout: Double(timeoutInSeconds) * Seconds)
            if result.isFailure {
                var signature: String? = nil

                for line in (result.output + result.error).split(separator: "\n") {
                    if line.contains("Error:") {
                        // Remove anything after a potential 2nd ":", which is usually testcase dependent content, e.g. "SyntaxError: Invalid regular expression: /ep{}[]Z7/: Incomplete quantifier"
                        signature = line.split(separator: ":")[0...1].joined(separator: ":")
                    } else if line.contains("[object WebAssembly.Exception]") {
                        // An uncaught thrown wasm tag results in an output like this in d8:
                        //   undefined:0: [object WebAssembly.Exception]
                        // Treat anything that contains the WebAssembly.Exception object as one
                        // special signature.
                        signature = "<Uncaught WebAssembly.Exception>"
                    }
                }

                if Self.VERBOSE {
                    let fuzzilProgram = FuzzILLifter().lift(program.program)
                    print("Program is invalid:")
                    print(program.jsProgram)
                    print("Out:")
                    print(result.output)
                    print("FuzzILCode:")
                    print(fuzzilProgram)
                }

                return .failed(failureMessage: signature ?? "<Unrecognized error>")
            }
        } catch {
            XCTFail("Could not execute script: \(error)")
        }

        return .succeeded
    }

    // Generates a call to an exported function or accesses an exported global if no simple function is available.
    private static func generateACallToWasmExport(
        b: ProgramBuilder,
        metadata: WasmModuleMetadata,
        exports: Variable
    ) {
        let simpleTypes: [ILType] = [.integer, .bigint, .float]

        // Find a function with simple parameters to call.
        let simpleFunc = metadata.functions.first { funcExport in
            let paramsOk = funcExport.signature.parameters.allSatisfy { param in
                guard case .plain(let type) = param else {
                    fatalError("Unexpected Wasm parameter type")
                }
                return simpleTypes.contains(type)
            }
            return paramsOk
        }

        // Call the method inside a try-catch block to ignore expected WebAssembly runtime exceptions.
        b.buildTryCatchFinally {
            if let targetFunc = simpleFunc {
                let args = targetFunc.signature.parameters.map { param in
                    guard case .plain(let type) = param else {
                        fatalError("Unexpected Wasm parameter type")
                    }

                    if let randomVar = b.randomVariable(ofType: type) {
                        return randomVar
                    }

                    if type.Is(.integer) {
                        return b.loadInt(0)
                    } else if type.Is(.bigint) {
                        return b.loadBigInt(0)
                    } else {
                        // type.Is(.float)
                        return b.loadFloat(0.0)
                    }
                }
                b.callMethod(targetFunc.name, on: exports, withArgs: args)
            } else if let firstGlobal = metadata.globals.first {
                let globalObj = b.getProperty(firstGlobal, of: exports)
                b.getProperty("value", of: globalObj)
            }
        } catchBody: { exception in
            let wasmGlobal = b.createNamedVariable(forBuiltin: "WebAssembly")
            let wasmException = b.getProperty("Exception", of: wasmGlobal)
            b.buildIf(b.unary(.LogicalNot, b.testInstanceOf(exception, wasmException))) {
                b.throwException(exception)
            }
        }
    }
}
