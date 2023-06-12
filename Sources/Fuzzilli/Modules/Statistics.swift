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

public class Statistics: Module {
    /// The data just for this instance.
    private var ownData = Fuzzilli_Protobuf_Statistics()

    /// Logger used to print some internal statistics in regular intervals.
    private let logger = Logger(withLabel: "Statistics")

    /// Data required to compute executions per second.
    private var currentExecs = 0.0
    private var lastEpsUpdate = Date()
    private var lastExecsPerSecond = 0.0

    /// Data required to compute the fuzzer overhead (i.e. the fraction of the total time that is not spent executing generated programs in the target engine).
    /// This includes time required for node synchronization, to mutate/generate a program, to lift it, to restart the target process after crashes/timeouts, etc.
    private var fuzzerOverheadAvg = MovingAverage(n: 1000)
    private var lastPreExecDate = Date()
    private var lastExecDate = Date()

    /// Data required to compute the minimization overhead (i.e. the fraction of executions spent on minimization).
    /// Since we may easily spent hundreds of executions on a single minimization task, the context window here is larger than the other ones.
    private var minimizationOverheadAvg = MovingAverage(n: 10000)

    /// Current corpus size. Updated when new samples are added to the corpus.
    private var corpusSize = 0

    /// Moving average to keep track of average program size.
    private var programSizeAvg = MovingAverage(n: 1000)

    /// Moving average to keep track of average program size in the corpus.
    /// Only computed locally, not across multiple nodes.
    private var corpusProgramSizeAvg = MovingAverage(n: 1000)

    /// Moving average to keep track of the average execution time of recently generated programs.
    /// This is only computed for successful executions, and so excludes e.g. samples that timed out.
    private var executionTimeAvg = MovingAverage(n: 1000)

    /// Moving average of the number of valid programs in the last 1000 generated programs.
    private var correctnessRate = MovingAverage(n: 1000)

    /// Moving average of the number of timeouts in the last 1000 generated programs.
    private var timeoutRate = MovingAverage(n: 1000)

    /// All data from connected nodes.
    private var nodes = [UUID: Fuzzilli_Protobuf_Statistics]()

    /// The IDs of nodes that are currently inactive.
    private var inactiveNodes = Set<UUID>()

    public init() {}

    /// Computes and returns the statistical data for this instance and all connected nodes.
    public func compute() -> Fuzzilli_Protobuf_Statistics {
        assert(nodes.count - inactiveNodes.count == ownData.numChildNodes)

        // Compute local statistics data
        ownData.avgCorpusSize = Double(corpusSize)
        ownData.avgProgramSize = programSizeAvg.currentValue
        ownData.avgCorpusProgramSize = corpusProgramSizeAvg.currentValue
        ownData.avgExecutionTime = executionTimeAvg.currentValue
        ownData.fuzzerOverhead = fuzzerOverheadAvg.currentValue
        ownData.minimizationOverhead = minimizationOverheadAvg.currentValue
        ownData.correctnessRate = correctnessRate.currentValue
        ownData.timeoutRate = timeoutRate.currentValue

        // Compute global statistics data
        var data = ownData

        for (id, node) in nodes {
            // Add "global" fields, even from nodes that are no longer active
            data.totalSamples += node.totalSamples
            data.validSamples += node.validSamples
            data.timedOutSamples += node.timedOutSamples
            data.totalExecs += node.totalExecs

            if !inactiveNodes.contains(id) {
                // Add fields that only have meaning for active nodes

                // For computing averages, we first multiply each average value with the number of nodes over which
                // it was computed, then divide it by the total number of active nodes.
                let numNodesRepresentedByData = Double(node.numChildNodes + 1)

                data.numChildNodes += node.numChildNodes
                data.avgCorpusSize += node.avgCorpusSize * numNodesRepresentedByData
                data.avgProgramSize += node.avgProgramSize * numNodesRepresentedByData
                data.avgCorpusProgramSize += node.avgCorpusProgramSize * numNodesRepresentedByData
                data.avgExecutionTime += node.avgExecutionTime * numNodesRepresentedByData
                data.execsPerSecond += node.execsPerSecond
                data.fuzzerOverhead += node.fuzzerOverhead * numNodesRepresentedByData
                data.minimizationOverhead += node.minimizationOverhead * numNodesRepresentedByData
                data.correctnessRate += node.correctnessRate * numNodesRepresentedByData
                data.timeoutRate += node.timeoutRate * numNodesRepresentedByData
            }

            // All other fields are already indirectly synchronized (e.g. number of interesting samples founds)
        }

        // Divide each average by the toal number of nodes. See above.
        let totalNumberOfNodes = Double(data.numChildNodes + 1)
        data.avgCorpusSize /= totalNumberOfNodes
        data.avgProgramSize /= totalNumberOfNodes
        data.avgCorpusProgramSize /= totalNumberOfNodes
        data.avgExecutionTime /= totalNumberOfNodes
        data.fuzzerOverhead /= totalNumberOfNodes
        data.minimizationOverhead /= totalNumberOfNodes
        data.correctnessRate /= totalNumberOfNodes
        data.timeoutRate /= totalNumberOfNodes

        return data
    }

