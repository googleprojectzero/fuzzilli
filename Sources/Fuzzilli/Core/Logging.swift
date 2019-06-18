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
}

public class Logger {
    typealias LogEvent = Event<(creator: UUID, level: LogLevel, label: String, message: String)>
    
    private let creator: UUID
    private let event: LogEvent
    private let label: String
    private let minLevel: LogLevel
    
    init(creator: UUID, logEvent: LogEvent, label: String, minLevel: LogLevel) {
        self.creator = creator
        self.event = logEvent
        self.label = label
        self.minLevel = minLevel
    }
    
    private func log(level: LogLevel, msg: String) {
        if minLevel.rawValue <= level.rawValue {
            event.dispatch(with: (creator: creator, level: level, label: label, message: msg))
        }
    }
    
    /// Log a message with log level verbose.
    public func verbose(_ msg: String) {
        log(level: .verbose, msg: msg)
    }

    /// Log a message with log level info.
    public func info(_ msg: String) {
        log(level: .info, msg: msg)
    }

    /// Log a message with log level warning.
    public func warning(_ msg: String) {
        log(level: .warning, msg: msg)
    }

    /// Log a message with log level error.
    public func error(_ msg: String) {
        log(level: .error, msg: msg)
    }

    /// Log a message with log level fatal. This will afterwards terminate the application.
    public func fatal(_ msg: String) -> Never {
        log(level: .fatal, msg: msg)
        // We don't really want to do proper cleanup here as the fuzzer's internal state could be corupted.
        // As such, just kill the entire process here...
        abort()
    }
}
