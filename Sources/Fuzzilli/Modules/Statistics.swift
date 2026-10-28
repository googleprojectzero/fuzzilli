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
    /// The fuzzer instance this module belongs to.
    private var fuzzer: Fuzzer?

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

    /// Number of programs received from other instances (including initial synchronization).
    private var instanceImportedProgramsReceived: UInt64 = 0

    /// Number of programs from other instances that were accepted into the corpus.
    private var instanceImportedProgramsAccepted: UInt64 = 0

    public init() {}

    public static func percentageOrNa(_ percentage: Double?, _ padding: Int) -> String {
        return if let percentage = percentage {
            String(format: "%.2f%%", percentage * 100).leftPadded(toLength: padding)
        } else {
            "N/A".leftPadded(toLength: padding)
        }
    }

    /// Computes and returns the statistical data for this instance and all connected nodes.
    public func compute() -> Fuzzilli_Protobuf_Statistics {
        assert(nodes.count - inactiveNodes.count == ownData.numChildNodes)

        // Update local statistics data
        ownData.avgCorpusSize = Double(corpusSize)
        ownData.avgProgramSize = programSizeAvg.currentValue
        ownData.avgCorpusProgramSize = corpusProgramSizeAvg.currentValue
        ownData.avgExecutionTime = executionTimeAvg.currentValue
        ownData.fuzzerOverhead = fuzzerOverheadAvg.currentValue
        ownData.minimizationOverhead = minimizationOverheadAvg.currentValue
        ownData.correctnessRate = correctnessRate.currentValue
        ownData.timeoutRate = timeoutRate.currentValue

        let localInstanceImportRate =
            instanceImportedProgramsReceived != 0
            ? Double(instanceImportedProgramsAccepted)
                / Double(instanceImportedProgramsReceived) : 1.0
        ownData.parentInstanceImportRate = localInstanceImportRate
        ownData.avgWorkerInstanceImportRate = localInstanceImportRate
        ownData.instanceImportedProgramsReceived = instanceImportedProgramsReceived
        ownData.instanceImportedProgramsAccepted = instanceImportedProgramsAccepted

        if let fuzzer = fuzzer {
            let contributorsList: [(prefix: String?, list: [Contributor], isCodeGenerator: Bool)] =
                fuzzer.codeGenerators.map { ($0.parts.count > 1 ? $0.name : nil, $0.parts, true) }
                + [
                    (nil, Array(fuzzer.programTemplates), false),
                    (nil, Array(fuzzer.mutators), false),
                ]
            ownData.contributorStats = contributorsList.flatMap { (prefix, list, isCodeGenerator) in
                list.map { contributor in
                    Fuzzilli_Protobuf_Statistics.ContributorStats.with {
                        $0.name = "\(prefix.flatMap { "\($0)/" } ?? "")\(contributor.name)"
                        $0.invocationCount = UInt64(contributor.invocationCount)
                        $0.successfulGenerationCount = UInt64(contributor.successfulGenerationCount)
                        $0.totalSamples = UInt64(contributor.totalSamples)
                        $0.correctSamples = UInt64(contributor.correctSamples)
                        $0.isCodeGenerator = isCodeGenerator
                        $0.interestingSamples = UInt64(contributor.interestingSamples)
                        $0.invalidSamples = UInt64(contributor.invalidSamples)
                        $0.timedOutSamples = UInt64(contributor.timedOutSamples)
                        $0.crashingSamples = UInt64(contributor.crashingSamples)
                        $0.differentialSamples = UInt64(contributor.differentialSamples)
                        $0.failures = UInt64(contributor.failures)
                        $0.totalInstructionsProduced = UInt64(contributor.totalInstructionsProduced)
                    }
                }
            }
        }

        // Compute global statistics data
        var data = ownData

        var contributorStatsByName = Dictionary(
            uniqueKeysWithValues: ownData.contributorStats.map { ($0.name, $0) }
        )

        var instanceImportedTotalWorkerReceived: UInt64 = 0
        var instanceImportedTotalWorkerAccepted: UInt64 = 0

        for (id, node) in nodes {
            // Add "global" fields, even from nodes that are no longer active
            data.totalSamples += node.totalSamples
            data.validSamples += node.validSamples
            data.timedOutSamples += node.timedOutSamples
            data.totalExecs += node.totalExecs
            data.aspectIntersectionNilCount += node.aspectIntersectionNilCount

            for stats in node.contributorStats {
                if var existing = contributorStatsByName[stats.name] {
                    assert(existing.isCodeGenerator == stats.isCodeGenerator)
                    existing.invocationCount += stats.invocationCount
                    existing.successfulGenerationCount += stats.successfulGenerationCount
                    existing.totalSamples += stats.totalSamples
                    existing.correctSamples += stats.correctSamples
                    existing.interestingSamples += stats.interestingSamples
                    existing.invalidSamples += stats.invalidSamples
                    existing.timedOutSamples += stats.timedOutSamples
                    existing.crashingSamples += stats.crashingSamples
                    existing.differentialSamples += stats.differentialSamples
                    existing.failures += stats.failures
                    existing.totalInstructionsProduced += stats.totalInstructionsProduced
                    contributorStatsByName[stats.name] = existing
                } else {
                    contributorStatsByName[stats.name] = stats
                }
            }

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

                instanceImportedTotalWorkerReceived += node.instanceImportedProgramsReceived
                instanceImportedTotalWorkerAccepted += node.instanceImportedProgramsAccepted
            }

            // All other fields are already indirectly synchronized (e.g. number of interesting samples founds)
        }

        data.contributorStats = Array(contributorStatsByName.values)

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

        if !nodes.isEmpty {
            data.instanceImportedProgramsReceived = instanceImportedTotalWorkerReceived
            data.instanceImportedProgramsAccepted = instanceImportedTotalWorkerAccepted
            data.avgWorkerInstanceImportRate =
                instanceImportedTotalWorkerReceived > 0
                ? Double(instanceImportedTotalWorkerAccepted)
                    / Double(instanceImportedTotalWorkerReceived) : 1.0
        }

        return data
    }

    public func initialize(with fuzzer: Fuzzer) {
        self.fuzzer = fuzzer
        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { _ in
            self.ownData.crashingSamples += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.DifferentialFound) { _ in
            self.ownData.differentialSamples += 1
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
        fuzzer.registerEventListener(for: fuzzer.events.AspectIntersectionNil) { _ in
            self.ownData.aspectIntersectionNilCount += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.Synchronized) {
            let initialSamples = UInt64(fuzzer.corpus.size)
            self.instanceImportedProgramsReceived += initialSamples
            self.instanceImportedProgramsAccepted += initialSamples
        }
        fuzzer.registerEventListener(for: fuzzer.events.ProgramImported) { ev in
            if ev.origin.isFromOtherInstance() {
                self.instanceImportedProgramsReceived += 1
                if ev.wasImported {
                    self.instanceImportedProgramsAccepted += 1
                }
            }
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
                return  // This can happen due to delays in queue processing
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
                let globalStats = self.compute()
                if fuzzer.config.machineReadableStats {
                    for json in Self.machineReadableMutatorStats(globalStats, of: fuzzer) {
                        self.logger.info(json)
                    }
                }
                self.logger.info("Mutator Statistics:")
                let statsByName = Dictionary(
                    uniqueKeysWithValues: globalStats.contributorStats.map { ($0.name, $0) }
                )
                let nameMaxLength = fuzzer.mutators.map({ $0.name.count }).max()!
                let maxSamplesGeneratedStringLength = fuzzer.mutators.map({
                    let total = statsByName[$0.name]?.totalSamples ?? 0
                    return String(total).count
                }).max()!
                for mutator in fuzzer.mutators {
                    let stats =
                        statsByName[mutator.name]
                        ?? Fuzzilli_Protobuf_Statistics.ContributorStats.with {
                            $0.name = mutator.name
                        }
                    let name = mutator.name.rightPadded(toLength: nameMaxLength)
                    let correctnessRate = Self.percentageOrNa(stats.correctnessRate, 7)
                    let failureRate = Self.percentageOrNa(stats.failureRate, 7)
                    let timeoutRate = Self.percentageOrNa(stats.timeoutRate, 6)
                    let interestingSamplesRate = Self.percentageOrNa(
                        stats.interestingSamplesRate, 7)
                    let avgInstructionsAdded = String(
                        format: "%.2f", stats.avgNumberOfInstructionsGenerated
                    ).leftPadded(toLength: 5)
                    let samplesGenerated = String(stats.totalSamples).leftPadded(
                        toLength: maxSamplesGeneratedStringLength)
                    let crashesFound = stats.crashesFound
                    self.logger.info(
                        "    \(name) : Correctness rate: \(correctnessRate), Failure rate: \(failureRate), Interesting sample rate: \(interestingSamplesRate), Timeout rate: \(timeoutRate), Avg. # of instructions added: \(avgInstructionsAdded), Total # of generated samples: \(samplesGenerated), Total # of crashes found: \(crashesFound)"
                    )
                }
            }

        }
        if fuzzer.config.logLevel.isAtLeast(.verbose) {
            fuzzer.timers.scheduleTask(every: 30 * Minutes) {
                self.logger.verbose("Code Generator Statistics:")
                let globalStats = self.compute()
                let statsByName = Dictionary(
                    uniqueKeysWithValues: globalStats.contributorStats.map { ($0.name, $0) }
                )
                let nameMaxLength = fuzzer.codeGenerators.map({ $0.name.count }).max()!

                for generator in fuzzer.codeGenerators {
                    for stub in generator.parts {
                        let name =
                            generator.parts.count > 1 ? "\(generator.name)/\(stub.name)" : stub.name
                        let stats =
                            statsByName[name]
                            ?? Fuzzilli_Protobuf_Statistics.ContributorStats.with { $0.name = name }
                        let namePadded = name.rightPadded(toLength: nameMaxLength)
                        let correctnessRate = Self.percentageOrNa(stats.correctnessRate, 7)
                        let interestingSamplesRate = Self.percentageOrNa(
                            stats.interestingSamplesRate, 7)
                        let timeoutRate = Self.percentageOrNa(stats.timeoutRate, 6)
                        let avgInstructionsAdded = String(
                            format: "%.2f", stats.avgNumberOfInstructionsGenerated
                        ).leftPadded(toLength: 5)
                        let invocationSuccessRate = Self.percentageOrNa(
                            stats.invocationSuccessRate, 7)
                        let samplesGenerated = stats.totalSamples
                        self.logger.verbose(
                            "    \(namePadded) : Invocation Success: \(invocationSuccessRate), Correctness rate: \(correctnessRate), Interesting sample rate: \(interestingSamplesRate), Timeout rate: \(timeoutRate), Avg. # of instructions added: \(avgInstructionsAdded), Total # of generated samples: \(samplesGenerated)"
                        )
                    }
                }
            }
        }
    }

    /// Import statistics data from a child node.
    public func importData(_ stats: Fuzzilli_Protobuf_Statistics, from child: UUID) {
        nodes[child] = stats
    }

    public static func machineReadableFuzzerStats(
        _ stats: Fuzzilli_Protobuf_Statistics,
        of fuzzer: Fuzzer,
        state: String,
        timeSinceLastInterestingSample: TimeInterval
    ) -> String? {
        let metrics = MachineReadableFuzzerMetrics(
            totalSamples: stats.totalSamples,
            interestingSamples: stats.interestingSamples,
            lastInterestingSample: finiteOrZero(timeSinceLastInterestingSample),
            validSamples: stats.validSamples,
            corpusSize: fuzzer.corpus.size,
            avgCorpusSize: stats.numChildNodes > 0 ? finiteOrZero(stats.avgCorpusSize) : nil,
            parentInstanceImportRate: finiteOrZero(stats.parentInstanceImportRate),
            avgWorkerInstanceImportRate: finiteOrZero(stats.avgWorkerInstanceImportRate),
            instanceImportedProgramsReceived: stats.instanceImportedProgramsReceived,
            instanceImportedProgramsAccepted: stats.instanceImportedProgramsAccepted,
            correctnessRate: finiteOrZero(stats.correctnessRate),
            overallCorrectnessRate: finiteOrZero(stats.overallCorrectnessRate),
            timeoutRate: finiteOrZero(stats.timeoutRate),
            overallTimeoutRate: finiteOrZero(stats.overallTimeoutRate),
            crashingSamples: stats.crashingSamples,
            differentialSamples: fuzzer.isDifferentialFuzzing ? stats.differentialSamples : nil,
            timedOutSamples: stats.timedOutSamples,
            aspectIntersectionNilCount: stats.aspectIntersectionNilCount,
            coverage: finiteOrZero(stats.coverage),
            avgProgramSize: finiteOrZero(stats.avgProgramSize),
            avgCorpusProgramSize: finiteOrZero(stats.avgCorpusProgramSize),
            avgExecutionTime: finiteOrZero(stats.avgExecutionTime),
            numChildNodes: stats.numChildNodes,
            execsPerSecond: finiteOrZero(stats.execsPerSecond),
            fuzzerOverhead: finiteOrZero(stats.fuzzerOverhead),
            minimizationOverhead: finiteOrZero(stats.minimizationOverhead),
            totalExecs: stats.totalExecs
        )
        let payload = MachineReadableFuzzerStatsPayload(
            tag: fuzzer.config.tag,
            state: state,
            uptime: finiteOrZero(fuzzer.uptime()),
            stats: metrics
        )
        return encodeMachineReadableStatsJSON(payload)
    }

    public static func machineReadableMutatorStats(
        _ globalStats: Fuzzilli_Protobuf_Statistics,
        of fuzzer: Fuzzer
    ) -> [String] {
        let statsByName = Dictionary(
            uniqueKeysWithValues: globalStats.contributorStats.map { ($0.name, $0) }
        )
        let uptime = finiteOrZero(fuzzer.uptime())
        var lines = [String]()
        lines.reserveCapacity(fuzzer.mutators.count)
        for mutator in fuzzer.mutators {
            let stats =
                statsByName[mutator.name]
                ?? Fuzzilli_Protobuf_Statistics.ContributorStats.with {
                    $0.name = mutator.name
                }
            let metrics = MachineReadableMutatorMetrics(
                invocationCount: stats.invocationCount,
                successfulGenerationCount: stats.successfulGenerationCount,
                totalSamples: stats.totalSamples,
                correctSamples: stats.correctSamples,
                interestingSamples: stats.interestingSamples,
                invalidSamples: stats.invalidSamples,
                timedOutSamples: stats.timedOutSamples,
                crashingSamples: stats.crashingSamples,
                differentialSamples: stats.differentialSamples,
                failures: stats.failures,
                totalInstructionsProduced: stats.totalInstructionsProduced,
                correctnessRate: finiteOrNil(stats.correctnessRate),
                failureRate: finiteOrNil(stats.failureRate),
                interestingSamplesRate: finiteOrNil(stats.interestingSamplesRate),
                timeoutRate: finiteOrNil(stats.timeoutRate),
                avgInstructionsProduced: finiteOrZero(stats.avgNumberOfInstructionsGenerated)
            )
            let payload = MachineReadableMutatorStatsPayload(
                mutator: mutator.name,
                tag: fuzzer.config.tag,
                uptime: uptime,
                stats: metrics
            )
            if let json = encodeMachineReadableStatsJSON(payload, loggerLabel: "Statistics") {
                lines.append(json)
            }
        }
        return lines
    }
}

