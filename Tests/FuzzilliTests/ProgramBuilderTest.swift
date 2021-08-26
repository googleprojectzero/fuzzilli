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

class ProgramBuilderTests: XCTestCase {
    // Verify that code generators don't crash and always produce valid programs.
    func testCodeGeneration() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.generate(n: 100)
            let program = b.finalize()
            // Add to corpus since generate() does splicing as well
            fuzzer.corpus.add(program, ProgramAspects(outcome: .succeeded))
            
            XCTAssert(program.size >= 100)
        }
    }
    
    func testSplicing1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        // Original
        var i = b.loadInt(42)
        b.doWhileLoop(i, .lessThan, b.loadInt(44)) {
            b.unary(.BitwiseNot, i)
        }
        b.loadFloat(13.37)
        var arr = b.createArray(with: [i, i, i])
        b.loadProperty("length", of: arr)
        b.callMethod("pop", on: arr, withArgs: [])
        let original = b.finalize()
        
        // Expected splice
        i = b.loadInt(42)
        arr = b.createArray(with: [i, i, i])
        b.callMethod("pop", on: arr, withArgs: [])
        let expectedSplice = b.finalize()
        
        // Actual splice
        b.splice(from: original, at: original.code.lastInstruction.index, activeContexts: [ProgramContext.script])
        let actualSplice = b.finalize()
        
        XCTAssertEqual(expectedSplice, actualSplice)
    }
    
    func testSplicing2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        // Original
        var i = b.loadInt(42)
        var f = b.loadFloat(13.37)
        var f2 = b.loadFloat(133.7)
        let o = b.createObject(with: ["f": f])
        b.storeProperty(f2, as: "f", on: o)
        b.whileLoop(i, .lessThan, b.loadInt(100)) {
            b.binary(f, f2, with: .Add)
        }
        b.loadProperty("f", of: o)
        let original = b.finalize()
        
        // Expected splice
        i = b.loadInt(42)
        f = b.loadFloat(13.37)
        f2 = b.loadFloat(133.7)
        b.whileLoop(i, .lessThan, b.loadInt(100)) {
            // If a block is spliced, its entire body is copied as well
            b.binary(f, f2, with: .Add)
        }
        let expectedSplice = b.finalize()
        
        // Actual splice
        let idx = original.code.lastInstruction.index - 1
        XCTAssert(original.code[idx].op is EndWhile)
        b.splice(from: original, at: idx, activeContexts: [ProgramContext.script])
        let actualSplice = b.finalize()
        
        XCTAssertEqual(expectedSplice, actualSplice)
    }
    
    func testSplicing3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative      // Aggressive splicing might not include all mutating instructions
        
        // Original
        var f2 = b.loadFloat(13.37)
        b.definePlainFunction(withSignature: [.anything] => .unknown) { args in
            let i = b.loadInt(42)
            let f = b.loadFloat(13.37)
            b.reassign(f2, to: b.loadFloat(133.7))
            let o = b.createObject(with: ["i": i, "f": f])
            let o2 = b.createObject(with: ["i": i, "f": f2])
            b.binary(i, args[0], with: .Add)
            b.storeProperty(f2, as: "f", on: o)
            let object = b.loadBuiltin("Object")
            let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
            b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])
            b.callMethod("defineProperty", on: object, withArgs: [o2, b.loadString("s"), descriptor])
            let json = b.loadBuiltin("JSON")
            b.callMethod("stringify", on: json, withArgs: [o])
        }
        let original = b.finalize()
        
        // Expected splice
        f2 = b.loadFloat(13.37)
        let i = b.loadInt(42)
        let f = b.loadFloat(13.37)
        b.reassign(f2, to: b.loadFloat(133.7))      // (Possibly) mutating instruction must be included
        let o = b.createObject(with: ["i": i, "f": f])
        b.storeProperty(f2, as: "f", on: o)     // (Possibly) mutating instruction must be included
        let object = b.loadBuiltin("Object")
        let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
        b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])    // (Possibly) mutating instruction must be included
        let json = b.loadBuiltin("JSON")
        b.callMethod("stringify", on: json, withArgs: [o])
        let expectedSplice = b.finalize()
        
        // Actual splice
        let idx = original.code.lastInstruction.index - 1
        XCTAssert(original.code[idx].op is CallMethod)
        b.splice(from: original, at: idx, activeContexts: [ProgramContext.script])
        let actualSplice = b.finalize()

        XCTAssertEqual(expectedSplice, actualSplice)
    }

    func testTypeInstantiation() {
        let env = JavaScriptEnvironment(additionalBuiltins: [:], additionalObjectGroups: [])
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            let t = ProgramTemplate.generateType(forFuzzer: fuzzer)
            // generateVariable must be able to generate every type produced by generateType
            let _ = b.generateVariable(ofType: t)
        }
    }

    func testVariableReuse() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let foo = b.loadBuiltin("foo")
        let foo2 = b.reuseOrLoadBuiltin("foo")
        XCTAssertEqual(foo, foo2)
        let bar = b.reuseOrLoadBuiltin("bar")
        XCTAssertNotEqual(foo, bar)         // Different builtin
        b.reassign(foo, to: b.loadBuiltin("baz"))
        let foo3 = b.reuseOrLoadBuiltin("foo")
        XCTAssertNotEqual(foo, foo3)        // Variable was reassigned

        let float = b.loadFloat(13.37)
        var floatOutOfScope: Variable? = nil
        b.definePlainFunction(withSignature: FunctionSignature.forUnknownFunction) { _ in
            let int = b.loadInt(42)
            let int2 = b.reuseOrLoadInt(42)
            XCTAssertEqual(int, int2)
            b.unary(.PostInc, int)
            let int3 = b.reuseOrLoadInt(42)
            XCTAssertNotEqual(int, int3)        // Variable was reassigned

            let float2 = b.reuseOrLoadFloat(13.37)
            XCTAssertEqual(float, float2)
            floatOutOfScope = b.loadFloat(4.2)
        }

        let float3 = b.reuseOrLoadFloat(4.2)
        XCTAssertNotEqual(floatOutOfScope!, float3)     // Variable went out of scope
    }

    func testVarRetrievalFromInnermostScope() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.blockStatement {
            b.blockStatement {
                b.blockStatement {
                    let innermostVar = b.loadInt(1)
                    XCTAssertEqual(b.randVar(), innermostVar)
                    XCTAssertEqual(b.randVarInternal(excludeInnermostScope: true), nil)
                }
            }
        }
    }

    func testVarRetrievalFromOuterScope() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.blockStatement {
            b.blockStatement {
                let outerScopeVar = b.loadFloat(13.37)
                b.blockStatement {
                    let _ = b.loadInt(100)
                    XCTAssertEqual(b.randVar(excludeInnermostScope: true), outerScopeVar)
                }
            }
        }
    }

    func testRandVarInternal() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.blockStatement {
            let var1 = b.loadString("HelloWorld")
            XCTAssertEqual(b.randVarInternal(filter: { $0 == var1 }), var1)
            b.blockStatement {
                let var2 = b.loadFloat(13.37)
                XCTAssertEqual(b.randVarInternal(filter: { $0 == var2 }), var2)
                b.blockStatement {
                    let var3 = b.loadInt(100)
                    XCTAssertEqual(b.randVarInternal(filter: { $0 == var3 }), var3)
                }
            }
        }
    }

    func testRandVarInternalFromOuterScope() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let var0 = b.loadInt(1337)
        b.blockStatement {
            let var1 = b.loadString("HelloWorld")
            XCTAssertEqual(b.randVarInternal(filter: { $0 == var0 }, excludeInnermostScope : true), var0)
            b.blockStatement {
                let var2 = b.loadFloat(13.37)
                XCTAssertEqual(b.randVarInternal(filter: { $0 == var1 }, excludeInnermostScope : true), var1)
                b.blockStatement {
                    let _ = b.loadInt(100)
                    XCTAssertEqual(b.randVarInternal(filter: { $0 == var2 }, excludeInnermostScope : true), var2)
                }
            }
        }
    }

    func testClassSplicing() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superclass = b.defineClass() { cls in
            cls.defineConstructor(withParameters: [.integer]) { params in
            }

            cls.defineProperty("a")

            cls.defineMethod("f", withSignature: [.float] => .string) { params in
                b.doReturn(value: b.loadString("foobar"))
            }
        }

        let _ = b.defineClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.string]) { params in
                let v3 = b.loadInt(0)
                let v4 = b.loadInt(2)
                let v5 = b.loadInt(1)
                b.forLoop(v3, .lessThan, v4, .Add, v5) { _ in
                    let v0 = b.loadInt(42)
                    let v1 = b.createObject(with: ["foo": v0])
                    b.callSuperConstructor(withArgs: [v1])
                }
            }

            cls.defineProperty("b")

            cls.defineMethod("g", withSignature: [.anything] => .unknown) { params in
                b.definePlainFunction(withSignature: [] => .unknown) { _ in
                }
            }
        }

        let original = b.finalize()
        
        // Splicing at CallSuperConstructor
        b.splice(from: original, at: original.code.lastInstruction.index - 5, activeContexts: [ProgramContext.script])
        var actualSplice = b.finalize()

        // No instructions spliced
        XCTAssertEqual(actualSplice, Program.init())

        b.splice(from: original, at: original.code.lastInstruction.index - 5, activeContexts: [ProgramContext.script, ProgramContext.classDefinition])
        actualSplice = b.finalize()
        
        print(fuzzer.lifter.lift(actualSplice))

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        b.callSuperConstructor(withArgs: [v1])
        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testAsyncGeneratorSplicing() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.defineAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.forLoop(v3, .lessThan, v4, .Add, v5) { _ in
                let v0 = b.loadInt(42)
                let _ = b.createObject(with: ["foo": v0])
                b.await(value: v3)
                let v8 = b.loadInt(1337)
                b.yield(value: v8)
            }
            b.doReturn(value: v4)
        }

        let original = b.finalize()

        b.splice(from: original, at: original.code.lastInstruction.index - 5, activeContexts: [ProgramContext.script])
        var actualSplice = b.finalize()

        XCTAssertEqual(actualSplice, Program.init())

        b.splice(from: original, at: original.code.lastInstruction.index - 5, activeContexts: [ProgramContext.script, ProgramContext.asyncFunction])
        actualSplice = b.finalize()

        let v0 = b.loadInt(0)
        let _ = b.await(value: v0)
        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }
}

extension ProgramBuilderTests {
    static var allTests : [(String, (ProgramBuilderTests) -> () throws -> Void)] {
        return [
            ("testCodeGeneration", testCodeGeneration),
            ("testSplicing1", testSplicing1),
            ("testSplicing2", testSplicing2),
            ("testSplicing3", testSplicing3),
            ("testTypeInstantiation", testTypeInstantiation),
            ("testVariableReuse", testVariableReuse),
            ("testVarRetrievalFromInnermostScope", testVarRetrievalFromInnermostScope),
            ("testVarRetrievalFromOuterScope", testVarRetrievalFromOuterScope),
            ("testRandVarInternal", testRandVarInternal),
            ("testRandVarInternalFromOuterScope", testRandVarInternalFromOuterScope),
            ("testClassSplicing", testClassSplicing),
            ("testAsyncGeneratorSplicing", testAsyncGeneratorSplicing),
        ]
    }
}
