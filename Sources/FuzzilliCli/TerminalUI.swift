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
import Fuzzilli

let Seconds = 1.0
let Minutes = 60.0 * Seconds
let Hours   = 60.0 * Minutes

// A very basic terminal UI.
class TerminalUI {
    init(for fuzzer: Fuzzer) {
        // Event listeners etc. have to be registered on the fuzzer's queue
        fuzzer.queue.addOperation {
            self.initOnFuzzerQueue(fuzzer)
            
        }
    }
    
    func initOnFuzzerQueue(_ fuzzer: Fuzzer) {
        // Register log event listener now to be able to print log messages
        // generated during fuzzer initialization
        fuzzer.events.Log.observe { (creator, level, label, msg) in
            let color = self.colorForLevel[level]!
            if creator == fuzzer.id {
                print("\u{001B}[0;\(color.rawValue)m[\(label)] \(msg)\u{001B}[0;\(Color.reset.rawValue)m")
            } else {
                // Mark message as coming from a worker by including its id
                let shortId = creator.uuidString.split(separator: "-")[0]
                print("\u{001B}[0;\(color.rawValue)m[\(shortId):\(label)] \(msg)\u{001B}[0;\(Color.reset.rawValue)m")
            }
        }
        
        fuzzer.events.CrashFound.observe { crash in
            if crash.isUnique {
                print("########## Unique Crash Found ##########")
                print(fuzzer.lifter.lift(crash.program))
            }
        }
        
        // Do everything else after fuzzer initialization finished
        fuzzer.events.Initialized.observe {
            if let stats = Statistics.instance(for: fuzzer) {
                fuzzer.events.Shutdown.observe {
                    print("\n++++++++++ Fuzzer Finished ++++++++++\n")
                    self.printStats(stats.compute(), of: fuzzer)
                }
                
                // We could also run our own timer on the main queue instead if we want to
                fuzzer.timers.scheduleTask(every: 60 * Seconds) {
                    self.printStats(stats.compute(), of: fuzzer)
                    print()
                }
            }
        }
    }
    
    func printStats(_ stats: Statistics.Data, of fuzzer: Fuzzer) {
        print("""
        Fuzzer Statistics
        -----------------
        Total Samples:                \(stats.totalSamples)
        Interesting Samples Found:    \(stats.interestingSamples)
        Valid Samples Found:          \(stats.validSamples)
        Corpus Size:                  \(fuzzer.corpus.size)
        Success Rate:                 \(String(format: "%.2f%%", stats.successRate * 100))
        Timeout Rate:                 \(String(format: "%.2f%%", stats.timeoutRate * 100))
        Crashes Found:                \(stats.crashingSamples)
        Timeouts Hit:                 \(stats.timedOutSamples)
        Coverage:                     \(String(format: "%.2f%%", stats.coverage * 100))
        Avg. program size:            \(String(format: "%.2f", stats.avgProgramSize))
        Connected workers:            \(stats.numWorkers)
        Execs / Second:               \(String(format: "%.2f", stats.execsPerSecond))
        Total Execs:                  \(stats.totalExecs)
        """)
    }
    
    private enum Color: Int {
        case reset   = 0
        case black   = 30
        case red     = 31
        case green   = 32
        case yellow  = 33
        case blue    = 34
        case magenta = 35
        case cyan    = 36
        case white   = 37
    }
    
    // The color with which to print log entries.
    private let colorForLevel: [LogLevel: Color] = [
        .verbose: .cyan,
        .info:    .white,
        .warning: .yellow,
        .error:   .magenta,
        .fatal:   .red
    ]
}
