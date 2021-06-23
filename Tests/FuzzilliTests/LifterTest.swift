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

        for _ in 0..<10 {
            b.generate(n: 100)
            let program = b.finalize()

            _ = lifter.lift(program)
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
        
        let expectedCode = """
        const v1 = {foo:42};
        let v2 = 42;
        let v4 = "foobar";
        const v5 = v4;
        v2 = 13.37;
        v4 = 42;
        const v6 = v1.foo;

        """
        
        XCTAssertEqual(fuzzer.lifter.lift(b.finalize()), expectedCode)
    }

    func testNestedCodeStrings(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.codeString() {
            let v1 = b.loadInt(1337)
            let v2 = b.loadFloat(13.37)
            let v3 = b.binary(v2, v1, with: .Mul)
            let v4 = b.codeString() {
                let v5 = b.loadInt(1337)
                let v6 = b.loadFloat(13.37)
                let _ = b.binary(v6, v5, with: .Add)
                let v8 = b.codeString() {
                    let v9 = b.loadInt(0)
                    let v10 = b.loadInt(2)
                    let v11 = b.loadInt(1)
                    b.forLoop(v9, .lessThan, v10, .Add, v11) { _ in
                        b.loadInt(1337)

                        let v15 = b.codeString() {
                            b.loadString("hello world")
                            return v3
                        }

                        let v18 = b.loadBuiltin("eval")
                        b.callFunction(v18, withArgs: [v15])
                    }
                    return v3
                }
                let v20 = b.loadBuiltin("eval")
                b.callFunction(v20, withArgs: [v8])
                return v3
            }
            let v22 = b.loadBuiltin("eval")
            b.callFunction(v22, withArgs: [v4])
            return v1
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
                            v3;
                        \\\\\\\\\\\\\\`;
                        const v17 = eval(v14);
                    }
                    v3;
                \\\\\\`;
                const v19 = eval(v8);
                v3;
            \\`;
            const v21 = eval(v4);
            1337;
        `;
        const v23 = eval(v0);

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
                let v7 = b.binary(v6, v5, with: .Add)
                return v7
            }
            let v8 = b.loadBuiltin("eval")
            b.callFunction(v8, withArgs: [v4])

            let v10 = b.codeString() {
                    let v11 = b.loadInt(0)
                    let v12 = b.loadInt(2)
                    let v13 = b.loadInt(1)
                    b.forLoop(v11, .lessThan, v12, .Add, v13) { _ in
                        b.loadInt(1337)

                    let _ = b.codeString() {
                        b.loadString("hello world")
                        return v1
                    }
                }
                return v1
            }
            b.callFunction(v8, withArgs: [v10])
            return v1
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
                v7;
            \\`;
            const v9 = eval(v4);
            const v10 = \\`
                for (let v14 = 0; v14 < 2; v14++) {
                    const v15 = 1337;
                    const v16 = \\\\\\`
                        const v17 = "hello world";
                        1337;
                    \\\\\\`;
                }
                1337;
            \\`;
            const v18 = eval(v10);
            1337;
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
        b.doWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
            let loopVar2 = b.loadInt(0)
            b.doWhileLoop(loopVar2, .lessThan, b.loadInt(1337)) {
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

    func testBlockStatements(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.createObject(with: ["a": v0])
        b.forInLoop(v1) { v2 in
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
        const v1 = {a:1337};
        for (let v2 in v1) {
            {
                v2 = 1337;
                {
                    const v4 = {a:v1};
                    v2 = v4;
                }
            }
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testAsyncGeneratorLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.defineAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.forLoop(v3, .lessThan, v4, .Add, v5) { _ in
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
                yield 1337;
            }
            return 2;
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testHoleyArrayLifting(){
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
        b.createArray(with: initialValues)

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)

        let expected_program = """
        let v6 = "foobar";
        v6 = undefined;
        const v8 = [1,2,,4,,6,v6];

        """
        XCTAssertEqual(lifted_program,expected_program)

    }

    func testTryCatchFinallyLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.beginTry() {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }
            b.beginCatch() { _ in
                let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                b.reassign(args[0], to: v4)
            }
            b.beginFinally() {
                let v = b.binary(args[0], args[1], with: .Add)
                b.doReturn(value: v)
            }
            b.endTryCatch()
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
                const v7 = {a:1337};
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

    func testTryCatchLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.beginTry() {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }
            b.beginCatch() { _ in
                let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                b.reassign(args[0], to: v4)
            }
            b.endTryCatch()
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
                const v7 = {a:1337};
                v1 = v7;
            }
        }
        const v10 = v0(true,1);

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testTryFinallyLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.definePlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.beginTry() {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(value: v)
            }
            b.beginFinally() {
                let v = b.binary(args[0], args[1], with: .Add)
                b.doReturn(value: v)
            }
            b.endTryCatch()
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

    func testComputedMethodLifting(){
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

    func testConditionalOperationLifting(){
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
        const v1 = {a:1337};
        const v2 = v1.a;
        const v4 = v2 > 10;
        const v5 = v4 ? v2 : 10;

        """
        XCTAssertEqual(lifted_program,expected_program)
    }

    func testSwitchStatementLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 =  b.loadProperty("foo", of: v1)
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")
        let v5 = b.loadFloat(13.37)

        b.beginSwitch(on: v2) { cases in
            cases.addDefault {
                b.storeProperty(v5, as: "foo", on: v1)
            }
            cases.add(v3, fallsThrough: false){
                b.storeProperty(v3, as: "bar", on: v1)
            }
            cases.add(v4, fallsThrough: true){
                b.storeProperty(v4, as: "baz", on: v1)
            }
            cases.add(v0, fallsThrough: false) {
                b.storeProperty(v2, as: "bla", on: v1)
            }
        }

        let program = b.finalize()

        let lifted_program = fuzzer.lifter.lift(program)
        let expected_program = """
        const v1 = {foo:42};
        const v2 = v1.foo;
        switch (v2) {
        default:
            v1.foo = 13.37;
            break;
        case 1337:
            v1.bar = 1337;
        case "42":
            v1.baz = "42";
            break;
        case 42:
            v1.bla = v2;
        }

        """

        XCTAssertEqual(lifted_program,expected_program)
    }

    func testBinaryOperationReassignLifting(){
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(1337)
        let v1 = b.loadFloat(13.37)
        b.binaryOpAndReassign(v0, to: v1, with: .Add)
        b.binaryOpAndReassign(v0, to: v1, with: .Mul)
        b.binaryOpAndReassign(v0, to: v1, with: .LShift)

        let v2 = b.loadString("hello")
        let v3 = b.loadString("world")
        b.binaryOpAndReassign(v2, to: v3, with: .Add)

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
        b.binaryOpAndReassign(v0, to: v1, with: .Add)
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
}

extension LifterTests {
    static var allTests : [(String, (LifterTests) -> () throws -> Void)] {
        return [
            ("testDeterministicLifting", testDeterministicLifting),
            ("testFuzzILLifter", testFuzzILLifter),
            ("testLiftingOptions", testLiftingOptions),
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
        ]
    }
}
