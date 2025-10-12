// Copyright 2022 Google LLC
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

// Resolves variable reassignments:
//
//     v0 <- LoadInt(42)
//     v1 <- LoadString("foobar")
//     Reassign v0, v1
//     v2 <- LoadBuiltin("print")
//     v3 <- CallFunction v2, v0
//
// becomes:
//
//     v0 <- LoadInt(42)
//     v1 <- LoadString("foobar")
//     Reassign v0, v1
//     v2 <- LoadBuiltin("print")
//     v3 <- CallFunction v2, v1
//                            ^^
//
// This now allows subsequent reductions to remove the reassignment, which is no longer required:
//
//     v0 <- LoadString("foobar")
//     v1 <- LoadBuiltin("print")
//     v2 <- CallFunction v1, v0
//
// Note that this reducer may change the semantics of the program, for example if reassigned variables are themselves reassigned again.
// However, the reducer will still ensure that its changes to not modify the important aspects of the program before committing them.
//
// TODO(saelo): consider replacing this special-purpose reducer with the generic DataFlowSimplifier.
// For that, the DataFlowSimplifier would also need to consider reassigned inputs as candidate variables
// and then only choose from the read-only inputs as replacements. Then it should mostly just work.
struct ReassignmentReducer: Reducer {
    func reduce(with helper: MinimizationHelper) {
        var reassignedVariables = VariableMap<Variable>()
        var reassignedVariableStack: [[Variable]] = [[]]
        var newCode = Code()
        var didChangeCode = false

        for instr in helper.code {
            if instr.isBlockEnd {
                let outOfScopeReassignments = reassignedVariableStack.removeLast()
                for v in outOfScopeReassignments {
                    reassignedVariables.removeValue(forKey: v)
                }
            }
            if instr.isBlockStart {
                reassignedVariableStack.append([])
            }

            if instr.op is Reassign {
                // Don't modify the inputs or reassignments, otherwise v1 = v2; v1 = v3; would become v1 = v2; v2 = v3
                newCode.append(instr)

                // Register the variable mapping
                reassignedVariables[instr.input(0)] = instr.input(1)
                reassignedVariableStack[reassignedVariableStack.count - 1].append(instr.input(0))

                // If the reassigned variable is itself the replacement of another variable, then that mapping becomes invalid:
                //  v0 = 42
                //  v1 = 43
                //  v2 = 44
                //
                //  v1 = v0
                //  v0 = v2
                //
                //  => v1 is still 42, not 44
                for (old, new) in reassignedVariables where new == instr.input(0) {
                    reassignedVariables.removeValue(forKey: old)
                }
            } else {
                let inouts = instr.inouts.map({ reassignedVariables[$0] ?? $0 })
                if inouts[...] != instr.inouts { didChangeCode = true }
                newCode.append(Instruction(instr.op, inouts: inouts, flags: .empty))
            }
        }

        assert(newCode.isStaticallyValid())
        if didChangeCode {
            helper.testAndCommit(newCode)
        }
    }
}
