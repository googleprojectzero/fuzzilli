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

class ContextGraphTests: XCTestCase {
    func testReachabilityCalculation() {
        let fuzzer = makeMockFuzzer()
        let contextGraph = ContextGraph(for: fuzzer.codeGenerators, withLogger: Logger(withLabel: "Test"))

        let reachableContexts = Set(contextGraph.getReachableContexts(from: .javascript))

        let reachableContexts2 = Set(contextGraph.getReachableContexts(from: .javascript))

        XCTAssertEqual(reachableContexts, reachableContexts2)

        XCTAssertEqual(reachableContexts,
                       Set([.javascript,
                            .method,
                            .classMethod,
                            .switchCase,
                            .classDefinition,
                            .switchBlock,
                            .asyncFunction,
                            .wasmFunction,
                            .wasm,
                            .loop,
                            .generatorFunction,
                            .objectLiteral,
                            .subroutine,
                            .wasmTypeGroup]))
    }

    func testSubsetReachabilityCalculation() {
        let fuzzer = makeMockFuzzer()
        let contextGraph = ContextGraph(for: fuzzer.codeGenerators, withLogger: Logger(withLabel: "Test"))
        let reachableContextsWasm = Set(contextGraph.getReachableContexts(from: .wasm))
        let reachableContextsWasm2 = Set(contextGraph.getReachableContexts(from: .wasm))

        XCTAssertEqual(reachableContextsWasm, reachableContextsWasm2)

        let reachableContextsWasmFunction = Set(contextGraph.getReachableContexts(from: .wasmFunction))
        let reachableContextsJavaScript = Set(contextGraph.getReachableContexts(from: .javascript))

        XCTAssertTrue(reachableContextsWasmFunction.isSubset(of: reachableContextsWasm))
        XCTAssertEqual(reachableContextsWasm,
                       Set([.wasmFunction,
                            .wasm]))
        XCTAssertTrue(reachableContextsWasm.isSubset(of: reachableContextsJavaScript))
    }
}
