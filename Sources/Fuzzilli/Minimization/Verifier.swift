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

class ReductionVerifier {
    var totalReductions = 0
    var failedReductions = 0
    var didReduce = false
    
    /// The aspects of the program to preserve during minimization.
    /// These map to the engine with the indicies, if the value is nil, we
    /// don't care if we preserve the aspects or not.
    private let aspects: [ProgramAspects?]
    
    /// Fuzzer instance to schedule execution of programs on. Every access to the fuzzer instance has to be scheduled on its queue.
    private let fuzzer: Fuzzer
    
    private let instructionsToKeep: Set<Int>
    
    init(for aspects: [ProgramAspects?], of fuzzer: Fuzzer, keeping instructionsToKeep: Set<Int>) {
        self.aspects = aspects
        self.fuzzer = fuzzer
        self.instructionsToKeep = instructionsToKeep
    }
    
    /// Test a reduction and return true if the reduction was Ok, false otherwise.
    func test(_ code: Code) -> Bool {
        // Reducers are allowed to nop instructions without verifying whether their outputs are used.
        // Thus, we need to check for that here and bail if we detect such a case. This approach is
        // much easier to implement than forcing reducers to keep track of variable uses.
        var nopVars = VariableSet()
        for instr in code {
            if instr.op is Nop {
                nopVars.formUnion(instr.outputs)
            }
            if !nopVars.isDisjoint(with: instr.inputs) {
                return false
            }
        }
        
        // At this point, the code must be statically valid though.
        assert(code.isStaticallyValid())
        
        totalReductions += 1
        
        // Run the modified program and see if the patch changed its behaviour
        var stillHasAspects = [Bool]()
        fuzzer.sync {
            let executions = fuzzer.execute(Program(with: code), withTimeout: fuzzer.config.timeout * 2)
            for (idx, execution) in executions.enumerated() {
                // If these aspects are nil, we just say that we did keep the aspects
                // such that minimization for the other engines can continue.
                if aspects[idx] == nil {
                    stillHasAspects.append(true)
                } else {
                    stillHasAspects.append(fuzzer.runners[idx].evaluator.hasAspects(execution, aspects[idx]!))
                }
            }
        }

        // If every engine has signaled that we did keep the aspects, we did reduce it correctly.
        if stillHasAspects.filter({$0 == true}) == stillHasAspects {
            didReduce = true
            return true
        } else {
            failedReductions += 1
            return false
        }
    }
    
    /// Replace the instruction at the given index with the provided replacement if it does not negatively influence the programs previous behaviour.
    /// The replacement instruction must produce the same output variables as the original instruction.
    @discardableResult
    func tryReplacing(instructionAt index: Int, with newInstr: Instruction, in code: inout Code) -> Bool {
        assert(code[index].allOutputs == newInstr.allOutputs)
        guard !instructionsToKeep.contains(index) else {
            return false
        }
        
        let origInstr = code[index]
        code[index] = newInstr
        
        let result = test(code)
        
        if !result {
            // Revert change
            code[index] = origInstr
        }
        
        return result
    }
    
    /// Remove the instruction at the given index if it does not negatively influence the programs previous behaviour.
    @discardableResult
    func tryNopping(instructionAt index: Int, in code: inout Code) -> Bool {
        return tryReplacing(instructionAt: index, with: nop(for: code[index]), in: &code)
    }
    
    /// Attempt multiple replacements at once.
    /// Every replacement instruction must produce the same output variables as the replaced instruction.
    @discardableResult
    func tryReplacements(_ replacements: [(Int, Instruction)], in code: inout Code) -> Bool {
        var originalInstructions = [(Int, Instruction)]()
        var abort = false, result = false
        for (index, newInstr) in replacements {
            if instructionsToKeep.contains(index) {
                abort = true
                break
            }
            let origInstr = code[index]
            code[index] = newInstr
            originalInstructions.append((index, origInstr))
            assert(origInstr.allOutputs == newInstr.allOutputs)
        }
        
        if !abort {
            result = test(code)
        }
        
        if !result {
            // Revert change
            for (index, origInstr) in originalInstructions {
                code[index] = origInstr
            }
        }
        
        return result
    }
    
    /// Attempt the removal of multiple instructions at once.
    @discardableResult
    func tryNopping(_ indices: [Int], in code: inout Code) -> Bool {
        var replacements = [(Int, Instruction)]()
        for index in indices {
            replacements.append((index, nop(for: code[index])))
        }
        return tryReplacements(replacements, in: &code)
    }
    
    /// Create a Nop instruction for replacing the given instruction with.
    private func nop(for instr: Instruction) -> Instruction {
        // We must preserve outputs here to keep variable number contiguous.
        return Instruction(Nop(numOutputs: instr.numOutputs + instr.numInnerOutputs), inouts: instr.allOutputs)
    }
}

protocol Reducer {
    /// Attempt to reduce the given program in some way and return the result.
    ///
    /// The returned program can have non-contiguous variable names but must otherwise be valid.
    func reduce(_ code: inout Code, with verifier: ReductionVerifier)
}
