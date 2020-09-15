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

public class HybridEngine: ComponentBase, FuzzEngine {
    // TODO: make these configurable
    private let mutationRoundsPerSample: Int
    private let spliceAndMutationRoundsPerSample: Int

    // The number of mutations to perform to a single sample per round
    private let numConsecutiveMutations: Int

    public init(numConsecutiveMutations: Int) {
        self.mutationRoundsPerSample = 2
        self.spliceAndMutationRoundsPerSample = 2
        self.numConsecutiveMutations = numConsecutiveMutations

        super.init(name: "HybridEngine")
    }

    override func initialize() {
    }

    private func generateTemplateProgram(mode: ProgramBuilder.Mode = .conservative) -> Program {
        let b = fuzzer.makeBuilder(mode: mode)

        b.run(CodeGenerators.get("PlainFunctionGenerator"))

        let baseTemplate = CodeTemplates.randomElement()

        b.run(baseTemplate)

        return b.finalize()
    }

    private func execute(_ program: Program) -> ExecutionOutcome {
        fuzzer.dispatchEvent(fuzzer.events.ProgramGenerated, data: program)

        let execution = fuzzer.execute(program)

        switch execution.outcome {
            case .crashed(let termsig):
                var code = program.code
                code.append(Instruction(Comment(execution.stderr)))
                let program = Program(with: code)
                fuzzer.processCrash(program, withSignal: termsig, isImported: false)

            case .succeeded:
                fuzzer.dispatchEvent(fuzzer.events.ValidProgramFound, data: program)
                if let aspects = fuzzer.evaluator.evaluate(execution) {
                    fuzzer.processInteresting(program, havingAspects: aspects, isImported: false, shouldMinimize: true)
                }

            case .failed(_):
                if self.fuzzer.config.diagnostics {
                    var code = program.code
                    code.append(Instruction(Comment(execution.stdout)))
                    let program = Program(with: code)
                    fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
                } else {
                    fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
                }

            case .timedOut:
                fuzzer.dispatchEvent(fuzzer.events.TimeOutFound, data: program)
        }

        return execution.outcome
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let program = generateTemplateProgram()

        let outcome = execute(program)

        guard outcome == .succeeded else {
            return
        }

        let b = fuzzer.makeBuilder(mode: .conservative)

        // after one successful execution, splice it a couple times, interleaved with mutational rounds
        for _ in 0..<spliceAndMutationRoundsPerSample {
            b.reset()
            b.append(program)

            let victim = self.fuzzer.corpus.randomElement()

            b.splice(from: victim)

            let splicedProg = b.finalize()

            let splicedExecution = execute(splicedProg)

            guard splicedExecution == .succeeded else {
                return
            }

            for _ in 0..<mutationRoundsPerSample {
                var current = splicedProg

                for _ in 0..<numConsecutiveMutations {
                    let mutator = self.fuzzer.mutators.randomElement()

                    if let mutated = mutator.mutate(current, for: fuzzer) {
                        let outcome = execute(mutated)
                        if outcome == .succeeded {
                            current = mutated
                        }
                    } else {
                      logger.warning("Mutator \(mutator.name) failed to mutate generated program")
                    }
                }
            }
        }
    }
}
