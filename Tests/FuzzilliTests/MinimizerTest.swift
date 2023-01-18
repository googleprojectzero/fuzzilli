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

    func testGenericInstructionMinimization() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var n1 = b.loadInt(42)
        let n2 = b.loadInt(43)
        var n3 = b.binary(n1, n1, with: .Add)
        let n4 = b.binary(n2, n2, with: .Add)

        evaluator.nextInstructionIsImportant(in: b)
        b.loadString("foo")
        var bar = b.loadString("bar")
        let baz = b.loadString("baz")

        var o1 = b.createObject(with: [:])
        evaluator.nextInstructionIsImportant(in: b)
        b.storeComputedProperty(n3, as: bar, on: o1)
        let o2 = b.createObject(with: [:])
        b.storeComputedProperty(n4, as: baz, on: o2)

        let originalProgram = b.finalize()

        // Build expected output program.
        n1 = b.loadInt(42)
        n3 = b.binary(n1, n1, with: .Add)
        b.loadString("foo")
        bar = b.loadString("bar")
        o1 = b.createObject(with: [:])
        b.storeComputedProperty(n3, as: bar, on: o1)

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
                let name = b.loadProperty("name", of: this)
                let msg = b.binary(prefix, name, with: .Add)
                evaluator.nextInstructionIsImportant(in: b)
                b.doReturn(msg)
            }
            obj.addGetter(for: "bar") { this in
                b.doReturn(b.loadString("baz"))
            }
        }

        evaluator.nextInstructionIsImportant(in: b)
        b.callMethod("m", on: o, withArgs: [])

        // This object literal can be removed entirely.
        b.buildObjectLiteral { obj in
            obj.addGetter(for: "x") { this in
                b.doReturn(b.loadInt(1337))
            }
            obj.addProperty("y", as: v)
            obj.addMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let x = b.loadProperty("x", of: this)
                let y = b.loadProperty("y", of: this)
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
                let name = b.loadProperty("name", of: this)
                let msg = b.binary(prefix, name, with: .Add)
                b.doReturn(msg)
            }
        }

        b.callMethod("m", on: o, withArgs: [])

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
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
            cls.addInstanceProperty("name", value: s)
            cls.addInstanceProperty("foo")
            cls.addInstanceElement(0)
            cls.addInstanceElement(1)
            evaluator.nextInstructionIsImportant(in: b)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let v = b.loadProperty("name", of: this)
                evaluator.nextInstructionIsImportant(in: b)
                b.doReturn(v)
            }
            cls.addInstanceGetter(for: "bar") { this in
                b.doReturn(b.loadInt(42))
            }
        }

        evaluator.nextInstructionIsImportant(in: b)
        b.construct(class1, withArgs: [])

        // Only the body of a method of this class is important, the class itself should be removed
        let class2 = b.buildClassDefinition(withSuperclass: class1) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { args in
                let this = args[0]
                b.storeProperty(args[1], as: "bar", on: this)
            }
            cls.addInstanceMethod("foo", with: .parameters(n: 0)) { args in
                let importantFunction = b.loadBuiltin("ImportantFunction")
                evaluator.nextInstructionIsImportant(in: b)
                b.callFunction(importantFunction, withArgs: [])
            }
            cls.addStaticMethod("bar", with: .parameters(n: 1)) { args in
                let this = args[0]
                b.storeProperty(args[1], as: "baz", on: this)
            }
            cls.addStaticProperty("baz")
        }
        let unusedInstance = b.construct(class2, withArgs: [])
        b.callMethod("foo", on: unusedInstance, withArgs: [])

        // This class can be removed entirely
        let supercls = b.loadBuiltin("SuperClass")
        let class3 = b.buildClassDefinition(withSuperclass: supercls) { cls in
            cls.addInstanceProperty("x", value: s)
            cls.addInstanceProperty("y")
            cls.addInstanceComputedProperty(s)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let x = b.loadProperty("x", of: this)
                let y = b.loadProperty("y", of: this)
                let r = b.binary(x, y, with: .Add)
                b.doReturn(r)
            }
            cls.addStaticMethod("n", with: .parameters(n: 1)) { args in
                let n = b.loadInt(1337)
                b.doReturn(n)
            }
            cls.addStaticSetter(for: "bar") { this, v in
            }
        }
        b.construct(class3, withArgs: [])

        let originalProgram = b.finalize()

        // Build expected output program.
        s = b.loadString("foobar")
        class1 = b.buildClassDefinition { cls in
            cls.addInstanceProperty("name", value: s)
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let this = args[0]
                let v = b.loadProperty("name", of: this)
                b.doReturn(v)
            }
        }
        b.construct(class1, withArgs: [])
        let importantFunction = b.loadBuiltin("ImportantFunction")
        b.callFunction(importantFunction, withArgs: [])

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
        b.buildSwitch(on: num) { cases in
            cases.add(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            cases.add(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            cases.addDefault(fallsThrough: false) {
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        num = b.loadInt(1337)
        cond3 = b.loadInt(1337)

        b.buildSwitch(on: num) { cases in
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            // The empty default case that will never be removed.
            cases.addDefault(fallsThrough: false) {
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
        b.buildSwitch(on: num) { cases in
            cases.add(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            cases.add(cond2, fallsThrough: false) {
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            cases.addDefault(fallsThrough: false) {
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

        b.buildSwitch(on: num) { cases in
            cases.add(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            // The empty default case that will never be removed.
            cases.addDefault(fallsThrough: false) {
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

        b.buildSwitch(on: num) { cases in
            cases.add(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            cases.add(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                evaluator.nextInstructionIsImportant(in: b)
                b.binary(num, two, with: .Mul)
            }
            cases.addDefault(fallsThrough: false) {
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

        b.buildSwitch(on: num) { cases in
            cases.add(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            cases.add(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            cases.addDefault(fallsThrough: false) {
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

    func testSwitchKeepDefaultCase() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var num = b.loadInt(1337)
        let cond1 = b.loadInt(1339)
        let cond2 = b.loadInt(1338)
        let cond3 = b.loadInt(1337)
        let one = b.loadInt(1)

        evaluator.nextInstructionIsImportant(in: b)
        b.buildSwitch(on: num) { cases in
            cases.add(cond1, fallsThrough: false) {
                b.binary(num, one, with: .Add)
            }
            cases.add(cond2, fallsThrough: false) {
                b.binary(num, one, with: .Sub)
            }
            cases.add(cond3, fallsThrough: false) {
                let two = b.loadInt(2)
                b.binary(num, two, with: .Mul)
            }
            cases.addDefault(fallsThrough: false) {
                let x = b.loadString("foobar")
                b.reassign(num, to: x)
            }
        }

        let originalProgram = b.finalize()

        // Build expected output program.
        num = b.loadInt(1337)
        b.buildSwitch(on: num) { cases in
            cases.addDefault(fallsThrough: false) {
            }
        }

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
            b.storeProperty(v, as: "foo", on: o)
        }
        let k = b.loadString("code")
        b.storeComputedProperty(c, as: k, on: o)
        let eval = b.loadBuiltin("eval")
        b.callFunction(eval, withArgs: [c])
        b.deleteProperty("foo", of: o)

        let originalProgram = b.finalize()

        // Build expected output program.
        v = b.loadInt(42)
        o = b.createObject(with: [:])
        b.storeProperty(v, as: "foo", on: o)

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
        b.storeProperty(r, as: "result", on: o)

        // As we are not emulating the dataflow through the function call in our evaluator, the minimizer will try to remove the binary ops and integer loads
        // as they do not directly flow into the property store. To avoid this, we simply mark all binary ops and integer loads as important in this program.
        evaluator.operationIsImportant(LoadInteger.self)
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
        b.storeProperty(r, as: "result", on: o)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
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
        b.storeProperty(r, as: "result", on: o)

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
        b.storeProperty(r, as: "result", on: o)

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
            let r = b.unary(.PostInc, args[0])
            b.doReturn(r)
        }
        let f2 = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let f3 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.loadString("unused2")
                b.loadArguments()
                let r = b.unary(.PostDec, args[0])
                b.doReturn(r)
            }
            b.loadString("unused3")
            let a1 = b.callFunction(f1, withArgs: [args[0]])
            let a2 = b.callFunction(f3, withArgs: [args[1]])
            let r = b.binary(a1, a2, with: .Add)
            b.doReturn(r)
        }
        var x = b.loadInt(1337)
        var y = b.loadInt(1338)
        var r = b.callFunction(f2, withArgs: [x, y])
        evaluator.nextInstructionIsImportant(in: b)
        b.storeProperty(r, as: "result", on: o)

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
        b.storeProperty(r, as: "result", on: o)

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
        b.storeProperty(n4, as: "n4", on: o)        // This will store n1, i.e. 42
        var c = b.loadBool(true)
        b.buildIfElse(c, ifBody: {
            let n5 = b.loadInt(46)
            b.reassign(n1, to: n5)
            b.storeProperty(n1, as: "n1", on: o)        // This will store n5, i.e. 46
            b.storeProperty(n1, as: "n1", on: o)        // This will (again) store n5, i.e. 46
            b.reassign(n1, to: n2)
            b.storeProperty(n1, as: "n1", on: o)        // This will store n2, i.e. 43
        }, elseBody: {
            let n6 = b.loadInt(47)
            b.reassign(n1, to: n6)
            b.storeProperty(n3, as: "n3", on: o)        // This will still store n3, i.e. 42
        })
        b.storeProperty(n1, as: "n1", on: o)        // This will store n1, i.e. 42
        b.reassign(n1, to: n2)
        b.storeProperty(n3, as: "n3", on: o)        // This will store n3, i.e. 42

        evaluator.operationIsImportant(Reassign.self)

        let originalProgram = b.finalize()

        // Keep all property stores and the if-else
        evaluator.operationIsImportant(StoreProperty.self)
        evaluator.operationIsImportant(BeginIf.self)

        // Build expected output program.
        o = b.createObject(with: [:])
        n1 = b.loadInt(42)
        n2 = b.loadInt(43)
        n3 = b.loadInt(44)
        b.reassign(n3, to: n1)
        n4 = b.loadInt(45)
        b.reassign(n4, to: n3)
        b.storeProperty(n1, as: "n4", on: o)
        c = b.loadBool(true)
        b.buildIfElse(c, ifBody: {
            let n5 = b.loadInt(46)
            b.reassign(n1, to: n5)
            b.storeProperty(n5, as: "n1", on: o)
            b.storeProperty(n5, as: "n1", on: o) 
            b.reassign(n1, to: n2)
            b.storeProperty(n2, as: "n1", on: o)
        }, elseBody: {
            let n6 = b.loadInt(47)
            b.reassign(n1, to: n6)
            b.storeProperty(n3, as: "n3", on: o)
        })
        evaluator.nextInstructionIsImportant(in: b)
        b.storeProperty(n1, as: "n1", on: o)
        b.reassign(n1, to: n2)
        evaluator.nextInstructionIsImportant(in: b)
        b.storeProperty(n3, as: "n3", on: o)

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
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
        var o = b.loadBuiltin("TheObject")
        let vars = b.destruct(o, selecting: ["foo", "bar", "baz"])
        var print = b.loadBuiltin("print")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [vars[1]])

        let originalProgram = b.finalize()

        // Build expected output program.
        o = b.loadBuiltin("TheObject")
        let bar = b.loadProperty("bar", of: o)
        print = b.loadBuiltin("print")
        b.callFunction(print, withArgs: [bar])

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
    }

    func testDestructuringSimplification2() {
        let evaluator = EvaluatorForMinimizationTests()
        let fuzzer = makeMockFuzzer(evaluator: evaluator)
        let b = fuzzer.makeBuilder()

        // Build input program to be minimized.
        var o = b.loadBuiltin("TheArray")
        let vars = b.destruct(o, selecting: [0, 3, 4])
        var print = b.loadBuiltin("print")
        evaluator.nextInstructionIsImportant(in: b)
        b.callFunction(print, withArgs: [vars[2]])

        let originalProgram = b.finalize()

        // Build expected output program.
        o = b.loadBuiltin("TheArray")
        let bar = b.loadElement(4, of: o)
        print = b.loadBuiltin("print")
        b.callFunction(print, withArgs: [bar])

        let expectedProgram = b.finalize()

        // Perform minimization and check that the two programs are equal.
        let actualProgram = minimize(originalProgram, with: fuzzer)
        XCTAssertEqual(expectedProgram, actualProgram)
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

        func operationIsImportant<T: Fuzzilli.Operation>(_ op: T.Type) {
            importantOperations.insert(T.name)
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
            fuzzer.events.PreExecute.addListener { program in
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
    func minimize(_ program: Program, with fuzzer: Fuzzer) -> Program {
        guard let evaluator = fuzzer.evaluator as? EvaluatorForMinimizationTests else { fatalError("Invalid Evaluator used for minimization tests: \(fuzzer.evaluator)") }
        evaluator.setOriginalProgram(program)
        let dummyAspects = ProgramAspects(outcome: .succeeded)
        return fuzzer.minimizer.minimize(program, withAspects: dummyAspects)
    }
}
