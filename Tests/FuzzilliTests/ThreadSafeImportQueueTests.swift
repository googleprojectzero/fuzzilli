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
import Testing

@testable import Fuzzilli

@Suite struct ThreadSafeImportQueueTests {
    private static let fuzzer = makeMockFuzzer()

    private func makeTestProgram(intVal: Int64) -> Program {
        return Self.fuzzer.sync {
            let b = Self.fuzzer.makeBuilder()
            b.loadInt(intVal)
            return b.finalize()
        }
    }

    private func makeTestPrograms(count: Int) -> [Program] {
        return Self.fuzzer.sync {
            var progs = [Program]()
            progs.reserveCapacity(count)
            for i in 0..<count {
                let b = Self.fuzzer.makeBuilder()
                b.loadInt(Int64(i))
                progs.append(b.finalize())
            }
            return progs
        }
    }

    @Test func testEmptyQueue() {
        let queue = ThreadSafeImportQueue([])
        #expect(queue.initialCount == 0)
        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
        #expect(queue.progress == 1.0)
        #expect(queue.next() == nil)
    }

    @Test func testDequeueOrderAndProgress() {
        let p0 = makeTestProgram(intVal: 0)
        let p1 = makeTestProgram(intVal: 1)
        let p2 = makeTestProgram(intVal: 2)

        let queue = ThreadSafeImportQueue([p0, p1, p2])
        #expect(queue.initialCount == 3)
        #expect(queue.count == 3)
        #expect(queue.isEmpty == false)
        #expect(queue.progress == 0.0)

        // Dequeue from end of array (p2)
        let first = queue.next()
        #expect(first == p2)
        #expect(queue.count == 2)
        #expect(queue.progress == 1.0 / 3.0)

        // Dequeue next program (p1)
        let second = queue.next()
        #expect(second == p1)
        #expect(queue.count == 1)
        #expect(queue.progress == 2.0 / 3.0)

        // Dequeue last remaining program (p0)
        let third = queue.next()
        #expect(third == p0)
        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
        #expect(queue.progress == 1.0)

        // Queue is depleted
        #expect(queue.next() == nil)
        #expect(queue.count == 0)
        #expect(queue.isEmpty == true)
    }

    @Test func testConcurrentDequeueingSafety() {
        let numPrograms = 1000
        let programs = makeTestPrograms(count: numPrograms)

        let queue = ThreadSafeImportQueue(programs)
        #expect(queue.initialCount == numPrograms)
        #expect(queue.count == numPrograms)

        let numWorkers = 8
        let resultsLock = DispatchQueue(label: "test.results.lock")
        var dequeuedPrograms = [Program]()
        dequeuedPrograms.reserveCapacity(numPrograms)

        DispatchQueue.concurrentPerform(iterations: numWorkers) { _ in
            var localDequeued = [Program]()
            while let prog = queue.next() {
                localDequeued.append(prog)
            }
            resultsLock.sync {
                dequeuedPrograms.append(contentsOf: localDequeued)
            }
        }

        #expect(queue.isEmpty == true)
        #expect(queue.count == 0)
        #expect(queue.progress == 1.0)
        #expect(dequeuedPrograms.count == numPrograms)

        // Verify that all original programs were dequeued with no duplicates or omissions.
        var originalSet = Set<Data>()
        for p in programs {
            let data = try! p.asProtobuf().serializedData()
            originalSet.insert(data)
        }

        var dequeuedSet = Set<Data>()
        for p in dequeuedPrograms {
            let data = try! p.asProtobuf().serializedData()
            #expect(!dequeuedSet.contains(data))
            dequeuedSet.insert(data)
        }

        #expect(dequeuedSet == originalSet)
    }

