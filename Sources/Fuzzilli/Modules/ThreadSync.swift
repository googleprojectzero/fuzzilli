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
        
        master.queue.addOperation {
            // "Identify" with the master.
            master.events.WorkerConnected.dispatch(with: self.id)
            
            // Corpus synchronization
            master.events.InterestingProgramFound.observe { ev in
                let program = ev.program.copy()
                worker.queue.addOperation {
                    worker.importProgram(program)
                }
            }
        }
        
        // Access to classes appears to be thread-safe...
        // TODO the programs should potentially be deep-copied, otherwise there will
        // be Operation instances used by multiple threads.
        worker.events.CrashFound.observe { ev in
            let program = ev.program.copy()
            master.queue.addOperation {
                master.importCrash(program)
            }
        }
        
        worker.events.InterestingProgramFound.observe { ev in
            let program = ev.program.copy()
            master.queue.addOperation {
                master.importProgram(program)
            }
        }
        
        worker.events.Log.observe { ev in
            master.queue.addOperation {
                master.events.Log.dispatch(with: ev)
            }
        }
        
        // Regularly send local statistics to the master
        if let stats = Statistics.instance(for: worker) {
            worker.timers.scheduleTask(every: 60 * Seconds) {
                let data = stats.compute()
                master.queue.addOperation {
                    Statistics.instance(for: master)?.importData(data, from: self.id)
                }
            }
        }
    }
}
