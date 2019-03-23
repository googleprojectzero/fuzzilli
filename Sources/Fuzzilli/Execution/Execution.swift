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

func WIFEXITED(_ status: Int32) -> Bool {
    return status & 0x7f == 0
}

func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xff
}

func WTERMSIG(_ status: Int32) -> Int32 {
    return status & 0x7f
}

/// The possible outcome of a program execution.
public enum ExecutionOutcome: CustomStringConvertible {
    case crashed
    case failed
    case succeeded
    case timedOut
    
    public var description: String {
        switch self {
        case .crashed:
            return "Crashed!"
        case .failed:
            return "Failed"
        case .succeeded:
            return "Succeeded"
        case .timedOut:
            return "TimedOut"
        }
    }
    
    /// Converts an exit code into an ExecutionOutcome.
    public static func fromExitCode(_ code: Int32) -> ExecutionOutcome {
        if code == 0 {
            return .succeeded
        } else {
            return .failed
        }
    }

    /// Converts an exit status (from wait (2) etc.) into an execution outcome.
    public static func fromExitStatus(_ status: Int32) -> ExecutionOutcome {
        if WIFEXITED(status) {
            return fromExitCode(WEXITSTATUS(status))
        } else if WTERMSIG(status) == SIGKILL {
            return .timedOut
        } else {
            return .crashed
        }
    }
}

/// The result of executing a program.
public struct Execution {
    /// The script that was executed to produce this result
    public let script: String
    
    /// The PID of the process that executed the program
    public let pid: Int
    
    /// The execution outcome
    public let outcome: ExecutionOutcome
    
    /// The termination signal
    public let termsig: Int
    
    /// Program output (not stdout but FuzzIL output)
    public let output: String
    
    /// Execution time in ms
    public let execTime: UInt
}
