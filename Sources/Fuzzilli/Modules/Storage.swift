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
    private let corpusDir: String
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
        self.corpusDir = storageDir + "/corpus"
        self.failedDir = storageDir + "/failed"
        self.timeOutDir = storageDir + "/timeouts"
        self.statisticsDir = storageDir + "/stats"
        self.stateFile = storageDir + "/state.bin"
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
            try FileManager.default.createDirectory(atPath: corpusDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(atPath: statisticsDir, withIntermediateDirectories: true)
            if fuzzer.config.enableDiagnostics {
                try FileManager.default.createDirectory(atPath: failedDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: timeOutDir, withIntermediateDirectories: true)
                try FileManager.default.createDirectory(atPath: diagnosticsDir, withIntermediateDirectories: true)
            }
        } catch {
            logger.fatal("Failed to create storage directories. Is \(storageDir) writable by the current user?")
        }

        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            let filename = "program_\(ev.program.id)_\(ev.behaviour.rawValue)_\(ev.signal)"
            if ev.isUnique {
                self.storeProgram(ev.program, as: filename, in: self.crashesDir)
            } else {
                self.storeProgram(ev.program, as: filename, in: self.duplicateCrashesDir)
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            let filename = "program_\(ev.program.id)"
            self.storeProgram(ev.program, as: filename, in: self.corpusDir)
        }

        if fuzzer.config.enableDiagnostics {
            fuzzer.registerEventListener(for: fuzzer.events.DiagnosticsEvent) { ev in
                let filename = "/\(ev.name)_\(String(currentMillis()))"
                let url = URL(fileURLWithPath: self.diagnosticsDir + filename + ".diag")
                self.createFile(url, withContent: ev.content)
            }

            fuzzer.registerEventListener(for: fuzzer.events.InvalidProgramFound) { program in
                let filename = "program_\(program.id)"
                self.storeProgram(program, as: filename, in: self.failedDir)
            }

            fuzzer.registerEventListener(for: fuzzer.events.TimeOutFound) { program in
                let filename = "program_\(program.id)"
                self.storeProgram(program, as: filename, in: self.timeOutDir)
            }
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

    private func createFile(_ url: URL, withContent content: String) {
        do {
            try content.write(to: url, atomically: false, encoding: String.Encoding.utf8)
        } catch {
            logger.error("Failed to write file \(url): \(error)")
        }
    }

    private func storeProgram(_ program: Program, as filename: String, in directory: String) {
        // Always include comments when writing programs to disk
        var options = LiftingOptions.includeComments

        // If enabled, also include type information
        if fuzzer.config.inspection.contains(.types) {
            options.insert(.dumpTypes)
        }

        let code = fuzzer.lifter.lift(program, withOptions: options)
        let url = URL(fileURLWithPath: "\(directory)/\(filename).js")
        createFile(url, withContent: code)

        // If inspection is enabled, we also include the programs ancestor chain in a separate .history file
        if fuzzer.config.inspection.contains(.history) && program.parent != nil {
            let lifter = FuzzILLifter()

            var ancestors: [Program] = []
            var current: Program? = program
            while current != nil {
                ancestors.append(current!)
                current = current?.parent
            }
            ancestors.reverse()

            var content = ""
            for program in ancestors {
                content += "// ===== [ Program \(program.id) ] =====\n"
                content += lifter.lift(program, withOptions: options) + "\n\n"
            }

            let url = URL(fileURLWithPath: "\(directory)/\(filename).fuzzil.history")
            createFile(url, withContent: content)
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
