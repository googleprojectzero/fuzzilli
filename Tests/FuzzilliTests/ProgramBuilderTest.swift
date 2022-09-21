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

        for _ in 0..<1000 {
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
        b.buildDoWhileLoop(i, .lessThan, b.loadInt(44)) {
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
        b.splice(from: original, at: original.code.lastInstruction.index)
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
        b.buildWhileLoop(i, .lessThan, b.loadInt(100)) {
            b.binary(f, f2, with: .Add)
        }
        b.loadProperty("f", of: o)
        let original = b.finalize()

        // Expected splice
        i = b.loadInt(42)
        f = b.loadFloat(13.37)
        f2 = b.loadFloat(133.7)
        b.buildWhileLoop(i, .lessThan, b.loadInt(100)) {
            // If a block is spliced, its entire body is copied as well
            b.binary(f, f2, with: .Add)
        }
        let expectedSplice = b.finalize()

        // Actual splice
        let idx = original.code.lastInstruction.index - 1
        XCTAssert(original.code[idx].op is EndWhileLoop)
        b.splice(from: original, at: idx)
        let actualSplice = b.finalize()

        XCTAssertEqual(expectedSplice, actualSplice)
    }

    func testSplicing3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative      // Aggressive splicing might not include all mutating instructions

        // Original
        var f2 = b.loadFloat(13.37)
        b.buildPlainFunction(withSignature: [.plain(.anything)] => .unknown) { args in
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
        b.splice(from: original, at: idx)
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
        b.buildPlainFunction(withSignature: FunctionSignature.forUnknownFunction) { _ in
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
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        // We enable conservative mode to exercise the canMutate checks within the splice loop
        b.mode = .conservative

        var superclass = b.buildClass() { cls in
            cls.defineConstructor(withParameters: [.plain(.integer)]) { params in
            }

            cls.defineProperty("a")

            cls.defineMethod("f", withSignature: [.plain(.float)] => .string) { params in
                b.doReturn(value: b.loadString("foobar"))
            }
        }

        let _ = b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.plain(.string)]) { params in
                let v3 = b.loadInt(0)
                let v4 = b.loadInt(2)
                let v5 = b.loadInt(1)
                b.buildForLoop(v3, .lessThan, v4, .Add, v5) { _ in
                    let v0 = b.loadInt(42)
                    let v1 = b.createObject(with: ["foo": v0])
                    splicePoint = b.indexOfNextInstruction()
                    b.callSuperConstructor(withArgs: [v1])
                }
            }

            cls.defineProperty("b")

            cls.defineMethod("g", withSignature: [.plain(.anything)] => .unknown) { params in
                b.buildPlainFunction(withSignature: [] => .unknown) { _ in
                }
            }
        }

        let original = b.finalize()

        superclass = b.buildClass() { cls in
            cls.defineConstructor(withParameters: [.plain(.integer)]) { params in
            }
        }
        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.plain(.string)]) { _ in
                // Splicing at CallSuperConstructor
                b.splice(from: original, at: splicePoint)
            }
        }
        let actualSplice = b.finalize()

        superclass = b.buildClass() { cls in
            cls.defineConstructor(withParameters: [.plain(.integer)]) { params in
            }
        }

        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.plain(.string)]) { _ in
                let v0 = b.loadInt(42)
                let v1 = b.createObject(with: ["foo": v0])
                b.callSuperConstructor(withArgs: [v1])
            }
        }
        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testAsyncGeneratorSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildAsyncGeneratorFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.buildForLoop(v3, .lessThan, v4, .Add, v5) { _ in
                let v0 = b.loadInt(42)
                let _ = b.createObject(with: ["foo": v0])
                splicePoint = b.indexOfNextInstruction()
                b.await(value: v3)
                let v8 = b.loadInt(1337)
                b.yield(value: v8)
            }
            b.doReturn(value: v4)
        }

        let original = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            // Splicing at Await
            b.splice(from: original, at: splicePoint)
        }

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v0 = b.loadInt(0)
            let _ = b.await(value: v0)
        }
        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testForInSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in

        //BEGIN: Some instructions that shouldn't end up in the splice
        var initialValues = [Variable]()
        initialValues.append(b.loadInt(15))
        initialValues.append(b.loadInt(30))
        initialValues.append(b.loadString("Hello"))
        initialValues.append(b.loadString("World"))
        let v4 = b.createArray(with: initialValues)
        let v5 = b.loadFloat(13.37)

        let v6 = b.loadBuiltin("Array")
        let _ = b.construct(v6, withArgs: [v4,v5], spreading: [true,false])
        // END

        let v0 = b.loadInt(10)
        let v1 = b.loadString("Hello")
        let v2 = b.loadFloat(13.57)
        let v3 = b.createObject(with: ["foo": v2, "bar": v1, "baz": v0])
        b.buildForInLoop(v3) { v4 in
            let v5 = b.loadInt(1000)
            let v6 = b.await(value: v5)
            splicePoint = b.indexOfNextInstruction()
            b.storeComputedProperty(v6, as: v4, on: v3)
        }
        }
        let original = b.finalize()

        // Splicing at StoreComputedProperty
        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
        let v0 = b.loadInt(10)
        let v1 = b.loadString("Hello")
        let v2 = b.loadFloat(13.57)
        let v3 = b.createObject(with: ["foo": v2, "bar": v1, "baz": v0])
        b.buildForInLoop(v3) { v4 in
            let v5 = b.loadInt(1000)
            let v6 = b.await(value: v5)
            b.storeComputedProperty(v6, as: v4, on: v3)
        }
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testBeginForSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v0 = b.loadBuiltin(b.genBuiltinName())
            let v1 = b.callFunction(v0, withArgs: [])
            b.createObject(with: ["foo" : v1])
            b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            }

            b.blockStatement {
                b.loadElement(2, of: v1)
            }

            let v2 = b.loadInt(0)
            let v3 = b.loadInt(10)
            let v4 = b.loadInt(20)
            splicePoint = b.indexOfNextInstruction()
            b.buildForLoop(v2, .lessThan, v3, .Add, v4) { _ in
                b.loadArguments()
            }
        }

        let original = b.finalize()

        // Splice at BeginForLoop
        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v2 = b.loadInt(0)
            let v3 = b.loadInt(10)
            let v4 = b.loadInt(20)
            b.buildForLoop(v2, .lessThan, v3, .Add, v4) { _ in
                b.loadArguments()
            }
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testBeginWithSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.loadInt(10)
            let obj = b.loadString("Hello")
            b.buildWith(obj) {
                let lfs = b.loadFromScope(id: "World")
                splicePoint = b.indexOfNextInstruction()
                b.await(value: lfs)
                b.loadString("Return")
            }
            b.loadFloat(13.37)
        }

        let original = b.finalize()

        // Splice at Await
        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let obj = b.loadString("Hello")
            b.buildWith(obj) {
                let lfs = b.loadFromScope(id: "World")
                b.await(value: lfs)
            }
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testCodeStringSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        let v2 = b.loadInt(0)
        let v3 = b.loadInt(10)
        let v4 = b.loadInt(20)
        b.buildForLoop(v2, .lessThan, v3, .Add, v4) { _ in
            b.loadThis()
            let code = b.buildCodeString() {
                let i = b.loadInt(42)
                let o = b.createObject(with: ["i": i])
                let json = b.loadBuiltin("JSON")
                b.callMethod("stringify", on: json, withArgs: [o])
            }
            let eval = b.reuseOrLoadBuiltin("eval")
            splicePoint = b.indexOfNextInstruction()
            b.callFunction(eval, withArgs: [code])
        }

        let original = b.finalize()

        // Splice at CallFunction
        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        let code = b.buildCodeString() {
                let i = b.loadInt(42)
                let o = b.createObject(with: ["i": i])
                let json = b.loadBuiltin("JSON")
                b.callMethod("stringify", on: json, withArgs: [o])
            }
        let eval = b.reuseOrLoadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testSwitchBlockSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        let obj = b.loadString("Hello")
        let builtin = b.loadBuiltin("JSON")
        let v0 = b.loadInt(10)
        b.buildWith(obj) {
            b.buildSwitch(on: builtin) { cases in
                cases.addDefault {
                    b.loadInt(20)
                }
                cases.add(v0){
                    let lfs = b.loadFromScope(id: "World")
                    splicePoint = b.indexOfNextInstruction()
                    b.reassign(v0, to: lfs)
                }
            }
        }

        let original = b.finalize()

        // Splice at Reassign
        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        let obj2 = b.loadString("Hello")
        let v2 = b.loadInt(10)
        b.buildWith(obj2) {
            let lfs = b.loadFromScope(id: "World")
            b.reassign(v2, to: lfs)
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testSameContextSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
                let v = b.loadInt(10)
                splicePoint = b.indexOfNextInstruction()
                b.await(value: v)
            }
        }

        let original = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.splice(from: original, at: splicePoint)
        }

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.await(value: b.loadInt(10))
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testSameContextSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { args in
            b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
                splicePoint = b.indexOfNextInstruction()
                b.await(value: args[0])
            }
        }

        let original = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.splice(from: original, at: splicePoint)
        }

        let actualSplice = b.finalize()

        b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { args in
                b.buildAsyncFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
                    b.await(value: args[0])
                }
            }
        }

        let expectedSplice = b.finalize()

        XCTAssertEqual(actualSplice, expectedSplice)
    }

    func testCallFunctionSplicingWhereInputIsAFunction() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        let v1 = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v2 = b.loadInt(0)
            let v3 = b.loadInt(10)
            let v4 = b.loadInt(20)
            b.buildForLoop(v2, .lessThan, v3, .Add, v4) { _ in
                b.loopBreak()
            }
        }
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(v1, withArgs: [])

        let original = b.finalize()

        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        XCTAssertEqual(actualSplice, original)
    }

    func testCreateArraySplicingWithMutatingFunction() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        let v0 = b.loadInt(42)
        b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v2 = b.loadInt(0)
            let v3 = b.loadInt(10)
            let v4 = b.loadInt(20)
            b.buildForLoop(v2, .lessThan, v3, .Add, v4) { _ in
                let v5 = b.loadArguments()
                b.reassign(v0, to: v5)
            }
        }
        splicePoint = b.indexOfNextInstruction()
        b.createArray(with: [v0])

        let original = b.finalize()

        b.splice(from: original, at: splicePoint)

        let actualSplice = b.finalize()

        let v6 = b.loadInt(42)
        b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 2)) { _ in
            let v5 = b.loadArguments()
            b.reassign(v6, to: v5)
        }
        b.createArray(with: [v6])

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
            ("testForInSplicing", testForInSplicing),
            ("testBeginForSplicing", testBeginForSplicing),
            ("testBeginWithSplicing", testBeginWithSplicing),
            ("testCodeStringSplicing", testCodeStringSplicing),
            ("testSwitchBlockSplicing", testSwitchBlockSplicing),
            ("testSameContextSplicing", testSameContextSplicing),
            ("testSameContextSplicing2", testSameContextSplicing2),
            ("testCallFunctionSplicingWhereInputIsAFunction", testCallFunctionSplicingWhereInputIsAFunction),
            ("testCreateArraySplicingWithMutatingFunction", testCreateArraySplicingWithMutatingFunction)
        ]
    }
}