/// Maximum formatted stdout line length (in UTF-8 bytes) for machine-readable statistics lines.
/// Exceeding 10,000 bytes would cause downstream log pipelines (e.g. `fold -w 10000`) to split
/// JSON records across multiple lines.
public let maxMachineReadableStatsLineLength = 10_000

func encodeMachineReadableStatsJSON<T: Encodable>(
    _ value: T,
    loggerLabel: String? = nil,
    maxLineLength: Int = maxMachineReadableStatsLineLength,
    onOverflow: ((String) -> Void)? = nil
) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value),
        let json = String(data: data, encoding: .utf8)
    else {
        return nil
    }
    // TerminalUI wraps main-instance Logger output as "\u{001B}[0;XXm[Label] <msg>\u{001B}[0;0m" (16 + label bytes).
    let wrapperBytes = loggerLabel.map { 16 + $0.utf8.count } ?? 0
    let formattedLength = json.utf8.count + wrapperBytes
    if formattedLength > maxLineLength {
        let msg =
            "Machine-readable statistics line length (\(formattedLength) bytes) exceeds limit of \(maxLineLength) bytes"
        if let onOverflow {
            onOverflow(msg)
            return nil
        }
        fatalError(msg)
    }
    return json
}

private func finiteOrZero(_ value: Double) -> Double {
    return value.isFinite ? value : 0.0
}

