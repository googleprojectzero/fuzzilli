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
            b.build(n: 100, by: .runningGenerators)
            let program = b.finalize()

            var contextAnalyzer = ContextAnalyzer()

            for instr in program.code {
                contextAnalyzer.analyze(instr)
            }

            XCTAssertEqual(contextAnalyzer.context, .javascript)
        }
    }

    func testNestedLoops() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)

        let _ = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            XCTAssertEqual(b.context, [.javascript, .subroutine])
            let loopVar1 = b.loadInt(0)
            b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                b.buildPlainFunction(with: .parameters(n: 2)) { args in
                    XCTAssertEqual(b.context, [.javascript, .subroutine])
                    let v1 = b.loadInt(0)
                    let v2 = b.loadInt(10)
                    let v3 = b.loadInt(20)
                    b.buildForLoop(v1, .lessThan, v2, .Add, v3) { _ in
                        XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                    }
                }
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
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
            b.loadFromScope(id: b.genPropertyNameForRead())
        }

        let _ = b.finalize()
    }

    func testClassDefinitions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)
        let superclass = b.buildClass() { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { params in
                XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine])
                let loopVar1 = b.loadInt(0)
                b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                    XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine, .loop])
                }
                XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine])
            }
        }
        XCTAssertEqual(b.context, .javascript)

        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { _ in
                XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine])
                let v0 = b.loadInt(42)
                let v1 = b.createObject(with: ["foo": v0])
                b.callSuperConstructor(withArgs: [v1])
            }
            cls.defineMethod("classMethod", with: .parameters(n: 2)) { _ in
                XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine])
                b.buildAsyncFunction(with: .parameters(n: 2)) { _ in
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .asyncFunction])
                }
                XCTAssertEqual(b.context, [.javascript, .classDefinition, .subroutine])
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
            let v11 = b.loadInt(0)
            let v12 = b.loadInt(2)
            let v13 = b.loadInt(1)
            b.buildForLoop(v11, .lessThan, v12, .Add, v13) { _ in
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

    func testContextPropagatingBlocks() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .javascript)

        let _ = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            XCTAssertEqual(b.context, [.javascript, .subroutine])
            let loopVar1 = b.loadInt(0)
            b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                b.buildIfElse(args[0], ifBody: {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                    let v = b.binary(args[0], args[1], with: .Mul)
                    b.doReturn(v)
                }, elseBody: {
                    XCTAssertEqual(b.context, [.javascript, .subroutine, .loop])
                    b.doReturn(args[2])
                })
            }
            b.blockStatement {
                XCTAssertEqual(b.context, [.javascript, .subroutine])
                b.buildTryCatchFinally(tryBody: {
                    XCTAssertEqual(b.context, [.javascript, .subroutine])
                    let v = b.binary(args[0], args[1], with: .Mul)
                    b.doReturn(v)
                }, catchBody: { _ in
                    XCTAssertEqual(b.context, [.javascript, .subroutine])
                    let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                    b.reassign(args[0], to: v4)
                }, finallyBody: {
                    XCTAssertEqual(b.context, [.javascript, .subroutine])
                    let v = b.binary(args[0], args[1], with: .Add)
                    b.doReturn(v)
                })
            }
        }
        XCTAssertEqual(b.context, .javascript)

        let _  = b.finalize()
    }
}
