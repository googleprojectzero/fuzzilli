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

/// This module synchronizes fuzzer instance in the same process.
public class ThreadWorker: Module {
    /// The master instance to synchronize with.
    private let master: Fuzzer

    /// Tracks whether this instance is shutting down, in which case
    /// no more (synchronous) messages should be sent to the master
    private var shuttingDown = false

    public init(forMaster master: Fuzzer) {
        self.master = master
    }

    public func initialize(with worker: Fuzzer) {
        let master = self.master

        // Set up synchronization.
        // Note: all reference types sent between workers and masters, in particular
        // Program objects, have to be deep copied to prevent race conditions.

        master.async {
            // "Identify" with the master.
            master.dispatchEvent(master.events.WorkerConnected, data: worker.id)

            // Corpus synchronization
            master.registerEventListener(for: master.events.InterestingProgramFound) { ev in
                // Don't send programs back to where they came from
                if case .worker(let id) = ev.origin, id == worker.id { return }
                let program = ev.program.copy()
                worker.async {
                    // Dropout can, if enabled in the fuzzer config, help workers become more independent
                    // from the rest of the fuzzers by forcing them to rediscover edges in different ways.
                    worker.importProgram(program, enableDropout: true, origin: .master)
                }
            }

            master.registerEventListener(for: master.events.Shutdown) {
                self.shuttingDown = true
                worker.sync {
                    worker.shutdown()
                }
            }
        }

        worker.registerEventListener(for: worker.events.CrashFound) { ev in
            let program = ev.program.copy()
            master.async {
                master.importCrash(program, origin: .worker(id: worker.id))
            }
        }

        worker.registerEventListener(for: worker.events.InterestingProgramFound) { ev in
            // Don't send programs back to where they came from
            if case .master = ev.origin { return }
            let program = ev.program.copy()
            master.async {
                master.importProgram(program, origin: .worker(id: worker.id))
            }
        }

        worker.registerEventListener(for: worker.events.Log) { ev in
            // Use sync here so that e.g. logger.fatal messages from workers get processed by the master
            guard !self.shuttingDown else { return }
            master.sync {
                master.dispatchEvent(master.events.Log, data: ev)
            }
        }

        // Regularly send local statistics to the master
        if let stats = Statistics.instance(for: worker) {
            worker.timers.scheduleTask(every: 30 * Seconds) {
                let data = stats.compute()
                master.async {
                    Statistics.instance(for: master)?.importData(data, from: worker.id)
                }
            }
        }
    }
}
