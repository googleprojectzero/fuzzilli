// Copyright 2023 Google LLC
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

class LiveTests: XCTestCase {
    func testValueGeneration() throws {
        guard let nodejs = NodeJS() else {
            throw XCTSkip("Could not find NodeJS executable.")
        }

        let liveTestConfig = Configuration(enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let N = 500

        for _ in 0..<N {
            let b = fuzzer.makeBuilder()
            b.buildValues(10)

            let program = b.finalize()
            let jsProgram = fuzzer.lifter.lift(program, withOptions: .includeComments)

            do {
                let (code, _) = try nodejs.executeScript(jsProgram)
                // TODO: Change this into an XCTAssertEqual.
                if code != 0 {
                    /*let fuzzilProgram = FuzzILLifter().lift(program)*/
                    /*print("Program is Invalid:")*/
                    /*print(jsProgram)*/
                    /*print("Out:")*/
                    /*print(out)*/
                    /*print("FuzzILCode:")*/
                    /*print(fuzzilProgram)*/
                }
            } catch let error {
                XCTFail("Could not execute script: \(error)")
            }

        }
    }
}
