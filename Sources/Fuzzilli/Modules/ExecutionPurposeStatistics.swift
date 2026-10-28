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

/// Counts executions and execution time per `ExecutionPurpose`, over the main instance and its
/// thread workers. Differential reference runs are not counted. Execution time is the runner's
/// time summed over instances, so it can exceed wall-clock time.
///
/// Also counts how often an instance picks a program for mutation that another instance picked
/// shortly before. Programs are matched by UUID.
///
/// The main instance's module logs the totals, periodically and on shutdown. Worker modules add
/// to its counters.
public class ExecutionPurposeStatistics: Module {
    struct Totals {
        var count: UInt64 = 0
        var time: Double = 0.0
    }

    private struct PickRecord {
        var lastPicker: UUID
        var time: Date
        /// Time of the last pick by an instance other than `lastPicker`.
        var otherTime: Date?
    }

    /// Counters shared by the main instance and its workers.
    private final class Counters {
        let lock = NSLock()
        var totals = [ExecutionPurpose: Totals]()
        var lastPicks = [UUID: PickRecord]()
        var numPicks: UInt64 = 0
        var numOverlappingPicks: UInt64 = 0
    }

    /// Two picks of the same program by different instances overlap if they are at most this many
    /// seconds apart.
    public static let pickOverlapWindow: TimeInterval = 60

    private let counters: Counters
    private let isMainInstance: Bool
    private let logInterval: TimeInterval
    private let logger = Logger(withLabel: "ExecutionPurposeStatistics")
    private weak var fuzzer: Fuzzer?
    private var currentPurpose = ExecutionPurpose.other

    /// Creates the module of the main instance.
    public init(logInterval: TimeInterval = 600) {
        self.counters = Counters()
        self.isMainInstance = true
        self.logInterval = logInterval
    }

    /// Creates the module of a worker. It adds to the counters of `main`.
    public init(addingTo main: ExecutionPurposeStatistics) {
        self.counters = main.counters
        self.isMainInstance = false
        self.logInterval = main.logInterval
    }

    public func initialize(with fuzzer: Fuzzer) {
        fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { (_, purpose) in
            self.currentPurpose = purpose
        }
        fuzzer.registerEventListener(for: fuzzer.events.PostExecute) { execution in
            let purpose = self.currentPurpose
            self.counters.lock.withLock {
                var totals = self.counters.totals[purpose, default: Totals()]
                totals.count += 1
                totals.time += execution.execTime
                self.counters.totals[purpose] = totals
            }
        }

        guard isMainInstance else { return }
        self.fuzzer = fuzzer
        fuzzer.timers.scheduleTask(every: logInterval) {
            self.logTotals()
        }
        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            self.logTotals()
        }
    }

    /// Records that `program` was picked for mutation by the instance `picker`.
    public func recordMutationPick(of program: Program, by picker: UUID, at now: Date = Date()) {
        let id = program.id
        counters.lock.withLock {
            counters.numPicks += 1
            let last = counters.lastPicks[id]
            let otherTime = last?.lastPicker == picker ? last?.otherTime : last?.time
            if let otherTime, now.timeIntervalSince(otherTime) <= Self.pickOverlapWindow {
                counters.numOverlappingPicks += 1
            }
            counters.lastPicks[id] = PickRecord(lastPicker: picker, time: now, otherTime: otherTime)
        }
    }

    var totals: [ExecutionPurpose: Totals] {
        counters.lock.withLock { counters.totals }
    }

    var pickCounts: (picks: UInt64, overlapping: UInt64) {
        counters.lock.withLock { (counters.numPicks, counters.numOverlappingPicks) }
    }

    /// Forgets picks that are too old to overlap with a future pick.
    func dropOldPicks(now: Date = Date()) {
        counters.lock.withLock {
            counters.lastPicks = counters.lastPicks.filter {
                now.timeIntervalSince($0.value.time) <= Self.pickOverlapWindow
            }
        }
    }

    private func logTotals() {
        dropOldPicks()
        let totals = self.totals
        let (picks, overlapping) = pickCounts
        let totalCount = totals.values.reduce(0) { $0 + $1.count }
        let totalTime = totals.values.reduce(0.0) { $0 + $1.time }
        guard totalCount > 0 else { return }

        if fuzzer?.config.machineReadableStats == true,
            let json = Self.machineReadableStats(
                totals: totals,
                picks: (picks: picks, overlapping: overlapping),
                tag: fuzzer?.config.tag,
                uptime: fuzzer?.uptime() ?? 0.0
            )
        {
            logger.info(json)
        }
        logger.info("Executions by purpose (main instance and thread workers):")
        for (purpose, entry) in totals.sorted(by: { $0.value.count > $1.value.count }) {
            let name = "\(purpose)".rightPadded(toLength: 30)
            let count = String(entry.count).leftPadded(toLength: 12)
            let countShare = String(format: "%5.1f", Double(entry.count) / Double(totalCount) * 100)
            let time = String(format: "%10.0f", entry.time)
            let timeShare = String(
                format: "%5.1f", totalTime > 0 ? entry.time / totalTime * 100 : 0)
            logger.info(
                "    \(name): \(count) execs (\(countShare)%), \(time)s exec time (\(timeShare)%)")
        }
        logger.info(
            "    Total: \(totalCount) execs, \(String(format: "%.0f", totalTime))s exec time")
        if picks > 0 {
            let share = String(format: "%.1f", Double(overlapping) / Double(picks) * 100)
            let window = Int(Self.pickOverlapWindow)
            logger.info(
                "Mutation picks: \(picks), of which \(overlapping) (\(share)%) picked a program that another instance picked within the last \(window)s"
            )
        }
    }

    static func machineReadableStats(
        totals: [ExecutionPurpose: Totals],
        picks: (picks: UInt64, overlapping: UInt64),
        tag: String?,
        uptime: TimeInterval
    ) -> String? {
        let totalCount = totals.values.reduce(0) { $0 + $1.count }
        let totalTime = totals.values.reduce(0.0) { $0 + $1.time }
        var purposes = [String: MachineReadablePurposeEntry]()
        for (purpose, entry) in totals {
            purposes["\(purpose)"] = MachineReadablePurposeEntry(
                count: entry.count,
                time: entry.time.isFinite ? entry.time : 0.0
            )
        }
        let payload = MachineReadableExecutionPurposePayload(
            tag: tag,
            uptime: uptime.isFinite ? uptime : 0.0,
            totalExecs: totalCount,
            totalTime: totalTime.isFinite ? totalTime : 0.0,
            purposes: purposes,
            mutationPicks: picks.picks > 0 ? picks.picks : nil,
            overlappingMutationPicks: picks.picks > 0 ? picks.overlapping : nil,
            pickOverlapWindow: picks.picks > 0 ? Self.pickOverlapWindow : nil
        )
        return encodeMachineReadableStatsJSON(
            payload, loggerLabel: "ExecutionPurposeStatistics")
    }
}

private struct MachineReadablePurposeEntry: Encodable {
    let count: UInt64
    let time: Double
}

private struct MachineReadableExecutionPurposePayload: Encodable {
    let fuzzilliStats = "executionPurpose"
    let tag: String?
    let uptime: Double
    let totalExecs: UInt64
    let totalTime: Double
    let purposes: [String: MachineReadablePurposeEntry]
    let mutationPicks: UInt64?
    let overlappingMutationPicks: UInt64?
    let pickOverlapWindow: Double?
}