    public func initialize(with fuzzer: Fuzzer) {
        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { _ in
            self.ownData.crashingSamples += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.TimeOutFound) { _ in
            self.ownData.timedOutSamples += 1
            self.correctnessRate.add(0.0)
            self.timeoutRate.add(1.0)
        }
        fuzzer.registerEventListener(for: fuzzer.events.InvalidProgramFound) { _ in
            self.correctnessRate.add(0.0)
            self.timeoutRate.add(0.0)
        }
        fuzzer.registerEventListener(for: fuzzer.events.ValidProgramFound) { _ in
            self.ownData.validSamples += 1
            self.correctnessRate.add(1.0)
            self.timeoutRate.add(0.0)
        }
        fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { (program, purpose) in
            // Currently we only care about the fraction of executions spent on
            // minimization, but we could extend this to get a detailed breakdown
            // of exactly what our executions are spent on.
            if purpose == .minimization {
                self.minimizationOverheadAvg.add(1)
            } else {
                self.minimizationOverheadAvg.add(0)
            }
        }
        fuzzer.registerEventListener(for: fuzzer.events.PostExecute) { exec in
            self.ownData.totalExecs += 1
            self.currentExecs += 1

            if exec.outcome == .succeeded {
                self.executionTimeAvg.add(exec.execTime)
            }

            let now = Date()
            let totalTime = now.timeIntervalSince(self.lastExecDate)
            self.lastExecDate = now

            let overhead = 1.0 - (exec.execTime / totalTime)
            self.fuzzerOverheadAvg.add(overhead)
        }
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            self.ownData.interestingSamples += 1
            self.ownData.coverage = fuzzer.evaluator.currentScore
            self.corpusProgramSizeAvg.add(ev.program.size)
            self.corpusSize = fuzzer.corpus.size
        }
        fuzzer.registerEventListener(for: fuzzer.events.ProgramGenerated) { program in
            self.ownData.totalSamples += 1
            self.programSizeAvg.add(program.size)
        }
        fuzzer.registerEventListener(for: fuzzer.events.ChildNodeConnected) { id in
            self.ownData.numChildNodes += 1
            self.nodes[id] = Fuzzilli_Protobuf_Statistics()
            self.inactiveNodes.remove(id)
        }
        fuzzer.registerEventListener(for: fuzzer.events.ChildNodeDisconnected) { id in
            self.ownData.numChildNodes -= 1
            self.inactiveNodes.insert(id)
        }
        fuzzer.timers.scheduleTask(every: 30 * Seconds) {
            let now = Date()
            let interval = Double(now.timeIntervalSince(self.lastEpsUpdate))
            guard interval >= 1.0 else {
                return // This can happen due to delays in queue processing
            }

            let execsPerSecond = self.currentExecs / interval
            self.ownData.execsPerSecond += execsPerSecond - self.lastExecsPerSecond
            self.lastExecsPerSecond = execsPerSecond

            self.lastEpsUpdate = now
            self.currentExecs = 0.0
        }

