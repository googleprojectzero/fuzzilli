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

/// A mutator that inserts a program in full into another one.
public class CombineMutator: BaseInstructionMutator {
    var deadCodeAnalyzer = DeadCodeAnalyzer()
    var contextAnalyzer = ContextAnalyzer()

    public init() {}

    public override func beginMutation(of program: Program) {
        deadCodeAnalyzer = DeadCodeAnalyzer()
        contextAnalyzer = ContextAnalyzer()
    }

    public override func canMutate(_ instr: Instruction) -> Bool {
        deadCodeAnalyzer.analyze(instr)
        contextAnalyzer.analyze(instr)
        let inDeadCode = deadCodeAnalyzer.currentlyInDeadCode
        let inScriptContext = contextAnalyzer.context.contains(.javascript)

        // We can mutate this sample, iff we are not in dead code and we also
        // have script context, as this is always required for a random sample.
        return !inDeadCode && inScriptContext
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        b.adopt(instr)
        let other = b.fuzzer.corpus.randomElementForSplicing()
        b.trace("Inserting program \(other.id)")
        b.append(other)
    }
}
