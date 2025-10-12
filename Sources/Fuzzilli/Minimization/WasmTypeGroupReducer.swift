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

            // For now, we only consider EndTypeGroup instructions.
            guard case .wasmEndTypeGroup = instr.op.opcode else  { continue }

            candidates.append(instr.index)
            for output in instr.outputs {
                uses[output] = 0
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
