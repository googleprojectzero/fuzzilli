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

// Attempts to replace code snippets with other, potentially shorter snippets.
struct ReplaceReducer: Reducer {
    // TODO: other things to replace
    //   - special function definition with plain function definitions
    //   - other call instructions with regular function calls
    //   - ObjectWithSpread and ArrayWithSpread with their no-spread versions
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        for instr in code {
            switch instr.op {
            case let op as Construct:
                // Try replacing with a simple call
                let newOp = CallFunction(numArguments: op.numArguments, spreads: [Bool](repeating: false, count: op.numArguments))
                verifier.tryReplacing(instructionAt: instr.index, with: Instruction(newOp, inouts: instr.inouts), in: &code)
            default:
                break
            }
        }
    }
}