    @Test func testCorpusImportJobIntegration() {
        let p0 = makeTestProgram(intVal: 10)
        let p1 = makeTestProgram(intVal: 20)
        let queue = ThreadSafeImportQueue([p0, p1])

        let job1 = Fuzzer.CorpusImportJob(queue: queue, mode: .full)
        let job2 = Fuzzer.CorpusImportJob(queue: queue, mode: .full)
        #expect(job1.totalNumberOfProgramsToImport == 2)
        #expect(job1.statistics.numberOfProgramsProcessedSoFar == 0)
        #expect(job1.isFinished == false)
        #expect(job1.progress() == 0.0)

        // Jobs sharing a queue also share its statistics. A program only counts as processed once
        // its outcome was recorded.
        let first = job1.nextProgram()
        #expect(first?.program == p1)
        #expect(first?.totalProcessed == 1)
        #expect(job1.statistics.numberOfProgramsProcessedSoFar == 0)
        job1.notifyImportOutcome(.imported, fixupAttempts: 0)
        #expect(job1.statistics.numberOfProgramsProcessedSoFar == 1)
        #expect(job2.statistics.numberOfProgramsProcessedSoFar == 1)
        #expect(job1.progress() == 0.5)
        #expect(job1.isFinished == false)

        let second = job2.nextProgram()
        #expect(second?.program == p0)
        #expect(second?.totalProcessed == 2)
        job2.notifyImportOutcome(.imported, fixupAttempts: 0)
        #expect(job1.statistics.numberOfProgramsProcessedSoFar == 2)
        #expect(job2.statistics.numberOfProgramsProcessedSoFar == 2)
        #expect(job1.progress() == 1.0)
        #expect(job1.isFinished == true)
        #expect(job2.isFinished == true)

        // Dequeueing on a depleted job must safely return nil without incrementing counter
        let third = job1.nextProgram()
        #expect(third == nil)
        #expect(job1.statistics.numberOfProgramsProcessedSoFar == 2)
        #expect(job1.isFinished == true)
    }

    @Test func testRecordedImportStatistics() {
        let queue = ThreadSafeImportQueue(makeTestPrograms(count: 2))

        queue.recordOutcome(.imported, fixupAttempts: 0)
        queue.recordOutcome(.imported, fixupAttempts: 1)
        queue.recordOutcome(.imported, fixupAttempts: 2)
        queue.recordOutcome(.imported, fixupAttempts: 3)
        queue.recordOutcome(.dropped, fixupAttempts: 0)
        queue.recordOutcome(.needsWasm, fixupAttempts: 0)
        queue.recordOutcome(.needsBundles, fixupAttempts: 0)
        queue.recordOutcome(.failed(.succeeded), fixupAttempts: 0)
        queue.recordOutcome(.failed(.failed(1)), fixupAttempts: 0)
        queue.recordOutcome(.failed(.timedOut), fixupAttempts: 0)
        queue.recordConvergencePattern("a")
        queue.recordConvergencePattern("a")
        queue.recordConvergencePattern("b")

        let stats = queue.statistics
        #expect(stats.numberOfProgramsProcessedSoFar == 10)
        #expect(stats.numberOfProgramsThatWereImport == 4)
        // Imported, dropped and uninteresting programs all executed successfully.
        #expect(stats.numberOfProgramsThatExecutedSuccessfullyDuringImport == 6)
        #expect(stats.numberOfProgramsNotImportedBecauseUninteresting == 1)
        #expect(stats.numberOfProgramsThatFailedDuringImport == 1)
        #expect(stats.numberOfProgramsThatTimedOutDuringImport == 1)
        #expect(stats.numberOfProgramsThatNeededOneFixupAttempt == 1)
        #expect(stats.numberOfProgramsThatNeededTwoFixupAttempts == 1)
        #expect(stats.numberOfProgramsThatNeededThreeFixupAttempts == 1)
        #expect(stats.numberOfProgramsThatNeededFixup == 3)
        #expect(stats.numberOfProgramsRequiringWasmButDisabled == 1)
        #expect(stats.numberOfProgramsRequiringBundlesButDisabled == 1)
        #expect(stats.convergencePatterns == ["a": 2, "b": 1])

        // Dequeueing alone doesn't update the processed counter: programs that are still being
        // processed (e.g. by other instances) must not skew the final statistics.
        _ = queue.next()
        #expect(queue.statistics.numberOfProgramsProcessedSoFar == 10)
    }

    @Test func testInFlightProgramsAreNotCountedAsProcessed() {
        let queue = ThreadSafeImportQueue(makeTestPrograms(count: 2))

        // Two instances dequeue a program each, but only one of them finished processing it.
        _ = queue.next()
        _ = queue.next()
        #expect(queue.isEmpty)
        queue.recordOutcome(.imported, fixupAttempts: 0)

        let stats = queue.statistics
        #expect(stats.numberOfProgramsProcessedSoFar == 1)
        #expect(stats.numberOfProgramsThatExecutedSuccessfullyDuringImport == 1)
    }

    @Test func testConcurrentlyRecordedImportStatistics() {
        let queue = ThreadSafeImportQueue(makeTestPrograms(count: 1))
        let iterations = 1000

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            queue.recordOutcome(.imported, fixupAttempts: i % 2)
            queue.recordConvergencePattern("pattern")
        }

