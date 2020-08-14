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
    var analyzer = DeadCodeAnalyzer()
    
    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousMutations)
    }
    
    public override func beginMutation(of program: Program) {
        analyzer = DeadCodeAnalyzer()
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        analyzer.analyze(instr)
        return !analyzer.currentlyInDeadCode
    }
    
    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        b.adopt(instr, keepTypes: true)
        b.generate(n: Int.random(in: 1...defaultMaxCodeGenerationAmount))
    }
}
