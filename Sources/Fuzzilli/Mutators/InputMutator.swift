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

/// A mutator that changes the input variables of instructions in a program.
public class InputMutator: BaseInstructionMutator {
    /// Whether this instance is type aware or not.
    /// A type aware InputMutator will attempt to find "compatible" replacement
    /// variables, which have roughly the same type as the replaced variable.
    public let isTypeAware: Bool

    /// The name of this mutator.
    public override var name: String {
        return isTypeAware ? "InputMutator (type aware)" : "InputMutator"
    }

    public init(isTypeAware: Bool) {
        self.isTypeAware = isTypeAware
        var maxSimultaneousMutations = defaultMaxSimultaneousMutations
        // A type aware instance can be more aggressive. Based on simple experiments and
        // the mutator correctness rates, it can very roughly be twice as aggressive.
        if isTypeAware {
            maxSimultaneousMutations *= 2
        }
        super.init(maxSimultaneousMutations: maxSimultaneousMutations)
    }

    public override func canMutate(_ instr: Instruction) -> Bool {
        return instr.numInputs > 0
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        var inouts = b.adopt(instr.inouts)

        // Replace one input
        let selectedInput = Int.random(in: 0..<instr.numInputs)
        // Inputs to block end instructions must be taken from the outer scope since the scope
        // closed by the instruction is currently still active.
        let replacement: Variable
        if (isTypeAware) {
            let type = b.type(of: inouts[selectedInput]).generalize()
            // We are guaranteed to find at least the current input.
            replacement = b.randVar(ofType: type, excludeInnermostScope: instr.isBlockEnd)!
        } else {
            replacement = b.randVar(excludeInnermostScope: instr.isBlockEnd)
        }
        b.trace("Replacing input \(selectedInput) (\(inouts[selectedInput])) with \(replacement)")
        inouts[selectedInput] = replacement

        b.append(Instruction(instr.op, inouts: inouts))
    }
}
