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

import Dispatch
import Foundation

/// A thread-safe queue for concurrently distributing programs during corpus import.
///
/// Popping from the end of the array via `removeLast()` is an O(1) operation.
/// Since the corpus is shuffled before population, popping from the end yields
/// unbiased random samples without requiring an upfront array reversal.
public class ThreadSafeImportQueue {
    private let queue = DispatchQueue(label: "fuzzilli.import-queue")
    private var programs: [Program]
    public let initialCount: Int

    public init(_ programs: [Program]) {
        self.programs = programs
        self.initialCount = programs.count
    }

    /// Dequeues and returns the next program in O(1) time, or nil if the queue is depleted.
    public func next() -> Program? {
        return nextWithProcessedCount()?.program
    }

    /// Dequeues and returns the next program together with the total number of
    /// programs dequeued so far in O(1) time, or nil if the queue is depleted.
    public func nextWithProcessedCount() -> (program: Program, totalProcessed: Int)? {
        return queue.sync {
            guard !programs.isEmpty else { return nil }
            let program = programs.removeLast()
            return (program, initialCount - programs.count)
        }
    }

    /// Number of programs remaining in the queue.
    public var count: Int {
        return queue.sync { programs.count }
    }

    /// Whether the queue has been completely depleted.
    public var isEmpty: Bool {
        return queue.sync { programs.isEmpty }
    }

    /// Import progress as a ratio between 0.0 and 1.0.
    public var progress: Double {
        return queue.sync {
            guard initialCount > 0 else { return 1.0 }
            return Double(initialCount - programs.count) / Double(initialCount)
        }
    }
}

extension ThreadSafeImportQueue: CustomStringConvertible {
    public var description: String {
        return
            "ThreadSafeImportQueue(remaining: \(count)/\(initialCount), progress: \(String(format: "%.1f%%", progress * 100)))"
    }
}
