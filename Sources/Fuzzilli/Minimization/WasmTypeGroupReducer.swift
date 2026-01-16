// Copyright 2025 Google LLC
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

struct WasmTypeGroupReducer: Reducer {
    func reduce(with helper: MinimizationHelper) {
        // Compute all candidates: intermediate operations in a data flow chain.
        var candidates = [Int]()
        var uses = VariableMap<Int>()
        for instr in helper.code {
            for input in instr.inputs {
                uses[input]? += 1
            }


            guard instr.op is WasmTypeOperation else { continue }
            // Define the usages for all WasmTypeOperation so that we also count usages of a type
            // inside a type group (i.e. by other type operations).
            for output in instr.outputs {
                uses[output] = 0
            }

            // For now, we only consider EndTypeGroup instructions.
            guard case .wasmEndTypeGroup = instr.op.opcode else  { continue }

            candidates.append(instr.index)
            for (input, output) in zip(instr.inputs, instr.outputs) {
                // Subtract 1 as the input in the WasmEndTypeGroup itself is not a reason to keep
                // the type. However, if the type is used inside the type group, it also needs to be
                // exposed by the type group. Right now the JSTyper requires that all types defined
                // in a type group are exposed by their WasmEndTypeGroup instruction.
                uses[output]! += uses[input]! - 1
            }
        }

        // Remove those candidates whose outputs are all used.
        candidates = candidates.filter {helper.code[$0].allOutputs.map({ uses[$0]! }).contains {$0 == 0}}

        if candidates.isEmpty {
            return
        }

        // Simplify each remaining candidate.
        var replacements = [(Int, Instruction)]()
        for candidate in candidates {
            let instr = helper.code[candidate]
            assert(instr.op is WasmEndTypeGroup)
            assert(instr.inputs.count == instr.outputs.count)
            let newInoutsMap = zip(instr.inputs, instr.outputs).filter {uses[$0.1]! > 0}
            let newInouts = newInoutsMap.map {$0.0} + newInoutsMap.map {$0.1}
            let newInstr = Instruction(WasmEndTypeGroup(typesCount: newInoutsMap.count), inouts: newInouts, flags: .empty)
            replacements.append((candidate, newInstr))
        }
        helper.tryReplacements(replacements, renumberVariables: true)
    }
}
