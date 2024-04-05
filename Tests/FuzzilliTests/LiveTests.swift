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
        case failed(failureMessage: String?)
        case succeeded
    }

    // Set to true to log failing programs
    static let VERBOSE = false

    func testValueGeneration() throws {
        guard let runner = JavaScriptExecutor() else {
            throw XCTSkip("Could not find js shell executable.")
        }

        let results = try Self.runLiveTest(withRunner: runner) { b in
            b.buildPrefix()
        }

        // We expect a maximum of 10% of ValueGeneration to fail
        checkFailureRate(testResults: results, maxFailureRate: 0.10)
    }

    // The closure can use the ProgramBuilder to emit a program of a specific
    // shape that is then executed with the given runner. We then check that
    // we stay below the maximum failure rate over the given number of iterations.
    static func runLiveTest(iterations n: Int = 250, withRunner runner: JavaScriptExecutor, body: (inout ProgramBuilder) -> Void) throws -> (failureRate: Double, failureMessages: [String: Int]) {
        let liveTestConfig = Configuration(logLevel: .warning, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        var failures = 0
        var failureMessages = [String: Int]()

        var programs = [(program: Program, jsProgram: String)]()
        // Pre-allocate this so that we don't need a lock in the `concurrentPerform`.
        var results = [ExecutionResult?](repeating: nil, count: n)

        for _ in 0..<n {
            var b = fuzzer.makeBuilder()

            body(&b)

            let program = b.finalize()
            let jsProgram = fuzzer.lifter.lift(program)

            programs.append((program, jsProgram))
        }

        DispatchQueue.concurrentPerform(iterations: n) { i in
            let result = executeAndParseResults(program: programs[i], runner: runner)
            results[i] = result
        }

        for result in results {
            switch result! {
            case .failed(let message):
                failures += 1
                if let message = message {
                    failureMessages[message] = (failureMessages[message] ?? 0) + 1
                }
            case .succeeded:
                break
            }
        }

        let failureRate = Double(failures) / Double(n)

        return (failureRate, failureMessages)
    }

    func checkFailureRate(testResults: (failureRate: Double, failureMessages: [String: Int]), maxFailureRate: Double) {
        if testResults.failureRate >= maxFailureRate {
            var message = "Failure rate is too high. Should be below \(String(format: "%.2f", maxFailureRate * 100))% but we observed \(String(format: "%.2f", testResults.failureRate * 100))%\n"
            message += "Observed failures:\n"
            for (signature, count) in testResults.failureMessages.sorted(by: { $0.value > $1.value }) {
                message += "    \(count)x \(signature)\n"
            }
            XCTFail(message)
        }
    }

    static func executeAndParseResults(program: (program: Program, jsProgram: String), runner: JavaScriptExecutor) -> ExecutionResult {

        do {
            let result = try runner.executeScript(program.jsProgram, withTimeout: 5 * Seconds)
            if result.isFailure {
                var signature: String? = nil

                for line in result.output.split(separator: "\n") {
                    if line.contains("Error:") {
                        // Remove anything after a potential 2nd ":", which is usually testcase dependent content, e.g. "SyntaxError: Invalid regular expression: /ep{}[]Z7/: Incomplete quantifier"
                        signature = line.split(separator: ":")[0...1].joined(separator: ":")
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

                return .failed(failureMessage: signature)
            }
        } catch {
            XCTFail("Could not execute script: \(error)")
        }

        return .succeeded
    }
}
