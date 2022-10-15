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

    func testSwitchCaseMinimizationA() {
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

    func testSwitchCaseMinimizationB() {
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
            b.doReturn(value: r)
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
                b.doReturn(value: args[1])
            }, elseBody: {
                b.doReturn(value: args[2])
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
            b.doReturn(value: r)
        }
        let f2 = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let f3 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.loadString("unused2")
                b.loadArguments()
                let r = b.unary(.PostDec, args[0])
                b.doReturn(value: r)
            }
            b.loadString("unused3")
            let a1 = b.callFunction(f1, withArgs: [args[0]])
            let a2 = b.callFunction(f3, withArgs: [args[1]])
            let r = b.binary(a1, a2, with: .Add)
            b.doReturn(value: r)
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

    // A mock evaluator that can be configured to treat selected instructions as important, causing them to not be minimized away.
    class EvaluatorForMinimizationTests: ProgramEvaluator {
        /// The instructions that are important and must not be removed.
        var importantInstructions = Set<Int>()

        /// In addition to the important instructions, we can also mark certain types of operations as important, preventing them from being modified.
        /// The evaluator only verifies that the sum of all important operations does not decrease. Otherwise, any form of instruction reordering, in particular inlining, would be prevented.
        var importantOperations = Set<String>()

        /// For testing inlining, it may be necessary to force return instructions to be kept as long as the surrounding function still exists. Setting this flag achieves this.
        var keepReturnsInFunctions = false
        /// Similarly, it may be necessary to keep reassign instructions as they will not be kept alive through data-flow dependencies. Setting this flag achieves this.
        var keepReassignments = false

        /// The program currently being evaluated.
        var currentProgram = Program()

        /// The reference program against which reductions are performed.
        /// At the start, this is the original program. After a successful reduction, it is replaced by the current program.
        var referenceProgram = Program()

        func nextInstructionIsImportant(in b: ProgramBuilder) {
            importantInstructions.insert(b.indexOfNextInstruction())
        }

        func operationIsImportant<T: Fuzzilli.Operation>(_ op: T.Type) {
            importantOperations.insert(T.name)
        }

        func setOriginalProgram(_ program: Program) {
            self.referenceProgram = program
        }

        func evaluate(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
            return nil
        }

        func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
            // Check if any important instructions were removed, and if yes return false.
            // We only need to check for Nop here since the minimizers replace instructions with Nops first, and only "really" delete them at the end of minimization.
            // Also check that the number of important operations doesn't change. We only check that the number stays constant to allow reordering of instructions (e.g. during inlining).
            var numImportantOperationsBefore = 0, numImportantOperationsAfter = 0
            var numReturnsBefore = 0, numReturnsAfter = 0
            var numFunctionsBefore = 0, numFunctionsAfter = 0

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
                if importantInstructions.contains(instr.index) && instr.op is Nop {
                    return false
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
                // The program size must not change during minimization
                assert(self.referenceProgram.size == self.currentProgram.size)
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

    // Helper function to performt the minimization.
    func minimize(_ program: Program, with fuzzer: Fuzzer) -> Program {
        guard let evaluator = fuzzer.evaluator as? EvaluatorForMinimizationTests else { fatalError("Invalid Evaluator used for minimization tests: \(fuzzer.evaluator)") }
        evaluator.setOriginalProgram(program)
        let dummyAspects = ProgramAspects(outcome: .succeeded)
        return fuzzer.minimizer.minimize(program, withAspects: dummyAspects)
    }
}

extension MinimizerTests {
    static var allTests : [(String, (MinimizerTests) -> () throws -> Void)] {
        return [
            ("testGenericInstructionMinimization", testGenericInstructionMinimization),
            ("testSwitchCaseMinimizationA", testSwitchCaseMinimizationA),
            ("testSwitchCaseMinimizationB", testSwitchCaseMinimizationB),
            ("testSwitchRemovalKeepContent", testSwitchRemovalKeepContent),
            ("testSwitchRemoval", testSwitchRemoval),
            ("testSwitchKeepDefaultCase", testSwitchKeepDefaultCase),
            ("testCodeStringMinimization", testCodeStringMinimization),
            ("testBasicInlining", testBasicInlining),
            ("testInliningWithConditionalReturn", testInliningWithConditionalReturn),
            ("testMultiInlining", testMultiInlining),
            ("testReassignmentReduction", testReassignmentReduction),
        ]
    }
}
