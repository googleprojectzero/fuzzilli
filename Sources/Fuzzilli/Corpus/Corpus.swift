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

    // A simplified version based on the FuzzEngine functionality
    // Implemented here in order to obtain coverage data without dispatching the events for having
    // found new coverage
    func execAndEvalProg(_ program: Program) -> ProgramAspects? {
        let execution = fuzzer.execute(program, withTimeout: fuzzer.config.timeout * 2)
        if execution.outcome == .succeeded {
            return fuzzer.evaluator.evaluate(execution)
        }
        return nil
    }

    func prepareProgramForInclusion(_ program: Program, index: Int) {
        // Program ancestor chains only go up to the next corpus element
        program.clearParent()

        // And programs in the corpus don't keep their comments
        program.comments.removeAll()

        if fuzzer.config.inspection.contains(.history) {
            // Except for one identifying them as part of the corpus
            program.comments.add("Corpus entry #\(index) on instance \(fuzzer.id) with Corpus type \(name)", at: .header)
        }
    }

    /// Change type extensions for cached ones to save memory
    func deduplicateTypeExtensions(in program: Program, deduplicationSet: inout Set<TypeExtension>) {
        var deduplicatedTypes = ProgramTypes()
        for (variable, instrTypes) in program.types {
            for typeInfo in instrTypes {
                deduplicatedTypes.setType(
                    of: variable,
                    to: typeInfo.type.uniquified(with: &deduplicationSet),
                    after: typeInfo.index,
                    quality: typeInfo.quality
                )
            }
        }
        program.types = deduplicatedTypes
    }


}
