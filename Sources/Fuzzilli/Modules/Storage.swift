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
    private let storageDir: String
    private let crashesDir: String
    private let duplicateCrashesDir: String
    private let interestingDir: String
    private let statisticsDir: String
    private let stateFile: String
    private let failedDir: String
    private let timeOutDir: String
    private let diagnosticsDir: String

    private let stateExportInterval: Double?
    private let statisticsExportInterval: Double?

    private unowned let fuzzer: Fuzzer
    private let logger: Logger

    public init(for fuzzer: Fuzzer, storageDir: String, stateExportInterval: Double? = nil, statisticsExportInterval: Double? = nil) {
        self.storageDir = storageDir
        self.crashesDir = storageDir + "/crashes"
        self.duplicateCrashesDir = storageDir + "/crashes/duplicates"
        self.interestingDir = storageDir + "/interesting"
        self.failedDir = storageDir + "/failed"
        self.timeOutDir = storageDir + "/timeouts"
        self.statisticsDir = storageDir + "/stats"
        self.stateFile = storageDir + "/state.json"
        self.diagnosticsDir = storageDir + "/diagnostics"

        self.stateExportInterval = stateExportInterval
        self.statisticsExportInterval = statisticsExportInterval

        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "Storage")
    }

    public func initialize(with fuzzer: Fuzzer) {
        do {
            try FileManager.default.createDirectory(atPath: crashesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: duplicateCrashesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: interestingDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: statisticsDir, withIntermediateDirectories: true)
            if fuzzer.config.diagnostics {
                try FileManager.default.createDirectory(atPath: failedDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: timeOutDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: diagnosticsDir, withIntermediateDirectories: true)
            }
        } catch {
            logger.fatal("Failed to create storage directories. Is \(storageDir) writable by the current user?")
        }

        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            let filename = "crash_\(String(currentMillis()))_\(ev.behaviour.rawValue)_\(ev.signal).js"
            let fileURL: URL
            if ev.isUnique {
                fileURL = URL(fileURLWithPath: "\(self.crashesDir)/\(filename)")
            } else {
                fileURL = URL(fileURLWithPath: "\(self.duplicateCrashesDir)/\(filename)")
            }
            let code = fuzzer.lifter.lift(ev.program)
            self.storeProgram(code, to: fileURL)
        }

        if fuzzer.config.diagnostics {
            fuzzer.registerEventListener(for: fuzzer.events.DiagnosticsEvent) { ev in
                let filename = "/\(ev.name)_\(String(currentMillis()))"
                let fileURL = URL(fileURLWithPath: self.diagnosticsDir + filename)
                self.storeProgram(ev.content, to: fileURL)
            }

            fuzzer.registerEventListener(for: fuzzer.events.InvalidProgramFound) { program in
                let filename = "invalid_\(String(currentMillis())).js"
                let fileURL = URL(fileURLWithPath: "\(self.failedDir)/\(filename)")
                let code = fuzzer.lifter.lift(program, withOptions: .dumpTypes)
                self.storeProgram(code, to: fileURL)
            }

            fuzzer.registerEventListener(for: fuzzer.events.TimeOutFound) { program in
                let filename = "timeout_\(String(currentMillis())).js"
                let fileURL = URL(fileURLWithPath: "\(self.timeOutDir)/\(filename)")
                let code = fuzzer.lifter.lift(program, withOptions: .dumpTypes)
                self.storeProgram(code, to: fileURL)
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            let filename = "sample_\(String(currentMillis())).js"
            let fileURL = URL(fileURLWithPath: "\(self.interestingDir)/\(filename)")
            let code = fuzzer.lifter.lift(ev.program, withOptions: .dumpTypes)
            self.storeProgram(code, to: fileURL)
        }

        // If enabled, export the current fuzzer state to disk in regular intervals.
        if let interval = stateExportInterval {
            fuzzer.timers.scheduleTask(every: interval, saveState)
            fuzzer.registerEventListener(for: fuzzer.events.Shutdown, listener: saveState)
        }

        // If enabled, export fuzzing statistics to disk in regular intervals.
        if let interval = statisticsExportInterval {
            guard let stats = Statistics.instance(for: fuzzer) else {
                logger.fatal("Requested stats export but not Statistics module is active")
            }
            fuzzer.timers.scheduleTask(every: interval) { self.saveStatistics(stats) }
            fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { self.saveStatistics(stats) }
        }
    }

    private func storeProgram(_ code: String, to url: URL) {
        do {
            try code.write(to: url, atomically: false, encoding: String.Encoding.utf8)
        } catch {
            logger.error("Failed to write program to disk: \(error)")
        }
    }

    private func saveState() {
        do {
            let state = try fuzzer.exportState()
            let url = URL(fileURLWithPath: self.stateFile)
            try state.write(to: url)
        } catch {
            logger.error("Failed to write state to disk: \(error)")
        }
    }

    private func saveStatistics(_ stats: Statistics) {
        let statsData = stats.compute()

        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        let datetime = formatter.string(from: Date())

        do {
            let data = try statsData.jsonUTF8Data()
            let url = URL(fileURLWithPath: "\(self.statisticsDir)/\(datetime).json")
            try data.write(to: url)
        } catch {
            logger.error("Failed to write statistics to disk: \(error)")
        }
    }
}
