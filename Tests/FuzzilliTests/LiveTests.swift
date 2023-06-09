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
    // Set to true to log failing programs
    static let VERBOSE = false

    func testValueGeneration() throws {
        guard let nodejs = NodeJS() else {
            throw XCTSkip("Could not find NodeJS executable.")
        }

        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let N = 250
        var failures = 0
        var failureMessages = [String: Int]()

        // TODO: consider running these in parallel.
        for _ in 0..<N {
            let b = fuzzer.makeBuilder()
            // Prefix building will run a handful of value generators. We use it instead of directly
            // calling buildValues() since we're mostly interested in emitting valid program prefixes.
            b.buildPrefix()

            let program = b.finalize()
            let jsProgram = fuzzer.lifter.lift(program, withOptions: .includeComments)

            // TODO: consider moving this code into a shared function once other tests need it as well.
            do {
                let result = try nodejs.executeScript(jsProgram, withTimeout: 5 * Seconds)
                if result.isFailure {
                    failures += 1

                    for line in result.output.split(separator: "\n") {
                        if line.contains("Error:") {
                            // Remove anything after a potential 2nd ":", which is usually testcase dependent content, e.g. "SyntaxError: Invalid regular expression: /ep{}[]Z7/: Incomplete quantifier"
                            let signature = line.split(separator: ":")[0...1].joined(separator: ":")
                            failureMessages[signature] = (failureMessages[signature] ?? 0) + 1
                        }
                    }

                    if LiveTests.VERBOSE {
                        let fuzzilProgram = FuzzILLifter().lift(program)
                        print("Program is invalid:")
                        print(jsProgram)
                        print("Out:")
                        print(result.output)
                        print("FuzzILCode:")
                        print(fuzzilProgram)
                    }
                }
            } catch {
                XCTFail("Could not execute script: \(error)")
            }
        }

        let failureRate = Double(failures) / Double(N)
        let maxFailureRate = 0.10        // TODO lower this (should probably be around 1-5%)
        if failureRate >= maxFailureRate {
            var message = "Failure rate for value generators is too high. Should be below \(String(format: "%.2f", maxFailureRate * 100))% but we observed \(String(format: "%.2f", failureRate * 100))%\n"
            message += "Observed failures:\n"
            for (signature, count) in failureMessages.sorted(by: { $0.value > $1.value }) {
                message += "    \(count)x \(signature)\n"
            }
            XCTFail(message)
        }
    }
}
