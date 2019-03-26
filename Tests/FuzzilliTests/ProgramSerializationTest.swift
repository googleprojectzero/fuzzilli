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

class ProgramSerializationTests: XCTestCase {
    func testJSONEncodingDecoding() {
        let fuzzer = makeMockFuzzer()

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for _ in 0..<100 {
            let b = fuzzer.makeBuilder()

            b.generate(n: 100)

            let program = b.finish()

            let data = try! encoder.encode(program)
            let programCopy = try! decoder.decode(Program.self, from: data)

            XCTAssert(areStructurallyEqual(program, programCopy))
        }
    }

    func testPListEncodingDecoding() {
        #if os(macOS)
        let fuzzer = makeMockFuzzer()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let decoder = PropertyListDecoder()

        for _ in 0..<100 {
            let b = fuzzer.makeBuilder()

            b.generate(n: 100)

            let program = b.finish()

            let data = try! encoder.encode(program)
            let programCopy = try! decoder.decode(Program.self, from: data)

            XCTAssert(areStructurallyEqual(program, programCopy))
        }
        #endif
    }
}

extension ProgramSerializationTests {
    static var allTests : [(String, (ProgramSerializationTests) -> () throws -> Void)] {
        return [
            ("testJSONEncodingDecoding", testJSONEncodingDecoding),
            ("testPListEncodingDecoding", testPListEncodingDecoding)
        ]
    }
}
