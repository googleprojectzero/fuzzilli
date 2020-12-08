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

/// Protocol defining a Corpus for use in Fuzzilli
/// It manages discovered programs, determines the next seed to target, 
/// and provides programs to be used in the splice mutators

public protocol Corpus : ComponentBase {
    var size: Int { get }
    var isEmpty: Bool { get }

    /// Add new programs to the corpus, from various sources.
    /// Accurate ProgramAspects must always be included, as some corpii depend on the aspects for internal data structures
    func add(_ program: Program, _ aspects: ProgramAspects)
 
    /// Returns a random element for use in a splicing
    func randomElementForSplicing() -> Program

    /// Returns the next program to be used as the basis of a mutation round
    func randomElementForMutating() -> Program

    /// A corpus needs to be able to import/export its state. 
    /// Currently, only the seed programs are handled, and corpus specific state is lost
    func exportState() throws -> Data
    func importState(_ buffer: Data) throws
}

extension Corpus {
    public func makeSeedProgram() -> Program {
        let b = fuzzer.makeBuilder()
        let objectConstructor = b.loadBuiltin("Object")
        b.callFunction(objectConstructor, withArgs: [])
        return b.finalize()
    }
}
