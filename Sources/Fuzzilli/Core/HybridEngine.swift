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
        if fuzzer.config.logLevel.isAtLeast(.info) {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                let codeTemplateStats = CodeTemplates.map({ "\($0.name): \(String(format: "%.2f%%", $0.stats.correctnessRate * 100))" }).joined(separator: ", ")
                self.logger.info("CodeTemplate correctness rates: \(codeTemplateStats)")
                let mutatorStats = self.fuzzer.mutators.map({ "\($0.name): \(String(format: "%.2f%%", $0.stats.correctnessRate * 100))" }).joined(separator: ", ")
                self.logger.info("Mutator correctness rates: \(mutatorStats)")
            }
        }
    }

    private func generateTemplateProgram(baseTemplate: CodeTemplate, mode: ProgramBuilder.Mode = .conservative) -> Program {
        let prefix = self.generateProgramPrefix(mode: .conservative)

        let b = fuzzer.makeBuilder(mode: mode)

        b.append(prefix)

        // Make sure we have at least a single function that we can use for generateVariable
        // as it requires this right now.
        // TODO(cffsmith): make generateVariable call this generator internally
        // if required or make the generateVariable call able to generate types
        // of functions
        b.run(CodeGenerators.get("PlainFunctionGenerator"))

        b.run(baseTemplate)

        return b.finalize()
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let template = chooseUniform(from: CodeTemplates)

        let program = generateTemplateProgram(baseTemplate: template)

        let (outcome, _) = execute(program, stats: &template.stats)

        guard outcome == .succeeded else {
            return
        }

        for _ in 0..<mutationRounds {
            var current = program

            for _ in 0..<numConsecutiveMutations {
                let mutator = self.fuzzer.mutators.randomElement()

                if let mutated = mutator.mutate(current, for: fuzzer) {
                    let (outcome, _) = self.execute(mutated, stats: &mutator.stats)
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
