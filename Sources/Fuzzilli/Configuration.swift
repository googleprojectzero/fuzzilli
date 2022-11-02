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

public struct Configuration {
    /// Timeout in milliseconds after which child processes will be killed.
    public let timeout: UInt32

    /// Log level to use.
    public let logLevel: LogLevel

    /// Code snippets that cause an observable crash in the target engine.
    /// Used to verify that crashes can be detected.
    public let crashTests: [String]

    /// Whether this instance fuzzes (i.e. generates new samples, executes, then evaulates them).
    /// This flag is true by default, so all instances, regardless of whether they run standalone, as
    /// master or as worker, perform fuzzing. However, it can make sense to configure master
    /// instances to not perform fuzzing tasks so they can concentrate on the synchronization of
    /// their workers and ensure smooth communication.
    public let isFuzzing: Bool

    /// The fraction of instruction to keep from the original program when minimizing.
    /// This setting is useful to avoid "over-minimization", which can negatively impact the fuzzer's
    /// performance if program features are removed that could later be mutated to trigger new
    /// interesting behaviour or crashes.
    /// See Minimizer.swift for the exact algorithm used to implement this.
    public let minimizationLimit: Double

    /// When importing programs from a master instance, discard this percentage of samples.
    ///
    /// Dropout can provide a way to make multiple instances less "similar" to each
    /// other as it forces them to (re)discover edges in a different way.
    public let dropoutRate: Double

    /// Enable the saving of programs that failed or timed-out during execution.
    public let enableDiagnostics: Bool

    /// Whether to enable inspection for generated programs. If enabled, a full record
    /// of the steps that led to a particular program will be kept. In particular, a programs
    /// ancestor chain (the programs that were mutated to arrive at the current program)
    /// is recorded as well as the exact list of mutations and code generations, as well
    /// as the reductions performed by the minimizer.
    public let enableInspection: Bool

    public init(timeout: UInt32 = 250,
                skipStartupTests: Bool = false,
                logLevel: LogLevel = .info,
                crashTests: [String] = [],
                isFuzzing: Bool = true,
                minimizationLimit: Double = 0.0,
                dropoutRate: Double = 0,
                collectRuntimeTypes: Bool = false,
                enableDiagnostics: Bool = false,
                enableInspection: Bool = false) {
        self.timeout = timeout
        self.logLevel = logLevel
        self.crashTests = crashTests
        self.isFuzzing = isFuzzing
        self.dropoutRate = dropoutRate
        self.minimizationLimit = minimizationLimit
        self.enableDiagnostics = enableDiagnostics
        self.enableInspection = enableInspection
    }
}

public struct InspectionOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // When writing programs to disk, their "history", describing in detail
    // how the program was generated through mutations, code generation, and
    // minimization, is included in .fuzzil.history files.
    public static let history = InspectionOptions(rawValue: 1 << 0)

    public static let all = InspectionOptions([.history])
}
