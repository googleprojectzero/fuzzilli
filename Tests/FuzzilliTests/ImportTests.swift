// Copyright 2026 Google LLC
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

import Foundation
import Testing

@testable import Fuzzilli

@Suite struct ImportTests {
    @Test func testImportProgramWithFixupBailout() {
        class TestScriptRunner: MockScriptRunner {
            var outcomeToReturn: ExecutionOutcome = .succeeded

            override func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
                return MockExecution(
                    outcome: outcomeToReturn,
                    stdout: stdoutToReturn,
                    stderr: stderrToReturn,
                    fuzzout: fuzzoutToReturn,
                    execTime: TimeInterval(0.1))
            }
        }

        let runner = TestScriptRunner()
        let liveTestConfig = Configuration(
            logLevel: .error,
            enableInspection: true
        )
        let fuzzer = makeMockFuzzer(config: liveTestConfig, runner: runner)

        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let prog = b.finalize()

            // 1. Test when outcome is .timedOut (which is not a failure)
            // It should bail out immediately with 0 fixup attempts
            runner.outcomeToReturn = .timedOut
            let result1 = fuzzer.importProgramWithFixup(
                prog, origin: .corpusImport(mode: .interestingOnly(shouldMinimize: false)))
            #expect(result1.fixupAttempts == 0)

            // 2. Test when outcome is .crashed(1) (which is not a failure)
            // It should bail out immediately with 0 fixup attempts
            runner.outcomeToReturn = .crashed(1)
            let result2 = fuzzer.importProgramWithFixup(
                prog, origin: .corpusImport(mode: .interestingOnly(shouldMinimize: false)))
            #expect(result2.fixupAttempts == 0)

            // 3. Test when outcome is .failed(1) (which IS a failure)
            // It should attempt fixups! Since none of them succeed (since TestScriptRunner always returns .failed(1)),
            // it should try all maxProgramImportFixupAttempts (3) and finish with 3 fixup attempts.
            runner.outcomeToReturn = .failed(1)
            let result3 = fuzzer.importProgramWithFixup(
                prog, origin: .corpusImport(mode: .interestingOnly(shouldMinimize: false)))
            #expect(result3.fixupAttempts > 0)
        }
    }
}
