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

    /// Data required to compute executions per second.
    private var currentExecs = 0.0
    private var lastEpsUpdate = Date()
    private var lastExecsPerSecond = 0.0

    /// Data required to compute the fuzzer overhead (i.e. the fraction of the total time that is not spent executing generated programs in the target engine).
    /// This includes time required for worker synchronization, to mutate/generate a program, to lift it, to restart the target process after crashes/timeouts, etc.
    private var overheadAvg = MovingAverage(n: 1000)
    private var lastPreExecDate = Date()
    private var lastExecDate = Date()

    /// Moving average to keep track of average program size.
    private var programSizeAvg = MovingAverage(n: 1000)

    /// Moving average to keep track of average program size in the corpus.
    /// Only computed locally, not across workers.
    private var corpusProgramSizeAvg = MovingAverage(n: 1000)

    /// Moving average of the number of valid programs in the last 1000 generated programs.
    private var correctnessRate = MovingAverage(n: 1000)

    /// Moving average of the number of timeoouts in the last 1000 generated programs.
    private var timeoutRate = MovingAverage(n: 1000)

    /// All data from connected workers.
    private var workers = [UUID: Fuzzilli_Protobuf_Statistics]()

    /// The IDs of workers that are currently inactive.
    private var inactiveWorkers = Set<UUID>()

    public init() {}

    /// Computes and returns the statistical data for this instance and all connected workers.
    public func compute() -> Fuzzilli_Protobuf_Statistics {
        Assert(workers.count - inactiveWorkers.count == ownData.numWorkers)

        // Compute local statistics data
        ownData.avgProgramSize = programSizeAvg.currentValue
        ownData.avgCorpusProgramSize = corpusProgramSizeAvg.currentValue
        ownData.fuzzerOverhead = overheadAvg.currentValue
        ownData.correctnessRate = correctnessRate.currentValue
        ownData.timeoutRate = timeoutRate.currentValue

        // Compute global statistics data
        var data = ownData
        for (id, workerData) in workers {
            // Add "global" fields, even from workers that are no longer active
            data.totalSamples += workerData.totalSamples
            data.validSamples += workerData.validSamples
            data.timedOutSamples += workerData.timedOutSamples
            data.totalExecs += workerData.totalExecs

            if !self.inactiveWorkers.contains(id) {
                // Add fields that only have meaning for active workers
                data.numWorkers += workerData.numWorkers
                data.avgProgramSize += workerData.avgProgramSize
                data.execsPerSecond += workerData.execsPerSecond
                data.fuzzerOverhead += workerData.fuzzerOverhead
                data.correctnessRate += workerData.correctnessRate
                data.timeoutRate += workerData.timeoutRate
            }

            // All other fields are already indirectly synchronized (e.g. number of interesting samples founds)
        }

        data.avgProgramSize /= Double(ownData.numWorkers + 1)
        data.fuzzerOverhead /= Double(ownData.numWorkers + 1)
        data.correctnessRate /= Double(ownData.numWorkers + 1)
        data.timeoutRate /= Double(ownData.numWorkers + 1)

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
        fuzzer.registerEventListener(for: fuzzer.events.PostExecute) { exec in
            self.ownData.totalExecs += 1
            self.currentExecs += 1

            let now = Date()
            let totalTime = now.timeIntervalSince(self.lastExecDate)
            self.lastExecDate = now

            let overhead = 1.0 - (exec.execTime / totalTime)
            self.overheadAvg.add(overhead)


        }
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            self.ownData.interestingSamples += 1
            self.ownData.coverage = fuzzer.evaluator.currentScore
            self.corpusProgramSizeAvg.add(ev.program.size)
        }
        fuzzer.registerEventListener(for: fuzzer.events.ProgramGenerated) { program in
            self.ownData.totalSamples += 1
            self.programSizeAvg.add(program.size)
        }
        fuzzer.registerEventListener(for: fuzzer.events.WorkerConnected) { id in
            self.ownData.numWorkers += 1
            self.workers[id] = Fuzzilli_Protobuf_Statistics()
            self.inactiveWorkers.remove(id)
        }
        fuzzer.registerEventListener(for: fuzzer.events.WorkerDisconnected) { id in
            self.ownData.numWorkers -= 1
            self.inactiveWorkers.insert(id)
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
    }

    /// Import statistics data from a worker.
    public func importData(_ stats: Fuzzilli_Protobuf_Statistics, from worker: UUID) {
        workers[worker] = stats
    }
}

extension Fuzzilli_Protobuf_Statistics {
    /// The ratio of valid samples to produced samples over the entire runtime of the fuzzer.
    public var globalCorrectnessRate: Double {
        return Double(validSamples) / Double(totalSamples)
    }

    /// The ratio of timed-out samples to produced samples over the entire runtime of the fuzzer.
    public var globalTimeoutRate: Double {
        return Double(timedOutSamples) / Double(totalSamples)
    }
}
