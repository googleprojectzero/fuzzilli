// Copyright 2020 Google LLC
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

public class SpliceEngine: ComponentBase, FuzzEngine {
    // TODO: make this configurable somehow.
    private let spliceRounds: Int

    private let consecutiveSplices: Int

    public init(consecutiveSplices: Int) {
        self.consecutiveSplices = consecutiveSplices
        self.spliceRounds = 3

        super.init(name: "SpliceEngine")
    }

    override func initialize() {}

    public func fuzzOne(_ group: DispatchGroup) {
        // Create a base program which is already a splice.
        let b = self.fuzzer.makeBuilder(mode: .aggressive)
        b.splice(from: self.fuzzer.corpus.randomElement())

        // get the base program.
        let baseProgram = b.finalize()
        b.append(baseProgram)

        for _ in 0..<consecutiveSplices {
            // splice a random sample from the corpus.
            b.splice(from: self.fuzzer.corpus.randomElement())
            let splicedProgram = b.finalize()

            let (outcome, newCoverage) = self.execute(splicedProgram)

            if outcome == .succeeded && (newCoverage || probability(0.8)) {
                b.append(splicedProgram)
            } else {
                b.append(baseProgram)
            }
        }
    }
}
