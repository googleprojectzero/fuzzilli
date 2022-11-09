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
    // The number of mutations to perform to a single sample per round
    private let numConsecutiveMutations: Int

    public init(numConsecutiveMutations: Int) {
        self.numConsecutiveMutations = numConsecutiveMutations
        super.init(name: "HybridEngine")
    }

    override func initialize() {
        if fuzzer.config.logLevel.isAtLeast(.info) {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                let programTemplateStats = self.fuzzer.programTemplates.map({ "\($0.name): \(String(format: "%.2f%%", $0.correctnessRate * 100))" }).joined(separator: ", ")
                self.logger.info("ProgramTemplate correctness rates: \(programTemplateStats)")
            }
        }
    }

    private func generateTemplateProgram(baseTemplate: ProgramTemplate) -> Program {
        let b = fuzzer.makeBuilder(mode: .conservative)

        b.traceHeader("Generating program based on \(baseTemplate.name) template")

        baseTemplate.generate(in: b)

        return b.finalize()
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let template = fuzzer.programTemplates.randomElement()

        var program = generateTemplateProgram(baseTemplate: template)

        let outcome = execute(program)

        guard outcome == .succeeded else {
            return
        }

        for _ in 0..<numConsecutiveMutations {
            let mutator = fuzzer.mutators.randomElement()

            if let mutated = mutator.mutate(program, for: fuzzer) {
                // TODO record number of added instruction for mutator?
                let outcome = execute(mutated)
                if outcome == .succeeded {
                    program = mutated
                }
            } else {
              logger.warning("Mutator \(mutator.name) failed to mutate generated program")
            }
        }
    }
}