private func finiteOrNil(_ value: Double?) -> Double? {
    guard let value = value, value.isFinite else { return nil }
    return value
}

private struct MachineReadableFuzzerMetrics: Encodable {
    let totalSamples: UInt64
    let interestingSamples: UInt64
    let lastInterestingSample: Double
    let validSamples: UInt64
    let corpusSize: Int
    let avgCorpusSize: Double?
    let parentInstanceImportRate: Double
    let avgWorkerInstanceImportRate: Double
    let instanceImportedProgramsReceived: UInt64
    let instanceImportedProgramsAccepted: UInt64
    let correctnessRate: Double
    let overallCorrectnessRate: Double
    let timeoutRate: Double
    let overallTimeoutRate: Double
    let crashingSamples: UInt64
    let differentialSamples: UInt64?
    let timedOutSamples: UInt64
    let aspectIntersectionNilCount: UInt64
    let coverage: Double
    let avgProgramSize: Double
    let avgCorpusProgramSize: Double
    let avgExecutionTime: Double
    let numChildNodes: UInt64
    let execsPerSecond: Double
    let fuzzerOverhead: Double
    let minimizationOverhead: Double
    let totalExecs: UInt64
}

private struct MachineReadableFuzzerStatsPayload: Encodable {
    let fuzzilliStats = "fuzzer"
    let tag: String?
    let state: String
    let uptime: Double
    let stats: MachineReadableFuzzerMetrics
}

