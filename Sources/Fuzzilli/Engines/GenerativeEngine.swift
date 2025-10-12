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

import Foundation

/// Purely generative fuzzing engine, mostly used for initial corpus generation when starting without an existing corpus.
public class GenerativeEngine: FuzzEngine {
    /// Approximate number of instructions to generate in additional to any prefix code.
    private let numInstructionsToGenerate = 10

    public init() {
        super.init(name: "GenerativeEngine")
    }

    /// Perform one round of fuzzing: simply generate a new program and execute it
    public override func fuzzOne(_ group: DispatchGroup) {
        let b = fuzzer.makeBuilder()

        // Start by building a prefix that creates some variables (of known types) that the following CodeGenerators can then make use of.
        b.buildPrefix()
        // Then generate the actual code.
        b.build(n: numInstructionsToGenerate, by: .generating)
        let program = b.finalize()

        let _ = execute(program)
    }
}
