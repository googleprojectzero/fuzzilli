// Copyright 2019 Google LLC
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

/// The possible outcome of a program execution.
public enum ExecutionOutcome: CustomStringConvertible, Equatable, Hashable {
    case crashed(Int)
    case failed(Int)
    case succeeded
    case timedOut
    // This outcome is added to support native differential fuzzing.
    // It should get very similar treatment to crashed -> if the run resulted
    // in a differential, most likely there's a bug.
    // Please note that this feature is unstable yet, so the statement above
    // might not always be the case.
    case differential

    public var description: String {
        switch self {
        case .crashed(let signal):
            return "Crashed (signal \(signal))"
        case .failed(let exitcode):
            return "Failed (exit code \(exitcode))"
        case .succeeded:
            return "Succeeded"
        case .timedOut:
            return "TimedOut"
        case .differential:
            return "Differential"
        }
    }

    public func isCrash() -> Bool {
        if case .crashed = self {
            return true
        } else {
            return false
        }
    }

    public func isFailure() -> Bool {
        if case .failed = self {
            return true
        } else {
            return false
        }
    }

    public func isDifferential() -> Bool {
        if case .differential = self {
            return true
        } else {
            return false
        }
    }
}

/// The result of executing a program.
public protocol Execution {
    var outcome: ExecutionOutcome { get }
    var stdout: String { get }
    var stderr: String { get }
    var fuzzout: String { get }
    var execTime: TimeInterval { get }
}

/// Struct to capture result of exection in differential mode
struct DiffExecution: Execution {
    let outcome: ExecutionOutcome
    let execTime: TimeInterval
    let stdout: String
    let stderr: String
    let fuzzout: String

    private init(
        outcome: ExecutionOutcome,
        execTime: TimeInterval,
        stdout: String,
        stderr: String,
        fuzzout: String
    ) {
        self.outcome = outcome
        self.execTime = execTime
        self.stdout = stdout
        self.stderr = stderr
        self.fuzzout = fuzzout
    }

    // TODO(mdanylo): we shouldn't pass dump outputs as a separate parameter,
    // instead we should rather make them a part of a REPRL protocol between Fuzzilli and V8.
    static func diff(optExec: Execution, unoptExec: Execution,
            optDumpOut: String, unoptDumpOut: String) -> Execution {

        assert(optExec.outcome == .succeeded && unoptExec.outcome == .succeeded)

        func formatDiff(label: String, optData: String, unoptData: String) -> String {
            return """
            === OPT \(label) ===
            \(optData)

            === UNOPT \(label) ===
            \(unoptData)
            """
        }

        let relateOutcome = DiffOracle.relate(optDumpOut, with: unoptDumpOut)

        return DiffExecution(
            outcome: relateOutcome ? .succeeded : .differential,
            execTime: optExec.execTime,
            stdout: formatDiff(label: "STDOUT", optData: optExec.stdout, unoptData: unoptExec.stdout),
            stderr: formatDiff(label: "STDERR", optData: optExec.stderr, unoptData: unoptExec.stderr),
            fuzzout: formatDiff(label: "FUZZOUT", optData: optExec.fuzzout, unoptData: unoptExec.fuzzout)
        )
    }
}
