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

// Event dispatching implementation.
public class Event<T> {
    public typealias EventListener = (T) -> Void
    
    /// The list of observers for this event.
    private(set) public var listeners = [EventListener]()
    
    /// Registers an event listener for this event.
    public func addListener(_ listener: @escaping EventListener) {
        listeners.append(listener)
    }
}

/// List of all events that can be dispatched in a fuzzer.
public class Events {
    /// Signals that the fuzzer is fully initialized.
    public let Initialized = Event<Void>()
    
    /// Signals that a this instance is shutting down.
    public let Shutdown = Event<ShutdownReason>()
    
    /// Signals that this instance has successfully shut down.
    /// Clients are expected to terminate the hosting process when handling this event.
    public let ShutdownComplete = Event<ShutdownReason>()

    /// Signals that a log message was dispatched.
    /// The origin field contains the UUID of the fuzzer instance that originally logged the message.
    public let Log = Event<(origin: UUID, level: LogLevel, label: String, message: String)>()

    /// Signals that a new (mutated) program has been generated.
    public let ProgramGenerated = Event<Program>()

    /// Signals that a valid program has been found.
    public let ValidProgramFound = Event<Program>()

    /// Signals that an invalid program has been found.
    public let InvalidProgramFound = Event<Program>()

    /// Signals that a crashing program has been found. Dispatched after the crashing program has been minimized.
    public let CrashFound = Event<(program: Program, behaviour: CrashBehaviour, isUnique: Bool, origin: ProgramOrigin)>()

    /// Signals that a program causing a timeout has been found.
    public let TimeOutFound = Event<Program>()

    /// Signals that a new interesting program has been found, after the program has been minimized.
    public let InterestingProgramFound = Event<(program: Program, origin: ProgramOrigin, newTypeCollectionRun: Bool)>()

    /// Signals a diagnostics event
    public let DiagnosticsEvent = Event<(name: String, content: String)>()

    /// Signals that a program is about to be executed.
    public let PreExecute = Event<Program>()

    /// Signals that a program was executed.
    public let PostExecute = Event<Execution>()

    /// Signals that a worker has connected to this master instance.
    public let WorkerConnected = Event<UUID>()

    /// Signals that a worker has disconnected.
    public let WorkerDisconnected = Event<UUID>()
}

/// Crash behavior of a program.
public enum CrashBehaviour: String {
    case deterministic = "deterministic"
    case flaky         = "flaky"
}

/// Reasons for shutting down a fuzzer instance.
public enum ShutdownReason: CustomStringConvertible {
    case userInitiated
    case finished
    case fatalError
    case masterShutdown

    public var description: String {
        switch self {
        case .userInitiated:
            return "user initiated stop"
        case .finished:
            return "maximum number of iterations reached"
        case .fatalError:
            return "fatal error"
        case .masterShutdown:
            return "master shutting down"
        }
    }

    public func toExitCode() -> Int32 {
        switch self {
        case .userInitiated, .finished, .masterShutdown:
            return 0
        case .fatalError:
            return -1
        }
    }
}
