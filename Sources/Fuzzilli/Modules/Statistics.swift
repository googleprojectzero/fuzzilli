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
    public struct Data: Codable {
        /// The total number of samples produced.
        public fileprivate(set) var totalSamples = 0
        
        /// The number of valid samples produced.
        public fileprivate(set) var validSamples = 0
        
        /// The number of intersting samples produced.
        public fileprivate(set) var interestingSamples = 0
        
        /// The number of timed-out samples produced.
        public fileprivate(set) var timedOutSamples = 0
        
        /// The number of crashes found.
        public fileprivate(set) var crashingSamples = 0
        
        /// The total number of program executions.
        public fileprivate(set) var totalExecs = 0
        
        /// The average size of produced programs over the last 1000 programs.
        public fileprivate(set) var avgProgramSize = 0.0
        
        /// The current executions per second.
        public fileprivate(set) var execsPerSecond = 0.0
        
        /// The number of workers connected directly or indirectly to this instance.
        public fileprivate(set) var numWorkers = 0

        /// The percentage of edges covered if doing coverage-guided fuzzing.
        public fileprivate(set) var coverage = 0.0

        /// The ratio of valid samples to produced samples.
        public var successRate: Double {
            return Double(validSamples) / Double(totalSamples)
        }
        
        /// The ratio of timed-out samples to produced samples.
        public var timeoutRate: Double {
            return Double(timedOutSamples) / Double(totalSamples)
        }
    }
    
    /// The data just for this instance.
    private var ownData = Data()
    
    /// Information required to compute executions per second.
    private var currentExecs = 0.0
    private var lastEpsUpdate = Date()
    private var lastExecsPerSecond = 0.0
    
    /// Moving average to keep track of average program size.
    private var avgProgramSize = MovingAverage(n: 1000)
    
    /// All data from connected workers.
    private var workers = [UUID: Data]()
    
    /// The IDs of workers that are currently inactive.
    private var inactiveWorkers = Set<UUID>()
    
    public init() {}
    
    /// Computes and returns the statistical data for this instance and all connected workers.
    public func compute() -> Data {
        assert(workers.count - inactiveWorkers.count == ownData.numWorkers)
        
        // Compute global statistics data
        var data = ownData
        
        for (id, workerData) in workers {
            data.totalSamples += workerData.totalSamples
            data.validSamples += workerData.validSamples
            data.timedOutSamples += workerData.timedOutSamples
            data.totalExecs += workerData.totalExecs
            
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
        fuzzer.events.CrashFound.observe { ev in
            self.ownData.crashingSamples += 1
        }
        fuzzer.events.TimeOutFound.observe { _ in
            self.ownData.timedOutSamples += 1
        }
        fuzzer.events.ValidProgramFound.observe { ev in
            self.ownData.validSamples += 1
        }
        fuzzer.events.PostExecute.observe { execution in
            self.ownData.totalExecs += 1
            self.currentExecs += 1
        }
        fuzzer.events.InterestingProgramFound.observe { ev in
            self.ownData.interestingSamples += 1
            self.ownData.coverage = fuzzer.evaluator.currentScore
        }
        fuzzer.events.ProgramGenerated.observe { program in
            self.ownData.totalSamples += 1
            self.avgProgramSize += program.size
            self.ownData.avgProgramSize = self.avgProgramSize.value
        }
        fuzzer.events.WorkerConnected.observe { id in
            self.ownData.numWorkers += 1
            self.workers[id] = Data()
            self.inactiveWorkers.remove(id)
        }
        fuzzer.events.WorkerDisconnected.observe { id in
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
    public func importData(_ data: Data, from worker: UUID) {
        workers[worker] = data
    }
}