        // Also schedule timers to print internal statistics in regular intervals.
        if fuzzer.config.logLevel.isAtLeast(.info) {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                self.logger.info("Mutator Statistics:")
                let nameMaxLength = fuzzer.mutators.map({ $0.name.count }).max()!
                let maxSamplesGeneratedStringLength = fuzzer.mutators.map({ String($0.totalSamples).count }).max()!
                for mutator in fuzzer.mutators {
                    let name = mutator.name.rightPadded(toLength: nameMaxLength)
                    let correctnessRate = String(format: "%.2f%%", mutator.correctnessRate * 100).leftPadded(toLength: 7)
                    let failureRate = String(format: "%.2f%%", mutator.failureRate * 100).leftPadded(toLength: 7)
                    let timeoutRate = String(format: "%.2f%%", mutator.timeoutRate * 100).leftPadded(toLength: 6)
                    let interestingSamplesRate = String(format: "%.2f%%", mutator.interestingSamplesRate * 100).leftPadded(toLength: 7)
                    let avgInstructionsAdded = String(format: "%.2f", mutator.avgNumberOfInstructionsGenerated).leftPadded(toLength: 5)
                    let samplesGenerated = String(mutator.totalSamples).leftPadded(toLength: maxSamplesGeneratedStringLength)
                    let crashesFound = mutator.crashesFound
                    self.logger.info("    \(name) : Correctness rate: \(correctnessRate), Failure rate: \(failureRate), Interesting sample rate: \(interestingSamplesRate), Timeout rate: \(timeoutRate), Avg. # of instructions added: \(avgInstructionsAdded), Total # of generated samples: \(samplesGenerated), Total # of crashes found: \(crashesFound)")
                }
            }

        }
        if fuzzer.config.logLevel.isAtLeast(.verbose) {
            fuzzer.timers.scheduleTask(every: 30 * Minutes) {
                self.logger.verbose("Code Generator Statistics:")
                let nameMaxLength = fuzzer.codeGenerators.map({ $0.name.count }).max()!
                for generator in fuzzer.codeGenerators {
                    let name = generator.name.rightPadded(toLength: nameMaxLength)
                    let correctnessRate = String(format: "%.2f%%", generator.correctnessRate * 100).leftPadded(toLength: 7)
                    let interestingSamplesRate = String(format: "%.2f%%", generator.interestingSamplesRate * 100).leftPadded(toLength: 7)
                    let timeoutRate = String(format: "%.2f%%", generator.timeoutRate * 100).leftPadded(toLength: 6)
                    let avgInstructionsAdded = String(format: "%.2f", generator.avgNumberOfInstructionsGenerated).leftPadded(toLength: 5)
                    let samplesGenerated = generator.totalSamples
                    self.logger.verbose("    \(name) : Correctness rate: \(correctnessRate), Interesting sample rate: \(interestingSamplesRate), Timeout rate: \(timeoutRate), Avg. # of instructions added: \(avgInstructionsAdded), Total # of generated samples: \(samplesGenerated)")
                }
            }
        }
    }

    /// Import statistics data from a child node.
    public func importData(_ stats: Fuzzilli_Protobuf_Statistics, from child: UUID) {
        nodes[child] = stats
    }
}

extension Fuzzilli_Protobuf_Statistics {
    /// The ratio of valid samples to produced samples over the entire runtime of the fuzzer.
    public var overallCorrectnessRate: Double {
        return Double(validSamples) / Double(totalSamples)
    }

    /// The ratio of timed-out samples to produced samples over the entire runtime of the fuzzer.
    public var overallTimeoutRate: Double {
        return Double(timedOutSamples) / Double(totalSamples)
    }
}
