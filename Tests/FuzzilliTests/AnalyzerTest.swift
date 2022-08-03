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
            b.generate(n: 100)
            let program = b.finalize()

            var contextAnalyzer = ContextAnalyzer()

            for instr in program.code {
                contextAnalyzer.analyze(instr)
            }

            XCTAssertEqual(contextAnalyzer.context, .script)
        }
    }

    func testNestedLoops() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)

        let _ = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            XCTAssertEqual(b.context, [.script, .function])
            let loopVar1 = b.loadInt(0)
            b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                XCTAssertEqual(b.context, [.script, .function, .loop])
                b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { args in
                    XCTAssertEqual(b.context, [.script, .function])
                    let v1 = b.loadInt(0)
                    let v2 = b.loadInt(10)
                    let v3 = b.loadInt(20)
                    b.buildForLoop(v1, .lessThan, v2, .Add, v3) { _ in
                        XCTAssertEqual(b.context, [.script, .function, .loop])
                    }
                }
                XCTAssertEqual(b.context, [.script, .function, .loop])
            }
        }

        let _ = b.finalize()
    }

    func testNestedFunctions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)
        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            XCTAssertEqual(b.context, [.script, .function, .asyncFunction])
            let v3 = b.loadInt(0)
            b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { _ in
                XCTAssertEqual(b.context, [.script, .function])
            }
            XCTAssertEqual(b.context, [.script, .function, .asyncFunction])
            b.await(value: v3)
            b.buildAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
                XCTAssertEqual(b.context, [.script, .function, .asyncFunction, .generatorFunction])
            }
            XCTAssertEqual(b.context, [.script, .function, .asyncFunction])
        }

        let _ = b.finalize()
    }

    func testNestedWithStatements() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)
        let obj = b.loadString("HelloWorld")
        b.buildWith(obj) {
            XCTAssertEqual(b.context, [.script, .with])
            b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { _ in
                XCTAssertEqual(b.context, [.script, .function])
                b.buildWith(obj) {
                    XCTAssertEqual(b.context, [.script, .function, .with])
                }
            }
            XCTAssertEqual(b.context, [.script, .with])
            b.loadFromScope(id: b.genPropertyNameForRead())
        }

        let _ = b.finalize()
    }

    func testClassDefinitions() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)
        let superclass = b.buildClass() { cls in
            cls.defineConstructor(withParameters: [.plain(.integer)]) { params in
                XCTAssertEqual(b.context, [.script, .classDefinition, .function])
                let loopVar1 = b.loadInt(0)
                b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                    XCTAssertEqual(b.context, [.script, .classDefinition, .function, .loop])
                }
                XCTAssertEqual(b.context, [.script, .classDefinition, .function])
            }
        }
        XCTAssertEqual(b.context, .script)

        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.plain(.string)]) { _ in
                XCTAssertEqual(b.context, [.script, .classDefinition, .function])
                let v0 = b.loadInt(42)
                let v1 = b.createObject(with: ["foo": v0])
                b.callSuperConstructor(withArgs: [v1])
            }
            cls.defineMethod("classMethod", withSignature: FunctionSignature(withParameterCount: 2, hasRestParam: false)) { _ in
                XCTAssertEqual(b.context, [.script, .classDefinition, .function])
                b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
                    XCTAssertEqual(b.context, [.script, .function, .asyncFunction])
                }
                XCTAssertEqual(b.context, [.script, .classDefinition, .function])
            }
        }
        XCTAssertEqual(b.context, .script)

        let _ = b.finalize()
    }

    func testCodeStrings() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)
        let _ = b.buildCodeString() {
            XCTAssertEqual(b.context, .script)
            let v11 = b.loadInt(0)
            let v12 = b.loadInt(2)
            let v13 = b.loadInt(1)
            b.buildForLoop(v11, .lessThan, v12, .Add, v13) { _ in
                b.loadInt(1337)
                XCTAssertEqual(b.context, [.script, .loop])
                let _ = b.buildCodeString() {
                    b.loadString("hello world")
                    XCTAssertEqual(b.context, [.script])
                }
            }
        }
        XCTAssertEqual(b.context, .script)

        let _ = b.finalize()
    }

    func testContextPropagatingBlocks() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssertEqual(b.context, .script)

        let _ = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            XCTAssertEqual(b.context, [.script, .function])
            let loopVar1 = b.loadInt(0)
            b.buildDoWhileLoop(loopVar1, .lessThan, b.loadInt(42)) {
                XCTAssertEqual(b.context, [.script, .function, .loop])
                b.buildIfElse(args[0], ifBody: {
                    XCTAssertEqual(b.context, [.script, .function, .loop])
                    let v = b.binary(args[0], args[1], with: .Mul)
                    b.doReturn(value: v)
                }, elseBody: {
                    XCTAssertEqual(b.context, [.script, .function, .loop])
                    b.doReturn(value: args[2])
                })
            }
            b.blockStatement {
                XCTAssertEqual(b.context, [.script, .function])
                b.buildTryCatchFinally(tryBody: {
                    XCTAssertEqual(b.context, [.script, .function])
                    let v = b.binary(args[0], args[1], with: .Mul)
                    b.doReturn(value: v)
                }, catchBody: { _ in
                    XCTAssertEqual(b.context, [.script, .function])
                    let v4 = b.createObject(with: ["a" : b.loadInt(1337)])
                    b.reassign(args[0], to: v4)
                }, finallyBody: {
                    XCTAssertEqual(b.context, [.script, .function])
                    let v = b.binary(args[0], args[1], with: .Add)
                    b.doReturn(value: v)
                })
            }
        }
        XCTAssertEqual(b.context, .script)

        let _  = b.finalize()
    }
}

extension AnalyzerTests {
    static var allTests : [(String, (AnalyzerTests) -> () throws -> Void)] {
        return [
            ("testContextAnalyzer", testContextAnalyzer),
            ("testNestedLoops", testNestedLoops),
            ("testNestedFunctions", testNestedFunctions),
            ("testNestedWithStatements", testNestedWithStatements),
            ("testClassDefinitions", testClassDefinitions),
            ("testCodeStrings", testCodeStrings),
            ("testContextPropagatingBlocks", testContextPropagatingBlocks)
        ]
    }
}
