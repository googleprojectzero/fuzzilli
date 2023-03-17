// Copyright 2023 Google LLC
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

// Attempts deduplicate variables containing the same values.
struct DeduplicatingReducer: Reducer {
    func reduce(_ code: inout Code, with helper: MinimizationHelper) {
        // Currently we only handle LoadBuiltin, but the code could easily be
        // extended to cover other types of values as well.
        // It's not obvious however which other values would benefit from this.
        // For example, for identical integer values it may be interesting to
        // leave them as separate variables so they can be mutated independently.
        //
        // We don't handle variable reassignments here explicitly. Instead, we
        // assume that reassigned variables will change the program's behaviour.
        //
        // For simplicity, we perform all replacements at once. We could also
        // try to replace each builtin individually though.
        var replacements = [(Int, Instruction)]()

        var deduplicatedVariables = VariableMap<Variable>()
        var visibleBuiltins = Stack<[String]>([[]])
        var variableForBuiltin = [String: Variable]()
        for instr in code {
            // Instruction replacement.
            let oldInouts = Array(instr.inouts)
            let newInouts = oldInouts.map({ deduplicatedVariables[$0] ?? $0 })
            if oldInouts != newInouts {
                replacements.append((instr.index, Instruction(instr.op, inouts: newInouts)))
            }

            // Scope management.
            if instr.isBlockEnd {
                for builtin in visibleBuiltins.pop() {
                    variableForBuiltin.removeValue(forKey: builtin)
                }
            }
            if instr.isBlockStart {
                visibleBuiltins.push([])
            }

            // Value deduplication.
            if let op = instr.op as? LoadBuiltin {
                if let replacement = variableForBuiltin[op.builtinName] {
                    deduplicatedVariables[instr.output] = replacement
                } else {
                    // Each builtin must only be present once (all other instances are replaced with the first one).
                    assert(visibleBuiltins.elementsStartingAtBottom().allSatisfy({ !$0.contains(op.builtinName) }))
                    visibleBuiltins.top.append(op.builtinName)
                    variableForBuiltin[op.builtinName] = instr.output
                }
            }
        }

        if !replacements.isEmpty {
            helper.tryReplacements(replacements, in: &code)
        }
    }
}
