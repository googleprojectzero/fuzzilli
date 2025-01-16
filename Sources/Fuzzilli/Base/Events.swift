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
    public let InterestingProgramFound = Event<(program: Program, origin: ProgramOrigin)>()

    /// Signals a diagnostics event
    public let DiagnosticsEvent = Event<(name: String, content: Data)>()

    /// Signals that a program is about to be executed, and for what purpose.
    public let PreExecute = Event<(program: Program, purpose: ExecutionPurpose)>()

    /// Signals that a program was executed.
    public let PostExecute = Event<Execution>()

    /// In distributed fuzzing, signals that this child node has synchronized with its parent node.
    /// This event is guaranteed to be dispatched at most once, but may not be dispatched at
    /// all, for example if this node is configured to use its own corpus and so does not synchronize
    /// with its parent node.
    /// However, if this instance starts out in the .waiting state, this event is guaranteed to be
    /// dispatched once the state is no longer .waiting.
    public let Synchronized = Event<Void>()

    /// In distributed fuzzing, signals that a child node has connected to this parent node.
    public let ChildNodeConnected = Event<UUID>()

    /// In distributed fuzzing, signals that a child node has disconnected.
    public let ChildNodeDisconnected = Event<UUID>()

    /// Signals that a corpus import is complete.
    public let CorpusImportComplete = Event<()>()
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
    case parentShutdown

    public var description: String {
        switch self {
        case .userInitiated:
            return "user initiated stop"
        case .finished:
            return "finished fuzzing"
        case .fatalError:
            return "fatal error"
        case .parentShutdown:
            return "parent node shutting down"
        }
    }

    public func toExitCode() -> Int32 {
        switch self {
        case .userInitiated, .finished, .parentShutdown:
            return 0
        case .fatalError:
            return -1
        }
    }
}

/// Programs may be executed for different purposes, which are captured in this enum.
public enum ExecutionPurpose {
    /// The program is executed for fuzzing.
    case fuzzing
    /// The program is executed because it is imported from somewhere (e.g. another distributed fuzzing node or a corpus import)
    case programImport
    /// The program is executed as part of a minimization task.
    case minimization
    /// The (interesting) program is executed again to determine which (if any) of the interesting aspects trigger deterministically.
    case checkForDeterministicBehavior
    /// The program is executed as part of the startup routine.
    case startup
    /// The (instrumented) program is executed as part of a runtime-assisted mutation.
    case runtimeAssistedMutation
    /// Any other reason.
    case other
}
