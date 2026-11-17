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

private struct TestExecution: Execution {
    let outcome: ExecutionOutcome
    let execTime: TimeInterval
    let stdout: String
    let stderr: String
    let fuzzout: String
}

private func testExecution(
    _ fuzzout: String, outcome: ExecutionOutcome = .succeeded, stdout: String = ""
) -> Execution {
    return TestExecution(
        outcome: outcome, execTime: 0.1, stdout: stdout, stderr: "", fuzzout: fuzzout)
}

struct DiffExecutionTests {
    @Test func testMatchingOutputsAreNotDifferential() {
        let optimized = testExecution("number\n5\n0.2\n")
        let reference = testExecution("number\n5\n0.2\n")

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .succeeded)
    }

    @Test func testMatchingOutputsWithSurroundingWhitespaceAreNotDifferential() {
        let optimized = testExecution("number\n5\n0.2\n")
        let reference = testExecution("\n number\n5\n0.2\n\n")

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .succeeded)
    }

    @Test func testDifferentFuzzoutIsDifferential() {
        let optimized = testExecution("number\n5\n0.2\n")
        let reference = testExecution("number\n5\nInfinity\n")

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .differential)
    }

    @Test func testDifferentStdoutIsDifferential() {
        let optimized = testExecution("5", stdout: "5")
        let reference = testExecution("5", stdout: "-\u{221E}")

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .differential)
    }

    @Test func testReferenceFailureIsDifferential() {
        let optimized = testExecution("number\n5\n0.2\n")
        let reference = testExecution("", outcome: .failed(1))

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .differential)
    }

    @Test func testReferenceTimeoutIsNotDifferential() {
        let optimized = testExecution("")
        let reference = testExecution("", outcome: .timedOut)

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .succeeded)
    }

    @Test func testBothFailedIsNotDifferential() {
        let optimized = testExecution("", outcome: .failed(1))
        let reference = testExecution("", outcome: .failed(1))

        let result = DiffExecution.compareOutputs(optimized: optimized, unoptimized: reference)
        #expect(result.outcome == .succeeded)
    }
}

struct ProfileTests {
    @Test func testMaglevDifferentialProfile() {
        #expect(v8MaglevDifferentialProfile.isDifferential)
        #expect(v8MaglevDifferentialProfile.differentialMode == .output)

        let optimizedArgs = v8MaglevDifferentialProfile.processArgs(false, false)
        #expect(optimizedArgs.contains("--maglev"))
        #expect(optimizedArgs.contains("--maglev-as-top-tier"))
        #expect(optimizedArgs.contains("--maglev-assert-types"))
        #expect(optimizedArgs.contains("--no-turbofan"))
        #expect(optimizedArgs.contains("--allow-natives-syntax"))
        #expect(optimizedArgs.contains("--expose-gc"))
        #expect(optimizedArgs.contains("--gc-interval=100"))

        let referenceArgs = v8MaglevDifferentialProfile.processArgsReference
        #expect(referenceArgs != nil)
        #expect(referenceArgs!.contains("--no-maglev"))
        #expect(referenceArgs!.contains("--no-turbofan"))
        #expect(referenceArgs!.contains("--allow-natives-syntax"))
        #expect(referenceArgs!.contains("--expose-gc"))
        #expect(referenceArgs!.contains("--gc-interval=100"))
        #expect(!referenceArgs!.contains("--maglev"))
    }
}
