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

import Foundation
import Testing

@testable import Fuzzilli

@Suite struct ExecutionPurposeStatisticsTests {
    @Test func testPickOverlap() {
        let stats = ExecutionPurposeStatistics()
        let program = Program(isBundle: false)
        let (a, b) = (UUID(), UUID())
        let start = Date()
        let window = ExecutionPurposeStatistics.pickOverlapWindow

        // A, then A again: same instance, no overlap.
        stats.recordMutationPick(of: program, by: a, at: start)
        stats.recordMutationPick(of: program, by: a, at: start + 1)
        #expect(stats.pickCounts.overlapping == 0)
        // B within the window of A: overlap.
        stats.recordMutationPick(of: program, by: b, at: start + 2)
        #expect(stats.pickCounts.overlapping == 1)
        // B again: still within the window of A's last pick.
        stats.recordMutationPick(of: program, by: b, at: start + 3)
        #expect(stats.pickCounts.overlapping == 2)
        // A after the window of B's last pick: no overlap.
        stats.recordMutationPick(of: program, by: a, at: start + 4 + window)
        #expect(stats.pickCounts == (picks: 5, overlapping: 2))
    }

    @Test func testDropOldPicks() {
        let stats = ExecutionPurposeStatistics()
        let program = Program(isBundle: false)
        let start = Date()
        stats.recordMutationPick(of: program, by: UUID(), at: start)
        stats.dropOldPicks(now: start + ExecutionPurposeStatistics.pickOverlapWindow + 1)
        // The first pick was forgotten, so this one does not overlap.
        stats.recordMutationPick(of: program, by: UUID(), at: start + 2)
        #expect(stats.pickCounts == (picks: 2, overlapping: 0))
    }

    @Test func testCountsByPurpose() {
        let mainFuzzer = makeMockFuzzer()
        let workerFuzzer = makeMockFuzzer()
        let main = ExecutionPurposeStatistics()
        let worker = ExecutionPurposeStatistics(addingTo: main)
        mainFuzzer.sync {
            main.initialize(with: mainFuzzer)
            let program = mainFuzzer.makeBuilder().finalize()
            _ = mainFuzzer.execute(program, purpose: .fuzzing)
            _ = mainFuzzer.execute(program, purpose: .minimization)
        }
        workerFuzzer.sync {
            worker.initialize(with: workerFuzzer)
            let program = workerFuzzer.makeBuilder().finalize()
            _ = workerFuzzer.execute(program, purpose: .fuzzing)
        }
        // The worker adds to the counters of the main instance.
        let totals = main.totals
        #expect(totals.count == 2)
        #expect(totals[.fuzzing]?.count == 2)
        #expect(totals[.minimization]?.count == 1)
        let fuzzingTime = totals[.fuzzing]?.time ?? 0
        let minimizationTime = totals[.minimization]?.time ?? 0
        #expect(fuzzingTime > 0)
        #expect(abs(fuzzingTime - 2 * minimizationTime) < 1e-9)
    }
}
