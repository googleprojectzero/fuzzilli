// Copyright 2022 Google LLC
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

class MinimizerTests: XCTestCase {

    func testMinimizationLimit() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.build(n: 70)

            let preMinimization = b.finalize()
            let limit = 0.1

            let result = minimize(preMinimization, with: fuzzer, limit: limit)
            XCTAssert(result.size >= Int(Double(preMinimization.size) * limit))
        }
    }

    func testGenericInstructionMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var n1 = b.loadInt(42)
        let n2 = b.loadInt(43)
        // This will be removed and n3 replaced by n1 (an input of this instruction)
        let n3 = b.binary(n1, n1, with: .Add)
        let n4 = b.binary(n2, n2, with: .Add)

        evaluator.nextInstructionIsImportant(in: b)
        b.loadString("foo")
        var bar = b.loadString("bar")
        let baz = b.loadString("baz")

        var o1 = b.createObject(with: [:])
        evaluator.nextInstructionIsImportant(in: b)
        b.setComputedProperty(bar, of: o1, to: n3)
        let o2 = b.createObject(with: [:])
        b.setComputedProperty(baz, of: o2, to: n4)

        let originalProgram = b.finalize()

        // Build expected output program.
        n1 = b.loadInt(42)
        b.loadString("foo")
        bar = b.loadString("bar")
        o1 = b.createObject(with: [:])
        b.setComputedProperty(bar, of: o1, to: n1)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testObjectLiteralMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let v = b.loadInt(42)
        var n = b.loadString("MyObject")
        // This object literal is important, but not all of its fields.
        var o = b.buildObjectLiteral { obj in
            evaluator.nextInstructionIsImportant(in: b)
            obj.addProperty("name", as: n)
            obj.addProperty("foo", as: v)
            evaluator.nextInstructionIsImportant(in: b)
            obj.addMethod("m", with: .parameters(n: 1)) { args in
                let this = args[0]
                let prefix = b.loadString("Hello World from ")
                evaluator.nextInstructionIsImportant(in: b)
                let name = b.getProperty("name", of: this)
                evaluator.nextInstructionIsImportant(in: b)
                let msg = b.binary(prefix, name, with: .Add)
                evaluator.nextInstructionIsImportant(in: b)
                b.doReturn(msg)
            }
            obj.addGetter(for: "bar") { this in
                b.doReturn(b.loadString("baz"))
            }
        }

        evaluator.nextInstructionIsImportant(in: b)
        b.callMethod("m", on: o)

        // This object literal can be removed entirely.
        b.buildObjectLiteral { obj in
            obj.addGetter(for: "x") { this in
                b.doReturn(b.loadInt(1337))
            }
            obj.addProperty("y", as: v)
            obj.addMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let x = b.getProperty("x", of: this)
                let y = b.getProperty("y", of: this)
                let r = b.binary(x, y, with: .Add)
                b.doReturn(r)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        n = b.loadString("MyObject")
        o = b.buildObjectLiteral { obj in
            obj.addProperty("name", as: n)
            obj.addMethod("m", with: .parameters(n: 1)) { args in
                let this = args[0]
                let prefix = b.loadString("Hello World from ")
                let name = b.getProperty("name", of: this)
                let msg = b.binary(prefix, name, with: .Add)
                b.doReturn(msg)
            }
        }

        b.callMethod("m", on: o)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testFunctionSimplification() {
        // We prefer plain functions over complex functions because they behave in a
        // more straight-forward way (e.g. return value doesn't become a Promise).

        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let async = b.buildAsyncFunction(with: .parameters(n: 0)) { args in }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(async)

        let generator = b.buildGeneratorFunction(with: .parameters(n: 0)) { args in }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(generator)

        let asyncGenerator = b.buildAsyncGeneratorFunction(with: .parameters(n: 0)) { args in }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(asyncGenerator)

        let originalProgram = b.finalize()

        // Build expected output program.
        let f1 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        b.callFunction(f1)

        let f2 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        b.callFunction(f2)

        let f3 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        b.callFunction(f3)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        // Post-processing can insert return statements or function parameters, so skip that.
        let actualProgram = minimize(originalProgram, with: fuzzer, performPostprocessing: false)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testFunctionNameRemoval() {
        // We prefer functions with "flexible" names (automatically assigned during lifting)
        // as there's no risk of name collisions during mutations with those.

        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let foo = b.buildPlainFunction(with: .parameters(n: 0), named: "foo") { args in }
        let bar = b.buildGeneratorFunction(with: .parameters(n: 0), named: "bar") { args in }
        let baz = b.buildAsyncFunction(with: .parameters(n: 0), named: "baz") { args in }
        let bla = b.buildAsyncGeneratorFunction(with: .parameters(n: 0), named: "bla") { args in }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(foo)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(bar)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(baz)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(bla)

        let originalProgram = b.finalize()

        // Build expected output program.
        // See test above for why the different function types also become plain functions.
        let f1 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        let f2 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        let f3 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        let f4 = b.buildPlainFunction(with: .parameters(n: 0)) { args in }
        b.callFunction(f1)
        b.callFunction(f2)
        b.callFunction(f3)
        b.callFunction(f4)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        // Post-processing can insert return statements or function parameters, so skip that.
        let actualProgram = minimize(originalProgram, with: fuzzer, performPostprocessing: false)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testClassDefinitionMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var s = b.loadString("foobar")
        // This class is important, but not all of its fields
        var class1 = b.buildClassDefinition { cls in
            evaluator.nextInstructionIsImportant(in: b)
            cls.addPrivateInstanceProperty("name", value: s)
            cls.addInstanceProperty("foo")
            cls.addInstanceElement(0)
            cls.addInstanceElement(1)
            evaluator.nextInstructionIsImportant(in: b)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                evaluator.nextInstructionIsImportant(in: b)
                let v = b.getPrivateProperty("name", of: this)
                evaluator.nextInstructionIsImportant(in: b)
                b.doReturn(v)
            }
            cls.addInstanceGetter(for: "bar") { this in
                b.doReturn(b.loadInt(42))
            }
        }

        evaluator.nextInstructionIsImportant(in: b)
        b.construct(class1)

        // Only the body of a method of this class is important, the class itself should be removed
        let class2 = b.buildClassDefinition(withSuperclass: class1) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setProperty("bar", of: this, to: args[1])
            }
            cls.addInstanceMethod("foo", with: .parameters(n: 0)) { args in
                let importantFunction = b.createNamedVariable(forBuiltin: "ImportantFunction")
                evaluator.nextInstructionIsImportant(in: b)
                b.callFunction(importantFunction)
            }
            cls.addStaticMethod("bar", with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setProperty("baz", of: this, to: args[1])
            }
            cls.addStaticProperty("baz")
        }
        let unusedInstance = b.construct(class2)
        b.callMethod("foo", on: unusedInstance)

        // This class can be removed entirely
        let supercls = b.createNamedVariable(forBuiltin: "SuperClass")
        let class3 = b.buildClassDefinition(withSuperclass: supercls) { cls in
            cls.addInstanceProperty("x", value: s)
            cls.addInstanceProperty("y")
            cls.addInstanceComputedProperty(s)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let x = b.getProperty("x", of: this)
                let y = b.getProperty("y", of: this)
                let r = b.binary(x, y, with: .Add)
                b.doReturn(r)
            }
            cls.addStaticMethod("n", with: .parameters(n: 1)) { args in
                let n = b.loadInt(1337)
                b.doReturn(n)
            }
            cls.addStaticSetter(for: "bar") { this, v in
            }
            cls.addPrivateStaticProperty("bla")
            cls.addPrivateStaticMethod("m", with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setPrivateProperty("bla", of: this, to: args[1])
            }
        }
        b.construct(class3)

        let originalProgram = b.finalize()

        // Build expected output program.
        s = b.loadString("foobar")
        class1 = b.buildClassDefinition { cls in
            cls.addPrivateInstanceProperty("name", value: s)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let v = b.getPrivateProperty("name", of: this)
                b.doReturn(v)
            }
        }
        b.construct(class1)
        let importantFunction = b.createNamedVariable(forBuiltin: "ImportantFunction")
        b.callFunction(importantFunction)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testSwitchCaseMinimization1() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var num = b.loadInt(1337)
        let cond1 = b.loadInt(1339)
        let cond2 = b.loadInt(1338)
        var cond3 = b.loadInt(1337)
        let one = b.loadInt(1)

        evaluator.nextInstructionIsImportant(in: b)
        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            swtch.addCase(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            swtch.addDefaultCase(fallsThrough: false) {
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        num = b.loadInt(1337)
        cond3 = b.loadInt(1337)

        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
        }

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testSwitchCaseMinimization2() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var num = b.loadInt(1337)
        let cond1 = b.loadInt(1339)
        var cond2 = b.loadInt(1338)
        var cond3 = b.loadInt(1337)
        var one = b.loadInt(1)

        evaluator.nextInstructionIsImportant(in: b)
        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            swtch.addCase(cond2, fallsThrough: false) {
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, one, with: .Sub)
            }
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            swtch.addDefaultCase(fallsThrough: false) {
                evaluator.nextInstructionIsImportant(in: b)
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        num = b.loadInt(1337)
        cond2 = b.loadInt(1338)
        cond3 = b.loadInt(1337)
        one = b.loadInt(1)

        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            swtch.addDefaultCase(fallsThrough: false) {
                let _ = b.loadString("foobar")
            }
        }

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testSwitchRemovalKeepContent() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var num = b.loadInt(1337)
        let cond1 = b.loadInt(1339)
        let cond2 = b.loadInt(1338)
        let cond3 = b.loadInt(1337)
        let one = b.loadInt(1)

        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            swtch.addCase(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            swtch.addDefaultCase(fallsThrough: false) {
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        num = b.loadInt(1337)
        let two = b.loadInt(2)
        b.binary(num, two, with: .Mul)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testSwitchRemoval() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let num = b.loadInt(1337)
        evaluator.nextInstructionIsImportant(in: b)
        var cond1 = b.loadInt(1339)
        let cond2 = b.loadInt(1338)
        let cond3 = b.loadInt(1337)
        let one = b.loadInt(1)

        b.buildSwitch(on: num) { swtch in
            swtch.addCase(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            swtch.addCase(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            swtch.addCase(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            swtch.addDefaultCase(fallsThrough: false) {
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        cond1 = b.loadInt(1339)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testCodeStringMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var v = b.loadInt(42)
        var o = b.createObject(with: [:])
        let c = b.buildCodeString {
            evaluator.nextInstructionIsImportant(in: b)
            b.setProperty("foo", of: o, to: v)
        }
        let k = b.loadString("code")
        b.setComputedProperty(k, of: o, to: c)
        let eval = b.createNamedVariable(forBuiltin: "eval")
        b.callFunction(eval, withArgs: [c])
        b.deleteProperty("foo", of: o)

        let originalProgram = b.finalize()

        // Build expected output program.
        v = b.loadInt(42)
        o = b.createObject(with: [:])
        b.setProperty("foo", of: o, to: v)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testBasicInlining() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.createObject(with: [:])
        var m = b.loadInt(42)
        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let t = b.binary(m, args[0], with: .Mul)
            let r = b.binary(t, args[1], with: .Add)
            b.doReturn(r)
        }
        var x = b.loadInt(1337)
        var y = b.loadInt(1338)
        var r = b.callFunction(f, withArgs: [x, y])
        evaluator.nextInstructionIsImportant(in: b)
        b.setProperty("result", of: o, to: r)

        // Make sure to keep the binary operations.
        evaluator.operationIsImportant(BinaryOperation.self)
        // We also need to keep the return instruction as long as the function still exists. However, once the function has been inlined, the return should also disappear.
        evaluator.keepReturnsInFunctions = true

        let originalProgram = b.finalize()

        // Build expected output program.
        o = b.createObject(with: [:])
        m = b.loadInt(42)
        x = b.loadInt(1337)
        y = b.loadInt(1338)
        let t = b.binary(m, x, with: .Mul)
        r = b.binary(t, y, with: .Add)
        b.setProperty("result", of: o, to: r)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(FuzzILLifter().lift(expectedProgram), FuzzILLifter().lift(actualProgram))
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testInliningWithConditionalReturn() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        b.loadString("unused")
        let f = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(args[1])
            }, elseBody: {
                b.doReturn(args[2])
            })
        }
        var a1 = b.loadBool(true)
        var a2 = b.loadInt(1337)
        var r = b.callFunction(f, withArgs: [a1, a2])
        var o = b.createObject(with: [:])
        evaluator.nextInstructionIsImportant(in: b)
        b.setProperty("result", of: o, to: r)

        let originalProgram = b.finalize()

        // Need to keep various things alive, see also the comment in testBasicInlining
        evaluator.operationIsImportant(LoadInteger.self)
        evaluator.operationIsImportant(LoadBoolean.self)
        evaluator.operationIsImportant(BeginIf.self)
        evaluator.operationIsImportant(Reassign.self)
        evaluator.keepReturnsInFunctions = true

        // Build expected output program.
        a1 = b.loadBool(true)
        a2 = b.loadInt(1337)
        let u = b.loadUndefined()
        r = b.loadUndefined()
        b.buildIfElse(a1, ifBody: {
            b.reassign(r, to: a2)
        }, elseBody: {
            b.reassign(r, to: u)
        })
        o = b.createObject(with: [:])
        b.setProperty("result", of: o, to: r)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testMultiInlining() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.createObject(with: [:])
        let f1 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.loadString("unused1")
            evaluator.nextInstructionIsImportant(in: b)
            let r = b.unary(.PostInc, args[0])
            b.doReturn(r)
        }
        let f2 = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let f3 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.loadString("unused2")
                b.loadArguments()
                evaluator.nextInstructionIsImportant(in: b)
                let r = b.unary(.PostDec, args[0])
                b.doReturn(r)
            }
            b.loadString("unused3")
            let a1 = b.callFunction(f1, withArgs: [args[0]])
            let a2 = b.callFunction(f3, withArgs: [args[1]])
            evaluator.nextInstructionIsImportant(in: b)
            let r = b.binary(a1, a2, with: .Add)
            b.doReturn(r)
        }
        var x = b.loadInt(1337)
        var y = b.loadInt(1338)
        var r = b.callFunction(f2, withArgs: [x, y])
        evaluator.nextInstructionIsImportant(in: b)
        b.setProperty("result", of: o, to: r)

        let originalProgram = b.finalize()

        // Need to keep various things alive, see also the comment in testBasicInlining
        evaluator.operationIsImportant(LoadInteger.self)
        evaluator.keepReturnsInFunctions = true

        // Build expected output program.
        o = b.createObject(with: [:])
        x = b.loadInt(1337)
        y = b.loadInt(1338)
        let t1 = b.unary(.PostInc, x)
        let t2 = b.unary(.PostDec, y)
        r = b.binary(t1, t2, with: .Add)
        b.setProperty("result", of: o, to: r)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testReassignmentReduction() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.createObject(with: [:])
        var n1 = b.loadInt(42)
        var n2 = b.loadInt(43)
        var n3 = b.loadInt(44)
        b.reassign(n3, to: n1)
        var n4 = b.loadInt(45)
        b.reassign(n4, to: n3)
        b.setProperty("n4", of: o, to: n4)        // This will store n1, i.e. 42
        var c = b.loadBool(true)
        b.buildIfElse(c, ifBody: {
            let n5 = b.loadInt(46)
            b.reassign(n1, to: n5)
            b.setProperty("n1", of: o, to: n1)        // This will store n5, i.e. 46
            b.setProperty("n1", of: o, to: n1)        // This will (again) store n5, i.e. 46
            b.reassign(n1, to: n2)
            b.setProperty("n1", of: o, to: n1)        // This will store n2, i.e. 43
        }, elseBody: {
            let n6 = b.loadInt(47)
            b.reassign(n1, to: n6)
            b.setProperty( "n3", of: o, to: n3)        // This will still store n3, i.e. 42
        })
        b.setProperty("n1", of: o, to: n1)        // This will store n1, i.e. 42
        b.reassign(n1, to: n2)
        b.setProperty("n3", of: o, to: n3)        // This will store n3, i.e. 42

        evaluator.operationIsImportant(Reassign.self)

        let originalProgram = b.finalize()

        // Keep all property stores and the if-else
        evaluator.operationIsImportant(SetProperty.self)
        evaluator.operationIsImportant(BeginIf.self)

        // Build expected output program.
        o = b.createObject(with: [:])
        n1 = b.loadInt(42)
        n2 = b.loadInt(43)
        n3 = b.loadInt(44)
        b.reassign(n3, to: n1)
        n4 = b.loadInt(45)
        b.reassign(n4, to: n3)
        b.setProperty("n4", of: o, to: n1)
        c = b.loadBool(true)
        b.buildIfElse(c, ifBody: {
            let n5 = b.loadInt(46)
            b.reassign(n1, to: n5)
            b.setProperty("n1", of: o, to: n5)
            b.setProperty("n1", of: o, to: n5)
            b.reassign(n1, to: n2)
            b.setProperty("n1", of: o, to: n2)
        }, elseBody: {
            let n6 = b.loadInt(47)
            b.reassign(n1, to: n6)
            b.setProperty("n3", of: o, to: n3)
        })
        evaluator.nextInstructionIsImportant(in: b)
        b.setProperty("n1", of: o, to: n1)
        b.reassign(n1, to: n2)
        evaluator.nextInstructionIsImportant(in: b)
        b.setProperty("n3", of: o, to: n3)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testNamedVariableRemoval() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var print = b.createNamedVariable(forBuiltin: "print")
        var v1 = b.loadInt(42)
        let n1 = b.createNamedVariable("n1", declarationMode: .var, initialValue: v1)
        // These uses of n1 can be replaced with v1
        evaluator.nextInstructionIsImportant(in: b)
        var s1 = b.binary(n1, n1, with: .Add)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [s1])

        // Similar situation, but now the original input is also reused.
        var v2 = b.loadInt(43)
        let n2 = b.createNamedVariable("n2", declarationMode: .var, initialValue: v2)
        evaluator.nextInstructionIsImportant(in: b)
        var s2 = b.binary(n2, v2, with: .Add)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [s2])

        // Now the named variable itself is important and so shouldn't be removed.
        evaluator.nextInstructionIsImportant(in: b)
        var n3 = b.createNamedVariable("n3", declarationMode: .var, initialValue: n2)
        // ... but this instruction can be removed (and s4 replaced with n3)
        let s4 = b.binary(n3, n3, with: .Add)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [n3, s4, n3])

        // This named variable can again be removed though.
        let n4 = b.createNamedVariable("n4", declarationMode: .var, initialValue: n3)
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [n1, n2, n3, n4])

        let originalProgram = b.finalize()

        // Build expected output program.
        print = b.createNamedVariable(forBuiltin: "print")
        v1 = b.loadInt(42)
        s1 = b.binary(v1, v1, with: .Add)
        b.callFunction(print, withArgs: [s1])
        v2 = b.loadInt(43)
        s2 = b.binary(v2, v2, with: .Add)
        b.callFunction(print, withArgs: [s2])
        n3 = b.createNamedVariable("n3", declarationMode: .var, initialValue: v2)
        b.callFunction(print, withArgs: [n3, n3, n3])
        b.callFunction(print, withArgs: [v1, v2, n3, n3])

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testSimpleLoopMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let f = b.createNamedVariable(forBuiltin: "f")
        let maxIterations = b.loadInt(10)
        let loopVar = b.loadInt(0)
        b.buildWhileLoop({ b.callFunction(f) }) {
            b.unary(.PostInc, loopVar)
            let foo = b.createNamedVariable(forBuiltin: "foo")
            evaluator.nextInstructionIsImportant(in: b)
            b.callMethod("bar", on: foo)
            let cond = b.compare(loopVar, with: maxIterations, using: .lessThan)
            b.buildIf(cond) {
                b.loopBreak()
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        let foo = b.createNamedVariable(forBuiltin: "foo")
        b.callMethod("bar", on: foo)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testNestedLoopMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let numIterations = b.loadInt(10)
        let loopVar = b.loadInt(0)
        b.buildWhileLoop({ b.compare(loopVar, with: numIterations, using: .lessThan) }) {
            b.unary(.PostInc, loopVar)
            evaluator.nextInstructionIsImportant(in: b)         // Otherwise, the minimizer will attempt to simplify the while-loop into a repeat-loop
            b.buildWhileLoop({ b.loadBool(true) }) {
                evaluator.nextInstructionIsImportant(in: b)
                b.loopBreak()
            }
            let f = b.createNamedVariable(forBuiltin: "importantFunction")
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(f)
            b.loopContinue()
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        b.buildWhileLoop({ b.loadBool(true) }) {
            b.loopBreak()
        }
        let f = b.createNamedVariable(forBuiltin: "importantFunction")
        b.callFunction(f)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testForLoopSimplification1() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var d = b.createNamedVariable(forBuiltin: "d")
        var e = b.createNamedVariable(forBuiltin: "e")
        var f = b.createNamedVariable(forBuiltin: "f")
        var g = b.createNamedVariable(forBuiltin: "g")
        var h = b.createNamedVariable(forBuiltin: "h")
        b.buildForLoop(i: { evaluator.nextInstructionIsImportant(in: b); return b.callFunction(d) },
                       { i in evaluator.nextInstructionIsImportant(in: b); b.callFunction(e); return b.compare(i, with: b.loadInt(100), using: .lessThan) },
                       { i in evaluator.nextInstructionIsImportant(in: b); b.callFunction(f); b.unary(.PostInc, i) }) { i in
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(g, withArgs: [i])
        }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(h)

        let originalProgram = b.finalize()

        // Build expected output program.
        d = b.createNamedVariable(forBuiltin: "d")
        e = b.createNamedVariable(forBuiltin: "e")
        f = b.createNamedVariable(forBuiltin: "f")
        g = b.createNamedVariable(forBuiltin: "g")
        h = b.createNamedVariable(forBuiltin: "h")
        b.callFunction(d)
        b.buildRepeatLoop(n: 5) { i in
            b.callFunction(e)
            b.callFunction(g, withArgs: [i])
            b.callFunction(f)
        }
        b.callFunction(h)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testForLoopSimplification2() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var d = b.createNamedVariable(forBuiltin: "d")
        let e = b.createNamedVariable(forBuiltin: "e")
        let f = b.createNamedVariable(forBuiltin: "f")
        var g = b.createNamedVariable(forBuiltin: "g")
        var h = b.createNamedVariable(forBuiltin: "h")
        var limit = b.loadInt(100)
        // In this case, the for-loop is actually important (we emulate that by marking the EndForLoopAfterthought instruction as important
        b.buildForLoop(i: { evaluator.nextInstructionIsImportant(in: b); return b.callFunction(d) },
                       { i in b.callFunction(e); evaluator.nextInstructionIsImportant(in: b); return b.compare(i, with: limit, using: .lessThan) },
                       { i in b.callFunction(f); evaluator.nextInstructionIsImportant(in: b); b.unary(.PostInc, i); evaluator.nextInstructionIsImportant(in: b) }) { i in
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(g, withArgs: [i])
        }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(h)

        let originalProgram = b.finalize()

        // Build expected output program.
        d = b.createNamedVariable(forBuiltin: "d")
        g = b.createNamedVariable(forBuiltin: "g")
        h = b.createNamedVariable(forBuiltin: "h")
        limit = b.loadInt(100)
        b.buildForLoop(i: { return b.callFunction(d) },
                       { i in b.compare(i, with: limit, using: .lessThan) },
                       { i in b.unary(.PostInc, i) }) { i in
            b.callFunction(g, withArgs: [i])
        }
        b.callFunction(h)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testWhileLoopSimplification() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var f = b.createNamedVariable(forBuiltin: "f")
        var g = b.createNamedVariable(forBuiltin: "g")
        var h = b.createNamedVariable(forBuiltin: "h")
        var loopVar = b.loadInt(10)
        b.buildWhileLoop({ evaluator.nextInstructionIsImportant(in: b); b.callFunction(f); evaluator.nextInstructionIsImportant(in: b); return b.unary(.PostDec, loopVar) }) {
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(g, withArgs: [loopVar])

            evaluator.nextInstructionIsImportant(in: b)
            // The Continue operation is necessary here so that the loop isn't simply deleted.
            b.loopContinue()
        }
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(h)

        let originalProgram = b.finalize()

        // Build expected output program.
        f = b.createNamedVariable(forBuiltin: "f")
        g = b.createNamedVariable(forBuiltin: "g")
        h = b.createNamedVariable(forBuiltin: "h")
        loopVar = b.loadInt(10)
        b.buildRepeatLoop(n: 5) {
            b.callFunction(f)
            b.unary(.PostDec, loopVar)
            b.callFunction(g, withArgs: [loopVar])
            b.loopContinue()
        }
        b.callFunction(h)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testDoWhileLoopSimplification() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var f = b.createNamedVariable(forBuiltin: "f")
        var g = b.createNamedVariable(forBuiltin: "g")
        var h = b.createNamedVariable(forBuiltin: "h")
        var loopVar = b.loadInt(10)
        b.buildDoWhileLoop(do: {
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(f, withArgs: [loopVar])

            evaluator.nextInstructionIsImportant(in: b)
            // The Continue operation is necessary here so that the loop isn't simply deleted.
            b.loopContinue()
        }, while: { evaluator.nextInstructionIsImportant(in: b); b.callFunction(g); return b.unary(.PostDec, loopVar) })
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(h)

        let originalProgram = b.finalize()

        // Build expected output program.
        f = b.createNamedVariable(forBuiltin: "f")
        g = b.createNamedVariable(forBuiltin: "g")
        h = b.createNamedVariable(forBuiltin: "h")
        loopVar = b.loadInt(10)
        b.buildRepeatLoop(n: 5) {
            b.callFunction(f, withArgs: [loopVar])
            b.loopContinue()
            b.callFunction(g)
        }
        b.callFunction(h)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testRepeatLoopReduction() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        b.buildRepeatLoop(n: 100) { i in
            let foo = b.createNamedVariable(forBuiltin: "foo")
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(foo, withArgs: [i])

            evaluator.nextInstructionIsImportant(in: b)
            // Due to the `continue` the loop must be kept, but the number of iterations can be decreased.
            b.loopContinue()
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        // Five is currently the smallest iteration count tried by the LoopReducer.
        b.buildRepeatLoop(n: 5) { i in
            let foo = b.createNamedVariable(forBuiltin: "foo")
            b.callFunction(foo, withArgs: [i])
            b.loopContinue()
        }

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testNestedLoopMerging1() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        b.buildRepeatLoop(n: 2) {
            b.buildRepeatLoop(n: 2) { i in
                let foo = b.createNamedVariable(forBuiltin: "foo")
                // The inner loop can't be deleted due to the data-flow dependency.
                evaluator.nextInstructionIsImportant(in: b)
                b.callFunction(foo, withArgs: [i])
            }

            // These instruction isn't needed and will be removed, allowing the loops to be merged.
            let unimportant = b.createNamedVariable(forBuiltin: "unimportant")
            b.callFunction(unimportant)

            // Small hack: we force the outer loop to be kept by keeping the EndRepeatLoop instruction (which the loop merging won't change).
            evaluator.nextInstructionIsImportant(in: b)
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        b.buildRepeatLoop(n: 4) { i in
            let foo = b.createNamedVariable(forBuiltin: "foo")
            b.callFunction(foo, withArgs: [i])
        }

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testNestedLoopMerging2() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        b.buildRepeatLoop(n: 2) { i in
            // These instruction isn't needed and will be removed, allowing the loops to be merged.
            let unimportant = b.createNamedVariable(forBuiltin: "unimportant")
            b.callFunction(unimportant)

            b.buildRepeatLoop(n: 2) { j in
                let foo = b.createNamedVariable(forBuiltin: "foo")
                evaluator.nextInstructionIsImportant(in: b)
                b.callFunction(foo, withArgs: [i, j])
            }

            // Small hack: we force the outer loop to be kept by keeping the EndRepeatLoop instruction (which the loop merging won't change).
            evaluator.nextInstructionIsImportant(in: b)
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        b.buildRepeatLoop(n: 4) { i in
            let foo = b.createNamedVariable(forBuiltin: "foo")
            b.callFunction(foo, withArgs: [i, i])
        }

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testNestedLoopMerging3() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        b.buildRepeatLoop(n: 2) {
            // In this case, the loops cannot be merged since there is code in between them.
            let important = b.createNamedVariable(forBuiltin: "important")
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(important)

            b.buildRepeatLoop(n: 2) { i in
                let foo = b.createNamedVariable(forBuiltin: "foo")
                evaluator.nextInstructionIsImportant(in: b)
                b.callFunction(foo, withArgs: [i])
            }

            // Small hack: we force the outer loop to be kept by keeping the EndRepeatLoop instruction (which the loop merging won't change).
            evaluator.nextInstructionIsImportant(in: b)
        }

        let originalProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(originalProgram, actualProgram)
    }

    func testTryCatchRemoval() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var i = b.loadInt(42)
        evaluator.nextInstructionIsImportant(in: b)
        var a = b.createArray(with: [i, i, i])
        var f = b.loadFloat(13.37)
        b.buildTryCatchFinally(tryBody: {
            evaluator.nextInstructionIsImportant(in: b)
            b.callMethod("fill", on: a, withArgs: [f])
        }, catchBody: { _ in })

        let originalProgram = b.finalize()

        // Build expected output program.
        i = b.loadInt(42)
        a = b.createArray(with: [i, i, i])
        f = b.loadFloat(13.37)
        b.callMethod("fill", on: a, withArgs: [f])

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testDestructuringSimplification1() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.createNamedVariable(forBuiltin: "TheObject")
        let vars = b.destruct(o, selecting: ["foo", "bar", "baz"])
        var print = b.createNamedVariable(forBuiltin: "print")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [vars[0], vars[1], vars[2]])

        let originalProgram = b.finalize()

        // Build expected output program.
        o = b.createNamedVariable(forBuiltin: "TheObject")
        let foo = b.getProperty("foo", of: o)
        let bar = b.getProperty("bar", of: o)
        let baz = b.getProperty("baz", of: o)
        print = b.createNamedVariable(forBuiltin: "print")
        b.callFunction(print, withArgs: [foo, bar, baz])

        let expectedProgram = b.finalize()

        // Here we rely on a quirk of the minimization evaluator: it only ensures that the sum
        // of all important operations doesn't decrease, and so this will allow the DestructObject
        // to be converted into GetProperty operations but prevent both the DestructObject and the
        // GetProperty from being removed entirely.
        evaluator.operationIsImportant(DestructObject.self)
        evaluator.operationIsImportant(GetProperty.self)

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testDestructuringSimplification2() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.createNamedVariable(forBuiltin: "TheArray")
        let vars = b.destruct(o, selecting: [0, 3, 4])
        var print = b.createNamedVariable(forBuiltin: "print")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [vars[0], vars[1], vars[2]])

        let originalProgram = b.finalize()

        // Build expected output program.
        o = b.createNamedVariable(forBuiltin: "TheArray")
        let val0 = b.getElement(0, of: o)
        let val3 = b.getElement(3, of: o)
        let val4 = b.getElement(4, of: o)
        print = b.createNamedVariable(forBuiltin: "print")
        b.callFunction(print, withArgs: [val0, val3, val4])

        let expectedProgram = b.finalize()

        // Here we rely on a quirk of the minimization evaluator: it only ensures that the sum
        // of all important operations doesn't decrease, and so this will allow the DestructArray
        // to be converted into GetElement operations but prevent both the DestructArray and the
        // GetElement from being removed entirely.
        evaluator.operationIsImportant(DestructArray.self)
        evaluator.operationIsImportant(GetElement.self)

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testVariableDeduplication() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var foo = b.createNamedVariable(forBuiltin: "foo")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(foo)
        let foo2 = b.createNamedVariable(forBuiltin: "foo")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(foo2)
        var bar = b.createNamedVariable(forBuiltin: "bar")
        evaluator.nextInstructionIsImportant(in: b)
        var cond = b.callFunction(bar)
        evaluator.nextInstructionIsImportant(in: b)
        b.buildIf(cond) {
            let baz = b.createNamedVariable(forBuiltin: "baz")
            evaluator.nextInstructionIsImportant(in: b)
            b.callFunction(baz)
        }
        var baz = b.createNamedVariable(forBuiltin: "baz")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(baz)

        let originalProgram = b.finalize()

        // Build expected output program.
        foo = b.createNamedVariable(forBuiltin: "foo")
        b.callFunction(foo)
        b.callFunction(foo)
        bar = b.createNamedVariable(forBuiltin: "bar")
        cond = b.callFunction(bar)
        b.buildIf(cond) {
            let baz = b.createNamedVariable(forBuiltin: "baz")
            b.callFunction(baz)
        }
        baz = b.createNamedVariable(forBuiltin: "baz")
        b.callFunction(baz)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testGuardedOperationSimplification() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        let o = b.createNamedVariable(forBuiltin: "o")
        let f = b.createNamedVariable(forBuiltin: "f")
        b.getProperty("p1", of: o, guard: true)
        b.getElement(2, of: o, guard: true)
        b.getComputedProperty(b.loadString("p3"), of: o, guard: true)
        b.callFunction(f, guard: true)
        b.callMethod("m", on: o, guard: true)

        // Make sure that none of the operations are removed.
        evaluator.operationsAreImportant([GetProperty.self, GetElement.self, GetComputedProperty.self, CallFunction.self, CallMethod.self])

        let originalProgram = b.finalize()

        // Perform minimization.
        // We then expect to have the same types of operations, but no guarded ones.
        let minimizedProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(originalProgram.size, minimizedProgram.size)

        let numGuardableOperationsBefore = originalProgram.code.filter({ $0.op is GuardableOperation }).count
        let numGuardableOperationsAfter = minimizedProgram.code.filter({ $0.op is GuardableOperation }).count
        XCTAssertEqual(numGuardableOperationsBefore, numGuardableOperationsAfter)

        let operationTypesBefore = originalProgram.code.map({ $0.op.name })
        let operationTypesAfter = minimizedProgram.code.map({ $0.op.name })
        XCTAssertEqual(operationTypesBefore, operationTypesAfter)

        let numGuardedOperationsBefore = originalProgram.code.filter({ $0.isGuarded }).count
        let numGuardedOperationsAfter = minimizedProgram.code.filter({ $0.isGuarded }).count
        XCTAssertEqual(numGuardedOperationsBefore, 5)
        XCTAssertEqual(numGuardedOperationsAfter, 0)
    }

    func testWasmCatchAllMinimization() throws {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        do {
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                    evaluator.nextInstructionIsImportant(in: b)
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                        evaluator.nextInstructionIsImportant(in: b)
                        let val = function.consti64(42)
                        evaluator.nextInstructionIsImportant(in: b)
                        function.wasmReturn(val)
                    } catchAllBody: { label in
                        function.wasmReturn(function.consti64(-1))
                    }
                    evaluator.nextInstructionIsImportant(in: b)
                    function.wasmUnreachable()
                }
            }

            evaluator.nextInstructionIsImportant(in: b)
            let exports = module.loadExports()
            evaluator.nextInstructionIsImportant(in: b)
            b.callMethod(module.getExportedMethod(at: 0), on: exports)
        }
        let originalProgram = b.finalize()

        // Build expected output program.
        do {
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                    function.wasmBuildLegacyTry(with: [] => .nothing, args: []) { label, _ in
                        function.wasmReturn(function.consti64(42))
                    // TODO(mliedtke): The catchAllBody should be removed!
                    // TODO(mliedtke): Also add a test for catch blocks and support reduction of them.
                    } catchAllBody: { label in
                    }
                    function.wasmUnreachable()
                }
            }

            let exports = module.loadExports()
            b.callMethod(module.getExportedMethod(at: 0), on: exports)
        }
        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram,
            "Expected:\n\(FuzzILLifter().lift(expectedProgram.code))\n\n" +
            "Actual:\n\(FuzzILLifter().lift(actualProgram.code))")
    }

    func testWasmDataflowMinimization() throws {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        do {
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                    evaluator.nextInstructionIsImportant(in: b)
                    let val = function.consti64(42)
                    // We would expect this to be removed by the DataflowSimplifier
                    let absVal = function.wasmi64UnOp(val, unOpKind: .Clz)
                    evaluator.nextInstructionIsImportant(in: b)
                    function.wasmReturn(absVal)
                }
                wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                    evaluator.nextInstructionIsImportant(in: b)
                    let valA = function.consti64(42)
                    let valB = function.consti64(43)
                    // We cannot remove this with the DataflowSimplifier as the input types don't match the output type.
                    let testVal = function.wasmi64CompareOp(valA, valB, using: .Eq)
                    evaluator.nextInstructionIsImportant(in: b)
                    function.wasmReturn(testVal)
                }
            }

            evaluator.nextInstructionIsImportant(in: b)
            let exports = module.loadExports()
            evaluator.nextInstructionIsImportant(in: b)
            b.callMethod(module.getExportedMethod(at: 0), on: exports)
        }
        let originalProgram = b.finalize()

        // Build expected output program.
        do {
            let module = b.buildWasmModule { wasmModule in
                wasmModule.addWasmFunction(with: [] => .wasmi64) { function, _ in
                    function.wasmReturn(function.consti64(42))
                }
                wasmModule.addWasmFunction(with: [] => .wasmi32) { function, _ in
                    let valA = function.consti64(42)
                    let valB = function.consti64(43)
                    let testVal = function.wasmi64CompareOp(valA, valB, using: .Eq)
                    function.wasmReturn(testVal)
                }
            }

            let exports = module.loadExports()
            b.callMethod(module.getExportedMethod(at: 0), on: exports)
        }
        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram,
            "Expected:\n\(FuzzILLifter().lift(expectedProgram.code))\n\n" +
            "Actual:\n\(FuzzILLifter().lift(actualProgram.code))")

    }

    // A mock evaluator that can be configured to treat selected instructions as important, causing them to not be minimized away.
    class EvaluatorForMinimizationTests: ProgramEvaluator {
        /// An abstract instruction used to identify the instructions that are important and should be kept.
        /// An abstract instruction contains the FuzzIL operation together with the number of inputs and outputs, but not the concrete variables as those will change during minimization.
        /// The operations of an AbstractInstruction are compared using their identity. This prevents any modifications to those operations by the minimizer.
        struct AbstractInstruction: Hashable {
            let op: Fuzzilli.Operation
            let numInouts: Int

            init(from concreteInstruction: Fuzzilli.Instruction) {
                self.op = concreteInstruction.op
                self.numInouts = concreteInstruction.numInouts
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(ObjectIdentifier(op))
                hasher.combine(numInouts)
            }

            static func == (lhs: AbstractInstruction, rhs: AbstractInstruction) -> Bool {
                return lhs.op === rhs.op && lhs.numInouts == rhs.numInouts
            }
        }

        /// The (abstract) instructions that are important and must not be removed.
        var importantInstructions = Set<AbstractInstruction>()

        /// The initial indices of the important instructions. Set through nextInstructionIsImportant during program building.
        var initialIndicesOfTheImportantInstructions = [Int]()

        /// In addition to the important instructions, we can also mark certain types of operations as important, preventing them from being modified.
        /// The evaluator only verifies that the sum of all important operations does not decrease. Otherwise, any form of instruction reordering, in particular inlining, would be prevented.
        var importantOperations = Set<String>()

        /// For testing inlining, it may be necessary to force return instructions to be kept as long as the surrounding function still exists. Setting this flag achieves this.
        var keepReturnsInFunctions = false

        /// The program currently being evaluated.
        var currentProgram = Program()

        /// The reference program against which reductions are performed.
        /// At the start, this is the original program. After a successful reduction, it is replaced by the current program.
        var referenceProgram = Program()

        func nextInstructionIsImportant(in b: ProgramBuilder) {
            initialIndicesOfTheImportantInstructions.append(b.indexOfNextInstruction())
        }

        func operationIsImportant(_ op: Fuzzilli.Operation.Type) {
            importantOperations.insert(op.name)
        }

        func operationsAreImportant(_ ops: [Fuzzilli.Operation.Type]) {
            for op in ops {
                operationIsImportant(op)
            }
        }

        func setOriginalProgram(_ program: Program) {
            referenceProgram = program

            // Extract the important instructions from the original program.
            for idx in initialIndicesOfTheImportantInstructions {
                let concreteInstr = program.code[idx]
                let abstractInstr = AbstractInstruction(from: concreteInstr)
                assert(!importantInstructions.contains(abstractInstr))
                importantInstructions.insert(abstractInstr)
            }
        }

        func evaluate(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
            // Check if any important instructions were removed, and if yes return false.

            var numImportantOperationsBefore = 0, numImportantOperationsAfter = 0
            var numReturnsBefore = 0, numReturnsAfter = 0
            var numFunctionsBefore = 0, numFunctionsAfter = 0
            var numImportantInstructionsBefore = importantInstructions.count, numImportantInstructionsAfter = 0

            for instr in referenceProgram.code {
                if instr.op is BeginAnyFunction {
                    numFunctionsBefore += 1
                } else if instr.op is Return {
                    numReturnsBefore += 1
                }

                if importantOperations.contains(instr.op.name) {
                    numImportantOperationsBefore += 1
                }
            }

            for instr in currentProgram.code {
                let abstractInstr = AbstractInstruction(from: instr)
                if importantInstructions.contains(abstractInstr) {
                    numImportantInstructionsAfter += 1
                }

                if instr.op is BeginAnyFunction {
                    numFunctionsAfter += 1
                } else if instr.op is Return {
                    numReturnsAfter += 1
                }

                if importantOperations.contains(instr.op.name) {
                    numImportantOperationsAfter += 1
                }
            }

            if numImportantInstructionsBefore != numImportantInstructionsAfter {
                return false
            }

            if numImportantOperationsBefore > numImportantOperationsAfter {
                return false
            }

            // When keepReturnsInFunctions is set, returns may only be removed if at least one function is also removed (e.g. by inlining)
            if keepReturnsInFunctions && numReturnsBefore > numReturnsAfter && numFunctionsBefore == numFunctionsAfter {
                return false
            }

            // The reduction was valid, so the current program now becomes the reference program.
            referenceProgram = currentProgram
            return true
        }

        var currentScore: Double {
            return 13.37
        }

        func initialize(with fuzzer: Fuzzer) {
            fuzzer.events.PreExecute.addListener { (program, _) in
                self.currentProgram = program
            }
        }

        var isInitialized: Bool {
            return true
        }

        func exportState() -> Data {
            return Data()
        }

        func importState(_ state: Data) {}

        func computeAspectIntersection(of program: Program, with aspects: ProgramAspects) -> ProgramAspects? {
            return nil
        }

        func resetState() {}
    }

    // Helper function to perform the minimization.
    func minimize(_ program: Program, with fuzzer: Fuzzer, limit: Double = 0.0, performPostprocessing: Bool = true) -> Program {
        guard let evaluator = fuzzer.evaluator as? EvaluatorForMinimizationTests else { fatalError("Invalid Evaluator used for minimization tests: \(fuzzer.evaluator)") }
        evaluator.setOriginalProgram(program)
        let dummyAspects = ProgramAspects(outcome: .succeeded)
        return fuzzer.minimizer.minimize(program, withAspects: dummyAspects, limit: limit, performPostprocessing: performPostprocessing)
    }
}
