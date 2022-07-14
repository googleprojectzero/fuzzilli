// Copyright 2020 Google LLC
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

/// Number of instructions that should be generated in a program prefix
let programPrefixSize = 5

public protocol FuzzEngine: ComponentBase {
    // Performs a single round of fuzzing using the engine.
    func fuzzOne(_ group: DispatchGroup)
}

extension FuzzEngine {
    public func execute(_ program: Program, stats: inout ProgramGeneratorStats) -> ExecutionOutcome {
        fuzzer.dispatchEvent(fuzzer.events.ProgramGenerated, data: program)

        let execution = fuzzer.execute(program)

        switch execution.outcome {
            case .crashed(let termsig):
                fuzzer.processCrash(program, withSignal: termsig, withStderr: execution.stderr, origin: .local) 
                let newCoverage = fuzzer.evaluator.newCoverageFound
                fuzzer.evaluateSuccessForSelectedMutator(newCoverageFound: newCoverage)

            case .succeeded:
                fuzzer.dispatchEvent(fuzzer.events.ValidProgramFound, data: program)
                if let aspects = fuzzer.evaluator.evaluate(execution) {
                    if fuzzer.config.inspection.contains(.history) {
                        program.comments.add("Program is interesting due to \(aspects)", at: .footer)
                    }
                    fuzzer.processInteresting(program, havingAspects: aspects, origin: .local)
                    let newCoverage = fuzzer.evaluator.newCoverageFound
                    fuzzer.evaluateSuccessForSelectedMutator(newCoverageFound: newCoverage)
                }
                stats.producedValidSample()

            case .failed(_):
                if fuzzer.config.enableDiagnostics {
                    program.comments.add("Stdout:\n" + execution.stdout, at: .footer)
                }
                fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
                stats.producedInvalidSample()

            case .timedOut:
                fuzzer.dispatchEvent(fuzzer.events.TimeOutFound, data: program)
                stats.producedInvalidSample()
        }

        if fuzzer.config.enableDiagnostics {
            // Ensure deterministic execution behaviour. This can for example help detect and debug REPRL issues.
            ensureDeterministicExecutionOutcomeForDiagnostic(of: program)
        }

        return execution.outcome
    }

    /// Generate some basic Prefix such that samples have some basic types available.
    public func generateProgramPrefix() -> Program {
        let b = fuzzer.makeBuilder(mode: .conservative)

        for _ in 1...programPrefixSize {
            let generator = chooseUniform(from: fuzzer.trivialCodeGenerators)
            b.run(generator)
        }

        let prefixProgram = b.finalize()

        fuzzer.updateTypeInformation(for: prefixProgram)

        return prefixProgram
    }

    private func ensureDeterministicExecutionOutcomeForDiagnostic(of program: Program) {
        let execution1 = fuzzer.execute(program)
        let stdout1 = execution1.stdout, stderr1 = execution1.stderr
        let execution2 = fuzzer.execute(program)
        switch (execution1.outcome, execution2.outcome) {
        case (.succeeded, .failed(_)),
             (.failed(_), .succeeded):
            let stdout2 = execution2.stdout, stderr2 = execution2.stderr
            logger.warning("""
                Non-deterministic execution detected for program
                \(fuzzer.lifter.lift(program))
                // Stdout of first execution
                \(stdout1)
                // Stderr of first execution
                \(stderr1)
                // Stdout of second execution
                \(stdout2)
                // Stderr of second execution
                \(stderr2)
                """)
        default:
            break
        }
    }
}
