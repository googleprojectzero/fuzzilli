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

import Foundation

/// The core fuzzer responsible for generating and executing programs.
public class MutationEngine: ComponentBase, FuzzEngine {
    // The number of consecutive mutations to apply to a sample.
    private let numConsecutiveMutations: Int

    public init(numConsecutiveMutations: Int) {
        self.numConsecutiveMutations = numConsecutiveMutations
        super.init(name: "MutationEngine")
    }

    /// Perform one round of fuzzing.
    ///
    /// High-level fuzzing algorithm:
    ///
    ///     let parent = pickSampleFromCorpus()
    ///     repeat N times:
    ///         let current = mutate(parent)
    ///         execute(current)
    ///         if current produced crashed:
    ///             output current
    ///         elif current resulted in a runtime exception or a time out:
    ///             // do nothing
    ///         elif current produced new, interesting behaviour:
    ///             minimize and add to corpus
    ///         else
    ///             parent = current
    ///
    ///
    /// This ensures that samples will be mutated multiple times as long
    /// as the intermediate results do not cause a runtime exception.
    public func fuzzOne(_ group: DispatchGroup) {
        var parent = fuzzer.corpus.randomElementForMutating()
        var program = parent
        for _ in 0..<numConsecutiveMutations {
            var mutator = fuzzer.mutators.randomElement()
            var mutated = false
            for _ in 0..<10 {
                if let result = mutator.mutate(parent, for: fuzzer) {
                    program = result
                    mutated = true
                    mutator.stats.producedSample(addingInstructions: program.size - parent.size)
                    break
                }
                logger.verbose("\(mutator.name) failed, trying different mutator")
                mutator.stats.failedToGenerateSample()
                mutator = fuzzer.mutators.randomElement()
            }

            if !mutated {
                logger.warning("Could not mutate sample, giving up. Sample:\n\(fuzzer.lifter.lift(parent))")
                continue
            }

            let outcome = execute(program, stats: &mutator.stats)

            // Mutate the program further if it succeeded.
            if .succeeded == outcome {
                parent = program
            }
        }
    }
}
