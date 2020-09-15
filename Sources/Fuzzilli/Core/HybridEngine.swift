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

    public func fuzzOne(_ group: DispatchGroup) {
        let program = generateTemplateProgram()

        let (outcome, _) = execute(program)

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

            let (splicedExecution, _) = self.execute(splicedProg)

            guard splicedExecution == .succeeded else {
                return
            }

            for _ in 0..<mutationRoundsPerSample {
                var current = splicedProg

                for _ in 0..<numConsecutiveMutations {
                    let mutator = self.fuzzer.mutators.randomElement()

                    if let mutated = mutator.mutate(current, for: fuzzer) {
                        let (outcome, _) = self.execute(mutated)
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
