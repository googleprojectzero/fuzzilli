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
        return variableAnalyzer.visibleVariables.count >= minVisibleVariables && !deadCodeAnalyzer.currentlyInDeadCode
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        b.adopt(instr)
        assert(b.numberOfVisibleVariables >= minVisibleVariables)
        b.build(n: defaultCodeGenerationAmount, by: .generating)
    }
}
