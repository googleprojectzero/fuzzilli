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

/// Master and worker modules to synchronize fuzzer instance within the same process.
///
/// Generally, this code should always use .async instead of .sync to avoid deadlocks.
/// Furthermore, all reference types sent between workers and masters, in particular
/// Program objects, need to be deep copied to prevent race conditions.

public class ThreadMaster: Module {
    /// Associated fuzzer.
    unowned let fuzzer: Fuzzer

    /// The active workers
    var workers: [Fuzzer] = []

    /// Used to ensure that all workers have shut down before the master teminates the process.
    let shutdownGroup = DispatchGroup()

    public init(for fuzzer: Fuzzer) {
        self.fuzzer = fuzzer
    }

    public func initialize(with fuzzer: Fuzzer) {
        assert(self.fuzzer === fuzzer)

        // Corpus synchronization
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            for worker in self.workers {
                // Don't send programs back to where they came from
                if case .worker(let id) = ev.origin, id == worker.id { return }
                let program = ev.program.copy()
                worker.async {
                    // Dropout can, if enabled in the fuzzer config, help workers become more independent
                    // from the rest of the fuzzers by forcing them to rediscover edges in different ways.
                    worker.importProgram(program, enableDropout: true, origin: .master)
                }
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            for worker in self.workers {
                worker.async {
                    worker.shutdown(reason: .masterShutdown)
                }
            }
            self.shutdownGroup.wait()
        }
    }

    func registerWorker(_ worker: Fuzzer) {
        fuzzer.dispatchEvent(fuzzer.events.WorkerConnected, data: worker.id)
        workers.append(worker)

        worker.async {
            self.shutdownGroup.enter()
            worker.registerEventListener(for: worker.events.ShutdownComplete) { _ in
                self.shutdownGroup.leave()
                // The master instance is responsible for terminating the process, so just sleep here now.
                while true { Thread.sleep(forTimeInterval: 60) }
            }
        }
    }
}

public class ThreadWorker: Module {
    /// The master instance to synchronize with.
    private let master: Fuzzer

    public init(forMaster master: Fuzzer) {
        self.master = master
    }

    public func initialize(with fuzzer: Fuzzer) {
        let master = self.master

        // Register with the master.
        master.async {
            guard let master = ThreadMaster.instance(for: master) else { fatalError("No active ThreadMaster module on master instance") }
            master.registerWorker(fuzzer)
        }

        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            let program = ev.program.copy()
            master.async {
                master.importCrash(program, origin: .worker(id: fuzzer.id))
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            // Don't send programs back to where they came from
            if case .master = ev.origin { return }
            let program = ev.program.copy()
            master.async {
                master.importProgram(program, origin: .worker(id: fuzzer.id))
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
            master.async {
                master.dispatchEvent(master.events.Log, data: ev)
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { reason in
            assert(reason != .userInitiated)
            // Only in the fatalError case to we have to tell the master to shut down
            if reason == .fatalError {
                master.async {
                    master.shutdown(reason: reason)
                }
            }
        }

        // Regularly send local statistics to the master
        if let stats = Statistics.instance(for: fuzzer) {
            fuzzer.timers.scheduleTask(every: 30 * Seconds) {
                let data = stats.compute()
                master.async {
                    Statistics.instance(for: master)?.importData(data, from: fuzzer.id)
                }
            }
        }
    }
}
