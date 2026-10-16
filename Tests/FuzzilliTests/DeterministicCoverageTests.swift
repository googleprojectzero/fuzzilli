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

/// Tests that collect the coverage of determinism check and minimization runs, using the real
/// ProgramCoverageEvaluator and libcoverage.
@Suite struct DeterministicCoverageTests {
    /// Writes the edges of each run into the coverage shared memory, like an instrumented engine.
    final class CoverageWritingRunner: ScriptRunner {
        var processArguments: [String] = []
        var env: [(String, String)] = []
        /// The evaluator's shared memory. Must be set before the first run.
        var sharedMemory: UnsafeMutableRawPointer? = nil
        /// Edges hit by the next runs. Once empty, runs hit `defaultEdges`.
        var edgeRuns: [[UInt32]] = []
        var defaultEdges: [UInt32] = []
        /// If set, scripts that do not contain this text hit no edges.
        var requiredText: String? = nil

        func setEnvironmentVariable(_ key: String, to value: String) {}

        func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
            let shmem = sharedMemory!
            shmem.storeBytes(of: UInt32(1000), as: UInt32.self)  // num_edges
            var edges = edgeRuns.isEmpty ? defaultEdges : edgeRuns.removeFirst()
            if let requiredText, !script.contains(requiredText) {
                edges = []
            }
            for edge in edges {
                let byte = shmem + 4 + Int(edge / 8)
                let value = byte.load(as: UInt8.self) | UInt8(1 << (edge % 8))
                byte.storeBytes(of: value, as: UInt8.self)
            }
            return MockExecution(
                outcome: .succeeded, stdout: "", stderr: "", fuzzout: "", execTime: 0.1)
        }

        func initialize(with fuzzer: Fuzzer) {}

