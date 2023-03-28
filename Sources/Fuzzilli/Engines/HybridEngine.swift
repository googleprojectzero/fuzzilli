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

    // The different outcomes of one fuzzing iterations.
    private enum CodeGenerationOutcome: String, CaseIterable {
        case success = "Success"
        case generatedCodeFailed = "Generated code failed"
        case generatedCodeTimedOut = "Generated code timed out"
        case generatedCodeCrashed = "Generated code crashed"
    }
    private var outcomeCounts = [CodeGenerationOutcome: Int]()

    // Additional statistics about the generated programs.
    private var totalInstructionsGenerated = 0
    private var programsGenerated = 0
    private var tryCatchDensityAfterGeneration = MovingAverage(n: 1000)

    public init(numConsecutiveMutations: Int) {
        self.numConsecutiveMutations = numConsecutiveMutations
        super.init(name: "HybridEngine")

        for outcome in CodeGenerationOutcome.allCases {
            outcomeCounts[outcome] = 0
        }
    }

    override func initialize() {
        if fuzzer.config.logLevel.isAtLeast(.verbose) {
            fuzzer.timers.scheduleTask(every: 30 * Minutes) {
                guard self.programsGenerated > 0 else { return }

                // TODO move into Statistics?
                self.logger.verbose("Program Template Statistics:")
                let nameMaxLength = self.fuzzer.programTemplates.map({ $0.name.count }).max()!
                for template in self.fuzzer.programTemplates {
                    let name = template.name.rightPadded(toLength: nameMaxLength)
                    let correctnessRate = String(format: "%.2f%%", template.correctnessRate * 100).leftPadded(toLength: 7)
                    let interestingSamplesRate = String(format: "%.2f%%", template.interestingSamplesRate * 100).leftPadded(toLength: 7)
                    let timeoutRate = String(format: "%.2f%%", template.timeoutRate * 100).leftPadded(toLength: 6)
                    let avgInstructionsAdded = String(format: "%.2f", template.avgNumberOfInstructionsGenerated).leftPadded(toLength: 5)
                    let samplesGenerated = template.totalSamples
                    self.logger.verbose("    \(name) : Correctness rate: \(correctnessRate), Interesting sample rate: \(interestingSamplesRate), Timeout rate: \(timeoutRate), Avg. # of instructions generated: \(avgInstructionsAdded), Total # of generated samples: \(samplesGenerated)")
                }

                let totalOutcomes = self.outcomeCounts.values.reduce(0, +)
                self.logger.verbose("Frequencies of code generation outcomes:")
                for outcome in CodeGenerationOutcome.allCases {
                    let count = self.outcomeCounts[outcome]!
                    let frequency = (Double(count) / Double(totalOutcomes)) * 100.0
                    self.logger.verbose("    \(outcome.rawValue.rightPadded(toLength: 25)): \(String(format: "%.2f%%", frequency))")
                }

                self.logger.verbose("Number of generated programs: \(self.programsGenerated)")
                self.logger.verbose("Average programs size: \(self.totalInstructionsGenerated / self.programsGenerated)")
                self.logger.verbose("Average try-catch density after code generation: \(String(format: "%.3f%", self.tryCatchDensityAfterGeneration.currentValue))")
            }
        }
    }

    private func generateTemplateProgram(template: ProgramTemplate) -> Program {
        let b = fuzzer.makeBuilder(mode: .conservative)
        b.traceHeader("Generating program based on \(template.name) template")
        template.generate(in: b)
        let program = b.finalize()

        program.contributors.add(template)
        template.addedInstructions(program.size)
        return program
    }

    public func fuzzOne(_ group: DispatchGroup) {
        let template = fuzzer.programTemplates.randomElement()

        var program = generateTemplateProgram(template: template)
        computeCodeGenStatistics(for: program)

        let outcome = execute(program)

        switch outcome {
        case .succeeded:
            recordOutcome(.success)
        case .failed:
            return recordOutcome(.generatedCodeFailed)
        case .timedOut:
            return recordOutcome(.generatedCodeTimedOut)
        case .crashed:
            return recordOutcome(.generatedCodeCrashed)
        }

        var parent = program
        for _ in 0..<numConsecutiveMutations {
            // TODO: factor out code shared with the MutationEngine?
            var mutator = fuzzer.mutators.randomElement()
            var mutated = false
            let maxAttempts = 10
            for _ in 0..<maxAttempts {
                if let result = mutator.mutate(parent, for: fuzzer) {
                    // Success!
                    program = result
                    mutated = true
                    program.contributors.add(template)
                    mutator.addedInstructions(program.size - parent.size)
                    break
                } else {
                    // Try a different mutator.
                    mutator.failedToGenerate()
                    mutator = fuzzer.mutators.randomElement()
                }
            }

            guard mutated else {
                logger.warning("Could not mutate sample, giving up. Sample:\n\(FuzzILLifter().lift(parent))")
                continue
            }

            assert(program !== parent)
            let outcome = execute(program)

            // Mutate the program further if it succeeded.
            if .succeeded == outcome {
                // TODO: should we extend the contributors with that of the parent? Then we'd automatically get the ProgramTemplate back as contributor.
                parent = program
            }
        }
    }

    private func recordOutcome(_ outcome: CodeGenerationOutcome) {
        outcomeCounts[outcome]! += 1
    }

    private func computeCodeGenStatistics(for program: Program) {
        totalInstructionsGenerated += program.size
        programsGenerated += 1
        let numTryCatchBlocks = Double(program.code.filter({ $0.op is BeginTry }).count)
        tryCatchDensityAfterGeneration.add(numTryCatchBlocks / Double(program.size))
    }
}
