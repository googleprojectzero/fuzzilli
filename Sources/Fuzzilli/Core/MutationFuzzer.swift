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
public class MutationFuzzer: ComponentBase {
    /// Common prefix of every generated program. This provides each program with several variables of the basic types
    private var prefix: Program
    
    private var shouldPreprocessSamples: Bool {
        // Programs are only preprocessed (have a prefix added to them etc.) if there is no minimization
        // limit (i.e. programs in the corpus are minimized as much as possible). Otherwise, we assume that
        // enough script content is available due to the limited minimization.
        return fuzzer.config.minimizationLimit == 0
    }

    /// Prefix "template" to use. Every program taken from the corpus
    /// is prefixed with some code generated from this before mutation.
    private let programPrefixGenerators: [CodeGenerator] = [
        CodeGenerators.get("IntegerGenerator"),
        CodeGenerators.get("StringGenerator"),
        CodeGenerators.get("BuiltinGenerator"),
        CodeGenerators.get("FloatArrayGenerator"),
        CodeGenerators.get("IntArrayGenerator"),
        CodeGenerators.get("ArrayGenerator"),
        CodeGenerators.get("ObjectGenerator"),
        CodeGenerators.get("ObjectGenerator"),
        CodeGenerators.get("PhiGenerator"),
    ]
    
    // The number of consecutive mutations to apply to a sample.
    private let numConsecutiveMutations: Int
    
    // Mutators to use.
    private let mutators: WeightedList<Mutator>

    public init(mutators: WeightedList<Mutator>, numConsecutiveMutations: Int) {
        self.prefix = Program()
        self.mutators = mutators
        self.numConsecutiveMutations = numConsecutiveMutations
        super.init(name: "MutationFuzzer")
    }
    
    override func initialize() {
        prefix = makePrefix()
        
        // Regenerate the common prefix from time to time
        if shouldPreprocessSamples {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                self.prefix = self.makePrefix()
            }
        }
        
        if fuzzer.config.logLevel.isAtLeast(.info) {
            fuzzer.timers.scheduleTask(every: 15*Minutes) {
                let stats = self.mutators.map({ "\($0.name): \(String(format: "%.2f%%", $0.correctnessRate * 100))" }).joined(separator: ", ")
                self.logger.info("Mutator correctness rates: \(stats)")
            }
        }
    }
    
    /// Prepare a previously minimized program for mutation.
    ///
    /// This mainly "refills" stuff that was removed during minimization:
    ///  * inserting NOPs to increase the likelyhood of mutators inserting code later on
    ///  * inserting return statements at the end of function definitions if there are none
    func prepareForMutation(_ program: Program) -> Program {
        if !shouldPreprocessSamples {
            return program
        }
        
        let b = fuzzer.makeBuilder()
        
        // Prepend the current program prefix
        b.append(prefix)
        
        // Now append the selected program, slightly changing
        // it to ease mutation later on
        b.adopting(from: program) {
            var blocks = [Int]()
            for instr in program {
                if instr.isBlockEnd {
                    let beginIdx = blocks.removeLast()
                    if instr.index - beginIdx == 1 {
                        b.append(Instruction.NOP)
                    }
                    if instr.operation is EndAnyFunctionDefinition && !(program[instr.index - 1].operation is Return) {
                        let rval = b.randVar()
                        b.doReturn(value: rval)
                    }
                }
                if instr.isBlockBegin {
                    blocks.append(instr.index)
                }
                b.adopt(instr)
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
    func fuzzOne(_ group: DispatchGroup) {
        var parent = prepareForMutation(fuzzer.corpus.randomElement())
        var program = Program()
        
        for _ in 0..<numConsecutiveMutations {
            var mutator = mutators.randomElement()
            var mutated = false
            for _ in 0..<10 {
                if let result = mutator.mutate(parent, for: fuzzer) {
                    program = result
                    mutated = true
                    break
                }
                logger.verbose("\(mutator.name) failed, trying different mutator")
                mutator = mutators.randomElement()
            }
            
            if !mutated {
                logger.warning("Could not mutate sample, giving up. Sampe:\n\(fuzzer.lifter.lift(parent))")
                continue
            }
    
            fuzzer.dispatchEvent(fuzzer.events.ProgramGenerated, data: program)
            
            let execution = fuzzer.execute(program)
            
            switch execution.outcome {
            case .crashed(let termsig):
                // For crashes, we append a comment containing the content of stderr
                program.append(Instruction(operation: Comment("Stderr:\n" + execution.stderr)))
                fuzzer.processCrash(program, withSignal: termsig, isImported: false)
                
            case .succeeded:
                mutator.producedValidSample()
                fuzzer.dispatchEvent(fuzzer.events.ValidProgramFound, data: program)
                
                if let aspects = fuzzer.evaluator.evaluate(execution) {
                    fuzzer.processInteresting(program, havingAspects: aspects, isImported: false)
                    // Continue mutating the parent as the new program should be in the corpus now.
                    // Moreover, the new program could be empty due to minimization, which would cause problems above.
                } else {
                    // Continue mutating this sample
                    parent = program
                }
                
            case .failed:
                mutator.producedInvalidSample()
                fuzzer.dispatchEvent(fuzzer.events.InvalidProgramFound, data: program)
                
            case .timedOut:
                mutator.producedInvalidSample()
                fuzzer.dispatchEvent(fuzzer.events.TimeOutFound, data: program)
            }
        }
    }
    
    private func makePrefix() -> Program {
        let b = fuzzer.makeBuilder()
        
        for generator in programPrefixGenerators {
            b.run(generator)
        }
        
        return b.finalize()
    }
}
