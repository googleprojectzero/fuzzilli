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

class LifterTests: XCTestCase {
    func testDeterministicLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<100 {
            b.generate(n: 100)
            let program = b.finalize()

            let code1 = fuzzer.lifter.lift(program)
            let code2 = fuzzer.lifter.lift(program)
            
            // but of course preserves the instructions of the program.
            XCTAssertEqual(code1, code2)
        }
    }
    
    func testLiftingOptions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.beginIf(args[0]) {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }
            b.beginElse() {
                b.doReturn(value: args[2])
            }
            b.endIf()
        }
        b.callFunction(f, withArgs: [b.loadBool(true), b.loadInt(1)])

        let program = b.finalize()

        let expectedPrettyCode = """
        function v0(v1,v2,v3) {
            if (v1) {
                const v4 = v1 * v2;
                return v4;
            } else {
                return v3;
            }
        }
        const v7 = v0(true,1);

        """

        let expectedMinifiedCode = "function v0(v1,v2,v3){if(v1){const v4=v1*v2;return v4;}else{return v3;}}const v7=v0(true,1);"

        let prettyCode = fuzzer.lifter.lift(program)
        let minifiedCode = fuzzer.lifter.lift(program, withOptions: .minify)

        XCTAssertEqual(prettyCode, expectedPrettyCode)
        XCTAssertEqual(minifiedCode, expectedMinifiedCode)
    }

    func testNestedCodeStrings(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let code = b.codeString() {
            let v0 = b.loadInt(1337)
            let v1 = b.loadFloat(13.37)
            let _ = b.binary(v1, v0, with: .Mul)
            let _ = b.codeString() {
                let v0 = b.loadInt(1337)
                let v1 = b.loadFloat(13.37)
                let _ = b.binary(v1, v0, with: .Add)
                let _ = b.codeString() {
                    let start = b.loadInt(0)
                    let end = b.loadInt(2)
                    let step = b.loadInt(1)
                    b.forLoop(start, .lessThan, end, .Add, step) { _ in
                        let v1 = b.loadInt(1337)
                        let _ = b.phi(v1)

                        let _ = b.codeString() {
                            let v3 = b.loadString("hello world")
                            let _ = b.phi(v3)
                        }
                    }
                }
            }
        }
        let eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v0 = `
            const v3 = 13.37 * 1337;
            const v4 = \\`
                const v7 = 13.37 + 1337;
                const v8 = \\`
                    for (let v12 = 0; v12 < 2; v12 = v12 + 1) {
                        let v14 = 1337;
                        const v15 = \\`
                            let v17 = "hello world";
                        \\`
                    }
                \\`
            \\`
        `
        const v19 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }

    func testConsecutiveNestedCodeStrings(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let code = b.codeString() {
            let v0 = b.loadInt(1337)
            let v1 = b.loadFloat(13.37)
            let _ = b.binary(v1, v0, with: .Mul)
            let _ = b.codeString() {
                let v0 = b.loadInt(1337)
                let v1 = b.loadFloat(13.37)
                let _ = b.binary(v1, v0, with: .Add)
            }

            let _ = b.codeString() {
                    let start = b.loadInt(0)
                    let end = b.loadInt(2)
                    let step = b.loadInt(1)
                    b.forLoop(start, .lessThan, end, .Add, step) { _ in
                        let v1 = b.loadInt(1337)
                        let _ = b.phi(v1)

                    let _ = b.codeString() {
                        let v3 = b.loadString("hello world")
                        let _ = b.phi(v3)
                    }
                }
            }
        }
        let eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v0 = `
            const v3 = 13.37 * 1337;
            const v4 = \\`
                const v7 = 13.37 + 1337;
            \\`
            const v8 = \\`
                for (let v12 = 0; v12 < 2; v12 = v12 + 1) {
                    let v14 = 1337;
                    const v15 = \\`
                        let v17 = "hello world";
                    \\`
                }
            \\`
        `
        const v19 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }
}

extension LifterTests {
    static var allTests : [(String, (LifterTests) -> () throws -> Void)] {
        return [
            ("testDeterministicLifting", testDeterministicLifting),
            ("testLiftingOptions", testLiftingOptions),
            ("testNestedCodeStrings", testNestedCodeStrings),
            ("testNestedConsecutiveCodeString", testConsecutiveNestedCodeStrings),
        ]
    }
}
