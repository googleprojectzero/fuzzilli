// Copyright 2026 Google LLC
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
import Testing

@testable import Fuzzilli

/// Differential testsuite for `InstructionSimplifier.simplifyMultiInstructions`.
///
/// Unlike the rest of the minimizer, which only has to preserve the aspects that the
/// ProgramEvaluator is looking for, this simplification is expected to preserve the observable
/// behaviour of the program. Only its one approximation, that iterating an array is equivalent to
/// loading its elements by index, is not covered here. Simplifications that are deliberately lossy
/// therefore must not be added to this function.
///
/// Reusing the .js files of the compiler testsuite, this verifies that:
///  - The code is parsed into an AST, then compiled to FuzzIL
///  - `simplifyMultiInstructions` is run on the resulting program
///  - Both the original and the simplified program are lifted back to JavaScript and executed
///  - The test passes if there are no errors along the way and if both outputs are identical
@Suite(.enabled(if: shouldRunCompilerTests()))
struct MultiInstructionSimplifierTests {
    let testcases: CompilerTestcases

    init() throws {
        self.testcases = try CompilerTestcases()
    }

    @Test func testMultiInstructionSimplifierPreservesBehaviour() throws {
        let fuzzer = makeMockFuzzer(evaluator: AlwaysAcceptingEvaluator())

        var simplifiedTestcases = Set<String>()
        for testcasePath in testcases.paths {
            let testName = URL(fileURLWithPath: testcasePath).lastPathComponent

            guard let program = testcases.compile(testcaseAt: testcasePath) else { continue }
            guard let simplified = simplifyMultiInstructions(of: program, with: fuzzer) else {
                // Nothing was simplified in this testcase, so there is nothing to compare.
                continue
            }
            simplifiedTestcases.insert(testName)

            // testAndCommit only asserts these in debug builds.
            #expect(
                simplified.code.isStaticallyValid(),
                "Simplifying \(testName) produced statically invalid code")
            #expect(
                simplified.code.variablesAreNumberedContinuously(),
                "Simplifying \(testName) left the variables numbered discontinuously")

            // Compare against the unsimplified program rather than against the original .js file,
            // so that a compiler or lifter regression only fails testFuzzILCompiler.
            guard
                let expectedOutput = try testcases.execute(
                    testcases.lifter.lift(program), describedAs: "TestCase \(testName)"),
                let actualOutput = try testcases.execute(
                    testcases.lifter.lift(simplified),
                    describedAs: "TestCase \(testName) after simplification")
            else { continue }

            #expect(
                expectedOutput == actualOutput,
                "Testcase \(testName) failed.\nExpected output:\n\(expectedOutput)\nActual output:\n\(actualOutput)"
            )
        }

        // Make sure this testcase does not silently turn into a no-op, for example because the
        // compiler stops emitting destructuring operations for these testcases.
        for expectedTestcase in ["destructuring.js", "nested_destructuring.js"] {
            #expect(
                simplifiedTestcases.contains(expectedTestcase),
                "No destructuring operation in \(expectedTestcase) was simplified. Simplified testcases: \(simplifiedTestcases.sorted())"
            )
        }
    }

    /// Runs only `simplifyMultiInstructions` on the given program.
    ///
    /// Returns nil if nothing could be simplified.
    private func simplifyMultiInstructions(of program: Program, with fuzzer: Fuzzer) -> Program? {
        return fuzzer.sync {
            let helper = MinimizationHelper(
                for: ProgramAspects(outcome: .succeeded), forCode: program.code, of: fuzzer,
                runningOnFuzzerQueue: true)
            InstructionSimplifier().simplifyMultiInstructions(with: helper)
            guard helper.didReduce else { return nil }
            return Program(with: helper.finalize())
        }
    }
}
