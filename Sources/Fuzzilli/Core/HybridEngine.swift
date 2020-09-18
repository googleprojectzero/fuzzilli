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
        assert(fuzzer.config.useAbstractInterpretation, "The HybridEngine requires abstract interpretation to be enabled")
        if fuzzer.config.logLevel.isAtLeast(.info) {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                let codeTemplateStats = CodeTemplates.map({ "\($0.name): \(String(format: "%.2f%%", $0.stats.correctnessRate * 100))" }).joined(separator: ", ")
                self.logger.info("CodeTemplate correctness rates: \(codeTemplateStats)")
            }
        }
    }

    private func generateTemplateProgram(baseTemplate: CodeTemplate, mode: ProgramBuilder.Mode = .conservative) -> Program {
        let prefix = generateProgramPrefix()

        let b = fuzzer.makeBuilder(mode: mode)
        
        b.traceHeader("Generating program based on \(baseTemplate.name) template")

        b.append(prefix)
        b.trace("End of prefix")

        // Make sure we have at least a single function that we can use for generateVariable
        // as it requires this right now.
        // TODO(cffsmith): make generateVariable call this generator internally
        // if required or make the generateVariable call able to generate types
        // of functions
        b.run(CodeGenerators.get("PlainFunctionGenerator"))

        baseTemplate.generate(in: b)

        return b.finalize()
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let template = chooseUniform(from: CodeTemplates)

        var program = generateTemplateProgram(baseTemplate: template)

        let outcome = execute(program, stats: &template.stats)

        guard outcome == .succeeded else {
            return
        }

        for _ in 0..<numConsecutiveMutations {
            let mutator = fuzzer.mutators.randomElement()

            if let mutated = mutator.mutate(program, for: fuzzer) {
                let outcome = execute(mutated, stats: &mutator.stats)
                if outcome == .succeeded {
                    program = mutated
                }
            } else {
              logger.warning("Mutator \(mutator.name) failed to mutate generated program")
            }
        }
    }
}
