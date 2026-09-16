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

struct RuntimeAssistedMutatorTests {
    class CrashMockScriptRunner: ScriptRunner {
        var processArguments: [String] = []
        var env: [(String, String)] = []
        func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
            // Minimization can change quotation marks. Checking for both here to be on the safe side.
            if script.contains("fuzzilli('FUZZILLI_CRASH', 0)")
                || script.contains("fuzzilli(\"FUZZILLI_CRASH\", 0)")
            {
                return MockExecution(
                    outcome: .crashed(9), stdout: "", stderr: "", fuzzout: "", execTime: 0.1)
            } else {
                return MockExecution(
                    outcome: .succeeded, stdout: "", stderr: "", fuzzout: "", execTime: 0.1)
            }
        }
        func setEnvironmentVariable(_ key: String, to value: String) {}
        func initialize(with fuzzer: Fuzzer) {}
        var isInitialized: Bool { true }
    }

    // This test checks that if *both* the instrumented and the processed programs crash,
    // we report the processed program.

    @Test func testInstrumentedAndProcessedProgramsCrash() {
        let runner = CrashMockScriptRunner()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, runner: runner)

        let semaphore = DispatchSemaphore(value: 0)

        fuzzer.sync {
            let mutator = CrashingInstrumentationMutator()
            let b = fuzzer.makeBuilder()
            b.loadInt(42)
            let program = b.finalize()

            fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
                let lifted = fuzzer.lifter.lift(ev.program)
                if lifted.contains("This is the processed program") {
                    semaphore.signal()
                }
            }

            _ = mutator.mutate(program, using: b, for: fuzzer)
        }

        let waitResult = semaphore.wait(timeout: .now() + 5)
        #expect(waitResult == .success)
    }

    // This test checks that if *only* the instrumented program crashes, we report it.

    @Test func testOnlyInstrumentedProgramCrashes() {
        let runner = CrashMockScriptRunner()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, runner: runner)

        let semaphore = DispatchSemaphore(value: 0)

        fuzzer.sync {
            let mutator = CrashingInstrumentationMutator(shouldProcessedProgramCrash: false)
            let b = fuzzer.makeBuilder()
            b.loadInt(42)
            let program = b.finalize()

            fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
                let lifted = fuzzer.lifter.lift(ev.program)
                if !lifted.contains("This is the processed program") {
                    semaphore.signal()
                }
            }

            _ = mutator.mutate(program, using: b, for: fuzzer)
        }

        let waitResult = semaphore.wait(timeout: .now() + 5)
        #expect(waitResult == .success)
    }

    // This test checks that if *only* the instrumented program crashes, this program is minimized.

    @Test(.enabled(if: shouldRunCompilerTests()))
    func testOnlyInstrumentedProgramCrashesAndIsMinimized() throws {
        class CrashEvaluator: MockEvaluator {
            override func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
                return execution.outcome.isCrash()
            }
        }

        let runner = CrashMockScriptRunner()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, runner: runner, evaluator: CrashEvaluator())

        let semaphore = DispatchSemaphore(value: 0)

        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let v0 = b.loadString("FUZZILLI_CRASH")
            let v1 = b.loadInt(0)
            let v2 = b.createNamedVariable(forBuiltin: "fuzzilli")
            b.callFunction(v2, withArgs: [v0, v1])
            let expectedProgram = b.finalize()

            let mutator = CrashingInstrumentationMutator(shouldProcessedProgramCrash: false)
            b.loadInt(42)
            let program = b.finalize()

            fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
                let actualProgram = ev.program
                #expect(expectedProgram == actualProgram)
                semaphore.signal()
            }

            _ = mutator.mutate(program, using: b, for: fuzzer)
        }

        let waitResult = semaphore.wait(timeout: .now() + 5)
        #expect(waitResult == .success)
    }

    /// Extracts the generated portion from an instrumented program without
    /// prefix code and with non-deterministic seeds replaced to avoid
    /// flakiness.
    private func extractCodeToVerify(from actual: String) -> String {
        let sentinel = "// END_OF_EXPLORATION_PREFIX"
        let range = actual.range(of: sentinel)!
        return String(actual[range.upperBound...]).replacingOccurrences(
            of: ", \\d+\\);", with: ", 123);", options: .regularExpression)
    }

    private func runExplorationInstrumentationTest(
        varSelector: @escaping ([Variable], [Variable]) -> [Variable],
        argSelector: @escaping (ProgramBuilder) -> [Variable],
        build: (ProgramBuilder) -> Void,
        expected: String
    ) {
        let config = Configuration(logLevel: .error, forDifferentialFuzzing: true)
        let fuzzer = makeMockFuzzer(config: config)
        fuzzer.sync {
            let mutator = ExplorationMutator()

            mutator.varSelector = varSelector
            mutator.argSelector = argSelector

            let b = fuzzer.makeBuilder()
            build(b)
            let program = b.finalize()

            guard let instrumented = mutator.instrument(program, for: fuzzer) else {
                Issue.record("Failed to instrument program")
                return
            }

            let actual = fuzzer.lifter.lift(instrumented, withOptions: .includeComments)
            let actualWithoutPrefix = extractCodeToVerify(from: actual)
            #expect(actualWithoutPrefix == expected)
        }
    }

    @Test func testExplorationMutatorInstrumentation() {
        runExplorationInstrumentationTest(
            varSelector: { untyped, typed in
                // Only explore the first untyped variable
                #expect(untyped.count == 1)
                return untyped
            },

            argSelector: { b in
                // Use the first two available variables as arguments
                return Array(
                    b.visibleVariables.filter({ b.type(of: $0).Is(.jsAnything) }).prefix(2))
            },

            build: { b in
                // We need 3 visible variables for exploration to trigger in the instrumenter loop.
                _ = b.loadInt(42)
                _ = b.loadString("foo")
                _ = b.loadFloat(13.37)
                // eval output is .jsAnything, so it will be in untypedVariables
                _ = b.eval("42", hasOutput: true)
            },
            expected: """

                const v3 = 42;
                explore("v3", v3, this, [42, "foo"], 123);

                """
        )
    }

    @Test func testExplorationMutatorInstrumentationVisibility() {
        runExplorationInstrumentationTest(
            varSelector: { untyped, typed in
                // Only explore the untyped variable
                return untyped
            },
            argSelector: { b in
                // Use all currently visible variables as arguments
                return b.visibleVariables.filter({ b.type(of: $0).Is(.jsAnything) })
            },
            build: { b in
                _ = b.loadInt(42)
                _ = b.loadInt(43)
                _ = b.loadInt(44)
                // This variable will be explored.
                _ = b.eval("early", hasOutput: true)
                // Add one more variable that should NOT be visible at the point of the early variable's exploration
                _ = b.loadInt(45)
            },
            expected: """

                const v3 = early;
                explore("v3", v3, this, [42, 43, 44, v3], 123);

                """
        )
    }

    private func runExplorationProcessingTest(
        build: (ProgramBuilder) -> Void,
        actions: [RuntimeAssistedMutator.Action],
        expected: String
    ) {
        let config = Configuration(logLevel: .error, forDifferentialFuzzing: true)
        let fuzzer = makeMockFuzzer(config: config)
        fuzzer.sync {
            let mutator = ExplorationMutator()
            let b = fuzzer.makeBuilder()

            build(b)
            let instrumentedProgram = b.finalize()

            let encoder = JSONEncoder()
            var output = ""
            for action in actions {
                let actionJson = String(data: try! encoder.encode(action), encoding: .utf8)!
                output += "EXPLORE_ACTION: \(actionJson)\n"
            }

            let (processedMaybe, outcome) = mutator.process(
                output, ofInstrumentedProgram: instrumentedProgram, using: fuzzer.makeBuilder())
            #expect(outcome == .success)
            guard let processed = processedMaybe else {
                Issue.record("Failed to process instrumented program")
                return
            }

            let actual = fuzzer.lifter.lift(processed)
            #expect(actual == expected)
        }
    }

    @Test func testExplorationMutatorProcessing() {
        runExplorationProcessingTest(
            build: { b in
                // Create an instrumented program manually for testing process()
                let v0 = b.loadInt(42)
                let v1 = b.loadString("foo")
                // Explore v0
                b.explore(v0, id: "v0", withArgs: [v1])
                _ = b.binary(v0, v1, with: .Add)
            },
            actions: [
                // Mock output from exploration
                // Action: GET_PROPERTY "bar" on v0
                RuntimeAssistedMutator.Action(
                    id: "v0",
                    operation: .GetProperty,
                    inputs: [.special(name: "exploredValue"), .string(value: "bar")],
                    isGuarded: false
                )
            ],
            expected: """
                const v2 = (42).bar;
                const v3 = 42 + "foo";

                """
        )
    }

    @Test func testExplorationMutatorProcessingComplex() {
        runExplorationProcessingTest(
            build: { b in
                // Create an instrumented program
                let v0 = b.loadInt(42)
                let v1 = b.loadString("foo")
                let v2 = b.createNamedVariable(forBuiltin: "func")
                // Explore v2 with args [v0, v1]
                b.explore(v2, id: "v2", withArgs: [v0, v1])
                // Explore v0 with no resulting action
                b.explore(v0, id: "v0", withArgs: [v1])
                _ = b.binary(v0, v1, with: .Add)
            },
            actions: [
                // Action for v2: CALL_FUNCTION v2 with args [v0, v1]
                // No action for v0 (it will be skipped)
                RuntimeAssistedMutator.Action(
                    id: "v2",
                    operation: .CallFunction,
                    inputs: [
                        .special(name: "exploredValue"), .argument(index: 0), .argument(index: 1),
                    ],
                    isGuarded: false
                )
            ],
            expected: """
                const v3 = func(42, "foo");
                const v4 = 42 + "foo";

                """
        )
    }

    @Test(.enabled(if: shouldRunCompilerTests()))
    func testRoundtripTranspilationHandlesLargeArrayGracefully() throws {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            b.eval(
                "const v = 0; [" + Array(repeating: "v", count: 65536).joined(separator: ", ") + "]"
            )
            let program = b.finalize()

            let mutator = CrashingInstrumentationMutator(shouldProcessedProgramCrash: false)
            let result = mutator.tryRoundtripTranspileInstrumentedProgramToFuzzIL(
                fuzzer, program, expectedSignal: 9
            )

            #expect(result == nil)
        }
    }
}
