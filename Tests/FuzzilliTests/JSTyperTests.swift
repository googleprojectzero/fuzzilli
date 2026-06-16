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

import Testing

@testable import Fuzzilli

struct JSTyperTests {

    @Test func testBasicTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let intVar = b.loadInt(42)
            let floatVar = b.loadFloat(13.37)
            let stringVar = b.loadString("foobar")
            let boolVar = b.loadBool(true)

            #expect(.integer == b.type(of: intVar))
            #expect(.float == b.type(of: floatVar))
            #expect(.jsString == b.type(of: stringVar))
            #expect(.boolean == b.type(of: boolVar))

            let sum = b.binary(intVar, stringVar, with: .Add)
            #expect(.primitive == b.type(of: sum))

        }
    }

    @Test func testObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            let obj = b.buildObjectLiteral { obj in
                obj.addProperty("a", as: v)
                obj.addMethod("m", with: .parameters(.integer)) { args in
                    let this = args[0]
                    // Up to this point, only the "a" property has been installed
                    #expect(
                        b.type(of: this) == .object(ofGroup: "_fuzz_Object0", withProperties: ["a"])
                    )
                    #expect(b.type(of: args[1]) == .integer)
                    let notArg = b.unary(.LogicalNot, args[1])
                    b.doReturn(notArg)
                }
                obj.addGetter(for: "b") { this in
                    // We don't add the "b" property to the |this| type here since it's probably not very useful to access it inside its getter/setter.
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["a"], withMethods: ["m"])
                    )
                }
                obj.addSetter(for: "c") { this, v in
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["a", "b"],
                                withMethods: ["m"]))
                }
            }

            #expect(
                b.type(of: obj)
                    == .object(
                        ofGroup: "_fuzz_Object0", withProperties: ["a", "b", "c"],
                        withMethods: ["m"]))

            let obj2 = b.buildObjectLiteral { obj in
                obj.addProperty("prop", as: v)
                obj.addElement(0, as: v)
            }

            #expect(b.type(of: obj2) == .object(ofGroup: "_fuzz_Object1", withProperties: ["prop"]))
        }
    }

    @Test func testNestedObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            b.buildObjectLiteral { outer in
                outer.addProperty("a", as: v)
                outer.addMethod("m", with: .parameters(n: 1)) { args in
                    let this = args[0]
                    #expect(
                        b.type(of: this) == .object(ofGroup: "_fuzz_Object0", withProperties: ["a"])
                    )
                    b.buildObjectLiteral { inner in
                        inner.addProperty("b", as: v)
                        inner.addMethod("n", with: .parameters(n: 0)) { args in
                            let this = args[0]
                            #expect(
                                b.type(of: this)
                                    == .object(ofGroup: "_fuzz_Object1", withProperties: ["b"]))
                        }
                    }
                }
                outer.addProperty("c", as: v)
                outer.addMethod("o", with: .parameters(n: 0)) { args in
                    let this = args[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["a", "c"],
                                withMethods: ["m"]))
                }
            }
        }
    }

    @Test func testObjectTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let intVar = b.loadInt(42)
            let obj = b.createObject(with: ["foo": intVar])
            #expect(b.type(of: obj) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))

            b.setProperty("bar", of: obj, to: intVar)
            #expect(
                b.type(of: obj)
                    == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar"]))

            b.setProperty("baz", of: obj, to: intVar)
            #expect(
                b.type(of: obj)
                    == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "baz"]))

            let _ = b.deleteProperty("foo", of: obj)
            #expect(
                b.type(of: obj)
                    == .object(ofGroup: "_fuzz_Object0", withProperties: ["bar", "baz"]))

            // Properties whose values are functions are still treated as properties, not methods.
            let function = b.buildPlainFunction(with: .parameters(n: 1)) { params in }
            #expect(b.type(of: function) == .functionAndConstructor([.jsAnything] => .undefined))
            let obj2 = b.createObject(with: ["foo": intVar, "bar": intVar, "baz": function])
            #expect(
                b.type(of: obj2)
                    == .object(ofGroup: "_fuzz_Object1", withProperties: ["foo", "bar", "baz"]))
        }
    }

    @Test func testClasses() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            let cls = b.buildClassDefinition { cls in
                cls.addConstructor(with: .parameters([.string])) { params in
                    let this = params[0]
                    #expect(b.type(of: this) == .object(ofGroup: "_fuzz_Class0"))
                    #expect(b.type(of: params[1]) == .string)
                    #expect(b.type(of: v) == .integer)
                    b.reassign(variable: v, value: params[1])
                    #expect(b.type(of: v) == .string)
                }

                cls.addInstanceProperty("a")
                cls.addInstanceProperty("b")

                cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(ofGroup: "_fuzz_Class0", withProperties: ["a", "b"]))
                    #expect(b.type(of: params[1]) == .float)
                    #expect(b.type(of: v) == .integer | .string)
                    b.reassign(variable: v, value: params[1])
                    #expect(b.type(of: v) == .float)
                }

                cls.addInstanceGetter(for: "c") { this in
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class0", withProperties: ["a", "b"],
                                withMethods: ["f"]))
                }

                cls.addInstanceMethod("g", with: .parameters(n: 2)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class0", withProperties: ["a", "b", "c"],
                                withMethods: ["f"]
                            ))
                    #expect(b.type(of: params[1]) == .jsAnything)
                    #expect(b.type(of: params[2]) == .jsAnything)
                }

                cls.addStaticProperty("a")
                cls.addStaticProperty("d")

                cls.addStaticMethod("g", with: .parameters(n: 2)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(ofGroup: "_fuzz_Constructor0", withProperties: ["a", "d"]))
                    #expect(b.type(of: params[1]) == .jsAnything)
                    #expect(b.type(of: params[2]) == .jsAnything)
                }

                cls.addStaticSetter(for: "e") { this, v in
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Constructor0", withProperties: ["a", "d"],
                                withMethods: ["g"]))
                }

                cls.addStaticMethod("h", with: .parameters(.integer)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Constructor0", withProperties: ["a", "d", "e"],
                                withMethods: ["g"]))
                    #expect(b.type(of: params[1]) == .integer)
                }

                cls.addPrivateInstanceMethod("p", with: .parameters(n: 0)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class0", withProperties: ["a", "b", "c"],
                                withMethods: ["f", "g"]))
                }

                cls.addPrivateStaticMethod("p", with: .parameters(n: 0)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Constructor0", withProperties: ["a", "d", "e"],
                                withMethods: ["g", "h"]))
                }
            }

            #expect(b.type(of: v) == .integer | .string | .float)
            #expect(
                b.type(of: cls) == .object(
                    ofGroup: "_fuzz_Constructor0", withProperties: ["a", "d", "e"],
                    withMethods: ["g", "h"])
                    + .constructor(
                        [.string]
                            => .object(
                                ofGroup: "_fuzz_Class0", withProperties: ["a", "b", "c"],
                                withMethods: ["f", "g"])))
        }
    }

    @Test func testClasses2() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            let s = b.loadString("foo")
            let f = b.loadFloat(13.37)
            b.buildClassDefinition { cls in
                // Class methods, getters, setters, etc. are treated as conditionally executing blocks.
                cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                    #expect(b.type(of: v) == .integer)

                    b.reassign(variable: v, value: b.loadFloat(13.37))

                    #expect(b.type(of: v) == .float)
                }

                cls.addInstanceGetter(for: "m") { this in
                    #expect(b.type(of: v) == .integer | .float)
                    #expect(b.type(of: f) == .float)

                    b.reassign(variable: v, value: b.loadString("bar"))
                    b.reassign(variable: f, value: b.loadString("baz"))

                    #expect(b.type(of: v) == .jsString)
                    #expect(b.type(of: f) == .jsString)
                }

                cls.addStaticMethod("n", with: .parameters(n: 0)) { args in
                    #expect(b.type(of: v) == .integer | .float | .jsString)
                    #expect(b.type(of: s) == .jsString)

                    b.reassign(variable: v, value: b.loadBool(true))
                    b.reassign(variable: s, value: b.loadFloat(13.37))

                    #expect(b.type(of: v) == .boolean)
                    #expect(b.type(of: s) == .float)
                }

                // The same is true for class static initializers, even though they technically execute unconditionally.
                // However, treating them as executing unconditionally would cause them to overwrite any variable changes
                // performed in preceeding blocks. For example, in this example |s| would be .jsString after the initializer
                // if it were treated as executing unconditionally, while .jsString | .float is "more correct".
                cls.addStaticInitializer { this in
                    #expect(b.type(of: f) == .float | .jsString)

                    b.reassign(variable: f, value: b.loadBool(true))

                    #expect(b.type(of: f) == .boolean)
                }
            }

            #expect(b.type(of: v) == .primitive | .object() | .iterable())
            #expect(b.type(of: s) == .jsString | .float)
            #expect(b.type(of: f) == .boolean)  // A static initializer block runs unconditionally
        }
    }

    @Test func testNestedClasses() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let outer = b.buildClassDefinition { cls in
                cls.addInstanceProperty("a")
                cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                    let inner = b.buildClassDefinition { cls in
                        cls.addInstanceProperty("a")
                        cls.addInstanceProperty("b")
                    }
                    #expect(
                        b.type(of: inner) == .object(ofGroup: "_fuzz_Constructor1")
                            + .constructor(
                                [] => .object(ofGroup: "_fuzz_Class1", withProperties: ["a", "b"])))
                }
                cls.addInstanceProperty("c")
            }
            #expect(
                b.type(of: outer) == .object(ofGroup: "_fuzz_Constructor0")
                    + .constructor(
                        []
                            => .object(
                                ofGroup: "_fuzz_Class0", withProperties: ["a", "c"],
                                withMethods: ["m"])
                    ))
        }
    }

    @Test func testSubClasses() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let base1 = b.buildClassDefinition { cls in
                cls.addInstanceProperty("a")
            }
            #expect(
                b.type(of: base1) == .object(ofGroup: "_fuzz_Constructor0")
                    + .constructor([] => .object(ofGroup: "_fuzz_Class0", withProperties: ["a"])))

            let v = b.loadInt(42)
            let base2 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let obj = b.buildObjectLiteral { obj in
                    obj.addProperty("b", as: v)
                }
                b.doReturn(obj)
            }
            #expect(
                b.type(of: base2)
                    == .functionAndConstructor(
                        [] => .object(ofGroup: "_fuzz_Object2", withProperties: ["b"])))

            let base3 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                b.doReturn(v)
            }
            #expect(b.type(of: base3) == .functionAndConstructor([] => .integer))

            let base4 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
            #expect(b.type(of: base4) == .functionAndConstructor([] => .undefined))

            let derived1 = b.buildClassDefinition(withSuperclass: base1) { cls in
                cls.addInstanceProperty("c")
            }
            #expect(
                b.type(of: derived1) == .object(ofGroup: "_fuzz_Constructor3")
                    + .constructor(
                        [] => .object(ofGroup: "_fuzz_Class3", withProperties: ["a", "c"])))

            let derived2 = b.buildClassDefinition(withSuperclass: base2) { cls in
                cls.addInstanceProperty("d")
            }
            #expect(
                b.type(of: derived2) == .object(ofGroup: "_fuzz_Constructor5")
                    + .constructor(
                        [] => .object(ofGroup: "_fuzz_Class5", withProperties: ["b", "d"])))

            // base3 does not return an object, so that return type is ignored for the constructor.
            // TODO: Technically, base3 used as a constructor would return |this|, so we'd have to use the type of |this| if the returned value is not an object in our type inference, but we don't currently do that.
            let derived3 = b.buildClassDefinition(withSuperclass: base3) { cls in
                cls.addInstanceProperty("e")
            }
            #expect(
                b.type(of: derived3) == .object(ofGroup: "_fuzz_Constructor7")
                    + .constructor([] => .object(ofGroup: "_fuzz_Class7", withProperties: ["e"])))

            let derived4 = b.buildClassDefinition(withSuperclass: base4) { cls in
                cls.addInstanceProperty("f")
            }
            #expect(
                b.type(of: derived4) == .object(ofGroup: "_fuzz_Constructor9")
                    + .constructor([] => .object(ofGroup: "_fuzz_Class9", withProperties: ["f"])))

            let derived5 = b.buildClassDefinition(withSuperclass: derived1) { cls in
                cls.addInstanceProperty("g")
            }
            #expect(
                b.type(of: derived5) == .object(ofGroup: "_fuzz_Constructor11")
                    + .constructor(
                        [] => .object(ofGroup: "_fuzz_Class11", withProperties: ["a", "c", "g"])))
        }
    }

    @Test func testSubroutineTypes() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let signature1 = [.integer, .number] => .undefined
            let signature2 = [.string, .number] => .undefined

            // Plain functions are both functions and constructors. This might yield interesting results since these function often return a value.
            var f = b.buildPlainFunction(with: .parameters(n: 2)) { params in
                #expect(b.type(of: params[0]) == .jsAnything)
                #expect(b.type(of: params[1]) == .jsAnything)
            }
            #expect(
                b.type(of: f) == .functionAndConstructor([.jsAnything, .jsAnything] => .undefined))

            f = b.buildPlainFunction(with: .parameters(signature1.parameters)) { params in
                #expect(b.type(of: params[0]) == .integer)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .functionAndConstructor(signature1))

            f = b.buildPlainFunction(with: .parameters(n: 2)) { params in
                #expect(b.type(of: params[0]) == .jsAnything)
                #expect(b.type(of: params[1]) == .jsAnything)
            }
            #expect(
                b.type(of: f) == .functionAndConstructor([.jsAnything, .jsAnything] => .undefined))

            // All other function types are just functions...
            f = b.buildArrowFunction(with: .parameters(signature2.parameters)) { params in
                #expect(b.type(of: params[0]) == .string)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .function(signature2))

            let signature3 = [.integer, .number] => .jsGenerator
            f = b.buildGeneratorFunction(with: .parameters(signature3.parameters)) { params in
                #expect(b.type(of: params[0]) == .integer)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .function(signature3))

            let signature4 = [.integer, .number] => .jsAsyncGenerator
            f = b.buildAsyncGeneratorFunction(with: .parameters(signature4.parameters)) { params in
                #expect(b.type(of: params[0]) == .integer)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .function(signature4))

            let signature5 = [.string, .number] => .jsPromise
            f = b.buildAsyncFunction(with: .parameters(signature5.parameters)) { params in
                #expect(b.type(of: params[0]) == .string)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .function(signature5))

            f = b.buildAsyncArrowFunction(with: .parameters(signature5.parameters)) { params in
                #expect(b.type(of: params[0]) == .string)
                #expect(b.type(of: params[1]) == .number)
            }
            #expect(b.type(of: f) == .function(signature5))

            // ... except for constructors, which are just constructors (when they are lifted to JavaScript, they explicitly forbid being called as a function).
            let signature6 = [.integer, .number] => .object(withProperties: ["foo", "bar"])
            f = b.buildConstructor(with: .parameters(signature6.parameters)) { params in
                let this = params[0]
                #expect(b.type(of: this) == .object())
                #expect(b.type(of: params[1]) == .integer)
                #expect(b.type(of: params[2]) == .number)
                b.setProperty("foo", of: this, to: params[1])
                b.setProperty("bar", of: this, to: params[2])
            }
            #expect(b.type(of: f) == .constructor(signature6))
        }
    }

    @Test func testReturnValueInference() {
        // Test that function and constructor return values are inferred correctly.
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let f1 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                b.doReturn(b.loadInt(42))
            }
            #expect(b.type(of: f1).signature?.outputType == .integer)

            let f2 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let o = b.createObject(with: ["a": b.loadInt(42)])
                b.doReturn(o)
            }
            #expect(
                b.type(of: f2).signature?.outputType
                    == .object(ofGroup: "_fuzz_Object0", withProperties: ["a"]))

            let f3 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.buildIfElse(
                    args[0],
                    ifBody: {
                        b.doReturn(b.loadFloat(13.37))
                    },
                    elseBody: {
                        b.doReturn(b.loadString("13.37"))
                    })
                b.doReturn(b.loadBool(false))
            }
            #expect(b.type(of: f3).signature?.outputType == .float | .jsString)

            let f4 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.buildIfElse(
                    args[0],
                    ifBody: {
                        b.doReturn(b.loadString("foo"))
                    },
                    elseBody: {
                    })
            }
            #expect(b.type(of: f4).signature?.outputType == .undefined | .jsString)

            let f5 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.buildIfElse(
                    args[0],
                    ifBody: {
                        b.doReturn(b.loadString("foo"))
                    },
                    elseBody: {
                    })
                b.doReturn(b.loadBool(true))
            }
            #expect(b.type(of: f5).signature?.outputType == .boolean | .jsString)

            let f6 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
                b.doReturn(b.loadInt(42))
                b.buildIfElse(
                    args[0],
                    ifBody: {
                        b.doReturn(b.loadFloat(13.37))
                    },
                    elseBody: {
                        b.doReturn(b.loadString("13.37"))
                    })
                b.doReturn(b.loadBool(false))
            }
            #expect(b.type(of: f6).signature?.outputType == .integer)

            let f7 = b.buildPlainFunction(with: .parameters(n: 2)) { args in
                b.buildIf(args[0]) {
                    b.buildIf(args[1]) {
                        b.doReturn(b.loadFloat(13.37))
                    }
                }
                b.doReturn(b.loadBool(true))
            }
            #expect(b.type(of: f7).signature?.outputType == .float | .boolean)

            let f8 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let f9 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadInt(42))
                }
                #expect(b.type(of: f9).signature?.outputType == .integer)
                b.doReturn(b.loadFloat(13.37))
            }
            #expect(b.type(of: f8).signature?.outputType == .float)

            let f9 = b.buildPlainFunction(with: .parameters(n: 3)) { args in
                b.buildIf(args[0]) {
                    b.doReturn(b.loadInt(42))
                }
                b.buildIf(args[1]) {
                    b.buildIfElse(
                        args[2],
                        ifBody: {
                            b.doReturn(b.loadBool(true))
                        },
                        elseBody: {
                            b.doReturn(b.loadBool(false))
                        })
                    // This is ignored: all paths have already returned
                    b.doReturn(b.loadString("foobar"))
                }
                b.doReturn(b.loadFloat(13.37))
            }
            #expect(b.type(of: f9).signature?.outputType == .integer | .boolean | .float)

            let a1 = b.buildArrowFunction(with: .parameters(n: 0)) { _ in
                b.doReturn(b.loadInt(42))
            }
            #expect(b.type(of: a1).signature?.outputType == .integer)

            let c1 = b.buildConstructor(with: .parameters(n: 0)) { _ in }
            #expect(b.type(of: c1).signature?.outputType == .object())

            let c2 = b.buildConstructor(with: .parameters(n: 2)) { args in
                let this = args[0]
                b.setProperty("a", of: this, to: args[1])
                b.setProperty("b", of: this, to: args[2])
            }
            #expect(b.type(of: c2).signature?.outputType == .object(withProperties: ["a", "b"]))

            let c3 = b.buildConstructor(with: .parameters(n: 2)) { args in
                let o = b.createObject(with: ["a": args[1], "b": args[2]])
                b.doReturn(o)
            }
            #expect(
                b.type(of: c3).signature?.outputType
                    == .object(ofGroup: "_fuzz_Object1", withProperties: ["a", "b"]))

            let g1 = b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
                b.yield(b.loadInt(42))
            }
            #expect(b.type(of: g1).signature?.outputType == .jsGenerator)

            let g2 = b.buildAsyncGeneratorFunction(with: .parameters(n: 0)) { _ in
                b.yield(b.loadInt(42))
            }
            #expect(b.type(of: g2).signature?.outputType == .jsAsyncGenerator)

            let a2 = b.buildAsyncFunction(with: .parameters(n: 0)) { _ in }
            #expect(b.type(of: a2).signature?.outputType == .jsPromise)

            let a3 = b.buildAsyncArrowFunction(with: .parameters(n: 0)) { _ in }
            #expect(b.type(of: a3).signature?.outputType == .jsPromise)
        }
    }

    @Test func testParameterTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let signature = [.string, .object(), .opt(.number)] => .float
            let f = b.buildPlainFunction(with: .parameters(signature.parameters)) { params in
                #expect(b.type(of: params[0]) == .string)
                #expect(b.type(of: params[1]) == .object())
                #expect(b.type(of: params[2]) == .undefined | .integer | .float)
                b.doReturn(b.loadFloat(13.37))
            }
            #expect(b.type(of: f) == .functionAndConstructor(signature))

            let signature2 = [.integer, .jsAnything...] => .float
            let f2 = b.buildPlainFunction(with: .parameters(signature2.parameters)) { params in
                #expect(b.type(of: params[0]) == .integer)
                #expect(b.type(of: params[1]) == .jsArray)
                b.doReturn(b.loadFloat(13.37))
            }
            #expect(b.type(of: f2) == .functionAndConstructor(signature2))
        }
    }

    @Test func testReassignments() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            #expect(b.type(of: v) == .integer)

            let floatVar = b.loadFloat(13.37)
            b.reassign(variable: v, value: floatVar)
            #expect(b.type(of: v) == .float)

            let objVar = b.createObject(with: ["foo": b.loadInt(1337)])
            b.reassign(variable: v, value: objVar)
            #expect(b.type(of: v) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))
        }
    }

    @Test func testIfElseHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            let obj = b.createObject(with: ["foo": v])

            b.buildIfElse(
                v,
                ifBody: {
                    #expect(
                        b.type(of: obj)
                            == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))
                    b.setProperty("bar", of: obj, to: v)
                    b.setProperty("baz", of: obj, to: v)
                    #expect(
                        b.type(of: obj)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "baz"]))

                    #expect(b.type(of: v) == .integer)
                    let stringVar = b.loadString("foobar")
                    b.reassign(variable: v, value: stringVar)
                    #expect(b.type(of: v) == .jsString)
                },
                elseBody: {
                    #expect(
                        b.type(of: obj)
                            == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))
                    b.setProperty("bar", of: obj, to: v)
                    b.setProperty("bla", of: obj, to: v)
                    #expect(
                        b.type(of: obj)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "bla"]))

                    #expect(b.type(of: v) == .integer)
                    let floatVar = b.loadFloat(13.37)
                    b.reassign(variable: v, value: floatVar)
                })

            #expect(b.type(of: v) == .string | .float | .object() | .iterable())
            #expect(
                b.type(of: obj)
                    == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar"]))

            // Test another program using if/else
            b.reset()

            let v0 = b.loadInt(42)
            let v1 = b.loadInt(42)
            #expect(b.type(of: v0) == .integer)
            #expect(b.type(of: v1) == .integer)
            b.buildIfElse(
                v0,
                ifBody: {
                    b.reassign(variable: v0, value: b.loadString("foo"))
                    b.reassign(variable: v1, value: b.loadString("foo"))
                },
                elseBody: {
                    b.reassign(variable: v1, value: b.loadString("bar"))
                })

            #expect(b.type(of: v0) == .integer | .jsString)
            #expect(b.type(of: v1) == .jsString)

            // Test another program using just if
            b.reset()

            let i = b.loadInt(42)
            #expect(b.type(of: i) == .integer)
            b.buildIf(i) {
                b.reassign(variable: i, value: b.loadString("foo"))
            }

            #expect(b.type(of: i) == .integer | .jsString)
        }
    }

    @Test func testDeeplyNestedBlocksHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v = b.loadInt(42)
            #expect(b.type(of: v) == .integer)

            b.buildIfElse(
                v,
                ifBody: {
                    b.buildIfElse(
                        v,
                        ifBody: {
                            b.buildIfElse(
                                v,
                                ifBody: {
                                    b.reassign(variable: v, value: b.loadString("foo"))
                                    #expect(b.type(of: v) == .jsString)
                                },
                                elseBody: {
                                    #expect(b.type(of: v) == .integer)
                                    b.reassign(variable: v, value: b.loadBool(true))
                                    #expect(b.type(of: v) == .boolean)
                                })

                            #expect(b.type(of: v) == .boolean | .jsString)
                        },
                        elseBody: {
                            #expect(b.type(of: v) == .integer)
                        })

                    #expect(b.type(of: v) == .boolean | .integer | .jsString)
                },
                elseBody: {
                    #expect(b.type(of: v) == .integer)
                })

            #expect(b.type(of: v) == .boolean | .integer | .jsString)
        }
    }

    @Test func testFunctionReassignment() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let signature = [.integer] => .undefined

            b.buildWhileLoop({ b.loadBool(true) }) {
                let f = b.buildPlainFunction(with: .parameters(signature.parameters)) {
                    params in #expect(b.type(of: params[0]) == .integer)
                }
                #expect(b.type(of: f) == .functionAndConstructor(signature))
                b.reassign(variable: f, value: b.loadString("foo"))
                #expect(b.type(of: f) == .jsString)
            }
        }
    }

    @Test func testLoopAndFunctionHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            for i in 0..<6 {
                let intVar1 = b.loadInt(0)
                let intVar2 = b.loadInt(100)
                let intVar3 = b.loadInt(42)
                let v = b.loadString("foobar")
                let obj = b.createObject(with: ["foo": v])

                func body() {
                    #expect(
                        b.type(of: obj)
                            == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))
                    b.setProperty("bar", of: obj, to: intVar1)

                    #expect(b.type(of: v) == .jsString)
                    let floatVar = b.loadFloat(13.37)
                    b.reassign(variable: v, value: floatVar)

                    #expect(
                        b.type(of: obj)
                            == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar"]))
                    #expect(b.type(of: v) == .float)
                }

                // Select loop type
                switch i {
                case 0:
                    b.buildForLoop {
                        body()
                    }
                case 1:
                    b.buildWhileLoop({ b.compare(intVar1, with: intVar2, using: .lessThan) }) {
                        body()
                    }
                    break
                case 2:
                    b.buildForInOfLoop(obj, type: .forIn, isAsync: false, header: .simple) {
                        vars, _ in
                        let loopVar = vars[0]
                        #expect(b.type(of: loopVar) == .string)
                        body()
                    }
                case 3:
                    b.buildForInOfLoop(obj, type: .forOf, isAsync: false, header: .simple) {
                        vars, _ in
                        let loopVar = vars[0]
                        #expect(b.type(of: loopVar) == .jsAnything)
                        body()
                    }
                case 4:
                    b.buildRepeatLoop(n: 10) { _ in
                        body()
                    }
                case 5:
                    b.buildPlainFunction(with: .parameters(n: 3)) { _ in
                        body()
                    }
                default:
                    fatalError()
                }

                #expect(b.type(of: intVar1) == .integer)
                #expect(b.type(of: intVar2) == .integer)
                #expect(b.type(of: intVar3) == .integer)
                #expect(b.type(of: v) == .float | .jsString)
                #expect(
                    b.type(of: obj) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))

                b.reset()
            }
        }
    }

    @Test func testBuiltinTypeInference() {
        let builtinAType = ILType.integer
        let builtinBType = ILType.object(
            ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"])
        let builtinCType = ILType.function([] => .number)

        let env = JavaScriptEnvironment(additionalBuiltins: [
            "A": builtinAType,
            "B": builtinBType,
            "C": builtinCType,
        ])

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let va = b.createNamedVariable(forBuiltin: "A")
            let vb = b.createNamedVariable(forBuiltin: "B")
            let vc = b.createNamedVariable(forBuiltin: "C")

            #expect(b.type(of: va) == builtinAType)
            #expect(b.type(of: vb) == builtinBType)
            #expect(b.type(of: vc) == builtinCType)
        }
    }

    @Test func testPropertyTypeInference() {
        let propFooType = ILType.float
        let propBarType = ILType.function([] => .jsAnything)
        let propBazType = ILType.object(withProperties: ["a", "b", "c"])
        let additionalObjectGroups: [ObjectGroup] = [
            ObjectGroup(
                name: "B",
                instanceType: .object(ofGroup: "B", withProperties: ["foo", "bar"]),
                properties: [
                    "foo": propFooType,
                    "bar": propBarType,
                ],
                overloads: [:]),
            ObjectGroup(
                name: "C",
                instanceType: .object(ofGroup: "C", withProperties: ["baz"]),
                properties: [
                    "baz": propBazType
                ],
                overloads: [:]),
        ]

        let builtins: [String: ILType] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C"),
        ]

        let env = JavaScriptEnvironment(
            additionalBuiltins: builtins, additionalObjectGroups: additionalObjectGroups)

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let aObj = b.createNamedVariable(forBuiltin: "A")
            #expect(b.type(of: aObj) == .jsAnything)
            let bObj = b.createNamedVariable(forBuiltin: "B")
            #expect(b.type(of: bObj) == .object(ofGroup: "B"))

            // .foo and .bar are both known for B objects
            var p = b.getProperty("foo", of: bObj)
            #expect(b.type(of: p) == propFooType)
            p = b.getProperty("bar", of: bObj)
            #expect(b.type(of: p) == propBarType)

            // But .baz is only known on C objects
            p = b.getProperty("baz", of: bObj)
            #expect(b.type(of: p) == .jsAnything)

            let cObj = b.createNamedVariable(forBuiltin: "C")
            p = b.getProperty("baz", of: cObj)
            #expect(b.type(of: p) == propBazType)

            // No property types are known for A objects though.
            p = b.getProperty("foo", of: aObj)
            #expect(b.type(of: p) == .jsAnything)
            p = b.getProperty("bar", of: aObj)
            #expect(b.type(of: p) == .jsAnything)
            p = b.getProperty("baz", of: aObj)
            #expect(b.type(of: p) == .jsAnything)
        }
    }

    @Test func testMethodTypeInference() {
        let m1Signature = [] => .float
        let m2Signature = [.string] => .object(ofGroup: "X")
        let groups: [ObjectGroup] = [
            ObjectGroup(
                name: "B",
                instanceType: .object(ofGroup: "B", withMethods: ["m1"]),
                properties: [:],
                methods: ["m1": m1Signature]),
            ObjectGroup(
                name: "C",
                instanceType: .object(ofGroup: "C", withMethods: ["m2"]),
                properties: [:],
                methods: ["m2": m2Signature]),
        ]

        let builtins: [String: ILType] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C"),
        ]

        let env = JavaScriptEnvironment(
            additionalBuiltins: builtins, additionalObjectGroups: groups)

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let aObj = b.createNamedVariable(forBuiltin: "A")
            #expect(b.type(of: aObj) == .jsAnything)
            let bObj = b.createNamedVariable(forBuiltin: "B")
            #expect(b.type(of: bObj) == .object(ofGroup: "B"))

            var r = b.callMethod("m1", on: bObj)
            #expect(b.type(of: r) == .float)

            r = b.callMethod("m2", on: bObj)
            #expect(b.type(of: r) == .jsAnything)

            let cObj = b.createNamedVariable(forBuiltin: "C")
            r = b.callMethod("m2", on: cObj)
            #expect(b.type(of: r) == .object(ofGroup: "X"))
        }
    }

    @Test func testConstructorTypeInference() {
        let aConstructorType = ILType.constructor([.rest(.jsAnything)] => .object(ofGroup: "A"))
        let builtins: [String: ILType] = [
            "A": aConstructorType
        ]

        let env = JavaScriptEnvironment(additionalBuiltins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let A = b.createNamedVariable(forBuiltin: "A")
            #expect(b.type(of: A) == aConstructorType)

            // For a known constructor, the resulting type can be inferred
            let a = b.construct(A)
            #expect(b.type(of: a) == .object(ofGroup: "A"))

            // For an unknown constructor, the result will be .object()
            let B = b.createNamedVariable(forBuiltin: "B")
            let b_ = b.construct(B)
            #expect(b.type(of: b_) == .object())

            // For a self-defined constructor, we can infer more details about the constructed type
            let C = b.buildConstructor(with: .parameters(n: 2)) { args in
                let this = args[0]
                b.setProperty("foo", of: this, to: args[1])
                b.setProperty("bar", of: this, to: args[2])
            }
            let c = b.construct(C)
            #expect(b.type(of: c) == .object(withProperties: ["foo", "bar"]))
        }
    }

    @Test func testReturnTypeInference() {
        let aFunctionType = ILType.function([.rest(.jsAnything)] => .primitive)
        let builtins: [String: ILType] = [
            "a": aFunctionType
        ]

        let env = JavaScriptEnvironment(additionalBuiltins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let a = b.createNamedVariable(forBuiltin: "a")
            #expect(b.type(of: a) == aFunctionType)

            // For a known function, the resulting type can be inferred
            var r = b.callFunction(a)
            #expect(b.type(of: r) == .primitive)

            // For an unknown function, the result will be .jsAnything
            let c = b.createNamedVariable(forBuiltin: "c")
            r = b.callFunction(c)
            #expect(b.type(of: r) == .jsAnything)
        }
    }

    @Test func testArrayCreation() {
        let env = JavaScriptEnvironment()

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let a = b.createArray(with: [])
            #expect(b.type(of: a) == ILType.jsArray)
        }
    }

    @Test func testParameterizedArrayCreation() {
        let propFooType = ILType.float
        let fooElement = ILType.object(ofGroup: "FooElement", withProperties: ["foo"])
        let additionalObjectGroups: [ObjectGroup] = [
            ObjectGroup(
                name: "FooElement",
                instanceType: fooElement,
                properties: [
                    "foo": propFooType
                ],
                methods: [:])
        ]

        let env = JavaScriptEnvironment(additionalObjectGroups: additionalObjectGroups)
        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let a1 = b.createArray(with: [], elementGroupName: "FooElement")
            #expect(b.type(of: a1) == ILType.createJsArrayType(ofElementType: fooElement))

            // For an unregistered group, resulting `jsArray` will have element type `.jsAnything`
            let a2 = b.createArray(with: [], elementGroupName: "UnknownGroup")
            #expect(b.type(of: a2) == ILType.createJsArrayType(ofElementType: .jsAnything))

            let a3 = b.createArray(with: [])
            #expect(b.type(of: a3) == ILType.jsArray)
        }
    }

    @Test func testMapCreation() {
        let env = JavaScriptEnvironment()

        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let m = b.createMap(withKeys: [], withValues: [])
            #expect(b.type(of: m) == ILType.jsMap)
        }
    }

    @Test func testParameterizedMapCreation() {
        let fooElement = ILType.object(ofGroup: "FooElement", withProperties: ["foo"])
        let stringElement = ILType.object(ofGroup: "StringElement")
        let additionalObjectGroups: [ObjectGroup] = [
            ObjectGroup(
                name: "FooElement",
                instanceType: fooElement,
                properties: [
                    "foo": .float
                ],
                methods: [:]),
            ObjectGroup(
                name: "StringElement",
                instanceType: stringElement,
                properties: [:],
                methods: [:]),
        ]

        let env = JavaScriptEnvironment(additionalObjectGroups: additionalObjectGroups)
        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let keyGroups = ["StringElement", "UnknownGroup", nil]
            let valueGroups = ["FooElement", "UnknownGroup", nil]
            for (keyGroupName, valueGroupName) in zip(keyGroups, valueGroups) {
                let m = b.createMap(
                    withKeys: [], withValues: [], keyGroupName: keyGroupName,
                    valueGroupName: valueGroupName)

                if keyGroupName == nil || valueGroupName == nil {
                    // If either group name is nil, resulting `jsMap` will have both key and value types set to nil
                    #expect(b.type(of: m) == ILType.createJsMapType())
                    continue
                }

                // Unregistered group names get resolved to jsAnything
                let keyElement = keyGroupName != "UnknownGroup" ? stringElement : .jsAnything
                let valueElement = valueGroupName != "UnknownGroup" ? fooElement : .jsAnything

                #expect(
                    b.type(of: m)
                        == ILType.createJsMapType(ofKeyType: keyElement, ofValueType: valueElement))
            }
        }
    }

    @Test func testSuperBinding() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let superclass = b.buildClassDefinition { cls in
                cls.addConstructor(with: .parameters([.integer])) { params in
                    let this = params[0]
                    #expect(b.type(of: this) == .object(ofGroup: "_fuzz_Class0"))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .integer)
                }

                cls.addInstanceProperty("a")

                cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this) == .object(ofGroup: "_fuzz_Class0", withProperties: ["a"]))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .float)

                    b.doReturn(b.loadString("foobar"))
                }
            }

            let superType = ILType.object(
                ofGroup: "_fuzz_Class0", withProperties: ["a"], withMethods: ["f"])
            #expect(
                b.type(of: superclass) == .object(ofGroup: "_fuzz_Constructor0")
                    + .constructor([.integer] => superType))

            let v = b.loadInt(42)
            let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
                cls.addInstanceProperty("b", value: v)

                cls.addConstructor(with: .parameters([.string])) { params in
                    #expect(
                        b.currentSuperConstructorType() == .object(ofGroup: "_fuzz_Constructor0")
                            + .constructor(
                                [.integer]
                                    => .object(
                                        ofGroup: "_fuzz_Class0", withProperties: ["a"],
                                        withMethods: ["f"])))
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f"]))
                    #expect(b.currentSuperType() == superType)

                    b.callSuperConstructor(withArgs: [b.loadFloat(42)])
                }

                cls.addInstanceMethod("g", with: .parameters(.jsAnything)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f"]))
                    #expect(b.currentSuperType() == superType)
                }
            }
            #expect(
                b.type(of: cls) == .object(ofGroup: "_fuzz_Constructor2")
                    + .constructor(
                        [.string]
                            => .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f", "g"])))
        }
    }

    @Test func testBigintTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let i1 = b.loadInt(42)
            let i2 = b.loadInt(43)
            #expect(b.type(of: i1).Is(.integer))
            let bi1 = b.loadBigInt(4_200_000_000)
            let bi2 = b.loadBigInt(4_300_000_000)
            #expect(b.type(of: bi1).Is(.bigint))

            for op in UnaryOperator.allCases {
                // Logical operators produce .boolean in any case
                guard op != .LogicalNot else { continue }
                let r1 = b.unary(op, i1)
                #expect(!b.type(of: r1).MayBe(.bigint))
                let r2 = b.unary(op, bi1)
                #expect(b.type(of: r2).Is(.bigint))
            }

            for op in BinaryOperator.allCases {
                // Logical operators produce .boolean in any case
                guard op != .LogicOr && op != .LogicAnd else { continue }
                let r1 = b.binary(i1, i2, with: op)
                #expect(!b.type(of: r1).MayBe(.bigint))
                let r2 = b.binary(i1, bi2, with: op)
                // This isn't really necessary, as mixing types in this way
                // would lead to an exception in JS. Currently, we handle
                // it like this though.
                #expect(b.type(of: r2).MayBe(.bigint))
                let r3 = b.binary(bi1, bi2, with: op)
                #expect(b.type(of: r3).Is(.bigint))
            }

            for op in BinaryOperator.allCases {
                let i3 = b.loadInt(45)
                let i4 = b.loadInt(46)
                #expect(b.type(of: i3).Is(.integer))
                let bi3 = b.loadBigInt(4_200_000_000)
                let bi4 = b.loadBigInt(4_300_000_000)
                #expect(b.type(of: bi3).Is(.bigint))

                // Logical operators produce .boolean in any case
                guard op != .LogicOr && op != .LogicAnd else { continue }
                b.reassign(variable: i3, value: i4, with: op)
                #expect(!b.type(of: i3).MayBe(.bigint))
                b.reassign(variable: i3, value: bi4, with: op)
                // This isn't really necessary, as mixing types in this way
                // would lead to an exception in JS. Currently, we handle
                // it like this though.
                #expect(b.type(of: i3).MayBe(.bigint))
                b.reassign(variable: bi3, value: bi4, with: op)
                #expect(b.type(of: bi3).Is(.bigint))
            }
        }
    }

    @Test func testWhileLoopHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v1 = b.loadInt(0)
            let v2 = b.loadInt(1)
            // The header executes unconditionally, but the body does not
            b.buildWhileLoop({
                b.reassign(variable: v1, value: b.loadString("foo"))
                return b.loadBool(false)
            }) {
                b.reassign(variable: v2, value: b.loadString("bar"))
            }

            #expect(b.type(of: v1) == .jsString)
            #expect(b.type(of: v2) == .integer | .jsString)
        }
    }

    @Test func testDoWhileLoopHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v1 = b.loadInt(0)
            let v2 = b.loadInt(1)
            // Both the header and the body execute unconditionally
            b.buildDoWhileLoop(
                do: {
                    b.reassign(variable: v2, value: b.loadString("foo"))
                },
                while: {
                    b.reassign(variable: v1, value: b.loadString("bar"))
                    return b.loadBool(false)
                })

            #expect(b.type(of: v1) == .jsString)
            #expect(b.type(of: v2) == .jsString)
        }
    }

    @Test func testForLoopHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v1 = b.loadInt(0)
            let v2 = b.loadInt(1)
            let v3 = b.loadInt(2)
            let v4 = b.loadInt(3)
            // The initializer block and the condition block are always executed.
            // The afterthought and body block may not be executed.
            b.buildForLoop(
                {
                    b.reassign(variable: v1, value: b.loadString("foo"))
                },
                {
                    b.reassign(variable: v2, value: b.loadString("bar"))
                    return b.loadBool(false)
                },
                {
                    b.reassign(variable: v3, value: b.loadString("baz"))
                }
            ) {
                b.reassign(variable: v4, value: b.loadString("bla"))
            }

            #expect(b.type(of: v1) == .jsString)
            #expect(b.type(of: v2) == .jsString)
            #expect(b.type(of: v3) == .integer | .jsString)
            #expect(b.type(of: v4) == .integer | .jsString)
        }
    }

    @Test func testForLoopLoopVariableTyping() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            b.buildForLoop(
                i: { b.loadInt(0) },
                { i in
                    #expect(b.type(of: i) == .integer)
                    return b.compare(i, with: b.loadInt(10), using: .lessThan)
                },
                { i in
                    #expect(b.type(of: i) == .integer)
                    b.unary(.PostInc, i)
                }
            ) { i in
                #expect(b.type(of: i) == .integer)
            }

            b.buildForLoop(
                i: { b.loadInt(0) },
                { i in
                    #expect(b.type(of: i) == .integer)
                    b.buildForLoop(
                        i: { b.loadFloat(12.34) },
                        { i in
                            #expect(b.type(of: i) == .float)
                            return b.loadBool(false)
                        }, { i in #expect(b.type(of: i) == .float) }
                    ) { i in
                        #expect(b.type(of: i) == .float)
                    }
                    return b.compare(i, with: b.loadInt(10), using: .lessThan)

                },
                { i in
                    #expect(b.type(of: i) == .integer)
                    b.unary(.PostInc, i)
                }
            ) { i in
                #expect(b.type(of: i) == .integer)
            }
        }
    }

    @Test func testSwitchStatementHandling() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let v0 = b.loadInt(42)
            let v1 = b.createObject(with: ["foo": v0])
            let v2 = b.getProperty("foo", of: v1)
            let v3 = b.loadInt(1337)
            let v4 = b.loadString("42")

            b.buildSwitch(on: v2) { swtch in
                swtch.addCase(v3) {
                    #expect(
                        b.type(of: v1) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"])
                    )
                    b.setProperty("bar", of: v1, to: v0)
                    b.setProperty("baz", of: v1, to: v0)
                    #expect(
                        b.type(of: v1)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "baz"]))

                    #expect(b.type(of: v0) == .integer)
                    let stringVar = b.loadString("foobar")
                    b.reassign(variable: v0, value: stringVar)
                    #expect(b.type(of: v0) == .jsString)
                }
                swtch.addDefaultCase {
                    #expect(
                        b.type(of: v1) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"])
                    )
                    b.setProperty("bar", of: v1, to: v0)
                    b.setProperty("qux", of: v1, to: v0)
                    #expect(
                        b.type(of: v1)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "qux"]))

                    #expect(b.type(of: v0) == .integer)
                    let boolVal = b.loadBool(false)
                    b.reassign(variable: v0, value: boolVal)
                    #expect(b.type(of: v0) == .boolean)
                }
                swtch.addCase(v4) {
                    #expect(
                        b.type(of: v1) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"])
                    )
                    b.setProperty("bar", of: v1, to: v0)
                    b.setProperty("bla", of: v1, to: v0)
                    #expect(
                        b.type(of: v1)
                            == .object(
                                ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar", "bla"]))

                    #expect(b.type(of: v0) == .integer)
                    let floatVar = b.loadFloat(13.37)
                    b.reassign(variable: v0, value: floatVar)
                    #expect(b.type(of: v0) == .float)
                }
            }

            #expect(b.type(of: v0) == .float | .boolean | .jsString)
            #expect(
                b.type(of: v1) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo", "bar"]))
            #expect(b.type(of: v3) == .integer)
            #expect(b.type(of: v4) == .jsString)
        }
    }

    @Test func testSwitchStatementHandling2() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let i1 = b.loadInt(42)
            let i2 = b.loadInt(42)
            b.buildSwitch(on: i1) { swtch in
                swtch.addDefaultCase {
                    #expect(b.type(of: i1) == .integer)
                    #expect(b.type(of: i2) == .integer)
                    b.reassign(variable: i2, value: b.loadString("bar"))
                }
            }

            #expect(b.type(of: i1) == .integer)
            #expect(b.type(of: i2) == .jsString)
        }
    }

    @Test func testSwitchStatementHandling3() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let i1 = b.loadInt(42)
            let i2 = b.loadInt(43)
            let i3 = b.loadInt(44)

            let v = b.loadString("foobar")

            b.buildSwitch(on: i1) { swtch in
                swtch.addCase(i2) {
                    #expect(b.type(of: v) == .jsString)
                    b.reassign(variable: v, value: b.loadFloat(13.37))
                    #expect(b.type(of: v) == .float)
                }

                swtch.addCase(i3) {
                    #expect(b.type(of: v) == .jsString)
                    b.reassign(variable: v, value: b.loadBool(false))
                    #expect(b.type(of: v) == .boolean)
                }
            }

            #expect(b.type(of: v) == .float | .boolean | .jsString)
        }
    }

    @Test func testSwitchStatementHandling4() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let i1 = b.loadInt(42)
            #expect(b.type(of: i1) == .integer)
            b.buildSwitch(on: i1) { _ in
            }
            #expect(b.type(of: i1) == .integer)
        }
    }

    @Test func testDestructObjectTypeInference() {
        let objectGroups: [ObjectGroup] = [
            ObjectGroup(
                name: "O",
                instanceType: .object(ofGroup: "O", withProperties: ["foo", "bar", "baz"]),
                properties: [
                    "foo": .integer,
                    "bar": .string,
                    "baz": .boolean,
                ],
                methods: [:])
        ]

        let env = JavaScriptEnvironment(
            additionalBuiltins: [:], additionalObjectGroups: objectGroups)
        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let obj = b.createNamedVariable(forBuiltin: "myO")
            b.setType(
                ofVariable: obj, to: .object(ofGroup: "O", withProperties: ["foo", "bar", "baz"]))

            let outputs = b.destruct(obj, selecting: ["foo", "bar"], hasRestElement: true)
            #expect(b.type(of: outputs[0]) == .integer)
            #expect(b.type(of: outputs[1]) == .string)
            #expect(b.type(of: outputs[2]) == .object(withProperties: ["baz"]))
        }
    }

    @Test func testDestructAndReassignTypeInference() {
        let objectGroups: [ObjectGroup] = [
            ObjectGroup(
                name: "O",
                instanceType: .object(ofGroup: "O", withProperties: ["foo"]),
                properties: [
                    "foo": .integer
                ],
                methods: [:])
        ]

        let env = JavaScriptEnvironment(
            additionalBuiltins: [:], additionalObjectGroups: objectGroups)
        let fuzzer = makeMockFuzzer(environment: env)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let obj = b.createNamedVariable(forBuiltin: "myO")
            b.setType(
                ofVariable: obj, to: .object(ofGroup: "O", withProperties: ["foo"]))

            let v1 = b.loadInt(0)
            let v2 = b.loadInt(0)
            let v3 = b.loadInt(0)

            let computedKey = b.loadString("bar")
            let defaultVal = b.loadString("default")

            let props = [
                DestructuringPattern.ObjectProperty(key: .string("foo"), target: .flatBinding),
                DestructuringPattern.ObjectProperty(
                    key: .computed, target: .flatBinding, hasDefaultValue: true),
            ]
            let pattern = DestructuringPattern.ObjectPattern(
                properties: props, hasRestElement: true)

            // DestructAndReassign: ({ "foo": v1, [computedKey]: v2 = defaultVal, ...v3 } = obj)
            // Inputs must be strictly ordered: [obj, computedKey, v1, v2, defaultVal, v3]
            b.destruct(obj, using: .object(pattern), into: [computedKey, v1, v2, defaultVal, v3])

            #expect(b.type(of: v1) == .integer)
            #expect(b.type(of: v2) == .jsAnything)
            #expect(b.type(of: v3) == .object())
        }
    }

    @Test func testForOfLoopDestructTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let arr = b.createArray(with: [b.loadInt(42), b.loadString("foo")])

            let pattern = DestructuringPattern.array(
                DestructuringPattern.ArrayPattern(
                    elements: [
                        DestructuringPattern.ArrayElement(
                            target: .flatBinding, hasDefaultValue: false),
                        DestructuringPattern.ArrayElement(
                            target: .flatBinding, hasDefaultValue: false),
                    ],
                    restTarget: .none
                )
            )

            b.buildForInOfLoop(
                arr, type: .forOf, isAsync: false, header: .destruct(pattern: pattern)
            ) {
                args, _ in
                let v0 = args[0]
                let v1 = args[1]
                // We cannot infer specific types for elements of an array destructuring pattern inside a loop yet,
                // so we expect `.jsAnything`. However, the code shouldn't crash and types should be properly initialized.
                #expect(b.type(of: v0) == .jsAnything)
                #expect(b.type(of: v1) == .jsAnything)
            }
        }
    }

    @Test func testWasmTypeInference() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            b.buildWasmModule { m in
                m.addWasmFunction(with: [] => []) { f, _, _ in
                    let ci32 = f.consti32(1337)
                    let ci64 = f.consti64(1338)
                    let cf32 = f.constf32(13.37)
                    let cf64 = f.constf64(13.38)

                    #expect(.wasmi32 == b.type(of: ci32))
                    #expect(.wasmi64 == b.type(of: ci64))
                    #expect(.wasmf32 == b.type(of: cf32))
                    #expect(.wasmf64 == b.type(of: cf64))
                    #expect(b.type(of: ci32).Is(.wasmPrimitive))
                    #expect(b.type(of: ci64).Is(.wasmPrimitive))
                    #expect(b.type(of: cf32).Is(.wasmPrimitive))
                    #expect(b.type(of: cf64).Is(.wasmPrimitive))
                    return []
                }
            }
        }
    }

    @Test func testWasmStructTypeDefinition() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let structType = b.wasmDefineTypeGroup {
                let structType = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(type: .wasmi32, mutability: true),
                        WasmStructTypeDescription.Field(type: .wasmi64, mutability: true),
                    ],
                    indexTypes: [])
                let structType2 = b.wasmDefineStructType(
                    fields: [
                        WasmStructTypeDescription.Field(type: .wasmi32, mutability: true),
                        WasmStructTypeDescription.Field(type: .wasmi64, mutability: true),
                    ],
                    indexTypes: [])
                #expect(b.type(of: structType).Is(.wasmTypeDef()))
                // Despite having identical structure, the two struct types are not comparable.
                #expect(!b.type(of: structType).Is(b.type(of: structType2)))
                #expect(!b.type(of: structType2).Is(b.type(of: structType)))
                let desc =
                    b.type(of: structType).wasmTypeDefinition!.description!
                    as! WasmStructTypeDescription
                #expect(desc.fields.count == 2)
                #expect(desc.fields[0].type == .wasmi32)
                #expect(desc.fields[1].type == .wasmi64)
                return [structType, structType2]
            }[0]

            #expect(b.type(of: structType).Is(.wasmTypeDef()))
            let desc =
                b.type(of: structType).wasmTypeDefinition!.description!
                as! WasmStructTypeDescription
            #expect(desc.fields.count == 2)
            #expect(desc.fields[0].type == .wasmi32)
            #expect(desc.fields[1].type == .wasmi64)
        }
    }

    @Test func testTypingOfDeletedMethods() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let object = b.buildObjectLiteral { o in
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadString("foo"))
                }
            }

            #expect(b.type(of: object) == .object(ofGroup: "_fuzz_Object0", withMethods: ["foo"]))

            b.deleteProperty("foo", of: object)

            #expect(b.type(of: object) == .object(ofGroup: "_fuzz_Object0", withMethods: []))
        }
    }

    @Test func testTypingOfPropertyForMethod() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let object = b.buildObjectLiteral { o in
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadString("foo"))
                }
            }

            #expect(b.type(of: object) == .object(ofGroup: "_fuzz_Object0", withMethods: ["foo"]))
            // When reading a "method" as a regular property, the method becomes a function where
            // `this` isn't bound to `object`. The type system should still correctly infer the
            // signatures of such functions.
            let fooProperty = b.getProperty("foo", of: object)
            #expect(b.type(of: fooProperty) == .function([] => .jsString))

            // Actions like `setProperty` modify the ILType but do not modify any information stored in
            // the ObjectGroupManager.
            b.setProperty("foo", of: object, to: b.loadInt(123))
            #expect(
                b.type(of: object)
                    == .object(
                        ofGroup: "_fuzz_Object0", withProperties: ["foo"], withMethods: ["foo"]))
            let fooPropertyNew = b.getProperty("foo", of: object)
            #expect(b.type(of: fooPropertyNew) == .function([] => .jsString))
        }
    }

    @Test func testTypingOfDuplicateProperties() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let intVal = b.loadInt(123)
            let stringVal = b.loadString("abc")

            let object = b.buildObjectLiteral { o in
                o.addProperty("foo", as: intVal)
                o.addProperty("foo", as: stringVal)
            }

            #expect(
                b.type(of: object) == .object(ofGroup: "_fuzz_Object0", withProperties: ["foo"]))
            let fooProperty = b.getProperty("foo", of: object)
            #expect(b.type(of: fooProperty) == .jsString)
            let fooResult = b.callMethod("foo", on: object)
            #expect(b.type(of: fooResult) == .jsAnything)
        }
    }

    @Test func testTypingOfDuplicateMethods() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let object = b.buildObjectLiteral { o in
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadString("abc"))
                }
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadInt(123))
                }
            }

            #expect(b.type(of: object) == .object(ofGroup: "_fuzz_Object0", withMethods: ["foo"]))
            let fooProperty = b.getProperty("foo", of: object)
            #expect(b.type(of: fooProperty) == .function([] => .integer))
            let fooResult = b.callMethod("foo", on: object)
            #expect(b.type(of: fooResult) == .integer)
        }
    }

    @Test func testTypingOfDuplicateMixedMethodAndProperty() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()
            let intVal = b.loadInt(123)

            let object = b.buildObjectLiteral { o in
                o.addProperty("foo", as: intVal)
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadString("abc"))
                }
            }

            // In JS, the last value a property is set to, overwrites the previous value. Since
            // Fuzzilli tracks properties and methods separately, they do not overwrite each other in
            // the ObjectGroupManager (but maybe should).
            #expect(
                b.type(of: object)
                    == .object(
                        ofGroup: "_fuzz_Object0", withProperties: ["foo"], withMethods: ["foo"]))
            let fooProperty = b.getProperty("foo", of: object)
            #expect(b.type(of: fooProperty) == .integer)
            let fooResult = b.callMethod("foo", on: object)
            #expect(b.type(of: fooResult) == .jsString)
        }
    }

    @Test func testDynamicObjectGroupTypingOfClassesWithGettersAndSetters() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let classDef = b.buildClassDefinition { cls in
                cls.addConstructor(with: .parameters([.integer])) { params in
                    let this = params[0]
                    #expect(b.type(of: this) == .object(ofGroup: "_fuzz_Class0"))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .integer)
                }

                cls.addInstanceProperty("a")

                cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this) == .object(ofGroup: "_fuzz_Class0", withProperties: ["a"]))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .float)

                    b.doReturn(b.loadString("foobar"))
                }

                cls.addInstanceGetter(for: "foo") { _ in
                    b.doReturn(b.loadBigInt(3))
                }

                cls.addInstanceSetter(for: "bar") { _, newVariable in
                    b.doReturn(newVariable)
                }

                cls.addInstanceSetter(for: "baz") { _, _ in
                }

                cls.addInstanceSetter(for: "blub") { _, newVariable in
                    b.doReturn(b.loadNull())
                }
            }

            let instanceType = ILType.object(
                ofGroup: "_fuzz_Class0", withProperties: ["a", "foo", "bar", "baz", "blub"],
                withMethods: ["f"])
            #expect(
                b.type(of: classDef) == .object(ofGroup: "_fuzz_Constructor0")
                    + .constructor([.integer] => instanceType))

            let instance = b.construct(classDef, withArgs: [b.loadInt(42)])

            #expect(b.methodSignatures(of: "f", on: instance) == [[.float] => .jsString])
            #expect(b.type(ofProperty: "foo", on: instance) == .bigint)
            #expect(b.type(ofProperty: "bar", on: instance) == .jsAnything)
            #expect(b.type(ofProperty: "baz", on: instance) == .undefined)
            #expect(b.type(ofProperty: "blub", on: instance) == .nullish)
        }
    }

    @Test func testDynamicObjectGroupTypingOfClassesWithSubclasses() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let classDef = b.buildClassDefinition { cls in
                cls.addConstructor(with: .parameters([.integer])) { params in
                    let this = params[0]
                    #expect(b.type(of: this) == .object(ofGroup: "_fuzz_Class0"))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .integer)
                }

                cls.addInstanceProperty("a")

                cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this) == .object(ofGroup: "_fuzz_Class0", withProperties: ["a"]))
                    #expect(b.currentSuperType() == .object())

                    #expect(b.type(of: params[1]) == .float)

                    b.doReturn(b.loadString("foobar"))
                }
            }

            let instanceType = ILType.object(
                ofGroup: "_fuzz_Class0", withProperties: ["a"], withMethods: ["f"])
            #expect(
                b.type(of: classDef) == .object(ofGroup: "_fuzz_Constructor0")
                    + .constructor([.integer] => instanceType))

            let v = b.loadInt(42)
            let cls = b.buildClassDefinition(withSuperclass: classDef) { cls in
                cls.addInstanceProperty("b", value: v)

                cls.addConstructor(with: .parameters([.string])) { params in
                    #expect(
                        b.currentSuperConstructorType() == .object(ofGroup: "_fuzz_Constructor0")
                            + .constructor(
                                [.integer]
                                    => .object(
                                        ofGroup: "_fuzz_Class0", withProperties: ["a"],
                                        withMethods: ["f"])))
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f"]))
                    #expect(b.currentSuperType() == instanceType)

                    b.callSuperConstructor(withArgs: [b.loadFloat(42)])
                }

                cls.addInstanceMethod("g", with: .parameters(.jsAnything)) { params in
                    let this = params[0]
                    #expect(
                        b.type(of: this)
                            == .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f"]))
                    #expect(b.currentSuperType() == instanceType)
                }
            }

            #expect(
                b.type(of: cls) == .object(ofGroup: "_fuzz_Constructor2")
                    + .constructor(
                        [.string]
                            => .object(
                                ofGroup: "_fuzz_Class2", withProperties: ["a", "b"],
                                withMethods: ["f", "g"])))

            let instance = b.construct(cls, withArgs: [b.loadString("bla")])

            #expect(b.methodSignatures(of: "f", on: instance) == [[.float] => .jsString])
            #expect(b.methodSignatures(of: "g", on: instance) == [[.jsAnything] => .undefined])
            #expect(b.type(ofProperty: "a", on: instance) == .jsAnything)
        }
    }

    @Test func testDynamicObjectGroupTypingOfLiterals() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let int = b.loadInt(42)

            let object = b.buildObjectLiteral { o in
                o.addMethod("foo", with: .parameters(n: 0)) { _ in
                    b.doReturn(b.loadString("foo"))
                }
                o.addProperty("bla", as: int)
            }

            #expect(
                b.type(of: object)
                    == .object(
                        ofGroup: "_fuzz_Object0", withProperties: ["bla"], withMethods: ["foo"]))
            #expect(b.type(ofProperty: "bla", on: object) == .integer)
        }
    }

    func dynamicObjectGroupTypingOfWasmModulesTestCase(isShared: Bool) {
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

        // We have to use the proper JavaScriptEnvironment here.
        // This ensures that we use the available builtins.
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        fuzzer.sync {

            let b = fuzzer.makeBuilder()

            let wasmGlobalf64: Variable = b.createWasmGlobal(
                value: .wasmf64(1337), isMutable: false)
            #expect(
                b.type(of: wasmGlobalf64)
                    == .object(
                        ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"],
                        withWasmType: WasmGlobalType(valueType: ILType.wasmf64, isMutable: false)))

            let maxPages: Int? = isShared ? 4 : nil
            let memory = b.createWasmMemory(minPages: 1, maxPages: maxPages, isShared: isShared)
            let jsTag = b.createWasmJSTag()

            let typeGroup = b.wasmDefineTypeGroup {
                return [b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)]
            }

            let plainFunction = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                let obj = b.buildObjectLiteral { obj in
                }
                b.doReturn(obj)
            }
            let wasmSignature = [] => [.wasmExternRef()]

            let typeDesc = b.type(of: typeGroup[0]).wasmTypeDefinition!.description!

            let module = b.buildWasmModule { wasmModule in
                // Defines one global
                wasmModule.addGlobal(wasmGlobal: .wasmi64(1339), isMutable: true)

                wasmModule.addMemory(minPages: 3, maxPages: maxPages, isShared: isShared)

                wasmModule.addTag(parameterTypes: [.wasmi32])

                // Function zero
                wasmModule.addWasmFunction(with: [] => []) { function, _, _ in
                    // This forces an import of the wasmGlobalf64, second global
                    function.wasmLoadGlobal(globalVariable: wasmGlobalf64)
                    // This forces an import and a re-export of the jsTag.
                    function.wasmBuildLegacyTryVoid(
                        body: { _ in },
                        catchClauses: [(tag: jsTag, body: { _, _, _ in })])
                    function.wasmUnreachable()
                    return []
                }

                // Function one
                wasmModule.addWasmFunction(with: [.wasmi32] => [.wasmi64]) {
                    function, label, args in
                    // Do a store to import the memory.
                    function.wasmMemoryStore(
                        memory: memory, dynamicOffset: function.consti32(0), value: args[0],
                        storeType: .I32StoreMem, staticOffset: 0)
                    return [function.consti64(1338)]
                }

                // Function two
                wasmModule.addWasmFunction(with: [.wasmf64] => [.wasmf64]) { function, label, _ in
                    let globalValue = function.wasmLoadGlobal(globalVariable: wasmGlobalf64)
                    return [globalValue]
                }

                // Function three
                wasmModule.addWasmFunction(with: [.wasmExternRef()] => [.wasmi32, .wasmi64]) {
                    function, label, _ in
                    return [function.consti32(1), function.consti64(2)]
                }

                // Function four
                wasmModule.addWasmFunction(
                    with: [] => [ILType.wasmIndexRef(typeDesc, nullability: true)]
                ) { function, label, _ in
                    return [
                        function.wasmArrayNewDefault(
                            arrayType: typeGroup[0], size: function.consti32(10))
                    ]
                }

                // Function five
                wasmModule.addWasmFunction(with: [] => [.wasmExternRef()]) { function, label, _ in
                    // This forces an import and we should see a re-exported function on the module.
                    return [
                        function.wasmJsCall(
                            function: plainFunction, withArgs: [], withWasmSignature: wasmSignature)!
                    ]
                }
            }

            let exports = module.loadExports()
            #expect(
                b.type(of: exports)
                    == .object(
                        ofGroup: "_fuzz_WasmExports1",
                        withProperties: ["wg0", "iwg0", "wm0", "iwm0", "wex0", "iwex0"],
                        withMethods: ["w0", "w1", "w2", "w3", "w4", "w5", "iw0"]))

            let fun0 = b.methodSignatures(of: module.getExportedMethod(at: 0), on: exports)
            let fun1 = b.methodSignatures(of: module.getExportedMethod(at: 1), on: exports)
            let fun2 = b.methodSignatures(of: module.getExportedMethod(at: 2), on: exports)
            let fun3 = b.methodSignatures(of: module.getExportedMethod(at: 3), on: exports)
            let fun4 = b.methodSignatures(of: module.getExportedMethod(at: 4), on: exports)
            let fun5 = b.methodSignatures(of: module.getExportedMethod(at: 5), on: exports)
            let reexportedFunction = b.methodSignatures(of: "iw0", on: exports)

            #expect(fun0 == [[] => .undefined])
            #expect(fun1 == [[.integer] => .bigint])
            #expect(fun2 == [[.float] => .float])
            #expect(fun3 == [[.jsAnything] => .jsArray])
            #expect(fun4 == [[] => .jsAnything])
            #expect(fun5 == [[] => .jsAnything])
            // Here the typer should be able to see the full JS signature.
            #expect(reexportedFunction == [[] => .object(ofGroup: "_fuzz_Object0")])

            let glob0 = b.getProperty("wg0", of: exports)
            #expect(
                b.type(of: glob0)
                    == .object(
                        ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"],
                        withWasmType: WasmGlobalType(valueType: .wasmi64, isMutable: true)))

            let glob1 = b.getProperty("iwg0", of: exports)
            #expect(
                b.type(of: glob1)
                    == .object(
                        ofGroup: "WasmGlobal", withProperties: ["value"], withMethods: ["valueOf"],
                        withWasmType: WasmGlobalType(valueType: .wasmf64, isMutable: false)))

            let mem0 = b.getProperty("wm0", of: exports)
            let memType = ILType.wasmMemory(
                limits: Limits(min: 3, max: maxPages), isShared: isShared)
            #expect(b.type(of: mem0) == memType)

            let importedMem = b.getProperty("iwm0", of: exports)
            let importedMemType = ILType.wasmMemory(
                limits: Limits(min: 1, max: maxPages), isShared: isShared)
            #expect(b.type(of: importedMem) == importedMemType)

            let reexportedJsTag = b.getProperty("iwex0", of: exports)
            #expect(b.type(of: reexportedJsTag) == b.type(of: jsTag))
        }
    }

    @Test func testDynamicObjectGroupTypingOfWasmModules() {
        dynamicObjectGroupTypingOfWasmModulesTestCase(isShared: false)
        dynamicObjectGroupTypingOfWasmModulesTestCase(isShared: true)
    }

    @Test func testBuiltinPrototypes() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            // Array.prototype
            let arrayBuiltin = b.createNamedVariable(forBuiltin: "Array")
            #expect(b.type(of: arrayBuiltin).Is(.object(ofGroup: "ArrayConstructor")))
            let arrayProto = b.getProperty("prototype", of: arrayBuiltin)
            #expect(b.type(of: arrayProto).Is(.object(ofGroup: "Array")))
            let signatures = b.methodSignatures(of: "indexOf", on: arrayProto)
            #expect(signatures == [[.jsAnything, .opt(.integer)] => .integer])
            let indexOf = b.getProperty("indexOf", of: arrayProto)
            #expect(
                b.type(of: indexOf)
                    == .unboundFunction(
                        [.jsAnything, .opt(.integer)] => .integer, receiver: .jsArray))

            // Date.prototype
            let dateBuiltin = b.createNamedVariable(forBuiltin: "Date")
            #expect(b.type(of: dateBuiltin).Is(.object(ofGroup: "DateConstructor")))
            let dateProto = b.getProperty("prototype", of: dateBuiltin)
            #expect(b.type(of: dateProto).Is(.object(ofGroup: "Date.prototype")))
            let getTime = b.getProperty("getTime", of: dateProto)
            #expect(b.type(of: getTime) == .unboundFunction([] => .number, receiver: .jsDate))

            // Promise.prototype
            let promiseBuiltin = b.createNamedVariable(forBuiltin: "Promise")
            #expect(b.type(of: promiseBuiltin).Is(.object(ofGroup: "PromiseConstructor")))
            let promiseProto = b.getProperty("prototype", of: promiseBuiltin)
            #expect(b.type(of: dateProto).Is(.object(ofGroup: "Date.prototype")))
            let then = b.getProperty("then", of: promiseProto)
            #expect(
                b.type(of: then)
                    == .unboundFunction([.function()] => .jsPromise, receiver: .jsPromise))

            // ArrayBuffer.prototype
            let arrayBufferBuiltin = b.createNamedVariable(forBuiltin: "ArrayBuffer")
            #expect(b.type(of: arrayBufferBuiltin).Is(.object(ofGroup: "ArrayBufferConstructor")))
            let arrayBufferProto = b.getProperty("prototype", of: arrayBufferBuiltin)
            #expect(b.type(of: arrayBufferProto).Is(.object(ofGroup: "ArrayBuffer.prototype")))
            let resize = b.getProperty("resize", of: arrayBufferProto)
            #expect(
                b.type(of: resize)
                    == .unboundFunction([.integer] => .undefined, receiver: .jsArrayBuffer))

            // ArrayBuffer.prototype
            let sharedArrayBufferBuiltin = b.createNamedVariable(forBuiltin: "SharedArrayBuffer")
            #expect(
                b.type(of: sharedArrayBufferBuiltin).Is(
                    .object(ofGroup: "SharedArrayBufferConstructor")))
            let sharedArrayBufferProto = b.getProperty("prototype", of: sharedArrayBufferBuiltin)
            #expect(
                b.type(of: sharedArrayBufferProto).Is(
                    .object(ofGroup: "SharedArrayBuffer.prototype")))
            let grow = b.getProperty("grow", of: sharedArrayBufferProto)
            #expect(
                b.type(of: grow)
                    == .unboundFunction([.number] => .undefined, receiver: .jsSharedArrayBuffer))

            // Temporal objects
            let temporalBuiltin = b.createNamedVariable(forBuiltin: "Temporal")
            #expect(b.type(of: temporalBuiltin).Is(.object(ofGroup: "Temporal")))
            let instantBuiltin = b.getProperty("Instant", of: temporalBuiltin)
            #expect(b.type(of: instantBuiltin).Is(.object(ofGroup: "TemporalInstantConstructor")))
            let instantProto = b.getProperty("prototype", of: instantBuiltin)
            #expect(b.type(of: instantProto).Is(.object(ofGroup: "Temporal.Instant.prototype")))
            let instantRound = b.getProperty("round", of: instantProto)
            #expect(
                b.type(of: instantRound).Is(
                    .unboundFunction(
                        [.plain(OptionsBag.jsTemporalDifferenceSettingOrRoundTo.group.instanceType)]
                            => ILType.jsTemporalInstant,
                        receiver: .jsTemporalInstant)))
            let randomString = b.randomVariable(forUseAs: .string)
            let fromCall = b.callMethod("from", on: instantBuiltin, withArgs: [randomString])
            #expect(b.type(of: fromCall).Is(.jsTemporalInstant))

            // We don't test Instant's prototype, since Instant only has nontrivial methods that
            // use options bag types that are still in flux.

            let durationBuiltin = b.getProperty("Duration", of: temporalBuiltin)
            #expect(b.type(of: durationBuiltin).Is(.object(ofGroup: "TemporalDurationConstructor")))
            let durationProto = b.getProperty("prototype", of: durationBuiltin)
            #expect(b.type(of: durationProto).Is(.object(ofGroup: "Temporal.Duration.prototype")))
            let negated = b.getProperty("negated", of: durationProto)
            #expect(
                b.type(of: negated)
                    == .unboundFunction([] => .jsTemporalDuration, receiver: .jsTemporalDuration))

        }
    }

    @Test func testTemporalRelativeTo() {
        var foundZDT = false
        var foundDT = false
        var foundDate = false
        var foundString = false
        // Test that relativeTo arguments are correctly generated
        // Annoyingly, we may generate undefined/.jsAnything here since the field may not exist.
        // We just call this a large number of times until we find everything.
        for i in 1..<100 {
            let fuzzer = makeMockFuzzer()
            fuzzer.sync {
                let b = fuzzer.makeBuilder()
                let temporalBuiltin = b.createNamedVariable(forBuiltin: "Temporal")
                let durationBuiltin = b.getProperty("Duration", of: temporalBuiltin)
                let duration = b.callMethod(
                    "from", on: durationBuiltin, withArgs: [b.loadString("P10D")])
                #expect(b.type(of: duration).Is(.jsTemporalDuration))
                let signature = chooseUniform(from: b.methodSignatures(of: "round", on: duration))
                let args = b.findOrGenerateArguments(forSignature: signature)
                let relativeTo = b.getProperty("relativeTo", of: args[0])
                let type = b.type(of: relativeTo)
                if type.Is(.string) {
                    foundString = true
                } else if type.Is(.jsTemporalZonedDateTime) {
                    #expect(type.group == "Temporal.ZonedDateTime")
                    foundZDT = true
                } else if type.Is(.jsTemporalPlainDateTime) {
                    #expect(type.group == "Temporal.PlainDateTime")
                    foundDT = true
                } else if type.Is(.jsTemporalPlainDate) {
                    #expect(type.group == "Temporal.PlainDate")
                    foundDate = true
                } else {
                    // If we got here, it must be because we never generated a relativeTo
                    // argument
                    let obj = b.type(of: args[0])
                    #expect(!obj.properties.contains("relativeTo"))
                }

            }
            // We don't want to run the test for 100 iterations, we only
            // want to run it for ~20 to ensure enough paths get tested,
            // and only if we do not generate all paths do we wish to run it more.
            if foundZDT && foundString && foundDate && foundDT && i > 20 {
                break
            }
        }
        #expect(foundZDT)
        #expect(foundString)
        #expect(foundDate)
        #expect(foundDT)
    }

    @Test func testWebAssemblyBuiltins() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let wasm = b.createNamedVariable(forBuiltin: "WebAssembly")
            #expect(b.type(of: wasm).Is(.object(ofGroup: "WebAssembly")))
            let wasmModuleConstructor = b.getProperty("Module", of: wasm)
            #expect(
                b.type(of: wasmModuleConstructor).Is(
                    .object(ofGroup: "WebAssemblyModuleConstructor")))
            let wasmModule = b.construct(wasmModuleConstructor)  // In theory this needs arguments.
            #expect(b.type(of: wasmModule).Is(.object(ofGroup: "WebAssembly.Module")))

            let wasmGlobalConstructor = b.getProperty("Global", of: wasm)
            #expect(
                b.type(of: wasmGlobalConstructor).Is(
                    .object(ofGroup: "WebAssemblyGlobalConstructor")))
            let wasmGlobal = b.construct(wasmGlobalConstructor)  // In theory this needs arguments.
            // We do not type the constructed value as globals as the "WasmGlobal" object group expects
            // to have a WasmTypeExtension.
            #expect(!b.type(of: wasmGlobal).Is(.object(ofGroup: "WasmGlobal")))
            // The high-level IL instruction produces properly typed wasm globals.
            let realWasmGlobal = b.createWasmGlobal(value: .wasmi32(1), isMutable: true)
            #expect(b.type(of: realWasmGlobal).Is(.object(ofGroup: "WasmGlobal")))
            #expect(b.type(of: realWasmGlobal).Is(ObjectGroup.jsWasmGlobal.instanceType))
            // The properly typed wasm globals can be used in conjunction with the
            // WebAssembly.Global.prototype.valueOf() function.
            let globalPrototype = b.getProperty("prototype", of: wasmGlobalConstructor)
            let valueOf = b.getProperty("valueOf", of: globalPrototype)
            #expect(
                b.type(of: valueOf)
                    == .unboundFunction(
                        [] => .jsAnything,
                        receiver: .object(
                            ofGroup: "WasmGlobal", withProperties: ["value"],
                            withMethods: ["valueOf"])))

            let wasmMemoryConstructor = b.getProperty("Memory", of: wasm)
            let wasmMemory = b.construct(wasmMemoryConstructor)  // In theory this needs arguments.
            #expect(!b.type(of: wasmMemory).Is(.object(ofGroup: "WasmMemory")))
            let realWasmMemory = b.createWasmMemory(minPages: 1, maxPages: 1, isShared: false)
            #expect(b.type(of: realWasmMemory).Is(.object(ofGroup: "WasmMemory")))
            #expect(b.type(of: realWasmMemory).Is(ObjectGroup.jsWasmMemory.instanceType))
            let memoryPrototype = b.getProperty("prototype", of: wasmMemoryConstructor)
            let grow = b.getProperty("grow", of: memoryPrototype)
            #expect(
                b.type(of: grow).Is(
                    .unboundFunction([.number] => .number, receiver: .object(ofGroup: "WasmMemory"))
                ))

            let wasmTableConstructor = b.getProperty("Table", of: wasm)
            let wasmTable = b.construct(wasmTableConstructor)  // In theory this needs arguments.
            #expect(!b.type(of: wasmTable).Is(.object(ofGroup: "WasmTable")))
            let realWasmTable = b.createWasmTable(
                elementType: .wasmAnyRef(), limits: .init(min: 0), isTable64: false)
            #expect(b.type(of: realWasmTable).Is(.object(ofGroup: "WasmTable")))
            #expect(b.type(of: realWasmTable).Is(ObjectGroup.wasmTable.instanceType))
            let tablePrototype = b.getProperty("prototype", of: wasmTableConstructor)
            let tableGrow = b.getProperty("grow", of: tablePrototype)
            #expect(
                b.type(of: tableGrow).Is(
                    .unboundFunction(
                        [.number, .opt(.jsAnything)] => .number,
                        receiver: .object(ofGroup: "WasmTable")
                    )))

            let wasmTagConstructor = b.getProperty("Tag", of: wasm)
            let wasmTag = b.construct(wasmTagConstructor)  // In theory this needs arguments.
            #expect(!b.type(of: wasmTag).Is(.object(ofGroup: "WasmTag")))
            let realWasmTag = b.createWasmTag(parameterTypes: [.wasmi32])
            #expect(b.type(of: realWasmTag).Is(.object(ofGroup: "WasmTag")))
            let tagPrototype = b.getProperty("prototype", of: wasmTagConstructor)
            #expect(
                b.type(of: tagPrototype)
                    == .object(ofGroup: "WasmTag.prototype", withProperties: ["constructor"]))

            let wasmExceptionConstructor = b.getProperty("Exception", of: wasm)
            let wasmException = b.construct(wasmExceptionConstructor)  // In theory this needs arguments.
            #expect(b.type(of: wasmException).Is(.object(ofGroup: "WebAssembly.Exception")))
            let isResult = b.callMethod("is", on: wasmException, withArgs: [realWasmTag])
            #expect(b.type(of: isResult) == .boolean)
            let exceptionPrototype = b.getProperty("prototype", of: wasmExceptionConstructor)
            #expect(
                b.type(of: exceptionPrototype).Is(
                    ObjectGroup.jsWebAssemblyExceptionPrototype.instanceType))
            let exceptionIs = b.getProperty("is", of: exceptionPrototype)
            #expect(
                b.type(of: exceptionIs).Is(
                    .unboundFunction(
                        [.plain(ObjectGroup.jsWasmTag.instanceType)] => ILType.boolean,
                        receiver: .object(ofGroup: "WebAssembly.Exception"))))
        }
    }

    @Test func testProducingGenerators() {
        // Make a simple object
        let mockEnum = ILType.enumeration(ofName: "MockEnum", withValues: ["mockValue"])
        let mockObject = ObjectGroup(
            name: "MockObject",
            instanceType: nil,
            properties: [
                "mockField": mockEnum
            ],
            methods: [:]
        )

        // Some things to keep track of how the generator was called
        var callCount = 0
        var returnedVar: Variable? = nil
        var generatedEnum: Variable? = nil
        // A simple generator
        func generateObject(builder: ProgramBuilder) -> Variable {
            callCount += 1
            let val = builder.loadEnum(mockEnum)
            generatedEnum = val
            let variable = builder.createObject(with: ["mockField": val])
            returnedVar = variable
            return variable
        }

        let mockNamedString = ILType.namedString(ofName: "NamedString")
        func generateString() -> String {
            callCount += 1
            return "mockStringValue"
        }

        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            fuzzer.environment.registerObjectGroup(mockObject)
            fuzzer.environment.registerEnumeration(mockEnum)
            fuzzer.environment.addProducingGenerator(
                forType: mockObject.instanceType, with: generateObject)
            fuzzer.environment.addNamedStringGenerator(
                forType: mockNamedString, with: generateString)
            let b = fuzzer.makeBuilder()
            b.buildPrefix()

            // Try to get it to invoke the generator
            let variable = b.findOrGenerateType(mockObject.instanceType)
            // Test that the generator was invoked
            #expect(callCount == 1)
            // Test that the returned variable matches the generated one
            #expect(variable == returnedVar)

            // Try to get it to invoke the string generator
            let variable2 = b.findOrGenerateType(mockNamedString)
            // Test that the generator was invoked
            #expect(callCount == 2)

            // Test that the returned variable gets typed correctly
            #expect(b.type(of: variable2).Is(mockNamedString))
            #expect(b.type(of: variable2).group == "NamedString")

            // We already generated a mockEnum, look for it.
            let foundEnum = b.randomVariable(ofType: mockEnum)!
            // Test that it picked up the existing generated variable.
            #expect(generatedEnum == foundEnum)

            // Test that the returned variable gets typed correctly.
            #expect(b.type(of: foundEnum).Is(mockEnum))
            #expect(b.type(of: foundEnum).group == "MockEnum")
        }
    }

    @Test func testFindConstructor() {
        for ctor in [
            "TemporalPlainMonthDayConstructor", "DateConstructor", "PromiseConstructor",
            "SymbolConstructor", "TemporalZonedDateTimeConstructor",
        ] {
            let fuzzer = makeMockFuzzer()
            fuzzer.sync {
                let b = fuzzer.makeBuilder()
                let temporalBuiltin = b.createNamedVariable(forBuiltin: "Temporal")
                let dateCtor = b.getProperty("PlainDate", of: temporalBuiltin)
                let requestedCtor = fuzzer.environment.type(ofGroup: ctor)
                let result = b.findOrGenerateType(requestedCtor)

                // The typer should not pick up the PlainDateConstructor we have in scope,
                // it should instead get the ctor from the global
                #expect(result != dateCtor)
                #expect(b.type(of: result).Is(requestedCtor))
            }
        }
    }

    @Test func testBufferUnionType() {
        // Explicitly verify the properties of the ArrayBuffer | SharedArrayBuffer union type.
        let unionType = ILType.jsArrayBuffer | .jsSharedArrayBuffer

        #expect(unionType.Is(.jsArrayBuffer | .jsSharedArrayBuffer))
        #expect(unionType.MayBe(.jsArrayBuffer))
        #expect(unionType.MayBe(.jsSharedArrayBuffer))
        #expect(!unionType.Is(.jsArrayBuffer))  // It's not *definitely* an ArrayBuffer
        #expect(!unionType.Is(.jsSharedArrayBuffer))

        // Common properties should be preserved
        #expect(unionType.properties.contains("byteLength"))
        #expect(unionType.methods.contains("slice"))

        // Disjoint properties/methods should be removed in the union
        #expect(!unionType.methods.contains("resize"))  // Only on ArrayBuffer
        #expect(!unionType.methods.contains("grow"))  // Only on SharedArrayBuffer

        #expect(unionType.group == nil)
    }

    @Test func testIntEnumerationCustomName() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let mockIntEnum = ILType.intEnumeration(ofName: "MockIntEnum", withValues: [1337, 42])
            fuzzer.environment.registerEnumeration(mockIntEnum)

            let v1 = b.loadInt(1337, customName: "MockIntEnum")
            let v2 = b.loadInt(1337)

            // v1 should be typed as the enumeration
            #expect(b.type(of: v1).group == "MockIntEnum")
            #expect(b.type(of: v1).isEnumeration)
            #expect(b.type(of: v1).Is(mockIntEnum))
            #expect(b.type(of: v1).Is(.integer))

            // v2 should be typed as a generic integer
            #expect(b.type(of: v2).group == nil)
            #expect(!b.type(of: v2).isEnumeration)
            #expect(b.type(of: v2).Is(.integer))
        }
    }

    @Test func testRawWasmModuleTyping() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let bytes: [UInt8] = [0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]
            let metadata = WasmModuleMetadata(
                functions: [
                    WasmModuleMetadata.FunctionExport(
                        name: "foo",
                        signature: Signature(expects: [.plain(.integer)], returns: .float)),
                    WasmModuleMetadata.FunctionExport(
                        name: "bar", signature: Signature(expects: [], returns: .undefined)),
                ],
                globals: ["g1"],
                tables: ["t1"],
                tags: ["tag1"]
            )

            let module = b.rawWasmModule(bytes: bytes, metadata: metadata)
            let exports = b.getProperty("exports", of: module)
            let exportsType = b.type(of: exports)

            #expect(exportsType.methods.contains("foo"))
            #expect(exportsType.methods.contains("bar"))
            #expect(exportsType.properties.contains("g1"))
            #expect(exportsType.properties.contains("t1"))
            #expect(exportsType.properties.contains("tag1"))

            let foo = b.getProperty("foo", of: exports)
            #expect(
                b.type(of: foo).Is(
                    .function(Signature(expects: [.plain(.integer)], returns: .float))))

            let g1 = b.getProperty("g1", of: exports)
            let g1Type = b.type(of: g1)
            #expect(g1Type.properties.contains("value"))
            #expect(g1Type.methods.contains("valueOf"))

            let t1 = b.getProperty("t1", of: exports)
            let t1Type = b.type(of: t1)
            #expect(t1Type.methods.contains("grow"))
            #expect(t1Type.methods.contains("get"))
            #expect(t1Type.methods.contains("set"))
        }
    }

    @Test func testHandlingDuplicateExportsGracefully() {
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildBundleModule(name: "myModule") {
                let v = b.loadInt(42)
                b.exportVariables(variables: [v, v], exportNames: ["foo", "foo"])
            }
            #expect(b.type(of: module) == .jsModule(exports: ["foo": .integer]))
        }
    }

    @Test func testImportNamespaceTyping() {
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildBundleModule(name: "myModule") {
                let v1 = b.loadInt(42)
                let v2 = b.loadString("abc")
                b.exportVariables(variables: [v1, v2], exportNames: ["foo", "bar"])
            }

            b.buildBundleModuleEntryPoint {
                let ns = b.importNamespace(module: module, isDeferred: true).output
                #expect(
                    b.type(of: ns)
                        == .object(ofGroup: "_fuzz_Namespace6", withProperties: ["foo", "bar"]))

                let retrievedFoo = b.getProperty("foo", of: ns)
                #expect(b.type(of: retrievedFoo) == .integer)

                let retrievedBar = b.getProperty("bar", of: ns)
                #expect(b.type(of: retrievedBar) == .jsString)
            }
        }
    }

    @Test func testDynamicImportTyping() {
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config)
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let module = b.buildBundleModule(name: "myModule") {
                let v1 = b.loadInt(42)
                let v2 = b.loadString("abc")
                b.exportVariables(variables: [v1, v2], exportNames: ["foo", "bar"])
            }

            b.buildBundleModuleEntryPoint {
                let dynImport = b.dynamicImport(module)
                #expect(b.type(of: dynImport) == .jsPromise)
            }
        }
    }
}
