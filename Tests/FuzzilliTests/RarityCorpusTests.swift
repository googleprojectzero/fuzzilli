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

@Suite struct RarityCorpusTests {
    private func makeProgram(for fuzzer: Fuzzer, intVal: Int64) -> Program {
        let b = fuzzer.makeBuilder()
        b.loadInt(intVal)
        return b.finalize()
    }

    private func makeProgramOfSize(for fuzzer: Fuzzer, count: Int) -> Program {
        let b = fuzzer.makeBuilder()
        for i in 0..<count {
            b.loadInt(Int64(i))
        }
        return b.finalize()
    }

    private func makeCorpus(
        ageExponent: Double = 1.5,
        sizeExponent: Double = 2.0,
        rarityExponent: Double = 3.0,
        rareEdgeLimit: Int = 8,
        splicingPoolSize: Int = 3,
        splicingAgeIncrement: Double = 0.2
    ) -> RarityCorpus {
        return RarityCorpus(
            ageExponent: ageExponent,
            sizeExponent: sizeExponent,
            rarityExponent: rarityExponent,
            rareEdgeLimit: rareEdgeLimit,
            splicingPoolSize: splicingPoolSize,
            splicingAgeIncrement: splicingAgeIncrement,
            covEvaluator: ProgramCoverageEvaluator(runner: MockScriptRunner())
        )
    }

    @Test func testDynamicSharedBitRarityCalculation() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Seed A covers edges [10, 20]. Since it's the only seed covering them:
            // Rarity(A) = 1/1 + 1/1 = 2.0
            let progA = makeProgram(for: fuzzer, intVal: 1)
            corpus.addInternal(progA, allDeterministicEdges: [10, 20])

            #expect(corpus.size == 1)
            #expect(corpus.seedRarity(at: 0) == 2.0)
            #expect(corpus.seedEnergy(at: 0) == 2.0)

            // Seed B covers edges [10, 20, 30].
            // Shared edges 10 and 20 now have seenCount = 2 (1 / 2^3 = 0.125 each); frontier edge 30 has seenCount = 1.
            // Rarity(A) drops to 0.125 + 0.125 = 0.25
            // Rarity(B) is 0.125 + 0.125 + 1.0 = 1.25
            let progB = makeProgram(for: fuzzer, intVal: 2)
            corpus.addInternal(progB, allDeterministicEdges: [10, 20, 30])

            #expect(corpus.size == 2)
            #expect(corpus.edgeCount(for: 10) == 2)
            #expect(corpus.edgeCount(for: 20) == 2)
            #expect(corpus.edgeCount(for: 30) == 1)

