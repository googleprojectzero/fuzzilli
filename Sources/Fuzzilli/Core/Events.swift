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
    public typealias EventObserver = (T) -> Void
    
    // Listeners and observers. Observers don't receive any data associated with the event.
    private var observers = [EventObserver]()
    
    // Queue on which event listeners are executed (synchronously or asynchronously).
    private let queue: OperationQueue
    
    public init(_ queue: OperationQueue) {
        self.queue =  queue
    }
    
    /// Dispatches this event.
    ///
    /// This will synchronously run all event listeners registered for this event.
    ///
    /// - Parameters:
    ///   - data: The data for the event.
    public func dispatch(with data: T) {
        assert(OperationQueue.current == queue)
        for observer in observers {
            observer(data)
        }
    }
    
    /// Dispatches this event.
    ///
    /// This will asynchronously run all event listeners registered for this event.
    ///
    /// - Parameters:
    ///   - data: The data for the event.
    public func dispatchAsync(with data: T) {
        queue.addOperation {
            self.dispatch(with: data)
        }
    }
    
    /// Registers an event listener for this event.
    public func observe(_ observer: @escaping EventObserver) {
        assert(OperationQueue.current == queue)
        observers.append(observer)
    }
}

// Special casing for events without associated data.
extension Event where T == Void {
    /// Dispatches this event.
    ///
    /// This will synchronously run all event listeners registered for this event.
    public func dispatch() {
        self.dispatch(with: ())
    }
    
    /// Dispatches this event.
    ///
    /// This will asynchronously run all event listeners registered for this event.
    public func dispatchAsync() {
        self.dispatchAsync(with: ())
    }
}

/// List of all events that can be dispatched in a fuzzer.
public class Events {
    /// Signals that the fuzzer is fully initialized.
    public let Initialized: Event<Void>
    
    /// Signals that a this instance is shutting down.
    public let Shutdown: Event<Void>
    
    /// Signals that this instance has successfully shut down.
    /// This is useful for embedders to e.g. terminate the fuzzer process on completion.
    public let ShutdownComplete: Event<Void>

    /// Signals that a log message was dispatched.
    /// The creator field is the UUID of the fuzzer instance that originally created the message.
    public let Log: Event<(creator: UUID, level: LogLevel, label: String, message: String)>

    /// Signals that a new (mutated) program has been generated.
    public let ProgramGenerated: Event<Program>
    
    /// Signals that a new program has been imported.
    public let ProgramImported: Event<Program>

    /// Signals that a valid program has been found.
    public let ValidProgramFound: Event<(program: Program, mutator: String)>

    /// Signals that an invalid program has been found.
    public let InvalidProgramFound: Event<(program: Program, mutator: String)>
    
    /// Signals that a crashing program has been found. Dispatched after the crashing program has been minimized.
    public let CrashFound: Event<(program: Program, behaviour: CrashBehaviour, signal: Int, pid: Int, isUnique: Bool, isImported: Bool)>
    
    /// Signals that a program causing a timeout has been found.
    public let TimeOutFound: Event<Program>
    
    /// Signals that a new interesting program has been found, after the program has been minimized.
    public let InterestingProgramFound: Event<(program: Program, isImported: Bool)>

    /// Signals that a program is about to be executed.
    public let PreExecute: Event<Program>
    
    /// Signals that a program was executed.
    public let PostExecute: Event<Execution>
    
    /// Signals that a worker has connected to this master instance.
    public let WorkerConnected: Event<UUID>
    
    /// Signals that a worker has disconnected.
    public let WorkerDisconnected: Event<UUID>
    
    init(_ queue: OperationQueue) {
        self.Initialized = Event(queue)
        self.Shutdown = Event(queue)
        self.ShutdownComplete = Event(queue)
        self.Log = Event(queue)
        self.ProgramGenerated = Event(queue)
        self.ProgramImported = Event(queue)
        self.ValidProgramFound = Event(queue)
        self.InvalidProgramFound = Event(queue)
        self.CrashFound = Event(queue)
        self.TimeOutFound = Event(queue)
        self.InterestingProgramFound = Event(queue)
        self.PreExecute = Event(queue)
        self.PostExecute = Event(queue)
        self.WorkerConnected = Event(queue)
        self.WorkerDisconnected = Event(queue)
    }
}
