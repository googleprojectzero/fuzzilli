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
            b.build(n: 100, by: .generating)
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
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            _ = lifter.lift(program)
        }
    }

    func testExpressionInlining1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Object = b.loadBuiltin("Object")
        let obj = b.construct(Object, withArgs: [])
        let o = b.loadBuiltin("SomeObj")
        let foo = b.getProperty("foo", of: o)
        let bar = b.getProperty("bar", of: foo)
        let i = b.loadInt(42)
        let r = b.callMethod("baz", on: bar, withArgs: [i, i])
        b.setProperty("r", of: obj, to: r)
        let Math = b.loadBuiltin("Math")
        let lhs = b.callMethod("random", on: Math, withArgs: [])
        let rhs = b.loadFloat(13.37)
        let s = b.binary(lhs, rhs, with: .Add)
        b.setProperty("s", of: obj, to: s)
        b.getProperty("s", of: obj)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = new Object();
        v1.r = SomeObj.foo.bar.baz(42, 42);
        v1.s = Math.random() + 13.37;
        v1.s;

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Object = b.loadBuiltin("Object")
        let obj = b.construct(Object, withArgs: [])
        let i = b.loadInt(42)
        let o = b.loadBuiltin("SomeObj")
        let foo = b.getProperty("foo", of: o)
        let bar = b.getProperty("bar", of: foo)
        let baz = b.getProperty("baz", of: bar)
        let r = b.callFunction(baz, withArgs: [i, i])
        b.setProperty("r", of: obj, to: r)
        let Math = b.loadBuiltin("Math")
        let lhs = b.callMethod("random", on: Math, withArgs: [])
        let f = b.loadBuiltin("SideEffect")
        b.callFunction(f, withArgs: [])
        let rhs = b.loadFloat(13.37)
        let s = b.binary(lhs, rhs, with: .Add)
        b.setProperty("s", of: obj, to: s)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = new Object();
        const v6 = SomeObj.foo.bar.baz;
        v1.r = v6(42, 42);
        const v9 = Math.random();
        SideEffect();
        v1.s = v9 + 13.37;

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(0)
        let f = b.loadBuiltin("computeNumIterations")
        let numIterations = b.callFunction(f, withArgs: [])
        // The function call should not be inlined into the loop header as that would change the programs behavior.
        b.buildWhileLoop(v0, .lessThan, numIterations) {
            b.unary(.PostInc, v0)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        const v2 = computeNumIterations();
        while (v0 < v2) {
            v0++;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining4() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Object = b.loadBuiltin("Object")
        let o = b.construct(Object, withArgs: [])
        let v0 = b.loadInt(1337)
        let f1 = b.loadBuiltin("func1")
        let r1 = b.callFunction(f1, withArgs: [v0])
        let f2 = b.loadBuiltin("func2")
        let r2 = b.callFunction(f2, withArgs: [r1])
        b.setProperty("x", of: o, to: r2)
        b.setProperty("y", of: o, to: r2)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = new Object();
        const v6 = func2(func1(1337));
        v1.x = v6;
        v1.y = v6;

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining5() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // The identifier for NaN should be inlined into its uses...
        let n1 = b.loadFloat(Double.nan)
        b.createArray(with: [n1, n1, n1])
        // ... but when it's reassigned, the identifier needs to be stored to a local variable.
        let n2 = b.loadFloat(Double.nan)
        b.reassign(n2, to: b.loadFloat(13.37))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        [NaN,NaN,NaN];
        let v2 = NaN;
        v2 = 13.37;

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining6() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let o = args[0]
            let x = b.getProperty("x", of: o)
            let y = b.getProperty("y", of: o)
            let z = b.getProperty("z", of: o)
            // Cannot inline the property load of .x as that would change the
            // evaluation order at runtime (.x would now be loaded after .y).
            let r = b.ternary(y, x, z)
            b.doReturn(r)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1) {
            const v2 = a1.x;
            return a1.y ? v2 : a1.z;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining7() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // This testcase demonstrates a scenario that could still be improved.
        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let v = args[0]
            let two = b.loadInt(2)
            let Math = b.loadBuiltin("Math")
            let x = b.getProperty("x", of: v)
            // This expression will currently be assigned to a temporary variable even though it could be inlined into the Math.sqrt call.
            let xSquared = b.binary(x, two, with: .Exp)
            let y = b.getProperty("y", of: v)
            let ySquared = b.binary(y, two, with: .Exp)
            let sum = b.binary(xSquared, ySquared, with: .Add)
            let result = b.callMethod("sqrt", on: Math, withArgs: [sum])
            b.doReturn(result)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1) {
            const v5 = a1.x ** 2;
            return Math.sqrt(v5 + (a1.y ** 2));
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testObjectLiteralLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.loadInt(42)
        let v2 = b.loadFloat(13.37)
        let v3 = b.loadString("foobar")
        let null = b.loadNull()
        let v4 = b.binary(v3, v1, with: .Add)
        let otherObject = b.loadBuiltin("SomeObject")
        b.buildObjectLiteral { obj in
            obj.addProperty("p1", as: v1)
            obj.addProperty("__proto__", as: null)
            obj.addElement(0, as: v2)
            obj.addComputedProperty(v3, as: v3)
            obj.addProperty("p2", as: v2)
            obj.addComputedProperty(v4, as: v1)
            obj.addMethod("m", with: .parameters(n: 2)) { args in
                let r = b.binary(args[1], args[2], with: .Sub)
                b.doReturn(r)
            }
            obj.addGetter(for: "prop") { this in
                let r = b.getProperty("p", of: this)
                b.doReturn(r)
            }
            obj.addSetter(for: "prop") { this, v in
                b.setProperty("p", of: this, to: v)
            }
            obj.copyProperties(from: otherObject)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v4 = "foobar" + 42;
        const o14 = {
            "p1": 42,
            "__proto__": null,
            0: 13.37,
            ["foobar"]: "foobar",
            "p2": 13.37,
            [v4]: 42,
            m(a7, a8) {
                return a7 - a8;
            },
            get prop() {
                return this.p;
            },
            set prop(a13) {
                this.p = a13;
            },
            ...SomeObject,
        };

        """
        XCTAssertEqual(actual, expected)
    }

    func testClassDefinitionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(42)
        let two = b.loadInt(2)
        let baz = b.loadString("baz")
        let baz42 = b.binary(baz, i, with: .Add)
        let C = b.buildClassDefinition() { cls in
            cls.addInstanceProperty("foo")
            cls.addInstanceProperty("bar", value: baz)
            cls.addInstanceElement(0, value: i)
            cls.addInstanceElement(1)
            cls.addInstanceComputedProperty(baz42)
            cls.addInstanceComputedProperty(two, value: baz42)
            cls.addConstructor(with: .parameters(n: 1)) { params in
                let this = params[0]
                b.setProperty("foo", of: this, to: params[1])
            }
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { params in
                let this = params[0]
                let foo = b.getProperty("foo", of: this)
                b.doReturn(foo)
            }
            cls.addInstanceGetter(for: "baz") { this in
                b.doReturn(b.loadInt(1337))
            }
            cls.addInstanceSetter(for: "baz") { this, v in
            }
            
            cls.addStaticProperty("foo")
            cls.addStaticInitializer { this in
                b.setProperty("foo", of: this, to: i)
            }
            cls.addStaticProperty("bar", value: baz)
            cls.addStaticElement(0, value: i)
            cls.addStaticElement(1)
            cls.addStaticComputedProperty(baz42)
            cls.addStaticComputedProperty(two, value: baz42)
            cls.addStaticMethod("m", with: .parameters(n: 0)) { params in
                let this = params[0]
                let foo = b.getProperty("foo", of: this)
                b.doReturn(foo)
            }
            cls.addStaticGetter(for: "baz") { this in
                b.doReturn(b.loadInt(1337))
            }
            cls.addStaticSetter(for: "baz") { this, v in
            }

            cls.addPrivateInstanceProperty("ifoo")
            cls.addPrivateInstanceProperty("ibar", value: baz)
            cls.addPrivateInstanceMethod("im", with: .parameters(n: 0)) { args in
                let this = args[0]
                let foo = b.getPrivateProperty("ifoo", of: this)
                b.setPrivateProperty("ibar", of: this, to: foo)
                b.doReturn(foo)
            }
            cls.addPrivateInstanceMethod("in", with: .parameters(n: 1)) { args in
                let this = args[0]
                b.callPrivateMethod("im", on: this, withArgs: [])
                b.updatePrivateProperty("ibar", of: this, with: args[1], using: .Add)
            }
            cls.addPrivateStaticProperty("sfoo")
            cls.addPrivateStaticProperty("sbar", value: baz)
            cls.addPrivateStaticMethod("sm", with: .parameters(n: 0)) { args in
                let this = args[0]
                let foo = b.getPrivateProperty("sfoo", of: this)
                b.setPrivateProperty("sbar", of: this, to: foo)
                b.doReturn(foo)
            }
            cls.addPrivateStaticMethod("sn", with: .parameters(n: 1)) { args in
                let this = args[0]
                b.callPrivateMethod("sm", on: this, withArgs: [])
                b.updatePrivateProperty("sbar", of: this, with: args[1], using: .Add)
            }
        }
        b.construct(C, withArgs: [b.loadInt(42)])
        b.reassign(C, to: b.loadBuiltin("Uint8Array"))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v3 = "baz" + 42;
        class C4 {
            foo;
            bar = "baz";
            0 = 42;
            1;
            [v3];
            [2] = v3;
            constructor(a6) {
                this.foo = a6;
            }
            m() {
                return this.foo;
            }
            get baz() {
                return 1337;
            }
            set baz(a12) {
            }
            static foo;
            static {
                this.foo = 42;
            }
            static bar = "baz";
            static 0 = 42;
            static 1;
            static [v3];
            static [2] = v3;
            static m() {
                return this.foo;
            }
            static get baz() {
                return 1337;
            }
            static set baz(a19) {
            }
            #ifoo;
            #ibar = "baz";
            #im() {
                const v21 = this.#ifoo;
                this.#ibar = v21;
                return v21;
            }
            #in(a23) {
                this.#im();
                this.#ibar += a23;
            }
            static #sfoo;
            static #sbar = "baz";
            static #sm() {
                const v26 = this.#sfoo;
                this.#sbar = v26;
                return v26;
            }
            static #sn(a28) {
                this.#sm();
                this.#sbar += a28;
            }
        }
        const v31 = new C4(42);
        C4 = Uint8Array;

        """

        XCTAssertEqual(actual, expected)
    }

    func testArrayLiteralLifting() {
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
        b.createIntArray(with: [1, 2, 3, 4])
        b.createFloatArray(with: [1.1, 2.2, 3.3, 4.4])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v6 = "foobar";
        v6 = undefined;
        const v8 = [1,2,,4,,6,v6];
        [301,,];
        [,];
        [...v8,,];
        [,];
        [1,2,3,4];
        [1.1,2.2,3.3,4.4];

        """
        XCTAssertEqual(actual, expected)

    }

    func testBinaryOperationLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.loadBuiltin("Math")
        let v = b.callMethod("random", on: Math, withArgs: [])
        let two_v = b.binary(v, v, with: .Add)
        let three_v = b.binary(two_v, v, with: .Add)
        let twelve_v = b.binary(b.loadInt(4), three_v, with: .Mul)
        let six_v = b.binary(twelve_v, b.loadInt(2), with: .Div)
        let print = b.loadBuiltin("print")
        b.callFunction(print, withArgs: [six_v])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        // TODO: Lifting could be improved to remove some brackets.
        let expected = """
        const v1 = Math.random();
        print((4 * ((v1 + v1) + v1)) / 2);

        """

        XCTAssertEqual(actual, expected)
    }

    func testRegExpInlining() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadRegExp("a", RegExpFlags())
        b.compare(v0, with: v0, using: .equal);
        let v1 = b.loadRegExp("b", RegExpFlags())
        b.compare(v0, with: v1, using: .equal);

        let program = b.finalize()

        let actual = fuzzer.lifter.lift(program)
        let expected = """
        const v0 = /a/;
        v0 == v0;
        v0 == /b/;

        """

        XCTAssertEqual(actual, expected)
    }

    func testNestedCodeStrings() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let code1 = b.buildCodeString() {
            let code2 = b.buildCodeString() {
                let code3 = b.buildCodeString() {
                    let code4 = b.buildCodeString() {
                        let print = b.loadBuiltin("print")
                        let msg = b.loadString("Hello")
                        b.callFunction(print, withArgs: [msg])
                    }
                    let code5 = b.buildCodeString() {
                        let print = b.loadBuiltin("print")
                        let msg = b.loadString("World")
                        b.callFunction(print, withArgs: [msg])
                    }
                    let eval = b.loadBuiltin("eval")
                    b.callFunction(eval, withArgs: [code4])
                    b.callFunction(eval, withArgs: [code5])
                }
                let eval = b.loadBuiltin("eval")
                b.callFunction(eval, withArgs: [code3])
            }
            let eval = b.loadBuiltin("eval")
            b.callFunction(eval, withArgs: [code2])
        }
        let eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [code1])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v0 = `
            const v1 = \\`
                const v2 = \\\\\\`
                    const v3 = \\\\\\\\\\\\\\`
                        print("Hello");
                    \\\\\\\\\\\\\\`;
                    const v7 = \\\\\\\\\\\\\\`
                        print("World");
                    \\\\\\\\\\\\\\`;
                    eval(v3);
                    eval(v7);
                \\\\\\`;
                eval(v2);
            \\`;
            eval(v1);
        `;
        eval(v0);

        """

        XCTAssertEqual(actual, expected)

    }

    func testFunctionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.doReturn(args[0])
        }
        b.callFunction(f, withArgs: [b.loadFloat(13.37)])
        let f2 = b.buildArrowFunction(with: .parameters(n: 0)) { args in
            b.doReturn(b.loadString("foobar"))
        }
        b.reassign(f, to: f2)
        b.callFunction(f, withArgs: [])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1) {
            return a1;
        }
        f0(13.37);
        const v4 = () => {
            return "foobar";
        };
        f0 = v4;
        f0();

        """

        XCTAssertEqual(actual, expected)
    }

    func testStrictFunctionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let sf = b.buildPlainFunction(with: .parameters(n: 3), isStrict: true) { args in
            b.buildIfElse(args[0], ifBody: {
                let v = b.binary(args[1], args[2], with: .Mul)
                b.doReturn(v)
            }, elseBody: {
                let v = b.binary(args[1], args[2], with: .Add)
                b.doReturn(v)
            })
        }
        b.callFunction(sf, withArgs: [b.loadBool(true), b.loadInt(1), b.loadInt(2)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1, a2, a3) {
            'use strict';
            if (a1) {
                return a2 * a3;
            } else {
                return a2 + a3;
            }
        }
        f0(true, 1, 2);

        """

        XCTAssertEqual(actual, expected)
    }

    func testConstructorLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let c1 = b.buildConstructor(with: .parameters(n: 2)) { args in
            let this = args[0]
            b.setProperty("foo", of: this, to: args[1])
            b.setProperty("bar", of: this, to: args[2])
        }
        b.construct(c1, withArgs: [b.loadInt(42), b.loadInt(43)])
        let c2 = b.loadBuiltin("Object")
        b.reassign(c1, to: c2)
        b.construct(c1, withArgs: [b.loadInt(44), b.loadInt(45)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function F0(a2, a3) {
            if (!new.target) { throw 'must be called with new'; }
            this.foo = a2;
            this.bar = a3;
        }
        const v6 = new F0(42, 43);
        F0 = Object;
        const v10 = new F0(44, 45);

        """
        XCTAssertEqual(actual, expected)
    }

    func testAsyncFunctionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f1 = b.buildAsyncFunction(with: .parameters(n: 2)) { args in
            let lhs = b.await(args[0])
            let rhs = b.await(args[1])
            let r = b.binary(lhs, rhs, with: .Add)
            b.doReturn(r)
        }
        let f2 = b.buildAsyncGeneratorFunction(with: .parameters(n: 2), isStrict: true) { args in
            let lhs = b.await(args[0])
            let rhs = b.await(args[1])
            let r = b.binary(lhs, rhs, with: .Mul)
            b.yield(r)
        }
        b.callFunction(f1, withArgs: [b.loadBuiltin("promise1"), b.loadBuiltin("promise2")])
        b.callFunction(f2, withArgs: [b.loadBuiltin("promise3"), b.loadBuiltin("promise4")])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        async function f0(a1, a2) {
            return await a1 + await a2;
        }
        async function* f6(a7, a8) {
            'use strict';
            yield await a7 * await a8;
        }
        f0(promise1, promise2);
        f6(promise3, promise4);

        """

        XCTAssertEqual(actual, expected)
    }

    func testConditionalOperationLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.createObject(with: ["a" : b.loadInt(1337)])
        let v2 = b.getProperty("a", of: v1)
        let v3 = b.loadInt(10)
        let v4 = b.compare(v2, with: v3, using: .greaterThan)
        let _ = b.ternary(v4, v2, v3)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o1 = {
            "a": 1337,
        };
        const v2 = o1.a;
        v2 > 10 ? v2 : 10;

        """
        XCTAssertEqual(actual, expected)
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 1337;
        v0 += 13.37;
        v0 *= 13.37;
        v0 <<= 13.37;
        let v2 = "hello";
        v2 += "world";

        """

        XCTAssertEqual(actual, expected)
    }

    func testReassignmentLifting() {
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 1337;
        let v1 = 13.37;
        v0 += v1;
        v1 = "Hello";
        let v3 = 1336;
        let v4 = ++v3;
        v4++;

        """

        XCTAssertEqual(actual, expected)
    }

    func testCreateTemplateLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.createTemplateString(from: [""], interpolating: [])
        let bar = b.loadString("bar")
        b.createTemplateString(from: ["foo", "baz"], interpolating: [bar])
        let space = b.loadString(" ")
        let inner = b.createTemplateString(from: ["Hello", "World"], interpolating: [space])
        let marker = b.callFunction(b.loadBuiltin("getMarker"), withArgs: [])
        let _ = b.createTemplateString(from: ["", "", "", ""], interpolating: [marker, inner, marker] )

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        ``;
        `foo${"bar"}baz`;
        const v6 = getMarker();
        `${v6}${`Hello${" "}World`}${v6}`;

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyAccessLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let o = b.loadBuiltin("Obj")
        let propA = b.getProperty("a", of: o)
        let propB = b.getProperty("b", of: propA)
        let propC = b.getProperty("c", of: propB)
        b.setElement(1337, of: o, to: propC)
        let o2 = b.createArray(with: [])
        let elem0 = b.getElement(0, of: o)
        let elem1 = b.getElement(1, of: elem0)
        let elem2 = b.getElement(2, of: elem1)
        // For aesthetic reasons, the object literal isn't inlined into the assignment expression, but the property name expression is.
        b.setComputedProperty(elem2, of: o2, to: b.loadInt(42))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        Obj[1337] = Obj.a.b.c;
        const v4 = [];
        v4[Obj[0][1][2]] = 42;

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyAccessWithBinopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 =  b.loadString("baz")
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")
        let v5 = b.loadFloat(13.37)
        b.setProperty("foo", of: v1, to: v5)
        b.updateProperty("foo", of: v1, with: v4, using: BinaryOperator.Add)
        b.setProperty("bar", of: v1, to: v3)
        b.updateProperty("bar", of: v1, with: v3, using: BinaryOperator.Mul)
        b.setComputedProperty(v2, of: v1, to: v0)
        b.updateComputedProperty(v2, of: v1, with: v3, using: BinaryOperator.LogicAnd)
        let arr = b.createArray(with: [v3,v3,v3])
        b.setElement(0, of: arr, to: v0)
        b.updateElement(0, of: arr, with: v5, using: BinaryOperator.Sub)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o1 = {
            "foo": 42,
        };
        o1.foo = 13.37;
        o1.foo += "42";
        o1.bar = 1337;
        o1.bar *= 1337;
        o1["baz"] = 42;
        o1["baz"] &&= 1337;
        const v6 = [1337,1337,1337];
        v6[0] = 42;
        v6[0] -= 13.37;

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyConfigurationOpsLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let obj = b.createObject(with: [:])
        let v = b.loadUndefined()
        let f1 = b.buildPlainFunction(with: .parameters(n: 0)) { args in
            b.doReturn(v)
        }
        let f2 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.reassign(v, to: args[0])
        }
        let num = b.loadInt(42)
        b.configureProperty("foo", of: obj, usingFlags: [.enumerable, .configurable], as: .getter(f1))
        b.configureProperty("bar", of: obj, usingFlags: [], as: .setter(f2))
        b.configureProperty("foobar", of: obj, usingFlags: [.enumerable], as: .getterSetter(f1, f2))
        b.configureProperty("baz", of: obj, usingFlags: [.writable], as: .value(num))
        b.configureElement(0, of: obj, usingFlags: [.writable], as: .getter(f1))
        b.configureElement(1, of: obj, usingFlags: [.writable, .enumerable], as: .setter(f2))
        b.configureElement(2, of: obj, usingFlags: [.writable, .enumerable, .configurable], as: .getterSetter(f1, f2))
        b.configureElement(3, of: obj, usingFlags: [], as: .value(num))
        let p = b.loadBuiltin("ComputedProperty")
        b.configureComputedProperty(p, of: obj, usingFlags: [.configurable], as: .getter(f1))
        b.configureComputedProperty(p, of: obj, usingFlags: [.enumerable], as: .setter(f2))
        b.configureComputedProperty(p, of: obj, usingFlags: [.writable], as: .getterSetter(f1, f2))
        b.configureComputedProperty(p, of: obj, usingFlags: [], as: .value(num))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o0 = {
        };
        let v1 = undefined;
        function f2() {
            return v1;
        }
        function f3(a4) {
            v1 = a4;
        }
        Object.defineProperty(o0, "foo", { configurable: true, enumerable: true, get: f2 });
        Object.defineProperty(o0, "bar", { set: f3 });
        Object.defineProperty(o0, "foobar", { enumerable: true, get: f2, set: f3 });
        Object.defineProperty(o0, "baz", { writable: true, value: 42 });
        Object.defineProperty(o0, 0, { writable: true, get: f2 });
        Object.defineProperty(o0, 1, { writable: true, enumerable: true, set: f3 });
        Object.defineProperty(o0, 2, { writable: true, configurable: true, enumerable: true, get: f2, set: f3 });
        Object.defineProperty(o0, 3, { value: 42 });
        Object.defineProperty(o0, ComputedProperty, { configurable: true, get: f2 });
        Object.defineProperty(o0, ComputedProperty, { enumerable: true, set: f3 });
        Object.defineProperty(o0, ComputedProperty, { writable: true, get: f2, set: f3 });
        Object.defineProperty(o0, ComputedProperty, { value: 42 });

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyDeletionLifting() {
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o3 = {
            "bar": 13.37,
            "foo": 1337,
        };
        delete o3.foo;
        delete o3["bar"];
        const v10 = [301,4,68,22];
        delete v10[3];

        """

        XCTAssertEqual(actual, expected)
    }

    func testFunctionCallLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let s = b.loadString("print('Hello World!')")
        var eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [s])
        let this = b.loadBuiltin("this")
        eval = b.getProperty("eval", of: this)
        // The property load must not be inlined, otherwise it would not be distinguishable from a method call (like the one following it).
        b.callFunction(eval, withArgs: [s])
        b.callMethod("eval", on: this, withArgs: [s])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        eval("print('Hello World!')");
        const v4 = this.eval;
        v4("print('Hello World!')");
        this.eval("print('Hello World!')");

        """

        XCTAssertEqual(actual, expected)
    }

    func testFunctionCallWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(1))
        initialValues.append(b.loadInt(2))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let values = b.createArray(with: initialValues)
        let n = b.loadFloat(13.37)
        let Array = b.loadBuiltin("Array")
        let _ = b.callFunction(Array, withArgs: [values,n], spreading: [true,false])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        Array(...[1,2,"Hello","World"], 13.37);

        """

        XCTAssertEqual(actual, expected)
    }

    func testMethodCallLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.loadBuiltin("Math")
        let r = b.callMethod("random", on: Math, withArgs: [])
        b.callMethod("sin", on: Math, withArgs: [r])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        Math.sin(Math.random());

        """

        XCTAssertEqual(actual, expected)
    }

    func testMethodCallWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.loadBuiltin("Math")
        var initialValues = [Variable]()
        initialValues.append(b.loadInt(1))
        initialValues.append(b.loadInt(3))
        initialValues.append(b.loadInt(9))
        initialValues.append(b.loadInt(10))
        initialValues.append(b.loadInt(2))
        initialValues.append(b.loadInt(6))
        let values = b.createArray(with: initialValues)
        let n1 = b.loadInt(0)
        let n2 = b.loadInt(4)
        b.callMethod("max", on: Math, withArgs: [n1,values,n2], spreading: [false, true, false])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        Math.max(0, ...[1,3,9,10,2,6], 4);

        """

        XCTAssertEqual(actual, expected)
    }

    func testComputedMethodCallLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let s = b.loadString("Hello World")
        let Symbol = b.loadBuiltin("Symbol")
        let iterator = b.getProperty("iterator", of: Symbol)
        let r = b.callComputedMethod(iterator, on: s, withArgs: [])
        b.callMethod("next", on: r, withArgs: [])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        ("Hello World")[Symbol.iterator]().next();

        """

        XCTAssertEqual(actual, expected)
    }

    func testComputedMethodCallWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let SomeObj = b.loadBuiltin("SomeObject")
        let RandomMethod = b.loadBuiltin("RandomMethod")
        let randomMethod = b.callFunction(RandomMethod, withArgs: [])
        let args = b.createArray(with: [b.loadInt(1), b.loadInt(2), b.loadInt(3), b.loadInt(4)])
        b.callComputedMethod(randomMethod, on: SomeObj, withArgs: [args], spreading: [true])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        SomeObject[RandomMethod()](...[1,2,3,4]);

        """

        XCTAssertEqual(actual, expected)
    }

    func testConstructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(1))
        initialValues.append(b.loadInt(2))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let values = b.createArray(with: initialValues)
        let n1 = b.loadFloat(13.37)
        let n2 = b.loadFloat(13.38)
        let Array = b.loadBuiltin("Array")
        b.construct(Array, withArgs: [n1,values,n2], spreading: [false,true,false])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v8 = new Array(13.37, ...[1,2,"Hello","World"], 13.38);

        """

        XCTAssertEqual(actual, expected)
    }

    func testSuperPropertyWithBinopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
            }

            cls.addInstanceMethod("f", with: .parameters(n: 1)) { params in
                b.doReturn(b.loadString("foobar"))
            }
        }
        let C = b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
                b.setSuperProperty("bar", to: b.loadInt(100))
            }
            cls.addInstanceMethod("g", with: .parameters(n: 1)) { params in
                b.updateSuperProperty("bar", with: b.loadInt(1337), using: BinaryOperator.Add)
             }
        }
        b.construct(C, withArgs: [b.loadFloat(13.37)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        class C0 {
            constructor(a2) {
            }
            f(a4) {
                return "foobar";
            }
        }
        class C6 extends C0 {
            constructor(a8) {
                super.bar = 100;
            }
            g(a11) {
                super.bar += 1337;
            }
        }
        const v14 = new C6(13.37);

        """

        XCTAssertEqual(actual, expected)
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o2 = {
            "bar": 13.37,
            "foo": 42,
        };
        let {"foo":v3,...v4} = o2;
        let {"foo":v5,"bar":v6,...v7} = o2;
        let {...v8} = o2;
        let {"foo":v9,"bar":v10,} = o2;

        """

        XCTAssertEqual(actual, expected)
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 42;
        let v1 = 13.37;
        let v2 = "Hello";
        const o3 = {
            "bar": v1,
            "foo": v0,
        };
        ({"foo":v2,...v0} = o3);
        ({"foo":v2,"bar":v0,...v1} = o3);
        ({...v2} = o3);
        ({"foo":v2,"bar":v1,} = o3);

        """

        XCTAssertEqual(actual, expected)
    }

    func testArrayDestructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let arr = b.createArray(with: initialValues)
        b.destruct(arr, selecting: [0,1])
        b.destruct(arr, selecting: [0,2,5])
        b.destruct(arr, selecting: [0,2], lastIsRest: true)
        b.destruct(arr, selecting: [0], lastIsRest: true)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v4 = [15,30,"Hello","World"];
        let [v5,v6] = v4;
        let [v7,,v8,,,v9] = v4;
        let [v10,,...v11] = v4;
        let [...v12] = v4;

        """

        XCTAssertEqual(actual, expected)
    }

    func testArrayDestructAndReassignLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let array = b.createArray(with: initialValues)
        let i = b.loadInt(1000)
        let s = b.loadString("foobar")
        b.destruct(array, selecting: [0,2], into: [i, s], lastIsRest: true)
        b.destruct(array, selecting: [0], into: [i], lastIsRest: true)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v4 = [15,30,"Hello","World"];
        let v5 = 1000;
        let v6 = "foobar";
        [v5,,...v6] = v4;
        [...v5] = v4;

        """

        XCTAssertEqual(actual, expected)
    }

    func testTryCatchLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(v)
            }, catchBody: { _ in
                let v = b.binary(args[0], args[1], with: .Div)
                b.doReturn(v)
            })
        }
        b.callFunction(f, withArgs: [b.loadInt(1337), b.loadInt(42)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1, a2) {
            try {
                return a1 * a2;
            } catch(e4) {
                return a1 / a2;
            }
        }
        f0(1337, 42);

        """

        XCTAssertEqual(actual, expected)
    }

    func testTryFinallyLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(v)
            }, finallyBody: {
                let v = b.binary(args[0], args[1], with: .Mod)
                b.doReturn(v)
            })
        }
        b.callFunction(f, withArgs: [b.loadInt(1337), b.loadInt(42)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1, a2) {
            try {
                return a1 * a2;
            } finally {
                return a1 % a2;
            }
        }
        f0(1337, 42);

        """

        XCTAssertEqual(actual, expected)
    }

    func testTryCatchFinallyLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            b.buildTryCatchFinally(tryBody: {
                let v = b.binary(args[0], args[1], with: .Mul)
                b.doReturn(v)
            }, catchBody: { _ in
                let v = b.binary(args[0], args[1], with: .Div)
                b.doReturn(v)
            }, finallyBody: {
                let v = b.binary(args[0], args[1], with: .Mod)
                b.doReturn(v)
            })
        }
        b.callFunction(f, withArgs: [b.loadInt(1337), b.loadInt(42)])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1, a2) {
            try {
                return a1 * a2;
            } catch(e4) {
                return a1 / a2;
            } finally {
                return a1 % a2;
            }
        }
        f0(1337, 42);

        """

        XCTAssertEqual(actual, expected)
    }

    func testSwitchStatementLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 =  b.getProperty("foo", of: v1)
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")
        let v5 = b.loadFloat(13.37)

        b.buildSwitch(on: v2) { cases in
            cases.add(v3, fallsThrough: false) {
                b.setProperty("bar", of: v1, to: v3)
            }
            cases.add(v4, fallsThrough: false){
                b.setProperty("baz", of: v1, to: v4)
            }
            cases.addDefault(fallsThrough: true){
                b.setProperty("foo", of: v1, to: v5)
            }
            cases.add(v0, fallsThrough: true) {
                b.setProperty("bla", of: v1, to: v2)
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o1 = {
            "foo": 42,
        };
        const v2 = o1.foo;
        switch (v2) {
            case 1337:
                o1.bar = 1337;
                break;
            case "42":
                o1.baz = "42";
                break;
            default:
                o1.foo = 13.37;
            case 42:
                o1.bla = v2;
        }

        """

        XCTAssertEqual(actual, expected)
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        do {
            let v2 = 0;
            do {
                v2++;
            } while (v2 < 1337);
            v0++;
        } while (v0 < 42);

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let start = b.loadInt(42)
        let end = b.loadInt(0)
        let step = b.loadInt(2)
        b.buildForLoop(start, .greaterThan, end, .Div, step) { i in
            let print = b.loadBuiltin("print")
            b.callFunction(print, withArgs: [i])
        }
    }

    func testRepeatLoopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let s = b.loadInt(0)
        b.buildRepeat(n: 1337) { i in
            b.reassign(s, to: i, with: .Add)
        }
        let print = b.loadBuiltin("print")
        b.callFunction(print, withArgs: [s])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        for (let v1 = 0; v1 < 1337; v1++) {
            v0 += v1;
        }
        print(v0);

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopWithArrayDestructLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let a1 = b.createArray(with: [b.loadInt(10), b.loadInt(11), b.loadInt(12), b.loadInt(13), b.loadInt(14)])
        let a2 = b.createArray(with: [b.loadInt(20), b.loadInt(21), b.loadInt(22), b.loadInt(23)])
        let a3 = b.createArray(with: [b.loadInt(30), b.loadInt(31), b.loadInt(32)])
        let a4 = b.createArray(with: [a1, a2, a3])
        let print = b.loadBuiltin("print")
        b.buildForOfLoop(a4, selecting: [0,2], hasRestElement: true) { args in
            b.callFunction(print, withArgs: [args[0]])
            b.buildForOfLoop(args[1]) { v in
                b.callFunction(print, withArgs: [v])
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let [v17,,...v18] of [[10,11,12,13,14],[20,21,22,23],[30,31,32]]) {
            print(v17);
            for (const v20 of v18) {
                print(v20);
            }
        }

        """

        XCTAssertEqual(actual, expected)
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
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const o1 = {
            "a": 1337,
        };
        for (let v2 in o1) {
            {
                v2 = 1337;
                {
                    const o4 = {
                        "a": o1,
                    };
                    v2 = o4;
                }
            }
        }

        """

        XCTAssertEqual(actual, expected)
    }
}