        var isInitialized: Bool { true }
    }

    private func makeEvaluator(_ runner: CoverageWritingRunner) -> ProgramCoverageEvaluator {
        let evaluator = ProgramCoverageEvaluator(runner: runner)
        runner.sharedMemory = evaluator.sharedMemory
        return evaluator
    }

    private func makeProgram(for fuzzer: Fuzzer, size: Int) -> Program {
        let b = fuzzer.makeBuilder()
        for i in 0..<size {
            b.loadInt(Int64(i))
        }
        return b.finalize()
    }

    @Test func testDeterminismCheckRunsAreIntersected() {
        let runner = CoverageWritingRunner()
        let evaluator = makeEvaluator(runner)
        defer { evaluator.shutdown() }
        let fuzzer = makeMockFuzzer(runner: runner, evaluator: evaluator)

        fuzzer.sync {
            let program = makeProgram(for: fuzzer, size: 1)
            runner.edgeRuns = [[2, 3, 70]]
            let aspects = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))!

            evaluator.startCollectingDeterministicCoverage()
            #expect(evaluator.stopCollectingDeterministicCoverage() == nil)

            evaluator.startCollectingDeterministicCoverage()
            runner.edgeRuns = [[1, 2, 3, 70], [2, 3, 4, 70], [2, 3, 5, 70]]
            for _ in 0..<3 {
                _ = evaluator.computeAspectIntersection(of: program, with: aspects)
            }
            guard let coverage = evaluator.stopCollectingDeterministicCoverage() else {
                Issue.record("No coverage was collected")
                return
            }
            #expect(evaluator.getAllDeterministicEdges(in: coverage) == [2, 3, 70])

            // With a mask, only edges also set in the mask are returned.
            runner.edgeRuns = [[3, 9]]
            _ = fuzzer.execute(program, purpose: .other)
            let lastRun = evaluator.makeCoverageBitmap()
            evaluator.copyCurrentCoverage(into: lastRun)
            #expect(
                evaluator.getAllDeterministicEdges(in: coverage, intersectedWith: lastRun) == [3])
        }
    }

    @Test func testMinimizationKeepsCoverageOfLastCommittedRun() {
        let runner = CoverageWritingRunner()
        let evaluator = makeEvaluator(runner)
        defer { evaluator.shutdown() }
        let fuzzer = makeMockFuzzer(runner: runner, evaluator: evaluator)

        fuzzer.sync {
            let program = makeProgram(for: fuzzer, size: 3)
            runner.edgeRuns = [[1, 2]]
            let aspects = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))!
            let helper = MinimizationHelper(
                for: aspects, forCode: program.code, of: fuzzer, runningOnFuzzerQueue: true,
                collectCoverageOf: evaluator)
            #expect(helper.lastCommittedCoverage == nil)

            runner.edgeRuns = [[1, 2, 7]]
            #expect(helper.tryNopping(instructionAt: 0))
            // Edge 2 is missing, so this reduction is not committed.
            runner.edgeRuns = [[1, 8]]
            #expect(!helper.tryNopping(instructionAt: 1))

            let edges = helper.lastCommittedCoverage.map {
                evaluator.getAllDeterministicEdges(in: $0)
            }
            #expect(edges == [1, 2, 7])
        }
    }

    @Test func testCorpusGetsAllDeterministicEdges() {
        let runner = CoverageWritingRunner()
        let evaluator = makeEvaluator(runner)
        defer { evaluator.shutdown() }
        let corpus = RarityCorpus(covEvaluator: evaluator)
        let fuzzer = makeMockFuzzer(runner: runner, evaluator: evaluator, corpus: corpus)

        fuzzer.sync {
            let program = makeProgram(for: fuzzer, size: 1)
            // Edge 4 is already known, so it is not a new edge of the program below.
            runner.edgeRuns = [[4]]
            _ = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))
            runner.defaultEdges = [1, 2, 4]
            let aspects = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))!

            var extraRuns = 0
            fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { (_, purpose) in
                if purpose == .other { extraRuns += 1 }
            }
            // Programs from the parent are not minimized.
            #expect(
                fuzzer.processMaybeInteresting(
                    program, havingAspects: aspects, origin: .parent, withExectime: 0))

            // The corpus does not run the program again.
            #expect(extraRuns == 0)
            #expect(corpus.size == 1)
            for edge: UInt32 in [1, 2, 4] {
                #expect(corpus.edgeCount(for: edge) == 1)
            }
        }
    }

    @Test func testMinimizedProgramMasksDeterministicEdges() {
        let runner = CoverageWritingRunner()
        let evaluator = makeEvaluator(runner)
        defer { evaluator.shutdown() }
        let corpus = RarityCorpus(covEvaluator: evaluator)
        let fuzzer = makeMockFuzzer(runner: runner, evaluator: evaluator, corpus: corpus)

        fuzzer.sync {
            // Minimization keeps the print call, so the program is not empty.
            let b = fuzzer.makeBuilder()
            b.loadInt(1)
            b.callFunction(b.createNamedVariable(forBuiltin: "print"), withArgs: [b.loadInt(42)])
            let program = b.finalize()
            runner.requiredText = "print(42)"
            // Edges 4 and 9 are known, so the new edges of the program are 1 and 2.
            runner.edgeRuns = [[4, 9]]
            _ = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))
            runner.edgeRuns = [[1, 2, 4, 9]]
            let aspects = evaluator.evaluate(fuzzer.execute(program, purpose: .fuzzing))!
            // The 5 determinism check runs hit edge 9, but the minimization runs do not.
            runner.edgeRuns = Array(repeating: [1, 2, 4, 9], count: 5)
            runner.defaultEdges = [1, 2, 4]
            #expect(
                fuzzer.processMaybeInteresting(
                    program, havingAspects: aspects, origin: .local, withExectime: 0))
        }

        // Minimization runs in the background; wait until the program is added.
        let deadline = Date() + 10
        while fuzzer.sync(do: { corpus.size }) == 0 && Date() < deadline {
            usleep(10_000)
        }
        fuzzer.sync {
            #expect(corpus.size == 1)
            for edge: UInt32 in [1, 2, 4] {
                #expect(corpus.edgeCount(for: edge) == 1)
            }
            #expect(corpus.edgeCount(for: 9) == 0)
        }
    }
}
