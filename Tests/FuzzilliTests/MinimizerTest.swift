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

import XCTest
@testable import Fuzzilli

class MinimizerTests: XCTestCase {
    let dummyAspects = ProgramAspects(outcome: .succeeded)
    
    func testGenericInstructionMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var n1 = b.loadInt(42)
        let n2 = b.loadInt(43)
        var n3 = b.binary(n1, n1, with: .Add)
        let n4 = b.binary(n2, n2, with: .Add)

        evaluator.nextInstructionIsImportant(in: b)
        b.loadString("foo")
        var bar = b.loadString("bar")
        let baz = b.loadString("baz")

        var o1 = b.createObject(with: [:])
        evaluator.nextInstructionIsImportant(in: b)
        b.storeComputedProperty(n3, as: bar, on: o1)
        let o2 = b.createObject(with: [:])
        b.storeComputedProperty(n4, as: baz, on: o2)

        let originalProgram = b.finalize()

        // Build expected output program.
        n1 = b.loadInt(42)
        n3 = b.binary(n1, n1, with: .Add)
        b.loadString("foo")
        bar = b.loadString("bar")
        o1 = b.createObject(with: [:])
        b.storeComputedProperty(n3, as: bar, on: o1)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = fuzzer.minimizer.minimize(originalProgram, withAspects: dummyAspects)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    // A mock evaluator that will XYZ
    class EvaluatorForMinimizationTests: ProgramEvaluator {
        /// The instructions that are important and must not be removed.
        var importantInstructions = Set<Int>()

        /// The last program executed. Required to check if an important instruction has been removed.
        var lastExecutedProgram = Program()

        func nextInstructionIsImportant(in b: ProgramBuilder) {
            importantInstructions.insert(b.indexOfNextInstruction())
        }

        func evaluate(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
            // Check if any important instructions were removed, and if yes return false.
            // We only need to check for Nop here since the minimizers replace instructions with Nops first, and only "really" delete them at the end of minimization.
            for instr in lastExecutedProgram.code {
                if importantInstructions.contains(instr.index) && instr.op is Nop {
                    return false
                }
            }
            return true
        }

        var currentScore: Double {
            return 13.37
        }

        func initialize(with fuzzer: Fuzzer) {
            fuzzer.events.PreExecute.addListener { program in
                self.lastExecutedProgram = program
            }
        }

        var isInitialized: Bool {
            return true
        }

        func exportState() -> Data {
            return Data()
        }

        func importState(_ state: Data) {}

        func computeAspectIntersection(of program: Program, with aspects: ProgramAspects) -> ProgramAspects? {
            return nil
        }

        func resetState() {}
    }
}

extension MinimizerTests {
    static var allTests : [(String, (MinimizerTests) -> () throws -> Void)] {
        return [
            ("testGenericInstructionMinimization", testGenericInstructionMinimization),
        ]
    }
}
