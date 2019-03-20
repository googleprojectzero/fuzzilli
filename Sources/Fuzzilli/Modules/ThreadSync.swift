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
    
    /// Number of programs already imported from the master's corpus.
    private var numImportedPrograms = 0
    
    /// UUID of this instance.
    let id: UUID
    
    public init(worker: Fuzzer, master: Fuzzer) {
        self.master = master
        self.id = UUID()
        
        let logger = worker.makeLogger(withLabel: "Worker")
        
        // "Identify" with the master.
        master.queue.async {
            dispatchEvent(master.events.WorkerConnected, data: self.id)
        }
        
        // Access to classes appears to be thread-safe...
        // TODO the programs should potentially be deep-copied, otherwise there will
        // be Operation instances used by multiple threads.
        addEventListener(for: worker.events.CrashFound) { ev in
            let program = ev.program.copy()
            master.queue.async {
                master.importCrash(program)
            }
        }
        
        addEventListener(for: worker.events.InterestingProgramFound) { ev in
            let program = ev.program.copy()
            master.queue.async {
                master.importProgram(program)
            }
        }
        
        addEventListener(for: worker.events.Log) { ev in
            master.queue.async {
                dispatchEvent(master.events.Log, data: ev)
            }
        }
        
        // Regularly pull new programs from the master.
        worker.timers.scheduleTask(every: 15 * Minutes) {
            let skip = self.numImportedPrograms
            master.queue.async {
                var corpus = [Program]()
                for program in master.corpus.export().dropFirst(skip) {
                    corpus.append(program.copy())
                }
                worker.queue.async {
                    worker.importCorpus(corpus, withDropout: true)
                    logger.info("Imported \(corpus.count) programs from master")
                    self.numImportedPrograms += corpus.count
                }
            }
        }
        
        // Regularly send local statistics to the master
        if let stats = Statistics.instance(for: worker) {
            worker.timers.scheduleTask(every: 60 * Seconds) {
                let data = stats.compute()
                master.queue.async {
                    Statistics.instance(for: master)?.importData(data, from: self.id)
                }
            }
        }
    }
}
