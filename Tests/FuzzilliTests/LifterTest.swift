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
            b.buildPrefix()
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
            b.buildPrefix()
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            _ = lifter.lift(program)
        }
    }

    func testLiftingWithLineNumbers() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            let codeWithLinenumbers = fuzzer.lifter.lift(program, withOptions: .includeLineNumbers)

            for (i, line) in codeWithLinenumbers.split(separator: "\n").enumerated() {
                XCTAssert(line.trimmingCharacters(in: .whitespaces).starts(with: "\(i+1)"))
            }
        }
    }

    func testExpressionInlining1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Object = b.createNamedVariable(forBuiltin: "Object")
        let obj = b.construct(Object)
        let o = b.createNamedVariable(forBuiltin: "SomeObj")
        let foo = b.getProperty("foo", of: o)
        let bar = b.getProperty("bar", of: foo)
        let i = b.loadInt(42)
        let r = b.callMethod("baz", on: bar, withArgs: [i, i])
        b.setProperty("r", of: obj, to: r)
        let Math = b.createNamedVariable(forBuiltin: "Math")
        let lhs = b.callMethod("random", on: Math)
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

        let Object = b.createNamedVariable(forBuiltin: "Object")
        let obj = b.construct(Object)
        let i = b.loadInt(42)
        let o = b.createNamedVariable(forBuiltin: "SomeObj")
        let foo = b.getProperty("foo", of: o)
        let bar = b.getProperty("bar", of: foo)
        let baz = b.getProperty("baz", of: bar)
        let r = b.callFunction(baz, withArgs: [i, i])
        b.setProperty("r", of: obj, to: r)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = new Object();
        const t1 = SomeObj.foo.bar.baz;
        v1.r = t1(42, 42);

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // Test that effectful operations aren't reordered in any sematic-changing way.
        let Object = b.createNamedVariable(forBuiltin: "Object")
        let obj = b.construct(Object)
        let effectful = b.createNamedVariable(forBuiltin: "effectful")

        var lhs = b.callMethod("func1", on: effectful)
        var rhs = b.callMethod("func2", on: effectful)
        var res = b.binary(lhs, rhs, with: .Add)
        b.setProperty("res1", of: obj, to: res)

        lhs = b.callMethod("func3", on: effectful)
        b.callMethod("func4", on: effectful)
        rhs = b.loadFloat(13.37)
        res = b.binary(lhs, rhs, with: .Add)
        b.setProperty("res2", of: obj, to: res)

        b.callMethod("func5", on: effectful)
        let val1 = b.callMethod("func6", on: effectful)
        b.callMethod("func7", on: effectful)
        let val2 = b.loadFloat(13.37)
        res = b.unary(.Minus, val1)
        b.setProperty("res3", of: obj, to: res)
        b.setProperty("res4", of: obj, to: val2)

        let arg = b.callMethod("func8", on: effectful)
        let res1 = b.callMethod("func9", on: effectful)
        let res2 = b.callMethod("func10", on: effectful, withArgs: [arg])
        b.setProperty("res5", of: obj, to: res1)
        b.setProperty("res6", of: obj, to: res2)

        b.callMethod("func11", on: effectful)
        let tmp1 = b.callMethod("func12", on: effectful)
        let tmp2 = b.callMethod("func13", on: effectful)
        lhs = b.callMethod("func14", on: effectful)
        rhs = b.callMethod("func15", on: effectful)
        rhs = b.binary(lhs, rhs, with: .Mul)
        lhs = b.binary(tmp2, rhs, with: .Add)
        res = b.binary(lhs, tmp1, with: .Div)
        b.setProperty("res7", of: obj, to: res)

        var x = b.callMethod("func16", on: effectful)
        var y = b.callMethod("func17", on: effectful)
        var z = b.callMethod("func18", on: effectful)
        res = b.callMethod("func19", on: effectful, withArgs: [x, y, z])
        b.setProperty("res8", of: obj, to: res)

        x = b.callMethod("func20", on: effectful)
        y = b.callMethod("func21", on: effectful)
        z = b.callMethod("func22", on: effectful)
        res = b.callMethod("func23", on: effectful, withArgs: [y, z, x])
        b.setProperty("res9", of: obj, to: res)

        x = b.callMethod("func24", on: effectful)
        y = b.callMethod("func25", on: effectful)
        z = b.callMethod("func26", on: effectful)
        res = b.callMethod("func27", on: effectful, withArgs: [x, z, y])
        b.setProperty("res10", of: obj, to: res)

        x = b.callMethod("func28", on: effectful)
        y = b.callMethod("func29", on: effectful)
        z = b.callMethod("func30", on: effectful)
        res = b.callMethod("func31", on: effectful, withArgs: [z, x, y])
        b.setProperty("res11", of: obj, to: res)

        x = b.callMethod("func32", on: effectful)
        y = b.callMethod("func33", on: effectful)
        z = b.callMethod("func34", on: effectful)
        let tmp = b.callMethod("func35", on: effectful, withArgs: [y])
        res = b.callMethod("func36", on: effectful, withArgs: [x, z, tmp])
        b.setProperty("res12", of: obj, to: res)


        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = new Object();
        v1.res1 = effectful.func1() + effectful.func2();
        const v6 = effectful.func3();
        effectful.func4();
        v1.res2 = v6 + 13.37;
        effectful.func5();
        const v11 = effectful.func6();
        effectful.func7();
        v1.res3 = -v11;
        v1.res4 = 13.37;
        const v15 = effectful.func8();
        const v16 = effectful.func9();
        const v17 = effectful.func10(v15);
        v1.res5 = v16;
        v1.res6 = v17;
        effectful.func11();
        const v19 = effectful.func12();
        v1.res7 = (effectful.func13() + (effectful.func14() * effectful.func15())) / v19;
        v1.res8 = effectful.func19(effectful.func16(), effectful.func17(), effectful.func18());
        const v30 = effectful.func20();
        v1.res9 = effectful.func23(effectful.func21(), effectful.func22(), v30);
        const v34 = effectful.func24();
        const v35 = effectful.func25();
        v1.res10 = effectful.func27(v34, effectful.func26(), v35);
        const v38 = effectful.func28();
        const v39 = effectful.func29();
        v1.res11 = effectful.func31(effectful.func30(), v38, v39);
        const v42 = effectful.func32();
        const v43 = effectful.func33();
        const v44 = effectful.func34();
        v1.res12 = effectful.func36(v42, v44, effectful.func35(v43));

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining4() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let someValue = b.createNamedVariable(forBuiltin: "someValue")
        let computeThreshold = b.createNamedVariable(forBuiltin: "computeThreshold")
        let threshold = b.callFunction(computeThreshold)
        let cond = b.compare(someValue, with: threshold, using: .lessThan)
        // The comparison and the function call can be inlined into the header of the if-statement.
        b.buildIf(cond) {
            let doSomething = b.createNamedVariable(forBuiltin: "doSomething")
            b.callFunction(doSomething)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        if (someValue < computeThreshold()) {
            doSomething();
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionInlining5() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(0)
        let f = b.createNamedVariable(forBuiltin: "computeNumIterations")
        let numIterations = b.callFunction(f)
        // The function call should not be inlined into the loop header as that would change the programs behavior.
        b.buildWhileLoop({ b.compare(v0, with: numIterations, using: .lessThan) }) {
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

    func testExpressionInlining6() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // Test that (potentially) effectful operations are only executed once.
        let Object = b.createNamedVariable(forBuiltin: "Object")
        let o = b.construct(Object)
        let v0 = b.loadInt(1337)
        let f1 = b.createNamedVariable(forBuiltin: "func1")
        let r1 = b.callFunction(f1, withArgs: [v0])
        let f2 = b.createNamedVariable(forBuiltin: "func2")
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

    func testExpressionInlining7() {
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

    func testExpressionInlining8() {
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

        // Note that this example also demonstrates that we currently allow expressions
        // to be inlined into lazily-evaluated expressions, which may cause them to not
        // be executed at runtime (in the example here, the a1.z load may never execute).

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

    func testExpressionInlining9() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let p = args[0]
            let two = b.loadInt(2)
            let Math = b.createNamedVariable(forBuiltin: "Math")
            let x = b.getProperty("x", of: p)
            let xSquared = b.binary(x, two, with: .Exp)
            let y = b.getProperty("y", of: p)
            let ySquared = b.binary(y, two, with: .Exp)
            let sum = b.binary(xSquared, ySquared, with: .Add)
            let result = b.callMethod("sqrt", on: Math, withArgs: [sum])
            b.doReturn(result)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1) {
            return Math.sqrt((a1.x ** 2) + (a1.y ** 2));
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testExpressionUninlining() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // This test ensures that expression inlining works corretly even when
        // expressions are explicitly "un-inlined", for example by a SetElement
        // operation where we force the object to be a variable.
        let i1 = b.loadInt(0)
        let i2 = b.loadInt(10)
        b.buildDoWhileLoop(do: {
            // The SetElement will "un-inline" i2, but for the do-while loop we'll still need the inlined expression (`10`).
            b.setElement(0, of: i2, to: i1)
            b.setElement(1, of: i2, to: i1)
            b.unary(.PostInc, i1)
        }, while: { b.compare(i1, with: i2, using: .lessThan) })

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        do {
            const t2 = 10;
            t2[0] = v0;
            const t4 = 10;
            t4[1] = v0;
            v0++;
        } while (v0 < 10)

        """

        XCTAssertEqual(actual, expected)
    }

    func testIdentifierLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // This tests checks that identifiers and other pure expressions
        // are completely omitted from the lifted code if they are not used.
        // This is important in some cases, for example if a non-existant
        // named variable is (only) accessed via `typeof`. In that case, the
        // `typeof` will make the access valid (no exception is raised), and so
        // the construct can currently only be minimized if an (unused) named
        // variable access also does not raise an exception.
        b.loadInt(42)
        b.loadString("foobar")
        b.createNamedVariable("nonexistant", declarationMode: .none)
        let v = b.createNamedVariable("alsoNonexistantButSafeToAccessViaTypeOf", declarationMode: .none)
        b.typeof(v)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        typeof alsoNonexistantButSafeToAccessViaTypeOf;

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
        let otherObject = b.createNamedVariable(forBuiltin: "SomeObject")
        let toPrimitive = b.getProperty("toPrimitive", of: b.createNamedVariable(forBuiltin: "Symbol"))
        b.buildObjectLiteral { obj in
            obj.addProperty("p1", as: v1)
            obj.addProperty("__proto__", as: null)
            obj.addElement(0, as: v2)
            obj.addElement(-1, as: v2)
            obj.addComputedProperty(v3, as: v3)
            obj.addProperty("p2", as: v2)
            obj.addComputedProperty(v4, as: v1)
            obj.setPrototype(to: null)
            obj.addMethod("m", with: .parameters(n: 2)) { args in
                let r = b.binary(args[1], args[2], with: .Sub)
                b.doReturn(r)
            }
            obj.addComputedMethod(toPrimitive, with: .parameters(n: 0)) { args in
                b.doReturn(v1)
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
        const v7 = Symbol.toPrimitive;
        const v17 = {
            p1: 42,
            __proto__: null,
            0: 13.37,
            [-1]: 13.37,
            ["foobar"]: "foobar",
            p2: 13.37,
            [v4]: 42,
            __proto__: null,
            m(a9, a10) {
                return a9 - a10;
            },
            [v7]() {
                return 42;
            },
            get prop() {
                return this.p;
            },
            set prop(a16) {
                this.p = a16;
            },
            ...SomeObject,
        };

        """
        XCTAssertEqual(actual, expected)
    }

    func testObjectLiteralIsDistinguishableFromBlockStatement() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(1)
        let i2 = b.loadInt(2)
        b.buildObjectLiteral { obj in
            obj.addProperty("foo", as: i1)
            obj.addProperty("bar", as: i2)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        // These must not lift to something like "{ foo: 1, bar: 2 };" as that would be invalid:
        // the parser cannot distinguish it from a block statement.
        let expected = """
        const v2 = { foo: 1, bar: 2 };

        """
        XCTAssertEqual(actual, expected)
    }

    func testObjectLiteralInlining() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let print = b.createNamedVariable(forBuiltin: "print")

        // We inline empty object literals.
        let o1 = b.buildObjectLiteral { obj in }
        b.callFunction(print, withArgs: [o1])

        // We inline "simple" object literals"
        let i = b.loadInt(42)
        let f = b.loadFloat(13.37)
        let foo = b.loadString("foo")
        let o2 = b.buildObjectLiteral { obj in
            obj.addProperty("foo", as: i)
            obj.addProperty("bar", as: f)
            obj.addElement(42, as: foo)
        }
        b.callFunction(print, withArgs: [o2])

        // We don't inline object literals as soon as they have any methods.
        let o3 = b.buildObjectLiteral { obj in
            obj.addMethod("baz", with: .parameters(n: 0)) { _ in }
        }
        b.callFunction(print, withArgs: [o3])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        print({});
        print({ foo: 42, bar: 13.37, 42: "foo" });
        const v9 = {
            baz() {
            },
        };
        print(v9);

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
            cls.addInstanceElement(-1)
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
            cls.addStaticElement(-1)
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
                b.callPrivateMethod("im", on: this)
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
                b.callPrivateMethod("sm", on: this)
                b.updatePrivateProperty("sbar", of: this, with: args[1], using: .Add)
            }
        }
        b.construct(C, withArgs: [b.loadInt(42)])
        b.reassign(C, to: b.createNamedVariable(forBuiltin: "Uint8Array"))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v3 = "baz" + 42;
        class C4 {
            foo;
            bar = "baz";
            0 = 42;
            1;
            [-1];
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
            static [-1];
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
        new C4(42);
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
        const v8 = [1,2,,4,,6,v6 = undefined];
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

        let Math = b.createNamedVariable(forBuiltin: "Math")
        let v = b.callMethod("random", on: Math)
        let two_v = b.binary(v, v, with: .Add)
        let three_v = b.binary(two_v, v, with: .Add)
        let twelve_v = b.binary(b.loadInt(4), three_v, with: .Mul)
        let six_v = b.binary(twelve_v, b.loadInt(2), with: .Div)
        let print = b.createNamedVariable(forBuiltin: "print")
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
                        let print = b.createNamedVariable(forBuiltin: "print")
                        let msg = b.loadString("Hello")
                        b.callFunction(print, withArgs: [msg])
                    }
                    let code5 = b.buildCodeString() {
                        let print = b.createNamedVariable(forBuiltin: "print")
                        let msg = b.loadString("World")
                        b.callFunction(print, withArgs: [msg])
                    }
                    let eval = b.createNamedVariable(forBuiltin: "eval")
                    b.callFunction(eval, withArgs: [code4])
                    b.callFunction(eval, withArgs: [code5])
                }
                let eval = b.createNamedVariable(forBuiltin: "eval")
                b.callFunction(eval, withArgs: [code3])
            }
            let eval = b.createNamedVariable(forBuiltin: "eval")
            b.callFunction(eval, withArgs: [code2])
        }
        let eval = b.createNamedVariable(forBuiltin: "eval")
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
        b.callFunction(f)

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

        let sf = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            b.directive("use strict")
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

    func testNamedFunctionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let foo = b.buildPlainFunction(with: .parameters(n: 0), named: "foo") { args in }
        let bar = b.buildGeneratorFunction(with: .parameters(n: 0), named: "bar") { args in }
        let baz = b.buildAsyncFunction(with: .parameters(n: 0), named: "baz") { args in }
        let bla = b.buildAsyncGeneratorFunction(with: .parameters(n: 0), named: "bla") { args in }

        b.callFunction(foo)
        b.callFunction(bar)
        b.callFunction(baz)
        b.callFunction(bla)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function foo() {
        }
        function* bar() {
        }
        async function baz() {
        }
        async function* bla() {
        }
        foo();
        bar();
        baz();
        bla();

        """
        XCTAssertEqual(actual, expected)
    }

    func testFunctionHoistingLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let foo = b.createNamedVariable("foo", declarationMode: .none)
        b.callFunction(foo)
        b.buildPlainFunction(with: .parameters(n: 0), named: "foo") { args in }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        foo();
        function foo() {
        }

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
        let c2 = b.createNamedVariable(forBuiltin: "Object")
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
        new F0(42, 43);
        F0 = Object;
        new F0(44, 45);

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
        let f2 = b.buildAsyncGeneratorFunction(with: .parameters(n: 2)) { args in
            b.directive("use strict")
            let lhs = b.await(args[0])
            let rhs = b.await(args[1])
            let r = b.binary(lhs, rhs, with: .Mul)
            b.yield(r)
        }
        b.callFunction(f1, withArgs: [b.createNamedVariable(forBuiltin: "promise1"), b.createNamedVariable(forBuiltin: "promise2")])
        b.callFunction(f2, withArgs: [b.createNamedVariable(forBuiltin: "promise3"), b.createNamedVariable(forBuiltin: "promise4")])

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
        const v2 = ({ a: 1337 }).a;
        v2 > 10 ? v2 : 10;

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

    func testUpdateLifting() {
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

    func testReassignmentInlining() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let foo = b.createNamedVariable(forBuiltin: "foo")
        let bar = b.createNamedVariable(forBuiltin: "bar")
        let baz = b.createNamedVariable(forBuiltin: "baz")
        let i = b.loadInt(42)
        b.reassign(i, to: b.loadInt(43))
        b.callFunction(foo, withArgs: [i])
        b.callFunction(bar, withArgs: [i])

        let j = b.loadInt(44)
        b.reassign(j, to: b.loadInt(45))
        b.reassign(j, to: b.loadInt(46))
        b.callFunction(foo, withArgs: [j])

        let k = b.loadInt(47)
        b.buildRepeatLoop(n: 10) { i in
            b.reassign(k, to: i)
        }
        b.callFunction(foo, withArgs: [k])

        let l = b.loadInt(48)
        b.reassign(l, to: b.loadInt(49))
        b.callFunction(foo, withArgs: [l, l, l])

        let m = b.loadInt(50)
        b.reassign(m, to: b.loadInt(51))
        var t = b.callFunction(baz)
        t = b.callFunction(bar, withArgs: [m, m, t, m])
        b.callFunction(foo, withArgs: [t])

        // Some operations such as element stores force the lhs to be an identifier, so test that here.
        let n = b.loadInt(52)
        b.reassign(n, to: b.createArray(with: []))
        b.setElement(42, of: n, to: n)

        let o = b.loadInt(53)
        b.buildWhileLoop({ b.reassign(o, to: i); return b.loadBool(false) }) {
        }
        b.callFunction(foo, withArgs: [o])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v3 = 42;
        foo(v3 = 43);
        bar(v3);
        let v7 = 44;
        v7 = 45;
        v7 = 46;
        foo(v7);
        let v11 = 47;
        for (let v12 = 0; v12 < 10; v12++) {
            v11 = v12;
        }
        foo(v11);
        let v14 = 48;
        foo(v14 = 49, v14, v14);
        let v17 = 50;
        foo(bar(v17 = 51, v17, baz(), v17));
        let v22 = 52;
        v22 = [];
        v22[42] = v22;
        let v24 = 53;
        while (v24 = v3, false) {
        }
        foo(v24);

        """

        XCTAssertEqual(actual, expected)
    }

    func testCreateTemplateLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.createTemplateString(from: [""], interpolating: [])
        let bar = b.loadString("bar")
        b.createTemplateString(from: ["foo", "baz"], interpolating: [bar])
        let marker = b.callFunction(b.createNamedVariable(forBuiltin: "getMarker"))
        let space = b.loadString(" ")
        let inner = b.createTemplateString(from: ["Hello", "World"], interpolating: [space])
        let _ = b.createTemplateString(from: ["", "", "", ""], interpolating: [marker, inner, marker] )

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        ``;
        `foo${"bar"}baz`;
        const v4 = getMarker();
        `${v4}${`Hello${" "}World`}${v4}`;

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyAccessLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let o = b.createNamedVariable(forBuiltin: "Obj")
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
        const t1 = [];
        t1[Obj[0][1][2]] = 42;

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
        const v1 = { foo: 42 };
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
        let p = b.createNamedVariable(forBuiltin: "ComputedProperty")
        b.configureComputedProperty(p, of: obj, usingFlags: [.configurable], as: .getter(f1))
        b.configureComputedProperty(p, of: obj, usingFlags: [.enumerable], as: .setter(f2))
        b.configureComputedProperty(p, of: obj, usingFlags: [.writable], as: .getterSetter(f1, f2))
        b.configureComputedProperty(p, of: obj, usingFlags: [], as: .value(num))

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v0 = {};
        let v1 = undefined;
        function f2() {
            return v1;
        }
        function f3(a4) {
            v1 = a4;
        }
        Object.defineProperty(v0, "foo", { configurable: true, enumerable: true, get: f2 });
        Object.defineProperty(v0, "bar", { set: f3 });
        Object.defineProperty(v0, "foobar", { enumerable: true, get: f2, set: f3 });
        Object.defineProperty(v0, "baz", { writable: true, value: 42 });
        Object.defineProperty(v0, 0, { writable: true, get: f2 });
        Object.defineProperty(v0, 1, { writable: true, enumerable: true, set: f3 });
        Object.defineProperty(v0, 2, { writable: true, configurable: true, enumerable: true, get: f2, set: f3 });
        Object.defineProperty(v0, 3, { value: 42 });
        Object.defineProperty(v0, ComputedProperty, { configurable: true, get: f2 });
        Object.defineProperty(v0, ComputedProperty, { enumerable: true, set: f3 });
        Object.defineProperty(v0, ComputedProperty, { writable: true, get: f2, set: f3 });
        Object.defineProperty(v0, ComputedProperty, { value: 42 });

        """

        XCTAssertEqual(actual, expected)
    }

    func testPropertyDeletionLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(1337)
        let s = b.loadString("bar")
        let f = b.loadFloat(13.37)
        var initialProperties = [String: Variable]()
        initialProperties["foo"] = i
        initialProperties["bar"] = f
        let o = b.createObject(with: initialProperties)
        let _ = b.deleteProperty("foo", of: o)
        let _ = b.deleteComputedProperty(s, of: o)
        let a = b.createArray(with: [b.loadInt(301), b.loadInt(4), b.loadInt(68), b.loadInt(22)])
        let _ = b.deleteElement(3, of: a)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v3 = { bar: 13.37, foo: 1337 };
        delete v3.foo;
        delete v3["bar"];
        const t1 = [301,4,68,22];
        delete t1[3];

        """

        XCTAssertEqual(actual, expected)
    }

    func testGuardedPropertyAccessLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let o = b.createNamedVariable(forBuiltin: "o")
        let a = b.getProperty("a", of: o, guard: true)
        b.getProperty("b", of: a, guard: true)
        b.getElement(0, of: o, guard: true)
        b.getComputedProperty(b.loadString("bar"), of: o, guard: true)
        b.deleteProperty("unfoo", of: o, guard: true)
        b.deleteElement(1, of: o, guard: true)
        b.deleteComputedProperty(b.loadString("unbar"), of: o, guard: true)

        // Stores must never use the optional chaining operator on the left-hand side.
        let v = b.loadInt(42)
        let t1 = b.getProperty("t1", of: o, guard: true)
        b.setProperty("foo", of: t1, to: v)
        let t2 = b.getProperty("t2", of: o, guard: true)
        b.setElement(0, of: t2, to: v)
        let t3 = b.getProperty("t3", of: o, guard: true)
        b.setComputedProperty(b.loadString("baz"), of: t3, to: v)

        let program = b.finalize()

        let actual = fuzzer.lifter.lift(program)
        let expected = """
        o?.a?.b;
        o?.[0];
        o?.["bar"];
        delete o?.unfoo;
        delete o?.[1];
        delete o?.["unbar"];
        const t0 = o?.t1;
        t0.foo = 42;
        const t8 = o?.t2;
        t8[0] = 42;
        const t10 = o?.t3;
        t10["baz"] = 42;

        """

        XCTAssertEqual(actual, expected)
    }

    func testGuardedCallLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f1 = b.createNamedVariable(forBuiltin: "f1")
        let f2 = b.createNamedVariable(forBuiltin: "f2")
        b.callFunction(f1, guard: true)
        let v1 = b.callFunction(f2, guard: true)
        let c1 = b.createNamedVariable(forBuiltin: "c1")
        let c2 = b.createNamedVariable(forBuiltin: "c2")
        b.construct(c1, guard: true)
        let v2 = b.construct(c2, guard: true)
        let o = b.createNamedVariable(forBuiltin: "obj")
        b.callMethod("m", on: o, guard: true)
        let v3 = b.callMethod("n", on: o, guard: true)
        b.callComputedMethod(b.loadString("o"), on: o, withArgs: [v1, v2, v3], guard: true)
        let v4 = b.callComputedMethod(b.loadString("p"), on: o, withArgs: [v1, v2, v3], guard: true)
        b.reassign(v3, to: b.loadString("foo"))
        b.reassign(v4, to: b.loadString("bar"))
        b.reassign(v3, to: b.loadString("baz"))

        let program = b.finalize()

        let actual = fuzzer.lifter.lift(program)
        let expected = """
        try { f1(); } catch (e) {}
        let v3;
        try { v3 = f2(); } catch (e) {}
        try { new c1(); } catch (e) {}
        let v7;
        try { v7 = new c2(); } catch (e) {}
        try { obj.m(); } catch (e) {}
        let v10;
        try { v10 = obj.n(); } catch (e) {}
        try { obj["o"](v3, v7, v10); } catch (e) {}
        let v14;
        try { v14 = obj["p"](v3, v7, v10); } catch (e) {}
        v10 = "foo";
        v14 = "bar";
        v10 = "baz";

        """

        XCTAssertEqual(actual, expected)
    }

    func testGuardedMultilineLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let str = b.loadString("foo")
        let _ = b.construct(str, guard: true)

        let program = b.finalize()

        let actual = fuzzer.lifter.lift(program)
        let expected = """
        try {
        const t0 = "foo";
        new t0();
        } catch (e) {}

        """

        XCTAssertEqual(actual, expected)
    }

    func testFunctionCallLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let s = b.loadString("print('Hello World!')")
        var eval = b.createNamedVariable(forBuiltin: "eval")
        b.callFunction(eval, withArgs: [s])
        let this = b.createNamedVariable(forBuiltin: "this")
        eval = b.getProperty("eval", of: this)
        // The property load must not be inlined, otherwise it would not be distinguishable from a method call (like the one following it).
        b.callFunction(eval, withArgs: [s])
        b.callMethod("eval", on: this, withArgs: [s])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        eval("print('Hello World!')");
        const t0 = this.eval;
        t0("print('Hello World!')");
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
        let Array = b.createNamedVariable(forBuiltin: "Array")
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

        let Math = b.createNamedVariable(forBuiltin: "Math")
        let r = b.callMethod("random", on: Math)
        b.callMethod("sin", on: Math, withArgs: [r])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        Math.sin(Math.random());

        """

        XCTAssertEqual(actual, expected)
    }

    func testMethodBindLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.createNamedVariable(forBuiltin: "Math")
        let r = b.callMethod("random", on: Math)
        let bound = b.bindMethod("sin", on: Math)
        b.callFunction(bound, withArgs: [Math, r])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = Math.random();
        let v2 = Function.prototype.call.bind(Math.sin);
        v2(Math, v1);

        """

        XCTAssertEqual(actual, expected)
    }

    func testMethodCallWithSpreadLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.createNamedVariable(forBuiltin: "Math")
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
        let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
        let iterator = b.getProperty("iterator", of: Symbol)
        let r = b.callComputedMethod(iterator, on: s)
        b.callMethod("next", on: r)

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

        let SomeObj = b.createNamedVariable(forBuiltin: "SomeObject")
        let RandomMethod = b.createNamedVariable(forBuiltin: "RandomMethod")
        let randomMethod = b.callFunction(RandomMethod)
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
        let Array = b.createNamedVariable(forBuiltin: "Array")
        b.construct(Array, withArgs: [n1,values,n2], spreading: [false,true,false])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        new Array(13.37, ...[1,2,"Hello","World"], 13.38);

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
                b.callSuperConstructor(withArgs: [])
                b.setSuperProperty("bar", to: b.loadInt(100))
            }
            cls.addInstanceMethod("g", with: .parameters(n: 1)) { params in
                b.updateSuperProperty("bar", with: b.loadInt(1337), using: BinaryOperator.Add)
            }
            cls.addInstanceMethod("h", with: .parameters(n: 0)) { params in
                b.doReturn(b.getSuperProperty("bar"))
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
                super();
                super.bar = 100;
            }
            g(a11) {
                super.bar += 1337;
            }
            h() {
                return super.bar;
            }
        }
        new C6(13.37);

        """

        XCTAssertEqual(actual, expected)
    }

    func testComputedSuperPropertyAccesses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
            }

            cls.addInstanceMethod("f", with: .parameters(n: 1)) { params in
                b.doReturn(b.loadString("foobar"))
            }
        }

        let function = b.buildPlainFunction(with: .parameters(n: 0)) { params in
            b.doReturn(b.loadString("baz"))
        }

        let C = b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
                b.callSuperConstructor(withArgs: []);
                b.setComputedSuperProperty(params[1], to: b.loadInt(100))
            }
            cls.addInstanceMethod("g", with: .parameters(n: 1)) { params in
                let property = b.binary(b.callFunction(function), params[1], with: .Add)
                b.doReturn(b.getComputedSuperProperty(property))
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
        function f6() {
            return "baz";
        }
        class C8 extends C0 {
            constructor(a10) {
                super();
                super[a10] = 100;
            }
            g(a13) {
                return super[f6() + a13];
            }
        }
        new C8(13.37);

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
        const v2 = { bar: 13.37, foo: 42 };
        let {"foo":v3,...v4} = v2;
        let {"foo":v5,"bar":v6,...v7} = v2;
        let {...v8} = v2;
        let {"foo":v9,"bar":v10,} = v2;

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
        b.destruct(v3, selecting: [String](), into: [])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 42;
        let v1 = 13.37;
        let v2 = "Hello";
        const v3 = { bar: v1, foo: v0 };
        ({"foo":v2,...v0} = v3);
        ({"foo":v2,"bar":v0,...v1} = v3);
        ({...v2} = v3);
        ({"foo":v2,"bar":v1,} = v3);
        ({} = v3);

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

    func testNamedVariableLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let print = b.createNamedVariable(forBuiltin: "print")
        let i1 = b.loadInt(42)
        let i2 = b.loadInt(1337)
        let va = b.createNamedVariable("a", declarationMode: .let, initialValue: i1)
        b.callFunction(print, withArgs: [va])
        let vb1 = b.createNamedVariable("b", declarationMode: .none)
        b.callFunction(print, withArgs: [vb1])
        b.createNamedVariable("c", declarationMode: .global, initialValue: i2)
        let vb2 = b.createNamedVariable("b", declarationMode: .var, initialValue: i2)
        b.reassign(vb2, to: i1)
        let vc = b.createNamedVariable("c", declarationMode: .none)
        b.callFunction(print, withArgs: [vc])
        let undefined = b.loadUndefined()
        let vd = b.createNamedVariable("d", declarationMode: .let, initialValue: undefined)
        b.callFunction(print, withArgs: [vd])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let a = 42;
        print(a);
        print(b);
        c = 1337;
        var b = 1337;
        b = 42;
        print(c);
        let d;
        print(d);

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

        b.buildSwitch(on: v2) { swtch in
            swtch.addCase(v3, fallsThrough: false) {
                b.setProperty("bar", of: v1, to: v3)
            }
            swtch.addCase(v4, fallsThrough: false){
                b.setProperty("baz", of: v1, to: v4)
            }
            swtch.addDefaultCase(fallsThrough: true){
                b.setProperty("foo", of: v1, to: v5)
            }
            swtch.addCase(v0, fallsThrough: true) {
                b.setProperty("bla", of: v1, to: v2)
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v1 = { foo: 42 };
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

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let loopVar = b.loadInt(0)
        b.buildWhileLoop({ b.compare(loopVar, with: b.loadInt(100), using: .lessThan) }) {
            b.unary(.PostInc, loopVar)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        while (v0 < 100) {
            v0++;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let shouldContinue = b.createNamedVariable(forBuiltin: "shouldContinue")
        b.buildWhileLoop({ b.callFunction(shouldContinue) }) {

        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        while (shouldContinue()) {
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.createNamedVariable(forBuiltin: "f")
        let g = b.createNamedVariable(forBuiltin: "g")
        let loopVar = b.loadInt(10)
        b.buildWhileLoop({ b.callFunction(f); b.callFunction(g); return loopVar }) {
            b.unary(.PostDec, loopVar)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v2 = 10;
        while (f(), g(), v2) {
            v2--;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting4() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        var f = b.createNamedVariable(forBuiltin: "f")
        var g = b.createNamedVariable(forBuiltin: "g")
        b.buildWhileLoop({ b.callFunction(f); let cond = b.callFunction(g); return cond }) {
        }

        var program = b.finalize()
        var actual = fuzzer.lifter.lift(program)

        var expected = """
        while (f(), g()) {
        }

        """

        XCTAssertEqual(actual, expected)

        f = b.createNamedVariable(forBuiltin: "f")
        g = b.createNamedVariable(forBuiltin: "g")
        b.buildWhileLoop({ let cond = b.callFunction(f); b.callFunction(g); return cond }) {
            b.callFunction(b.createNamedVariable(forBuiltin: "body"))
        }

        program = b.finalize()
        actual = fuzzer.lifter.lift(program)

        expected = """
        while ((() => {
                const v2 = f();
                g();
                return v2;
            })()) {
            body();
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting5() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({
            let foobar = b.createNamedVariable(forBuiltin: "foobar")
            let v = b.callFunction(foobar)
            return b.binary(v, v, with: .Add)
        }) {
            let doLoopBodyStuff = b.createNamedVariable(forBuiltin: "doLoopBodyStuff")
            b.callFunction(doLoopBodyStuff)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        while ((() => {
                const v1 = foobar();
                return v1 + v1;
            })()) {
            doLoopBodyStuff();
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testWhileLoopLifting6() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let print = b.createNamedVariable(forBuiltin: "print")
        let f = b.callFunction(b.createNamedVariable(forBuiltin: "f"))
        let g = b.callFunction(b.createNamedVariable(forBuiltin: "g"))
        let h = b.callFunction(b.createNamedVariable(forBuiltin: "h"))
        b.buildWhileLoop({ b.callFunction(print, withArgs: [f]); return b.loadBool(false) }) {
            b.callFunction(print, withArgs: [g])
        }
        b.callFunction(print, withArgs: [h])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v2 = f();
        const v4 = g();
        const v6 = h();
        while (print(v2), false) {
            print(v4);
        }
        print(v6);

        """

        XCTAssertEqual(actual, expected)
    }

    func testDoWhileLoopLifting1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let loopVar1 = b.loadInt(0)
        b.buildDoWhileLoop(do: {
            let loopVar2 = b.loadInt(0)
            b.buildDoWhileLoop(do: {
                b.unary(.PostInc, loopVar2)
            }, while: { b.callFunction(b.createNamedVariable(forBuiltin: "f"), withArgs: [loopVar2]) })
            b.unary(.PostInc, loopVar1)
        }, while: { b.compare(loopVar1, with: b.loadInt(42), using: .lessThan) })

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = 0;
        do {
            let v1 = 0;
            do {
                v1++;
            } while (f(v1))
            v0++;
        } while (v0 < 42)

        """

        XCTAssertEqual(actual, expected)
    }

    func testDoWhileLoopLifting2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildDoWhileLoop(do: {
            let doSomething = b.createNamedVariable(forBuiltin: "doSomething")
            b.callFunction(doSomething)
        }, while: { b.callFunction(b.createNamedVariable(forBuiltin: "f")); return b.callFunction(b.createNamedVariable(forBuiltin: "g")) })

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        do {
            doSomething();
        } while (f(), g())

        """

        XCTAssertEqual(actual, expected)
    }

    func testDoWhileLoopLifting3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let print = b.createNamedVariable(forBuiltin: "print")
        let f = b.callFunction(b.createNamedVariable(forBuiltin: "f"))
        let g = b.callFunction(b.createNamedVariable(forBuiltin: "g"))
        let h = b.callFunction(b.createNamedVariable(forBuiltin: "h"))
        b.buildDoWhileLoop(do: {
            b.callFunction(print, withArgs: [f])
        }, while: { b.callFunction(print, withArgs: [g]); return b.loadBool(false) })
        b.callFunction(print, withArgs: [h])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v2 = f();
        const v4 = g();
        const v6 = h();
        do {
            print(v2);
        } while (print(v4), false)
        print(v6);

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop(i: { b.loadInt(0) }, { i in b.compare(i, with: b.loadInt(10), using: .lessThan) }, { i in b.unary(.PostInc, i) }) { i in
            b.buildForLoop(i: { b.loadInt(0) }, { j in b.compare(j, with: i, using: .lessThan) }, { j in b.unary(.PostInc, j) }) { j in
                let print = b.createNamedVariable(forBuiltin: "print")
                b.callFunction(print, withArgs: [i, j])
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let i1 = 0; i1 < 10; i1++) {
            for (let i8 = 0; i8 < i1; i8++) {
                print(i1, i8);
            }
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop() {
            b.loopBreak()
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (;;) {
            break;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop({ return [b.callFunction(b.createNamedVariable(forBuiltin: "f1")), b.callFunction(b.createNamedVariable(forBuiltin: "f2"))] },
                       { vars in b.callFunction(b.createNamedVariable(forBuiltin: "f3"), withArgs: [vars[0]]); return b.callFunction(b.createNamedVariable(forBuiltin: "f4"), withArgs: [vars[1]]) },
                       { vars in b.callFunction(b.createNamedVariable(forBuiltin: "f5"), withArgs: [vars[1]]); b.callFunction(b.createNamedVariable(forBuiltin: "f6"), withArgs: [vars[0]]) }) { vars in
            b.callFunction(b.createNamedVariable(forBuiltin: "f7"), withArgs: vars)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let i4 = f1(), i5 = f2(); f3(i4), f4(i5); f5(i5), f6(i4)) {
            f7(i4, i5);
        }

        """
        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting4() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop({ let x = b.callFunction(b.createNamedVariable(forBuiltin: "f")); let y = b.callFunction(b.createNamedVariable(forBuiltin: "g")); b.callFunction(b.createNamedVariable(forBuiltin: "h")); return [x, y] },
                       { vs in return b.compare(vs[0], with: vs[1], using: .lessThan) },
                       { vs in b.reassign(vs[0], to: vs[1], with: .Add) }) { vs in
            b.callFunction(b.createNamedVariable(forBuiltin: "print"), withArgs: vs)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let [i6, i7] = (() => {
                const v1 = f();
                const v3 = g();
                h();
                return [v1, v3];
            })();
            i6 < i7;
            i6 += i7) {
            print(i6, i7);
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting5() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop({ b.callFunction(b.createNamedVariable(forBuiltin: "foo")); b.callFunction(b.createNamedVariable(forBuiltin: "bar")) },
                       {
                            let shouldContinue = b.callFunction(b.createNamedVariable(forBuiltin: "shouldContinue"))
                            b.buildIf(b.callFunction(b.createNamedVariable(forBuiltin: "shouldNotContinue"))) {
                                b.reassign(shouldContinue, to: b.loadBool(false))
                            }
                            return shouldContinue
                       }) {
            b.loopBreak()
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (foo(), bar();
            (() => {
                let v5 = shouldContinue();
                if (shouldNotContinue()) {
                    v5 = false;
                }
                return v5;
            })();
            ) {
            break;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting6() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop(i: { b.loadInt(0) }, { b.compare($0, with: b.loadInt(100), using: .lessThan) }, { b.reassign($0, to: b.loadInt(10), with: .Add) }) { i in
            b.callFunction(b.createNamedVariable(forBuiltin: "print"), withArgs: [i])
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let i1 = 0; i1 < 100; i1 += 10) {
            print(i1);
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting7() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop(i: { b.callFunction(b.createNamedVariable(forBuiltin: "f")); return b.callFunction(b.createNamedVariable(forBuiltin: "g")) }, {_ in b.loadBool(true) }, { _ in }) { i in
            b.loopBreak()
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        for (let i4 = (() => {
                f();
                return g();
            })();
            ;
            ) {
            break;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting8() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildPlainFunction(with: .parameters(n: 3)) { args in
            b.buildForLoop(i: { args[0] }, { i in b.compare(i, with: args[1], using: .greaterThanOrEqual) }, { i in b.reassign(i, to: args[2], with: .Sub)}) { vars in
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0(a1, a2, a3) {
            for (let i4 = a1; i4 >= a2; i4 -= a3) {
            }
        }

        """
        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting9() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let print = b.createNamedVariable(forBuiltin: "print")
        let f = b.callFunction(b.createNamedVariable(forBuiltin: "f"))
        let g = b.callFunction(b.createNamedVariable(forBuiltin: "g"))
        let h = b.callFunction(b.createNamedVariable(forBuiltin: "h"))
        let i = b.callFunction(b.createNamedVariable(forBuiltin: "i"))
        let j = b.callFunction(b.createNamedVariable(forBuiltin: "j"))

        b.buildForLoop({ b.callFunction(print, withArgs: [f]) }, { b.callFunction(print, withArgs: [g]) }, { b.callFunction(print, withArgs: [h]) }) {
            b.callFunction(print, withArgs: [i])
        }
        b.callFunction(print, withArgs: [j])

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        const v2 = f();
        const v4 = g();
        const v6 = h();
        const v8 = i();
        const v10 = j();
        for (print(v2); print(v4); print(v6)) {
            print(v8);
        }
        print(v10);

        """
        XCTAssertEqual(actual, expected)
    }

    func testForLoopLifting10() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            let s = b.loadInt(0)
            // Test that context-dependent operations such as LoadArguments are handled correctly inside loop headers
            b.buildForLoop(i: { b.loadInt(0) }, { i in b.compare(i, with: b.getProperty("length", of: b.loadArguments()), using: .lessThan) }, { i in b.unary(.PostInc, i) }) { i in
                let arg = b.getComputedProperty(i, of: b.loadArguments())
                b.reassign(s, to: arg, with: .Add)
            }
            b.doReturn(s)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0() {
            let v1 = 0;
            for (let i3 = 0; i3 < arguments.length; i3++) {
                v1 += arguments[i3];
            }
            return v1;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testRepeatLoopLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let s = b.loadInt(0)
        b.buildRepeatLoop(n: 1337) { i in
            b.reassign(s, to: i, with: .Add)
        }
        let print = b.createNamedVariable(forBuiltin: "print")
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
        let print = b.createNamedVariable(forBuiltin: "print")
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
        const v1 = { a: 1337 };
        for (let v2 in v1) {
            {
                v2 = 1337;
                {
                    v2 = { a: v1 };
                }
            }
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testSingularOperationLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // If there are multiple singular operations inside the same surrounding block, then
        // all but the first one should be ignored by the lifter.

        b.buildClassDefinition { cls in
            cls.addConstructor(with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setProperty("foo", of: this, to: args[1])
            }

            cls.addConstructor(with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setProperty("bar", of: this, to: args[1])
            }

            cls.addInstanceMethod("baz", with: .parameters(n: 0)) { args in
                let this = args[0]
                b.doReturn(b.getProperty("bar", of: this))
            }
        }

        let p1 = b.createNamedVariable(forBuiltin: "proto1")
        let p2 = b.createNamedVariable(forBuiltin: "proto2")
        let v = b.loadInt(42)

        b.buildObjectLiteral { obj in
            obj.addProperty("foo", as: v)
            obj.setPrototype(to: p1)
            obj.addProperty("bar", as: v)
            obj.setPrototype(to: p2)
            obj.addProperty("baz", as: v)
        }

        let print = b.createNamedVariable(forBuiltin: "print")
        let v2 = b.loadInt(43)
        let v3 = b.loadInt(44)
        b.buildSwitch(on: v) { swtch in
            swtch.addDefaultCase {
                b.callFunction(print, withArgs: [b.loadString("default case 1")])
            }
            swtch.addCase(v2) {
                b.callFunction(print, withArgs: [b.loadString("case 43")])
            }
            swtch.addDefaultCase {
                b.callFunction(print, withArgs: [b.loadString("default case 2")])
            }
            swtch.addCase(v3) {
                b.callFunction(print, withArgs: [b.loadString("case 44")])
            }
            swtch.addDefaultCase {
                b.callFunction(print, withArgs: [b.loadString("default case 3")])
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        class C0 {
            constructor(a2) {
                this.foo = a2;
            }
            baz() {
                return this.bar;
            }
        }
        const v10 = { foo: 42, __proto__: proto1, bar: 42, baz: 42 };
        switch (42) {
            default:
                print("default case 1");
                break;
            case 43:
                print("case 43");
                break;
            case 44:
                print("case 44");
                break;
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testNoAssignmentToThis() {
        // Assigning to |this| (e.g. `this = 42;`) is a syntax error in JavaScript, so we must never produce such code.
        // Instead, in cases where a variable containing |this| is reassigned, we need to create a local variable (e.g.
        // `let v3 = this; ...; v3 = 42;`).
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let this = b.loadThis()
        let v = b.loadInt(42)
        b.reassign(this, to: v)

        b.buildConstructor(with: .parameters(n: 0)) { args in
            b.reassign(args[0], to: v)
        }

        b.buildObjectLiteral { obj in
            obj.addMethod("foo", with: .parameters(n: 0)) { args in
                b.reassign(args[0], to: v)
            }
        }

        b.buildClassDefinition { cls in
            cls.addInstanceMethod("bar", with: .parameters(n: 0)) { args in
                b.reassign(args[0], to: v)
            }
            cls.addStaticGetter(for: "baz") { this in
                b.reassign(this, to: v)
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = this;
        v0 = 42;
        function F2() {
            if (!new.target) { throw 'must be called with new'; }
            let v3 = this;
            v3 = 42;
        }
        const v5 = {
            foo() {
                let v4 = this;
                v4 = 42;
            },
        };
        class C6 {
            bar() {
                let v7 = this;
                v7 = 42;
            }
            static get baz() {
                let v8 = this;
                v8 = 42;
            }
        }

        """

        XCTAssertEqual(actual, expected)
    }

    func testNegativeNumberLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(-42)
        let v1 = b.loadBigInt(-43)
        let v2 = b.loadFloat(-4.4)

        // Negative numbers are technically unary expressions, which makes a difference when performing a negation (otherwise, we'd end up with something like `--42`)
        b.unary(.Minus, v0)
        b.unary(.Minus, v1)
        b.unary(.Minus, v2)

        // For some reason, when performing an exponentiation we also need parenthesis, otherwise "SyntaxError: Unary operator
        // used immediately before exponentiation expression. Parenthesis must be used to disambiguate operator precedence"
        b.binary(v0, v2, with: .Exp)

        // However, in pretty much all other cases we dont want/expect parenthesis since unary expressions have fairly high precedence,
        // and most expressions with higher precendence such as MemberExpressions anyway need special handling for literals.
        b.unary(.BitwiseNot, v0)
        b.binary(v0, v2, with: .Add)
        let v3 = b.loadInt(42)
        b.reassign(v3, to: v0)
        let print = b.createNamedVariable(forBuiltin: "print")
        b.callFunction(print, withArgs: [v0, v1, v2])
        b.getProperty("foo", of: v1)
        b.getProperty("bar", of: v2)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        -(-42);
        -(-43n);
        -(-4.4);
        (-42) ** -4.4;
        ~-42;
        -42 + -4.4;
        let v9 = 42;
        v9 = -42;
        print(-42, -43n, -4.4);
        (-43n).foo;
        (-4.4).bar;

        """

        XCTAssertEqual(actual, expected)
    }

    func testLoadNewTargetLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let variable = b.loadNull()
        b.buildPlainFunction(with: .parameters(n: 0)) { args in
            let t = b.loadNewTarget()
            b.reassign(variable, to: t)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        let v0 = null;
        function f1() {
            v0 = new.target;
        }

        """
        XCTAssertEqual(actual, expected)
    }

    func testLoadDisposableVariableLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(with: .parameters(n: 0)) { args in
            let v1 = b.loadInt(1)
            let v2 = b.loadInt(42)
            let dispose = b.getProperty("dispose", of: b.createNamedVariable(forBuiltin: "Symbol"));
            let disposableVariable = b.buildObjectLiteral { obj in
                obj.addProperty("value", as: v1)
                obj.addComputedMethod(dispose, with: .parameters(n:0)) { args in
                    b.doReturn(v2)
                }
            }
            b.loadDisposableVariable(disposableVariable)
        }
        b.callFunction(f)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        function f0() {
            const v4 = Symbol.dispose;
            const v6 = {
                value: 1,
                [v4]() {
                    return 42;
                },
            };
            using v7 = v6;
        }
        f0();

        """
        XCTAssertEqual(actual, expected)
    }

    func testLoadAsyncDisposableVariableLifting() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildAsyncFunction(with: .parameters(n: 0)) { args in
            let v1 = b.loadInt(1)
            let v2 = b.loadInt(42)
            let asyncDispose = b.getProperty("asyncDispose", of: b.createNamedVariable(forBuiltin: "Symbol"))
            let asyncDisposableVariable = b.buildObjectLiteral { obj in
                obj.addProperty("value", as: v1)
                obj.addComputedMethod(asyncDispose, with: .parameters(n:0)) { args in
                    b.doReturn(v2)
                }
            }
            b.loadAsyncDisposableVariable(asyncDisposableVariable)
        }

        let g = b.buildAsyncFunction(with: .parameters(n: 0)) { args in
            b.await(b.callFunction(f))
        }
        b.callFunction(g)

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)

        let expected = """
        async function f0() {
            const v4 = Symbol.asyncDispose;
            const v6 = {
                value: 1,
                [v4]() {
                    return 42;
                },
            };
            await using v7 = v6;
        }
        async function f8() {
            await f0();
        }
        f8();

        """
        XCTAssertEqual(actual, expected)
    }
}
