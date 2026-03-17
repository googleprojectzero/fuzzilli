// Copyright 2025 Google LLC
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

class EngineTests: XCTestCase {
    func testPostProcessorOnGenerativeEngine() throws {
        class MockPostProcessor : FuzzingPostProcessor {
            var callCount = 0
            func process(_ program: Program, for fuzzer: Fuzzer) -> Program {
                callCount += 1
                return program
            }
        }
        let mockPostProcessor = MockPostProcessor()

        let engine = MutationEngine(numConsecutiveMutations: 1)
        engine.registerPostProcessor(mockPostProcessor)
        let q = DispatchQueue(label: "fuzzerQueue")
        let fuzzer = makeMockFuzzer(engine: engine, queue: q)
        XCTAssertNotNil(fuzzer.corpusGenerationEngine.postProcessor)
        XCTAssertEqual(mockPostProcessor.callCount, 0)
        q.sync {
            fuzzer.start(runUntil: .iterationsPerformed(3))
        }
        // Synchronize on the queue 2 times, so that each time at least one new
        // fuzzOne() is executed on the DispatchQueue in that time.
        // This should work consistently as the DispatchQueue is not marked
        // with DispatchQueue.Attributes.concurrent, so each time one of the
        // que.sync {} is executed, a fuzzOne() was executed as well.
        q.sync {}
        q.sync {}
        XCTAssertEqual(mockPostProcessor.callCount, 3)
        // No more tasks are queued.
        q.sync {}
        XCTAssertEqual(mockPostProcessor.callCount, 3)
        XCTAssert(fuzzer.isStopped)
    }

    // Test that certain usages of "arguments" are rejected by the Dumpling
    // post processor.
    func testDumplingPostProcessor() {
        let fuzzer = makeMockFuzzer()
        let processor = DumplingFuzzingPostProcessor()

        let rejectedCases: [(ProgramBuilder) -> ()] = [
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                b.getProperty("arguments", of: f)
            },
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                let i = b.loadInt(0)
                b.setProperty("arguments", of: f, to: i)
            },
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                let i = b.loadInt(0)
                b.updateProperty("arguments", of: f, with: i, using: BinaryOperator.Add)
            },
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                b.deleteProperty("arguments", of: f)
            },
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                let a = b.loadString("arguments")
                b.getComputedProperty(a, of: f)
            },
        ]

        for (i, rejectedCase) in rejectedCases.enumerated() {
            let b = fuzzer.makeBuilder()
            rejectedCase(b)
            let program = b.finalize()
            XCTAssertThrowsError(try processor.process(program, for: fuzzer), "test case \(i)")
        }

        for acceptedCase: (ProgramBuilder) -> () in [
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                b.getProperty("not_arguments", of: f)
            },
            { b in
                let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
                let a = b.loadString("not_arguments")
                b.getComputedProperty(a, of: f)
            },
        ] {

            let b = fuzzer.makeBuilder()
            acceptedCase(b)
            let program = b.finalize()
            _ = try! processor.process(program, for: fuzzer)
        }
    }
}
