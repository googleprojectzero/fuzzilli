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

        var job = Fuzzer.CorpusImportJob(queue: queue, mode: .full)
        #expect(job.totalNumberOfProgramsToImport == 2)
        #expect(job.isFinished == false)
        #expect(job.progress() == 0.0)

        let first = job.nextProgram()
        #expect(first == p1)
        #expect(job.numberOfProgramsProcessedSoFar == 1)
        #expect(job.progress() == 0.5)
        #expect(job.isFinished == false)

        let second = job.nextProgram()
        #expect(second == p0)
        #expect(job.numberOfProgramsProcessedSoFar == 2)
        #expect(job.progress() == 1.0)
        #expect(job.isFinished == true)

        // Dequeueing on a depleted job must safely return nil without incrementing counter
        let third = job.nextProgram()
        #expect(third == nil)
        #expect(job.numberOfProgramsProcessedSoFar == 2)
        #expect(job.isFinished == true)
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
}
