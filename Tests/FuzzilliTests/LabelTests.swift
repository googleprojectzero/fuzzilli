import XCTest

@testable import Fuzzilli

class LabelTests: XCTestCase {
    func testWhileLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let loopVar = b.loadInt(0)
        b.buildWhileLoop({
            return b.compare(loopVar, with: b.loadInt(10), using: .lessThan)
        }) { label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)
            b.unary(.PostInc, loopVar)
            b.loopBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            let v0 = 0;
            L3: while (v0 < 10) {
                v0++;
                break L3;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testDoWhileLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildDoWhileLoop(
            do: { label in
                XCTAssertEqual(b.type(of: label), .jsLoopLabel)
                b.loopBreak(label)
            },
            while: {
                return b.loadBool(false)
            })

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L0: do {
                break L0;
            } while (false)

            """
        XCTAssertEqual(actual, expected)
    }

    func testForLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop(
            i: { b.loadInt(0) }, { i in b.loadBool(true) }, { i in },
            { i, label in
                XCTAssertEqual(b.type(of: label), .jsLoopLabel)
                b.loopBreak(label)
            })

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L5: for (let i1 = 0;;) {
                break L5;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testForInLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let obj = b.createObject(with: [:])
        b.buildForInOfLoop(obj, type: .forIn, isAsync: false, header: .simple) { vars, label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)
            b.loopBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L2: for (const v1 in {}) {
                break L2;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testForOfLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let obj = b.createArray(with: [])
        b.buildForInOfLoop(obj, type: .forOf, isAsync: false, header: .simple) { vars, label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)
            b.loopBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L2: for (const v1 of []) {
                break L2;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testRepeatLoopLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildRepeatLoop(n: 10) { i, label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)
            b.loopBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L1: for (let v0 = 0; v0 < 10; v0++) {
                break L1;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testAllNestedLoopsLabels() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) { whileLabel in
            b.loopContinue(whileLabel)
            b.loopBreak(whileLabel)

            b.buildForLoop(
                i: { b.loadInt(0) }, { i in b.loadBool(true) }, { i in },
                { i, forLabel in
                    b.loopContinue(whileLabel)
                    b.loopBreak(forLabel)

                    let obj = b.createObject(with: [:])
                    b.buildForInOfLoop(obj, type: .forIn, isAsync: false, header: .simple) {
                        vars, forInLabel in
                        b.loopContinue(forInLabel)
                        b.loopBreak(forLabel)

                        b.buildDoWhileLoop(
                            do: { doWhileLabel in
                                b.loopContinue(whileLabel)
                                b.loopBreak(doWhileLabel)

                                let arr = b.createArray(with: [])
                                b.buildForInOfLoop(
                                    arr, type: .forOf, isAsync: false, header: .simple
                                ) { vars, forOfLabel in
                                    b.loopContinue(forOfLabel)
                                    b.loopBreak(forInLabel)

                                    b.buildRepeatLoop(n: 10) { i, repeatLabel in
                                        b.loopContinue(whileLabel)
                                        b.loopBreak(repeatLabel)
                                    }
                                }
                            }, while: { b.loadBool(false) })
                    }
                })
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L1: while (true) {
                continue L1;
                break L1;
                L7: for (let i3 = 0;;) {
                    continue L1;
                    break L7;
                    L10: for (const v9 in {}) {
                        continue L10;
                        break L7;
                        L11: do {
                            continue L1;
                            break L11;
                            L14: for (const v13 of []) {
                                continue L14;
                                break L10;
                                L16: for (let v15 = 0; v15 < 10; v15++) {
                                    continue L1;
                                    break L16;
                                }
                            }
                        } while (false)
                    }
                }
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testAllNestedLoopsNoLabels() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) {
            b.buildForLoop(
                i: { b.loadInt(0) }, { i in b.loadBool(true) }, { i in },
                { i in
                    let obj = b.createObject(with: [:])
                    b.buildForInOfLoop(obj, type: .forIn, isAsync: false, header: .simple) {
                        vars, _ in
                        b.buildDoWhileLoop(
                            do: {
                                let arr = b.createArray(with: [])
                                b.buildForInOfLoop(
                                    arr, type: .forOf, isAsync: false, header: .simple
                                ) { vars, _ in
                                    b.buildRepeatLoop(n: 10) { i in
                                        b.loadInt(42)
                                    }
                                }
                            }, while: { b.loadBool(false) })
                    }
                })
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            while (true) {
                for (let i3 = 0;;) {
                    for (const v9 in {}) {
                        do {
                            for (const v13 of []) {
                                for (let v15 = 0; v15 < 10; v15++) {
                                }
                            }
                        } while (false)
                    }
                }
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testBlockStatementLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildBlockStatement { label in
            XCTAssertEqual(b.type(of: label), .jsBlockLabel)
            b.blockBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L0: {
                break L0;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testNestedBlockStatementLabels() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildBlockStatement { label1 in
            b.buildBlockStatement { label2 in
                b.blockBreak(label1)
                b.blockBreak(label2)
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L0: {
                L1: {
                    break L0;
                    break L1;
                }
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testIfStatementLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let cond = b.loadBool(true)
        b.buildIf(cond) { label in
            XCTAssertEqual(b.type(of: label), .jsBlockLabel)
            b.blockBreak(label)
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L1: if (true) {
                break L1;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testIfElseStatementLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let cond = b.loadBool(true)
        b.buildIfElse(
            cond,
            ifBody: { label in
                XCTAssertEqual(b.type(of: label), .jsBlockLabel)
                b.blockBreak(label)
            },
            elseBody: { label in
                XCTAssertEqual(b.type(of: label), .jsBlockLabel)
                b.blockBreak(label)
            })

        let program = b.finalize()

        let fuzzilLifter = FuzzILLifter()
        let fuzzil = fuzzilLifter.lift(program)
        let expectedFuzzil = """
            v0 <- LoadBoolean 'true'
            BeginIf v0 -> v1
                BlockBreak v1
            BeginElse -> v2
                BlockBreak v2
            EndIf

            """
        XCTAssertEqual(fuzzil, expectedFuzzil)

        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L1: if (true) {
                break L1;
            } else {
                break L1;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testNestedIfElseStatementLabels() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let cond1 = b.loadBool(true)
        let cond2 = b.loadBool(false)
        b.buildIfElse(
            cond1,
            ifBody: { label1If in
                b.buildIfElse(
                    cond2,
                    ifBody: { label2If in
                        b.blockBreak(label1If)
                        b.blockBreak(label2If)
                    },
                    elseBody: { label2Else in
                        b.blockBreak(label1If)
                        b.blockBreak(label2Else)
                    })
            },
            elseBody: { label1Else in
                b.blockBreak(label1Else)
            })

        let program = b.finalize()

        let fuzzilLifter = FuzzILLifter()
        let fuzzil = fuzzilLifter.lift(program)
        let expectedFuzzil = """
            v0 <- LoadBoolean 'true'
            v1 <- LoadBoolean 'false'
            BeginIf v0 -> v2
                BeginIf v1 -> v3
                    BlockBreak v2
                    BlockBreak v3
                BeginElse -> v4
                    BlockBreak v2
                    BlockBreak v4
                EndIf
            BeginElse -> v5
                BlockBreak v5
            EndIf

            """
        XCTAssertEqual(fuzzil, expectedFuzzil)

        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L2: if (true) {
                L3: if (false) {
                    break L2;
                    break L3;
                } else {
                    break L2;
                    break L3;
                }
            } else {
                break L2;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testLabelVisibilityInFunctions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) { label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)

            // The label should NOT be visible here if we are inside a function
            b.buildPlainFunction(with: .parameters(n: 0)) { args in
                let visibleLabels = b.visibleVariables.filter {
                    b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
                }
                XCTAssertTrue(visibleLabels.isEmpty)
            }

            // But it should be visible again here
            let visibleLabels = b.visibleVariables.filter {
                b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
            }
            XCTAssertTrue(visibleLabels.contains(label))
        }
    }

    func testLabelVisibilityInClasses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) { label in
            XCTAssertEqual(b.type(of: label), .jsLoopLabel)

            // The label should NOT be visible here if we are inside a class definition
            b.buildClassDefinition { cls in
                let visibleLabels = b.visibleVariables.filter {
                    b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
                }
                XCTAssertTrue(visibleLabels.isEmpty)
            }

            // But it should be visible again here
            let visibleLabels = b.visibleVariables.filter {
                b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
            }
            XCTAssertTrue(visibleLabels.contains(label))
        }
    }

    func testLabelVisibilityInObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) { label in
            // Labels should NOT be visible inside an object literal
            b.buildObjectLiteral { obj in
                let visibleLabels = b.visibleVariables.filter {
                    b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
                }
                XCTAssertTrue(visibleLabels.isEmpty)
            }
        }
    }

    func testLabelVisibilityAcrossSwitches() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWhileLoop({ b.loadBool(true) }) { label in
            // Labels SHOULD be visible inside a switch
            let cond = b.loadInt(42)
            b.buildSwitch(on: cond) { sw in
                sw.addDefaultCase {
                    let visibleLabels = b.visibleVariables.filter {
                        b.type(of: $0).Is(.jsLoopLabel | .jsBlockLabel)
                    }
                    XCTAssertTrue(visibleLabels.contains(label))
                }
            }
        }
    }

    func testSwitchNoLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let case1 = b.loadInt(1)
        b.buildSwitch(on: v) { sw in
            sw.addCase(case1, fallsThrough: true) {
                b.switchBreak()
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            switch (42) {
                case 1:
                    break;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testSwitchLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let case1 = b.loadInt(1)
        b.buildSwitch(on: v) { sw, label in
            XCTAssertEqual(b.type(of: label), .jsBlockLabel)
            sw.addCase(case1, fallsThrough: true) {
                b.blockBreak(label)
            }
            sw.addDefaultCase(fallsThrough: true) {
                b.blockBreak(label)
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L2: switch (42) {
                case 1:
                    break L2;
                default:
                    break L2;
            }

            """
        XCTAssertEqual(actual, expected)
    }

    func testNestedSwitchLabel() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.loadInt(1)
        let v2 = b.loadInt(2)
        let case1 = b.loadInt(1)
        let case2 = b.loadInt(2)
        b.buildSwitch(on: v1) { sw1, label1 in
            sw1.addCase(case1, fallsThrough: true) {
                b.buildSwitch(on: v2) { sw2, label2 in
                    sw2.addCase(case2, fallsThrough: true) {
                        b.blockBreak(label1)
                    }
                }
            }
        }

        let program = b.finalize()
        let actual = fuzzer.lifter.lift(program)
        let expected = """
            L4: switch (1) {
                case 1:
                    switch (2) {
                        case 2:
                            break L4;
                    }
            }

            """
        XCTAssertEqual(actual, expected)
    }
}