            #expect(corpus.seedRarity(at: 0) == 0.25)
            #expect(corpus.seedRarity(at: 1) == 1.25)
        }
    }

    @Test func testMutationAgeDecay() {
        let corpus = makeCorpus(ageExponent: 2.0)
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            let prog = makeProgram(for: fuzzer, intVal: 42)
            corpus.addInternal(prog, allDeterministicEdges: [100, 200])

            // Initial energy: Rarity 2.0 / (age 0 + 1)^2 = 2.0
            #expect(corpus.seedEnergy(at: 0) == 2.0)

            let _ = corpus.randomElementForMutating()
            #expect(corpus.seedAge(at: 0) == 1)
            // Energy after 1 mutation: 2.0 / (1 + 1)^2 = 0.5
            #expect(corpus.seedEnergy(at: 0) == 0.5)

            let _ = corpus.randomElementForMutating()
            let _ = corpus.randomElementForMutating()
            #expect(corpus.seedAge(at: 0) == 3)
            // Energy after 3 mutations: 2.0 / (3 + 1)^2 = 0.125
            #expect(corpus.seedEnergy(at: 0) == 0.125)
        }
    }

    @Test func testProgramSizeLogPenaltyInEnergy() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Seed 0: 1 instruction (1 + ln(1)^2 = 1.0), unique edge [10] -> Rarity = 1.0, Energy = 1.0
            let prog1 = makeProgramOfSize(for: fuzzer, count: 1)
            corpus.addInternal(prog1, allDeterministicEdges: [10])

            // Seed 1: 10 instructions (1 + ln(10)^2), unique edge [20] -> Rarity = 1.0
            let prog10 = makeProgramOfSize(for: fuzzer, count: 10)
            corpus.addInternal(prog10, allDeterministicEdges: [20])

            #expect(prog1.size == 1)
            #expect(prog10.size == 10)
            #expect(corpus.seedRarity(at: 0) == 1.0)
            #expect(corpus.seedRarity(at: 1) == 1.0)

            let expectedEnergy10 = 1.0 / (1.0 + Foundation.pow(Foundation.log(10.0), 2.0))
            #expect(abs(corpus.seedEnergy(at: 0) - 1.0) < 1e-9)
            #expect(abs(corpus.seedEnergy(at: 1) - expectedEnergy10) < 1e-9)
            #expect(corpus.seedEnergy(at: 0) > corpus.seedEnergy(at: 1))
        }
    }

    @Test func testSaturatedEdgesDropToStrictZeroRarity() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Add 8 seeds covering edge [500]. Once 8 seeds have executed edge 500,
            // edgeSeenCount[500] reaches maxRareEdgeCount (8) and its rarity drops to strict 0.0!
            for i in 0..<8 {
                corpus.addInternal(
                    makeProgram(for: fuzzer, intVal: Int64(i)), allDeterministicEdges: [500])
                if i < 7 {
                    #expect(corpus.seedRarity(at: 0) > 0.0)
                }
            }

            for i in 0..<8 {
                #expect(corpus.seedRarity(at: i) == 0.0)
                #expect(corpus.seedEnergy(at: i) == 0.0)
            }

            // With no seed left with positive energy, mutation falls back to uniform random
            // selection and no seed is evicted, so that the corpus never becomes empty.
            let _ = corpus.randomElementForMutating()
            #expect(corpus.size == 8)

            // Add a 9th seed with unique edge [501] (rarity = 1.0).
            let rareProg = makeProgram(for: fuzzer, intVal: 999)
            corpus.addInternal(rareProg, allDeterministicEdges: [501])
            #expect(corpus.seedRarity(at: 8) == 1.0)

            let picked = corpus.randomElementForMutating()
            #expect(picked == rareProg)
            // The 8 saturated seeds can never be scheduled again, so they were evicted from RAM.
            #expect(corpus.size == 1)
            #expect(corpus.allPrograms() == [rareProg])
        }
    }

    @Test func testCrashEdgesImmediatelyDecreaseParentRarity() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Parent seed covers rare setup edge [777].
            let parent = makeProgram(for: fuzzer, intVal: 15)
            corpus.addInternal(parent, allDeterministicEdges: [777])

            #expect(corpus.size == 1)
            #expect(corpus.seedRarity(at: 0) == 1.0)
            #expect(corpus.edgeCount(for: 777) == 1)

            corpus.recordCrashEdges([777, 888])
            #expect(corpus.size == 1)
            #expect(corpus.seedRarity(at: 0) == 0.125)
            #expect(corpus.edgeCount(for: 777) == 2)

            corpus.recordCrashEdges([777, 888])
            #expect(abs(corpus.seedRarity(at: 0) - (1.0 / 27.0)) < 1e-9)
            #expect(corpus.edgeCount(for: 777) == 3)

            for _ in 0..<5 {
                corpus.recordCrashEdges([777, 888])
            }
            #expect(corpus.seedRarity(at: 0) == 0.0)
            #expect(corpus.seedEnergy(at: 0) == 0.0)
        }
    }

    @Test func testDeterministicEdgesCapPreservesAspects() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            let deterministicShared = Array(UInt32(1000)..<UInt32(1200))

            let prog0 = makeProgram(for: fuzzer, intVal: 1)
            corpus.addInternal(prog0, allDeterministicEdges: deterministicShared)

            let prog = makeProgram(for: fuzzer, intVal: 7)
            let newEdges: [UInt32] = [1, 2, 3, 4, 5]
            corpus.addInternal(prog, allDeterministicEdges: deterministicShared + newEdges)

            #expect(corpus.size == 2)

            for aspectEdge in newEdges {
                #expect(corpus.edgeCount(for: aspectEdge) == 1)
            }
            // 5 new edges (rarity 1.0 each) + 123 shared edges (count = 2, rarity 0.125 each) = 5.0 + 15.375 = 20.375
            #expect(corpus.seedRarity(at: 1) == 20.375)
        }
    }

    @Test func testProvidedDeterministicEdgesSkipExtraExecutions() {
        let corpus = makeCorpus()
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            var executions = 0
            fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { _ in executions += 1 }

            let prog = makeProgram(for: fuzzer, intVal: 7)
            corpus.addInternal(prog, allDeterministicEdges: [1, 2, 3, 4])

            #expect(corpus.size == 1)
            #expect(executions == 0)
            for edge: UInt32 in [1, 2, 3, 4] {
                #expect(corpus.edgeCount(for: edge) == 1)
            }
            #expect(corpus.seedRarity(at: 0) == 4.0)
        }
    }

    @Test func testSplicingAgesDonorFractionally() {
        let corpus = makeCorpus(ageExponent: 2.0, splicingAgeIncrement: 0.2)
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            let prog = makeProgram(for: fuzzer, intVal: 42)
            corpus.addInternal(prog, allDeterministicEdges: [100, 200])

            // Each selection as a splicing donor adds 0.2 to the age.
            #expect(corpus.randomElementForSplicing() == prog)
            #expect(corpus.seedAge(at: 0) == 0.2)
            // Energy: 2.0 / (0.2 + 1)^2
            #expect(abs(corpus.seedEnergy(at: 0) - 2.0 / 1.44) < 1e-9)

            #expect(corpus.randomElementForSplicing() == prog)
            #expect(abs(corpus.seedAge(at: 0) - 0.4) < 1e-9)

            // A mutation round adds 1.0 on top of the splicing age: 2.0 / (1.4 + 1)^2
            let _ = corpus.randomElementForMutating()
            #expect(abs(corpus.seedAge(at: 0) - 1.4) < 1e-9)
            #expect(abs(corpus.seedEnergy(at: 0) - 2.0 / (2.4 * 2.4)) < 1e-9)
        }
    }

    @Test func testFastStateSynchronizationPreservesRarityAndCounts() throws {
        let parentCorpus = makeCorpus(splicingAgeIncrement: 0.2)
        let parentFuzzer = makeMockFuzzer(corpus: parentCorpus)

        let childCorpus = makeCorpus()
        let childFuzzer = makeMockFuzzer(corpus: childCorpus)

        try parentFuzzer.sync {
            let progA = makeProgram(for: parentFuzzer, intVal: 1)
            let progB = makeProgram(for: parentFuzzer, intVal: 2)
            parentCorpus.addInternal(progA, allDeterministicEdges: [10, 20])
            parentCorpus.addInternal(progB, allDeterministicEdges: [20, 30])
            let _ = parentCorpus.randomElementForMutating()
            parentCorpus.recordCrashEdges([30])
            // progA now has the highest energy, so it is the splicing donor and gets a fractional age.
            #expect(parentCorpus.randomElementForSplicing() == progA)
            #expect(parentCorpus.seedAge(at: 0) == 0.2)

            let stateData = try parentCorpus.exportState()

            try childFuzzer.sync {
                try childCorpus.importState(stateData)

                #expect(childCorpus.size == 2)
                #expect(childCorpus.edgeCount(for: 10) == 1)
                #expect(childCorpus.edgeCount(for: 20) == 2)
                #expect(childCorpus.edgeCount(for: 30) == 2)
                #expect(childCorpus.seedRarity(at: 0) == parentCorpus.seedRarity(at: 0))
                #expect(childCorpus.seedRarity(at: 1) == parentCorpus.seedRarity(at: 1))
                #expect(childCorpus.seedAge(at: 0) == parentCorpus.seedAge(at: 0))
                #expect(childCorpus.seedAge(at: 1) == parentCorpus.seedAge(at: 1))
                #expect(childCorpus.seedEnergy(at: 0) == parentCorpus.seedEnergy(at: 0))
                #expect(childCorpus.seedEnergy(at: 1) == parentCorpus.seedEnergy(at: 1))
            }
        }
    }

    @Test func testHeapEntryTieBreakingByAgeSizeAndIndex() {
        let corpus = makeCorpus(ageExponent: 2.0)
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Seed 0 covers 4 unique edges [10, 11, 12, 13] (size 1, rarity = 4.0, initial energy = 4.0)
            let prog0 = makeProgram(for: fuzzer, intVal: 100)
            corpus.addInternal(prog0, allDeterministicEdges: [10, 11, 12, 13])

            // Seed 1 covers 1 unique edge [20] (size 1, rarity = 1.0, initial energy = 1.0)
            let prog1 = makeProgram(for: fuzzer, intVal: 200)
            corpus.addInternal(prog1, allDeterministicEdges: [20])

            // 1st mutation picks Seed 0 (energy = 4.0), ageing it to age = 1 (new energy = 4.0 / (1 + 1)^2 = 1.0)
            let firstPick = corpus.randomElementForMutating()
            #expect(firstPick == prog0)
            #expect(corpus.seedAge(at: 0) == 1)
            #expect(corpus.seedEnergy(at: 0) == 1.0)
            #expect(corpus.seedEnergy(at: 1) == 1.0)

            // Now both Seed 0 (index 0, age 1) and Seed 1 (index 1, age 0) have exact energy = 1.0!
            // With age tie-breaking, Seed 1 (age 0) must be picked before Seed 0 (age 1) despite higher index.
            let secondPick = corpus.randomElementForMutating()
            #expect(secondPick == prog1)
        }
    }

    @Test func testSplicingSelectsNonZeroEnergySeedsAndFavorsHighEnergy() {
        let corpus = makeCorpus(splicingPoolSize: 20)
        let fuzzer = makeMockFuzzer(corpus: corpus)

        fuzzer.sync {
            // Saturate edge [0] across 100 seeds (>= rareEdgeLimit = 8) so all 100 have 0.0 energy.
            for i in 0..<100 {
                corpus.addInternal(
                    makeProgram(for: fuzzer, intVal: Int64(i)), allDeterministicEdges: [0])
            }

            // Add 20 non-zero-energy seeds with energies 1.0, 2.0, ..., 20.0.
            var nextUniqueEdge: UInt32 = 1
            var maxProg: Program!
            for k in 1...20 {
                let edges = Array(nextUniqueEdge..<(nextUniqueEdge + UInt32(k)))
                nextUniqueEdge += UInt32(k)
                let prog = makeProgram(for: fuzzer, intVal: Int64(1000 + k))
                corpus.addInternal(prog, allDeterministicEdges: edges)
                if k == 20 {
                    maxProg = prog
                }
            }

            // Since `randomSample(count: 20)` draws 20 distinct non-zero-energy seeds without
            // replacement, when there are 20 non-zero-energy seeds it deterministically includes
            // all 20 of them and `.max()` always returns `maxProg`.
            for _ in 0..<20 {
                #expect(corpus.randomElementForSplicing() == maxProg)
            }
        }
    }
}
