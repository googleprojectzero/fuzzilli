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

        let v0 = b.codeString() {
            let v1 = b.loadInt(1337)
            let v2 = b.loadFloat(13.37)
            let _ = b.binary(v2, v1, with: .Mul)
            let v4 = b.codeString() {
                let v5 = b.loadInt(1337)
                let v6 = b.loadFloat(13.37)
                let _ = b.binary(v6, v5, with: .Add)
                let v8 = b.codeString() {
                    let v9 = b.loadInt(0)
                    let v10 = b.loadInt(2)
                    let v11 = b.loadInt(1)
                    b.forLoop(v9, .lessThan, v10, .Add, v11) { _ in
                        let v13 = b.loadInt(1337)
                        let _ = b.phi(v13)

                        let v15 = b.codeString() {
                            let v16 = b.loadString("hello world")
                            let _ = b.phi(v16)
                        }

                        let v18 = b.loadBuiltin("eval")
                        b.callFunction(v18, withArgs: [v15])
                    }
                }
                let v20 = b.loadBuiltin("eval")
                b.callFunction(v20, withArgs: [v8])
            }
            let v22 = b.loadBuiltin("eval")
            b.callFunction(v22, withArgs: [v4])
        }
        let v24 = b.loadBuiltin("eval")
        b.callFunction(v24, withArgs: [v0])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v0 = `
            const v3 = 13.37 * 1337;
            const v4 = \\`
                const v7 = 13.37 + 1337;
                const v8 = \\\\\\`
                    for (let v12 = 0; v12 < 2; v12 = v12 + 1) {
                        let v14 = 1337;
                        const v15 = \\\\\\\\\\\\\\`
                            let v17 = "hello world";
                        \\\\\\\\\\\\\\`;
                        const v19 = eval(v15);
                    }
                \\\\\\`;
                const v21 = eval(v8);
            \\`;
            const v23 = eval(v4);
        `;
        const v25 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }

    func testConsecutiveNestedCodeStrings(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.codeString() {
            let v1 = b.loadInt(1337)
            let v2 = b.loadFloat(13.37)
            let _ = b.binary(v2, v1, with: .Mul)
            let v4 = b.codeString() {
                let v5 = b.loadInt(1337)
                let v6 = b.loadFloat(13.37)
                let _ = b.binary(v6, v5, with: .Add)
            }
            let v8 = b.loadBuiltin("eval")
            b.callFunction(v8, withArgs: [v4])

            let v10 = b.codeString() {
                    let v11 = b.loadInt(0)
                    let v12 = b.loadInt(2)
                    let v13 = b.loadInt(1)
                    b.forLoop(v11, .lessThan, v12, .Add, v13) { _ in
                        let v15 = b.loadInt(1337)
                        let _ = b.phi(v15)

                    let _ = b.codeString() {
                        let v18 = b.loadString("hello world")
                        let _ = b.phi(v18)
                    }
                }
            }
            b.callFunction(v8, withArgs: [v10])
        }
        let v21 = b.loadBuiltin("eval")
        b.callFunction(v21, withArgs: [v0])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v0 = `
            const v3 = 13.37 * 1337;
            const v4 = \\`
                const v7 = 13.37 + 1337;
            \\`;
            const v9 = eval(v4);
            const v10 = \\`
                for (let v14 = 0; v14 < 2; v14 = v14 + 1) {
                    let v16 = 1337;
                    const v17 = \\\\\\`
                        let v19 = "hello world";
                    \\\\\\`;
                }
            \\`;
            const v20 = eval(v10);
        `;
        const v22 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }
    
    func testDoWhileLifting() {
        // Do-While loops require special handling as the loop condition is kept
        // in BeginDoWhileLoop but only emitted during lifting of EndDoWhileLoop
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let loopVar1 = b.phi(b.loadInt(0))
        b.doWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
            let loopVar2 = b.phi(b.loadInt(0))
            b.doWhileLoop(loopVar2, .lessThan, b.loadInt(1337)) {
                b.copy(b.binary(loopVar2, b.loadInt(1), with: .Add), to: loopVar2)
            }
            b.copy(b.binary(loopVar1, b.loadInt(1), with: .Add), to: loopVar1)
        }
        
        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        let v1 = 0;
        do {
            let v4 = 0;
            do {
                const v7 = v4 + 1;
                v4 = v7;
            } while (v4 < 1337);
            const v9 = v1 + 1;
            v1 = v9;
        } while (v1 < 42);

        """
        
        XCTAssertEqual(lifted_program, expected_program)
    }

    func testBlockStatements(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.createObject(with: ["a": v0])
        b.forInLoop(v1) { _ in
            b.blockStatement {
                let _ = b.loadInt(1337)
                b.blockStatement {
                    let _ = b.createObject(with: ["a" : v1])
                }
                b.phi(v1)
            }
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v1 = {a:1337};
        for (const v2 in v1) {
            {
                const v3 = 1337;
                {
                    const v4 = {a:v1};
                }
                let v5 = v1;
            }
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }
}

extension LifterTests {
    static var allTests : [(String, (LifterTests) -> () throws -> Void)] {
        return [
            ("testDeterministicLifting", testDeterministicLifting),
            ("testLiftingOptions", testLiftingOptions),
            ("testNestedCodeStrings", testNestedCodeStrings),
            ("testNestedConsecutiveCodeString", testConsecutiveNestedCodeStrings),
            ("testDoWhileLifting", testDoWhileLifting),
            ("testBlockStatements", testBlockStatements)
        ]
    }
}
