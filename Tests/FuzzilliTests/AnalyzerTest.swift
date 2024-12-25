// Copyright 2020 Google LLC
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

class AnalyzerTests: XCTestCase {

    func testContextAnalyzer() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            var contextAnalyzer = ContextAnalyzer()

            for instr in program.code {
                contextAnalyzer.analyze(instr)
            }

            XCTAssertEqual(contextAnalyzer.context, .javascript)
        }
    }

    func testObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        let v = b.loadInt(42)
        b.buildObjectLiteral { obj in
            XCTAssertEqual(b.context, .objectLiteral)
            obj.addProperty("foo", as: v)
            XCTAssertEqual(b.context, .objectLiteral)
            obj.addMethod("bar", with: .parameters(n: 0)) { args in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method])
            }
            XCTAssertEqual(b.context, .objectLiteral)
            obj.addGetter(for: "baz") { this in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method])
            }
            XCTAssertEqual(b.context, .objectLiteral)
            obj.addSetter(for: "baz") { this, v in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method])
            }
            XCTAssertEqual(b.context, .objectLiteral)
        }
        XCTAssertEqual(b.context, .javascript)
    }

    func testNestedLoops() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)

        let _ = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            XCTAssertEqual(b.context, [.javascript, .subroutine])
            let loopVar = b.loadInt(0)
            b.buildWhileLoop({
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                return b.compare(loopVar, with: b.loadInt(10), using: .lessThan)

            }) {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                b.buildPlainFunction(with: .parameters(n: 2)) { args in
                    XCTAssertEqual(b.context, [.javascript, .subroutine])
                    b.buildRepeatLoop(n: 10) { _ in
                        XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                    }
                }
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                b.unary(.PostInc, loopVar)
            }
        }

        let _ = b.finalize()
    }

    func testNestedFunctions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        b.buildAsyncFunction(with: .parameters(n: 2)) { _ in
            XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction])
            let v3 = b.loadInt(0)
            b.buildPlainFunction(with: .parameters(n: 3)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }
            XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction])
            b.await(v3)
            b.buildAsyncGeneratorFunction(with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction, .generatorFunction])
            }
            XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction])
        }

        let _ = b.finalize()
    }

    func testNestedWithStatements() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        let obj = b.loadString("HelloWorld")
        b.buildWith(obj) {
            XCTAssertEqual(b.context, [.javascript, .with])
            b.buildPlainFunction(with: .parameters(n: 3)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                b.buildWith(obj) {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .with])
                }
            }
            XCTAssertEqual(b.context, [.javascript, .with])
            b.createNamedVariable(b.randomPropertyName(), declarationMode: .none)
        }

        let _ = b.finalize()
    }

    func testClassDefinitions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        let superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
                b.buildDoWhileLoop(do: {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod, .loop])
                }, while: { b.loadBool(false) })
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
        }
        XCTAssertEqual(b.context, .javascript)

        b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
                let v0 = b.loadInt(42)
                let v1 = b.createObject(with: ["foo": v0])
                b.callSuperConstructor(withArgs: [v1])
            }
            cls.addInstanceMethod("m", with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
                b.buildAsyncFunction(with: .parameters(n: 2)) { _ in
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction])
                }
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addStaticMethod("m", with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }

            cls.addInstanceGetter(for: "foo") { this in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addInstanceSetter(for: "foo") { this, v in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addStaticGetter(for: "foo") { this in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addStaticSetter(for: "foo") { this, v in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addStaticInitializer { this in
                XCTAssertEqual(b.context, [.javascript, .method, .classMethod])
            }

            cls.addPrivateInstanceMethod("m", with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
            cls.addPrivateStaticMethod("m", with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .method, .classMethod])
            }
        }
        XCTAssertEqual(b.context, .javascript)

        let _ = b.finalize()
    }

    func testCodeStrings() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        let _ = b.buildCodeString() {
            XCTAssertEqual(b.context, .javascript)
            b.buildRepeatLoop(n: 10) { _ in
                b.loadInt(1337)
                XCTAssertEqual(b.context, [.javascript, .loop])
                let _ = b.buildCodeString() {
                    b.loadString("hello world")
                    XCTAssertEqual(b.context, [.javascript])
                }
            }
        }
        XCTAssertEqual(b.context, .javascript)

        let _ = b.finalize()
    }

    func testContextPropagation() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)

        let _ = b.buildPlainFunction(with: .parameters(n: 5)) { args in
            XCTAssertEqual(b.context, [.javascript, .subroutine])

            b.buildIfElse(args[0], ifBody: {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }, elseBody: {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            })

            b.buildWhileLoop({
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                return b.loadBool(false)
            }) {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            b.buildDoWhileLoop(do: {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }, while: {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                return b.loadBool(false)
            })

            b.buildForLoop({
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }, {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                return b.loadBool(false)
            }, {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }) {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            b.buildForInLoop(args[1]) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            b.buildForOfLoop(args[2]) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            b.buildForOfLoop(args[3], selecting: [0, 1, 3]) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            b.buildRepeatLoop(n: 100) { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
            }

            let case1 = b.loadInt(1337)
            let case2 = b.loadInt(1338)
            b.buildSwitch(on: args[4]) { swtch in
                XCTAssertEqual(b.context, .switchBlock)
                swtch.addCase(case1) {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .switchCase])
                }
                swtch.addCase(case2) {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .switchCase])
                }
                swtch.addDefaultCase {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .switchCase])
                }
            }

            b.buildTryCatchFinally(tryBody: {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }, catchBody: { _ in
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }, finallyBody: {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            })

            b.blockStatement {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
            }
        }
        XCTAssertEqual(b.context, .javascript)

        let _  = b.finalize()
    }

    // Tests if the context is correctly identified in nested loops and switches. 
    // Needs to work to distinguish when to emit LoopBreak and SwitchBreak.
    func testBreakContext() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let case1 = b.loadInt(1337)
        let case2 = b.loadInt(9001)
        
        // Test case 1: switch -> loop -> switch
        b.buildSwitch(on: case1) { outer_switch in
            XCTAssertEqual(b.context, .switchBlock)
            outer_switch.addCase(case1) {
                XCTAssertEqual(b.context, [.javascript, .switchCase])
                b.buildWhileLoop({ b.loadBool(true) }) {        
                    XCTAssertEqual(b.context, [.javascript, .loop])
                    b.buildSwitch(on: case2) { inner_switch in
                        XCTAssertEqual(b.context, .switchBlock)
                        inner_switch.addCase(case2) {
                            XCTAssertEqual(b.context, [.javascript, .switchCase])
                        }
                    }
                } 
            }
        }
        XCTAssertEqual(b.context, .javascript)

        // Test case 2: loop -> switch -> loop
        b.buildWhileLoop({ b.loadBool(true) }) {
            XCTAssertEqual(b.context, [.javascript, .loop])
            b.buildSwitch(on: case1) { swtch in
                XCTAssertEqual(b.context, .switchBlock)
                swtch.addCase(case1) {
                    XCTAssertEqual(b.context, [.javascript, .switchCase])
                    b.buildWhileLoop({ b.loadBool(true) }) {
                        XCTAssertEqual(b.context, [.javascript, .loop])
                    }
                }
            }
        }
        XCTAssertEqual(b.context, .javascript)
        
        let _ = b.finalize()
    }
}
