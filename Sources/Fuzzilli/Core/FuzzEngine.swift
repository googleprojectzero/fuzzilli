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

public protocol FuzzEngine: ComponentBase {
    // Performs a single round of fuzzing using the engine.
    func fuzzOne(_ group: DispatchGroup)
}

extension FuzzEngine {
    public func execute(_ program: Program, stats: inout ProgramGeneratorStats) -> [ExecutionOutcome] {
        fuzzer.dispatchEvent(fuzzer.events.ProgramGenerated, data: program)

        let executions = fuzzer.execute(program)

        if fuzzer.config.enableDiagnostics {
            // Ensure deterministic execution behaviour. This can for example help detect and debug REPRL issues.
            ensureDeterministicExecutionBehaviour(of: program, firstExecutions: executions)
        }

        var aspects = [ProgramAspects?]()
        var termsigs = [Int?]()
        var didSucceed = false
        var didTimeOut = true

        for (idx, execution) in executions.enumerated() {
            aspects.append(nil)
            termsigs.append(nil)

            switch execution.outcome {
                case .crashed(let termsig):
                    didTimeOut = false
                    termsigs[idx] = termsig

                case .succeeded:
                    didSucceed = true
                    didTimeOut = false
                    aspects[idx] = fuzzer.runners[idx].evaluator.evaluate(execution)
                    if let programAspects = aspects[idx] {
                        if fuzzer.config.inspection.contains(.history) {
                            program.comments.add("Program is interesting due to \(programAspects) in engine at \(idx)", at: .footer)
                        }
                    }

                case .failed(_):
                    didTimeOut = false
                    if fuzzer.config.enableDiagnostics {
                        program.comments.add("Stdout\(idx):\n" + executions[idx].stdout, at: .footer)
                    }

                case .timedOut:
                    break
            }

        }

        if termsigs.compactMap({$0}).count > 0 {
            fuzzer.processCrash(program,
                                withSignals: termsigs,
                                withStderrs: executions.map { $0.stderr },
                                origin: .local,
                                engineIdx: (0..<executions.count).map { termsigs[$0] != nil ? $0 : nil }
            )
        }

        if didSucceed {
            fuzzer.dispatchEvent(fuzzer.events.ValidProgramFound, data: program)
            fuzzer.processInteresting(program, havingAspects: aspects, origin: .local)
            stats.producedValidSample()
        } else {
            fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
            stats.producedInvalidSample()
        }

        if didTimeOut {
            fuzzer.dispatchEvent(fuzzer.events.TimeOutFound, data: program)
            stats.producedInvalidSample()
        }

        return executions.map { $0.outcome }
    }

    /// Generate some basic Prefix such that samples have some basic types available.
    public func generateProgramPrefix() -> Program {
        let b = fuzzer.makeBuilder(mode: .conservative)

        let programPrefixGenerators: [CodeGenerator] = [
            CodeGenerators.get("IntegerGenerator"),
            CodeGenerators.get("StringGenerator"),
            CodeGenerators.get("BuiltinGenerator"),
            CodeGenerators.get("FloatArrayGenerator"),
            CodeGenerators.get("IntArrayGenerator"),
            CodeGenerators.get("ArrayGenerator"),
            CodeGenerators.get("ObjectGenerator"),
            CodeGenerators.get("ObjectGenerator"),
        ]

        for generator in programPrefixGenerators {
            b.run(generator)
        }

        let prefixProgram = b.finalize()

        fuzzer.updateTypeInformation(for: prefixProgram)

        return prefixProgram
    }

    private func ensureDeterministicExecutionBehaviour(of program: Program, firstExecutions executions1: [Execution]) {
        let stdouts1 = executions1.map { $0.stdout }
        let stderrs1 = executions1.map { $0.stderr }
        let executions2 = fuzzer.execute(program)
        assert(executions1.count == executions2.count)
        for (idx, (execution1, execution2)) in zip(executions1, executions2).enumerated() {
            switch (execution1.outcome, execution2.outcome) {
            case (.succeeded, .failed(_)),
                 (.failed(_), .succeeded):
                let stdout2 = execution2.stdout, stderr2 = execution2.stderr
                logger.warning("""
                    Non-deterministic execution detected for program
                    \(fuzzer.runners[idx].lifter.lift(program))
                    // Stdout of first execution
                    \(stdouts1[idx])
                    // Stderr of first execution
                    \(stderrs1[idx])
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
}
