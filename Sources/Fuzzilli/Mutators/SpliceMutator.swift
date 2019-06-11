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

/// A mutator that inserts a "slice" of a program at a random position in another program.
///
/// A "slice" is defined as (not necessarily contiguous) sequence of instructions that define all used variables.
public class SpliceMutator: BaseInstructionMutator {
    var analyzer = DeadCodeAnalyzer()
    
    public init() {
        super.init(maxSimultaneousMutations: 2)
    }
    
    override public func beginMutation(of program: Program) {
        analyzer = DeadCodeAnalyzer()
    }
    
    override public func canMutate(_ instr: Instruction) -> Bool {
        analyzer.analyze(instr)
        return !analyzer.currentlyInDeadCode
    }
    
    override public func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        b.adopt(instr)
        
        // Step 1: select program to copy a slice from
        let program = b.fuzzer.corpus.randomElement(increaseAge: false)
        
        // Step 2 pick any instruction from the selected program
        var idx = 0
        var counter = 0
        repeat {
            counter += 1
            idx = Int.random(in: 0..<program.size)
            // Blacklist a few operations
        } while counter < 25 && (program[idx].isJump || program[idx].isBlockEnd || program[idx].isPrimitive || program[idx].isLiteral)
        
        // Step 3: determine all necessary input instructions for the choosen instruction
        // We need special handling for blocks:
        //   If the choosen instruction is a block instruction then copy the whole block
        //   If we need an inner output of a block instruction then only copy the block instructions, not the content
        //   Otherwise copy the whole block including its content
        var needs = Set<Int>()
        var requiredInputs = VariableSet()
        
        func keep(_ instr: Instruction, includeBlockContent: Bool = false) {
            guard !needs.contains(instr.index) else { return }
            if instr.isBlock {
                let group = BlockGroup(around: instr, in: program)
                for instr in group.includingContent(includeBlockContent) {
                    requiredInputs.formUnion(instr.inputs)
                    needs.insert(instr.index)
                }
            } else {
                requiredInputs.formUnion(instr.inputs)
                needs.insert(instr.index)
            }
        }
        
        // Keep the selected instruction
        keep(program[idx], includeBlockContent: true)
        
        while idx > 0 {
            idx -= 1
            let current = program[idx]
            if !requiredInputs.isDisjoint(with: current.allOutputs) {
                let onlyNeedsInnerOutputs = requiredInputs.isDisjoint(with: current.outputs)
                keep(current, includeBlockContent: !onlyNeedsInnerOutputs)
            }
        }
        
        // Step 4: insert the slice into the currently mutated program
        b.adopting(from: program) {
            for instr in program {
                if needs.contains(instr.index) {
                    b.adopt(instr)
                }
            }
        }
    }
}
