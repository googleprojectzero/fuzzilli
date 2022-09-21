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
        }
    }

    public func isCrash() -> Bool {
        if case .crashed = self {
            return true
        } else {
            return false
        }
    }
}

/// The result of executing a program.
public protocol Execution {
    /// The execution outcome
    var outcome: ExecutionOutcome { get }

    /// The program's stdout
    var stdout: String { get }

    /// The program's stderr
    var stderr: String { get }

    /// The program's FuzzIL output
    var fuzzout: String { get }

    /// Execution time in microseconds
    var execTime: TimeInterval { get }
}
