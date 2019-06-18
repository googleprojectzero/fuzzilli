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

/// Module to store programs to disk.
public class Storage: Module {
    private let crashesDir: String
    private let duplicateCrashesDir: String
    private let interestingDir: String
    private let stateFile: String
    
    private let stateExportInterval: Double?
    
    private unowned let fuzzer: Fuzzer
    private let logger: Logger
    
    public init(for fuzzer: Fuzzer, storageDir: String, stateExportInterval: Double? = nil) {
        self.crashesDir = storageDir + "/crashes"
        self.duplicateCrashesDir = storageDir + "/crashes/duplicates"
        self.interestingDir = storageDir + "/interesting"
        self.stateFile = storageDir + "/state.json"
        
        self.stateExportInterval = stateExportInterval
        
        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "Storage")

        do {
            try FileManager.default.createDirectory(atPath: crashesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: duplicateCrashesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: interestingDir, withIntermediateDirectories: true)
        } catch {
            logger.fatal("Failed to create storage directories. Is \(storageDir) writable by the current user?")
        }
    }
    
    public func initialize(with fuzzer: Fuzzer) {
       fuzzer.events.CrashFound.observe { ev in
            let filename = "crash_\(String(currentMillis()))_\(ev.pid)_\(ev.behaviour.rawValue)_\(ev.signal).js"
            let fileURL: URL
            if ev.isUnique {
                fileURL = URL(fileURLWithPath: "\(self.crashesDir)/\(filename)")
            } else {
                fileURL = URL(fileURLWithPath: "\(self.duplicateCrashesDir)/\(filename)")
            }
            
            self.storeProgram(ev.program, to: fileURL)
        }
        
        fuzzer.events.InterestingProgramFound.observe { ev in
            let filename = "sample_\(String(currentMillis())).js"
            let fileURL = URL(fileURLWithPath: "\(self.interestingDir)/\(filename)")
            self.storeProgram(ev.program, to: fileURL)
        }
        
        // If enabled, export the current fuzzer state to disk in regular intervals.
        if let interval = stateExportInterval {
            fuzzer.timers.scheduleTask(every: interval, saveState)
            fuzzer.events.Shutdown.observe(saveState)
        }
    }
    
    private func storeProgram(_ program: Program, to url: URL) {
        let code = fuzzer.lifter.lift(program)
        
        do {
            try code.write(to: url, atomically: false, encoding: String.Encoding.utf8)
        } catch {
            logger.error("Failed to write program to disk: \(error)")
        }
    }

    private func saveState() {
        let state = fuzzer.exportState()
        let encoder = JSONEncoder()

        do {
            let data = try encoder.encode(state)
            let url = URL(fileURLWithPath: self.stateFile)
            try data.write(to: url)
        } catch {
            logger.error("Failed to write state to disk: \(error)")
        }
    }
}
