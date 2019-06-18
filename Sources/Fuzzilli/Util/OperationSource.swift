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

/// A lightweight wrapper around DispatchSources that enqueues operations
/// into an OperationQueue.
public class OperationSource {
    /// The underlying dispatch source.
    private let source: DispatchSourceProtocol
    
    /// Initializes this OperationSource.
    ///
    /// This takes ownership of the given dispatch source and activates it.
    /// The given handler block will be enqueued into the operation queue
    /// whenever the dispatch source triggers.
    private init(source: DispatchSourceProtocol, handler: @escaping () -> Void, queue: OperationQueue) {
        self.source = source
        source.setEventHandler {
            // We have to "emulate" the behaviour of a single queue handling the events. As
            // such we need to suspend the event source until the real handler has executed
            // on the target queue. Otherwise, we would potentially invoke the event handler
            // multiple times for the same event which might e.g. lead to blocking I/O.
            source.suspend()
            let op = BlockOperation(block: handler)
            op.completionBlock = {
                source.resume()
            }
            queue.addOperation(op)
        }
        source.activate()
    }
    
    /// Cancels this operation source so that no further events are dispatched by it.
    public func cancel() {
        source.cancel()
    }
    
    /// Constructs and activates a timer that triggers on the provided OperationQueue.
    ///
    /// - Parameters:
    ///   - deadline: The time after which to execute the block
    ///   - repeating: The interval for repeating this timer
    ///   - queue: The OperationQueue on which the block is executed
    ///   - block: The block to execute whenever the timer trigges
    /// - Returns: A new OperationSource
    public static func timer(deadline: DispatchTime, repeating: DispatchTimeInterval = .never, on queue: OperationQueue, block: @escaping () -> Void) -> OperationSource {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        source.schedule(deadline: deadline, repeating: repeating)
        return OperationSource(source: source, handler: block, queue: queue)
    }
    
    /// Constructs and activates an operation source that triggers when the current process receives the specified unix signal.
    ///
    /// - Parameters:
    ///   - signal: The signal to listen for
    ///   - queue: The OperationQueue on which to execute the block
    ///   - block: The block to execute when the signal is received
    /// - Returns: A new OperationSource
    public static func forReceivingSignal(_ signal: Int32, on queue: OperationQueue, block: @escaping () -> Void) -> OperationSource {
        let source = DispatchSource.makeSignalSource(signal: signal, queue: DispatchQueue.global())
        return OperationSource(source: source, handler: block, queue: queue)
    }
    
    /// Constructs and activates an operation source that triggers when the specified file descriptor becomes readable.
    ///
    /// - Parameters:
    ///   - fileDescriptor: The file descriptor to monitor
    ///   - queue: The OperationQueue on which to execute the block
    ///   - block: The block to execute when the file descriptor becomes readable
    /// - Returns: A new OperationSource
    public static func forReading(from fileDescriptor: Int32, on queue: OperationQueue, block: @escaping () -> Void) -> OperationSource {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: DispatchQueue.global())
        return OperationSource(source: source, handler: block, queue: queue)
    }
    
    /// Constructs and activates an operation source that triggers when the specified file descriptor becomes writable.
    ///
    /// - Parameters:
    ///   - fileDescriptor: The file descriptor to monitor
    ///   - queue: The OperationQueue on which to execute the block
    ///   - block: The block to execute when the file descriptor becomes writable
    /// - Returns: A new OperationSource
    public static func forWriting(to fileDescriptor: Int32, on queue: OperationQueue, block: @escaping () -> Void) -> OperationSource {
        let source = DispatchSource.makeWriteSource(fileDescriptor: fileDescriptor, queue: DispatchQueue.global())
        return OperationSource(source: source, handler: block, queue: queue)
    }
}
