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

/// Crash behavior of a program.
public enum CrashBehaviour: String {
    case deterministic = "deterministic"
    case flaky         = "flaky"
}

/// The core fuzzer responsible for generating and executing programs.
public class FuzzerCore: ComponentBase {
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
        IntegerLiteralGenerator,
        StringLiteralGenerator,
        BuiltinGenerator,
        FloatArrayGenerator,
        IntArrayGenerator,
        ArrayLiteralGenerator,
        ObjectLiteralGenerator,
        ObjectLiteralGenerator,
        PhiGenerator,
    ]
    
    // The number of consecutive mutations to apply to a sample.
    private let numConsecutiveMutations: Int
    
    // Mutators to use.
    private let mutators: [Mutator]

    public init(mutators: [Mutator], numConsecutiveMutations: Int) {
        self.prefix = Program()
        self.mutators = mutators
        self.numConsecutiveMutations = numConsecutiveMutations
        
        super.init(name: "FuzzerCore")
    }
    
    override func initialize() {
        prefix = makePrefix()
        
        // Regenerate the common prefix from time to time
        if shouldPreprocessSamples {
            fuzzer.timers.scheduleTask(every: 15 * Minutes) {
                self.prefix = self.makePrefix()
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
                    if instr.operation is EndFunctionDefinition && !(program[instr.index - 1].operation is Return) {
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
        
        return b.finish()
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
    func fuzzOne() {
        var parent = prepareForMutation(fuzzer.corpus.randomElement())
        var program = Program()
        
        for _ in 0..<numConsecutiveMutations {
            var mutator = chooseUniform(from: mutators)
            var mutated = false
            for _ in 0..<100 {
                if let result = mutator.mutate(parent, for: fuzzer) {
                    program = result
                    mutated = true
                    break
                }
                logger.verbose("\(mutator.name) failed, trying different mutator")
                mutator = chooseUniform(from: mutators)
                
            }
            if !mutated {
                logger.warning("Could not mutate sample, giving up. Sampe:\n\(fuzzer.lifter.lift(parent))")
                program = parent
            }
    
            fuzzer.events.ProgramGenerated.dispatch(with: program)
            
            let execution = fuzzer.execute(program)
            
            switch execution.outcome {
            case .crashed:
                processCrash(program, withSignal: execution.termsig, ofProcess: execution.pid, isImported: false)
                
            case .succeeded:
                fuzzer.events.ValidProgramFound.dispatch(with: (program, mutator.name))
                
                if let aspects = fuzzer.evaluator.evaluate(execution) {
                    processInteresting(program, havingAspects: aspects, isImported: false)
                    // Continue mutating the parent as the new program should be in the corpus now.
                    // Moreover, the new program could be empty due to minimization, which would cause problems above.
                } else {
                    // Continue mutating this sample
                    parent = program
                }
                
            case .failed:
                fuzzer.events.InvalidProgramFound.dispatch(with: (program, mutator.name))
                
            case .timedOut:
                fuzzer.events.TimeOutFound.dispatch(with: program)
            }
        }
    }
    
    /// Import a program from somewhere. The imported program will be treated like a freshly generated one.
    ///
    /// - Parameters:
    ///   - program: The program to import.
    ///   - doDropout: If true, the sample is discarded with a small probability. This can be useful to desynchronize multiple instances a bit.
    ///   - isCrash: Whether the program is a crashing sample in which case a crash event will be dispatched in any case.
    func importProgram(_ program: Program, withDropout doDropout: Bool, isCrash: Bool = false) {
        assert(program.check() == .valid)
        
        if doDropout && probability(fuzzer.config.dropoutRate) {
            return
        }
        
        fuzzer.events.ProgramImported.dispatch(with: program)

        let execution = fuzzer.execute(program)
        var didCrash = false
        
        switch execution.outcome {
        case .crashed:
            processCrash(program, withSignal: execution.termsig, ofProcess: execution.pid, isImported: true)
            didCrash = true
            
        case .succeeded:
            if let aspects = fuzzer.evaluator.evaluate(execution) {
                processInteresting(program, havingAspects: aspects, isImported: true)
            }
            
        default:
            break
        }

        if !didCrash && isCrash {
            fuzzer.events.CrashFound.dispatch(with: (program, .flaky, 0, 0, true, true))
        }
    }

    private func processInteresting(_ program: Program, havingAspects aspects: ProgramAspects, isImported: Bool) {
        if isImported {
            // Imported samples are already minimized.
            return fuzzer.events.InterestingProgramFound.dispatch(with: (program, isImported))
        }
        let minimizedProgram = fuzzer.minimizer.minimize(program, withAspects: aspects, usingMode: .normal)
        fuzzer.events.InterestingProgramFound.dispatch(with: (minimizedProgram, isImported))
    }
    
    private func processCrash(_ program: Program, withSignal termsig: Int, ofProcess pid: Int, isImported: Bool) {
        let minimizedProgram = fuzzer.minimizer.minimize(program, withAspects: ProgramAspects(outcome: .crashed), usingMode: .aggressive)
            
        // Check for uniqueness only after minimization
        let execution = fuzzer.execute(minimizedProgram, withTimeout: fuzzer.config.timeout * 2)
        if execution.outcome == .crashed {
            let isUnique = fuzzer.evaluator.evaluateCrash(execution) != nil
            fuzzer.events.CrashFound.dispatch(with: (minimizedProgram, .deterministic, termsig, pid, isUnique, isImported))
        } else {
            fuzzer.events.CrashFound.dispatch(with: (minimizedProgram, .flaky, termsig, pid, true, isImported))
        }
    }
    
    private func makePrefix() -> Program {
        let b = fuzzer.makeBuilder()
        
        for generator in programPrefixGenerators {
            b.run(generator)
        }
        
        return b.finish()
    }
}
