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
            b.buildPrefix()
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

    func testValueBuilding() {
        // Test that buildValues() is always possible and generates at least the requested
        // number of new variables.
        // For this test, we need the full JavaScript environment so that the typer has type
        // information for builtin objects like the TypedArray constructors.
        let env = JavaScriptEnvironment()
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        for _ in 0..<100 {
            XCTAssertEqual(b.numberOfVisibleVariables, 0)

            // Run a single value generator.
            let (numberOfGeneratedInstructions, numberOfGeneratedVariables) = b.buildValues(1)

            // Currently the following holds since ValueGenerators never emit instructions with multiple outputs.
            XCTAssertGreaterThanOrEqual(numberOfGeneratedInstructions, numberOfGeneratedVariables)

            // Must now have at least the requested number of visible variables.
            XCTAssertGreaterThanOrEqual(b.numberOfVisibleVariables, 1)
            XCTAssertEqual(b.numberOfVisibleVariables, numberOfGeneratedVariables)

            // The types of all variables created by a ValueGenerator must be statically inferrable.
            // However, it is not guaranteed that, after running more than one value generator, all
            // newly created variables have a known type. For example, it can happen that a recursive
            // value generator generates a reassignment of a variable created by a previous value
            // generator. As that should be rare in practice, we don't care too much about that though.
            for v in b.visibleVariables {
                XCTAssertNotEqual(b.type(of: v), .anything)
            }

            let _ = b.finalize()
        }
    }

    func testPrefixBuilding() {
        // We expect program prefixes (used e.g. for bootstraping code generation but also
        // by the mutation engine) to produce at least a handful of variables for following
        // code to operate on.
        // Internally, prefix generation relies on the value generators tested above.
        let env = JavaScriptEnvironment()
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        b.buildPrefix()

        XCTAssertGreaterThanOrEqual(b.numberOfVisibleVariables, 5)
    }

    func testShapeOfGeneratedCode1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let simpleGenerator = ValueGenerator("SimpleGenerator") { b, _ in
            b.loadInt(Int64.random(in: 0..<100))
        }
        fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
            (simpleGenerator,      1),
        ]))

        for _ in 0..<10 {
            b.buildPrefix()
            let prefixSize = b.currentNumberOfInstructions
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            // In this case, the size of the generated code must be exactly the requested size.
            XCTAssertEqual(program.size - prefixSize, 100)
        }
    }

    func testShapeOfGeneratedCode2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.minRecursiveBudgetRelativeToParentBudget = 0.25
        b.maxRecursiveBudgetRelativeToParentBudget = 0.25

        let simpleGenerator = ValueGenerator("SimpleGenerator") { b, _ in
            b.loadInt(Int64.random(in: 0..<100))
        }
        let recursiveGenerator = RecursiveCodeGenerator("RecursiveGenerator") { b in
            b.buildRepeatLoop(n: 5) { _ in
                b.buildRecursive()
            }
        }
        fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
            (simpleGenerator,      3),
            (recursiveGenerator,   1),
        ]))

        for _ in 0..<10 {
            b.buildPrefix()
            let prefixSize = b.currentNumberOfInstructions
            b.build(n: 100, by: .generating)
            let program = b.finalize()

            // Uncomment to see the "shape" of generated programs on the console.
            //print(FuzzILLifter().lift(program))

            // The size may be larger, but only roughly by 100 * 0.25 + 100 * 0.25**2 + 100 * 0.25**3 ... (each block may overshoot its budget by roughly the maximum recursive block size).
            XCTAssertLessThan(program.size - prefixSize, 150)
        }
    }

    func testVariableRetrieval1() {
        // This testcase demonstrates the behavior of `b.randomVariable(forUseAs:)`
        // This API behaves in the following way:
        //  - It prefers to return variables that are known to have the requested type
        //    with probability `b.probabilityOfVariableSelectionTryingToFindAnExactMatch`,
        //    but only if there's a sufficient number of them currently visible (to ensure
        //    that consecutive queries return different variables. This threshold is
        //    determined by `b.minVisibleVariablesOfRequestedTypeForVariableSelection`.
        //  - Otherwise, it tries a wider match, including all variables that may have the
        //    requested type. This includes all variables that have unknown type.
        //  - If even that doesn't find any matches, the function will return a random
        //    variable that is known to _not_ have the requested type. This should be
        //    rare though.

        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(42)
        // There is only one visible variable, so we always get that, no matter what we actually query
        XCTAssertLessThan(b.numberOfVisibleVariables, b.minVisibleVariablesOfRequestedTypeForVariableSelection)
        XCTAssertEqual(b.randomVariable(forUseAs: .integer), i)
        XCTAssertEqual(b.randomVariable(forUseAs: .anything), i)
        XCTAssertEqual(b.randomVariable(forUseAs: .string), i)

        // Now there's also a string variable. Now, when asking for e.g. an integer, we will not get the string
        // variable as that is known to have a different type.
        let s = b.loadString("foobar")
        XCTAssertEqual(b.randomVariable(forUseAs: .integer), i)
        XCTAssert([i, s].contains(b.randomVariable(forUseAs: .primitive)))
        XCTAssertEqual(b.randomVariable(forUseAs: .string), s)

        // Now there's also a variable of unknown type, which may be anything. Since we don't have enough variables
        // of a known type, all queries will use a `MayBe` type query to find matches and so may return the unknown variable.
        let unknown = b.createNamedVariable(forBuiltin: "unknown")
        XCTAssertEqual(b.type(of: unknown), .anything)

        XCTAssert([i, unknown].contains(b.randomVariable(forUseAs: .integer)))
        XCTAssert([i, unknown].contains(b.randomVariable(forUseAs: .number)))
        XCTAssert([s, unknown].contains(b.randomVariable(forUseAs: .string)))
        XCTAssert([i, s, unknown].contains(b.randomVariable(forUseAs: .primitive)))
        XCTAssert([i, s, unknown].contains(b.randomVariable(forUseAs: .anything)))

        // Now we add some more integers and set the probability of trying an exact match (i.e. an `Is` query instead of a
        // `MayBe` query) to 100%. Then, we expect to always get back the known integers when asking for them.
        let i2 = b.loadInt(43)
        let i3 = b.loadInt(44)
        XCTAssertGreaterThanOrEqual(b.numberOfVisibleVariables, b.minVisibleVariablesOfRequestedTypeForVariableSelection)
        b.probabilityOfVariableSelectionTryingToFindAnExactMatch = 1.0
        // Now we should always get back the integer when querying for that type.
        XCTAssert([i, i2, i3].contains(b.randomVariable(forUseAs: .integer)))
        XCTAssert([i, i2, i3].contains(b.randomVariable(forUseAs: .number)))
        // We don't have enough strings yet though.
        XCTAssert([s, unknown].contains(b.randomVariable(forUseAs: .string)))
        // But enough primitive values.
        XCTAssert([i, i2, i3, s].contains(b.randomVariable(forUseAs: .primitive)))
        XCTAssert([i, i2, i3, s, unknown].contains(b.randomVariable(forUseAs: .anything)))
    }

    func testVariableRetrieval2() {
        // This testcase demonstrates the behavior of `b.randomVariable(ofType:)`
        // This API will always return a variable for which `type(of: v).Is(requestedType)` is true,
        // i.e. for which we can statically infer that the variable has the requested type.

        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        XCTAssertEqual(b.randomVariable(ofType: .integer), v)
        XCTAssertEqual(b.randomVariable(ofType: .number), v)
        XCTAssertEqual(b.randomVariable(ofType: .anything), v)
        XCTAssertEqual(b.randomVariable(ofType: .string), nil)

        let s = b.loadString("foobar")
        XCTAssertEqual(b.randomVariable(ofType: .integer), v)
        XCTAssertEqual(b.randomVariable(ofType: .number), v)
        XCTAssert([v, s].contains(b.randomVariable(ofType: .primitive)))
        XCTAssert([v, s].contains(b.randomVariable(ofType: .anything)))
        XCTAssertEqual(b.randomVariable(ofType: .string), s)

        let _ = b.finalize()

        let unknown = b.createNamedVariable(forBuiltin: "unknown")
        XCTAssertEqual(b.type(of: unknown), .anything)
        XCTAssertEqual(b.randomVariable(ofType: .integer), nil)
        XCTAssertEqual(b.randomVariable(ofType: .number), nil)
        XCTAssertEqual(b.randomVariable(ofType: .anything), unknown)

        let _ = b.finalize()

        let n = b.createNamedVariable(forBuiltin: "theNumber")
        b.setType(ofVariable: n, to: .number)
        XCTAssertEqual(b.type(of: n), .number)
        XCTAssertEqual(b.randomVariable(ofType: .integer), nil)
        XCTAssertEqual(b.randomVariable(ofType: .string), nil)
        XCTAssertEqual(b.randomVariable(ofType: .number), n)
        XCTAssertEqual(b.randomVariable(ofType: .primitive), n)
    }

    func testVariableRetrieval3() {
        // This testcase demonstrates the behavior of `b.randomVariable(preferablyNotOfType:)`
        // This API will always return a variable for which `type(of: v).Is(requestedType)` is false,
        // i.e. for which we cannot statically infer that the variable has the requested type.

        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .nothing), v)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .string), v)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .integer), nil)

        let s = b.loadString("foobar")
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .integer), s)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .string), v)
        XCTAssert([v, s].contains(b.randomVariable(preferablyNotOfType: .boolean)))
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .primitive), nil)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .anything), nil)

        let unknown = b.createNamedVariable(forBuiltin: "unknown")
        XCTAssertEqual(b.type(of: unknown), .anything)
        XCTAssert([v, unknown].contains(b.randomVariable(preferablyNotOfType: .string)))
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .primitive), unknown)
        XCTAssertEqual(b.randomVariable(preferablyNotOfType: .anything), nil)
    }

    func testRandomVarableInternal() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.blockStatement {
            let var1 = b.loadString("HelloWorld")
            XCTAssertEqual(b.findVariable(satisfying: { $0 == var1 }), var1)
            b.blockStatement {
                let var2 = b.loadFloat(13.37)
                XCTAssertEqual(b.findVariable(satisfying: { $0 == var2 }), var2)
                b.blockStatement {
                    let var3 = b.loadInt(100)
                    XCTAssertEqual(b.findVariable(satisfying: { $0 == var3 }), var3)
                }
            }
        }
    }

    func testVariableHiding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let Math = b.createNamedVariable(forBuiltin: "Math")

        XCTAssert(b.visibleVariables.contains(Math))
        XCTAssertEqual(b.numberOfVisibleVariables, 1)
        // Hide "Math" as it is only a temporary value that shouldn't be used later on
        b.hide(Math)
        XCTAssert(!b.visibleVariables.contains(Math))
        XCTAssertEqual(b.numberOfVisibleVariables, 0)

        let v = b.loadFloat(13.37)
        b.callMethod("log", on: Math, withArgs: [v])
        XCTAssertEqual(b.numberOfVisibleVariables, 2)

        for _ in 0..<10 {
            XCTAssertNotEqual(b.randomVariable(), Math)
        }

        // Make sure the variable stays hidden when entering new scopes.
        b.buildPlainFunction(with: .parameters(n: 2)) { args in
            b.callMethod("log1p", on: Math, withArgs: [v])

            XCTAssert(!b.visibleVariables.contains(Math))
            for _ in 0..<10 {
                XCTAssertNotEqual(b.randomVariable(), Math)
            }

            b.callMethod("log2", on: Math, withArgs: [v])

            XCTAssertEqual(b.numberOfVisibleVariables, 6)
            b.buildRepeatLoop(n: 25) {
                let v2 = b.callMethod("log10", on: Math, withArgs: [v])
                let v3 = b.callMethod("log10", on: Math, withArgs: [v2])
                let v4 = b.callMethod("log10", on: Math, withArgs: [v3])

                XCTAssert(b.visibleVariables.contains(v2))
                XCTAssert(b.visibleVariables.contains(v3))
                XCTAssert(b.visibleVariables.contains(v4))

                // These three variables are hidden but never unhidden.
                // However, once they go out of scope, they should be deleted
                // from the `hiddenVariables` set in the ProgramBuilder.
                XCTAssertEqual(b.numberOfVisibleVariables, 9)
                b.hide(v2)
                b.hide(v3)
                b.hide(v4)
                XCTAssertEqual(b.numberOfVisibleVariables, 6)

                XCTAssert(!b.visibleVariables.contains(Math))
                for _ in 0..<10 {
                    XCTAssertNotEqual(b.randomVariable(), Math)
                    XCTAssertNotEqual(b.randomVariable(), v2)
                    XCTAssertNotEqual(b.randomVariable(), v3)
                    XCTAssertNotEqual(b.randomVariable(), v4)
                }
            }
            XCTAssertEqual(b.numberOfVisibleVariables, 6)

            XCTAssert(!b.visibleVariables.contains(Math))
            for _ in 0..<10 {
                XCTAssertNotEqual(b.randomVariable(), Math)
            }
        }

        XCTAssert(!b.visibleVariables.contains(Math))
        for _ in 0..<10 {
            XCTAssertNotEqual(b.randomVariable(), Math)
        }

        b.unhide(Math)
        XCTAssert(b.visibleVariables.contains(Math))
    }

    func testRecursionGuard() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        XCTAssert(b.enableRecursionGuard)

        // The recursion guard feature of the ProgramBuilder is meant to prevent trivial recursion
        // where a newly created function directly calls itself. It's also meant to prevent somewhat
        // odd code from being generated where operation inside a function's body operate on the function
        // itself. However, the guarding is only active during the initial creation of the function,
        // so future mutations can still build recursive calls etc.
        let functionVar = Variable(number: 0)
        let realFunctionVar = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            // The function variable is hidden during it's initial creation, so that all the code
            // generated for its body doesn't operate on it (and e.g. cause trivial recursion).
            XCTAssertFalse(b.visibleVariables.contains(functionVar))
            XCTAssertNotEqual(b.randomVariable(), functionVar)
            XCTAssertNotEqual(b.randomVariable(ofType: .function()), functionVar)
        }
        XCTAssertEqual(functionVar, realFunctionVar)

        // The function must in any case be visible outside of its body.
        XCTAssert(b.visibleVariables.contains(functionVar))
        XCTAssertEqual(b.randomVariable(ofType: .function()), functionVar)

        let program = b.finalize()

        // However, during later mutations, the function variable is visible and can be used to
        // construct recursive calls. If these calls end up creating infinite recursion (which is
        // fairly likely), the mutation will simply be reverted, so there is not much harm caused.
        for instr in program.code {
            b.append(instr)
            if b.context.contains(.subroutine) {
                // The function variable should now be visible
                XCTAssert(b.visibleVariables.contains(functionVar))
                XCTAssertEqual(b.randomVariable(ofType: .function()), functionVar)
            }
        }
    }

    func testParameterGeneration1() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // No variables are visible, so we expect to generate functions with no parameters
        // (since we otherwise won't have any argument values for calling the function).
        XCTAssertEqual(b.randomParameters().count, 0)

        // But even with a single visible variable, we still expect to generate functions
        // with no parameters since we could only call the function in exactly one way.
        b.loadInt(42)
        XCTAssertEqual(b.randomParameters().count, 0)

        // However, once we have more than one visible variable, we expect to generate functions
        // that take a few parameters, since we now have at least some arugment values.
        b.loadInt(43)
        XCTAssert((1...2).contains(b.randomParameters().count))
        b.loadInt(44)
        b.loadInt(45)
        XCTAssert((1...2).contains(b.randomParameters().count))

        // And once we have plenty of visible variables, we expect to generate functions
        // with multiple parameters.
        b.loadInt(46)
        b.loadInt(47)
        XCTAssert((2...4).contains(b.randomParameters().count))
        b.loadInt(48)
        XCTAssert((2...4).contains(b.randomParameters().count))
    }

    func testParameterGeneration2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.probabilityOfUsingAnythingAsParameterTypeIfAvoidable = 0

        // If we have multiple visible variables of the same type, then we expect
        // generated functions to use this type as parameter type as this ensures
        // that we will be able to call this function in different ways.
        let i = b.loadInt(42)
        b.loadInt(43)
        b.loadInt(44)
        XCTAssertEqual(b.randomParameters(n: 1).parameterTypes[0], .integer)

        // The same is true if we have variables of other types, but not enough to
        // ensure that a function using these types as parameter types can be called
        // with multiple different argument values.
        let s = b.loadString("foo")
        let a = b.createIntArray(with: [1, 2, 3])
        let o = b.createObject(with: [:])
        XCTAssertEqual(b.randomParameters(n: 1).parameterTypes[0], .integer)

        // But as soon as we have a sufficient number of other types as well,
        // we expect those to be used as well.
        b.loadString("bar")
        b.loadString("baz")
        b.createIntArray(with: [4, 5, 6])
        b.createIntArray(with: [7, 8, 9])
        b.createObject(with: [:])
        b.createObject(with: [:])

        let types = [b.type(of: i), b.type(of: s), b.type(of: a), b.type(of: o)]
        var usesOfParameterType = [ILType: Int]()
        for _ in 0..<100 {
            guard case .plain(let paramType) = b.randomParameters(n: 1).parameterTypes[0] else { return XCTFail("Unexpected parameter" )}
            XCTAssert(types.contains(paramType))
            usesOfParameterType[paramType] = (usesOfParameterType[paramType] ?? 0) + 1
        }
        XCTAssert(usesOfParameterType.values.allSatisfy({ $0 > 0 }))

        // However, if we set the probability of using .anything as parameter to 100%, we expect to only see .anything parameters.
        b.probabilityOfUsingAnythingAsParameterTypeIfAvoidable = 1.0
        XCTAssertEqual(b.randomParameters(n: 1).parameterTypes[0], .anything)
        XCTAssertEqual(b.randomParameters(n: 1).parameterTypes[0], .anything)
    }

    func testParameterGeneration3() {
        // A kind of end-to-end example showing how we might generate a function and use the parameters in a useful way.
        // We use the real JavaScriptEnvironment here to make sure that this is also how XYZ
        let env = JavaScriptEnvironment()
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        b.probabilityOfUsingAnythingAsParameterTypeIfAvoidable = 0

        let c = b.buildConstructor(with: .parameters(n: 0)) { args in
            let this = args[0]
            b.setProperty("x", of: this, to: b.loadInt(0))
            b.setProperty("y", of: this, to: b.loadInt(0))
        }

        let p1 = b.construct(c)
        let p2 = b.construct(c)
        let p3 = b.construct(c)
        XCTAssertEqual(b.type(of: p1), .object(withProperties: ["x", "y"]))
        XCTAssertEqual(b.type(of: p1), b.type(of: p2))

        let f1 = b.buildPlainFunction(with: b.randomParameters(n: 1)) { args in
            let p = args[0]
            XCTAssertEqual(b.type(of: p), b.type(of: p1))
            XCTAssertEqual(b.type(of: p).properties, ["x", "y"])
        }
        var args = b.randomArguments(forCalling: f1)
        XCTAssertEqual(args.count, 1)
        XCTAssert([p1, p2, p3].contains(args[0]))

        let _ = b.finalize()

        // Similar example, but with builtin types.
        let a1 = b.createIntArray(with: [1, 2, 3])
        let a2 = b.createIntArray(with: [1, 2, 3])
        let a3 = b.createIntArray(with: [1, 2, 3])

        // Some sanity checks that we get the right kind of object.
        XCTAssert(b.type(of: a1).properties.contains("length"))
        XCTAssert(b.type(of: a1).methods.contains("slice"))

        let f2 = b.buildPlainFunction(with: b.randomParameters(n: 1)) { args in
            let a = args[0]
            XCTAssertEqual(b.type(of: a), b.type(of: a1))
        }
        args = b.randomArguments(forCalling: f2)
        XCTAssertEqual(args.count, 1)
        XCTAssert([a1, a2, a3].contains(args[0]))

        let _ = b.finalize()

        // And another similar example, but this time with a union type: .number
        let Number = b.createNamedVariable(forBuiltin: "Number")
        let n1 = b.getProperty("POSITIVE_INFINITY", of: Number)
        let n2 = b.getProperty("MIN_SAFE_INTEGER", of: Number)
        let n3 = b.getProperty("MAX_SAFE_INTEGER", of: Number)
        XCTAssertEqual(b.type(of: n1), .number)
        XCTAssertEqual(b.type(of: n1), b.type(of: n2))
        XCTAssertEqual(b.type(of: n2), b.type(of: n3))

        let f3 = b.buildPlainFunction(with: b.randomParameters(n: 1)) { args in
            let a = args[0]
            XCTAssertEqual(b.type(of: a), b.type(of: n1))
        }
        args = b.randomArguments(forCalling: f3)
        XCTAssertEqual(args.count, 1)
        XCTAssert([n1, n2, n3].contains(args[0]))
    }

    func testObjectLiteralBuilding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(42)
        let s = b.loadString("baz")
        b.buildObjectLiteral { obj in
            XCTAssertIdentical(obj, b.currentObjectLiteral)

            XCTAssertFalse(obj.properties.contains("foo"))
            obj.addProperty("foo", as: i)
            XCTAssert(obj.properties.contains("foo"))

            XCTAssertFalse(obj.elements.contains(0))
            obj.addElement(0, as: i)
            XCTAssert(obj.elements.contains(0))

            XCTAssertFalse(obj.computedProperties.contains(s))
            obj.addComputedProperty(s, as: i)
            XCTAssert(obj.computedProperties.contains(s))

            XCTAssertFalse(obj.hasPrototype)
            obj.setPrototype(to: i)
            XCTAssert(obj.hasPrototype)

            XCTAssertFalse(obj.methods.contains("bar"))
            obj.addMethod("bar", with: .parameters(n: 0)) { args in }
            XCTAssert(obj.methods.contains("bar"))

            XCTAssertFalse(obj.computedMethods.contains(s))
            obj.addComputedMethod(s, with: .parameters(n: 0)) { args in }
            XCTAssert(obj.computedMethods.contains(s))

            XCTAssertFalse(obj.getters.contains("foobar"))
            obj.addGetter(for: "foobar") { this in }
            XCTAssert(obj.getters.contains("foobar"))

            XCTAssertFalse(obj.setters.contains("foobar"))
            obj.addSetter(for: "foobar") { this, v in }
            XCTAssert(obj.setters.contains("foobar"))

            XCTAssertIdentical(obj, b.currentObjectLiteral)
        }

        let program = b.finalize()
        XCTAssertEqual(program.size, 16)
    }

    func testClassDefinitionBuilding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(42)
        let s = b.loadString("baz")
        let c = b.buildClassDefinition { cls in
            XCTAssertIdentical(cls, b.currentClassDefinition)

            XCTAssertFalse(cls.isDerivedClass)

            XCTAssertFalse(cls.instanceProperties.contains("foo"))
            cls.addInstanceProperty("foo", value: i)
            XCTAssert(cls.instanceProperties.contains("foo"))

            XCTAssertFalse(cls.instanceElements.contains(0))
            cls.addInstanceElement(0)
            XCTAssert(cls.instanceElements.contains(0))

            XCTAssertFalse(cls.instanceComputedProperties.contains(s))
            cls.addInstanceComputedProperty(s, value: i)
            XCTAssert(cls.instanceComputedProperties.contains(s))

            XCTAssertFalse(cls.instanceMethods.contains("bar"))
            cls.addInstanceMethod("bar", with: .parameters(n: 0)) { args in }
            XCTAssert(cls.instanceMethods.contains("bar"))

            XCTAssertFalse(cls.instanceGetters.contains("foobar"))
            cls.addInstanceGetter(for: "foobar") { this in }
            XCTAssert(cls.instanceGetters.contains("foobar"))

            XCTAssertFalse(cls.instanceSetters.contains("foobar"))
            cls.addInstanceSetter(for: "foobar") { this, v in }
            XCTAssert(cls.instanceSetters.contains("foobar"))

            XCTAssertFalse(cls.staticProperties.contains("foo"))
            cls.addStaticProperty("foo", value: i)
            XCTAssert(cls.staticProperties.contains("foo"))

            XCTAssertFalse(cls.staticElements.contains(0))
            cls.addStaticElement(0)
            XCTAssert(cls.staticElements.contains(0))

            XCTAssertFalse(cls.staticComputedProperties.contains(s))
            cls.addStaticComputedProperty(s, value: i)
            XCTAssert(cls.staticComputedProperties.contains(s))

            XCTAssertFalse(cls.staticMethods.contains("bar"))
            cls.addStaticMethod("bar", with: .parameters(n: 0)) { args in }
            XCTAssert(cls.staticMethods.contains("bar"))

            XCTAssertFalse(cls.staticGetters.contains("foobar"))
            cls.addStaticGetter(for: "foobar") { this in }
            XCTAssert(cls.staticGetters.contains("foobar"))

            XCTAssertFalse(cls.staticSetters.contains("foobar"))
            cls.addStaticSetter(for: "foobar") { this, v in }
            XCTAssert(cls.staticSetters.contains("foobar"))

            // All private fields, regardless of whether they are per-instance or static and whether they are properties or methods use the same
            // namespace and each entry must be unique in that namespace. For example, there cannot be both a `#foo` and `static #foo` field.
            // However, for the purpose of selecting candidates for private property access and private method calls, we also track fields and methods separately.
            XCTAssertFalse(cls.privateFields.contains("ifoo"))
            XCTAssertFalse(cls.privateProperties.contains("ifoo"))
            cls.addPrivateInstanceProperty("ifoo", value: i)
            XCTAssert(cls.privateFields.contains("ifoo"))
            XCTAssert(cls.privateProperties.contains("ifoo"))

            XCTAssertFalse(cls.privateFields.contains("ibar"))
            XCTAssertFalse(cls.privateMethods.contains("ibar"))
            cls.addPrivateInstanceMethod("ibar", with: .parameters(n: 0)) { args in }
            XCTAssert(cls.privateFields.contains("ibar"))
            XCTAssert(cls.privateMethods.contains("ibar"))

            XCTAssertFalse(cls.privateFields.contains("sfoo"))
            XCTAssertFalse(cls.privateProperties.contains("sfoo"))
            cls.addPrivateStaticProperty("sfoo", value: i)
            XCTAssert(cls.privateFields.contains("sfoo"))
            XCTAssert(cls.privateProperties.contains("sfoo"))

            XCTAssertFalse(cls.privateFields.contains("sbar"))
            XCTAssertFalse(cls.privateMethods.contains("sbar"))
            cls.addPrivateStaticMethod("sbar", with: .parameters(n: 0)) { args in }
            XCTAssert(cls.privateFields.contains("sbar"))
            XCTAssert(cls.privateMethods.contains("sbar"))

            XCTAssertEqual(cls.privateProperties, ["ifoo", "sfoo"])
            XCTAssertEqual(cls.privateMethods, ["ibar", "sbar"])

            XCTAssertIdentical(cls, b.currentClassDefinition)
        }

        b.buildClassDefinition(withSuperclass: c) { cls in
            XCTAssert(cls.isDerivedClass)
        }

        b.buildClassDefinition(withSuperclass: nil) { cls in
            XCTAssertFalse(cls.isDerivedClass)
        }

        let program = b.finalize()
        XCTAssertEqual(program.size, 32)
    }

    func testSwitchBlockBuilding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i = b.loadInt(42)
        let v = b.createNamedVariable(forBuiltin: "v")

        b.buildSwitch(on: v) { swtch in
            XCTAssertIdentical(swtch, b.currentSwitchBlock)

            XCTAssertFalse(swtch.hasDefaultCase)
            swtch.addCase(i) {

            }

            XCTAssertFalse(swtch.hasDefaultCase)
            swtch.addDefaultCase {

            }
            XCTAssert(swtch.hasDefaultCase)
        }

        let program = b.finalize()
        XCTAssertEqual(program.size, 8)
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
            let String = b.createNamedVariable(forBuiltin: "String")
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
        let String = b.createNamedVariable(forBuiltin: "String")
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
        b.buildDoWhileLoop(do: {
            b.unary(.PostInc, i)
        }, while: { b.compare(i, with: b.loadInt(44), using: .lessThan) })
        b.loadFloat(13.37)
        var arr = b.createArray(with: [i, i, i])
        b.getProperty("length", of: arr)
        splicePoint = b.indexOfNextInstruction()
        b.callMethod("pop", on: arr)
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
        b.callMethod("pop", on: arr)
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
        b.unary(.PostInc, i)
        arr = b.createArray(with: [i, i, i])
        b.callMethod("pop", on: arr)
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
        b.setProperty("f", of: o, to: f2)
        b.buildWhileLoop({ b.compare(i, with: b.loadInt(100), using: .lessThan) }) {
            b.binary(f, f2, with: .Add)
        }
        b.getProperty("f", of: o)
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
        b.buildWhileLoop({ b.compare(i, with: b.loadInt(100), using: .lessThan) }) {
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
            let print = b.createNamedVariable(forBuiltin: "print")
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
            let print = b.createNamedVariable(forBuiltin: "print")
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
                let r = b.callFunction(f)
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
        b.callFunction(f)
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
                let r = b.callFunction(f)
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
            let promise = b.createNamedVariable(forBuiltin: "ThePromise")
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
            let promise = b.createNamedVariable(forBuiltin: "ThePromise")
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
        let promise = b.createNamedVariable(forBuiltin: "ThePromise")
        let f = b.buildAsyncFunction(with: .parameters(n: 0)) { _ in
            let v = b.await(promise)
            let zero = b.loadInt(0)
            let c = b.compare(v, with: zero, using: .notEqual)
            b.buildIfElse(c, ifBody: {
                splicePoint = b.indexOfNextInstruction()
                b.unary(.PostDec, v)
            }, elseBody: {})
        }
        b.callFunction(f)
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
            let promise = b.createNamedVariable(forBuiltin: "ThePromise")
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
                b.buildWhileLoop({ b.compare(i, with: b.loadInt(100), using: .lessThan) }) {
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
            b.buildWhileLoop({ b.compare(i, with: b.loadInt(0), using: .greaterThan) }) {
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
            b.buildWhileLoop({ b.compare(i, with: b.loadInt(0), using: .greaterThan) }) {
                b.buildPlainFunction(with: .parameters(n: 1)) { args in
                    b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
                        let i = b.loadInt(0)
                        b.buildWhileLoop({ b.compare(i, with: b.loadInt(100), using: .lessThan) }) {
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
        let p = b.createNamedVariable(forBuiltin: "ThePromise")
        let f = b.buildAsyncFunction(with: .parameters(n: 0)) { args in
            let v = b.await(p)
            let print = b.createNamedVariable(forBuiltin: "print")
            splicePoint = b.indexOfNextInstruction()
            // We can only splice this if we replace |v| with another variable in the host program
            b.callFunction(print, withArgs: [v])
        }
        b.callFunction(f)
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
        var i = b.loadInt(42)
        var s = b.loadString("foo")
        var o = b.createObject(with: [:])
        splicePoint = b.indexOfNextInstruction()
        b.setComputedProperty(s, of: o, to: i)
        let original = b.finalize()

        //
        // Actual Program
        //
        // If we set the probability of remapping a variables outputs during splicing to 100% we expect
        // the slices to just contain a single instruction.
        XCTAssertGreaterThan(b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing, 0.0)
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0

        b.loadInt(1337)
        b.loadString("bar")
        b.createObject(with: [:])
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: true))
        let actual = b.finalize()

        //
        // Expected Program
        //
        // In this case, there are compatible variables for all types, so we expect these to be used.
        i = b.loadInt(1337)
        s = b.loadString("bar")
        o = b.createObject(with: [:])
        b.setComputedProperty(s, of: o, to: i)
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testDataflowSplicing4() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let f = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            let Array = b.createNamedVariable(forBuiltin: "Array")
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
            let print = b.createNamedVariable(forBuiltin: "print")
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

        // This function is "compatible" with the original function (also one parameter of type .anything).
        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let two = b.loadInt(2)
            let r = b.binary(args[0], two, with: .Mul)
            // Due to the way remapping is currently implemented, function return values
            // are currently assumed to be .anything when looking for compatible functions.
            b.doReturn(r)
        }
        // This function is not compatible since it requires more parameters.
        b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let r = b.binary(args[0], args[1], with: .Exp)
            b.doReturn(r)
        }
        b.loadInt(42)
        b.splice(from: original, at: splicePoint, mergeDataFlow: true)
        let actual = b.finalize()

        //
        // Expected Program
        //
        // Variables should be remapped to variables of the same type (unless there are none).
        // In this case, the two functions are compatible because their parameter types are
        // identical (both take one .anything parameter).
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let two = b.loadInt(2)
            let r = b.binary(args[0], two, with: .Mul)
            b.doReturn(r)
        }
        b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let r = b.binary(args[0], args[1], with: .Exp)
            b.doReturn(r)
        }
        n = b.loadInt(42)
        b.callFunction(f, withArgs: [n])
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testDataflowSplicing7() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        //
        // Here we have a function with one parameter of type .anything.
        var f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let print = b.createNamedVariable(forBuiltin: "print")
            b.callFunction(print, withArgs: args)
        }
        XCTAssertEqual(b.type(of: f).signature?.parameters, [.anything])
        var n = b.loadInt(1337)
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(f, withArgs: [n])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0
        // In the host program, we have a function with one parameter of an explicit type.
        // For splicint, we therefore won't take this function since it's not guaranteed to be compatible.
        b.buildPlainFunction(with: .parameters(.integer)) { args in
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
        let expected: Program
        // The host function isn't guaranteed to be compatible, so don't take it.
        b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let two = b.loadInt(2)
            let r = b.binary(args[0], two, with: .Mul)
            b.doReturn(r)
        }
        n = b.loadInt(42)
        f = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            let print = b.createNamedVariable(forBuiltin: "print")
            b.callFunction(print, withArgs: args)
        }
        b.callFunction(f, withArgs: [n])
        expected = b.finalize()

        XCTAssertEqual(FuzzILLifter().lift(actual), FuzzILLifter().lift(expected))
        XCTAssertEqual(actual, expected)
    }

    func testDataflowSplicing8() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var i = b.loadInt(42)
        splicePoint = b.indexOfNextInstruction()
        b.unary(.PostInc, i)
        let original = b.finalize()

        //
        // Actual Program
        //
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0

        // For splicing, we will not use a variable of an unknown type as replacement.
        let unknown = b.createNamedVariable(forBuiltin: "unknown")
        XCTAssertEqual(b.type(of: unknown), .anything)
        b.loadBool(true)        // This should also never be used as replacement as it definitely has a different type
        b.splice(from: original, at: splicePoint, mergeDataFlow: true)
        let actual = b.finalize()

        //
        // Expected Program
        //
        let expected: Program
        b.createNamedVariable(forBuiltin: "unknown")
        b.loadBool(true)
        i = b.loadInt(42)
        b.unary(.PostInc, i)
        expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testDataflowSplicing9() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var i1 = b.loadInt(41)
        var i2 = b.loadInt(42)
        splicePoint = b.indexOfNextInstruction()
        b.binary(i1, i2, with: .Exp)
        let original = b.finalize()

        //
        // Actual Program
        //
        b.probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 1.0

        // In this case, all existing variables are known to definitely have a different
        // type than the one we're looking for (.integer) when trying to replace the outputs
        // of the LoadInt operations. In this case we don't replace the outputs in such cases.
        b.loadString("foobar")
        b.loadBool(true)
        b.splice(from: original, at: splicePoint, mergeDataFlow: true)
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.loadString("foobar")
        b.loadBool(true)
        i1 = b.loadInt(41)
        i2 = b.loadInt(42)
        b.binary(i1, i2, with: .Exp)
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testObjectLiteralSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let v = b.loadInt(42)
        let p = b.loadString("foobar")
        let o = b.buildObjectLiteral { obj in
            obj.addElement(0, as: v)
            obj.addComputedProperty(p, as: v)
        }
        splicePoint = b.indexOfNextInstruction()
        b.getProperty("foobar", of: o)
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testObjectLiteralSplicing2() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let v = b.loadInt(42)
        b.buildObjectLiteral { obj in
            obj.addProperty("foo", as: v)
            splicePoint = b.indexOfNextInstruction()
            obj.addGetter(for: "baz") { this in
                b.doReturn(b.loadString("baz"))
            }
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        var foo = b.loadString("foo")
        var bar = b.loadString("bar")
        b.buildObjectLiteral { obj in
            obj.addElement(0, as: foo)
            b.splice(from: original, at: splicePoint, mergeDataFlow: false)
            obj.addElement(1, as: bar)
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        foo = b.loadString("foo")
        bar = b.loadString("bar")
        b.buildObjectLiteral { obj in
            obj.addElement(0, as: foo)
            obj.addGetter(for: "baz") { this in
                b.doReturn(b.loadString(("baz")))
            }
            obj.addElement(1, as: bar)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testObjectLiteralSplicing3() {
        // This tests that the object variable, which is an output of the EndObjectLiteral
        // instruction (not the BeginObjectLiteral!) is properly handled during splicing.
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let o = b.buildObjectLiteral { obj in
                obj.addProperty("x", as: args[0])
                obj.addProperty("y", as: args[1])
            }
            b.doReturn(o)
        }
        let v = b.loadInt(42)
        splicePoint = b.indexOfNextInstruction()
        b.callFunction(f, withArgs: [v, v])
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testClassDefinitionSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let v = b.loadInt(1337)
        let c = b.buildClassDefinition { cls in
            cls.addInstanceProperty("foo", value: v)
            cls.addStaticProperty("bar")
            cls.addInstanceElement(0)
        }
        splicePoint = b.indexOfNextInstruction()
        b.construct(c)
        let original = b.finalize()

        //
        // Actual Program
        //
        b.splice(from: original, at: splicePoint, mergeDataFlow: false)
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testClassDefinitionSplicing2() {
        var splicePoint1 = -1, splicePoint2 = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        b.buildClassDefinition { cls in
            cls.addInstanceProperty("foo")
            cls.addConstructor(with: .parameters(n: 1)) { args in
                let this = args[0]
                b.setProperty("foo", of: this, to: args[1])
            }
            splicePoint1 = b.indexOfNextInstruction()
            cls.addInstanceMethod("bar", with: .parameters(n: 0)) { args in
                let this = args[0]
                let one = b.loadInt(1)
                b.updateProperty("count", of: this, with: one, using: .Add)
            }
            splicePoint2 = b.indexOfNextInstruction()
            cls.addStaticElement(42)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        b.buildClassDefinition { cls in
            b.splice(from: original, at: splicePoint1, mergeDataFlow: false)
            b.splice(from: original, at: splicePoint2, mergeDataFlow: false)
        }
        let actual = b.finalize()

        //
        // Expected Program
        //
        b.buildClassDefinition { cls in
            cls.addInstanceMethod("bar", with: .parameters(n: 0)) { args in
                let this = args[0]
                let one = b.loadInt(1)
                b.updateProperty("count", of: this, with: one, using: .Add)
            }
            cls.addStaticElement(42)
        }
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

        //
        // Original Program
        //
        var f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            splicePoint = b.indexOfNextInstruction()
            b.buildForLoop(i: { args[0] }, { i in b.compare(i, with: args[1], using: .lessThan) }, { i in b.unary(.PostInc, i) }) { i in
                b.callFunction(b.createNamedVariable(forBuiltin: "print"), withArgs: [i])
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
            splicePoint = b.indexOfNextInstruction()
            b.buildForLoop(i: { args[0] }, { i in b.compare(i, with: args[1], using: .lessThan) }, { i in b.unary(.PostInc, i) }) { i in
                b.callFunction(b.createNamedVariable(forBuiltin: "print"), withArgs: [i])
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
            b.setProperty("f", of: o, to: f2)
            let object = b.createNamedVariable(forBuiltin: "Object")
            let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
            b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])
            b.callMethod("defineProperty", on: object, withArgs: [o2, b.loadString("s"), descriptor])
            let json = b.createNamedVariable(forBuiltin: "JSON")
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
        b.setProperty("f", of: o, to: f2)     // (Possibly) mutating instruction must be included
        let object = b.createNamedVariable(forBuiltin: "Object")
        let descriptor = b.createObject(with: ["value": b.loadString("foobar")])
        b.callMethod("defineProperty", on: object, withArgs: [o, b.loadString("s"), descriptor])    // (Possibly) mutating instruction must be included
        let json = b.createNamedVariable(forBuiltin: "JSON")
        b.callMethod("stringify", on: json, withArgs: [o])
        let expected = b.finalize()

        XCTAssertEqual(expected, actual)
    }

    func testClassSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        var superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
            }

            cls.addInstanceProperty("a")

            cls.addInstanceMethod("f", with: .parameters(n: 1)) { params in
                b.doReturn(b.loadString("foobar"))
            }
        }
        let _ = b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
                b.buildRepeatLoop(n: 10) { _ in
                    let v0 = b.loadInt(42)
                    let v1 = b.createObject(with: ["foo": v0])
                    splicePoint = b.indexOfNextInstruction()
                    b.callSuperConstructor(withArgs: [v1])
                }
            }
            cls.addInstanceProperty("b")

            cls.addInstanceMethod("g", with: .parameters(n: 1)) { params in
                b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                }
            }
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
            }
        }
        b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { _ in
                // Splicing at CallSuperConstructor
                b.splice(from: original, at: splicePoint, mergeDataFlow: false)
            }
        }

        let actual = b.finalize()

        //
        // Expected Program
        //
        superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters(n: 1)) { params in
            }
        }
        b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addConstructor(with: .parameters(n: 1)) { _ in
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

        //
        // Original Program
        //
        b.buildAsyncGeneratorFunction(with: .parameters(n: 2)) { _ in
            let p = b.createNamedVariable(forBuiltin: "thePromise")
            b.buildDoWhileLoop(do: {
                let v0 = b.loadInt(42)
                let _ = b.createObject(with: ["foo": v0])
                splicePoint = b.indexOfNextInstruction()
                b.await(p)
                let v8 = b.loadInt(1337)
                b.yield(v8)
            }, while: { b.loadBool(false) })
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
            let p = b.createNamedVariable(forBuiltin: "thePromise")
            let _ = b.await(p)
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
        b.buildWhileLoop({ b.compare(i, with: end, using: .lessThan) }) {
            let i2 = b.loadInt(0)
            let end2 = b.loadInt(10)
            splicePoint = b.indexOfNextInstruction()
            b.buildWhileLoop({ b.compare(i2, with: end2, using: .lessThan) }) {
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
        b.buildWhileLoop({ b.compare(i2, with: end2, using: .lessThan) }) {
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

        //
        // Original Program
        //
        b.buildWhileLoop({
            let c = b.loadBool(true)
            // Test that splicing at the BeginWhileLoopBody works as expected
            splicePoint = b.indexOfNextInstruction()
            return c
        }) {
            let foobar = b.createNamedVariable(forBuiltin: "foobar")
            b.callFunction(foobar)
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        let actual = b.finalize()

        XCTAssertEqual(actual, original)
    }

    func testLoopSplicing3() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        b.buildDoWhileLoop(do: {
            let foo = b.createNamedVariable(forBuiltin: "foo")
            b.callFunction(foo)
        }, while: {
            // Test that splicing out of the header works.
            let bar = b.createNamedVariable(forBuiltin: "bar")
            splicePoint = b.indexOfNextInstruction()
            b.callFunction(bar)
            return b.loadBool(false)
        })
        let original = b.finalize()

        //
        // Actual Program
        //
        XCTAssert(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        let actual = b.finalize()

        //
        // Expected Program
        //
        let bar = b.createNamedVariable(forBuiltin: "bar")
        b.callFunction(bar)
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testForInSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

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
            b.setComputedProperty(p, of: o2, to: i)
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
            b.setComputedProperty(p, of: o2, to: i)
        }
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testTryCatchSplicing() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

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

        //
        // Original Program
        //
        b.buildRepeatLoop(n: 5) { _ in
            b.loadThis()
            let code = b.buildCodeString() {
                let i = b.loadInt(42)
                let o = b.createObject(with: ["i": i])
                let json = b.createNamedVariable(forBuiltin: "JSON")
                b.callMethod("stringify", on: json, withArgs: [o])
            }
            let eval = b.createNamedVariable(forBuiltin: "eval")
            splicePoint = b.indexOfNextInstruction()
            b.callFunction(eval, withArgs: [code])
        }
        let original = b.finalize()

        //
        // Actual Program
        //
        XCTAssertTrue(b.splice(from: original, at: splicePoint, mergeDataFlow: false))
        let actual = b.finalize()

        //
        // Expected Program
        //
        let code = b.buildCodeString() {
            let i = b.loadInt(42)
            let o = b.createObject(with: ["i": i])
            let json = b.createNamedVariable(forBuiltin: "JSON")
            b.callMethod("stringify", on: json, withArgs: [o])
        }
        let eval = b.createNamedVariable(forBuiltin: "eval")
        b.callFunction(eval, withArgs: [code])
        let expected = b.finalize()

        XCTAssertEqual(actual, expected)
    }

    func testSwitchBlockSplicing1() {
        var splicePoint = -1
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        //
        // Original Program
        //
        let i1 = b.loadInt(1)
        let i2 = b.loadInt(2)
        let i3 = b.loadInt(3)
        let s = b.loadString("Foo")
        splicePoint = b.indexOfNextInstruction()
        b.buildSwitch(on: i1) { swtch in
            swtch.addCase(i2) {
                b.reassign(s, to: b.loadString("Bar"))
            }
            swtch.addCase(i3) {
                b.reassign(s, to: b.loadString("Baz"))
            }
            swtch.addDefaultCase {
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

        //
        // Original Program
        //
        var i1 = b.loadInt(1)
        var i2 = b.loadInt(2)
        var i3 = b.loadInt(3)
        var s = b.loadString("Foo")
        b.buildSwitch(on: i1) { swtch in
            swtch.addCase(i2) {
                b.reassign(s, to: b.loadString("Bar"))
            }
            swtch.addCase(i3) {
                b.reassign(s, to: b.loadString("Baz"))
            }
            swtch.addDefaultCase {
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
    }

    func testArgumentGenerationForKnownSignature() {
        let env = JavaScriptEnvironment()
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        b.loadInt(42)

        let constructor = b.createNamedVariable(forBuiltin: "DataView")
        let signature = env.type(ofBuiltin: "DataView").signature!

        let variables = b.findOrGenerateArguments(forSignature: signature)

        XCTAssertTrue(b.type(of: variables[0]).Is(.object(ofGroup: "ArrayBuffer")))
        if (variables.count > 1) {
            XCTAssertTrue(b.type(of: variables[1]).Is(.number))
        }

        b.construct(constructor, withArgs: variables)
    }

    func testArgumentGenerationForKnownSignatureWithLimit() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        b.loadInt(42)

        let typeA: ILType = .object(withProperties: ["a", "b"])
        let typeB: ILType = .object(withProperties: ["c", "d"])
        let typeC: ILType = .object(withProperties: ["e", "f"])

        let signature: Signature = [.plain(typeA), .plain(typeB)] => .undefined
        let signature2: Signature = [.plain(typeC), .plain(typeC)] => .undefined

        var args = b.findOrGenerateArguments(forSignature: signature)
        XCTAssertEqual(args.count, 2)

        // check that args have the right types
        XCTAssert(b.type(of: args[0]).Is(typeA))
        XCTAssert(b.type(of: args[1]).Is(typeB))

        let previous = b.numberOfVisibleVariables

        args = b.findOrGenerateArguments(forSignature: signature2, maxNumberOfVariablesToGenerate: 1)
        XCTAssertEqual(args.count, 2)

        // Ensure first object has the right type, and that we only generated one more variable
        XCTAssert(b.type(of: args[0]).Is(typeC))
        XCTAssertEqual(b.numberOfVisibleVariables, previous + 1)
    }

    func testFindOrGenerateTypeWorksRecursively() {
        // Types
        let jsD8 = ILType.object(ofGroup: "D8", withProperties: ["test"], withMethods: [])
        let jsD8Test = ILType.object(ofGroup: "D8Test", withProperties: ["FastCAPI"], withMethods: [])
        let jsD8FastCAPI = ILType.object(ofGroup: "D8FastCAPI", withProperties: [], withMethods: ["throw_no_fallback", "add_32bit_int"])
        let jsD8FastCAPIConstructor = ILType.constructor(Signature(expects: [], returns: jsD8FastCAPI))

        // Object groups
        let jsD8Group = ObjectGroup(name: "D8", instanceType: jsD8, properties: ["test" : jsD8Test], methods: [:])
        let jsD8TestGroup = ObjectGroup(name: "D8Test", instanceType: jsD8Test, properties: ["FastCAPI": jsD8FastCAPIConstructor], methods: [:])
        let jsD8FastCAPIGroup = ObjectGroup(name: "D8FastCAPI", instanceType: jsD8FastCAPI, properties: [:],
                methods:["throw_no_fallback": Signature(expects: [], returns: ILType.integer),
                        "add_32bit_int": Signature(expects: [Parameter.plain(ILType.integer), Parameter.plain(ILType.integer)], returns: ILType.integer)
            ])
        let additionalObjectGroups = [jsD8Group, jsD8TestGroup, jsD8FastCAPIGroup]

        let env = JavaScriptEnvironment(additionalBuiltins: ["d8" : jsD8], additionalObjectGroups: additionalObjectGroups)
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()
        // This has to generate `new d8.test.D8FastCAPI()`
        let d8FastCAPIObj = b.findOrGenerateType(jsD8FastCAPI)
        XCTAssert(b.type(of: d8FastCAPIObj).Is(jsD8FastCAPI))

        // Check that the intermediate variables were generated as part of the recursion.
        let d8 = b.randomVariable(ofType: jsD8)
        XCTAssert(d8 != nil && b.type(of: d8!).Is(jsD8))

        let d8Test = b.randomVariable(ofType: jsD8Test)
        XCTAssert(d8Test != nil && b.type(of: d8Test!).Is(jsD8Test))
    }

    func testFindOrGenerateTypeWithGlobalConstructor() {
        let objType = ILType.object(ofGroup: "Test", withProperties: [], withMethods: [])
        let constructor = ILType.constructor(Signature(expects: [], returns: objType))

        let testGroup = ObjectGroup(name: "Test", instanceType: objType, properties: [:], methods: [:])

        let env = JavaScriptEnvironment(additionalBuiltins: ["myBuiltin" : constructor], additionalObjectGroups: [testGroup])
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()

        let obj = b.findOrGenerateType(objType)
        XCTAssert(b.type(of: obj).Is(objType))
    }

    func testFindOrGenerateTypeWithMethod() {
        // Types
        let jsD8 = ILType.object(ofGroup: "D8", withProperties: [], withMethods: ["test"])
        let objType = ILType.object(ofGroup: "Test", withProperties: [], withMethods: [])

        // Object groups
        let jsD8Group = ObjectGroup(name: "D8", instanceType: jsD8, properties: [:], methods: ["test" : Signature(expects: [], returns: objType)])

        let testGroup = ObjectGroup(name: "Test", instanceType: objType, properties: [:], methods: [:])

        let env = JavaScriptEnvironment(additionalBuiltins: ["d8" : jsD8], additionalObjectGroups: [jsD8Group, testGroup])
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()

        let obj = b.findOrGenerateType(objType)
        XCTAssert(b.type(of: obj).Is(objType))
    }

    func testRandomVariableOfTypeOrSubtype() {
        let type1 = ILType.object(ofGroup: "group1", withProperties: [], withMethods: [])
        let type2 = ILType.object(ofGroup: "group2", withProperties: [], withMethods: [])
        let type3 = ILType.object(ofGroup: "group3", withProperties: [], withMethods: [])
        let type4 = ILType.object(ofGroup: "group4", withProperties: [], withMethods: [])

        let group1 = ObjectGroup(name: "group1", instanceType: type1, properties: [:], methods: [:])
        let group2 = ObjectGroup(name: "group2", instanceType: type2, properties: [:], methods: [:], parent: "group1")
        let group3 = ObjectGroup(name: "group3", instanceType: type3, properties: [:], methods: [:], parent: "group2")
        let group4 = ObjectGroup(name: "group4", instanceType: type4, properties: [:], methods: [:], parent: "group3")

        let env = JavaScriptEnvironment(additionalBuiltins: ["type3": type3], additionalObjectGroups: [group1, group2, group3, group4])
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()
        let var3 = b.createNamedVariable(forBuiltin: "type3")
        XCTAssert(b.type(of: var3).Is(type3))
        // Get a random variable and then change the type
        let var1 = b.randomVariable(ofTypeOrSubtype: type1)
        XCTAssert(var1 != nil)
        XCTAssert(var1 == var3)
        let var4 = b.randomVariable(ofTypeOrSubtype: type4)
        XCTAssert(var4 == nil)
    }

    func testFindOrGenerateTypeWithSubtype() {
        let type1 = ILType.object(ofGroup: "group1", withProperties: [], withMethods: [])
        let type2 = ILType.object(ofGroup: "group2", withProperties: [], withMethods: [])
        let type3 = ILType.object(ofGroup: "group3", withProperties: [], withMethods: [])
        let type4 = ILType.object(ofGroup: "group4", withProperties: [], withMethods: [])

        let type4Constructor = ILType.constructor([] => type4)

        let group1 = ObjectGroup(name: "group1", instanceType: type1, properties: [:], methods: [:])
        let group2 = ObjectGroup(
            name: "group2", instanceType: type2, properties: [:], methods: [:], parent: "group1")
        let group3 = ObjectGroup(
            name: "group3", instanceType: type3, properties: [:], methods: [:], parent: "group2")
        let group4 = ObjectGroup(
            name: "group4", instanceType: type4, properties: [:], methods: [:], parent: "group3")

        let env = JavaScriptEnvironment(
            additionalBuiltins: ["group4": type4Constructor],
            additionalObjectGroups: [group1, group2, group3, group4])
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()
        // Get a random variable and then change the type

        let obj = b.findOrGenerateType(type1)
        XCTAssert(b.type(of: obj).Is(type4))
    }

    func testFindOrGenerateTypeWithSubtypeWithMethod() {
    let type1 = ILType.object(ofGroup: "group1", withProperties: [], withMethods: [])
    let type2 = ILType.object(ofGroup: "group2", withProperties: [], withMethods: [])
    let type3 = ILType.object(ofGroup: "group3", withProperties: [], withMethods: [])
    let type4 = ILType.object(ofGroup: "group4", withProperties: [], withMethods: ["method3"])

    let type4Constructor = ILType.constructor([] => type4)

    let group1 = ObjectGroup(name: "group1", instanceType: type1, properties: [:], methods: [:])
    let group2 = ObjectGroup(
        name: "group2", instanceType: type2, properties: [:], methods: [:], parent: "group1")
    let group3 = ObjectGroup(
        name: "group3", instanceType: type3, properties: [:], methods: [:], parent: "group2")
    let group4 = ObjectGroup(
        name: "group4", instanceType: type4, properties: [:],
        methods: [
        "method3": [] => type3
        ])

    let env = JavaScriptEnvironment(
        additionalBuiltins: ["group4": type4Constructor],
        additionalObjectGroups: [group1, group2, group3, group4])
    let config = Configuration(logLevel: .error)
    let fuzzer = makeMockFuzzer(config: config, environment: env)
    let b = fuzzer.makeBuilder()
    b.buildPrefix()
    // Get a random variable and then change the type

    let obj = b.findOrGenerateType(type1)
    XCTAssert(b.type(of: obj).Is(type3))
    }

    func testFindOrGenerateTypeEnum() {
        let allowedValues = ["hello", "world", "foo", "bar"]

        let enumType = ILType.enumeration(ofName: "myEnum", withValues: allowedValues)
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()
        b.buildPrefix()
        // Get a random variable and then change the type

        let obj = b.findOrGenerateType(enumType)
        XCTAssert(b.type(of: obj).Is(.string))
        let program = b.finalize()
        var analyzer = DefUseAnalyzer(for: program)
        analyzer.analyze()
        let instruction = analyzer.definition(of: obj)
        switch instruction.op.opcode {
            case .loadString(let value):
              XCTAssert(allowedValues.contains(value.value))
            default:
              XCTAssert(false)
        }
    }
}
