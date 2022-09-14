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

        for _ in 0..<10 {
            b.generate(n: 100)
            let program = b.finalize()

            let code1 = fuzzer.lifter.lift(program)
            let code2 = fuzzer.lifter.lift(program)

            XCTAssertEqual(code1, code2)
        }
    }

    func testFuzzILLifter() {
        // Mostly this just ensures that the FuzzILLifter supports all operations

        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        let lifter = FuzzILLifter()

        for _ in 0..<100 {
            b.generate(n: 100)
            let program = b.finalize()

            _ = lifter.lift(program)
        }
    }

    func testConstantLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 = b.dup(v0)
        let v3 = b.loadFloat(13.37)
        let v4 = b.loadString("foobar")
        let _ = b.dup(v4)
        b.reassign(v2, to: v3)
        b.reassign(v4, to: v0)
        let _ = b.loadProperty("foo", of: v1)
        b.createObject(with:["foo":v0],andSpreading:[v1,v1])

        let expectedCode = """
        const v1 = {"foo":42};
        let v2 = 42;
        let v4 = "foobar";
        const v5 = v4;
        v2 = 13.37;
        v4 = 42;
        const v6 = v1.foo;
        const v7 = {"foo":42,...v1,...v1};

        """

        XCTAssertEqual(fuzzer.lifter.lift(b.finalize()), expectedCode)
    }

    func testNestedCodeStrings() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.buildCodeString() {
            let v1 = b.loadInt(1337)
            let v2 = b.loadFloat(13.37)
            let _ = b.binary(v2, v1, with: .Mul)
            let v4 = b.buildCodeString() {
                let v5 = b.loadInt(1337)
                let v6 = b.loadFloat(13.37)
                let _ = b.binary(v6, v5, with: .Add)
                let v8 = b.buildCodeString() {
                    let v9 = b.loadInt(0)
                    let v10 = b.loadInt(2)
                    let v11 = b.loadInt(1)
                    b.buildForLoop(v9, .lessThan, v10, .Add, v11) { _ in
                        b.loadInt(1337)

                        let v15 = b.buildCodeString() {
                            b.loadString("hello world")
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
                    for (let v12 = 0; v12 < 2; v12++) {
                        const v13 = 1337;
                        const v14 = \\\\\\\\\\\\\\`
                            const v15 = "hello world";
                        \\\\\\\\\\\\\\`;
                        const v17 = eval(v14);
                    }
                \\\\\\`;
                const v19 = eval(v8);
            \\`;
            const v21 = eval(v4);
        `;
        const v23 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }

    func testConsecutiveNestedCodeStrings() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.buildCodeString() {
            let v1 = b.loadInt(1337)
            let v2 = b.loadFloat(13.37)
            let _ = b.binary(v2, v1, with: .Mul)
            let v4 = b.buildCodeString() {
                let v5 = b.loadInt(1337)
                let v6 = b.loadFloat(13.37)
                let _ = b.binary(v6, v5, with: .Add)
            }
            let v8 = b.loadBuiltin("eval")
            b.callFunction(v8, withArgs: [v4])

            let v10 = b.buildCodeString() {
                    let v11 = b.loadInt(0)
                    let v12 = b.loadInt(2)
                    let v13 = b.loadInt(1)
                    b.buildForLoop(v11, .lessThan, v12, .Add, v13) { _ in
                        b.loadInt(1337)

                    let _ = b.buildCodeString() {
                        b.loadString("hello world")
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
                for (let v14 = 0; v14 < 2; v14++) {
                    const v15 = 1337;
                    const v16 = \\\\\\`
                        const v17 = "hello world";
                    \\\\\\`;
                }
            \\`;
            const v18 = eval(v10);
        `;
        const v20 = eval(v0);

        """

        XCTAssertEqual(lifted_program, expected_program)

    }

    func testDoWhileLifting() {
        // Do-While loops require special handling as the loop condition is kept
        // in BeginDoWhileLoop but only emitted during lifting of EndDoWhileLoop
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let loopVar1 = b.loadInt(0)
        b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
            let loopVar2 = b.loadInt(0)
            b.buildDoWhileLoop(loopVar2, .lessThan, b.loadInt(1337)) {
                b.unary(.PostInc, loopVar2)
            }
            b.unary(.PostInc, loopVar1)
        }

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        let v0 = 0;
        do {
            let v2 = 0;
            do {
                const v4 = v2++;
            } while (v2 < 1337);
            const v5 = v0++;
        } while (v0 < 42);

        """

        XCTAssertEqual(lifted_program, expected_program)
    }

    func testBlockStatements() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.createObject(with: ["a": v0])
        b.buildForInLoop(v1) { v2 in
            b.blockStatement {
                let v3 = b.loadInt(1337)
                b.reassign(v2, to: v3)
                b.blockStatement {
                    let v4 = b.createObject(with: ["a" : v1])
                    b.reassign(v2, to: v4)
                }

            }
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v1 = {"a":1337};
        for (let v2 in v1) {
            {
                v2 = 1337;
                {
                    const v4 = {"a":v1};
                    v2 = v4;
                }
            }
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testAsyncGeneratorLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.buildForLoop(v3, .lessThan, v4, .Add, v5) { _ in
                b.await(value: v3)
                let v8 = b.loadInt(1337)
                b.yield(value: v8)
            }
            b.doReturn(value: v4)
        }

        b.buildAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2), isStrict: true) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.buildForLoop(v3, .lessThan, v4, .Add, v5) { _ in
                b.await(value: v3)
                let v8 = b.loadInt(1337)
                b.yield(value: v8)
            }
            b.doReturn(value: v4)
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        async function* v0(v1,v2) {
            for (let v6 = 0; v6 < 2; v6++) {
                const v7 = await 0;
                const v9 = yield 1337;
            }
            return 2;
        }
        async function* v10(v11,v12) {
            'use strict';
            for (let v16 = 0; v16 < 2; v16++) {
                const v17 = await 0;
                const v19 = yield 1337;
            }
            return 2;
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testHoleyArrayLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(1))
        initialValues.append(b.loadInt(2))
        initialValues.append(b.loadUndefined())
        initialValues.append(b.loadInt(4))
        initialValues.append(b.loadUndefined())
        initialValues.append(b.loadInt(6))
        let v = b.loadString("foobar")
        b.reassign(v, to: b.loadUndefined())
        initialValues.append(v)
        let va = b.createArray(with: initialValues)
        b.createArray(with: [b.loadInt(301), b.loadUndefined()])
        b.createArray(with: [b.loadUndefined()])
        b.createArray(with: [va, b.loadUndefined()], spreading: [true,false])
        b.createArray(with: [b.loadUndefined()], spreading: [false])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        let v6 = "foobar";
        v6 = undefined;
        const v8 = [1,2,,4,,6,v6];
        const v11 = [301,,];
        const v13 = [,];
        const v15 = [...v8,,];
        const v17 = [,];

        """
        XCTAssertEqual(lifted_program,expected_program)

    }

    func testTryCatchFinallyLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }, catchBody: { _ in
                let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                b.reassign(args[0], to: v4)
            }, finallyBody: {
                let v = b.binary(args[0], args[1], with: .Add)
                b.doReturn(value: v)
            })
        }
        b.callFunction(f, withArgs: [b.loadBool(true), b.loadInt(1)])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        function v0(v1,v2,v3) {
            try {
                const v4 = v1 * v2;
                return v4;
            } catch(v5) {
                const v7 = {"a":1337};
                v1 = v7;
            } finally {
                const v8 = v1 + v2;
                return v8;
            }
        }
        const v11 = v0(true,1);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testTryCatchLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }, catchBody: { _ in
                let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                b.reassign(args[0], to: v4)
            })
        }
        b.callFunction(f, withArgs: [b.loadBool(true), b.loadInt(1)])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        function v0(v1,v2,v3) {
            try {
                const v4 = v1 * v2;
                return v4;
            } catch(v5) {
                const v7 = {"a":1337};
                v1 = v7;
            }
        }
        const v10 = v0(true,1);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testTryFinallyLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }, finallyBody: {
                let v = b.binary(args[0], args[1], with: .Add)
                b.doReturn(value: v)
            })
        }
        b.callFunction(f, withArgs: [b.loadBool(true), b.loadInt(1)])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        function v0(v1,v2,v3) {
            try {
                const v4 = v1 * v2;
                return v4;
            } finally {
                const v5 = v1 + v2;
                return v5;
            }
        }
        const v8 = v0(true,1);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testComputedMethodLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadString("Hello World")
        let v1 = b.loadBuiltin("Symbol")
        let v2 = b.loadProperty("iterator", of: v1)
        let v3 = b.callComputedMethod(v2, on: v0, withArgs: [])
        let _ = b.callMethod("next", on: v3, withArgs: [])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v2 = Symbol.iterator;
        const v3 = "Hello World"[v2]();
        const v4 = v3.next();

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testConditionalOperationLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.createObject(with: ["a" : b.loadInt(1337)])
        let v2 = b.loadProperty("a", of: v1)
        let v3 = b.loadInt(10)
        let v4 = b.compare(v2, v3, with: .greaterThan)
        let _ = b.conditional(v4, v2, v3)

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = {"a":1337};
        const v2 = v1.a;
        const v4 = v2 > 10;
        const v5 = v4 ? v2 : 10;

        """
        XCTAssertEqual(lifted_program,expected_program)
    }

    func testSwitchStatementLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 =  b.loadProperty("foo", of: v1)
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")
        let v5 = b.loadFloat(13.37)

        b.buildSwitch(on: v2) { cases in
            cases.add(v3, previousCaseFallsThrough: false) {
                b.storeProperty(v3, as: "bar", on: v1)
            }
            cases.add(v4, previousCaseFallsThrough: false){
                b.storeProperty(v4, as: "baz", on: v1)
            }
            cases.addDefault(previousCaseFallsThrough: false){
                b.storeProperty(v5, as: "foo", on: v1)
            }
            cases.add(v0, previousCaseFallsThrough: true) {
                b.storeProperty(v2, as: "bla", on: v1)
            }
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = {"foo":42};
        const v2 = v1.foo;
        switch (v2) {
        case 1337:
            v1.bar = 1337;
            break;
        case "42":
            v1.baz = "42";
            break;
        default:
            v1.foo = 13.37;
        case 42:
            v1.bla = v2;
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testBinaryOperationReassignLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.loadFloat(13.37)
        b.reassign(v0, to: v1, with: .Add)
        b.reassign(v0, to: v1, with: .Mul)
        b.reassign(v0, to: v1, with: .LShift)

        let v2 = b.loadString("hello")
        let v3 = b.loadString("world")
        b.reassign(v2, to: v3, with: .Add)

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        let v0 = 1337;
        v0 += 13.37;
        v0 *= 13.37;
        v0 <<= 13.37;
        let v2 = "hello";
        v2 += "world";

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    /// Verifies that all variables that are reassigned through either
    ///
    /// a .PostInc and .PreInc UnaryOperation,
    /// a Reassign instruction, or
    /// a BinaryOperationAndReassign instruction
    func testVariableAnalyzer() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.loadFloat(13.37)
        b.reassign(v0, to: v1, with: .Add)
        let v2 = b.loadString("Hello")
        b.reassign(v1, to: v2)
        let v3 = b.loadInt(1336)
        let v4 = b.unary(.PreInc, v3)
        b.unary(.PostInc, v4)

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        let v0 = 1337;
        let v1 = 13.37;
        v0 += v1;
        v1 = "Hello";
        let v3 = 1336;
        let v4 = ++v3;
        const v5 = v4++;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testCreateTemplateLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let _ = b.createTemplateString(from: [""], interpolating: [])
        let v2 = b.createTemplateString(from: ["Hello", "World"], interpolating: [v0])
        let v3 = b.createObject(with: ["foo": v0])
        let v4 = b.loadProperty("foo", of: v3)
        let _ = b.createTemplateString(from: ["bar", "baz"], interpolating: [v4])
        let _ = b.createTemplateString(from: ["test", "inserted", "template"], interpolating: [v4, v2] )

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = ``;
        const v3 = {"foo":1337};
        const v4 = v3.foo;
        const v5 = `bar${v4}baz`;
        const v6 = `test${v4}inserted${`Hello${1337}World`}template`;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testDeleteOpsLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.loadString("bar")
        let v2 = b.loadFloat(13.37)
        var initialProperties = [String: Variable]()
        initialProperties["foo"] = v0
        initialProperties["bar"] = v2
        let v3 = b.createObject(with: initialProperties)
        let _ = b.deleteProperty("foo", of: v3)
        let _ = b.deleteComputedProperty(v1, of: v3)

        let v10 = b.createArray(with: [b.loadInt(301), b.loadInt(4), b.loadInt(68), b.loadInt(22)])
        let _ = b.deleteElement(3, of: v10)

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        const v3 = {"bar":13.37,"foo":1337};
        const v4 = delete v3.foo;
        const v5 = delete v3["bar"];
        const v10 = [301,4,68,22];
        const v11 = delete v10[3];

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testStrictFunctionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let sf = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3), isStrict: true) { args in
            b.buildIfElse(args[0], ifBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }, elseBody: {
                b.doReturn(value: args[2])
            })
        }
        b.callFunction(sf, withArgs: [b.loadBool(true), b.loadInt(1)])

        let saf = b.buildArrowFunction(withSignature: FunctionSignature(withParameterCount: 3), isStrict: true) { args in
            b.buildIfElse(args[0], ifBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }, elseBody: {
                b.doReturn(value: args[2])
            })
        }
        b.callFunction(saf, withArgs: [b.loadBool(true), b.loadInt(1)])

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        function v0(v1,v2,v3) {
            'use strict';
            if (v1) {
                const v4 = v1 * v2;
                return v4;
            } else {
                return v3;
            }
        }
        const v7 = v0(true,1);
        const v8 = (v9,v10,v11) => {
            'use strict';
            if (v9) {
                const v12 = v9 * v10;
                return v12;
            } else {
                return v11;
            }
        };
        const v15 = v8(true,1);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testRegExpInline() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadRegExp("a", RegExpFlags())
        b.compare(v0,v0, with: .equal);
        let v1 = b.loadRegExp("b", RegExpFlags())
        b.compare(v0,v1, with: .equal);

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v0 = /a/;
        const v1 = v0 == v0;
        const v2 = /b/;
        const v3 = v0 == v2;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }


    func testCallMethodWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(1))
        initialValues.append(b.loadInt(3))
        initialValues.append(b.loadInt(9))
        initialValues.append(b.loadInt(10))
        initialValues.append(b.loadInt(2))
        initialValues.append(b.loadInt(6))
        let v6 = b.createArray(with: initialValues)

        let v7 = b.loadInt(0)
        let v8 = b.loadInt(4)

        let v9 = b.loadBuiltin("Math")
        let _ = b.callMethod("max", on: v9, withArgs: [v7,v6,v8], spreading: [false, true, false])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v6 = [1,3,9,10,2,6];
        const v10 = Math.max(0,...v6,4);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testCallComputedMethodWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { args in
            let v3 = b.binary(args[0], args[1], with: .Add)
            b.doReturn(value: v3)
        }
        let v4 = b.createObject(with: ["add" : v0])
        let v5 = b.loadString("add")
        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        let v8 = b.createArray(with: initialValues)
        let _ = b.callComputedMethod(v5, on: v4, withArgs: [v8], spreading: [true])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        function v0(v1,v2) {
            const v3 = v1 + v2;
            return v3;
        }
        const v4 = {"add":v0};
        const v8 = [15,30];
        const v9 = v4["add"](...v8);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testConstructWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let v4 = b.createArray(with: initialValues)
        let v5 = b.loadFloat(13.37)

        let v6 = b.loadBuiltin("Array")
        let _ = b.construct(v6, withArgs: [v4,v5], spreading: [true,false])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v4 = [15,30,"Hello","World"];
        const v7 = new Array(...v4,13.37);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testCallWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let v4 = b.createArray(with: initialValues)
        let v5 = b.loadFloat(13.37)

        let v6 = b.loadBuiltin("Array")
        let _ = b.callFunction(v6, withArgs: [v4,v5], spreading: [true,false])

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v4 = [15,30,"Hello","World"];
        const v7 = Array(...v4,13.37);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testPropertyAndElementWithBinopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 =  b.loadString("baz")
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")
        let v5 = b.loadFloat(13.37)

        b.storeProperty(v5, as: "foo", on: v1)
        b.storeProperty(v4, as: "foo", with: BinaryOperator.Add, on: v1)
        b.storeProperty(v3, as: "bar", on: v1)
        b.storeProperty(v3, as: "bar", with: BinaryOperator.Mul, on: v1)
        b.storeComputedProperty(v0, as: v2, on: v1)
        b.storeComputedProperty(v3, as: v2, with: BinaryOperator.LogicAnd, on: v1)

        let arr = b.createArray(with: [v3,v3,v3])
        b.storeElement(v0, at: 0, of: arr)
        b.storeElement(v5, at: 0, with: BinaryOperator.Sub, of: arr)

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = {"foo":42};
        v1.foo = 13.37;
        v1.foo += "42";
        v1.bar = 1337;
        v1.bar *= 1337;
        v1["baz"] = 42;
        v1["baz"] &&= 1337;
        const v6 = [1337,1337,1337];
        v6[0] = 42;
        v6[0] -= 13.37;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testSuperPropertyWithBinopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superclass = b.buildClass() { cls in
            cls.defineConstructor(withParameters: [.plain(.integer)]) { params in
            }

            cls.defineMethod("f", withSignature: [.plain(.float)] => .string) { params in
                b.doReturn(value: b.loadString("foobar"))
            }
        }

        let _ = b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.plain(.string)]) { params in
                b.storeSuperProperty(b.loadInt(100), as: "bar")
            }
            cls.defineMethod("g", withSignature: [.plain(.anything)] => .unknown) { params in
                b.storeSuperProperty(b.loadInt(1337), as: "bar", with: BinaryOperator.Add)
             }
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v0 = class V0 {
            constructor(v2) {
            }
            f(v4) {
                return "foobar";
            }
        };
        const v6 = class V6 extends v0 {
            constructor(v8) {
                super.bar = 100;
            }
            g(v11) {
                super.bar += 1337;
            }
        };

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testArrayDestructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let v4 = b.createArray(with: initialValues)

        b.destruct(v4, selecting: [0,1])
        b.destruct(v4, selecting: [0,2,5])

        b.destruct(v4, selecting: [0,2], hasRestElement: true)

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v4 = [15,30,"Hello","World"];
        let [v5,v6] = v4;
        let [v7,,v8,,,v9] = v4;
        let [v10,,...v11] = v4;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testArrayDestructAndReassignLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let v4 = b.createArray(with: initialValues)
        let v8 = b.loadInt(1000)
        let v9 = b.loadBuiltin("JSON")

        b.destruct(v4, selecting: [0,2], into: [v8, v9], hasRestElement: true)

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v4 = [15,30,"Hello","World"];
        let v5 = 1000;
        let v6 = JSON;
        [v5,,...v6] = v4;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testForLoopWithArrayDestructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        let v0 = b.loadInt(10)
        let v1 = b.createArray(with: [v0,v0,v0])
        let v2 = b.loadInt(20)
        let v3 = b.createArray(with: [v2,v2,v2])
        let v4 = b.createArray(with: [v1,v3])

        b.buildForOfLoop(v4, selecting: [0,2], hasRestElement: true) { args in
            let v8 = b.binary(args[0], b.loadInt(30), with: BinaryOperator.Add)
            let v9 = b.callMethod("push", on: args[1], withArgs: [v8])
            b.buildForOfLoop(v9) { arg in
                b.binary(arg, b.loadFloat(4.0), with: BinaryOperator.Sub)
            }
            b.buildForOfLoop(v4, selecting: [1]) { _ in
            }
        }

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = [10,10,10];
        const v3 = [20,20,20];
        const v4 = [v1,v3];
        for (let [v5,,...v6] of v4) {
            const v8 = v5 + 30;
            const v9 = v6.push(v8);
            for (const v10 of v9) {
                const v12 = v10 - 4.0;
            }
            for (let [,v13] of v4) {
            }
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testObjectDestructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.loadFloat(13.37)
        let v2 = b.createObject(with: ["foo": v0, "bar": v1])

        b.destruct(v2, selecting: ["foo"], hasRestElement: true)
        b.destruct(v2, selecting: ["foo", "bar"], hasRestElement: true)
        b.destruct(v2, selecting: [String](), hasRestElement: true)
        b.destruct(v2, selecting: ["foo", "bar"])

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v2 = {"bar":13.37,"foo":42};
        let {"foo":v3,...v4} = v2;
        let {"foo":v5,"bar":v6,...v7} = v2;
        let {...v8} = v2;
        let {"foo":v9,"bar":v10,} = v2;

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testObjectDestructAndReassignLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.loadFloat(13.37)
        let v2 = b.loadString("Hello")
        let v3 = b.createObject(with: ["foo": v0, "bar": v1])

        b.destruct(v3, selecting: ["foo"], into: [v2,v0], hasRestElement: true)
        b.destruct(v3, selecting: ["foo", "bar"], into: [v2,v0,v1], hasRestElement: true)
        b.destruct(v3, selecting: [String](), into: [v2], hasRestElement: true)
        b.destruct(v3, selecting: ["foo", "bar"], into: [v2,v1])

        let program = b.finalize()
        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        let v0 = 42;
        let v1 = 13.37;
        let v2 = "Hello";
        const v3 = {"bar":v1,"foo":v0};
        ({"foo":v2,...v0} = v3);
        ({"foo":v2,"bar":v0,...v1} = v3);
        ({...v2} = v3);
        ({"foo":v2,"bar":v1,} = v3);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }
}

extension LifterTests {
    static var allTests : [(String, (LifterTests) -> () throws -> Void)] {
        return [
            ("testDeterministicLifting", testDeterministicLifting),
            ("testFuzzILLifter", testFuzzILLifter),
            ("testNestedCodeStrings", testNestedCodeStrings),
            ("testNestedConsecutiveCodeString", testConsecutiveNestedCodeStrings),
            ("testDoWhileLifting", testDoWhileLifting),
            ("testBlockStatements", testBlockStatements),
            ("testAsyncGeneratorLifting", testAsyncGeneratorLifting),
            ("testHoleyArray", testHoleyArrayLifting),
            ("testTryCatchFinallyLifting", testTryCatchFinallyLifting),
            ("testTryCatchLifting", testTryCatchLifting),
            ("testTryFinallyLifting", testTryFinallyLifting),
            ("testComputedMethodLifting", testComputedMethodLifting),
            ("testConditionalOperationLifting", testConditionalOperationLifting),
            ("testBinaryOperationReassignLifting", testBinaryOperationReassignLifting),
            ("testVariableAnalyzer", testVariableAnalyzer),
            ("testSwitchStatementLifting", testSwitchStatementLifting),
            ("testCreateTemplateLifting", testCreateTemplateLifting),
            ("testDeleteOpsLifting", testDeleteOpsLifting),
            ("testRegExpInline",testRegExpInline),
            ("testStrictFunctionLifting", testStrictFunctionLifting),
            ("testCallMethodWithSpreadLifting", testCallMethodWithSpreadLifting),
            ("testCallComputedMethodWithSpreadLifting", testCallComputedMethodWithSpreadLifting),
            ("testConstructWithSpreadLifting", testConstructWithSpreadLifting),
            ("testCallWithSpreadLifting", testCallWithSpreadLifting),
            ("testPropertyAndElementWithBinopLifting", testPropertyAndElementWithBinopLifting),
            ("testSuperPropertyWithBinopLifting", testSuperPropertyWithBinopLifting),
            ("testArrayDestructLifting", testArrayDestructLifting),
            ("testArrayDestructAndReassignLifting", testArrayDestructAndReassignLifting),
            ("testForLoopWithArrayDestructLifting", testForLoopWithArrayDestructLifting),
            ("testObjectDestructLifting", testObjectDestructLifting),
            ("testArrayDestructAndReassignLifting", testObjectDestructAndReassignLifting),
        ]
    }
}
