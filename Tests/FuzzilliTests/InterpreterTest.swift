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

class AbstractInterpreterTests: XCTestCase {

    func testBasicTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let intVar = b.loadInt(42)
        let floatVar = b.loadFloat(13.37)
        let stringVar = b.loadString("foobar")
        let boolVar = b.loadBool(true)

        XCTAssertEqual(.integer, b.type(of: intVar))
        XCTAssertEqual(.float, b.type(of: floatVar))
        XCTAssertEqual(.string, b.type(of: stringVar))
        XCTAssertEqual(.boolean, b.type(of: boolVar))

        let sum = b.binary(intVar, stringVar, with: .Add)
        XCTAssertEqual(.primitive, b.type(of: sum))

    }

    func testObjectTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let intVar = b.loadInt(42)
        let obj = b.createObject(with: ["foo": intVar])
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))

        b.storeProperty(intVar, as: "bar", on: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))

        b.storeProperty(intVar, as: "baz", on: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))

        b.deleteProperty("foo", of: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["bar", "baz"]))

        let method = b.definePlainFunction(withSignature: [] => .object()) { params in }
        XCTAssertEqual(b.type(of: method), .functionAndConstructor([] => .object()))
        let obj2 = b.createObject(with: ["foo": intVar, "m1": method, "bar": intVar, "m2": method])
        XCTAssertEqual(b.type(of: obj2), .object(withProperties: ["foo", "bar"], withMethods: ["m1", "m2"]))
    }

    func testFunctionTypes() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature = [.integer] => .unknown

        var f = b.definePlainFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor(signature))

        // Every other type of function is not also a constructor
        f = b.defineStrictFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .function(signature))

        f = b.defineArrowFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .function(signature))

        f = b.defineGeneratorFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .function(signature))

        f = b.defineAsyncFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .function(signature))

        f = b.defineAsyncArrowFunction(withSignature: signature) { params in XCTAssertEqual(b.type(of: params[0]), .integer) }
        XCTAssertEqual(b.type(of: f), .function(signature))
    }

    func testParameterTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature = [.string, .object(), .opt(.number)] => .float
        let f = b.definePlainFunction(withSignature: signature) { params in
            XCTAssertEqual(b.type(of: params[0]), .string)
            XCTAssertEqual(b.type(of: params[1]), .object())
            XCTAssertEqual(b.type(of: params[2]), .opt(.number))
        }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor(signature))

        let signature2 = [.integer, .anything...] => .float
        let f2 = b.definePlainFunction(withSignature: signature2) { params in
            XCTAssertEqual(b.type(of: params[0]), .integer)
            XCTAssertEqual(b.type(of: params[1]), .object())
        }
        XCTAssertEqual(b.type(of: f2), .functionAndConstructor(signature2))
    }

    func testReassignments() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        XCTAssertEqual(b.type(of: v), .integer)

        let floatVar = b.loadFloat(13.37)
        b.reassign(v, to: floatVar)
        XCTAssertEqual(b.type(of: v), .float)

        let objVar = b.createObject(with: ["foo": b.loadInt(1337)])
        b.reassign(v, to: objVar)
        XCTAssertEqual(b.type(of: v), .object(withProperties: ["foo"]))
    }

    func testIfElseHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let obj = b.createObject(with: ["foo": v])

        b.beginIf(v) {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.storeProperty(v, as: "bar", on: obj)
            b.storeProperty(v, as: "baz", on: obj)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))

            XCTAssertEqual(b.type(of: v), .integer)
            let stringVar = b.loadString("foobar")
            b.reassign(v, to: stringVar)
            XCTAssertEqual(b.type(of: v), .string)
        }
        b.beginElse {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.storeProperty(v, as: "bar", on: obj)
            b.storeProperty(v, as: "bla", on: obj)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "bla"]))

            XCTAssertEqual(b.type(of: v), .integer)
            let floatVar = b.loadFloat(13.37)
            b.reassign(v, to: floatVar)
        }
        b.endIf()

        XCTAssertEqual(b.type(of: v), .string | .float)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))

        // Test another program using if/else
        b.reset()

        let v0 = b.loadInt(42)
        let v1 = b.loadInt(42)
        XCTAssertEqual(b.type(of: v0), .integer)
        XCTAssertEqual(b.type(of: v1), .integer)
        b.beginIf(v0) {
            b.reassign(v0, to: b.loadString("foo"))
            b.reassign(v1, to: b.loadString("foo"))
        }
        b.beginElse {
            b.reassign(v1, to: b.loadString("bar"))
        }
        b.endIf()

        XCTAssertEqual(b.type(of: v0), .string | .integer)
        XCTAssertEqual(b.type(of: v1), .string)
    }

    func testDeeplyNestedBlocksHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        XCTAssertEqual(b.type(of: v), .integer)

        b.beginIf(v) {
            b.beginIf(v) {
                b.beginIf(v) {
                    b.reassign(v, to: b.loadString("foo"))
                    XCTAssertEqual(b.type(of: v), .string)
                }
                b.beginElse {
                    XCTAssertEqual(b.type(of: v), .integer)
                    b.reassign(v, to: b.loadBool(true))
                    XCTAssertEqual(b.type(of: v), .boolean)
                }
                b.endIf()

                XCTAssertEqual(b.type(of: v), .string | .boolean)
            }
            b.beginElse {
                XCTAssertEqual(b.type(of: v), .integer)
            }
            b.endIf()

            XCTAssertEqual(b.type(of: v), .string | .boolean | .integer)
        }
        b.beginElse {
            XCTAssertEqual(b.type(of: v), .integer)
        }
        b.endIf()

        XCTAssertEqual(b.type(of: v), .string | .boolean | .integer)
    }

    func testFunctionReassignment() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature = [.integer] => .unknown

        func body() {
            let f = b.definePlainFunction(withSignature: signature) {
                params in XCTAssertEqual(b.type(of: params[0]), .integer)
            }
            XCTAssertEqual(b.type(of: f), .function([.integer] => .unknown) + .constructor([.integer] => .unknown))
            b.reassign(f, to: b.loadString("foo"))
            XCTAssertEqual(b.type(of: f), .string)
        }

        let v0 = b.loadInt(42)
        b.whileLoop(v0, .lessThan, v0) {
            body()
        }
    }

    func testLoopAndFunctionHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for i in 0..<6 {
            let intVar1 = b.loadInt(0)
            let intVar2 = b.loadInt(100)
            let intVar3 = b.loadInt(42)
            let v = b.loadString("foobar")
            let obj = b.createObject(with: ["foo": v])

            func body() {
                XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
                b.storeProperty(intVar1, as: "bar", on: obj)

                XCTAssertEqual(b.type(of: v), .string)
                let floatVar = b.loadFloat(13.37)
                b.reassign(v, to: floatVar)

                XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))
                XCTAssertEqual(b.type(of: v), .float)
            }

            // Select loop type
            switch i {
            case 0:
                b.forLoop(intVar1, .lessThan, intVar2, .Add, intVar3) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .primitive)
                    body()
                }
            case 1:
                b.whileLoop(intVar1, .lessThan, intVar2) {
                    body()
                }
            case 2:
                b.doWhileLoop(intVar1, .lessThan, intVar2) {
                    body()
                }
            case 3:
                b.forInLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .string)
                    body()
                }
            case 4:
                b.forOfLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .unknown)
                    body()
                }
            case 5:
                b.definePlainFunction(withSignature: FunctionSignature.forUnknownFunction) { _ in
                    body()
                }
            default:
                fatalError()
            }

            XCTAssertEqual(b.type(of: intVar1), .integer)
            XCTAssertEqual(b.type(of: intVar2), .integer)
            XCTAssertEqual(b.type(of: intVar3), .integer)
            XCTAssertEqual(b.type(of: v), .string | .float)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))

            b.reset()
        }
    }

    func testBuiltinTypeInference() {
        let builtinAType = Type.integer
        let builtinBType = Type.object(ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"])
        let builtinCType = Type.function([] => .number)

        let env = MockEnvironment(builtins: [
            "A": builtinAType,
            "B": builtinBType,
            "C": builtinCType
        ])

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let va = b.loadBuiltin("A")
        let vb = b.loadBuiltin("B")
        let vc = b.loadBuiltin("C")

        XCTAssertEqual(b.type(of: va), builtinAType)
        XCTAssertEqual(b.type(of: vb), builtinBType)
        XCTAssertEqual(b.type(of: vc), builtinCType)
    }

    func testPropertyTypeInference() {
        let propFooType = Type.float
        let propBarType = Type.function([] => .unknown)
        let propBazType = Type.object(withProperties: ["a", "b", "c"])
        let propertiesByGroup: [String: [String: Type]] = [
            "B": [
                "foo": propFooType,
                "bar": propBarType
            ],
            "C": [
                "baz": propBazType,
            ]
        ]

        let builtins: [String: Type] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]

        let env = MockEnvironment(builtins: builtins, propertiesByGroup: propertiesByGroup)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        // Test program-wide property inference
        b.setType(ofProperty: "a", to: .integer)
        b.setType(ofProperty: "b", to: .object(ofGroup: "B"))

        let aObj = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: aObj), .unknown)
        let bObj = b.loadBuiltin("B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))

        // Program-wide property types can always be inferred.
        var p = b.loadProperty("a", of: aObj)
        XCTAssertEqual(b.type(of: p), .integer)
        p = b.loadProperty("b", of: aObj)
        XCTAssertEqual(b.type(of: p), .object(ofGroup: "B"))
        p = b.loadProperty("b", of: bObj)
        XCTAssertEqual(b.type(of: p), .object(ofGroup: "B"))

        // Test inference of property types from the environment
        // .foo and .bar are both known for B objects
        p = b.loadProperty("foo", of: bObj)
        XCTAssertEqual(b.type(of: p), propFooType)
        p = b.loadProperty("bar", of: bObj)
        XCTAssertEqual(b.type(of: p), propBarType)

        // But .baz is only known on C objects
        p = b.loadProperty("baz", of: bObj)
        XCTAssertEqual(b.type(of: p), .unknown)

        let cObj = b.loadBuiltin("C")
        p = b.loadProperty("baz", of: cObj)
        XCTAssertEqual(b.type(of: p), propBazType)

        // No property types are known for A objects though.
        p = b.loadProperty("foo", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
        p = b.loadProperty("bar", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
        p = b.loadProperty("baz", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
    }

    func testMethodTypeInference() {
        let m1Signature = [] => .float
        let m2Signature = [.string] => .object(ofGroup: "X")
        let methodsByGroup: [String: [String: FunctionSignature]] = [
            "B": [
                "m1": m1Signature,
            ],
            "C": [
                "m2": m2Signature,
            ]
        ]

        let builtins: [String: Type] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]

        let env = MockEnvironment(builtins: builtins, methodsByGroup: methodsByGroup)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        // Test method signature inference of program-wide methods.
        b.setSignature(ofMethod: "m3", to: [] => .integer)

        let aObj = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: aObj), .unknown)
        let bObj = b.loadBuiltin("B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))

        var r = b.callMethod("m3", on: aObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .integer)
        r = b.callMethod("m3", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .integer)

        // Test inference of per-group methods.
        r = b.callMethod("m1", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .float)

        r = b.callMethod("m2", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .unknown)

        let cObj = b.loadBuiltin("C")
        r = b.callMethod("m2", on: cObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .object(ofGroup: "X"))
    }

    func testConstructorTypeInference() {
        let aConstructorType = Type.constructor([.anything...] => .object(ofGroup: "A"))
        let builtins: [String: Type] = [
            "A": aConstructorType,
        ]

        let env = MockEnvironment(builtins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let A = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: A), aConstructorType)

        // For a known constructor, the resulting type can be inferred
        let a = b.construct(A, withArgs: [])
        XCTAssertEqual(b.type(of: a), .object(ofGroup: "A"))

        // For an unknown constructor, the result will be .object()
        let C = b.loadBuiltin("C")
        let c = b.construct(C, withArgs: [])
        XCTAssertEqual(b.type(of: c), .object())
    }

    func testReturnTypeInference() {
        let aFunctionType = Type.function([.anything...] => .primitive)
        let builtins: [String: Type] = [
            "a": aFunctionType,
        ]

        let env = MockEnvironment(builtins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let a = b.loadBuiltin("a")
        XCTAssertEqual(b.type(of: a), aFunctionType)

        // For a known function, the resulting type can be inferred
        var r = b.callFunction(a, withArgs: [])
        XCTAssertEqual(b.type(of: r), .primitive)

        // For an unknown function, the result will be .unknown
        let c = b.loadBuiltin("c")
        r = b.callFunction(c, withArgs: [])
        XCTAssertEqual(b.type(of: r), .unknown)
    }

    func testPrimitiveTypesOverride() {
        let env = MockEnvironment(builtins: [:])
        env.intType = .integer + .object(ofGroup: "Number")
        env.floatType = .float + .object(ofGroup: "Number")
        env.booleanType = .boolean + .object(ofGroup: "Number")
        env.stringType = .string + .object(ofGroup: "Number")

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let iv = b.loadInt(42)
        let fv = b.loadFloat(13.37)
        let bv = b.loadBool(true)
        let sv = b.loadString("foobar")

        XCTAssertEqual(b.type(of: iv), env.intType)
        XCTAssertEqual(b.type(of: fv), env.floatType)
        XCTAssertEqual(b.type(of: bv), env.booleanType)
        XCTAssertEqual(b.type(of: sv), env.stringType)
    }

    func testArrayCreation() {
        let env = MockEnvironment(builtins: [:])
        env.arrayType = .object(ofGroup: "Array")

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let a = b.createArray(with: [])
        XCTAssertEqual(b.type(of: a), .object(ofGroup: "Array"))
    }

    func testClasses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)

        let instanceType = Type.object(withProperties: ["a", "b"], withMethods: ["f"])

        let cls = b.defineClass() { cls in
            cls.defineConstructor(withParameters: [.string]) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(instanceType))

                XCTAssertEqual(b.type(of: v), .integer)
                b.reassign(v, to: params[1])
                XCTAssertEqual(b.type(of: v), .string)
            }

            cls.defineProperty("a")
            cls.defineProperty("b")

            cls.defineMethod("f", withSignature: [.anything] => .unknown) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(instanceType))

                XCTAssertEqual(b.type(of: v), .integer | .string)
                b.reassign(v, to: b.loadFloat(13.37))
                XCTAssertEqual(b.type(of: v), .float)
            }
        }

        XCTAssertEqual(b.type(of: v), .integer | .string | .float)
        XCTAssertEqual(b.type(of: cls), .constructor([.string] => instanceType))
    }

    func testSuperBinding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superType = Type.object(withProperties: ["a"], withMethods: ["f"])
        let instanceType = Type.object(withProperties: ["a", "b"], withMethods: ["f", "g"])

        let superclass = b.defineClass() { cls in
            cls.defineConstructor(withParameters: [.integer]) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(superType))
                XCTAssert(b.currentSuperType().Is(.unknown))        // No superclass
            }

            cls.defineProperty("a")

            cls.defineMethod("f", withSignature: [.float] => .string) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(superType))
                XCTAssert(b.currentSuperType().Is(.unknown))        // No superclass

                b.doReturn(value: b.loadString("foobar"))
            }
        }
        XCTAssertEqual(b.type(of: superclass), .constructor([.integer] => superType))

        let cls = b.defineClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(withParameters: [.string]) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(instanceType))
                XCTAssert(b.currentSuperType().Is(superType))

                b.callSuperConstructor(withArgs: [b.loadFloat(42)])
            }

            cls.defineProperty("b")

            cls.defineMethod("g", withSignature: [.anything] => .unknown) { params in
                let this = params[0]
                XCTAssert(b.type(of: this).Is(instanceType))
                XCTAssert(b.currentSuperType().Is(superType))

                // In the future, we can also track property types and method signatures
                //let v = b.callSuperMethod("f", withArgs: [b.loadFloat(13.37)])
                //XCTAssert(b.type(of: v).Is(.string))

                b.definePlainFunction(withSignature: [] => .unknown) { _ in
                    // 'super' now refers to some other, unknown object
                    XCTAssert(b.currentSuperType().Is(.unknown))
                }
            }
        }
        XCTAssertEqual(b.type(of: cls), .constructor([.string] => instanceType))
    }

    func testBigintTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(42)
        let i2 = b.loadInt(43)
        XCTAssert(b.type(of: i1).Is(.integer))
        let bi1 = b.loadBigInt(4200000000)
        let bi2 = b.loadBigInt(4300000000)
        XCTAssert(b.type(of: bi1).Is(.bigint))

        for op in allUnaryOperators {
            // Logical operators produce .boolean in any case
            guard op != .LogicalNot else { continue }
            let r1 = b.unary(op, i1)
            XCTAssertFalse(b.type(of: r1).MayBe(.bigint))
            let r2 = b.unary(op, bi1)
            XCTAssert(b.type(of: r2).Is(.bigint))
        }

        for op in allBinaryOperators {
            // Logical operators produce .boolean in any case
            guard op != .LogicOr && op != .LogicAnd else { continue }
            let r1 = b.binary(i1, i2, with: op)
            XCTAssertFalse(b.type(of: r1).MayBe(.bigint))
            let r2 = b.binary(i1, bi2, with: op)
            // This isn't really necessary, as mixing types in this way
            // would lead to an exception in JS. Currently, we handle
            // it like this though.
            XCTAssert(b.type(of: r2).MayBe(.bigint))
            let r3 = b.binary(bi1, bi2, with: op)
            XCTAssert(b.type(of: r3).Is(.bigint))
        }

        for op in allBinaryOperators {
            let i3 = b.loadInt(45)
            let i4 = b.loadInt(46)
            XCTAssert(b.type(of: i3).Is(.integer))
            let bi3 = b.loadBigInt(4200000000)
            let bi4 = b.loadBigInt(4300000000)
            XCTAssert(b.type(of: bi3).Is(.bigint))

            // Logical operators produce .boolean in any case
            guard op != .LogicOr && op != .LogicAnd else { continue }
            b.binaryOpAndReassign(i3, to: i4, with: op)
            XCTAssertFalse(b.type(of: i3).MayBe(.bigint))
            b.binaryOpAndReassign(i3, to: bi4, with: op)
            // This isn't really necessary, as mixing types in this way
            // would lead to an exception in JS. Currently, we handle
            // it like this though.
            XCTAssert(b.type(of: i3).MayBe(.bigint))
            b.binaryOpAndReassign(bi3, to: bi4, with: op)
            XCTAssert(b.type(of: bi3).Is(.bigint))
        }
    }
    
    func testSwitchStatementHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 = b.loadProperty("foo", of: v1)
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")

        b.doSwitch(on: v2){ cases in
            cases.addDefault {
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.storeProperty(v0, as: "bar", on: v1)
                b.storeProperty(v0, as: "qux", on: v1)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "qux"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let newObj = b.createObject(with: ["quux": v4])
                b.reassign(v0, to: newObj)
                XCTAssertEqual(b.type(of: v0), .object(withProperties: ["quux"]))
            }
            cases.add(v3) {
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.storeProperty(v0, as: "bar", on: v1)
                b.storeProperty(v0, as: "baz", on: v1)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "baz"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let stringVar = b.loadString("foobar")
                b.reassign(v0, to: stringVar)
                XCTAssertEqual(b.type(of: v0), .string)
            }
            cases.add(v4){
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.storeProperty(v0, as: "bar", on: v1)
                b.storeProperty(v0, as: "bla", on: v1)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "bla"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let floatVar = b.loadFloat(13.37)
                b.reassign(v0, to: floatVar)
                XCTAssertEqual(b.type(of: v0), .float)
            }
        }

        XCTAssertEqual(b.type(of: v0), .float | .string | .object())
        XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar"]))

        // Test another program using switch
        b.reset()

        let v6 = b.loadInt(42)
        let v7 = b.loadInt(42)
        XCTAssertEqual(b.type(of: v6), .integer)
        XCTAssertEqual(b.type(of: v7), .integer)
        b.doSwitch(on: v6) { cases in
            cases.addDefault {
                b.reassign(v7, to: b.loadString("bar"))
            }
        }

        XCTAssertEqual(b.type(of: v6), .integer)
        XCTAssertEqual(b.type(of: v7), .string)
    }
}

