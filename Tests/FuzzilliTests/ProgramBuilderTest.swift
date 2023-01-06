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
    // Verify that program building doesn't crash and always produce valid programs.
    func testBuilding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        let N = 100

        var sumOfProgramSizes = 0
        for _ in 0..<100 {
            b.build(n: N)
            let program = b.finalize()
            sumOfProgramSizes += program.size

            // Add to corpus since build() does splicing as well
            fuzzer.corpus.add(program, ProgramAspects(outcome: .succeeded))

            // We'll have generated at least N instructions, probably more.
            XCTAssertGreaterThanOrEqual(program.size, N)
        }

        // On average, we should generate between n and 2x n instructions.
        let averageSize = sumOfProgramSizes / 100
        XCTAssertLessThanOrEqual(averageSize, 2*N)
    }

    func testShapeOfGeneratedCode1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let simpleGenerator = CodeGenerator("SimpleGenerator") { b in
            b.loadInt(Int64.random(in: 0..<100))
        }
        fuzzer.codeGenerators = WeightedList<CodeGenerator>([
            (simpleGenerator,      1),
        ])

        for _ in 0..<10 {
            b.build(n: 100, by: .runningGenerators)
            let program = b.finalize()

            // In this case, the size of the generated program must be exactly the requested size.
            XCTAssertEqual(program.size, 100)
        }
    }

    func testShapeOfGeneratedCode2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.minRecursiveBudgetRelativeToParentBudget = 0.25
        b.maxRecursiveBudgetRelativeToParentBudget = 0.25

        let simpleGenerator = CodeGenerator("SimpleGenerator") { b in
            b.loadInt(Int64.random(in: 0..<100))
        }
        let recursiveGenerator = RecursiveCodeGenerator("RecursiveGenerator") { b in
            b.buildRepeat(n: 5) { _ in
                b.buildRecursive()
            }
        }
        fuzzer.codeGenerators = WeightedList<CodeGenerator>([
            (simpleGenerator,      3),
            (recursiveGenerator,   1),
        ])

        for _ in 0..<10 {
            b.build(n: 100, by: .runningGenerators)
            let program = b.finalize()

            // Uncomment to see the "shape" of generated programs on the console.
            //print(FuzzILLifter().lift(program))

            // The size may be larger, but only roughly by 100 * 0.25 + 100 * 0.25**2 + 100 * 0.25**3 ... (each block may overshoot its budget by roughly the maximum recursive block size).
            XCTAssertLessThan(program.size, 150)
        }
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
        b.buildPlainFunction(with: b.generateFunctionParameters()) { _ in
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

    func testBasicSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let i1 = b.loadInt(0x41)
        var i2 = b.loadInt(0x42)
        let cond = b.compare(i1, with: i2, using: .lessThan)
        b.buildIfElse(cond, ifBody: {
            let String = b.loadBuiltin("String")
            splicePoint = b.indexOfNextInstruction()
            b.callMethod("fromCharCode", on: String, withArgs: [i1])
            b.callMethod("fromCharCode", on: String, withArgs: [i2])
        }, elseBody: {
            b.binary(i1, i2, with: .Add)
        })
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        i2 = b.loadInt(0x41)
        let String = b.loadBuiltin("String")
        b.callMethod("fromCharCode", on: String, withArgs: [i2])
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testBasicSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var i = b.loadInt(42)
        b.buildDoWhileLoop(i, .lessThan, b.loadInt(44)) {
            b.unary(.PostInc, i)
        }
        b.loadFloat(13.37)
        var arr = b.createArray(with: [i, i, i])
        b.loadProperty("length", of: arr)
        splicePoint = b.indexOfNextInstruction()
        b.callMethod("pop", on: arr, withArgs: [])
        let original = b.finalize()

        //
        // Actual Program (1)
        //
        b.probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 0.0
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual1 = b.finalize()

        //
        // Expected Program (1)
        //
        i = b.loadInt(42)
        arr = b.createArray(with: [i, i, i])
        b.callMethod("pop", on: arr, withArgs: [])
        let expected1 = b.finalize()

        XCTAssertEqual(expected1, actual1)

        //
        // Actual Program (2)
        //
        b.probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 1.0
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual2 = b.finalize()

        //
        // Expected Program (2)
        //
        i = b.loadInt(42)
        b.buildDoWhileLoop(i, .lessThan, b.loadInt(44)) {
            b.unary(.PostInc, i)
        }
        arr = b.createArray(with: [i, i, i])
        b.callMethod("pop", on: arr, withArgs: [])
        let expected2 = b.finalize()

        XCTAssertEqual(expected2, actual2)
    }

    func testBasicSplicing3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
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

        //
        // Actual Program
        //
        let idx = original.code.lastInstruction.index - 1       // Splice at EndWhileLoop
        XCTAssert(original.code[idx].op is EndWhileLoop)
        b.splice(from: original, at: idx)
        let actual = b.finalize()

        //
        // Expected Program
        //
        i = b.loadInt(42)
        f = b.loadFloat(13.37)
        f2 = b.loadFloat(133.7)
        b.buildWhileLoop(i, .lessThan, b.loadInt(100)) {
            // If a block is spliced, its entire body is copied as well
            b.binary(f, f2, with: .Add)
        }
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testBasicSplicing4() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let f1 = b.buildPlainFunction(with: .parameters(n: 1)) { args1 in
            let f2 = b.buildPlainFunction(with: .parameters(n: 1)) { args2 in
                let s = b.binary(args1[0], args2[0], with: .Add)
                b.doReturn(s)
            }
            let one = b.loadInt(1)
            let r = b.callFunction(f2, withArgs: args1 + [one])
            b.doReturn(r)
        }
        let zero = b.loadInt(0)
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(f1, withArgs: [zero])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(original, actual)
    }

    func testBasicSplicing5() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        // The whole function is included due to the data dependencies on the parameters
        let f = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            let t1 = b.binary(args[0], args[1], with: .Mul)
            let t2 = b.binary(t1, args[2], with: .Add)
            let print = b.loadBuiltin("print")
            splicePoint = b.indexOfNextInstruction()
            b.callFunction(print, withArgs: [t2])
        }
        let one = b.loadInt(1)
        let two = b.loadInt(2)
        let three = b.loadInt(3)
        b.callFunction(f, withArgs: [one, two, three])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildPlainFunction(with: .parameters(n: 3)) { args in
            let t1 = b.binary(args[0], args[1], with: .Mul)
            let t2 = b.binary(t1, args[2], with: .Add)
            let print = b.loadBuiltin("print")
            b.callFunction(print, withArgs: [t2])
        }
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testBasicSplicing6() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var n = b.loadInt(10)
        var f = Variable(number: 1)      // Need to declare this up front as the builder interface doesn't support recursive calls
        // The whole function is included due to the recursive call
        f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            b.buildIfElse(n, ifBody: {
                b.unary(.PostDec, n)
                let r = b.callFunction(f, withArgs: [])
                let two = b.loadInt(2)
                splicePoint = b.indexOfNextInstruction()
                let v = b.binary(r, two, with: .Mul)
                b.doReturn(v)
            }, elseBody: {
                let one = b.loadInt(1)
                b.doReturn(one)
            })
        }
        XCTAssertEqual(f.number, 1)
        b.callFunction(f, withArgs: [])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected program
        //
        n = b.loadInt(10)
        f = Variable(number: 1)
        f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            b.buildIfElse(n, ifBody: {
                b.unary(.PostDec, n)
                let r = b.callFunction(f, withArgs: [])
                let two = b.loadInt(2)
                splicePoint = b.indexOfNextInstruction()
                let v = b.binary(r, two, with: .Mul)
                b.doReturn(v)
            }, elseBody: {
                let one = b.loadInt(1)
                b.doReturn(one)
            })
        }
        XCTAssertEqual(f.number, 1)
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testBasicSplicing7() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        b.buildAsyncFunction(with: .parameters(n: 0)) { _ in
            let promise = b.loadBuiltin("ThePromise")
            splicePoint = b.indexOfNextInstruction()
            b.await(promise)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        // This should fail: we cannot splice the Await as it required .async context.
        XCTAssertFalse(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        XCTAssertEqual(b.indexOfNextInstruction(), 0)
        b.buildAsyncFunction(with: .parameters(n: 1)) { args in
            // This should work however.
            b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildAsyncFunction(with: .parameters(n: 1)) { args in
            let promise = b.loadBuiltin("ThePromise")
            b.await(promise)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testBasicSplicing8() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let promise = b.loadBuiltin("ThePromise")
        let f = b.buildAsyncFunction(with: .parameters(n: 0)) { _ in
            let v = b.await(promise)
            let zero = b.loadInt(0)
            let c = b.compare(v, with: zero, using: .notEqual)
            b.buildIfElse(c, ifBody: {
                splicePoint = b.indexOfNextInstruction()
                b.unary(.PostDec, v)
            }, elseBody: {})
        }
        b.callFunction(f, withArgs: [])
        let original = b.finalize()

        //
        // Actual Program
        //
        XCTAssertFalse(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        b.buildAsyncFunction(with: .parameters(n: 2)) { _ in
            b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        }
        let actual = b.finalize()

        //
        // Expected Program
        //

        b.buildAsyncFunction(with: .parameters(n: 2)) { _ in
            let promise = b.loadBuiltin("ThePromise")
            let v = b.await(promise)
            b.unary(.PostDec, v)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testBasicSplicing9() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            let s1 = b.loadString("foo")
            b.buildTryCatchFinally(tryBody: {
                let s2 = b.loadString("bar")
                splicePoint = b.indexOfNextInstruction()
                let s3 = b.binary(s1, s2, with: .Add)
                b.yield(s3)
            }, catchBody: { e in
                b.yield(e)
            })
            let s4 = b.loadString("baz")
            b.yield(s4)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        let s1 = b.loadString("foo")
        let s2 = b.loadString("bar")
        b.binary(s1, s2, with: .Add)
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testBasicSplicing10() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let foo = b.loadString("foo")
        let bar = b.loadString("bar")
        let baz = b.loadString("baz")
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(foo)
            b.buildTryCatchFinally(tryBody: {
                b.throwException(bar)
            }, catchBody: { e in
                splicePoint = b.indexOfNextInstruction()
                b.yield(e)
            })
            b.yield(baz)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(1337))
            b.splice(from: original, at: splicePoint, mergeDataFlow: false)
            b.yield(b.loadInt(1338))
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(1337))
            let bar = b.loadString("bar")
            b.buildTryCatchFinally(tryBody: {
                b.throwException(bar)
            }, catchBody: { e in
                splicePoint = b.indexOfNextInstruction()
                b.yield(e)
            })
            b.yield(b.loadInt(1338))
        }
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testBasicSplicing11() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        // This entire function will be included due to data dependencies on its parameter.
        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
                let i = b.loadInt(0)
                b.buildWhileLoop(i, .lessThan, b.loadInt(100)) {
                    splicePoint = b.indexOfNextInstruction()
                    b.buildIfElse(args[0], ifBody: {
                        b.yield(i)
                    }, elseBody: {
                        b.loopContinue()
                    })
                    b.unary(.PostInc, i)
                }
            }
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(1337))
            let i = b.loadInt(100)
            b.buildWhileLoop(i, .greaterThan, b.loadInt(0)) {
                b.splice(from: original, at: splicePoint, mergeDataFlow: false)
                b.unary(.PostDec, i)
            }
            b.yield(b.loadInt(1338))
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(1337))
            let i = b.loadInt(100)
            b.buildWhileLoop(i, .greaterThan, b.loadInt(0)) {
                b.buildPlainFunction(with: .parameters(n: 1)) { args in
                    b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
                        let i = b.loadInt(0)
                        b.buildWhileLoop(i, .lessThan, b.loadInt(100)) {
                            splicePoint = b.indexOfNextInstruction()
                            b.buildIfElse(args[0], ifBody: {
                                b.yield(i)
                            }, elseBody: {
                                b.loopContinue()
                            })
                            b.unary(.PostInc, i)
                        }
                    }
                }
                b.unary(.PostDec, i)
            }
            b.yield(b.loadInt(1338))
        }
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testDataflowSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let p = b.loadBuiltin("ThePromise")
        let f = b.buildAsyncFunction(with: .parameters(n: 0)) { args in
            let v = b.await(p)
            let print = b.loadBuiltin("print")
            splicePoint = b.indexOfNextInstruction()
            // We can only splice this if we replace |v| with another variable in the host program
            b.callFunction(print, withArgs: [v])
        }
        b.callFunction(f, withArgs: [])
        let original = b.finalize()

        //
        // Result Program
        //
        b.loadInt(1337)
        b.loadString("Foobar")
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        let result = b.finalize()
        XCTAssertFalse(result.code.contains(where: { $0.op is Await }))
        XCTAssert(result.code.contains(where: { $0.op is CallFunction }))
    }

    func testDataflowSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let f = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            let t1 = b.binary(args[0], args[1], with: .Add)
            splicePoint = b.indexOfNextInstruction()
            let t2 = b.binary(t1, args[2], with: .Add)
            b.doReturn(t2)
        }
        var s1 = b.loadString("Foo")
        var s2 = b.loadString("Bar")
        var s3 = b.loadString("Baz")
        b.callFunction(f, withArgs: [s1, s2, s3])
        let original = b.finalize()

        //
        // Result Program
        //
        s1 = b.loadString("A")
        s2 = b.loadString("B")
        s3 = b.loadString("C")
        b.splice(from: original, at: splicePoint, mergeDataFlow: true)
        let result = b.finalize()

        // Either the BeginPlainFunction has been omitted (in which case the parameter usages must have been remapped to an existing variable), or the BeginPlainFunction is included and none of the parameter usages have been remapped.
        let didSpliceFunction = result.code.contains(where: { $0.op is BeginPlainFunction })
        let existingVariables = [s1, s2, s3]
        if didSpliceFunction {
            for instr in result.code where instr.op is BinaryOperation {
                XCTAssert(instr.inputs.allSatisfy({ !existingVariables.contains($0) }))
            }
        }
    }

    func testDataflowSplicing3() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let v = b.loadInt(42)
        let name = b.loadString("foo")
        let obj = b.createObject(with: [:])
        splicePoint = b.indexOfNextInstruction()
        b.storeComputedProperty(v, as: name, on: obj)
        let original = b.finalize()

        // If we set the probability of remapping a variables outputs during splicing to 100% we expect
        // the slices to just contain a single instruction.
        XCTAssertGreaterThan(b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing, 0.0)
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0

        b.loadInt(1337)
        b.loadString("bar")
        b.createObject(with: [:])
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        let result = b.finalize()

        XCTAssertEqual(result.size, 4)
        XCTAssert(result.code.lastInstruction.op is StoreComputedProperty)
    }

    func testDataflowSplicing4() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let f = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            let Array = b.loadBuiltin("Array")
            splicePoint = b.indexOfNextInstruction()
            b.callMethod("of", on: Array, withArgs: args)
        }
        let i1 = b.loadInt(42)
        let i2 = b.loadInt(43)
        let i3 = b.loadInt(44)
        b.callFunction(f, withArgs: [i1, i2, i3])
        let original = b.finalize()

        // When splicing from the method call, we expect to omit the function definition in many cases and
        // instead remap the parameters to existing variables in the host program. Otherwise, we'd end up
        // with a function that's never called.
        // To test this reliably, we set the probability of remapping inner outputs to 100% but also check
        // that it is reasonably high by default.
        XCTAssertGreaterThanOrEqual(b.probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing, 0.5)
        b.probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing = 1.0

        b.loadString("Foo")
        b.loadString("Bar")
        b.loadString("Baz")
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        let result = b.finalize()

        XCTAssert(result.code.contains(where: { $0.op is CallMethod }))
        XCTAssertFalse(result.code.contains(where: { $0.op is BeginPlainFunction }))
    }

    func testDataflowSplicing5() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var f = Variable(number: 0)
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let n = args[0]
            let zero = b.loadInt(0)
            let one = b.loadInt(1)
            let c = b.compare(n, with: zero, using: .greaterThan)
            b.buildIfElse(c, ifBody: {
                let nMinusOne = b.binary(n, one, with: .Sub)
                let t = b.callFunction(f, withArgs: [nMinusOne])
                splicePoint = b.indexOfNextInstruction()
                let r = b.binary(n, t, with: .Mul)
                b.doReturn(r)
            }, elseBody: {
                b.doReturn(one)
            })
        }
        XCTAssertEqual(f.number, 0)
        let i = b.loadInt(42)
        b.callFunction(f, withArgs: [i])
        let original = b.finalize()

        //
        // Actual Program
        //
        // Here, even if we replace all parameters of the function, we still include it due to the recursive call.
        // In that case, we expect none of the parameter usages to have been replaced as the parameters are available.
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 0.0
        b.probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing = 1.0

        b.loadInt(1337)
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.loadInt(1337)
        f = Variable(number: 1)
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let n = args[0]
            let zero = b.loadInt(0)
            let one = b.loadInt(1)
            let c = b.compare(n, with: zero, using: .greaterThan)
            b.buildIfElse(c, ifBody: {
                let nMinusOne = b.binary(n, one, with: .Sub)
                let t = b.callFunction(f, withArgs: [nMinusOne])
                splicePoint = b.indexOfNextInstruction()
                let r = b.binary(n, t, with: .Mul)
                b.doReturn(r)
            }, elseBody: {
                b.doReturn(one)
            })
        }
        XCTAssertEqual(f.number, 1)
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testDataflowSplicing6() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let print = b.loadBuiltin("print")
            b.callFunction(print, withArgs: args)
        }
        var n = b.loadInt(1337)
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(f, withArgs: [n])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0

        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let two = b.loadInt(2)
            let r = b.binary(args[0], two, with: .Mul)
            b.doReturn(r)
        }
        b.loadInt(42)
        b.splice(from: original, at: splicePoint, mergeDataFlow: true)
        let actual = b.finalize()

        //
        // Expected Program
        //
        // Variables should be remapped to variables of the same type (unless there are none).
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let two = b.loadInt(2)
            let r = b.binary(args[0], two, with: .Mul)
            b.doReturn(r)
        }
        n = b.loadInt(42)
        b.callFunction(f, withArgs: [n])
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testFunctionSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        b.loadString("foo")
        var i1 = b.loadInt(42)
        var f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let i3 = b.binary(i1, args[0], with: .Add)
            b.doReturn(i3)
        }
        b.loadString("bar")
        var i2 = b.loadInt(43)
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(f, withArgs: [i2])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        i1 = b.loadInt(42)
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let i3 = b.binary(i1, args[0], with: .Add)
            b.doReturn(i3)
        }
        i2 = b.loadInt(43)
        b.callFunction(f, withArgs: [i2])
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testFunctionSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        var f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let step = b.loadInt(1)
            splicePoint = b.indexOfNextInstruction()
            b.buildForLoop(args[0], .lessThan, args[1], .Add, step) { _ in
                b.loopBreak()
            }
        }
        let arg1 = b.loadInt(42)
        let arg2 = b.loadInt(43)
        b.callFunction(f, withArgs: [arg1, arg2])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let step = b.loadInt(1)
            splicePoint = b.indexOfNextInstruction()
            b.buildForLoop(args[0], .lessThan, args[1], .Add, step) { _ in
                b.loopBreak()
            }
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testSplicingOfMutatingOperations() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        XCTAssertGreaterThan(b.probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable, 0.0)
        b.probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 1.0

        //
        // Original Program
        //
        var f2 = b.loadFloat(13.37)
        b.buildPlainFunction(with: .parameters(n: 1)) { args in
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

        //
        // Actual Program
        //
        let idx = original.code.lastInstruction.index - 1
        XCTAssert(original.code[idx].op is CallMethod)
        b.splice(from: original, at: idx)
        let actual = b.finalize()

        //
        // Expected Program
        //
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
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testClassSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        // We enable conservative mode to exercise the canMutate checks within the splice loop
        b.mode = .conservative

        //
        // Original Program
        //
        var superclass = b.buildClass() { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { params in
            }

            cls.defineProperty("a")

            cls.defineMethod("f", with: .parameters(n: 1)) { params in
                b.doReturn(b.loadString("foobar"))
            }
        }
        let _ = b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { params in
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

            cls.defineMethod("g", with: .parameters(n: 1)) { params in
                b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                }
            }
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        superclass = b.buildClass() { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { params in
            }
        }
        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { _ in
                // Splicing at CallSuperConstructor
                b.splice(from: original, at: splicePoint, mergeDataFlow: false)
            }
        }

        let actual = b.finalize()

        //
        // Expected Program
        //
        superclass = b.buildClass() { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { params in
            }
        }
        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: .parameters(n: 1)) { _ in
                let v0 = b.loadInt(42)
                let v1 = b.createObject(with: ["foo": v0])
                b.callSuperConstructor(withArgs: [v1])
            }
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testAsyncGeneratorSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        b.buildAsyncGeneratorFunction(with: .parameters(n: 2)) { _ in
            let v3 = b.loadInt(0)
            let v4 = b.loadInt(2)
            let v5 = b.loadInt(1)
            b.buildForLoop(v3, .lessThan, v4, .Add, v5) { _ in
                let v0 = b.loadInt(42)
                let _ = b.createObject(with: ["foo": v0])
                splicePoint = b.indexOfNextInstruction()
                b.await(v3)
                let v8 = b.loadInt(1337)
                b.yield(v8)
            }
            b.doReturn(v4)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.buildAsyncFunction(with: .parameters(n: 1)) { _ in
            // Splicing at Await
            b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildAsyncFunction(with: .parameters(n: 1)) { _ in
            let v0 = b.loadInt(0)
            let _ = b.await(v0)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testLoopSplicing1() {
        var splicePoint = -1, invalidSplicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let i = b.loadInt(0)
        let end = b.loadInt(100)
        b.buildWhileLoop(i, .lessThan, end) {
            let i2 = b.loadInt(0)
            let end2 = b.loadInt(10)
            splicePoint = b.indexOfNextInstruction()
            b.buildWhileLoop(i2, .lessThan, end2) {
                let mid = b.binary(end2, b.loadInt(2), with: .Div)
                let cond = b.compare(i2, with: mid, using: .greaterThan)
                b.buildIfElse(cond, ifBody: {
                    b.loopContinue()
                }, elseBody: {
                    invalidSplicePoint = b.indexOfNextInstruction()
                    b.loopBreak()
                })
                b.unary(.PostInc, i2)
            }
            b.unary(.PostInc, i)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        XCTAssertFalse(b.splice(from: original, at: invalidSplicePoint, mergeDataFlow: false))
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        let actual = b.finalize()

        //
        // Expected Program
        //
        let i2 = b.loadInt(0)
        let end2 = b.loadInt(10)
        b.buildWhileLoop(i2, .lessThan, end2) {
            let mid = b.binary(end2, b.loadInt(2), with: .Div)
            let cond = b.compare(i2, with: mid, using: .greaterThan)
            b.buildIfElse(cond, ifBody: {
                b.loopContinue()
            }, elseBody: {
                b.loopBreak()
            })
            b.unary(.PostInc, i2)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testLoopSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        let start = b.loadInt(100)
        let end = b.loadInt(100)
        let i = b.dup(start)
        // A loop is considered to mutate its run variable
        b.buildWhileLoop(i, .lessThan, end) {
            let two = b.loadInt(2)
            splicePoint = b.indexOfNextInstruction()
            b.binary(i, two, with: .Mod)
            b.unary(.PostInc, i)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 1.0
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testForInSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        b.loadString("unused")
        var i = b.loadInt(10)
        var s = b.loadString("Bar")
        var f = b.loadFloat(13.37)
        var o1 = b.createObject(with: ["foo": i, "bar": s, "baz": f])
        b.loadString("unused")
        var o2 = b.createObject(with: [:])
        b.buildForInLoop(o1) { p in
            let i = b.loadInt(1337)
            b.loadString("unusedButPartOfBody")
            splicePoint = b.indexOfNextInstruction()
            b.storeComputedProperty(i, as: p, on: o2)
        }
        b.loadString("unused")
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        i = b.loadInt(10)
        s = b.loadString("Bar")
        f = b.loadFloat(13.37)
        o1 = b.createObject(with: ["foo": i, "bar": s, "baz": f])
        o2 = b.createObject(with: [:])
        b.buildForInLoop(o1) { p in
            let i = b.loadInt(1337)
            b.loadString("unusedButPartOfBody")
            b.storeComputedProperty(i, as: p, on: o2)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testTryCatchSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        let s = b.loadString("foo")
        b.buildTryCatchFinally(tryBody: {
            let v = b.loadString("bar")
            b.throwException(v)
        }, catchBody: { e in
            splicePoint = b.indexOfNextInstruction()
            b.reassign(e, to: s)
        })
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testCodeStringSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
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

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        //
        // Expected Program
        //
        let code = b.buildCodeString() {
                let i = b.loadInt(42)
                let o = b.createObject(with: ["i": i])
                let json = b.loadBuiltin("JSON")
                b.callMethod("stringify", on: json, withArgs: [o])
            }
        let eval = b.reuseOrLoadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testSwitchBlockSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        let i1 = b.loadInt(1)
        let i2 = b.loadInt(2)
        let i3 = b.loadInt(3)
        let s = b.loadString("Foo")
        splicePoint = b.indexOfNextInstruction()
        b.buildSwitch(on: i1) { cases in
            cases.add(i2) {
                b.reassign(s, to: b.loadString("Bar"))
            }
            cases.add(i3) {
                b.reassign(s, to: b.loadString("Baz"))
            }
            cases.addDefault {
                b.reassign(s, to: b.loadString("Bla"))
            }
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testSwitchBlockSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.mode = .conservative

        //
        // Original Program
        //
        var i1 = b.loadInt(1)
        var i2 = b.loadInt(2)
        var i3 = b.loadInt(3)
        var s = b.loadString("Foo")
        b.buildSwitch(on: i1) { cases in
            cases.add(i2) {
                b.reassign(s, to: b.loadString("Bar"))
            }
            cases.add(i3) {
                b.reassign(s, to: b.loadString("Baz"))
            }
            cases.addDefault {
                b.reassign(s, to: b.loadString("Bla"))
            }
        }
        let original = b.finalize()
        splicePoint = original.code.firstIndex(where: { $0.op is BeginSwitchCase })!

        //
        // Result Program
        //
        // Splicing a BeginSwitchCase is not possible here as we don't (yet) have a BeginSwitch.
        XCTAssertFalse(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        i1 = b.loadInt(10)
        i2 = b.loadInt(20)
        i3 = b.loadInt(30)
        s = b.loadString("Fizz")
        b.buildSwitch(on: i1) { cases in
            // Splicing will only be possible if we allow variables from the original program
            // to be remapped to variables in the host program, so set mergeDataFlow to true.
            XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
            XCTAssert(b.splice(from: original, mergeDataFlow: true))
        }
        let result = b.finalize()
        XCTAssert(result.code.contains(where: { $0.op is BeginSwitchCase }))
        // We must not splice default cases. Otherwise we may end up with multiple default cases, which is forbidden.
        XCTAssertFalse(result.code.contains(where: { $0.op is BeginSwitchDefaultCase }))
    }
}
