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
    private let aspects: ProgramAspects
    
    private let fuzzer: Fuzzer
    
    private let instructionsToKeep: Set<Int>
    
    init(for aspects: ProgramAspects, of fuzzer: Fuzzer, keeping instructionsToKeep: Set<Int>) {
        self.aspects = aspects
        self.fuzzer = fuzzer
        self.instructionsToKeep = instructionsToKeep
    }
    
    /// Test a reduction and return true if the reduction was Ok, false otherwise.
    func test(_ reducedProgram: Program) -> Bool {
        guard reducedProgram.check() == .valid else {
            return false
        }
        
        totalReductions += 1
        
        // Run the modified program and see if the patched changed its behaviour
        let execution = fuzzer.execute(reducedProgram, withTimeout: fuzzer.config.timeout * 2)
        if fuzzer.evaluator.hasAspects(execution, aspects) {
            didReduce = true
            return true
        } else {
            failedReductions += 1
            return false
        }
    }
    
    /// Replace the instruction at the given index with the provided replacement if it does not negatively influence the programs previous behaviour.
    @discardableResult
    func tryReplacing(instructionAt index: Int, with newInstr: Instruction, in program: Program) -> Bool {
        guard !instructionsToKeep.contains(index) else {
            return false
        }
        
        let origInstr = program.replace(instructionAt: index, with: newInstr)
        
        let result = test(program)
        
        if !result {
            // Revert change
            program.replace(instructionAt: index, with: origInstr)
        }
        
        return result
    }
    
    /// Remove the instruction at the given index if it does not negatively influence the programs previous behaviour.
    @discardableResult
    func tryNopping(instructionAt index: Int, in program: Program) -> Bool {
        return tryReplacing(instructionAt: index, with: Instruction.NOP, in: program)
    }
    
    /// Attempt multiple replacements at once.
    @discardableResult
    func tryReplacements(_ replacements: [(Int, Instruction)], in program: Program) -> Bool {
        var originalInstructions = [(Int, Instruction)]()
        var abort = false, result = false
        for (index, newInstr) in replacements {
            if instructionsToKeep.contains(index) {
                abort = true
                break
            }
            let origInstr = program.replace(instructionAt: index, with: newInstr)
            originalInstructions.append((index, origInstr))
        }
        
        if !abort {
            result = test(program)
        }
        
        if !result {
            // Revert change
            for (index, origInstr) in originalInstructions {
                program.replace(instructionAt: index, with: origInstr)
            }
        }
        
        return result
    }
    
    /// Attempt the removal of multiple instructions at once.
    @discardableResult
    func tryNopping(_ indices: [Int], in program: Program) -> Bool {
        var replacements = [(Int, Instruction)]()
        for index in indices {
            replacements.append((index, Instruction.NOP))
        }
        return tryReplacements(replacements, in: program)
    }
}

protocol Reducer {
    /// Attempt to reduce the given program in some way and return the result.
    ///
    /// The returned program can have non-contiguous variable names but must,
    /// after normailization, be fully valid.
    func reduce(_ program: Program, with verifier: ReductionVerifier) -> Program
}
