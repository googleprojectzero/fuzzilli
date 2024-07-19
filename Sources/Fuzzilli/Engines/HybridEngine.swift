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

public class HybridEngine: FuzzEngine {
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
    private var percentageOfGuardedOperationsAfterCodeGeneration = MovingAverage(n: 1000)
    private var percentageOfGuardedOperationsAfterCodeRefining = MovingAverage(n: 1000)

    // We use the FixupMutator to "fix" the generated programs based on runtime information (e.g. remove unneeded try-catch).
    private var fixupMutator = FixupMutator(name: "HybridEngineFixupMutator")

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
                self.logger.verbose("Average percentage of guarded operations after code generation: \(String(format: "%.2f%", self.percentageOfGuardedOperationsAfterCodeGeneration.currentValue))%")
                self.logger.verbose("Average percentage of guarded operations after code refining: \(String(format: "%.2f%", self.percentageOfGuardedOperationsAfterCodeRefining.currentValue))%")
            }
        }
    }

    private func generateTemplateProgram(template: ProgramTemplate) -> Program {
        let b = fuzzer.makeBuilder()
        b.traceHeader("Generating program based on \(template.name) template")
        template.generate(in: b)
        let program = b.finalize()

        program.contributors.insert(template)
        template.addedInstructions(program.size)
        return program
    }

    public override func fuzzOne(_ group: DispatchGroup) {
        let template = fuzzer.programTemplates.randomElement()

        let generatedProgram = generateTemplateProgram(template: template)

        // Update basic codegen statistics.
        totalInstructionsGenerated += generatedProgram.size
        programsGenerated += 1
        percentageOfGuardedOperationsAfterCodeGeneration.add(computePercentageOfGuardedOperations(in: generatedProgram))

        // We use a higher timeout for the initial execution as pure code generation should only rarely lead to infinite loops/recursion.
        // On the other hand, the generated program may contain slow operations (e.g. try-catch guards) that the subsequent fixup may remove.
        let outcome = execute(generatedProgram, withTimeout: fuzzer.config.timeout * 2)
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

        // Now perform one round of fixup to improve the generated program based on runtime information and in particular remove all try-catch guards that are not needed.
        // For example, at runtime we'll know the exact type of variables, including object methods and properties, which we do not necessarily know statically during code generation.
        // As such, it is much easier to select a "good" method/property to access at runtime than it is during static code generation. Further, it is trivial to determine which
        // operations raise an exception at runtime, but hard to determine that statically at code generation time. So we can be overly conservative and wrap many operations in
        // try-catch (i.e. "guard" them), then remove the unnecessary guards after code generation based on runtime information. This is what fixup achieves.
        let refinedProgram: Program
        if let result = fixupMutator.mutate(generatedProgram, for: fuzzer) {
            refinedProgram = result
            percentageOfGuardedOperationsAfterCodeRefining.add(computePercentageOfGuardedOperations(in: refinedProgram))
        } else {
            // Fixup is expected to fail sometimes, for example if there is nothing to fix.
            refinedProgram = generatedProgram
        }

        // Now mutate the program a number of times.
        // We do this for example because pure code generation will often not generate "weird" code (e.g. weird inputs to operations, infinite loops, very large arrays, odd-looking object/class literals, etc.), but mutators are pretty good at that.
        // Further, some mutators have access to runtime information (e.g. Probe and Explore mutator) which the static code generation lacks.
        var parent = refinedProgram
        for _ in 0..<numConsecutiveMutations {
            // TODO: factor out code shared with the MutationEngine?
            var mutator = fuzzer.mutators.randomElement()
            let maxAttempts = 10
            var mutatedProgram: Program? = nil
            for _ in 0..<maxAttempts {
                if let result = mutator.mutate(parent, for: fuzzer) {
                    // Success!
                    result.contributors.formUnion(parent.contributors)
                    mutator.addedInstructions(result.size - parent.size)
                    mutatedProgram = result
                    break
                } else {
                    // Try a different mutator.
                    mutator.failedToGenerate()
                    mutator = fuzzer.mutators.randomElement()
                }
            }

            guard let program = mutatedProgram else {
                logger.warning("Could not mutate sample, giving up. Sample:\n\(FuzzILLifter().lift(parent))")
                continue
            }

            assert(program !== parent)
            let outcome = execute(program)

            // Mutate the program further if it succeeded.
            if .succeeded == outcome {
                parent = program
            }
        }
    }

    private func recordOutcome(_ outcome: CodeGenerationOutcome) {
        outcomeCounts[outcome]! += 1
    }

    private func computePercentageOfGuardedOperations(in program: Program) -> Double {
        let numGuardedOperations = Double(program.code.filter({ $0.isGuarded }).count)
        // We also count try-catch blocks as guards for the purpose of these statistics, and we count them as 3 instructions
        // as they at least need the BeginTry and EndTryCatchFinally, plus either a BeginCatch or BeginFinally.
        let numTryCatchBlocks = Double(program.code.filter({ $0.op is BeginTry }).count)
        return ((numGuardedOperations + numTryCatchBlocks * 3) / Double(program.size)) * 100.0
    }
}
