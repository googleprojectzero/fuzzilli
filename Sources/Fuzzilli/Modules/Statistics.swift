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
    
    /// Information required to compute executions per second.
    private var currentExecs = 0.0
    private var lastEpsUpdate = Date()
    private var lastExecsPerSecond = 0.0
    
    /// Moving average to keep track of average program size.
    private var avgProgramSize = MovingAverage(n: 1000)
    
    /// All data from connected workers.
    private var workers = [UUID: Fuzzilli_Protobuf_Statistics]()
    
    /// The IDs of workers that are currently inactive.
    private var inactiveWorkers = Set<UUID>()
    
    public init() {}
    
    /// Computes and returns the statistical data for this instance and all connected workers.
    public func compute() -> Fuzzilli_Protobuf_Statistics {
        assert(workers.count - inactiveWorkers.count == ownData.numWorkers)
        
        // Compute global statistics data
        var data = ownData
        
        for (id, workerData) in workers {
            data.totalSamples += workerData.totalSamples
            data.validSamples += workerData.validSamples
            data.timedOutSamples += workerData.timedOutSamples
            data.totalExecs += workerData.totalExecs
            data.typeCollectionAttempts += workerData.typeCollectionAttempts
            data.typeCollectionFailures += workerData.typeCollectionFailures
            data.typeCollectionTimeouts += workerData.typeCollectionTimeouts
            
            // Interesting samples and crashes are already synchronized
            
            if !self.inactiveWorkers.contains(id) {
                data.numWorkers += workerData.numWorkers
                data.avgProgramSize += workerData.avgProgramSize
                data.execsPerSecond += workerData.execsPerSecond
            }
        }
        
        data.avgProgramSize /= Double(ownData.numWorkers + 1)
        
        return data
    }
    
    public func initialize(with fuzzer: Fuzzer) {
        // Initialize our array of coverage scores.
        self.ownData.coverage = [Double]()
        for _ in fuzzer.runners {
            self.ownData.coverage.append(0.0)
        }
        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { _ in
            self.ownData.crashingSamples += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.TimeOutFound) { _ in
            self.ownData.timedOutSamples += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.ValidProgramFound) { _ in
            self.ownData.validSamples += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.PostExecute) { _ in
            self.ownData.totalExecs += 1
            self.currentExecs += 1
        }
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            self.ownData.interestingSamples += 1
            for (idx, (_, _, evaluator)) in fuzzer.runners.enumerated() {
                self.ownData.coverage[idx] = evaluator.currentScore
            }

            if ev.program.typeCollectionStatus == .success {
                self.ownData.interestingSamplesWithTypes += 1
            }

            guard ev.newTypeCollectionRun else { return }

            if ev.program.typeCollectionStatus != .notAttempted {
                self.ownData.typeCollectionAttempts += 1
            }

            if ev.program.typeCollectionStatus == .timeout {
                self.ownData.typeCollectionTimeouts += 1
            } else if ev.program.typeCollectionStatus == .error {
                self.ownData.typeCollectionFailures += 1
            }
        }
        fuzzer.registerEventListener(for: fuzzer.events.ProgramGenerated) { program in
            self.ownData.totalSamples += 1
            self.avgProgramSize += program.size
            self.ownData.avgProgramSize = self.avgProgramSize.value
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
    /// The ratio of valid samples to produced samples.
    public var successRate: Double {
        return Double(validSamples) / Double(totalSamples)
    }
    
    /// The ratio of timed-out samples to produced samples.
    public var timeoutRate: Double {
        return Double(timedOutSamples) / Double(totalSamples)
    }

    /// The ratio of time-outs and total number of runtime type collection runs.
    public var typeCollectionTimeoutRate: Double {
        return Double(typeCollectionTimeouts) / Double(typeCollectionAttempts)
    }

    /// The ratio of failures and total number of runtime type collection runs.
    public var typeCollectionFailureRate: Double {
        return Double(typeCollectionFailures) / Double(typeCollectionAttempts)
    }

    /// The ratio of interesting samples with tuntime types information and total number of interesting samples.
    public var interestingSamplesWithTypesRate: Double {
        return Double(interestingSamplesWithTypes) / Double(interestingSamples)
    }
}
