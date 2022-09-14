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

/// A mutator designed to call already JITed functions with different arguments or environment.
///
/// In a way, this is a workaround for the fact that we don't have coverage feedback from JIT code.
public class JITStressMutator: Mutator {
    public override init() {}

    override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        b.append(program)

        // Possibly change the environment
        b.generate(n: Int.random(in: 1...defaultMaxCodeGenerationAmount))

        // Call an existing (and hopefully JIT compiled) function again
        guard let f = b.randVar(ofConservativeType: .function()) else { return nil }
        guard let arguments = b.randCallArguments(for: f) else { return nil }
        b.callFunction(f, withArgs: arguments)
        return b.finalize()
    }
}
