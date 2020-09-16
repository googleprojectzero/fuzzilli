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
    public func execute(_ program: Program, stats: inout ProgramGeneratorStats) -> ExecutionOutcome {
        fuzzer.dispatchEvent(fuzzer.events.ProgramGenerated, data: program)

        let execution = fuzzer.execute(program)

        switch execution.outcome {
            case .crashed(let termsig):
                fuzzer.processCrash(program, withSignal: termsig, withStderr: execution.stderr, origin: .local)

            case .succeeded:
                fuzzer.dispatchEvent(fuzzer.events.ValidProgramFound, data: program)
                if let aspects = fuzzer.evaluator.evaluate(execution) {
                    fuzzer.processInteresting(program, havingAspects: aspects, origin: .local)
                }
                stats.producedValidSample()

            case .failed(_):
                if self.fuzzer.config.enableDiagnostics {
                    program.comments.add("Stdout:\n" + execution.stdout, at: .footer)
                }
                fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
                stats.producedInvalidSample()

            case .timedOut:
                fuzzer.dispatchEvent(fuzzer.events.TimeOutFound, data: program)
                stats.producedInvalidSample()
        }

        return execution.outcome
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
}
