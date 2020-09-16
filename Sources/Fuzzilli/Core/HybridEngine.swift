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
    private let mutationRounds: Int

    // The number of mutations to perform to a single sample per round
    private let numConsecutiveMutations: Int

    public init(numConsecutiveMutations: Int) {
        self.mutationRounds = 2
        self.numConsecutiveMutations = numConsecutiveMutations

        super.init(name: "HybridEngine")
    }

    override func initialize() {
    }

    private func generateTemplateProgram(mode: ProgramBuilder.Mode = .conservative) -> Program {
        let prefix = self.generateProgramPrefix(mode: .conservative)

        let b = fuzzer.makeBuilder(mode: mode)

        b.append(prefix)

        // Make sure we have at least a single function that we can use for generateVariable
        // as it requires this right now.
        // TODO(cffsmith): make generateVariable call this generator internally if required.
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

        for _ in 0..<mutationRounds {
            var current = program

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