        let stats = queue.statistics
        #expect(stats.numberOfProgramsThatWereImport == iterations)
        #expect(stats.numberOfProgramsThatNeededOneFixupAttempt == iterations / 2)
        #expect(stats.convergencePatterns["pattern"] == iterations)
    }

    @Test func testFuzzerScheduleCorpusImportWithQueue() {
        let fuzzer = makeMockFuzzer(initialize: false)
        fuzzer.sync {
            let p0 = makeTestProgram(intVal: 42)
            let queue = ThreadSafeImportQueue([p0])

            #expect(fuzzer.state == .uninitialized)
            fuzzer.scheduleCorpusImport(queue, importMode: .full)
            #expect(fuzzer.state == .corpusImport)
            #expect(fuzzer.corpusImportProgress() == 0.0)
            #expect(fuzzer.currentImportQueue === queue)
        }
    }

    @Test func testSharedQueueFinalImportStats() {
        let config = Configuration(logLevel: .info)
        let fuzzer = makeMockFuzzer(
            config: config, queue: DispatchQueue(label: "test.fuzzer.stats"), initialize: false)
        let programs = makeTestPrograms(count: 4)
        let queue = ThreadSafeImportQueue(programs)
        let done = DispatchSemaphore(value: 0)

        var infoMessages = [String]()
        var warningMessages = [String]()

        fuzzer.sync {
            fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
                if ev.level == .info {
                    infoMessages.append(ev.message)
                } else if ev.level == .warning {
                    warningMessages.append(ev.message)
                }
            }
            fuzzer.registerEventListener(for: fuzzer.events.CorpusImportComplete) {
                fuzzer.shutdown(reason: .finished)
                done.signal()
            }

            fuzzer.scheduleCorpusImport(queue, importMode: .full)
            fuzzer.initialize()

            // Simulate other workers importing 3 of the 4 programs from the shared queue.
            for _ in 0..<3 {
                _ = queue.next()
                queue.recordOutcome(.imported, fixupAttempts: 0)
            }
            #expect(queue.count == 1)

            fuzzer.start()
        }

        done.wait()

        // The import statistics are shared by all instances consuming from the same queue, so the
        // final summary reports the totals of all of them.
        // Note: This uses the value-returning sync overload, since the Void overload doesn't execute
        // the block anymore once the fuzzer was shut down.
        let (info, warnings) = fuzzer.sync { (infoMessages, warningMessages) }
        #expect(info.contains("Corpus import finished:"))
        #expect(info.contains("4/4 programs executed successfully"))
        #expect(!warnings.contains(where: { $0.contains("of imported programs failed to") }))
    }

    @Test func testSharedQueueDepletedBeforeWorkerStarts() {
        let config = Configuration(logLevel: .info)
        let fuzzer = makeMockFuzzer(
            config: config, queue: DispatchQueue(label: "test.fuzzer.depleted"), initialize: false)
        let programs = makeTestPrograms(count: 2)
        let queue = ThreadSafeImportQueue(programs)
        let done = DispatchSemaphore(value: 0)

        var infoMessages = [String]()
        var warningMessages = [String]()

        fuzzer.sync {
            fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
                if ev.level == .info {
                    infoMessages.append(ev.message)
                } else if ev.level == .warning {
                    warningMessages.append(ev.message)
                }
            }
            fuzzer.registerEventListener(for: fuzzer.events.CorpusImportComplete) {
                fuzzer.shutdown(reason: .finished)
                done.signal()
            }

            fuzzer.scheduleCorpusImport(queue, importMode: .full)
            fuzzer.initialize()

            // Simulate other workers importing the entire queue before this worker processes any program.
            for _ in 0..<2 {
                _ = queue.next()
                queue.recordOutcome(.imported, fixupAttempts: 0)
            }
            #expect(queue.isEmpty)

            fuzzer.start()
        }

        done.wait()

        // Even though this instance didn't import any program itself, it reports the shared totals.
        // Note: This uses the value-returning sync overload, since the Void overload doesn't execute
        // the block anymore once the fuzzer was shut down.
        let (info, warnings) = fuzzer.sync { (infoMessages, warningMessages) }
        #expect(info.contains("Corpus import finished:"))
        #expect(info.contains("2/2 programs executed successfully"))
        #expect(!warnings.contains(where: { $0.contains("of imported programs failed to") }))
    }
}