extension AbstractInterpreterTests {
    static var allTests : [(String, (AbstractInterpreterTests) -> () throws -> Void)] {
        return [
            ("testBasicTypeTracking", testBasicTypeTracking),
            ("testObjectTypeTracking", testObjectTypeTracking),
            ("testFunctionTypes", testFunctionTypes),
            ("testParameterTypeTracking", testParameterTypeTracking),
            ("testReassignments", testReassignments),
            ("testIfElseHandling", testIfElseHandling),
            ("testDeeplyNestedBlocksHandling", testDeeplyNestedBlocksHandling),
            ("testFunctionReassignment", testFunctionReassignment),
            ("testLoopAndFunctionHandling", testLoopAndFunctionHandling),
            ("testBuiltinTypeInference", testBuiltinTypeInference),
            ("testPropertyTypeInference", testPropertyTypeInference),
            ("testMethodTypeInference", testMethodTypeInference),
            ("testConstructorTypeInference", testConstructorTypeInference),
            ("testReturnTypeInference", testReturnTypeInference),
            ("testPrimitiveTypesOverride", testPrimitiveTypesOverride),
            ("testArrayCreation", testArrayCreation),
            ("testClasses", testClasses),
            ("testSuperBinding", testSuperBinding),
            ("testBigintTypeTracking", testBigintTypeTracking),
            ("testSwitchStatementHandling",testSwitchStatementHandling),
        ]
    }
}
