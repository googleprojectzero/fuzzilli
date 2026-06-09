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

/// A mutator that generates new code at random positions in a program.
public class CodeGenMutator: BaseInstructionMutator {
    private var deadCodeAnalyzer = DeadCodeAnalyzer()
    private var variableAnalyzer = VariableAnalyzer()
    private let minVisibleVariables = 3

    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousCodeGenerations)
        assert(defaultCodeGenerationAmount >= ProgramBuilder.minBudgetForRecursiveCodeGeneration)
    }

    public override func beginMutation(of program: Program) {
        deadCodeAnalyzer = DeadCodeAnalyzer()
        variableAnalyzer = VariableAnalyzer()
    }

    public override func canMutate(_ instr: Instruction) -> Bool {
        deadCodeAnalyzer.analyze(instr)
        variableAnalyzer.analyze(instr)
        // We can only generate code if there are some visible variables to use, and it only
        // makes sense to generate code if we're not currently in dead code.

        // Don't CodeGen on Type definition instructions, with this line they are not available as candidates which effectively compresses the program and avoids useless CodeGeneration.
        // (As any emitted type would not be an input to the EndTypeGroup instruction).
        if (instr.op.requiredContext.contains(.wasmTypeGroup) && !(instr.op is WasmEndTypeGroup))
            || (instr.op is WasmBeginTypeGroup)
        {
            return false
        }

        // The visible variables don't necessarily need to be JS variables; Wasm code generators can run without JS variables.
        return variableAnalyzer.visibleVariables.count >= minVisibleVariables
            && !deadCodeAnalyzer.currentlyInDeadCode
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        switch instr.op.opcode {
        case .wasmEndTypeGroup:
            b.buildIntoTypeGroup(endTypeGroupInstr: instr, by: .generating)
        default:
            b.adopt(instr)

            if b.numberOfVisibleJsVariables < minVisibleVariables {
                // VariableAnalyzer counts the number of visible variables, not only JS variables. It also overapproxiamtes, e.g., JS labels are considered visible even after opening a new function scope.
                // So, canMutate() may return true even if the _actual_ number of visible variables is less than minVisibleVariables, potentially triggering a call to mutate() later.
                // In contrast, the analysis of ProgramBuilder (=b.numberOfVisibleJSVariables) is precise in this regard.
                // Since b.build() might trigger generators which require JS variables to be visible, we account for this discrepancy here by building some JS variables.
                // We only generate variables if we are in a .javascript context, so we're not generating variables in, e.g., a switch block, which wouldn't be allowed.
                if b.context.contains(.javascript) {
                    b.buildValues(minVisibleVariables - b.numberOfVisibleJsVariables)
                } else if b.context.contains(.objectLiteral) || b.context.contains(.classDefinition)
                    || b.context.contains(.switchBlock)
                {
                    // In these contexts, we might still run code generators which depend on having JS variables available, but we cannot insert more code here to ensure we have enough variables. Thus, our only option is to bail out.
                    return
                }
                // Otherwise, we are in a context where we only run code generators which don't require JS variables (such as wasm contexts).
            }
            assert(b.numberOfVisibleVariables > 0)
            assert(!b.context.contains(.switchBlock) || b.numberOfVisibleJsVariables > 0)
            assert(!b.context.contains(.classDefinition) || b.numberOfVisibleJsVariables > 0)
            assert(!b.context.contains(.objectLiteral) || b.numberOfVisibleJsVariables > 0)
            b.build(n: defaultCodeGenerationAmount, by: .generating)
        }
    }
}
