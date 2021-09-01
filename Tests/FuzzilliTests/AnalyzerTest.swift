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

import XCTest
@testable import Fuzzilli

class AnalyzerTests: XCTestCase {

    func testContextAnalyzer() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.generate(n: 100)
            let program = b.finalize()

            var contextAnalyzer = ContextAnalyzer()

            for instr in program.code {
                contextAnalyzer.analyze(instr)
            }
            print(contextAnalyzer.context)
            XCTAssertEqual(contextAnalyzer.context, .script)
        }
    }
}

extension AnalyzerTests {
    static var allTests : [(String, (AnalyzerTests) -> () throws -> Void)] {
        return [
            ("testContextAnalyzer", testContextAnalyzer),
        ]
    }
}
