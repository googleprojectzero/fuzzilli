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

/// Minimizes programs.
///
/// Executes various program reducers to shrink a program in size while retaining its special aspects. All of this
/// happens on a separate dispatch queue so the main queue stays responsive.
///
/// There are two basic principles for program minimization:
///   - Minimization must only remove program features that can be added back through mutations later on.
///     For example, variadic inputs to instructions can be removed because the OperationMutator can add them back.
///   - Minimization should generally strive to be as powerful as possible, i.e. be able to find the smallest possible programs.
///     To counter "over-minimization" (i.e. programs becoming too small, making mutations less effective), there should
///     be a configurable limit to minimization which keeps some random instructions alive, so that those are uniformly
///     distributed and not biased to a certain type of instruction or instruction sequence.
///
public class Minimizer: ComponentBase {
    /// DispatchQueue on which program minimization happens.
    private let minimizationQueue = DispatchQueue(label: "Minimizer")

    public init() {
        super.init(name: "Minimizer")
    }

    /// Minimizes the given program while preserving its special aspects.
    ///
    /// Minimization will not modify the given program. Instead, it produce a new Program instance.
    /// Once minimization is finished, the passed block will be invoked on the fuzzer's queue with the minimized program.
    func withMinimizedCopy(_ program: Program, withAspects aspects: ProgramAspects, limit minimizationLimit: Double = 0.0, block: @escaping (Program) -> ()) {
        minimizationQueue.async {
            let minimizedCode = self.internalMinimize(program, withAspects: aspects, limit: minimizationLimit, runningSynchronously: false)
            self.fuzzer.async {
                let minimizedProgram: Program
                if self.fuzzer.config.enableInspection {
                    minimizedProgram = Program(code: minimizedCode, parent: program, contributors: program.contributors)
                    minimizedProgram.comments.add("Minimizing \(program.id)", at: .header)
                } else {
                    minimizedProgram = Program(code: minimizedCode, contributors: program.contributors)
                }
                block(minimizedProgram)
            }
        }
    }

    /// Synchronous version of withMinimizedCopy. Should only be used for tests since it otherwise blocks the fuzzer queue.
    func minimize(_ program: Program, withAspects aspects: ProgramAspects, limit minimizationLimit: Double = 0.0) -> Program {
        let minimizedCode = internalMinimize(program, withAspects: aspects, limit: minimizationLimit, runningSynchronously: true)
        return Program(code: minimizedCode, parent: program, contributors: program.contributors)
    }

    private func internalMinimize(_ program: Program, withAspects aspects: ProgramAspects, limit minimizationLimit: Double, runningSynchronously: Bool) -> Code {
        // Implementation of minimization limits:
        // Pick N (~= minimizationLimit * programSize) instructions at random which will not be removed during minimization.
        // This way, minimization will be sped up (because no executions are necessary for those instructions marked as keep-alive)
        // while the instructions that are kept artificially are equally distributed throughout the program.
        var keptInstructions = Set<Int>()
        if minimizationLimit != 0 {
            assert(minimizationLimit > 0.0 && minimizationLimit <= 1.0)
            var analyzer = DefUseAnalyzer(for: program)
            analyzer.analyze()
            let numberOfInstructionsToKeep = Int(Double(program.size) * minimizationLimit)
            var indices = Array(0..<program.size).shuffled()

            while keptInstructions.count < numberOfInstructionsToKeep {
                func keep(_ instr: Instruction) {
                    guard !keptInstructions.contains(instr.index) else { return }

                    keptInstructions.insert(instr.index)

                    // Keep alive all inputs recursively.
                    for input in instr.inputs {
                        keep(analyzer.definition(of: input))
                    }
                }

                keep(program.code[indices.removeLast()])
            }
        }

        let helper = MinimizationHelper(for: aspects, of: fuzzer, keeping: keptInstructions, runningOnFuzzerQueue: runningSynchronously)
        var code = program.code

        var iterations = 0
        repeat {
            helper.didReduce = false

            // Notes on reducer scheduling:
            //  - The ReplaceReducer should run before the InliningReducer as it changes "special" functions into plain functions, which the inlining reducer inlines.
            //  - The ReassignmentReducer should run right after the InliningReducer as inlining produces new Reassign instructions.
            //  - The VariadicInputReducer should run after the InliningReducer as it may remove function call arguments, causing the parameters to be undefined after inlining.
            let reducers: [Reducer] = [GenericInstructionReducer(), BlockReducer(), SimplifyingReducer(), LoopReducer(), InliningReducer(), ReassignmentReducer(), VariadicInputReducer(), DeduplicatingReducer()]
            for reducer in reducers {
                reducer.reduce(&code, with: helper)
                assert(code.isStaticallyValid())
            }
            iterations += 1
            guard iterations < 100 else {
                // This can happen if a reducer performs a no-op change in every iteration, e.g. replacing one instruction with the same instruction. This is considered a bug since it leads to this kind of issue.
                logger.error("Fixpoint iteration for program minimization did not converge after 100 iterations for program:\n\(FuzzILLifter().lift(code)). Aborting minimization.")
                break
            }
        } while helper.didReduce

        // Most reducers replace instructions with NOPs instead of deleting them. Remove those NOPs now.
        code.removeNops()

        // Post-process the sample after minimization. This step adds certain features back to the program that may have been minimized away but are typically helpful for future mutations.
        // Currently we run this regardless of whether we're processing a crash or an interesting sample. If we wanted to, we could only run this for interesting samples (that will be mutated again), but its fine to also run it for crashes.
        // Adding instructions will invalidate the keptInstructions array. Since we're not removing any more instructions, clear that array now.
        helper.clearInstructionsToKeep()
        let postProcessor = MinimizationPostProcessor()
        postProcessor.process(&code, with: helper)
        assert(code.isStaticallyValid())

        return code
    }
}
