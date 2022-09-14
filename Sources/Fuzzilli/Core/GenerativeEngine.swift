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
public class GenerativeEngine: ComponentBase, FuzzEngine {
    /// Size of the generated programs.
    private let programSize: Int

    /// Stats for this generative engine.
    private var stats = ProgramProducerStats()

    public init(programSize: Int) {
        self.programSize = programSize
        super.init(name: "GenerativeEngine")
    }

    /// Perform one round of fuzzing: simply generate a new program and execute it
    public func fuzzOne(_ group: DispatchGroup) {
        let b = fuzzer.makeBuilder()
        b.performSplicingDuringCodeGeneration = false
        b.generate(n: programSize)
        let program = b.finalize()
        let _ = execute(program, stats: &stats)
    }
}
