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
public class Minimizer: ComponentBase {
    /// DispatchQueue on which program minimization happens.
    private let minimizationQueue = DispatchQueue(label: "Minimizer")

    public init() {
        super.init(name: "Minimizer")
    }

    enum MinimizationMode {
        // Normal minimization will honor the minimization limit, not perform
        // some of the expensive and especially "destructive" reductions (e.g.
        // of call arguments and literals) and not perform fixpoint minimization.
        case normal
        
        // Aggressive minimization will minimize the program as much as possible,
        // ignoring the minimization limit.
        case aggressive
    }

    /// Minimizes the given program while preserving its special aspects.
    ///
    /// Minimization will not modify the given program. Instead, it produce a new Program instance.
    /// Once minimization is finished, the passed block will be invoked on the fuzzer's queue with the minimized program.
    func withMinimizedCopy(_ program: Program, withAspects aspects: ProgramAspects, usingMode mode: MinimizationMode, block: @escaping (Program) -> ()) {
        minimizationQueue.async {
            let minimizedProgram = self.internalMinimize(program, withAspects: aspects, usingMode: mode, limit: self.fuzzer.config.minimizationLimit)
            self.fuzzer.async {
                block(minimizedProgram)
            }
        }
    }

    private func internalMinimize(_ program: Program, withAspects aspects: ProgramAspects, usingMode mode: MinimizationMode, limit minimizationLimit: UInt) -> Program {
        dispatchPrecondition(condition: .onQueue(minimizationQueue))

        if mode == .normal && program.size <= fuzzer.config.minimizationLimit {
            return program
        }

        // Implementation of minimization limits:
        // Pick N (~= the minimum program size) instructions at random which will not be removed during minimization.
        // This way, minimization will be sped up (because no executions are necessary for those instructions marked as keep-alive)
        // while the instructions that are kept artificially are equally distributed throughout the program.
        var keptInstructions = Set<Int>()
        if mode == .normal && minimizationLimit > 0 {
            let analyzer = DefUseAnalyzer(for: program)
            var indices = Array(0..<program.size).shuffled()

            while keptInstructions.count < minimizationLimit {
                func keep(_ instr: Instruction) {
                    guard !keptInstructions.contains(instr.index) else { return }
                    
                    keptInstructions.insert(instr.index)
                    
                    // Keep alive all inputs recursively.
                    for input in instr.inputs {
                        let inputInstr = analyzer.definition(of: input)
                        keep(inputInstr)
                    }
                }
                
                keep(program[indices.removeLast()])
            }
        }

        let verifier = ReductionVerifier(for: aspects, of: self.fuzzer, keeping: keptInstructions)
        var current = program.copy()

        repeat {
            verifier.didReduce = false

            let reducers: [Reducer]
            switch mode {
            case .aggressive:
                reducers = [CallArgumentReducer(), ReplaceReducer(), GenericInstructionReducer(), BlockReducer(), InliningReducer()]
            case .normal:
                reducers = [ReplaceReducer(), GenericInstructionReducer(), BlockReducer(), InliningReducer()]
            }

            for reducer in reducers {
                current = reducer.reduce(current, with: verifier)
            }
        } while verifier.didReduce && mode == .aggressive

        // Most reducers replace instructions with NOPs instead of deleting them. Remove those NOPs now.
        current.normalize()

        return current
    }
}