private struct MachineReadableMutatorMetrics: Encodable {
    let invocationCount: UInt64
    let successfulGenerationCount: UInt64
    let totalSamples: UInt64
    let correctSamples: UInt64
    let interestingSamples: UInt64
    let invalidSamples: UInt64
    let timedOutSamples: UInt64
    let crashingSamples: UInt64
    let differentialSamples: UInt64
    let failures: UInt64
    let totalInstructionsProduced: UInt64
    let correctnessRate: Double?
    let failureRate: Double?
    let interestingSamplesRate: Double?
    let timeoutRate: Double?
    let avgInstructionsProduced: Double
}

private struct MachineReadableMutatorStatsPayload: Encodable {
    let fuzzilliStats = "mutator"
    let mutator: String
    let tag: String?
    let uptime: Double
    let stats: MachineReadableMutatorMetrics
}

extension Fuzzilli_Protobuf_Statistics {
    /// The ratio of valid samples to produced samples over the entire runtime of the fuzzer.
    public var overallCorrectnessRate: Double {
        return totalSamples != 0 ? Double(validSamples) / Double(totalSamples) : 0
    }

    /// The ratio of timed-out samples to produced samples over the entire runtime of the fuzzer.
    public var overallTimeoutRate: Double {
        return totalSamples != 0 ? Double(timedOutSamples) / Double(totalSamples) : 0
    }
}

extension Fuzzilli_Protobuf_Statistics.ContributorStats {
    public var invocationSuccessRate: Double? {
        guard invocationCount > 0 else { return nil }
        return Double(successfulGenerationCount) / Double(invocationCount)
    }

    public var correctnessRate: Double? {
        guard totalSamples > 0 else { return nil }
        return Double(correctSamples) / Double(totalSamples)
    }

    public var interestingSamplesRate: Double? {
        guard totalSamples > 0 else { return nil }
        return Double(interestingSamples) / Double(totalSamples)
    }

    public var timeoutRate: Double? {
        guard totalSamples > 0 else { return nil }
        return Double(timedOutSamples) / Double(totalSamples)
    }

    public var failureRate: Double? {
        let totalAttempts = totalSamples + failures
        guard totalAttempts > 0 else { return nil }
        return Double(failures) / Double(totalAttempts)
    }

    public var avgNumberOfInstructionsGenerated: Double {
        guard totalSamples > 0 else { return 0.0 }
        return Double(totalInstructionsProduced) / Double(totalSamples)
    }

    public var crashesFound: UInt64 {
        return crashingSamples
    }
}
