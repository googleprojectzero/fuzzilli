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

/// Reducer to remove unnecessary arguments in function calls.
struct CallArgumentReducer: Reducer {
    let minArgCount: Int
    
    init(keepingAtLeast minArgumentCount: Int = 0) {
        self.minArgCount = minArgumentCount
    }
    
    // TODO probably should remove as much as it can?
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        for instr in code {
            switch instr.op {
            case let op as CallFunction:
                guard op.numArguments > minArgCount else {
                    break
                }
                
                let newOp = CallFunction(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                let newInstr = Instruction(newOp, output: instr.output, inputs: Array(instr.inputs.dropLast()))
                verifier.tryReplacing(instructionAt: instr.index, with: newInstr, in: &code)
                
            case let op as CallMethod:
                guard op.numArguments > minArgCount else {
                    break
                }
                
                let newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                let newInstr = Instruction(newOp, output: instr.output, inputs: Array(instr.inputs.dropLast()))
                verifier.tryReplacing(instructionAt: instr.index, with: newInstr, in: &code)

            case let op as CallComputedMethod:
                guard op.numArguments > minArgCount else {
                    break
                }

                let newOp = CallComputedMethod(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                let newInstr = Instruction(newOp, output: instr.output, inputs: Array(instr.inputs.dropLast()))
                verifier.tryReplacing(instructionAt: instr.index, with: newInstr, in: &code)
                
            case let op as Construct:
                guard op.numArguments > minArgCount else {
                    break
                }
                
                let newOp = Construct(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                let newInstr = Instruction(newOp, output: instr.output, inputs: Array(instr.inputs.dropLast()))
                verifier.tryReplacing(instructionAt: instr.index, with: newInstr, in: &code)
            
            case let op as CallSuperConstructor:
                guard op.numArguments > minArgCount else {
                    break
                }

                let newOp = CallSuperConstructor(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                let newInstr = Instruction(newOp, output: instr.output, inputs: Array(instr.inputs.dropLast()))
                verifier.tryReplacing(instructionAt: instr.index, with: newInstr, in: &code)
                
            default:
                break
            }
            
        }
    }
}
