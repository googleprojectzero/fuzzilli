// Copyright 2023 Google LLC
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

/// A mutator that uses runtime feedback to perform smart(er) mutations.
///
/// A runtime assisted-mutator will generally perform the following steps:
/// 1. Instrument the program to mutate in some way, usually by inserting special operations.
/// 2. Execute the instrumented program and collect its output through the fuzzout channel.
/// 3. Process the output from step 2. to perform smarter mutations and generate the final program.
///
/// See the ExplorationMutator or ProbingMutator for examples of runtime-assisted mutators.
public class RuntimeAssistedMutator: Mutator {
    let logger: Logger

    // Whether to enable verbose logging. Mostly useful for development/debugging.
    let verbose: Bool

    // The different outcomes of exploration. Used for statistics in verbose mode.
    enum Outcome: String, CaseIterable {
        case success = "Success"
        case cannotInstrument = "Cannot instrument input"
        case instrumentedProgramFailed = "Instrumented program failed"
        case instrumentedProgramTimedOut = "Instrumented program timed out"
        case noResults = "No results received"
        case unexpectedError = "Unexpected Error"
    }
    private var outcomeCounts = [Outcome: Int]()

    // The number of programs produced so far, mostly used for the verbose mode.
    private var producedSamples = 0

    public init(_ name: String, verbose: Bool = false) {
        self.logger = Logger(withLabel: name)
        self.verbose = verbose

        if verbose {
            for outcome in Outcome.allCases {
                outcomeCounts[outcome] = 0
            }
        }
    }

    // Instrument the given program.
    func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        fatalError("Must be overwritten by child classes")
    }

    // Process the runtime output of the instrumented program and build the final program from that.
    func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, Outcome) {
        fatalError("Must be overwritten by child classes")
    }

    func logAdditionalStatistics() {
        // May be overwritten by child classes
    }

    override final func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        // Build the instrumented program.
        guard let instrumentedProgram = instrument(program, for: fuzzer) else {
            return failure(.cannotInstrument)
        }

        // We currently assume that instrumenting will add internal operations to a program.
        assert(instrumentedProgram.code.contains(where: { $0.op is JsInternalOperation }))

        // Execute the instrumented program (with a higher timeout) and collect the output.
        let execution = fuzzer.execute(instrumentedProgram, withTimeout: fuzzer.config.timeout * 2)
        switch execution.outcome {
        case .failed(_):
            // We generally do not expect the instrumentation code itself to cause runtime exceptions. Even if it performs new actions those should be guarded with try-catch.
            // However, failures can still happen for various reasons, for example when the instrumented program performs new actions that cause subsequent code to raise an exception.
            // Examples include detaching an ArrayBufer, rejecting a Promise, or even just modifying an object so that it can no longer be processed in a certain way
            // (for example by something like JSON.stringify, or when changing a method to a property, or when installing a property accessor that throws, etc.).
            // In these cases, an exception will potentially be raised later on in the program, leading to a failed execution. Failed executions are therefore expected to some
            // degree, but if the failure rate appears unreasonably high, one could log the failing program here.
            return failure(.instrumentedProgramFailed)
        case .timedOut:
            // Similar to the above case, this is expected to some degree.
            return failure(.instrumentedProgramTimedOut)
        case .crashed(let signal):
            // This is also somewhat unexpected, but can happen, generally for one of two reasons:
            // 1. The instrumented code performs new actions (e.g. in case of the ExplorationMutator) and those cause a crash
            // 2. Some part of the instrumentation logic caused a crash. For example, if an object is already in an inconsistent state, inspecting it may cause a crash
            // In this case we still try to process the instrumentation output (if any) and produce the final, uninstrumented program
            // so that we obtain reliable testcase for crashes due to (1). However, to not loose crashes due to (2), we also
            // report the instrumented program as crashing here. We may therefore end up with two crashes from one mutation.
            let stdout = execution.fuzzout + "\n" + execution.stdout
            fuzzer.processCrash(instrumentedProgram, withSignal: signal, withStderr: execution.stderr, withStdout: stdout, origin: .local, withExectime: execution.execTime)
        case .succeeded:
            // The expected case.
            break
        }

        // Process the output to build the mutated program.
        let (maybeMutatedProgram, outcome) = process(execution.fuzzout, ofInstrumentedProgram: instrumentedProgram, using: b)
        guard let mutatedProgram = maybeMutatedProgram else {
            assert(outcome != .success)
            return failure(outcome)
        }
        assert(outcome == .success)

        // Potentially log verbose statistics.
        producedSamples += 1
        if verbose && (producedSamples % 1000) == 0 {
            let totalOutcomes = outcomeCounts.values.reduce(0, +)
            logger.verbose("Frequencies of outcomes:")
            for outcome in Outcome.allCases {
                let count = outcomeCounts[outcome]!
                let frequency = (Double(count) / Double(totalOutcomes)) * 100.0
                logger.verbose("    \(outcome.rawValue.rightPadded(toLength: 30)): \(String(format: "%.2f%%", frequency))")
            }

            logAdditionalStatistics()
        }

        // All finished!
        return success(mutatedProgram)
    }

    private func failure(_ outcome: Outcome) -> Program? {
        assert(outcome != .success)
        outcomeCounts[outcome]! += 1
        return nil
    }

    private func success(_ program: Program) -> Program {
        outcomeCounts[.success]! += 1
        return program
    }
}
