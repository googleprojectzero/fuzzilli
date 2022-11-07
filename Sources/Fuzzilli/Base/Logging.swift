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

public enum LogLevel: Int {
    case verbose = 0
    case info    = 1
    case warning = 2
    case error   = 3
    case fatal   = 4

    public func isAtLeast(_ level: LogLevel) -> Bool {
        return self.rawValue <= level.rawValue
    }
}

/// Logs messages to the active fuzzer instance or prints them to stdout if no fuzzer is active.
public class Logger {
    private let label: String

    public init(withLabel label: String) {
        self.label = label
    }

    public func log(_ message: String, atLevel level: LogLevel) {
        if let fuzzer = Fuzzer.current {
            if fuzzer.config.logLevel.isAtLeast(level) {
                fuzzer.dispatchEvent(fuzzer.events.Log, data: (fuzzer.id, level, label, message))
            }
        } else {
            print("[\(label)] \(message)")
        }
    }

    /// Log a message with log level verbose.
    public func verbose(_ msg: String) {
        log(msg, atLevel: .verbose)
    }

    /// Log a message with log level info.
    public func info(_ msg: String) {
        log(msg, atLevel: .info)
    }

    /// Log a message with log level warning.
    public func warning(_ msg: String) {
        log(msg, atLevel: .warning)
    }

    /// Log a message with log level error.
    public func error(_ msg: String) {
        log(msg, atLevel: .error)
    }

    /// Log a message with log level fatal.
    /// This will terminate the process after shutting down the active fuzzer instance.
    public func fatal(_ msg: String) -> Never {
        log(msg, atLevel: .fatal)

        // Attempt a clean shutdown so any persistent state is cleaned up.
        // This should terminate the process (due to ShutdownComplete event handlers).
        if let fuzzer = Fuzzer.current {
            fuzzer.shutdown(reason: .fatalError)
        }

        // If the process hasn't terminated yet, just abort now.
        abort()
    }
}
