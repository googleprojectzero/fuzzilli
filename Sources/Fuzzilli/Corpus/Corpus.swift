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
/// and specifies how much energy to allocate to that seed

public protocol Corpus : Component {
    var size: Int { get }
    var isEmpty: Bool { get }
    // Whether or not the corpus requires edge tracking to function
    var requiresEdgeTracking: Bool { get }

    /// Add new programs to the corpus, from various sources
    func add(_ program: Program)
    func add(_ program: Program, _ aspects: ProgramAspects)
    func add(_ programs: [Program])
    
    /// Returns a random element for use in a mutator.
    /// The program is should not be used as a seed for a fuzz run
    func randomElement() -> Program

    /// Returns the next seed that should be used, and the energy (number of rounds)
    /// that should be assigned to it
    func getNextSeed() -> (seed: Program, energy: UInt64)

    /// A corpus needs to be able to import/export its state. 
    /// Currently, only the seed programs are handled, and corpus specific state is lost
    func exportState() throws -> Data
    func importState(_ buffer: Data) throws
}