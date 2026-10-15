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

import Foundation

// The TypeGroupReducer removes unused type definition. A type definition is considered unused if it
// is not used by any other operation but the WasmEndTypeGroup and if the corresponding output
// of the WasmEndTypeGroup is not used anywhere inside the program.
// Usages by unused type definitions don't count. With custom descriptors, if B <: A and DA
// describes A, then B needs a descriptor DB <: DA. So DB is also used if DA and B are used.
// TODO(bettscheider): Track that WasmRefGetDesc implicitly uses the descriptor of its input's
// struct type. Currently, that descriptor may be removed, which makes the program fail to lift.
//
// This reducer preserves the invariant that each type defined inside a type group is also exposed
// by the WasmEndTypeGroup operation.
// Note that a WasmResolveForwardReference(v0, v1) makes v1 used and prevents its removal by this
// reducer. However, the GenericInstructionReducer will try to remove the
// WasmResolveForwardReference, so this is not an issue.
struct WasmTypeGroupReducer: Reducer {
    func reduce(with helper: MinimizationHelper) {
        var usedDefinitions = IndexSet()
        var definitions = VariableMap<Int>()

        func markUsed(_ type: Variable) {
            if let definition = definitions[type], usedDefinitions.insert(definition).inserted {
                helper.code[definition].inputs.forEach(markUsed)
            }
        }
        func isUsed(_ type: Variable) -> Bool { usedDefinitions.contains(definitions[type]!) }

        for instr in helper.code {
            if instr.op is WasmTypeOperation {
                for output in instr.outputs {
                    definitions[output] = instr.index
                }
            }

            if instr.op is WasmEndTypeGroup {
                for (input, output) in zip(instr.inputs, instr.outputs) {
                    definitions[output] = definitions[input]!
                }
            } else if !(instr.op is WasmTypeOperation) || instr.op is WasmResolveForwardReference {
                // Any usage but by the WasmEndTypeGroup and type definitions should be tracked.
                // (This includes WasmResolveForwardReference.)
                for input in instr.inputs {
                    markUsed(input)
                }
            }
        }

        if definitions.isEmpty {
            return
        }

        // Custom descriptors rule (see above): DB's inputs 0 and 1 are DA and B. Marking DB can
        // make more types used, so search again after each one.
        while let descriptor = helper.code.first(where: {
            guard let op = $0.op as? WasmDefineStructType, op.hasSuperType, op.hasDescribes else {
                return false
            }
            return !isUsed($0.output) && isUsed($0.input(0)) && isUsed($0.input(1))
        }) {
            markUsed(descriptor.output)
        }

        // Create replacements for WasmEndTypeGroup and collect type definitions to remove.
        var toRemove = IndexSet()
        var endTypeGroupReplacements = [Int: Instruction]()

        for instr in helper.code {
            guard case .wasmEndTypeGroup = instr.op.opcode else { continue }

            let keptInoutsMap = zip(instr.inputs, instr.outputs).filter { isUsed($0.1) }
            if keptInoutsMap.count == instr.inputs.count { continue }

            let unusedInputs =
                zip(instr.inputs, instr.outputs).filter { !isUsed($0.1) }.map { $0.0 }
            for input in unusedInputs {
                toRemove.insert(definitions[input]!)
            }

            let newInouts = keptInoutsMap.map { $0.0 } + keptInoutsMap.map { $0.1 }
            endTypeGroupReplacements[instr.index] = Instruction(
                WasmEndTypeGroup(typesCount: keptInoutsMap.count), inouts: newInouts)
        }

        if toRemove.isEmpty {
            return
        }

        var newCode = Code(
            helper.code
                .filter { !toRemove.contains($0.index) }
                .map { endTypeGroupReplacements[$0.index] ?? $0 }, isBundle: helper.code.isBundle)

        newCode.renumberVariables()
        helper.testAndCommit(newCode)
    }
}
