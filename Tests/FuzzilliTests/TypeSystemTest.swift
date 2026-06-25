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

import Testing

@testable import Fuzzilli

struct TypeSystemTests {

    @Test
    func testSymbolGroups() {
        #expect(ILType.jsSymbol(ofGroup: "Symbol.dispose").Is(.jsSymbol))
        #expect(ILType.jsSymbol(ofGroup: "Symbol.dispose").union(with: .jsSymbol) == .jsSymbol)
        #expect(ILType.jsSymbol.union(with: .jsSymbol(ofGroup: "Symbol.dispose")) == .jsSymbol)
        #expect(
            ILType.jsSymbol(ofGroup: "Symbol.dispose").intersection(with: .jsSymbol)
                == .jsSymbol(ofGroup: "Symbol.dispose"))
        #expect(
            ILType.jsSymbol.intersection(with: .jsSymbol(ofGroup: "Symbol.dispose"))
                == .jsSymbol(ofGroup: "Symbol.dispose"))
    }

    @Test
    func testSubsumptionReflexivity() {
        for t in typeSuite {
            #expect(t >= t, "\(t) >= \(t)")
        }
    }

    @Test
    func testSubsumptionTransitivity() {
        for t1 in typeSuite {
            for t2 in typeSuite {
                for t3 in typeSuite {
                    if t1 >= t2 && t2 >= t3 {
                        #expect(
                            t1 >= t3, "\(t1) >= \(t2) && \(t2) >= \(t3) implies \(t1) => \(t3)")
                    }
                }
            }
        }
    }

    @Test
    func testSubsumptionAntisymmetry() {
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 && t2 >= t1 {
                    #expect(t1 == t2, "\(t1) >= \(t2) && \(t2) >= \(t1) implies \(t1) == \(t2)")
                } else if t1 >= t2 {
                    #expect(!(t2 >= t1), "\(t1) >= \(t2) && \(t1) != \(t2) implies \(t2) !>= \(t1)")
                }
            }
        }
    }

    @Test
    func testTypeEquality() {
        // Do some ad-hoc tests
        #expect(.integer == .integer)
        #expect(.integer != .float)

        #expect(.object() == .object())
        #expect(.object(withProperties: ["foo"]) == .object(withProperties: ["foo"]))
        #expect(.object(withProperties: ["foo"]) != .object(withProperties: ["bar"]))
        #expect(.object(withProperties: ["foo"]) != .object())
        #expect(.object(withProperties: ["x"]) != .object(withMethods: ["x"]))
        #expect(.object(withMethods: ["m1"]) == .object(withMethods: ["m1"]))
        #expect(.object(withMethods: ["m1"]) != .object(withMethods: ["m2"]))
        #expect(.object(withMethods: ["m1"]) != .object())

        #expect(.function() == .function())
        #expect(
            .function([.integer, .rest(.integer)] => .undefined)
                == .function([.integer, .rest(.integer)] => .undefined))
        #expect(.function([.integer, .rest(.integer)] => .undefined) != .function())

        // Test equality properties for all types in the test suite
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 == t2 {
                    #expect(t1 >= t2, "\(t1) == \(t2) implies \(t1) >= \(t2)")
                    #expect(t2 >= t1, "\(t1) == \(t2) implies \(t2) >= \(t1)")
                } else {
                    #expect(
                        !(t1 >= t2 && t2 >= t1),
                        "\(t1) != \(t2) implies !(\(t1) >= \(t2) && \(t2) >= \(t1))")
                }
            }
        }
    }

    @Test
    func testSubsumptionOperators() {
        // Test that the >= and <= operators and the .subsumes method
        // behave as expected for all types in the test suite
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 {
                    #expect(t1.subsumes(t2))
                    #expect(t2 <= t1, "\(t1) >= \(t2) implies \(t2) <= \(t1)")
                } else if t2 >= t1 {
                    #expect(t2.subsumes(t1))
                    #expect(t1 <= t2, "\(t2) >= \(t1) implies \(t1) <= \(t2)")
                } else {
                    #expect(!(t1.subsumes(t2) || t2.subsumes(t1)))
                }
            }
        }
    }

    @Test
    func testIsAndMayBe() {
        // An A Is a B iff A <= B.
        // E.g. a object with a property "foo" is an object
        #expect(ILType.object(withProperties: ["foo"]).Is(.object()))
        // and an integer is a number
        #expect(ILType.integer.Is(.number))
        // but an integer is not an object
        #expect(!ILType.integer.Is(.object()))
        // and is also not a boolean
        #expect(!ILType.integer.Is(.boolean))
        // and a boolean is not a number
        #expect(!ILType.boolean.Is(.number))
        // but an integer is a number
        #expect(ILType.integer.Is(.number))
        #expect(!ILType.integer.MayNotBe(.number))
        // even though a number may not be an integer (it could also be a float)
        #expect(ILType.number.MayNotBe(.integer))
        // A function f1 is a function f2 if the signatures are compatible, such that f1
        // can be used when a function f2 is required (i.e. if the call to the functions
        // assumes the function has the signature of f2).
        // See also the signature subsumption test for more complicated examples.
        #expect(ILType.function([.jsAnything] => .integer).Is(.function([.integer] => .number)))
        #expect(!ILType.function([.integer] => .integer).Is(.function([.jsAnything] => .number)))
        #expect(!ILType.function([.jsAnything] => .number).Is(.function([.jsAnything] => .integer)))

        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 {
                    #expect(t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    #expect(!t2.MayNotBe(t1), "\(t1) >= \(t2) <=> !(\(t2)).MayNotBe(\(t1))")
                } else {
                    #expect(!t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    #expect(t2.MayNotBe(t1), "\(t1) >= \(t2) <=> !(\(t2)).MayNotBe(\(t1))")
                }

                if t2.Is(t1) {
                    #expect(!t2.MayNotBe(t1), "(\(t2)).Is(\(t1)) <=> !(\(t2)).MayNotBe(\(t1))")
                    #expect(t1 >= t2, "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                } else {
                    #expect(!(t1 >= t2), "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    #expect(t2.MayNotBe(t1), "(\(t2)).Is(\(t1)) <=> !(\(t2)).MayNotBe(\(t1))")
                }
            }
        }

        // An A MayBe a B iff the intersection between A and B is non-empty.
        // E.g. a .primitive MayBe a .number because the intersection of the two is non-empty (is .number).
        #expect(ILType.primitive.MayBe(.number))
        // and a .number MayBe a .integer or a .float
        #expect(ILType.number.MayBe(.integer))
        #expect(ILType.number.MayBe(.float))
        // but a number can never be a .boolean or a .object etc.
        #expect(!ILType.number.MayBe(.boolean))
        #expect(!ILType.number.MayBe(.object()))
        // The union of two types MayBe eiher of the two types. Phrased differently,
        // if something is either a number or a boolean, then it may be either of these.
        #expect((.integer | .boolean).MayBe(.integer))
        #expect((.integer | .boolean).MayBe(.boolean))
        // But it may still not be a string.
        #expect(!(.integer | .boolean).MayBe(.string))
        // Less obviously, an object MayBe an object with a property "foo"
        #expect(ILType.object().MayBe(.object(withProperties: ["foo"])))
        // and a function that takes an integer may be a function that also takes anything as first parameter.
        // The way to think about is is (probably) that a function taking .jsAnything may still be called
        // with a .integer as argument. However, from a practical point of view the function that takes .integer
        // may in fact also be fine with a different argument.
        #expect(
            ILType.function([.integer] => .jsAnything).MayBe(
                .function([.jsAnything] => .jsAnything)))
        // But (at least from a theoretical point-of-view) a function taking a .integer is definitely not a function
        // that takes (only) a string as first parameter.
        #expect(
            !ILType.function([.integer] => .jsAnything).MayBe(.function([.string] => .jsAnything)))

        #expect((ILType.integer | ILType.boolean).MayBe(ILType.integer | ILType.string))
        #expect(!(ILType.integer + ILType.object()).MayBe(ILType.string + ILType.object()))

        // An object with properties .a and .b Is definitely an object with property .a. However, an
        // object with property .a MayBe an object with properties .a and .b.
        let o1 = ILType.object(withProperties: ["a", "b"], withMethods: ["m", "n"])
        let o2 = ILType.object(withProperties: ["a"], withMethods: ["m"])
        #expect(o1.Is(o2))
        #expect(!o2.Is(o1))
        #expect(o1.MayBe(o2))
        #expect(o2.MayBe(o2))

        for t1 in typeSuite {
            for t2 in typeSuite {
                // Below tests don't work for .nothing because that
                // is also the intersection of unrelated types.
                if t1 == .nothing || t2 == .nothing {
                    continue
                }

                // If t2 is a t1 then it clearly may be a t1.
                if t2.Is(t1) {
                    #expect(t2.MayBe(t1), "(\(t2)).Is(a: \(t1)) => (\(t2)).MayBe(\(t1))")
                }

                if t1 & t2 != .nothing {
                    #expect(t2.MayBe(t1), "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(\(t1))")
                } else {
                    #expect(!t2.MayBe(t1), "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(\(t1))")
                }

                #expect((t1 | t2).MayBe(t1), "A union type may be one of its parts")
                #expect((t1 | t2).MayBe(t2), "A union type may be one of its parts")

                if t2.MayBe(t1) {
                    #expect(
                        t1 & t2 != .nothing, "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(\(t1))")
                } else {
                    #expect(
                        t1 & t2 == .nothing, "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(\(t1))")
                }
            }
        }

        // .jsAnything MayBe anything (in JS), but definitely is only .jsAnything
        for t in typeSuite where t != .jsAnything && t != .nothing {
            #expect(ILType.jsAnything.MayBe(t) || t.Is(.wasmAnything), ".jsAnything MayBe \(t)")
            #expect(!ILType.jsAnything.Is(t), ".jsAnything Is not definitely \(t)")
        }

        // .wasmAnything MayBe anything (in Wasm), but definitely is only .wasmAnything
        for t in typeSuite where t != .wasmAnything && t != .nothing {
            #expect(ILType.wasmAnything.MayBe(t) || t.Is(.jsAnything), ".wasmAnything MayBe \(t)")
            #expect(!ILType.wasmAnything.Is(t), ".jsAnything Is not definitely \(t)")
        }
    }

    @Test
    func testPrimitiveTypeSubsumption() {
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                if t1 == t2 {
                    #expect(t1 >= t2 && t2 >= t1)
                } else {
                    #expect(!(t1 >= t2 || t2 >= t1))
                }
            }
        }
    }

    @Test
    func testAnythingAndNothingSubsumption() {
        for t in typeSuite {
            // .jsAnything subsumes every other type and no other type subsumes .jsAnything
            #expect(.jsAnything >= t || t.Is(.wasmAnything))
            if t != .jsAnything {
                #expect(!(t >= .jsAnything))
            }

            #expect(.wasmAnything >= t || t.Is(.jsAnything))
            if t != .wasmAnything {
                #expect(!(t >= .wasmAnything))
            }

            // .nothing is subsumed by all types and subsumes no other type but itself
            #expect(t >= .nothing)
            if t != .nothing {
                #expect(!(.nothing >= t))
            }
        }
    }

    @Test
    func testObjectTypeSubsumption() {
        // Verify that object type A >= object type B implies that B has at least
        // the properties and methods of A.
        // The opposite direction also holds in many cases, so verify that as well.
        for t1 in typeSuite {
            guard t1.Is(.object()) else { continue }
            for t2 in typeSuite {
                guard t2.Is(.object()) else { continue }

                // If t1 is a more generic object type than t2, then t1's
                // properties and methods must be a subset of those in t2.
                // (a FooBar object is a Foo object because it has a property "foo").
                // .nothing must be excluded here though, because .nothing is also an object.
                if t1 >= t2 && t2 != .nothing {
                    #expect(t1.properties.isSubset(of: t2.properties))
                    #expect(t1.methods.isSubset(of: t2.methods))
                }

                // The opposite direction holds if the base types are equal and if the groups are compatible.
                // E.g. string objects never subsume objects, but can subsume other string objects if the
                // properties and methods are a subset.
                if t1.baseType == t2.baseType && (t1.group == nil || t1.group == t2.group) {
                    if t1.properties.isSubset(of: t2.properties)
                        && t1.methods.isSubset(of: t2.methods) && t1.wasmType == t2.wasmType
                    {
                        #expect(t1 >= t2, "\(t1) >= \(t2)")
                    }
                }
            }
        }

        // With that, test subsumption rules for various different objects types.

        // Run this test three times:
        //   0. Only properties are set
        //   1. Only methods are set
        //   2. Both properties and methods are set
        let foo = ["foo"]
        let bar = ["bar"]
        let baz = ["baz"]
        let fooBar = ["foo", "bar"]
        let fooBaz = ["foo", "baz"]

        for i in 0..<3 {
            // The properties of the object types.
            let fooProperties = i != 1 ? foo : []
            let barProperties = i != 1 ? bar : []
            let bazProperties = i != 1 ? baz : []
            let fooBarProperties = i != 1 ? fooBar : []
            let fooBazProperties = i != 1 ? fooBaz : []

            // The methods of the object types.
            let fooMethods = i != 0 ? foo : []
            let barMethods = i != 0 ? bar : []
            let bazMethods = i != 0 ? baz : []
            let fooBarMethods = i != 0 ? fooBar : []
            let fooBazMethods = i != 0 ? fooBaz : []

            // The object types used in this test.
            let object = ILType.object()
            let fooObj = ILType.object(withProperties: fooProperties, withMethods: fooMethods)
            let barObj = ILType.object(withProperties: barProperties, withMethods: barMethods)
            let bazObj = ILType.object(withProperties: bazProperties, withMethods: bazMethods)
            let fooBarObj = ILType.object(
                withProperties: fooBarProperties, withMethods: fooBarMethods)
            let fooBazObj = ILType.object(
                withProperties: fooBazProperties, withMethods: fooBazMethods)

            // Foo, Bar, Baz, FooBar, and FooBaz objects are all objects, but not every object is a Foo, Bar, Baz, FooBar, or FooBaz object.
            #expect(object >= fooObj)
            #expect(!(fooObj >= object))
            #expect(object >= barObj)
            #expect(!(barObj >= object))
            #expect(object >= bazObj)
            #expect(!(bazObj >= object))
            #expect(object >= fooBarObj)
            #expect(!(fooBarObj >= object))
            #expect(object >= fooBazObj)
            #expect(!(fooBazObj >= object))

            // Order of property and methods names does not matter.
            #expect(
                fooBarObj
                    >= ILType.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            #expect(
                fooBarObj
                    >= ILType.object(
                        withProperties: fooBarProperties.reversed(),
                        withMethods: fooBarMethods.reversed()))
            #expect(
                fooBarObj
                    == ILType.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            #expect(
                fooBarObj
                    == ILType.object(
                        withProperties: fooBarProperties.reversed(),
                        withMethods: fooBarMethods.reversed()))

            // No subsumption relationship between Foo, Bar, and Baz objects
            #expect(!(fooObj >= barObj))
            #expect(!(fooObj >= bazObj))
            #expect(!(barObj >= fooObj))
            #expect(!(barObj >= bazObj))
            #expect(!(bazObj >= fooObj))
            #expect(!(bazObj >= barObj))

            // ... However, their unions are still objects
            #expect(object >= fooObj | barObj)
            #expect(object >= fooObj | bazObj)
            #expect(object >= barObj | bazObj)
            #expect(object >= fooObj | barObj | bazObj)

            // ... And their merged type is a Foo, Bar, and Baz object
            #expect(fooObj >= fooObj + barObj + bazObj)
            #expect(barObj >= fooObj + barObj + bazObj)
            #expect(bazObj >= fooObj + barObj + bazObj)

            // ... Moreover, Foo objects merged with Bar objects yields FooBar objects. Same for Foo and Baz.
            #expect(fooBarObj == fooObj + barObj)
            #expect(fooBazObj == fooObj + bazObj)

            // The intersection of FooBar and Foo or Bar objects again yield FooBar objects as they are a subtype. Same for FooBaz.
            #expect(fooBarObj & fooObj == fooBarObj)
            #expect(fooBarObj & barObj == fooBarObj)
            #expect(fooBazObj & fooObj == fooBazObj)
            #expect(fooBazObj & bazObj == fooBazObj)

            // ... However, the other intersections are empty.
            #expect(fooObj & barObj == .nothing)
            #expect(fooObj & bazObj == .nothing)
            #expect(barObj & bazObj == .nothing)
            #expect(barObj & fooBazObj == .nothing)
            #expect(bazObj & fooBarObj == .nothing)
            #expect(fooBarObj & fooBazObj == .nothing)

            // FooBar objects are Foo objects but not every Foo object is a FooBar object. Same for FooBar and Bar objects.
            #expect(fooObj >= fooBarObj)
            #expect(!(fooBarObj >= fooObj))
            #expect(barObj >= fooBarObj)
            #expect(!(fooBarObj >= barObj))

            // Same as above, but for FooBaz, Foo, and Baz objects.
            #expect(fooObj >= fooBazObj)
            #expect(!(fooBazObj >= fooObj))
            #expect(bazObj >= fooBazObj)
            #expect(!(fooBazObj >= bazObj))

            // FooBar objects are not Baz objects and FooBaz objects are not Bar objects.
            #expect(!(bazObj >= fooBarObj))
            #expect(!(barObj >= fooBazObj))

            // There is no subsumption relationship between FooBar and FooBaz objects
            #expect(!(fooBarObj >= fooBazObj))
            #expect(!(fooBazObj >= fooBarObj))

            // ... However, their union is still a Foo object
            #expect(fooObj >= fooBarObj | fooBazObj)

            // ... And their merged type is a FooBar and a FooBaz object
            #expect(fooBarObj >= fooBarObj + fooBazObj)
            #expect(fooBazObj >= fooBarObj + fooBazObj)

            //... in particular, it is a FooBarBaz object.
            let fooBarBazProperties = fooProperties + barProperties + bazProperties
            let fooBarBazMethods = fooMethods + barMethods + bazMethods
            #expect(fooObj + barObj + bazObj == fooBarObj + fooBazObj)
            #expect(
                fooBarObj + fooBazObj
                    == .object(withProperties: fooBarBazProperties, withMethods: fooBarBazMethods))
        }
    }

    @Test
    func testObjectInspection() {
        let aObj = ILType.object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1", "m2"])
        let bObj = ILType.object(ofGroup: "B", withProperties: ["foo", "bar"])

        #expect(aObj.properties.contains("foo"))
        #expect(bObj.properties.contains("bar"))
        #expect(bObj.properties.contains("foo"))

        #expect(aObj.numProperties == 1)
        #expect(aObj.numMethods == 2)
        #expect(bObj.numProperties == 2)
        #expect(bObj.numMethods == 0)

        // We can be more precise.
        #expect(aObj.properties == ["foo"])
        #expect(bObj.properties == ["foo", "bar"])

        #expect(aObj.methods.contains("m1"))
        #expect(aObj.methods.contains("m2"))

        #expect(aObj.methods == ["m1", "m2"])
        #expect(bObj.methods == [])

        #expect(aObj.group == "A")
        #expect(bObj.group == "B")

        let fooBarObj = ILType.object(withProperties: ["foo", "bar"])
        let fooBazObj = ILType.object(withProperties: ["foo", "baz"])
        #expect((fooBarObj | fooBazObj).properties == ["foo"])
        #expect((fooBarObj + fooBazObj).properties == ["foo", "bar", "baz"])
        #expect((fooBarObj & fooBazObj).properties == [])

        // Unions of objects with non-objects do not have any definite properties or methods.
        #expect((aObj | .integer).properties == [])
        #expect((aObj | .integer).methods == [])

        // However, merging preserves the properties and methods as expected.
        #expect((aObj + .integer).properties == ["foo"])
        #expect((aObj + .integer).methods == ["m1", "m2"])
    }

    @Test
    func testPropertyTypeTransitions() {
        let object = ILType.object(ofGroup: "A")
        let fooObj = ILType.object(ofGroup: "A", withProperties: ["foo"])
        let barObj = ILType.object(ofGroup: "A", withProperties: ["bar"])
        let bazObj = ILType.object(ofGroup: "A", withProperties: ["baz"])
        let fooBarObj = ILType.object(ofGroup: "A", withProperties: ["foo", "bar"])
        let fooBazObj = ILType.object(ofGroup: "A", withProperties: ["foo", "baz"])

        #expect(object.adding(property: "foo") == fooObj)
        #expect(fooObj.adding(property: "bar") == fooBarObj)
        #expect(barObj.adding(property: "foo") == fooBarObj)
        #expect(fooObj.adding(property: "baz") == fooBazObj)
        #expect(bazObj.adding(property: "foo") == fooBazObj)

        #expect(fooBarObj.removing(propertyOrMethod: "baz") == fooBarObj)
        #expect(fooBarObj.removing(propertyOrMethod: "foo") == barObj)
        #expect(barObj.removing(propertyOrMethod: "bar") == object)
    }

    @Test
    func testMethodTypeTransitions() {
        let object = ILType.object(ofGroup: "A")
        let fooObj = ILType.object(ofGroup: "A", withMethods: ["foo"])
        let barObj = ILType.object(ofGroup: "A", withMethods: ["bar"])
        let bazObj = ILType.object(ofGroup: "A", withMethods: ["baz"])
        let fooBarObj = ILType.object(ofGroup: "A", withMethods: ["foo", "bar"])
        let fooBazObj = ILType.object(ofGroup: "A", withMethods: ["foo", "baz"])

        #expect(object.adding(method: "foo") == fooObj)
        #expect(fooObj.adding(method: "bar") == fooBarObj)
        #expect(barObj.adding(method: "foo") == fooBarObj)
        #expect(fooObj.adding(method: "baz") == fooBazObj)
        #expect(bazObj.adding(method: "foo") == fooBazObj)

        #expect(fooBarObj.removing(method: "baz") == fooBarObj)
        #expect(fooBarObj.removing(method: "foo") == barObj)
        #expect(barObj.removing(method: "bar") == object)
    }

    @Test
    func testCallableTypeSubsumption() {
        let signature1 = [.integer, .string] => .jsAnything
        let signature2 = [.boolean, .rest(.jsAnything)] => .object()

        // Repeat the below tests for functions, constructors, and function constructors (function and constructor at the same time)
        // We call something that is a function or a constructor (or both) a "callable".
        let anyCallables = [
            ILType.function(), ILType.constructor(), ILType.functionAndConstructor(),
        ]
        let callable1s = [
            ILType.function(signature1), ILType.constructor(signature1),
            ILType.functionAndConstructor(signature1),
        ]
        let callable2s = [
            ILType.function(signature2), ILType.constructor(signature2),
            ILType.functionAndConstructor(signature2),
        ]

        for i in 0..<3 {
            let anyCallable = anyCallables[i]
            let callable1 = callable1s[i]
            let callable2 = callable2s[i]

            // Both callable1 and callable2 are callables
            #expect(anyCallable >= callable1)
            #expect(anyCallable >= callable2)

            // Not every callable is a callable1 or a callable2
            #expect(!(callable1 >= anyCallable))
            #expect(!(callable2 >= anyCallable))

            // Callable1 is not a callable2 and vice versa
            #expect(!(callable1 >= callable2))
            #expect(!(callable2 >= callable1))

            // Callable1 and callable2 cannot be merged (because they have different signatures)
            #expect(!callable1.canMerge(with: callable2))
            #expect(!callable2.canMerge(with: callable1))

            // ... But they can be unioned, and the union is still a callable
            #expect(anyCallable >= callable1 | callable2)
        }

        // See testSignatureSubsumption for more complicated examples related specifically to signatures.
    }

    @Test
    func testObjectGroupSubsumption() {
        let aObj = ILType.object(ofGroup: "A", withProperties: ["foo"])
        let bObj = ILType.object(ofGroup: "B", withProperties: ["foo", "bar"])

        // Both aObj and bObj are objects.
        #expect(.object() >= aObj)
        #expect(.object() >= bObj)

        // aObj is an object with a property "foo",
        #expect(.object(withProperties: ["foo"]) >= aObj)
        // and an object of group A,
        #expect(.object(ofGroup: "A") >= aObj)
        // but is not an object of group B,
        #expect(!(.object(ofGroup: "B") >= aObj))
        // and not every object with a property "foo" is an object of group A.
        #expect(!(aObj >= .object(withProperties: ["foo"])))

        // Same as above.
        #expect(.object(withProperties: ["bar"]) >= bObj)
        #expect(.object(withProperties: ["foo"]) >= bObj)
        #expect(.object(withProperties: ["foo", "bar"]) >= bObj)
        #expect(.object(ofGroup: "B") >= bObj)
        #expect(!(.object(ofGroup: "A") >= bObj))
        #expect(!(bObj >= .object(withProperties: ["bar"])))
        #expect(!(bObj >= .object(withProperties: ["foo"])))
        #expect(!(bObj >= .object(withProperties: ["foo", "bar"])))

        // No relationship between different groups.
        #expect(!(bObj == aObj || bObj >= aObj || aObj >= bObj))
    }

    @Test
    func testJsModuleSubsumption() {
        let emptyModule = ILType.jsModule()
        let module1 = ILType.jsModule(exports: ["a": .object(), "b": .integer])
        let module2 = ILType.jsModule(exports: ["a": .object()])
        let module3 = ILType.jsModule(exports: ["a": .object(withProperties: ["p"]), "b": .integer])

        #expect(emptyModule.subsumes(module1))
        #expect(!module1.subsumes(emptyModule))

        #expect(module2.subsumes(module1))
        #expect(!module1.subsumes(module2))

        #expect(module1.subsumes(module3))
        #expect(!module3.subsumes(module1))

        #expect(module2.subsumes(module3))
        #expect(!module3.subsumes(module2))
    }

    @Test
    func testJsModuleUnion() {
        let module1 = ILType.jsModule(exports: ["a": .object(), "b": .integer])
        let module2 = ILType.jsModule(exports: ["a": .object()])
        let module3 = ILType.jsModule(exports: ["a": .object(withProperties: ["p"]), "b": .integer])

        let module1Or2 = module1 | module2
        #expect(module1Or2.exports["a"] != nil)
        #expect(.object() == module1Or2.exports["a"])
        #expect(module1Or2.exports["b"] == nil)

        let module1Or3 = module1 | module3
        #expect(module1Or3.exports["a"] != nil)
        #expect(.object() == module1Or3.exports["a"])
        #expect(module1Or3.exports["b"] != nil)
        #expect(.integer == module1Or3.exports["b"])

        let module2Or3 = module2 | module3
        #expect(module2Or3.exports["a"] != nil)
        #expect(.object() == module2Or3.exports["a"])
        #expect(module2Or3.exports["b"] == nil)
    }

    @Test
    func testJsModuleIntersection() {
        let module1 = ILType.jsModule(exports: ["a": .object(), "b": .integer])
        let module2 = ILType.jsModule(exports: ["a": .object()])
        let module3 = ILType.jsModule(exports: ["a": .object(withProperties: ["p"]), "b": .integer])

        let module1And2 = module1 & module2
        #expect(module1And2.exports["a"] != nil)
        #expect(.object() == module1And2.exports["a"])
        #expect(module1And2.exports["b"] != nil)
        #expect(.integer == module1And2.exports["b"])

        let module1And3 = module1 & module3
        #expect(module1And3.exports["a"] != nil)
        #expect(.object(withProperties: ["p"]) == module1And3.exports["a"])
        #expect(module1And3.exports["b"] != nil)
        #expect(.integer == module1And3.exports["b"])

        let module2And3 = module2 & module3
        #expect(module2And3.exports["a"] != nil)
        #expect(.object(withProperties: ["p"]) == module2And3.exports["a"])
        #expect(module2And3.exports["b"] != nil)
        #expect(.integer == module2And3.exports["b"])
    }

    @Test
    func testWasmGlobalSubsumption() {
        let wasmi32Mutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: false)
        let wasmi64Mutable = WasmGlobalType(valueType: ILType.wasmi64, isMutable: true)

        let ILTypeGlobalI32Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalI64Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable)

        #expect(ILTypeGlobalI32Mutable >= ILTypeGlobalI32Mutable)
        // Types which don't have equal WasmTypeExtension don't subsume.
        #expect(!(ILTypeGlobalI32NonMutable >= ILTypeGlobalI32Mutable))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalI32NonMutable))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalI64Mutable))
        #expect(!(ILTypeGlobalI64Mutable >= ILTypeGlobalI32Mutable))
        #expect(!(ILTypeGlobalI32NonMutable >= ILTypeGlobalI64Mutable))

        let ILTypeGlobalI32MutableNoGroup: ILType = ILType.object(
            withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32MutableNoProperty: ILType = ILType.object(
            ofGroup: "WasmGlobal", withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32MutableNoWasmType: ILType = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"])
        let ILTypeGlobalOnlyGroup: ILType = ILType.object(ofGroup: "WasmGlobal")
        let ILTypeGlobalOnlyProperty: ILType = ILType.object(withProperties: ["value"])

        // If the WasmGlobalTypes are equal, the other subsumption rules apply.
        #expect(ILTypeGlobalI32MutableNoGroup >= ILTypeGlobalI32Mutable)
        #expect(ILTypeGlobalI32MutableNoProperty >= ILTypeGlobalI32Mutable)
        #expect(ILTypeGlobalI32MutableNoWasmType >= ILTypeGlobalI32Mutable)
        #expect(ILTypeGlobalOnlyGroup >= ILTypeGlobalI32Mutable)
        #expect(ILTypeGlobalOnlyProperty >= ILTypeGlobalI32Mutable)
        // But not the other way around: the WasmGlobalType matters.
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoGroup))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoProperty))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoWasmType))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalOnlyGroup))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeGlobalOnlyProperty))

        // Groups should match.
        let ILTypeWrongGroup = ILType.object(
            ofGroup: "SomeOtherGroup", withProperties: ["value"], withWasmType: wasmi32Mutable)
        #expect(!(ILTypeWrongGroup >= ILTypeGlobalI32Mutable))
        #expect(!(ILTypeGlobalI32Mutable >= ILTypeWrongGroup))
    }

    @Test
    func testWasmGlobalUnion() {
        let wasmi32Mutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: false)
        let wasmf32Mutable = WasmGlobalType(valueType: ILType.wasmf32, isMutable: true)

        let ILTypeGlobalI32Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalF32Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf32Mutable)

        #expect(ILTypeGlobalI32Mutable | ILTypeGlobalI32Mutable == ILTypeGlobalI32Mutable)

        // Types with not equal WasmTypeExtension don't have a WasmTypeExtension in their union.
        let unionMutabilityDiff = ILType.object(withProperties: ["value"])
        #expect(ILTypeGlobalI32Mutable | ILTypeGlobalI32NonMutable == unionMutabilityDiff)
        // Invariant: the union of two types subsumes both types.
        #expect(unionMutabilityDiff >= ILTypeGlobalI32Mutable)
        #expect(unionMutabilityDiff >= ILTypeGlobalI32NonMutable)

        let unionValueTypeDiff = ILType.object(withProperties: ["value"])
        #expect(ILTypeGlobalI32Mutable | ILTypeGlobalF32Mutable == unionValueTypeDiff)
        #expect(unionValueTypeDiff >= ILTypeGlobalI32Mutable)
        #expect(unionValueTypeDiff >= ILTypeGlobalI32NonMutable)

        // When removing the WasmTypeExtension, the group is also removed. (Note that this specific
        // case is artificial as a .object(ofGroup: WasmGlobal) should only be used e.g. as a
        // search criteria but never appear as a type for a variable without a corresponding
        // .wasmGlobalType extension.)
        #expect(ILTypeGlobalI32Mutable | .object(ofGroup: "WasmGlobal") == .object())
        #expect(.object(ofGroup: "WasmGlobal") >= ILTypeGlobalI32Mutable)
        #expect(
            ILTypeGlobalI32Mutable | .object(withProperties: ["value"])
                == .object(withProperties: ["value"]))
        #expect(.object(withProperties: ["value"]) >= ILTypeGlobalI32Mutable)
    }

    @Test
    func testWasmGlobalIntersection() {
        let wasmi64Mutable = WasmGlobalType(valueType: ILType.wasmi64, isMutable: true)
        let wasmi64NonMutable = WasmGlobalType(valueType: ILType.wasmi64, isMutable: false)
        let wasmf64Mutable = WasmGlobalType(valueType: ILType.wasmf64, isMutable: true)

        let ILTypeGlobalI64Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable)
        let ILTypeGlobalI64NonMutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64NonMutable)
        let ILTypeGlobalF64Mutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf64Mutable)

        #expect(ILTypeGlobalI64Mutable & ILTypeGlobalI64Mutable == ILTypeGlobalI64Mutable)
        #expect(ILTypeGlobalI64Mutable & ILTypeGlobalI64NonMutable == .nothing)
        #expect(ILTypeGlobalI64Mutable & ILTypeGlobalF64Mutable == .nothing)
        #expect(
            ILTypeGlobalI64Mutable & .object(withProperties: ["value"]) == ILTypeGlobalI64Mutable)
        #expect(
            (ILTypeGlobalI64Mutable & ILType.object(withWasmType: wasmi64Mutable))
                == ILType.object(
                    ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable))
    }

    @Test
    func testWasmGlobalIsAndMayBe() {
        let wasmi32Mutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType: ILType.wasmi32, isMutable: false)
        let wasmf64Mutable = WasmGlobalType(valueType: ILType.wasmf64, isMutable: true)

        let ILTypeGlobalI32Mutable: ILType = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalF64Mutable: ILType = ILType.object(
            ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf64Mutable)

        #expect(ILTypeGlobalI32Mutable.Is(.object(ofGroup: "WasmGlobal")))
        #expect(ILTypeGlobalI32Mutable.Is(.object(withProperties: ["value"])))
        #expect(ILTypeGlobalI32Mutable.Is(.object(withWasmType: wasmi32Mutable)))
        #expect(!ILTypeGlobalI32Mutable.Is(ILTypeGlobalI32NonMutable))
        #expect(!ILTypeGlobalI32NonMutable.Is(ILTypeGlobalI32Mutable))
        #expect(!ILTypeGlobalI32Mutable.Is(ILTypeGlobalF64Mutable))
        #expect(!ILTypeGlobalF64Mutable.Is(ILTypeGlobalI32Mutable))

        #expect(ILTypeGlobalI32Mutable.MayBe(.object(ofGroup: "WasmGlobal")))
        #expect(ILTypeGlobalI32Mutable.MayBe(.object(withProperties: ["value"])))
        #expect(ILTypeGlobalI32Mutable.MayBe(.object(withWasmType: wasmi32Mutable)))
        #expect(ILTypeGlobalI32Mutable.MayBe(ILTypeGlobalI32Mutable))
        #expect(!ILTypeGlobalI32Mutable.MayBe(ILTypeGlobalI32NonMutable))
        #expect(!ILTypeGlobalI32NonMutable.MayBe(ILTypeGlobalI32Mutable))
    }

    @Test
    func testTypeUnioning() {
        // Basic union tests
        #expect(.integer | .float >= .integer)
        #expect(.integer | .float >= .float)

        #expect(.integer | .float >= .integer | .float)
        #expect(.integer | .float == .integer | .float)

        #expect(.integer | .float | .string >= .integer)
        #expect(.integer | .float | .string >= .float)
        #expect(.integer | .float | .string >= .string)
        #expect(.integer | .float | .string >= .integer | .float)
        #expect(.integer | .float | .string >= .integer | .string)
        #expect(.integer | .float | .string >= .float | .string)
        #expect(.integer | .float | .string >= .integer | .float | .string)
        #expect(ILType.integer | .float | .string == .integer | .float | .string)
        #expect(ILType.integer | .float | .string == .float | .string | .integer)

        // Test special union cases
        #expect(.jsAnything | .integer == .jsAnything)
        #expect(.jsAnything | .integer == .jsAnything)
        #expect(.jsAnything | .nothing == .jsAnything)
        #expect(.nothing | .nothing == .nothing)
        #expect(.nothing | .jsAnything == .jsAnything)
        #expect(.nothing | .integer == .integer)

        // Test subsumption of unions of related types.
        let objectUnion = .object(withProperties: ["a"]) | .object(withProperties: ["b"])
        // The union is still definitely an object
        #expect(.object() >= objectUnion)

        let objUnionA = .object(withProperties: ["a", "b"]) | .object(withProperties: ["a", "c"])
        // The union type is still an object with a property "a"
        #expect(.object() >= objUnionA)
        #expect(.object(withProperties: ["a"]) >= objUnionA)

        // Unioning primitive types a and b does not suddenly produce something that is a c
        // for an unrelated primitive type c. The same is true for other types, but is more
        // complicated to test there, mainly due to merged types. See below.
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                for t3 in primitiveTypes {
                    if t3 != t1 && t3 != t2 {
                        #expect(
                            !(t1 | t2 >= t3),
                            "\(t3) != \(t1) && \(t3) != \(t2) => \(t1) | \(t2) !>= \(t3)")
                    }
                }
            }
        }

        for t1 in typeSuite {
            #expect(t1 | t1 == t1, "\(t1) | \(t1) (\(t1 | t1)) == \(t1)")

            for t2 in typeSuite {
                // Unioning is symmetric
                #expect(t1 | t2 == t2 | t1)

                let union1 = t1 | t2

                // Union of a and b must subsume a and b: a | b >= a && a | b >= b
                #expect(union1 >= t1, "\(t1) | \(t2) (\(union1)) >= \(t1)")
                #expect(union1 >= t2, "\(t1) | \(t2) (\(union1)) >= \(t2)")

                // One additional guaruantee of the union operation is that it preserves properties common to
                // both input type. E.g. unioning something that is definitely an object with something else
                // that is also definitely an object again produces something that definitely is an object.
                // Test this here loosely by checking the base types.
                if t1.baseType == t2.baseType {
                    #expect(union1.baseType == t1.baseType)
                }

                for t3 in typeSuite {
                    let union2 = union1 | t3
                    #expect(union2 >= t1, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t1)")
                    #expect(union2 >= t2, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t2)")
                    #expect(union2 >= t3, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t3)")
                }
            }
        }
    }

    @Test
    func testTypeIntersection() {
        // The intersection of .string and .object() is empty (as is the case for all unrelated types)
        #expect(ILType.string & ILType.object() == .nothing)
        // the same is true for all "unrelated" types, in particular the primitive types
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                if t1 != t2 {
                    #expect(t1 & t2 == .nothing, "\(t1) & \(t2) (\(t1 & t2)) == .nothing")
                }
            }
        }
        // however, the intersection of StringObject and .string is again a StringObject
        let stringObj = ILType.string + ILType.object()
        #expect(stringObj & .string == stringObj)
        // in the same way as the intersection of .number (.integer | .float) and .integer is .integer (the smaller type)
        #expect(ILType.number & ILType.integer == ILType.integer)
        // but the intersection of a StringObject and an IntegerObject is empty
        let integerObj = ILType.integer + ILType.object()
        #expect(stringObj & integerObj == .nothing)

        // There are some interesting edge cases here.
        // E.g. the intersection of .function() and .function() + .constructor() is the latter (because that's already a subtype)
        let funcCtor = ILType.function() + ILType.constructor()
        #expect(funcCtor & .function() == funcCtor)
        #expect(.function() & funcCtor == funcCtor)
        // and the intersection of .function() and .function([.string] => .float) is also the latter (for the same reason)
        let sig = ([.string] => .float)
        #expect(ILType.function() & .function(sig) == .function(sig))
        // as such, the intersection of .function([.string] => .float) and .function() + .constructor() now becomes
        // .function([.string] => .float) + .constructor([.string] => .float)
        #expect(ILType.function(sig) & funcCtor == .constructor(sig) + .function(sig))
        // Maybe a bit less intuitively, the intersection of two functions with different signatures can also exist.
        // In the following example, the more general signature of the two functions is the intersection as that's what
        // both functions "have in common".
        #expect(
            ILType.function([.jsAnything] => .integer) & .function([.integer] => .jsAnything)
                == .function([.jsAnything] => .integer))
        #expect(
            ILType.function([.jsAnything] => .jsAnything) & .function([.integer] => .jsAnything)
                == .function([.jsAnything] => .jsAnything))
        // In this example, the parameter type is widened and the return type is narrowed.
        #expect(
            ILType.function([.integer] => .integer) & .function([.jsAnything] => .jsAnything)
                == .function([.jsAnything] => .integer))
        // However, here the return types are incompatible
        #expect(
            ILType.function([.integer] => .integer) & .function([.integer] => .string) == .nothing)

        // Now test the basic invariants of intersections for all types in the type suite.
        for t1 in typeSuite {
            #expect(t1 & t1 == t1, "\(t1) & \(t1) (\(t1 | t1)) == \(t1)")

            for t2 in typeSuite {
                // Intersecting is symmetric
                #expect(
                    t1 & t2 == t2 & t1, "\(t1) & \(t2) (\(t2 & t2)) == \(t2) & \(t1) (\(t2 & t1))")

                let intersection = t1 & t2

                // The intersection of a and b must be subsumed by both a and b: a >= a & b && b >= a & b
                #expect(t1 >= intersection, "\(t1) >= \(t1) & \(t2) (\(intersection))")
                #expect(t2 >= intersection, "\(t2) >= \(t1) & \(t2) (\(intersection))")

                // If one of the two inputs subsumes the other, then the result will be the subsumed type.
                if t1 >= t2 {
                    #expect(
                        t1 & t2 == t2, "\(t1) >= \(t2) => \(t1) & \(t2) (\(t1 & t2)) == \(t2)")
                }
            }
        }
    }

    @Test
    func testTypeMerging() {
        let obj = ILType.object(withProperties: ["foo"])
        let str = ILType.string
        let strObj = obj + str

        // A string object is both a string and an object.
        #expect(str >= strObj)
        #expect(obj >= strObj)

        // But is not suddenly e.g. an integer.
        #expect(!(.integer >= strObj))
        // Or an integer object
        #expect(!(.integer + .object() >= strObj))

        // And not every string or every object is a string object.
        #expect(!(strObj >= str))
        #expect(!(strObj >= obj))

        // Test the above (as good as possible) for all types in the test suite.
        for t1 in typeSuite {
            for t2 in typeSuite {
                guard t1.canMerge(with: t2) else { continue }

                // Merging is symmetric
                #expect(t1 + t2 == t2 + t1)

                let merged = t1 + t2

                // Merging t1 and t2 yields a type that is both a t1 and a t2
                #expect(t1 >= merged, "\(t1) >= \(t1) + \(t2) (\(merged))")
                #expect(t2 >= merged, "\(t2) >= \(t1) + \(t2) (\(merged))")

                for t3 in typeSuite {
                    if t3 >= t1 || t3 >= t2 {
                        // If t1 or t2 are a t3, than the merged type t1 + t2 must also be a t3.
                        #expect(
                            t3 >= merged,
                            "\(t3) >= \(t1) || \(t3) >= \(t2) implies \(t3) >= \(t1) + \(t2) (\(merged))"
                        )
                    }

                    guard t1.canMerge(with: t3) && t2.canMerge(with: t3) else { continue }
                    if t1 >= t2 {
                        #expect(
                            t1 + t3 >= t2 + t3,
                            "\(t1) >= \(t2) implies \(t1) + \(t3) >= \(t2) + \(t3)")
                    }
                }
            }
        }

        // Test that type merging is possible for the expected types.
        for t1 in typeSuite {
            for t2 in typeSuite {
                // Union types cannot be merged
                if t1.isUnion || t2.isUnion {
                    #expect(!t1.canMerge(with: t2))
                }

                // .nothing cannot be merged
                else if t1 == .nothing || t2 == .nothing {
                    #expect(!t1.canMerge(with: t2))
                }

                // Callables with different signatures cannot be merged
                else if t1.isCallable && t2.isCallable && t1.signature != nil && t2.signature != nil
                    && t1.signature != t2.signature
                {
                    #expect(!t1.canMerge(with: t2))
                }

                else if t1.isCallable && t2.isCallable && t1.receiver != nil && t2.receiver != nil
                    && t1.receiver != t2.receiver
                {
                    #expect(!t1.canMerge(with: t2))
                }

                // Objects of different groups cannot be merged
                else if t1.group != nil && t2.group != nil && t1.group != t2.group {
                    #expect(!t1.canMerge(with: t2))
                }

                // Objects with different WasmTypeExtensions cannot be merged.
                else if t1.wasmType != nil && t2.wasmType != nil && t1.wasmType != t2.wasmType {
                    #expect(!t1.canMerge(with: t2))
                }

                // Iterables with different parameterization cannot be merged.
                else if t1.iterableElementType != nil && t2.iterableElementType != nil
                    && t1.iterableElementType != t2.iterableElementType
                {
                    #expect(!t1.canMerge(with: t2))
                }

                // Everything else can be merged
                else {
                    #expect(t1.canMerge(with: t2), "\(t1) \(t2)")
                    // Merging is symmetric
                    #expect(t2.canMerge(with: t1))
                }
            }
        }
    }

    @Test
    func testSignatureTypes() {
        let sig1 = [.jsAnything, .string, .integer, .opt(.integer), .opt(.float)] => .undefined
        #expect(!sig1.parameters[0].isOptionalParameter)
        #expect(!sig1.parameters[1].isOptionalParameter)
        #expect(!sig1.parameters[2].isOptionalParameter)
        #expect(sig1.parameters[3].isOptionalParameter)
        #expect(sig1.parameters[4].isOptionalParameter)

        let sig2 = [.integer, .opt(.integer), .rest(.float)] => .undefined
        #expect(!sig2.parameters[0].isOptionalParameter)
        #expect(!sig2.parameters[0].isRestParameter)
        #expect(sig2.parameters[1].isOptionalParameter)
        #expect(!sig2.parameters[1].isRestParameter)
        #expect(!sig2.parameters[2].isOptionalParameter)
        #expect(sig2.parameters[2].isRestParameter)

        let sig3 = [.either(.integer, .string)] => .undefined
        #expect(!sig3.parameters[0].isOptionalParameter)
        #expect(!sig3.parameters[0].isRestParameter)
    }

    @Test
    func testSignatureSubsumption() {
        // For sig1 to subsume sig2, sig1's parameters must be subsumed by their
        // counterparts in sig2.
        // In other words, if we need a function that accepts an integer as first
        // parameter, then we're fine receiving a function that accepts anything
        // (or e.g. a number) as first parameter.
        #expect(([.integer] => .undefined) >= ([.jsAnything] => .undefined))
        #expect(([.integer, .string] => .undefined) >= ([.number, .string] => .undefined))
        #expect(([.integer, .string] => .undefined) >= ([.integer, .primitive] => .undefined))
        // but not one that requires a string.
        #expect(!(([.integer] => .undefined) >= ([.string] => .undefined)))
        #expect(!(([.integer, .integer] => .undefined) >= ([.integer, .string] => .undefined)))
        // Or, phrased differentley still, a function that accepts anything as first
        // parameter is a function that accepts an integer as first parameter.
        #expect(
            ILType.function([.jsAnything] => .undefined).Is(.function([.integer] => .undefined)))
        // However, the other direction does not hold: if we want a function that
        // accepts anything as first parameter, we cannot use a function that
        // requires an integer as first parameter instead.
        #expect(!(([.jsAnything] => .undefined) >= ([.integer] => .undefined)))

        // Signatures with more parameters subsume signatures with fewer parameters
        // because the additional parameters are simply ignored.
        #expect(([.integer] => .undefined) >= ([] => .undefined))
        #expect(([.jsAnything, .jsAnything] => .undefined) >= ([.jsAnything] => .undefined))
        // But the other way doesn't work: if we want a function that takes no parameters,
        // we cannot use one that requires parameters instead.
        #expect(!(([] => .undefined) >= ([.jsAnything] => .undefined)))

        // A signature with rest parameters is subsumed by a signature with no rest parameters
        // if either there are no parameters that will "turn into" rest parameters, or if
        // they all have the correct type.
        #expect(([] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(([.jsAnything] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(([.integer, .number] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(([.integer, .integer] => .undefined) >= ([.integer...] => .undefined))
        #expect(!(([.integer, .boolean] => .undefined) >= ([.integer...] => .undefined)))
        #expect(([.integer, .boolean] => .undefined) >= ([.primitive...] => .undefined))
        // A signature with rest parameters subsumes a signature with no rest parameters
        // only if the subsumed function expects no parameters at the position of the
        // rest parameter (because it can be omitted by the caller).
        #expect(([.jsAnything...] => .undefined) >= ([] => .undefined))
        #expect(!(([.jsAnything...] => .undefined) >= ([.jsAnything] => .undefined)))
        // If both signatures have rest parameters, then these must be compatible.
        #expect(([.jsAnything...] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(([.integer...] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(([.integer, .integer...] => .undefined) >= ([.jsAnything...] => .undefined))
        #expect(!(([.integer, .boolean...] => .undefined) >= ([.number...] => .undefined)))
        #expect(!(([.jsAnything...] => .undefined) >= ([.integer...] => .undefined)))
        #expect(!(([.integer, .jsAnything...] => .undefined) >= ([.integer...] => .undefined)))

        // Optional parameters behave mostly identical to rest parameters, except that they
        // are only expanded once.
        #expect(([] => .undefined) >= ([.opt(.integer), .opt(.float)] => .undefined))
        #expect(([.opt(.integer)] => .undefined) >= ([.opt(.jsAnything)] => .undefined))
        #expect(([.opt(.integer)] => .undefined) >= ([] => .undefined))
        #expect(
            ([.string, .opt(.integer)] => .undefined) >= ([.string, .jsAnything...] => .undefined))
        #expect(([.integer] => .undefined) >= ([.opt(.integer)] => .undefined))
        #expect(
            !(([.integer, .integer] => .undefined)
                >= ([.opt(.integer), .opt(.string)] => .undefined)))
        #expect(!(([.opt(.integer)] => .undefined) >= ([.integer] => .undefined)))
        #expect(!(([.opt(.integer)] => .undefined) >= ([.string...] => .undefined)))
        #expect(!(([.string...] => .undefined) >= ([.opt(.integer)] => .undefined)))

        // Signatures with .either parameters
        #expect(([.either(.integer, .float)] => .undefined) >= ([.number] => .undefined))
        #expect(!(([.either(.integer, .string)] => .undefined) >= ([.number] => .undefined)))
        #expect(([.integer] => .undefined) >= ([.either(.number, .string)] => .undefined))
        #expect(([.integer] => .undefined) >= ([.either(.string, .number)] => .undefined))
        #expect(!(([.integer] => .undefined) >= ([.either(.string, .boolean)] => .undefined)))
        #expect(
            ([.either(.integer, .string)] => .undefined)
                >= ([.either(.number, .jsAnything)]
                    => .undefined))
        #expect(
            ([.either(.integer, .string)] => .undefined)
                >= ([.either(.jsAnything, .number)]
                    => .undefined))
        #expect(
            !(([.either(.integer, .string)] => .undefined)
                >= ([.either(.number, .boolean)] => .undefined)))

        // Test return value subsumption: sig1 subsumes sig2 if sig1's return value subsumes that
        // of sig2. For example, a function returning .integer is a function returning a .number.
        #expect(([] => .number) >= ([] => .integer))
        #expect(([] => .jsAnything) >= ([] => .integer))
        #expect(!(([] => .integer) >= ([] => .number)))
        #expect(!(([] => .integer) >= ([] => .jsAnything)))

        // Check that the unknown function signature is subsumed by most other signatures.
        #expect(Signature.forUnknownFunction <= ([] => .jsAnything))
        #expect(Signature.forUnknownFunction <= ([.jsAnything] => .jsAnything))
        #expect(Signature.forUnknownFunction <= ([.integer, .string] => .jsAnything))
    }

    @Test
    func testCustomGroupsSubsumption() {
        // This is ok, see also the comment in TypeSystem.subsumes.
        // Essentially, we have these ObjectGroups such that we can ask them about their types for more informed CodeGeneration.
        // Previously we would just say that all objects are the same anyways.
        // Now we want them to be interchangeable, e.g. for splicing in JS.
        #expect(ILType.object(ofGroup: "_fuzz_Object0").Is(.object(ofGroup: "_fuzz_Object1")))
        #expect(
            ILType.object(ofGroup: "_fuzz_WasmExports0").Is(.object(ofGroup: "_fuzz_WasmExports1")))
        #expect(
            ILType.object(ofGroup: "_fuzz_WasmModule0").Is(.object(ofGroup: "_fuzz_WasmModule1")))
        #expect(ILType.object(ofGroup: "_fuzz_Class1").Is(.object(ofGroup: "_fuzz_Class0")))
        #expect(
            ILType.object(ofGroup: "_fuzz_Constructor1").Is(.object(ofGroup: "_fuzz_Constructor0")))

        #expect(!ILType.object(ofGroup: "_fuzz_Constructor1").Is(.object(ofGroup: "_fuzz_Class0")))
        #expect(!ILType.object(ofGroup: "_fuzz_Class1").Is(.object(ofGroup: "_fuzz_Constructor1")))

        // Negative tests to make sure they don't subsume if they don't subsume based on properties / methods..
        #expect(
            ILType.object(ofGroup: "_fuzz_Object1", withMethods: ["a"]).Is(
                .object(ofGroup: "_fuzz_Object0")))
        #expect(
            !ILType.object(ofGroup: "_fuzz_Object1").Is(
                .object(ofGroup: "_fuzz_Object0", withMethods: ["a"])))

        #expect(
            ILType.object(ofGroup: "_fuzz_Class1", withProperties: ["a"]).Is(
                .object(ofGroup: "_fuzz_Class0")))
        #expect(
            !ILType.object(ofGroup: "_fuzz_Class1").Is(
                .object(ofGroup: "_fuzz_Class0", withProperties: ["a"])))

        #expect(
            ILType.object(ofGroup: "_fuzz_Object1", withProperties: ["a", "b"]).Is(
                .object(ofGroup: "_fuzz_Object0", withProperties: ["a"])))
        #expect(
            !ILType.object(ofGroup: "_fuzz_Object1", withProperties: ["b"]).Is(
                .object(ofGroup: "_fuzz_Object0", withProperties: ["a"])))

    }

    @Test
    func testNamedStrings() {
        let namedA = ILType.namedString(ofName: "A")
        #expect(namedA.Is(.string))
        let namedB = ILType.namedString(ofName: "B")
        #expect(namedA | namedB == .string)
        #expect(namedA & namedB == .nothing)
        let objectA = ILType.object(ofGroup: "A", withProperties: ["a"])
        #expect(namedA & objectA == .nothing)
    }

    @Test
    func testTypeDescriptions() {
        // Test primitive types
        #expect(ILType.undefined.description == ".undefined")
        #expect(ILType.integer.description == ".integer")
        #expect(ILType.bigint.description == ".bigint")
        #expect(ILType.float.description == ".float")
        #expect(ILType.string.description == ".string")
        #expect(ILType.regexp.description == ".regexp")
        #expect(ILType.boolean.description == ".boolean")
        #expect(ILType.bigint.description == ".bigint")
        #expect(ILType.iterable().description == ".iterable")

        // Test object types
        #expect(ILType.object().description == ".object()")
        #expect(
            ILType.object(withProperties: ["foo"]).description
                == ".object(withProperties: [\"foo\"])")
        #expect(ILType.object(withMethods: ["m"]).description == ".object(withMethods: [\"m\"])")

        // Property and method order is not defined
        let fooBarObj = ILType.object(withProperties: ["foo", "bar"])
        #expect(
            fooBarObj.description == ".object(withProperties: [\"foo\", \"bar\"])"
                || fooBarObj.description == ".object(withProperties: [\"bar\", \"foo\"])")

        let objWithMethods = ILType.object(withMethods: ["m1", "m2"])
        #expect(
            objWithMethods.description == ".object(withMethods: [\"m1\", \"m2\"])"
                || objWithMethods.description == ".object(withMethods: [\"m2\", \"m1\"])")

        let fooBarObjWithMethod = ILType.object(withProperties: ["foo", "bar"], withMethods: ["m"])
        #expect(
            fooBarObjWithMethod.description
                == ".object(withProperties: [\"foo\", \"bar\"], withMethods: [\"m\"])"
                || fooBarObjWithMethod.description
                    == ".object(withProperties: [\"bar\", \"foo\"], withMethods: [\"m\"])"
        )

        // Test function and constructor types
        #expect(ILType.function().description == ".function()")
        #expect(
            ILType.function([.rest(.jsAnything)] => .jsAnything).description
                == ".function([.jsAnything...] => .jsAnything)")
        #expect(
            ILType.function([.float, .opt(.integer)] => .object()).description
                == ".function([.float, .opt(.integer)] => .object())")
        #expect(
            ILType.function([.integer, .boolean, .rest(.jsAnything)] => .object()).description
                == ".function([.integer, .boolean, .jsAnything...] => .object())")

        #expect(ILType.constructor().description == ".constructor()")
        #expect(
            ILType.constructor([.rest(.jsAnything)] => .jsAnything).description
                == ".constructor([.jsAnything...] => .jsAnything)")
        #expect(
            ILType.constructor([.integer, .boolean, .rest(.jsAnything)] => .object()).description
                == ".constructor([.integer, .boolean, .jsAnything...] => .object())")

        #expect(ILType.functionAndConstructor().description == ".function() + .constructor()")
        #expect(
            ILType.functionAndConstructor([.rest(.jsAnything)] => .jsAnything).description
                == ".function([.jsAnything...] => .jsAnything) + .constructor([.jsAnything...] => .jsAnything)"
        )
        #expect(
            ILType.functionAndConstructor([.integer, .boolean, .rest(.jsAnything)] => .object())
                .description
                == ".function([.integer, .boolean, .jsAnything...] => .object()) + .constructor([.integer, .boolean, .jsAnything...] => .object())"
        )

        #expect(
            ILType.unboundFunction(
                ([.integer, .boolean, .rest(.jsAnything)] => .object()), receiver: .object()
            ).description
                == ".unboundFunction([.integer, .boolean, .jsAnything...] => .object(), receiver: .object())"
        )
        #expect(ILType.unboundFunction().description == ".unboundFunction(nil, receiver: nil)")

        // Test other "well-known" types
        #expect(ILType.nothing.description == ".nothing")
        #expect(ILType.jsAnything.description == ".jsAnything")

        #expect(ILType.primitive.description == ".primitive")
        #expect(ILType.number.description == ".number")

        // Test union types
        let strOrInt = ILType.integer | ILType.string
        #expect(strOrInt.description == ".integer | .string")

        let strOrIntOrObj = ILType.integer | ILType.string | ILType.object(withProperties: ["foo"])
        // Note: information about properties and methods is discarded when unioning with non-object types.
        #expect(strOrIntOrObj.description == ".integer | .string | .object()")

        let objOrFunc = ILType.object() | ILType.function([.integer, .integer] => .integer)
        // Note: information about signatures is discarded when unioning callable types.
        #expect(objOrFunc.description == ".object() | .function()")

        // Test merged types
        let strObj = ILType.string + ILType.object(withProperties: ["foo"])
        #expect(strObj.description == ".string + .object(withProperties: [\"foo\"])")

        let funcObj =
            ILType.object(withProperties: ["foo"], withMethods: ["m"])
            + ILType.function([.integer, .rest(.jsAnything)] => .boolean)
        #expect(
            funcObj.description
                == ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.integer, .jsAnything...] => .boolean)"
        )

        let funcConstrObj =
            ILType.object(withProperties: ["foo"], withMethods: ["m"])
            + ILType.functionAndConstructor([.integer, .rest(.jsAnything)] => .boolean)
        #expect(
            funcConstrObj.description
                == ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.integer, .jsAnything...] => .boolean) + .constructor([.integer, .jsAnything...] => .boolean)"
        )

        // Test union of merged types
        let strObjOrFuncObj =
            (ILType.string + ILType.object(withProperties: ["foo"]))
            | (ILType.function([.rest(.jsAnything)] => .float)
                + ILType.object(withProperties: ["foo"]))
        #expect(
            strObjOrFuncObj.description
                == ".string + .object(withProperties: [\"foo\"]) | .object(withProperties: [\"foo\"]) + .function()"
        )

        let nullExn = ILType.wasmRef(.WasmExn, shared: true, nullability: true)
        let nonNullAny = ILType.wasmRef(.WasmAny, shared: false, nullability: false)
        #expect(nullExn.description == ".wasmRef(.Abstract(null shared WasmExn))")
        #expect(nonNullAny.description == ".wasmRef(.Abstract(WasmAny))")

        // TODO(pawkra): add shared variant.
        let arrayDesc = WasmArrayTypeDescription(
            elementType: .wasmi32, mutability: false, typeGroupIndex: 0)
        let arrayRef = ILType.wasmIndexRef(arrayDesc, nullability: true)
        #expect(arrayRef.description == ".wasmRef(null Index 0 Array[immutable .wasmi32])")
        let nullableSelfRef = ILType.wasmRef(
            .Index(.init(WasmTypeDescription.selfReference)), nullability: true)
        let structDesc = WasmStructTypeDescription(
            fields: [
                .init(type: .wasmf32, mutability: true),
                .init(type: nullableSelfRef, mutability: false),  // unresolved
                .init(type: arrayRef, mutability: true),
            ], typeGroupIndex: 1)
        let structRef = ILType.wasmIndexRef(structDesc, nullability: false)
        #expect(
            structRef.description == ".wasmRef(Index 1 Struct[mutable .wasmf32, "
                + "immutable .wasmRef(null Index selfReference), mutable .wasmRef(null Index 0 Array)])"
        )
        // Create a cycle (a "resolved" self reference) for an array element type.
        arrayDesc.elementType = arrayRef
        #expect(
            arrayRef.description
                == ".wasmRef(null Index 0 Array[immutable .wasmRef(null Index 0 Array)])")
        // Create a cycle for a struct field type.
        structDesc.fields[1].type = .wasmIndexRef(structDesc, nullability: true)
        #expect(
            structRef.description == ".wasmRef(Index 1 Struct[mutable .wasmf32, "
                + "immutable .wasmRef(null Index 1 Struct), mutable .wasmRef(null Index 0 Array)])")

        // Type definitions print the same thing as references just with .wasmTypeDef instead of
        // .wasmRef.
        let arrayDef = ILType.wasmTypeDef(description: arrayDesc)
        #expect(
            arrayDef.description == ".wasmTypeDef(0 Array[immutable .wasmRef(null Index 0 Array)])")
        let structDef = ILType.wasmTypeDef(description: structDesc)
        #expect(
            structDef.description == ".wasmTypeDef(1 Struct[mutable .wasmf32, "
                + "immutable .wasmRef(null Index 1 Struct), mutable .wasmRef(null Index 0 Array)])")
        let signatureDesc = WasmSignatureTypeDescription(
            signature: [.wasmi32, arrayRef] => [structRef, .wasmNullRef(shared: true)],
            typeGroupIndex: 0)
        let signatureDef = ILType.wasmTypeDef(description: signatureDesc)
        #expect(
            signatureDef.description
                == ".wasmTypeDef(0 Func[[.wasmi32, .wasmRef(null Index 0 Array)] => "
                + "[.wasmRef(Index 1 Struct), .wasmRef(.Abstract(null shared WasmNone))]])")

        // A generic index type without a type description.
        // These are e.g. used by the element types for arrays and structs inside the operation as
        // the operation doesn't know about the actual type definition inputs.
        let nullableGenericIndexRef = ILType.wasmRef(.Index(), nullability: true)
        #expect(nullableGenericIndexRef.description == ".wasmRef(null Index)")
        #expect(ILType.anyNonNullableIndexRef.description == ".wasmRef(Index)")
    }

    @Test
    func testWasmSubsumptionRules() {
        let wasmTypes: [ILType] =
            [.wasmi32, .wasmi64, .wasmf32, .wasmf64] + ILType.allNullableAbstractWasmRefTypes()
        // Make sure that no Wasm type is subsumed by (JS-)anything.
        for t in wasmTypes {
            #expect(!(t <= .jsAnything))
        }
    }

    @Test
    func testWasmTypeExtensionSubsumptionRules() {
        let arrayi32Desc = WasmArrayTypeDescription(
            elementType: .wasmi32, mutability: true, typeGroupIndex: 0)
        let arrayi64Desc = WasmArrayTypeDescription(
            elementType: .wasmi64, mutability: true, typeGroupIndex: 0)

        // Test Wasm reference type definitions.
        #expect(ILType.wasmTypeDef() != ILType.wasmTypeDef(description: arrayi32Desc))
        #expect(
            ILType.wasmTypeDef(description: arrayi64Desc)
                != ILType.wasmTypeDef(description: arrayi32Desc))
        #expect(
            ILType.wasmTypeDef(description: arrayi32Desc)
                == ILType.wasmTypeDef(description: arrayi32Desc))
        #expect(ILType.wasmTypeDef(description: arrayi32Desc) <= ILType.wasmTypeDef())
        #expect(
            ILType.wasmTypeDef(description: arrayi32Desc)
                <= ILType.wasmTypeDef(description: arrayi32Desc))
        #expect(
            !(ILType.wasmTypeDef(description: arrayi32Desc)
                <= ILType.wasmTypeDef(description: arrayi64Desc)))

        // Test Wasm references.
        #expect(
            ILType.wasmRef(.Index(), nullability: true)
                <= ILType.wasmRef(.Index(), nullability: true))
        #expect(
            ILType.wasmRef(.Index(), nullability: false)
                <= ILType.wasmRef(.Index(), nullability: false))
        #expect(
            ILType.wasmRef(.Index(), nullability: false)
                <= ILType.wasmRef(.Index(), nullability: true))
        #expect(
            !(ILType.wasmRef(.Index(), nullability: true)
                <= ILType.wasmRef(.Index(), nullability: false)))
        #expect(!(ILType.wasmi32 <= ILType.wasmRef(.Index(), nullability: true)))
        #expect(!(ILType.wasmRef(.Index(), nullability: true) <= ILType.wasmi32))
        #expect(
            !(ILType.wasmIndexRef(arrayi32Desc, nullability: true)
                >= ILType.wasmIndexRef(arrayi64Desc, nullability: true)))
        #expect(
            !(ILType.wasmIndexRef(arrayi64Desc, nullability: true)
                >= ILType.wasmIndexRef(arrayi32Desc, nullability: true)))
        #expect(
            ILType.wasmIndexRef(arrayi32Desc, nullability: true)
                >= ILType.wasmIndexRef(arrayi32Desc, nullability: true))
        #expect(
            ILType.wasmIndexRef(arrayi32Desc, nullability: true)
                >= ILType.wasmIndexRef(arrayi32Desc, nullability: false))
        #expect(
            ILType.wasmRef(.Index(), nullability: true)
                >= ILType.wasmIndexRef(arrayi32Desc, nullability: true))
        #expect(
            !(ILType.wasmRef(.Index(), nullability: true)
                <= ILType.wasmIndexRef(arrayi32Desc, nullability: true)))

        #expect(ILType.wasmRef(.Index(), nullability: true) <= ILType.wasmGenericRef)
        #expect(!(ILType.wasmGenericRef <= ILType.wasmRef(.Index(), nullability: true)))

        // Test nullability rules for abstract Wasm types.
        for heapType: WasmAbstractHeapType in WasmAbstractHeapType.allCases {
            for shared in [true, false] {
                let nullable = ILType.wasmRef(heapType, shared: shared, nullability: true)
                let nonNullable = ILType.wasmRef(heapType, shared: shared, nullability: false)
                #expect(nonNullable.Is(nullable))
                #expect(!nullable.Is(nonNullable))
                #expect(nullable.union(with: nonNullable) == nullable)
                #expect(nonNullable.union(with: nullable) == nullable)
                #expect(nullable.intersection(with: nonNullable) == nonNullable)
                #expect(nonNullable.intersection(with: nullable) == nonNullable)
            }
        }
    }

    @Test
    func testWasmSubtypingRules() {
        let baseDesc = WasmTypeDescription(typeGroupIndex: 0)
        let subDesc = WasmTypeDescription(typeGroupIndex: 1, concreteHeapSupertype: baseDesc)
        let subSubDesc = WasmTypeDescription(typeGroupIndex: 2, concreteHeapSupertype: subDesc)
        let unrelatedDesc = WasmTypeDescription(typeGroupIndex: 3)
        let finalSubDesc = WasmTypeDescription(
            typeGroupIndex: 4, concreteHeapSupertype: baseDesc, isFinal: true)

        #expect(baseDesc.subsumes(baseDesc))
        #expect(baseDesc.subsumes(subDesc))
        #expect(baseDesc.subsumes(subSubDesc))
        #expect(subDesc.subsumes(subSubDesc))
        #expect(baseDesc.subsumes(finalSubDesc))

        #expect(!subDesc.subsumes(baseDesc))
        #expect(!subSubDesc.subsumes(baseDesc))
        #expect(!subSubDesc.subsumes(subDesc))
        #expect(!finalSubDesc.subsumes(baseDesc))

        #expect(!baseDesc.subsumes(unrelatedDesc))
        #expect(!unrelatedDesc.subsumes(baseDesc))

        let anyTypeDef = ILType.wasmTypeDef()
        let baseDef = ILType.wasmTypeDef(description: baseDesc)
        let subDef = ILType.wasmTypeDef(description: subDesc)
        let subSubDef = ILType.wasmTypeDef(description: subSubDesc)
        let unrelatedDef: ILType = ILType.wasmTypeDef(description: unrelatedDesc)
        let finalSubDef = ILType.wasmTypeDef(description: finalSubDesc)

        #expect(baseDef >= baseDef)
        #expect(baseDef >= subDef)
        #expect(baseDef >= subSubDef)
        #expect(subDef >= subSubDef)

        #expect(!(baseDef >= finalSubDef))
        #expect(finalSubDef >= finalSubDef)

        #expect(!(subDef >= baseDef))
        #expect(!(subSubDef >= baseDef))
        #expect(!(subSubDef >= subDef))

        #expect(!(baseDef >= unrelatedDef))
        #expect(!(unrelatedDef >= baseDef))

        #expect(anyTypeDef >= baseDef)
        #expect(!(baseDef >= anyTypeDef))

        #expect(anyTypeDef.union(with: baseDef) == anyTypeDef)
        #expect(baseDef.union(with: anyTypeDef) == anyTypeDef)
        #expect(baseDef.union(with: subDef) == baseDef)
        #expect(subDef.union(with: baseDef) == baseDef)

        #expect(anyTypeDef.intersection(with: baseDef) == baseDef)
        #expect(baseDef.intersection(with: anyTypeDef) == baseDef)
        #expect(baseDef.intersection(with: subDef) == subDef)
        #expect(subDef.intersection(with: baseDef) == subDef)
        #expect(baseDef.intersection(with: finalSubDef) == .nothing)

        let baseRefNullable = ILType.wasmIndexRef(baseDesc, nullability: true)
        let subRefNullable = ILType.wasmIndexRef(subDesc, nullability: true)
        let subSubRefNullable = ILType.wasmIndexRef(subSubDesc, nullability: true)
        let unrelatedRefNullable = ILType.wasmIndexRef(unrelatedDesc, nullability: true)
        let finalSubRefNullable = ILType.wasmIndexRef(finalSubDesc, nullability: true)

        let subRefNonNull = ILType.wasmIndexRef(subDesc, nullability: false)
        let subSubRefNonNull = ILType.wasmIndexRef(subSubDesc, nullability: false)

        #expect(baseRefNullable >= baseRefNullable)
        #expect(baseRefNullable >= subRefNullable)
        #expect(baseRefNullable >= subSubRefNullable)
        #expect(subRefNullable >= subSubRefNullable)

        #expect(baseRefNullable >= finalSubRefNullable)
        #expect(!(finalSubRefNullable >= baseRefNullable))

        #expect(!(subRefNullable >= baseRefNullable))
        #expect(!(subSubRefNullable >= baseRefNullable))
        #expect(!(subSubRefNullable >= subRefNullable))

        #expect(!(baseRefNullable >= unrelatedRefNullable))
        #expect(!(unrelatedRefNullable >= baseRefNullable))

        #expect(subRefNonNull >= subSubRefNonNull)
        #expect(!(subSubRefNonNull >= subRefNonNull))
        #expect(baseRefNullable >= subSubRefNonNull)
        #expect(!(subRefNonNull >= subSubRefNullable))
        #expect(subRefNullable >= subSubRefNullable)

        #expect(baseRefNullable.union(with: subRefNullable) == baseRefNullable)
        #expect(subRefNullable.union(with: baseRefNullable) == baseRefNullable)
        #expect(subRefNullable.union(with: subSubRefNullable) == subRefNullable)
        #expect(subSubRefNullable.union(with: subRefNullable) == subRefNullable)
        #expect(baseRefNullable.union(with: subSubRefNullable) == baseRefNullable)
        #expect(subSubRefNullable.union(with: baseRefNullable) == baseRefNullable)
        #expect(subRefNullable.union(with: subRefNullable) == subRefNullable)

        #expect(baseRefNullable.union(with: finalSubRefNullable) == baseRefNullable)
        #expect(finalSubRefNullable.union(with: baseRefNullable) == baseRefNullable)

        #expect(subRefNonNull.union(with: subSubRefNonNull) == subRefNonNull)
        #expect(subRefNullable.union(with: subRefNonNull) == subRefNullable)
        #expect(subRefNonNull.union(with: subSubRefNullable) == subRefNullable)

        #expect(baseRefNullable.intersection(with: subRefNullable) == subRefNullable)
        #expect(subRefNullable.intersection(with: baseRefNullable) == subRefNullable)
        #expect(subRefNullable.intersection(with: subSubRefNullable) == subSubRefNullable)
        #expect(subSubRefNullable.intersection(with: subRefNullable) == subSubRefNullable)
        #expect(baseRefNullable.intersection(with: subSubRefNullable) == subSubRefNullable)
        #expect(subSubRefNullable.intersection(with: baseRefNullable) == subSubRefNullable)
        #expect(subRefNullable.intersection(with: subRefNullable) == subRefNullable)

        #expect(baseRefNullable.intersection(with: finalSubRefNullable) == finalSubRefNullable)
        #expect(finalSubRefNullable.intersection(with: baseRefNullable) == finalSubRefNullable)

        #expect(subRefNonNull.intersection(with: subSubRefNonNull) == subSubRefNonNull)
        #expect(subRefNullable.intersection(with: subRefNonNull) == subRefNonNull)
        #expect(subRefNonNull.intersection(with: subSubRefNullable) == subSubRefNonNull)
    }

    @Test
    func testWasmArraySubtypingRules() {
        let anyRefType = ILType.wasmAnyRef()
        let indexDesc = WasmArrayTypeDescription(
            elementType: .wasmi32, mutability: true, typeGroupIndex: 0)
        let indexRefType = ILType.wasmIndexRef(indexDesc, nullability: true)

        let superArrayDescImmutable = WasmArrayTypeDescription(
            elementType: anyRefType, mutability: false, typeGroupIndex: 1)
        let subArrayDescImmutable = WasmArrayTypeDescription(
            elementType: indexRefType, mutability: false, typeGroupIndex: 2,
            concreteHeapSupertype: superArrayDescImmutable)
        let subArrayDescMutable = WasmArrayTypeDescription(
            elementType: indexRefType, mutability: true, typeGroupIndex: 3,
            concreteHeapSupertype: superArrayDescImmutable)

        #expect(superArrayDescImmutable.subsumes(subArrayDescImmutable))
        #expect(!subArrayDescImmutable.subsumes(superArrayDescImmutable))
        #expect(superArrayDescImmutable.subsumes(subArrayDescMutable))
        #expect(!subArrayDescMutable.subsumes(superArrayDescImmutable))

        let superArrayDescMutable = WasmArrayTypeDescription(
            elementType: indexRefType, mutability: true, typeGroupIndex: 4)
        let subArrayDescMutable2 = WasmArrayTypeDescription(
            elementType: indexRefType, mutability: true, typeGroupIndex: 5,
            concreteHeapSupertype: superArrayDescMutable)

        #expect(superArrayDescMutable.subsumes(subArrayDescMutable2))
    }

    @Test
    func testWasmStructSubtypingRules() {
        let anyRefType = ILType.wasmAnyRef()
        let indexDesc = WasmArrayTypeDescription(
            elementType: .wasmi32, mutability: true, typeGroupIndex: 0)
        let indexRefType = ILType.wasmIndexRef(indexDesc, nullability: true)

        let superStructDescImmutable = WasmStructTypeDescription(
            fields: [WasmStructTypeDescription.Field(type: anyRefType, mutability: false)],
            typeGroupIndex: 1)
        let subStructDescImmutable = WasmStructTypeDescription(
            fields: [WasmStructTypeDescription.Field(type: indexRefType, mutability: false)],
            typeGroupIndex: 2, concreteHeapSupertype: superStructDescImmutable)
        let subStructDescMutable = WasmStructTypeDescription(
            fields: [WasmStructTypeDescription.Field(type: indexRefType, mutability: true)],
            typeGroupIndex: 3, concreteHeapSupertype: superStructDescImmutable)

        #expect(superStructDescImmutable.subsumes(subStructDescImmutable))
        #expect(!subStructDescImmutable.subsumes(superStructDescImmutable))
        #expect(superStructDescImmutable.subsumes(subStructDescMutable))
        #expect(!subStructDescMutable.subsumes(superStructDescImmutable))

        let superStructDescMulti = WasmStructTypeDescription(
            fields: [
                WasmStructTypeDescription.Field(type: anyRefType, mutability: false),
                WasmStructTypeDescription.Field(type: anyRefType, mutability: true),
            ],
            typeGroupIndex: 4)

        let subStructDescMultiWidthAndDepth = WasmStructTypeDescription(
            fields: [
                WasmStructTypeDescription.Field(type: indexRefType, mutability: true),
                WasmStructTypeDescription.Field(type: anyRefType, mutability: true),
                WasmStructTypeDescription.Field(type: .wasmi32, mutability: false),
            ],
            typeGroupIndex: 5, concreteHeapSupertype: superStructDescMulti)

        #expect(superStructDescMulti.subsumes(subStructDescMultiWidthAndDepth))
        #expect(!subStructDescMultiWidthAndDepth.subsumes(superStructDescMulti))
    }

    @Test func testWasmSignatureSubtypingRules() {
        let superSigDesc = WasmSignatureTypeDescription(
            signature: [] => [], typeGroupIndex: 0)
        let subSigDesc = WasmSignatureTypeDescription(
            signature: [] => [], typeGroupIndex: 1, concreteHeapSupertype: superSigDesc)

        #expect(superSigDesc.subsumes(subSigDesc))
        #expect(!subSigDesc.subsumes(superSigDesc))
    }

    @Test func testWasmTypeExtensionUnionTypeExtensionVsWasmTypeExtension() {
        let tagA = ILType.object(ofGroup: "WasmTag", withWasmType: WasmTagType([.wasmi32]))
        let tagB = ILType.object(ofGroup: "WasmTag", withWasmType: WasmTagType([.wasmi64]))
        // The union with itself doesn't modify the type.
        #expect(tagA.union(with: tagA) == tagA)
        // The union of two distinct wasm tags / WasmTypeExtensions leads to the removal of the wasm
        // type extension. To make the types easier to use (e.g. a catch might just want to search
        // for any wasm tag by doing `required(.object(ofGroup: "WasmTag"))` and expect to get a tag
        // with a valid type extension), if the WasmTypeExtension is removed, also any object group
        // is invalidated on the TypeExtension.
        let tagUnion = tagA.union(with: tagB)
        #expect(tagUnion.wasmType == nil)
        #expect(tagUnion.group == nil)
        // The intersection of two unequal tags always leads to an invalid type (as tags never
        // subsume each other).
        let tagIntersection = tagA.intersection(with: tagB)
        #expect(tagIntersection == .nothing)
    }

    @Test
    func testWasmAbstractHeapTypeSubsumptionRules() {
        let groupAny: [WasmAbstractHeapType] =
            [.WasmAny, .WasmEq, .WasmI31, .WasmStruct, .WasmArray, .WasmNone]
        let groupExtern: [WasmAbstractHeapType] = [.WasmExtern, .WasmNoExtern]
        let groupFunc: [WasmAbstractHeapType] = [.WasmFunc, .WasmNoFunc]
        let groupExn: [WasmAbstractHeapType] = [.WasmExn, .WasmNoExn]
        let allGroups = [groupAny, groupExtern, groupFunc, groupExn]
        let allTypes = allGroups.joined()
        // If this fails, please extend the arrays above with the newly added type(s).
        #expect(WasmAbstractHeapType.allCases.allSatisfy(allTypes.contains))

        // All types in the same type group share the same bottom type.
        #expect(groupAny.allSatisfy { $0.getBottom() == .WasmNone })
        #expect(groupExtern.allSatisfy { $0.getBottom() == .WasmNoExtern })
        #expect(groupFunc.allSatisfy { $0.getBottom() == .WasmNoFunc })
        #expect(groupExn.allSatisfy { $0.getBottom() == .WasmNoExn })

        // The union and intersection of of two unrelated types are nil.
        for groupA in allGroups {
            for groupB in allGroups where groupA != groupB {
                for typeA in groupA {
                    for typeB in groupB {
                        #expect(typeA.union(typeB) == nil, "a=\(typeA) b=\(typeB)")
                        #expect(typeA.intersection(typeB) == nil, "a=\(typeA) b=\(typeB)")
                    }
                }
            }
        }

        for type in allTypes {
            #expect(type.union(type) == type)
            #expect(type.union(type.getBottom()) == type)
            #expect(type.getBottom().union(type) == type)
            #expect(type.intersection(type) == type)
            #expect(type.intersection(type.getBottom()) == type.getBottom())
        }

        #expect(WasmAbstractHeapType.WasmAny.union(.WasmEq) == .WasmAny)
        #expect(WasmAbstractHeapType.WasmStruct.union(.WasmArray) == .WasmEq)
        #expect(WasmAbstractHeapType.WasmI31.union(.WasmArray) == .WasmEq)
        #expect(WasmAbstractHeapType.WasmArray.union(.WasmEq) == .WasmEq)
        #expect(WasmAbstractHeapType.WasmArray.intersection(.WasmStruct) == .WasmNone)
        #expect(WasmAbstractHeapType.WasmI31.intersection(.WasmStruct) == .WasmNone)
        #expect(WasmAbstractHeapType.WasmI31.intersection(.WasmEq) == .WasmI31)
        #expect(WasmAbstractHeapType.WasmAny.intersection(.WasmArray) == .WasmArray)

        // Tests on the whole ILType.
        for shared in [true, false] {
            let ref: (WasmAbstractHeapType) -> ILType = { t in
                ILType.wasmRef(t, shared: shared, nullability: false, )
            }
            let refNull = { t in ILType.wasmRef(t, shared: shared, nullability: true) }

            for type in allTypes {
                let refT = ref(type)
                let refNullT = refNull(type)
                #expect(refT.union(with: refNullT) == refNullT)
                #expect(refNullT.union(with: refT) == refNullT)
                #expect(refT.union(with: refT) == refT)
                #expect(refNullT.union(with: refNullT) == refNullT)
                #expect(refT.intersection(with: refT) == refT)
                #expect(refNullT.intersection(with: refNullT) == refNullT)
                #expect(refT.intersection(with: refNullT) == refT)
                #expect(refNullT.intersection(with: refT) == refT)
            }
            #expect(ref(.WasmAny).union(with: refNull(.WasmEq)) == refNull(.WasmAny))
            #expect(ref(.WasmStruct).union(with: ref(.WasmArray)) == ref(.WasmEq))
            // We should never do this for the type information of any Variable as .wasmGenericRef
            // cannot be encoded in the Wasm module and any instruction that leads to such a static type
            // is "broken". However, we will still need to allow this union type if we want to be able
            // to request a .required(.wasmGenericRef) for operations like WasmRefIsNull.
            #expect(ref(.WasmI31).union(with: refNull(.WasmExn)) == .wasmGenericRef)

            #expect(ref(.WasmAny).intersection(with: refNull(.WasmEq)) == ref(.WasmEq))
            #expect(
                refNull(.WasmI31).intersection(with: refNull(.WasmStruct)) == refNull(.WasmNone))
            // Note that `ref none` is a perfectly valid type in Wasm but such a reference can never be
            // constructed.
            #expect(ref(.WasmArray).intersection(with: refNull(.WasmStruct)) == ref(.WasmNone))
            #expect(refNull(.WasmArray).intersection(with: ref(.WasmAny)) == ref(.WasmArray))
        }

        let ref = { t, shared in ILType.wasmRef(t, shared: shared, nullability: false, ) }
        let refNull = { t, shared in ILType.wasmRef(t, shared: shared, nullability: true) }
        // Shared and unshared ref hierarchies are disjoint.
        for (lhsShared, rhsShared) in [(true, false), (false, true)] {
            for type in allTypes {
                #expect(ref(type, lhsShared).union(with: ref(type, rhsShared)) == .wasmGenericRef)
                #expect(
                    refNull(type, lhsShared).union(with: refNull(type, rhsShared))
                        == .wasmGenericRef)
            }
        }
    }

    @Test
    func testUnboundFunctionSubsumptionRules() {
        #expect(ILType.unboundFunction() == .unboundFunction())
        #expect(ILType.unboundFunction([] => .object()) != .unboundFunction())
        #expect(ILType.unboundFunction(receiver: .object()) != .unboundFunction())
        #expect(ILType.unboundFunction(receiver: .object()).Is(.unboundFunction()))
        #expect(!ILType.unboundFunction().Is(.unboundFunction(receiver: .object())))
        #expect(
            ILType.unboundFunction(receiver: .object()).Is(.unboundFunction(receiver: .jsAnything)))
        #expect(
            !ILType.unboundFunction(receiver: .jsAnything).Is(.unboundFunction(receiver: .object()))
        )

        let receiverNil = ILType.unboundFunction()
        let receiverObject = ILType.unboundFunction(receiver: .object())
        let receiverArray = ILType.unboundFunction(receiver: .object(ofGroup: "Array"))

        #expect(receiverArray.union(with: receiverObject) == receiverArray)
        #expect(receiverObject.union(with: receiverArray) == receiverArray)
        #expect(receiverNil.union(with: receiverObject) == receiverNil)
        #expect(receiverObject.union(with: receiverNil) == receiverNil)
        #expect(receiverObject.intersection(with: receiverArray) == receiverObject)
        #expect(receiverArray.intersection(with: receiverObject) == receiverObject)
        #expect(receiverNil.intersection(with: receiverObject) == receiverObject)
        #expect(receiverObject.intersection(with: receiverNil) == receiverObject)
    }

    private func runParameterizedIterableTests(
        factory: (ILType) -> ILType,
        baseInstance: ILType,
        descriptionPrefix: String
    ) {
        let intIterable = factory(.integer)
        let strIterable = factory(.string)
        let multiIterable = factory(.integer | .string)
        let objIterable = factory(.object(withProperties: ["foo"]))
        let objIterable2 = factory(.object(withProperties: ["foo", "bar"]))

        #expect(intIterable == factory(.integer))
        #expect(intIterable != strIterable)
        #expect(intIterable != baseInstance)
        #expect(baseInstance >= intIterable)
        #expect(multiIterable >= intIterable)
        #expect(multiIterable >= strIterable)
        #expect(!(intIterable >= baseInstance))
        #expect(!(intIterable >= strIterable))
        #expect(objIterable >= objIterable2)
        #expect(!(objIterable2 >= objIterable))

        #expect(intIterable | strIterable == multiIterable)
        #expect(baseInstance | strIterable == baseInstance)

        #expect(intIterable & strIterable == factory(.nothing))
        #expect(baseInstance & strIterable == strIterable)

        #expect(intIterable.canMerge(with: intIterable))
        #expect(!intIterable.canMerge(with: strIterable))
        #expect(baseInstance.canMerge(with: intIterable))
        #expect(intIterable.merging(with: intIterable) == intIterable)
        #expect(baseInstance.merging(with: intIterable) == intIterable)
        #expect(intIterable.merging(with: baseInstance) == intIterable)

        #expect(intIterable.description == "\(descriptionPrefix)<.integer>")
        #expect(multiIterable.description == "\(descriptionPrefix)<.integer | .string>")
    }

    @Test
    func testParameterizedIterables() {
        runParameterizedIterableTests(
            factory: { ILType.iterable(ofElementType: $0) },
            baseInstance: .iterable(),
            descriptionPrefix: ".iterable"
        )
    }

    @Test
    func testParameterizedAsyncIterables() {
        runParameterizedIterableTests(
            factory: { ILType.asyncIterable(ofElementType: $0) },
            baseInstance: .asyncIterable(),
            descriptionPrefix: ".asyncIterable"
        )

        // Subtyping with regular iterables
        let intAsyncIterable = ILType.asyncIterable(ofElementType: .integer)
        let intIterable = ILType.iterable(ofElementType: .integer)
        #expect(!intAsyncIterable.Is(intIterable))
        #expect(intIterable.Is(intAsyncIterable))
        #expect(!ILType.asyncIterable().Is(.iterable()))
        #expect(ILType.iterable().Is(.asyncIterable()))

        // Object group subtyping
        #expect(!ILType.jsAsyncGenerator.Is(.iterable()))
        #expect(ILType.jsGenerator.Is(.asyncIterable()))
    }

    @Test
    func testEnumerationTypeOperations() {
        let enumA = ILType.enumeration(ofName: "EnumA", withValues: ["A", "B"])
        let enumB = ILType.intEnumeration(ofName: "EnumB", withValues: [1, 2])
        let genericString = ILType.string
        let genericInt = ILType.integer

        #expect(enumA.isEnumeration)
        #expect(enumB.isEnumeration)
        #expect(!genericString.isEnumeration)
        #expect(!genericInt.isEnumeration)

        // Union: enumA | genericString should be genericString, so not an enumeration.
        #expect(!(enumA | genericString).isEnumeration)
        // Union: enumB | genericInt should be genericInt, so not an enumeration.
        #expect(!(enumB | genericInt).isEnumeration)
        // Union: enumA (string) | enumB (int) should be number | string, so not an enumeration.
        #expect(!(enumA | enumB).isEnumeration)

        // Intersection: enumA & genericString should be enumA, so it should be an enumeration.
        #expect((enumA & genericString).isEnumeration)
        // Intersection: enumB & genericInt should be enumB, so it should be an enumeration.
        #expect((enumB & genericInt).isEnumeration)

        // Intersection of string enum and int enum should be .nothing, which is not an enumeration.
        #expect(enumA & enumB == .nothing)
        #expect(!(enumA & enumB).isEnumeration)

        // Merging: enumA + object should maintain the isEnumeration flag.
        let obj = ILType.object(withProperties: ["foo"])
        #expect(!obj.isEnumeration)
        #expect((enumA + obj).isEnumeration)
        #expect((enumB + obj).isEnumeration)
    }

    let primitiveTypes: [ILType] = [
        .undefined, .integer, .float, .string, .boolean, .bigint, .regexp,
    ]

    static let wasmSigI32I64 = ILType.wasmTypeDef(
        description: WasmSignatureTypeDescription(
            signature: ([.wasmi32] => [.wasmi64]), typeGroupIndex: 0))
    static let wasmSigExternRefExternRef = ILType.wasmTypeDef(
        description: WasmSignatureTypeDescription(
            signature: ([.wasmExternRef()] => [.wasmExternRef()]), typeGroupIndex: 0))

    // A set of different types used by various tests.
    // TODO(cffsmith): Test and adjust types with a WasmTypeExtension.
    let typeSuite: [ILType] =
        [
            .undefined,
            .integer,
            .float,
            .string,
            .boolean,
            .bigint,
            .regexp,
            .iterable(),
            .iterable(ofElementType: .integer),
            .iterable(ofElementType: .string),
            .iterable(ofElementType: .integer | .string),
            .jsAnything,
            .nothing,
            .object(),
            .object(ofGroup: "A"),
            .object(ofGroup: "B"),
            .object(withProperties: ["foo"]),
            .object(withProperties: ["bar"]),
            .object(withProperties: ["baz"]),
            .object(withProperties: ["foo", "bar"]),
            .object(withProperties: ["foo", "baz"]),
            .object(withProperties: ["foo", "bar", "baz"]),
            .object(withMethods: ["m1"]),
            .object(withMethods: ["m2"]),
            .object(withMethods: ["m1", "m2"]),
            .object(withProperties: ["foo"], withMethods: ["m1"]),
            .object(withProperties: ["foo"], withMethods: ["m2"]),
            .object(withProperties: ["foo", "bar"], withMethods: ["m1"]),
            .object(withProperties: ["baz"], withMethods: ["m1"]),
            .object(withProperties: ["bar"], withMethods: ["m1", "m2"]),
            .object(withProperties: ["foo", "bar"], withMethods: ["m1", "m2"]),
            .object(withProperties: ["foo", "bar", "baz"], withMethods: ["m1", "m2"]),
            .object(ofGroup: "A", withProperties: ["foo"]),
            .object(ofGroup: "A", withProperties: ["foo", "bar"]),
            .object(ofGroup: "A", withMethods: ["m1"]),
            .object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1"]),
            .object(ofGroup: "A", withProperties: ["foo", "bar"], withMethods: ["m1"]),
            .object(ofGroup: "A", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"]),
            .object(ofGroup: "B", withProperties: ["foo"]),
            .object(ofGroup: "B", withProperties: ["foo", "bar"]),
            .object(ofGroup: "B", withMethods: ["m1"]),
            .object(ofGroup: "B", withProperties: ["foo"], withMethods: ["m1"]),
            .object(ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1"]),
            .object(ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"]),
            .function(),
            .function([.string] => .string),
            .function([.string] => .jsAnything),
            .function([.primitive] => .string),
            .function([.string, .string] => .jsAnything),
            .function([.integer] => .number),
            .function([.jsAnything...] => .jsAnything),
            .function([.integer, .string, .opt(.jsAnything)] => .float),
            .unboundFunction(),
            .unboundFunction([.string] => .string),
            .unboundFunction([.string] => .string, receiver: .object()),
            .unboundFunction([.string] => .jsAnything, receiver: .object()),
            .constructor(),
            .constructor([.string] => .string),
            .constructor([.string] => .jsAnything),
            .constructor([.primitive] => .string),
            .constructor([.string, .string] => .jsAnything),
            .constructor([.integer] => .number),
            .constructor([.jsAnything...] => .object()),
            .constructor([.integer, .string, .opt(.jsAnything)] => .object()),
            .functionAndConstructor(),
            .functionAndConstructor([.string] => .string),
            .functionAndConstructor([.string] => .jsAnything),
            .functionAndConstructor([.primitive] => .string),
            .functionAndConstructor([.string, .string] => .jsAnything),
            .functionAndConstructor([.integer] => .number),
            .functionAndConstructor([.jsAnything...] => .jsAnything),
            .functionAndConstructor([.integer, .string, .opt(.jsAnything)] => .object()),
            .number,
            .primitive,
            .string | .object(),
            .string | .object(withProperties: ["foo"]),
            .object(withProperties: ["foo"]) | .function(),
            .object(withProperties: ["foo"]) | .constructor([.rest(.jsAnything)] => .object()),
            .primitive | .object() | .function() | .constructor(),
            .string + .object(withProperties: ["foo", "bar"]),
            .integer + .object(withProperties: ["foo"], withMethods: ["m"]),
            .object(withProperties: ["foo", "bar"]) + .function([.integer] => .jsAnything),
            .object(ofGroup: "A", withProperties: ["foo", "bar"])
                + .constructor([.integer] => .jsAnything),
            .object(withMethods: ["m1"])
                + .functionAndConstructor([.integer, .boolean] => .jsAnything),
            .object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1"])
                + .functionAndConstructor([.integer, .boolean] => .jsAnything),
            // Wasm types
            .wasmAnything,
            .wasmi32,
            .wasmf32,
            .wasmi64,
            .wasmf64,
            wasmSigI32I64,
            wasmSigExternRefExternRef,
            .wasmFunctionDef(wasmSigI32I64),
            .wasmFunctionDef(wasmSigExternRefExternRef),
            .wasmMemory(limits: Limits(min: 10)),
            .wasmMemory(limits: Limits(min: 10, max: 20)),
        ] + ILType.allNullableAbstractWasmRefTypes()
}
