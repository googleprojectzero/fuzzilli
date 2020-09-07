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
///
/// TODO this module is currently mostly untested and should be regarded experimental.

public class LocalWorker: Module {
    /// The master instance to synchronize with.
    private let master: Fuzzer
    
    /// UUID of this instance.
    let id: UUID
    
    public init(worker: Fuzzer, master: Fuzzer) {
        self.master = master
        self.id = UUID()
        
        master.async {
            // "Identify" with the master.
            master.dispatchEvent(master.events.WorkerConnected, data: self.id)
            
            // Corpus synchronization
            master.registerEventListener(for: master.events.InterestingProgramFound) { ev in
                let program = ev.program.copy()
                worker.async {
                    // Dropout can, if enabled in the fuzzer config, help workers become more independent
                    // from the rest of the fuzzers by forcing them to rediscover edges in different ways.
                    worker.importProgram(program, enableDropout: true, shouldMinimize: false)
                }
            }
        }
        
        // Access to classes appears to be thread-safe...
        // TODO the programs should potentially be deep-copied, otherwise there will
        // be Operation instances used by multiple threads.
        worker.registerEventListener(for: worker.events.CrashFound) { ev in
            let program = ev.program.copy()
            master.async {
                master.importCrash(program, shouldMinimize: false)
            }
        }
        
        worker.registerEventListener(for: worker.events.InterestingProgramFound) { ev in
            let program = ev.program.copy()
            master.async {
                master.importProgram(program, shouldMinimize: false)
            }
        }
        
        worker.registerEventListener(for: worker.events.Log) { ev in
            master.async {
                master.dispatchEvent(master.events.Log, data: ev)
            }
        }
        
        // Regularly send local statistics to the master
        if let stats = Statistics.instance(for: worker) {
            worker.timers.scheduleTask(every: 60 * Seconds) {
                let data = stats.compute()
                master.async {
                    Statistics.instance(for: master)?.importData(data, from: self.id)
                }
            }
        }
    }
}
