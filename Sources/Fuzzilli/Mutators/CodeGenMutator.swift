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
        if instr.op.requiredContext.contains(.wasmTypeGroup) && !(instr.op is WasmEndTypeGroup) {
            return false
        }

        return variableAnalyzer.visibleVariables.count >= minVisibleVariables && !deadCodeAnalyzer.currentlyInDeadCode
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        switch instr.op.opcode {
        case .wasmEndTypeGroup:
            mutateTypeGroup(instr, b)
        default:
            b.adopt(instr)
            assert(b.numberOfVisibleVariables >= minVisibleVariables)
            b.build(n: defaultCodeGenerationAmount, by: .generating)
        }
    }

    /// This is special handling for the EndTypeGroup instruction, it needs all newly allocated types as inputs.
    private func mutateTypeGroup(_ instr: Instruction, _ b: ProgramBuilder) {
        assert(instr.op is WasmEndTypeGroup)
        assert(b.context.contains(.wasmTypeGroup))

        // We need to update the inputs later, so take note of the visible variables here.
        let oldVisibleVariables = b.visibleVariables

        b.build(n: defaultCodeGenerationAmount, by: .generating)

        let newVisibleVariables = b.visibleVariables.filter { v in
            let t = b.type(of: v)
            return !oldVisibleVariables.contains(v) && t.wasmTypeDefinition?.description != .selfReference && t.Is(.wasmTypeDef())
        }

        let newOp = WasmEndTypeGroup(typesCount: instr.inputs.count + newVisibleVariables.count)
        // We need to keep and adopt the inputs that are still there.
        let newInputs = b.adopt(instr.inputs) + newVisibleVariables
        // Adopt the old outputs and allocate new output variables for the new outputs
        let newOutputs = b.adopt(instr.outputs) + newVisibleVariables.map { _ in
            b.nextVariable()
        }

        b.append(Instruction(newOp, inouts: Array(newInputs) + newOutputs, flags: instr.flags))
    }
}
