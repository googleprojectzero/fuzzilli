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

import XCTest
@testable import Fuzzilli

class CodeGenerationTests: XCTestCase {
    // Verify that code generators don't crash and always produce valid programs.
    func testBasicCodeGeneration() {
        let fuzzer = makeMockFuzzer()

        for _ in 0..<100 {
            let b = fuzzer.makeBuilder()

            b.generate(n: 100)

            let program = b.finish()

            XCTAssert(program.check() == .valid)
        }
    }
}

extension CodeGenerationTests {
    static var allTests : [(String, (CodeGenerationTests) -> () throws -> Void)] {
        return [
            ("testBasicCodeGeneration", testBasicCodeGeneration),
        ]
    }
}
