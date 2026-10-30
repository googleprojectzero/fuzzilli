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
    public struct Statistics {
        /// The number of programs whose import outcome was recorded. Programs that were dequeued
        /// but are still being processed (e.g. by other instances sharing the queue) aren't counted.
        public var numberOfProgramsProcessedSoFar = 0
        public var numberOfProgramsThatExecutedSuccessfullyDuringImport = 0
        public var numberOfProgramsThatWereImport = 0
        public var numberOfProgramsNotImportedBecauseUninteresting = 0
        public var numberOfProgramsThatFailedDuringImport = 0
        public var numberOfProgramsThatTimedOutDuringImport = 0
        public var numberOfProgramsThatNeededOneFixupAttempt = 0
        public var numberOfProgramsThatNeededTwoFixupAttempts = 0
        public var numberOfProgramsThatNeededThreeFixupAttempts = 0
        public var numberOfProgramsRequiringWasmButDisabled = 0
        public var numberOfProgramsRequiringBundlesButDisabled = 0
        public var convergencePatterns = [String: Int]()

        public var numberOfProgramsThatNeededFixup: Int {
            return numberOfProgramsThatNeededOneFixupAttempt
                + numberOfProgramsThatNeededTwoFixupAttempts
                + numberOfProgramsThatNeededThreeFixupAttempts
        }

        /// Records the execution outcome and fixup attempts for an imported program.
        mutating func recordOutcome(_ result: Fuzzer.ImportResult, fixupAttempts: Int) {
            numberOfProgramsProcessedSoFar += 1
            switch result {
            case .imported:
                numberOfProgramsThatExecutedSuccessfullyDuringImport += 1
                numberOfProgramsThatWereImport += 1
                switch fixupAttempts {
                case 0: break
                case 1: numberOfProgramsThatNeededOneFixupAttempt += 1
                case 2: numberOfProgramsThatNeededTwoFixupAttempts += 1
                case 3: numberOfProgramsThatNeededThreeFixupAttempts += 1
                default: fatalError("Unexpected number of fixup rounds: \(fixupAttempts)")
                }
            case .dropped:
                // Dropping a program is treated as success.
                numberOfProgramsThatExecutedSuccessfullyDuringImport += 1
            case .needsWasm:
                numberOfProgramsRequiringWasmButDisabled += 1
            case .needsBundles:
                numberOfProgramsRequiringBundlesButDisabled += 1
            case .failed(let outcome):
                switch outcome {
                case .succeeded:
                    // The execution succeeded, but the program was not imported (e.g. because it was not interesting).
                    numberOfProgramsThatExecutedSuccessfullyDuringImport += 1
                    numberOfProgramsNotImportedBecauseUninteresting += 1
                case .failed:
                    numberOfProgramsThatFailedDuringImport += 1
                case .timedOut:
                    numberOfProgramsThatTimedOutDuringImport += 1
                case .crashed, .differential:
                    // This is unexpected during corpus import (unless it's a crash/differential corpus), so we don't track these.
                    break
                }
            }
        }
    }

    private let queue = DispatchQueue(label: "fuzzilli.import-queue")
    private var programs: [Program]
    private var stats = Statistics()
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

    /// Records the execution outcome and fixup attempts for an imported program.
    public func recordOutcome(_ result: Fuzzer.ImportResult, fixupAttempts: Int) {
        queue.sync {
            stats.recordOutcome(result, fixupAttempts: fixupAttempts)
        }
    }

    /// Records a convergence pattern observed during program import.
    public func recordConvergencePattern(_ pattern: String) {
        queue.sync {
            stats.convergencePatterns[pattern, default: 0] += 1
        }
    }

    /// Returns a snapshot of the current aggregated import statistics.
    public var statistics: Statistics {
        return queue.sync { stats }
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
