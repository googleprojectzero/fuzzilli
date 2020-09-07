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
    
    /// Enable "speed test" mode.
    /// In that mode, the fuzzer runs as normal, but all programs
    /// scheduled for execution are replaced by a predefined program.
    /// This provides consistent execution speed of the generated samples
    /// and is useful for evaluating the performance of the fuzzer itself.
    public let speedTestMode: Bool
    
    /// Log level to use.
    public let logLevel: LogLevel
    
    /// Code snippets that cause an observable crash in the target engine.
    /// Used to verify that crashes can be detected.
    public let crashTests: [String]
    
    /// Is this instance configured to run as a master?
    public let isMaster: Bool
    
    /// Is this instance configured to run as a worker?
    public let isWorker: Bool
    
    /// Whether this instance fuzzes (i.e. generates new samples, executes, then evaulates them).
    /// This flag is true by default, so all instances, regardless of whether they run standalone, as
    /// master or as worker, perform fuzzing. However, it can make sense to configure master
    /// instances to not perform fuzzing tasks so they can concentrate on the synchronization of
    /// their workers and ensure smooth communication.
    public let isFuzzing: Bool

    /// The minimum number of instructions that programs which are put into the corpus should have.
    /// This setting is useful to avoid "over-minimization", which can negatively impact the fuzzer's
    /// performance if program features are removed that could later be mutated to trigger new
    /// interesting behaviour or crashes.
    /// See Minimizer.swift for the exact algorithm used to implement this.
    public let minimizationLimit: UInt
    
    /// When importing programs from a master instance, discard this percentage of samples.
    ///
    /// Dropout can provide a way to make multiple instances less "similar" to each
    /// other as it forces them to (re)discover edges in a different way.
    public let dropoutRate: Double
    
    /// Abstractly interpret the generated FuzzIL programs to compute static type information.
    /// This is used by code generators to produce valid code as much as possible. However,
    /// it is a performance overhead and is also imprecise as the execution semantics of FuzzIL
    /// and the target language are not strictly the same.
    /// As an example, FuzzIL does not have the concept of JS prototypes, so operations on prototype
    /// objects aren't correctly handled.
    /// This configuration option makes it possible to disable the abstract interpretation. In that
    /// case, all variables will have the .unknown type and code generators will fall back to
    /// picking random variables as inputs.
    public let useAbstractInterpretation: Bool

    public let collectRuntimeTypes: Bool

    /// Enable the saving of programs that failed or timed-out during execution.
    public let diagnostics: Bool
    
    public init(timeout: UInt32 = 250,
                skipStartupTests: Bool = false,
                speedTestMode: Bool = false,
                logLevel: LogLevel = .info,
                crashTests: [String] = [],
                isMaster: Bool = false,
                isWorker: Bool = false,
                isFuzzing: Bool = true,
                minimizationLimit: UInt = 0,
                dropoutRate: Double = 0,
                useAbstractInterpretation: Bool = true,
                collectRuntimeTypes: Bool = false,
                diagnostics: Bool = false) {
        self.timeout = timeout
        self.speedTestMode = speedTestMode
        self.logLevel = logLevel
        self.crashTests = crashTests
        self.isMaster = isMaster
        self.isWorker = isWorker
        self.isFuzzing = isFuzzing
        self.dropoutRate = dropoutRate
        self.minimizationLimit = minimizationLimit
        self.useAbstractInterpretation = useAbstractInterpretation
        self.collectRuntimeTypes = collectRuntimeTypes
        self.diagnostics = diagnostics
    }
}
