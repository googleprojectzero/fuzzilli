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

class JSTyperTests: XCTestCase {

    func testBasicTypeInference() {
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

    func testObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let obj = b.buildObjectLiteral { obj in
            obj.addProperty("a", as: v)
            obj.addMethod("m", with: .parameters(.integer)) { args in
                let this = args[0]
                // Up to this point, only the "a" property has been installed
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a"]))
                XCTAssertEqual(b.type(of: args[1]), .integer)
                let notArg = b.unary(.LogicalNot, args[1])
                b.doReturn(notArg)
            }
            obj.addGetter(for: "b") { this in
                // We don't add the "b" property to the |this| type here since it's probably not very useful to access it inside its getter/setter.
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a"], withMethods: ["m"]))
            }
            obj.addSetter(for: "c") { this, v in
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b"], withMethods: ["m"]))
            }
        }

        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["a", "b", "c"], withMethods: ["m"]))

        let obj2 = b.buildObjectLiteral { obj in
            obj.addProperty("prop", as: v)
            obj.addElement(0, as: v)
        }

        XCTAssertEqual(b.type(of: obj2), .object(withProperties: ["prop"]))
    }

    func testNestedObjectLiterals() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        b.buildObjectLiteral { outer in
            outer.addProperty("a", as: v)
            outer.addMethod("m", with: .parameters(n: 1)) { args in
                let this = args[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a"]))
                b.buildObjectLiteral { inner in
                    inner.addProperty("b", as: v)
                    inner.addMethod("n", with: .parameters(n: 0)) { args in
                        let this = args[0]
                        XCTAssertEqual(b.type(of: this), .object(withProperties: ["b"]))
                    }
                }
            }
            outer.addProperty("c", as: v)
            outer.addMethod("o", with: .parameters(n: 0)) { args in
                let this = args[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "c"], withMethods: ["m"]))
            }
        }
    }

    func testObjectTypeInference() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let intVar = b.loadInt(42)
        let obj = b.createObject(with: ["foo": intVar])
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))

        b.setProperty("bar", of: obj, to: intVar)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))

        b.setProperty("baz", of: obj, to: intVar)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))

        let _ = b.deleteProperty("foo", of: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["bar", "baz"]))

        // Properties whose values are functions are still treated as properties, not methods.
        let function = b.buildPlainFunction(with: .parameters(n: 1)) { params in }
        XCTAssertEqual(b.type(of: function), .functionAndConstructor([.anything] => .undefined))
        let obj2 = b.createObject(with: ["foo": intVar, "bar": intVar, "baz": function])
        XCTAssertEqual(b.type(of: obj2), .object(withProperties: ["foo", "bar", "baz"]))
    }

    func testClasses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let cls = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters([.string])) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object())
                XCTAssertEqual(b.type(of: params[1]), .string)
                XCTAssertEqual(b.type(of: v), .integer)
                b.reassign(v, to: params[1])
                XCTAssertEqual(b.type(of: v), .string)
            }

            cls.addInstanceProperty("a")
            cls.addInstanceProperty("b")

            cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b"]))
                XCTAssertEqual(b.type(of: params[1]), .float)
                XCTAssertEqual(b.type(of: v), .integer | .string)
                b.reassign(v, to: params[1])
                XCTAssertEqual(b.type(of: v), .float)
            }

            cls.addInstanceGetter(for: "c") { this in
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b"], withMethods: ["f"]))
            }

            cls.addInstanceMethod("g", with: .parameters(n: 2)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b", "c"], withMethods: ["f"]))
                XCTAssertEqual(b.type(of: params[1]), .anything)
                XCTAssertEqual(b.type(of: params[2]), .anything)
            }

            cls.addStaticProperty("a")
            cls.addStaticProperty("d")

            cls.addStaticMethod("g", with: .parameters(n: 2)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "d"]))
                XCTAssertEqual(b.type(of: params[1]), .anything)
                XCTAssertEqual(b.type(of: params[2]), .anything)
            }

            cls.addStaticSetter(for: "e") { this, v in
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "d"], withMethods: ["g"]))
            }

            cls.addStaticMethod("h", with: .parameters(.integer)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "d", "e"], withMethods: ["g"]))
                XCTAssertEqual(b.type(of: params[1]), .integer)
            }

            cls.addPrivateInstanceMethod("p", with: .parameters(n: 0)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b", "c"], withMethods: ["f", "g"]))
            }

            cls.addPrivateStaticMethod("p", with: .parameters(n: 0)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "d", "e"], withMethods: ["g", "h"]))
            }
        }

        XCTAssertEqual(b.type(of: v), .integer | .string | .float)
        XCTAssertEqual(b.type(of: cls), .object(withProperties: ["a", "d", "e"], withMethods: ["g", "h"]) + .constructor([.string] => .object(withProperties: ["a", "b", "c"], withMethods: ["f", "g"])))
    }

    func testClasses2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        let s = b.loadString("foo")
        let f = b.loadFloat(13.37)
        b.buildClassDefinition() { cls in
            // Class methods, getters, setters, etc. are treated as conditionally executing blocks.
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                XCTAssertEqual(b.type(of: v), .integer)

                b.reassign(v, to: b.loadFloat(13.37))

                XCTAssertEqual(b.type(of: v), .float)
            }

            cls.addInstanceGetter(for: "m") { this in
                XCTAssertEqual(b.type(of: v), .integer | .float)
                XCTAssertEqual(b.type(of: f), .float)

                b.reassign(v, to: b.loadString("bar"))
                b.reassign(f, to: b.loadString("baz"))

                XCTAssertEqual(b.type(of: v), .string)
                XCTAssertEqual(b.type(of: f), .string)
            }

            cls.addStaticMethod("n", with: .parameters(n: 0)) { args in
                XCTAssertEqual(b.type(of: v), .integer | .float | .string)
                XCTAssertEqual(b.type(of: s), .string)

                b.reassign(v, to: b.loadBool(true))
                b.reassign(s, to: b.loadFloat(13.37))

                XCTAssertEqual(b.type(of: v), .boolean)
                XCTAssertEqual(b.type(of: s), .float)
            }

            // The same is true for class static initializers, even though they technically execute unconditionally.
            // However, treating them as executing unconditionally would cause them to overwrite any variable changes
            // performed in preceeding blocks. For example, in this example |s| would be .string after the initializer
            // if it were treated as executing unconditionally, while .string | .float is "more correct".
            cls.addStaticInitializer { this in
                XCTAssertEqual(b.type(of: f), .float | .string)

                b.reassign(f, to: b.loadBool(true))

                XCTAssertEqual(b.type(of: f), .boolean)
            }
        }

        XCTAssertEqual(b.type(of: v), .primitive)
        XCTAssertEqual(b.type(of: s), .string | .float)
        XCTAssertEqual(b.type(of: f), .boolean)         // A static initializer block runs unconditionally
    }

    func testNestedClasses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let outer = b.buildClassDefinition() { cls in
            cls.addInstanceProperty("a")
            cls.addInstanceMethod("m", with: .parameters(n: 0)) { args in
                let inner = b.buildClassDefinition { cls in
                    cls.addInstanceProperty("a")
                    cls.addInstanceProperty("b")
                }
                XCTAssertEqual(b.type(of: inner), .object() + .constructor([] => .object(withProperties: ["a", "b"])))
            }
            cls.addInstanceProperty("c")
        }
        XCTAssertEqual(b.type(of: outer), .object() + .constructor([] => .object(withProperties: ["a", "c"], withMethods: ["m"])))
    }

    func testSubClasses() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let base1 = b.buildClassDefinition() { cls in
            cls.addInstanceProperty("a")
        }
        XCTAssertEqual(b.type(of: base1), .object() + .constructor([] => .object(withProperties: ["a"])))

        let v = b.loadInt(42)
        let base2 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            let obj = b.buildObjectLiteral { obj in
                obj.addProperty("b", as: v)
            }
            b.doReturn(obj)
        }
        XCTAssertEqual(b.type(of: base2), .functionAndConstructor([] => .object(withProperties: ["b"])))

        let base3 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            b.doReturn(v)
        }
        XCTAssertEqual(b.type(of: base3), .functionAndConstructor([] => .integer))

        let base4 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in }
        XCTAssertEqual(b.type(of: base4), .functionAndConstructor([] => .undefined))

        let derived1 = b.buildClassDefinition(withSuperclass: base1) { cls in
            cls.addInstanceProperty("c")
        }
        XCTAssertEqual(b.type(of: derived1), .object() + .constructor([] => .object(withProperties: ["a", "c"])))

        let derived2 = b.buildClassDefinition(withSuperclass: base2) { cls in
            cls.addInstanceProperty("d")
        }
        XCTAssertEqual(b.type(of: derived2), .object() + .constructor([] => .object(withProperties: ["b", "d"])))

        // base3 does not return an object, so that return type is ignored for the constructor.
        // TODO: Technically, base3 used as a constructor would return |this|, so we'd have to use the type of |this| if the returned value is not an object in our type inference, but we don't currently do that.
        let derived3 = b.buildClassDefinition(withSuperclass: base3) { cls in
            cls.addInstanceProperty("e")
        }
        XCTAssertEqual(b.type(of: derived3), .object() + .constructor([] => .object(withProperties: ["e"])))

        let derived4 = b.buildClassDefinition(withSuperclass: base4) { cls in
            cls.addInstanceProperty("f")
        }
        XCTAssertEqual(b.type(of: derived4), .object() + .constructor([] => .object(withProperties: ["f"])))

        let derived5 = b.buildClassDefinition(withSuperclass: derived1) { cls in
            cls.addInstanceProperty("g")
        }
        XCTAssertEqual(b.type(of: derived5), .object() + .constructor([] => .object(withProperties: ["a", "c", "g"])))
    }

    func testSubroutineTypes() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature1 = [.integer, .number] => .undefined
        let signature2 = [.string, .number] => .undefined

        // Plain functions are both functions and constructors. This might yield interesting results since these function often return a value.
        var f = b.buildPlainFunction(with: .parameters(n: 2)) { params in XCTAssertEqual(b.type(of: params[0]), .anything); XCTAssertEqual(b.type(of: params[1]), .anything) }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor([.anything, .anything] => .undefined))

        f = b.buildPlainFunction(with: .parameters(signature1.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .integer); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor(signature1))

        f = b.buildPlainFunction(with: .parameters(n: 2)) { params in XCTAssertEqual(b.type(of: params[0]), .anything); XCTAssertEqual(b.type(of: params[1]), .anything) }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor([.anything, .anything] => .undefined))

        // All other function types are just functions...
        f = b.buildArrowFunction(with: .parameters(signature2.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .string); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .function(signature2))

        let signature3 = [.integer, .number] => fuzzer.environment.generatorType
        f = b.buildGeneratorFunction(with: .parameters(signature3.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .integer); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .function(signature3))

        f = b.buildAsyncGeneratorFunction(with: .parameters(signature3.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .integer); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .function(signature3))

        let signature4 = [.string, .number] => fuzzer.environment.promiseType
        f = b.buildAsyncFunction(with: .parameters(signature4.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .string); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .function(signature4))

        f = b.buildAsyncArrowFunction(with: .parameters(signature4.parameters)) { params in XCTAssertEqual(b.type(of: params[0]), .string); XCTAssertEqual(b.type(of: params[1]), .number) }
        XCTAssertEqual(b.type(of: f), .function(signature4))



        // ... except for constructors, which are just constructors (when they are lifted to JavaScript, they explicitly forbid being called as a function).
        let signature5 = [.integer, .number] => .object(withProperties: ["foo", "bar"])
        f = b.buildConstructor(with: .parameters(signature3.parameters)) { params in
            let this = params[0]
            XCTAssertEqual(b.type(of: this), .object())
            XCTAssertEqual(b.type(of: params[1]), .integer)
            XCTAssertEqual(b.type(of: params[2]), .number)
            b.setProperty("foo", of: this, to: params[1])
            b.setProperty("bar", of: this, to: params[2])
        }
        XCTAssertEqual(b.type(of: f), .constructor(signature5))
    }

    func testReturnValueInference() {
        // Test that function and constructor return values are inferred correctly.
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f1 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            b.doReturn(b.loadInt(42))
        }
        XCTAssertEqual(b.type(of: f1).signature?.outputType, .integer)

        let f2 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            let o = b.createObject(with: ["a": b.loadInt(42)])
            b.doReturn(o)
        }
        XCTAssertEqual(b.type(of: f2).signature?.outputType, .object(withProperties: ["a"]))

        let f3 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(b.loadFloat(13.37))
            }, elseBody: {
                b.doReturn(b.loadString("13.37"))
            })
            b.doReturn(b.loadBool(false))
        }
        XCTAssertEqual(b.type(of: f3).signature?.outputType, .float | .string)

        let f4 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(b.loadString("foo"))
            }, elseBody: {
            })
        }
        XCTAssertEqual(b.type(of: f4).signature?.outputType, .string | .undefined)

        let f5 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(b.loadString("foo"))
            }, elseBody: {
            })
            b.doReturn(b.loadBool(true))
        }
        XCTAssertEqual(b.type(of: f5).signature?.outputType, .string | .boolean)

        let f6 = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.doReturn(b.loadInt(42))
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(b.loadFloat(13.37))
            }, elseBody: {
                b.doReturn(b.loadString("13.37"))
            })
            b.doReturn(b.loadBool(false))
        }
        XCTAssertEqual(b.type(of: f6).signature?.outputType, .integer)

        let f7 = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            b.buildIf(args[0]) {
                b.buildIf(args[1]) {
                    b.doReturn(b.loadFloat(13.37))
                }
            }
            b.doReturn(b.loadBool(true))
        }
        XCTAssertEqual(b.type(of: f7).signature?.outputType, .float | .boolean)

        let f8 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            let f9 = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
                b.doReturn(b.loadInt(42))
            }
            XCTAssertEqual(b.type(of: f9).signature?.outputType, .integer)
            b.doReturn(b.loadFloat(13.37))
        }
        XCTAssertEqual(b.type(of: f8).signature?.outputType, .float)

        let f9 = b.buildPlainFunction(with: .parameters(n: 3)) { args in
            b.buildIf(args[0]) {
                b.doReturn(b.loadInt(42))
            }
            b.buildIf(args[1]) {
                b.buildIfElse(args[2], ifBody: {
                    b.doReturn(b.loadBool(true))
                }, elseBody: {
                    b.doReturn(b.loadBool(false))
                })
                // This is ignored: all paths have already returned
                b.doReturn(b.loadString("foobar"))
            }
            b.doReturn(b.loadFloat(13.37))
        }
        XCTAssertEqual(b.type(of: f9).signature?.outputType, .integer | .boolean | .float)

        let a1 = b.buildArrowFunction(with: .parameters(n: 0)) { _ in
            b.doReturn(b.loadInt(42))
        }
        XCTAssertEqual(b.type(of: a1).signature?.outputType, .integer)

        let c1 = b.buildConstructor(with: .parameters(n: 0)) { _ in }
        XCTAssertEqual(b.type(of: c1).signature?.outputType, .object())

        let c2 = b.buildConstructor(with: .parameters(n: 2)) { args in
            let this = args[0]
            b.setProperty("a", of: this, to: args[1])
            b.setProperty("b", of: this, to: args[2])
        }
        XCTAssertEqual(b.type(of: c2).signature?.outputType, .object(withProperties: ["a", "b"]))

        let c3 = b.buildConstructor(with: .parameters(n: 2)) { args in
            let o = b.createObject(with: ["a": args[1], "b": args[2]])
            b.doReturn(o)
        }
        XCTAssertEqual(b.type(of: c3).signature?.outputType, .object(withProperties: ["a", "b"]))

        let g1 = b.buildGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(42))
        }
        XCTAssertEqual(b.type(of: g1).signature?.outputType, fuzzer.environment.generatorType)

        let g2 = b.buildAsyncGeneratorFunction(with: .parameters(n: 0)) { _ in
            b.yield(b.loadInt(42))
        }
        XCTAssertEqual(b.type(of: g2).signature?.outputType, fuzzer.environment.generatorType)

        let a2 = b.buildAsyncFunction(with: .parameters(n: 0)) { _ in }
        XCTAssertEqual(b.type(of: a2).signature?.outputType, fuzzer.environment.promiseType)

        let a3 = b.buildAsyncArrowFunction(with: .parameters(n: 0)) { _ in }
        XCTAssertEqual(b.type(of: a3).signature?.outputType, fuzzer.environment.promiseType)
    }

    func testParameterTypeInference() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature = [.string, .object(), .opt(.number)] => .float
        let f = b.buildPlainFunction(with: .parameters(signature.parameters)) { params in
            XCTAssertEqual(b.type(of: params[0]), .string)
            XCTAssertEqual(b.type(of: params[1]), .object())
            XCTAssertEqual(b.type(of: params[2]), .undefined | .integer | .float)
            b.doReturn(b.loadFloat(13.37))
        }
        XCTAssertEqual(b.type(of: f), .functionAndConstructor(signature))

        let signature2 = [.integer, .anything...] => .float
        let f2 = b.buildPlainFunction(with: .parameters(signature2.parameters)) { params in
            XCTAssertEqual(b.type(of: params[0]), .integer)
            XCTAssertEqual(b.type(of: params[1]), fuzzer.environment.arrayType)
            b.doReturn(b.loadFloat(13.37))
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

        b.buildIfElse(v, ifBody: {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.setProperty("bar", of: obj, to: v)
            b.setProperty("baz", of: obj, to: v)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))

            XCTAssertEqual(b.type(of: v), .integer)
            let stringVar = b.loadString("foobar")
            b.reassign(v, to: stringVar)
            XCTAssertEqual(b.type(of: v), .string)
        }, elseBody: {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.setProperty("bar", of: obj, to: v)
            b.setProperty("bla", of: obj, to: v)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "bla"]))

            XCTAssertEqual(b.type(of: v), .integer)
            let floatVar = b.loadFloat(13.37)
            b.reassign(v, to: floatVar)
        })

        XCTAssertEqual(b.type(of: v), .string | .float)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))

        // Test another program using if/else
        b.reset()

        let v0 = b.loadInt(42)
        let v1 = b.loadInt(42)
        XCTAssertEqual(b.type(of: v0), .integer)
        XCTAssertEqual(b.type(of: v1), .integer)
        b.buildIfElse(v0, ifBody: {
            b.reassign(v0, to: b.loadString("foo"))
            b.reassign(v1, to: b.loadString("foo"))
        }, elseBody: {
            b.reassign(v1, to: b.loadString("bar"))
        })

        XCTAssertEqual(b.type(of: v0), .string | .integer)
        XCTAssertEqual(b.type(of: v1), .string)


        // Test another program using just if
        b.reset()

        let i = b.loadInt(42)
        XCTAssertEqual(b.type(of: i), .integer)
        b.buildIf(i) {
            b.reassign(i, to: b.loadString("foo"))
        }

        XCTAssertEqual(b.type(of: i), .string | .integer)
    }

    func testDeeplyNestedBlocksHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v = b.loadInt(42)
        XCTAssertEqual(b.type(of: v), .integer)

        b.buildIfElse(v, ifBody: {
            b.buildIfElse(v, ifBody: {
                b.buildIfElse(v, ifBody: {
                    b.reassign(v, to: b.loadString("foo"))
                    XCTAssertEqual(b.type(of: v), .string)
                }, elseBody: {
                    XCTAssertEqual(b.type(of: v), .integer)
                    b.reassign(v, to: b.loadBool(true))
                    XCTAssertEqual(b.type(of: v), .boolean)
                })

                XCTAssertEqual(b.type(of: v), .string | .boolean)
            }, elseBody: {
                XCTAssertEqual(b.type(of: v), .integer)
            })

            XCTAssertEqual(b.type(of: v), .string | .boolean | .integer)
        }, elseBody: {
            XCTAssertEqual(b.type(of: v), .integer)
        })

        XCTAssertEqual(b.type(of: v), .string | .boolean | .integer)
    }

    func testFunctionReassignment() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let signature = [.integer] => .undefined

        b.buildWhileLoop({ b.loadBool(true) }) {
            let f = b.buildPlainFunction(with: .parameters(signature.parameters)) {
                params in XCTAssertEqual(b.type(of: params[0]), .integer)
            }
            XCTAssertEqual(b.type(of: f), .functionAndConstructor(signature))
            b.reassign(f, to: b.loadString("foo"))
            XCTAssertEqual(b.type(of: f), .string)
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
                b.setProperty("bar", of: obj, to: intVar1)

                XCTAssertEqual(b.type(of: v), .string)
                let floatVar = b.loadFloat(13.37)
                b.reassign(v, to: floatVar)

                XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))
                XCTAssertEqual(b.type(of: v), .float)
            }

            // Select loop type
            switch i {
            case 0:
                b.buildForLoop() {
                    body()
                }
            case 1:
                b.buildWhileLoop({ b.compare(intVar1, with: intVar2, using: .lessThan) }) {
                    body()
                }
                break
            case 2:
                b.buildForInLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .string)
                    body()
                }
            case 3:
                b.buildForOfLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .anything)
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

            XCTAssertEqual(b.type(of: intVar1), .integer)
            XCTAssertEqual(b.type(of: intVar2), .integer)
            XCTAssertEqual(b.type(of: intVar3), .integer)
            XCTAssertEqual(b.type(of: v), .string | .float)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))

            b.reset()
        }
    }

    func testBuiltinTypeInference() {
        let builtinAType = ILType.integer
        let builtinBType = ILType.object(ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"])
        let builtinCType = ILType.function([] => .number)

        let env = MockEnvironment(builtins: [
            "A": builtinAType,
            "B": builtinBType,
            "C": builtinCType
        ])

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let va = b.createNamedVariable(forBuiltin: "A")
        let vb = b.createNamedVariable(forBuiltin: "B")
        let vc = b.createNamedVariable(forBuiltin: "C")

        XCTAssertEqual(b.type(of: va), builtinAType)
        XCTAssertEqual(b.type(of: vb), builtinBType)
        XCTAssertEqual(b.type(of: vc), builtinCType)
    }

    func testPropertyTypeInference() {
        let propFooType = ILType.float
        let propBarType = ILType.function([] => .anything)
        let propBazType = ILType.object(withProperties: ["a", "b", "c"])
        let propertiesByGroup: [String: [String: ILType]] = [
            "B": [
                "foo": propFooType,
                "bar": propBarType
            ],
            "C": [
                "baz": propBazType,
            ]
        ]

        let builtins: [String: ILType] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]

        let env = MockEnvironment(builtins: builtins, propertiesByGroup: propertiesByGroup)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let aObj = b.createNamedVariable(forBuiltin: "A")
        XCTAssertEqual(b.type(of: aObj), .anything)
        let bObj = b.createNamedVariable(forBuiltin: "B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))

        // .foo and .bar are both known for B objects
        var p = b.getProperty("foo", of: bObj)
        XCTAssertEqual(b.type(of: p), propFooType)
        p = b.getProperty("bar", of: bObj)
        XCTAssertEqual(b.type(of: p), propBarType)

        // But .baz is only known on C objects
        p = b.getProperty("baz", of: bObj)
        XCTAssertEqual(b.type(of: p), .anything)

        let cObj = b.createNamedVariable(forBuiltin: "C")
        p = b.getProperty("baz", of: cObj)
        XCTAssertEqual(b.type(of: p), propBazType)

        // No property types are known for A objects though.
        p = b.getProperty("foo", of: aObj)
        XCTAssertEqual(b.type(of: p), .anything)
        p = b.getProperty("bar", of: aObj)
        XCTAssertEqual(b.type(of: p), .anything)
        p = b.getProperty("baz", of: aObj)
        XCTAssertEqual(b.type(of: p), .anything)
    }

    func testMethodTypeInference() {
        let m1Signature = [] => .float
        let m2Signature = [.string] => .object(ofGroup: "X")
        let methodsByGroup: [String: [String: Signature]] = [
            "B": [
                "m1": m1Signature,
            ],
            "C": [
                "m2": m2Signature,
            ]
        ]

        let builtins: [String: ILType] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]

        let env = MockEnvironment(builtins: builtins, methodsByGroup: methodsByGroup)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let aObj = b.createNamedVariable(forBuiltin: "A")
        XCTAssertEqual(b.type(of: aObj), .anything)
        let bObj = b.createNamedVariable(forBuiltin: "B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))

        var r = b.callMethod("m1", on: bObj)
        XCTAssertEqual(b.type(of: r), .float)

        r = b.callMethod("m2", on: bObj)
        XCTAssertEqual(b.type(of: r), .anything)

        let cObj = b.createNamedVariable(forBuiltin: "C")
        r = b.callMethod("m2", on: cObj)
        XCTAssertEqual(b.type(of: r), .object(ofGroup: "X"))
    }

    func testConstructorTypeInference() {
        let aConstructorType = ILType.constructor([.rest(.anything)] => .object(ofGroup: "A"))
        let builtins: [String: ILType] = [
            "A": aConstructorType,
        ]

        let env = MockEnvironment(builtins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let A = b.createNamedVariable(forBuiltin: "A")
        XCTAssertEqual(b.type(of: A), aConstructorType)

        // For a known constructor, the resulting type can be inferred
        let a = b.construct(A)
        XCTAssertEqual(b.type(of: a), .object(ofGroup: "A"))

        // For an unknown constructor, the result will be .object()
        let B = b.createNamedVariable(forBuiltin: "B")
        let b_ = b.construct(B)
        XCTAssertEqual(b.type(of: b_), .object())

        // For a self-defined constructor, we can infer more details about the constructed type
        let C = b.buildConstructor(with: .parameters(n: 2)) { args in
            let this = args[0]
            b.setProperty("foo", of: this, to: args[1])
            b.setProperty("bar", of: this, to: args[2])
        }
        let c = b.construct(C)
        XCTAssertEqual(b.type(of: c), .object(withProperties: ["foo", "bar"]))
    }

    func testReturnTypeInference() {
        let aFunctionType = ILType.function([.rest(.anything)] => .primitive)
        let builtins: [String: ILType] = [
            "a": aFunctionType,
        ]

        let env = MockEnvironment(builtins: builtins)

        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let a = b.createNamedVariable(forBuiltin: "a")
        XCTAssertEqual(b.type(of: a), aFunctionType)

        // For a known function, the resulting type can be inferred
        var r = b.callFunction(a)
        XCTAssertEqual(b.type(of: r), .primitive)

        // For an unknown function, the result will be .anything
        let c = b.createNamedVariable(forBuiltin: "c")
        r = b.callFunction(c)
        XCTAssertEqual(b.type(of: r), .anything)
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

    func testSuperBinding() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let superclass = b.buildClassDefinition() { cls in
            cls.addConstructor(with: .parameters([.integer])) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object())
                XCTAssertEqual(b.currentSuperType(), .object())

                XCTAssertEqual(b.type(of: params[1]), .integer)
            }

            cls.addInstanceProperty("a")

            cls.addInstanceMethod("f", with: .parameters(.float)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a"]))
                XCTAssertEqual(b.currentSuperType(), .object())

                XCTAssertEqual(b.type(of: params[1]), .float)

                b.doReturn(b.loadString("foobar"))
            }
        }

        let superType = ILType.object(withProperties: ["a"], withMethods: ["f"])
        XCTAssertEqual(b.type(of: superclass), .object() + .constructor([.integer] => superType))

        let v = b.loadInt(42)
        let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
            cls.addInstanceProperty("b", value: v)

            cls.addConstructor(with: .parameters([.string])) { params in
                XCTAssertEqual(b.currentSuperConstructorType(), .object() + .constructor([.integer] => .object(withProperties: ["a"], withMethods: ["f"])))
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b"], withMethods: ["f"]))
                XCTAssertEqual(b.currentSuperType(), superType)

                b.callSuperConstructor(withArgs: [b.loadFloat(42)])
            }

            cls.addInstanceMethod("g", with: .parameters(.anything)) { params in
                let this = params[0]
                XCTAssertEqual(b.type(of: this), .object(withProperties: ["a", "b"], withMethods: ["f"]))
                XCTAssertEqual(b.currentSuperType(), superType)
            }
        }
        XCTAssertEqual(b.type(of: cls), .object() + .constructor([.string] => .object(withProperties: ["a", "b"], withMethods: ["f", "g"])))
    }

    func testBigintTypeInference() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(42)
        let i2 = b.loadInt(43)
        XCTAssert(b.type(of: i1).Is(.integer))
        let bi1 = b.loadBigInt(4200000000)
        let bi2 = b.loadBigInt(4300000000)
        XCTAssert(b.type(of: bi1).Is(.bigint))

        for op in UnaryOperator.allCases {
            // Logical operators produce .boolean in any case
            guard op != .LogicalNot else { continue }
            let r1 = b.unary(op, i1)
            XCTAssertFalse(b.type(of: r1).MayBe(.bigint))
            let r2 = b.unary(op, bi1)
            XCTAssert(b.type(of: r2).Is(.bigint))
        }

        for op in BinaryOperator.allCases {
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

        for op in BinaryOperator.allCases {
            let i3 = b.loadInt(45)
            let i4 = b.loadInt(46)
            XCTAssert(b.type(of: i3).Is(.integer))
            let bi3 = b.loadBigInt(4200000000)
            let bi4 = b.loadBigInt(4300000000)
            XCTAssert(b.type(of: bi3).Is(.bigint))

            // Logical operators produce .boolean in any case
            guard op != .LogicOr && op != .LogicAnd else { continue }
            b.reassign(i3, to: i4, with: op)
            XCTAssertFalse(b.type(of: i3).MayBe(.bigint))
            b.reassign(i3, to: bi4, with: op)
            // This isn't really necessary, as mixing types in this way
            // would lead to an exception in JS. Currently, we handle
            // it like this though.
            XCTAssert(b.type(of: i3).MayBe(.bigint))
            b.reassign(bi3, to: bi4, with: op)
            XCTAssert(b.type(of: bi3).Is(.bigint))
        }
    }

    func testWhileLoopHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.loadInt(0)
        let v2 = b.loadInt(1)
        // The header executes unconditionally, but the body does not
        b.buildWhileLoop({ b.reassign(v1, to: b.loadString("foo")); return b.loadBool(false) }) {
            b.reassign(v2, to: b.loadString("bar"))
        }

        XCTAssertEqual(b.type(of: v1), .string)
        XCTAssertEqual(b.type(of: v2), .integer | .string)
    }

    func testDoWhileLoopHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.loadInt(0)
        let v2 = b.loadInt(1)
        // Both the header and the body execute unconditionally
        b.buildDoWhileLoop(do: {
            b.reassign(v2, to: b.loadString("foo"))
        }, while: { b.reassign(v1, to: b.loadString("bar")); return b.loadBool(false) })

        XCTAssertEqual(b.type(of: v1), .string)
        XCTAssertEqual(b.type(of: v2), .string)
    }

    func testForLoopHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v1 = b.loadInt(0)
        let v2 = b.loadInt(1)
        let v3 = b.loadInt(2)
        let v4 = b.loadInt(3)
        // The initializer block and the condition block are always executed.
        // The afterthought and body block may not be executed.
        b.buildForLoop({
            b.reassign(v1, to: b.loadString("foo"))
        }, {
            b.reassign(v2, to: b.loadString("bar"))
            return b.loadBool(false)
        }, {
            b.reassign(v3, to: b.loadString("baz"))
        }) {
            b.reassign(v4, to: b.loadString("bla"))
        }

        XCTAssertEqual(b.type(of: v1), .string)
        XCTAssertEqual(b.type(of: v2), .string)
        XCTAssertEqual(b.type(of: v3), .integer | .string)
        XCTAssertEqual(b.type(of: v4), .integer | .string)
    }

    func testForLoopLoopVariableTyping() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildForLoop(i: { b.loadInt(0) },
                       { i in XCTAssertEqual(b.type(of: i), .integer); return b.compare(i, with: b.loadInt(10), using: .lessThan) },
                       { i in XCTAssertEqual(b.type(of: i), .integer); b.unary(.PostInc, i) }) { i in
            XCTAssertEqual(b.type(of: i), .integer)
        }

        b.buildForLoop(i: { b.loadInt(0) },
                       { i in
                            XCTAssertEqual(b.type(of: i), .integer);
                            b.buildForLoop(i: { b.loadFloat(12.34) }, { i in XCTAssertEqual(b.type(of: i), .float); return b.loadBool(false) }, { i in XCTAssertEqual(b.type(of: i), .float )}) { i in
                                XCTAssertEqual(b.type(of: i), .float)
                            }
                            return b.compare(i, with: b.loadInt(10), using: .lessThan)

                       },
                       { i in XCTAssertEqual(b.type(of: i), .integer); b.unary(.PostInc, i) }) { i in
            XCTAssertEqual(b.type(of: i), .integer)
        }
    }

    func testSwitchStatementHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let v0 = b.loadInt(42)
        let v1 = b.createObject(with: ["foo": v0])
        let v2 = b.getProperty("foo", of: v1)
        let v3 = b.loadInt(1337)
        let v4 = b.loadString("42")

        b.buildSwitch(on: v2) { swtch in
            swtch.addCase(v3) {
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.setProperty("bar", of: v1, to: v0)
                b.setProperty("baz", of: v1, to: v0)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "baz"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let stringVar = b.loadString("foobar")
                b.reassign(v0, to: stringVar)
                XCTAssertEqual(b.type(of: v0), .string)
            }
            swtch.addDefaultCase {
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.setProperty("bar", of: v1, to: v0)
                b.setProperty("qux", of: v1, to: v0)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "qux"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let boolVal = b.loadBool(false)
                b.reassign(v0, to: boolVal)
                XCTAssertEqual(b.type(of: v0), .boolean)
            }
            swtch.addCase(v4) {
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo"]))
                b.setProperty("bar", of: v1, to: v0)
                b.setProperty("bla", of: v1, to: v0)
                XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar", "bla"]))

                XCTAssertEqual(b.type(of: v0), .integer)
                let floatVar = b.loadFloat(13.37)
                b.reassign(v0, to: floatVar)
                XCTAssertEqual(b.type(of: v0), .float)
            }
        }

        XCTAssertEqual(b.type(of: v0), .float | .string | .boolean)
        XCTAssertEqual(b.type(of: v1), .object(withProperties: ["foo", "bar"]))
        XCTAssertEqual(b.type(of: v3), .integer)
        XCTAssertEqual(b.type(of: v4), .string)
    }

    func testSwitchStatementHandling2() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(42)
        let i2 = b.loadInt(42)
        b.buildSwitch(on: i1) { swtch in
            swtch.addDefaultCase {
                XCTAssertEqual(b.type(of: i1), .integer)
                XCTAssertEqual(b.type(of: i2), .integer)
                b.reassign(i2, to: b.loadString("bar"))
            }
        }

        XCTAssertEqual(b.type(of: i1), .integer)
        XCTAssertEqual(b.type(of: i2), .string)
    }

    func testSwitchStatementHandling3() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(42)
        let i2 = b.loadInt(43)
        let i3 = b.loadInt(44)

        let v = b.loadString("foobar")

        b.buildSwitch(on: i1) { swtch in
            swtch.addCase(i2) {
                XCTAssertEqual(b.type(of: v), .string)
                b.reassign(v, to: b.loadFloat(13.37))
                XCTAssertEqual(b.type(of: v), .float)
            }

            swtch.addCase(i3) {
                XCTAssertEqual(b.type(of: v), .string)
                b.reassign(v, to: b.loadBool(false))
                XCTAssertEqual(b.type(of: v), .boolean)
            }
        }

        XCTAssertEqual(b.type(of: v), .string | .float | .boolean)
    }

    func testSwitchStatementHandling4() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let i1 = b.loadInt(42)
        XCTAssertEqual(b.type(of: i1), .integer)
        b.buildSwitch(on: i1) { _ in
        }
        XCTAssertEqual(b.type(of: i1), .integer)
    }

    func testDestructObjectTypeInference() {
        let objectGroups: [String: [String: ILType]] = [
            "O": [
                "foo": .integer,
                "bar": .string,
                "baz": .boolean
            ],
        ]

        let env = MockEnvironment(builtins: [:], propertiesByGroup: objectGroups)
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()

        let obj = b.createNamedVariable(forBuiltin: "myO")
        b.setType(ofVariable: obj, to: .object(ofGroup: "O", withProperties: ["foo", "bar", "baz"]))

        let outputs = b.destruct(obj, selecting: ["foo", "bar"], hasRestElement: true)
        XCTAssertEqual(b.type(of: outputs[0]), .integer)
        XCTAssertEqual(b.type(of: outputs[1]), .string)
        XCTAssertEqual(b.type(of: outputs[2]), .object())
    }

    func testWasmTypeInference() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        b.buildWasmModule { m in
            m.addWasmFunction(with: [] => .nothing) { f, _ in
                let ci32 = f.consti32(1337)
                let ci64 = f.consti64(1338)
                let cf32 = f.constf32(13.37)
                let cf64 = f.constf64(13.38)

                XCTAssertEqual(.wasmi32, b.type(of: ci32))
                XCTAssertEqual(.wasmi64, b.type(of: ci64))
                XCTAssertEqual(.wasmf32, b.type(of: cf32))
                XCTAssertEqual(.wasmf64, b.type(of: cf64))
                XCTAssertTrue(b.type(of: ci32).Is(.wasmPrimitive))
                XCTAssertTrue(b.type(of: ci64).Is(.wasmPrimitive))
                XCTAssertTrue(b.type(of: cf32).Is(.wasmPrimitive))
                XCTAssertTrue(b.type(of: cf64).Is(.wasmPrimitive))
            }
        }
    }
}
