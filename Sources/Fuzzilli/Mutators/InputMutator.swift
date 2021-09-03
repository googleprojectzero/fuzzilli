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

/// A mutator that changes the input variables of instructions in a program.
public class InputMutator: BaseInstructionMutator {
    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousMutations)
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        return instr.numInputs > 0
    }
    
    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        var inouts = b.adopt(instr.inouts)
        
        // Replace one input
        let selectedInput = Int.random(in: 0..<instr.numInputs)
        b.trace("Mutating input \(selectedInput)")
        inouts[selectedInput] = instr.isBlockEnd ? b.randVarFromOuterScope() : b.randVar()
                
        b.append(Instruction(instr.op, inouts: inouts))
    }
}
