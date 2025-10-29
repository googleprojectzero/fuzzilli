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

public class TestTemplateEngine: FuzzEngine {
    // The number of mutations to perform to a single sample per round
    private let numConsecutiveMutations: Int
    private var lmao: Int
    private let lifter: Lifter

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

    public init(numConsecutiveMutations: Int, lifter: Lifter) {
        self.numConsecutiveMutations = numConsecutiveMutations
        self.lifter = lifter
        self.lmao = 0
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
                    let correctnessRate = Statistics.percentageOrNa(template.correctnessRate, 7)
                    let interestingSamplesRate = Statistics.percentageOrNa(template.interestingSamplesRate, 7)
                    let timeoutRate = Statistics.percentageOrNa(template.timeoutRate, 6)
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
        //if lmao != 0 {
        //    return
        //}
        
        for template in fuzzer.programTemplates {
            let generatedProgram = generateTemplateProgram(template: template)
            let script = lifter.lift(generatedProgram)
            //print("Lifted Program based on template \(template)\nLifted Program:\n\(script)")

            let content = "Template: \(template.name)\nProgram:\n\(script)"
            let filename = "template_\(template.name).fzil"
            let base = "Corpus/lifted_templates"
            let url = URL(fileURLWithPath: "\(base)/\(filename)")
            do {
                try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
            } catch {
                logger.fatal("Failed to create storage directories. Is \(base) writable by the current user?")
            }
            do {
                try content.write(to: url, atomically: false, encoding: String.Encoding.utf8)
            } catch {
                logger.error("Failed to write file \(url): \(error)")
            }
        }

        lmao = 1
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
