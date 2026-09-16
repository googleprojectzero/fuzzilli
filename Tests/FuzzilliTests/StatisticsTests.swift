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

@Suite struct StatisticsTests {
    @Test func testStatisticsAggregation() {
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig)

        fuzzer.sync {
            let stats = Statistics()
            stats.initialize(with: fuzzer)

            let mutatorsList = Array(fuzzer.mutators)
            #expect(mutatorsList.count > 0)
            // Add some samples to the first mutator statistic.
            let mutator = mutatorsList.first!
            mutator.invoked()
            mutator.addedInstructions(10)
            mutator.generatedValidSample()
            mutator.generatedInterestingSample()
            mutator.generatedCrashingSample()
            mutator.failedToGenerate()

            // Verify local data.
            let ownData = stats.compute()
            let ownMutatorStats = ownData.contributorStats.first(where: { $0.name == mutator.name })
            #expect(ownMutatorStats != nil)
            #expect(ownMutatorStats?.invocationCount == 1)
            #expect(ownMutatorStats?.totalInstructionsProduced == 10)
            #expect(ownMutatorStats?.crashingSamples == 1)
            #expect(ownMutatorStats?.failures == 1)

            // Simulate importing data from another process.
            let childNodeUUID = UUID()
            fuzzer.dispatchEvent(fuzzer.events.ChildNodeConnected, data: childNodeUUID)

            let childStats = Fuzzilli_Protobuf_Statistics.with {
                $0.contributorStats = [
                    Fuzzilli_Protobuf_Statistics.ContributorStats.with {
                        $0.name = mutator.name
                        $0.invocationCount = 2
                        $0.totalInstructionsProduced = 5
                        $0.crashingSamples = 2
                        $0.failures = 0
                        $0.totalSamples = 3
                        $0.correctSamples = 3
                        $0.isCodeGenerator = false
                    }
                ]
            }
            stats.importData(childStats, from: childNodeUUID)

            // Compute aggregated global stats.
            let globalData = stats.compute()
            let globalMutatorStats = globalData.contributorStats.first(where: {
                $0.name == mutator.name
            })

            #expect(globalMutatorStats != nil)
            // Aggregated: 1 (own) + 2 (child) = 3
            #expect(globalMutatorStats?.invocationCount == 3)
            // Aggregated instructions: 10 (own) + 5 (child) = 15
            #expect(globalMutatorStats?.totalInstructionsProduced == 15)
            // Aggregated crashes: 1 (own) + 2 (child) = 3
            #expect(globalMutatorStats?.crashingSamples == 3)
            // Aggregated failures: 1 (own) + 0 (child) = 1
            #expect(globalMutatorStats?.failures == 1)

            // Test the extension computed helper properties on the aggregated stats
            // 15 instructions / 6 totalSamples (3 own + 3 child)
            #expect(globalMutatorStats?.avgNumberOfInstructionsGenerated == 15.0 / 6.0)
            // 5 correctSamples / 6 totalSamples
            #expect(globalMutatorStats?.correctnessRate == 5.0 / 6.0)
        }
    }

    @Test func testCorpusImportUninterestingCounter() {
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig)

        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let prog = b.finalize()
            var job = Fuzzer.CorpusImportJob(
                corpus: [prog], mode: .interestingOnly(shouldMinimize: false))

            #expect(job.numberOfProgramsNotImportedBecauseUninteresting == 0)
            #expect(job.numberOfProgramsThatExecutedSuccessfullyDuringImport == 0)

            // Test failed with succeeded outcome (uninteresting)
            job.notifyImportOutcome(.failed(.succeeded), fixupAttempts: 0)
            #expect(job.numberOfProgramsNotImportedBecauseUninteresting == 1)
            #expect(job.numberOfProgramsThatExecutedSuccessfullyDuringImport == 1)

            // Test other outcomes (should not increment the uninteresting counter)
            job.notifyImportOutcome(.imported, fixupAttempts: 0)
            #expect(job.numberOfProgramsNotImportedBecauseUninteresting == 1)
            #expect(job.numberOfProgramsThatExecutedSuccessfullyDuringImport == 2)

            job.notifyImportOutcome(.dropped, fixupAttempts: 0)
            #expect(job.numberOfProgramsNotImportedBecauseUninteresting == 1)
            #expect(job.numberOfProgramsThatExecutedSuccessfullyDuringImport == 3)

            job.notifyImportOutcome(.failed(.failed(1)), fixupAttempts: 0)
            #expect(job.numberOfProgramsNotImportedBecauseUninteresting == 1)
            #expect(job.numberOfProgramsThatExecutedSuccessfullyDuringImport == 3)
        }
    }
}
