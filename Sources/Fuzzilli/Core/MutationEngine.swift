// Copyright 2019 Google LLC
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

/// Crash behavior of a program.
public enum CrashBehaviour: String {
    case deterministic = "deterministic"
    case flaky         = "flaky"
}

/// The core fuzzer responsible for generating and executing programs.
public class MutationEngine: ComponentBase, FuzzEngine {
    /// Common prefix of every generated program. This provides each program with several variables of the basic types
    private var prefix: Program

    private var shouldPreprocessSamples: Bool {
        // Programs are only preprocessed (have a prefix added to them etc.) if there is no minimization
        // limit (i.e. programs in the corpus are minimized as much as possible). Otherwise, we assume that
        // enough script content is available due to the limited minimization.
        return fuzzer.config.minimizationLimit == 0
    }

    // The number of consecutive mutations to apply to a sample.
    private let numConsecutiveMutations: Int

    public init(numConsecutiveMutations: Int) {
        self.prefix = Program()
        self.numConsecutiveMutations = numConsecutiveMutations
        super.init(name: "MutationEngine")
    }

    override func initialize() {
        prefix = generateProgramPrefix()

        // Regenerate the common prefix from time to time
        if shouldPreprocessSamples {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                self.prefix = self.generateProgramPrefix()
            }
        }
    }

    /// Prepare a previously minimized program for mutation.
    ///
    /// This mainly "refills" stuff that was removed during minimization:
    ///  * inserting NOPs to increase the likelihood of mutators inserting code later on
    ///  * inserting return statements at the end of function definitions if there are none
    func prepareForMutation(_ program: Program) -> Program {
        if !shouldPreprocessSamples {
            return program
        }

        let b = fuzzer.makeBuilder(forMutating: program)
        b.traceHeader("Preparing program \(program.id) for mutation")
        
        // Prepend the current program prefix
        b.append(prefix)
        b.trace("End of prefix")
        
        // Now append the selected program, slightly changing
        // it to ease mutation later on
        b.adopting(from: program) {
            var blocks = [Int]()
            for instr in program.code {
                if instr.isBlockEnd {
                    let beginIdx = blocks.removeLast()
                    if instr.index - beginIdx == 1 {
                        b.nop()
                    }
                    let prevInstr = program.code.before(instr)!
                    if instr.op is EndAnyFunctionDefinition && prevInstr.op is Return {
                        let rval = b.randVar()
                        b.doReturn(value: rval)
                    }
                }
                if instr.isBlockBegin {
                    blocks.append(instr.index)
                }
                b.adopt(instr, keepTypes: true)
            }
        }

        return b.finalize()
    }



    /// Perform one round of fuzzing.
    ///
    /// High-level fuzzing algorithm:
    ///
    ///     let parent = pickSampleFromCorpus()
    ///     repeat N times:
    ///         let current = mutate(parent)
    ///         execute(current)
    ///         if current produced crashed:
    ///             output current
    ///         elif current resulted in a runtime exception or a time out:
    ///             // do nothing
    ///         elif current produced new, interesting behaviour:
    ///             minimize and add to corpus
    ///         else
    ///             parent = current
    ///
    ///
    /// This ensures that samples will be mutated multiple times as long
    /// as the intermediate results do not cause a runtime exception.
    public func fuzzOne(_ group: DispatchGroup) {
        var parent = prepareForMutation(fuzzer.corpus.randomElementForMutating())
        var program = parent

        for _ in 0..<numConsecutiveMutations {
            var mutator = fuzzer.selectRandomMutator()
            var mutated = false
            for _ in 0..<10 {
                
                if let result = mutator.mutate(parent, for: fuzzer) {
                    program = result
                    mutated = true
                    break
                }
                logger.verbose("\(mutator.name) failed, trying different mutator")

                mutator = fuzzer.selectRandomMutator()
            }

            if !mutated {
                logger.warning("Could not mutate sample, giving up. Sample:\n\(fuzzer.lifter.lift(parent))")
                continue
            }
    
            let outcome = execute(program, stats: &mutator.stats)

            // Mutate the program further if it succeeded.
            if .succeeded == outcome {
                parent = program
            }
        }

        // Inform mutator MAB that mutation accumulation has finished and new coverage found can be evaluated
        fuzzer.notifySimultaneousMutationsComplete()
    }

    /// Set program prefix, should be used only in tests
    public func setPrefix(_ prefix: Program) {
        self.prefix = prefix
    }
}
