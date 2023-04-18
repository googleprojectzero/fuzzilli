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

/// Base class for mutators that operate on or at single instructions.
public class BaseInstructionMutator: Mutator {
    let maxSimultaneousMutations: Int

    public init(name: String? = nil, maxSimultaneousMutations: Int = 1) {
        self.maxSimultaneousMutations = maxSimultaneousMutations
        super.init(name: name)
    }

    override final func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        beginMutation(of: program)

        var candidates = [Int]()
        for instr in program.code {
            if canMutate(instr) {
                candidates.append(instr.index)
            }
        }

        guard candidates.count > 0 else {
            return nil
        }

        var toMutate = Set<Int>()
        for _ in 0..<Int.random(in: 1...maxSimultaneousMutations) {
            toMutate.insert(chooseUniform(from: candidates))
        }

        b.adopting(from: program) {
            for instr in program.code {
                if toMutate.contains(instr.index) {
                    mutate(instr, b)
                } else {
                    b.adopt(instr)
                }
            }
        }

        return b.finalize()
    }

    /// Can be overwritten by child classes.
    public func beginMutation(of program: Program) {}

    /// Overridden by child classes.
    /// Determines the set of instructions that can be mutated by this mutator
    public func canMutate(_ instr: Instruction) -> Bool {
        fatalError("This method must be overridden")
    }

    /// Overridden by child classes.
    /// Mutate a single statement
    public func mutate(_ instr: Instruction, _ builder: ProgramBuilder) {
        fatalError("This method must be overridden")
    }
}

