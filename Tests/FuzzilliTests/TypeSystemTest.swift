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

class TypeSystemTests: XCTestCase {

    func testSubsumptionReflexivity() {
        for t in typeSuite {
            XCTAssert(t >= t, "\(t) >= \(t)")
        }
    }

    func testSubsumptionTransitivity() {
        for t1 in typeSuite {
            for t2 in typeSuite {
                for t3 in typeSuite {
                    if t1 >= t2 && t2 >= t3 {
                        XCTAssert(t1 >= t3, "\(t1) >= \(t2) && \(t2) >= \(t3) implies \(t1) => \(t3)")
                    }
                }
            }
        }
    }

    func testSubsumptionAntisymmetry() {
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 && t2 >= t1 {
                    XCTAssert(t1 == t2, "\(t1) >= \(t2) && \(t2) >= \(t1) implies \(t1) == \(t2)")
                } else if t1 >= t2 {
                    XCTAssertFalse(t2 >= t1, "\(t1) >= \(t2) && \(t1) != \(t2) implies \(t2) !>= \(t1)")
                }
            }
        }
    }

    func testTypeEquality() {
        // Do some ad-hoc tests
        XCTAssert(.integer == .integer)
        XCTAssert(.integer != .float)

        XCTAssert(.object() == .object())
        XCTAssert(.object(withProperties: ["foo"]) == .object(withProperties: ["foo"]))
        XCTAssert(.object(withProperties: ["foo"]) != .object(withProperties: ["bar"]))
        XCTAssert(.object(withProperties: ["foo"]) != .object())
        XCTAssert(.object(withProperties: ["x"]) != .object(withMethods: ["x"]))
        XCTAssert(.object(withMethods: ["m1"]) == .object(withMethods: ["m1"]))
        XCTAssert(.object(withMethods: ["m1"]) != .object(withMethods: ["m2"]))
        XCTAssert(.object(withMethods: ["m1"]) != .object())

        XCTAssert(.function() == .function())
        XCTAssert(.function([.integer, .rest(.integer)] => .undefined) == .function([.integer, .rest(.integer)] => .undefined))
        XCTAssert(.function([.integer, .rest(.integer)] => .undefined) != .function())

        // Test equality properties for all types in the test suite
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 == t2 {
                    XCTAssert(t1 >= t2, "\(t1) == \(t2) implies \(t1) >= \(t2)")
                    XCTAssert(t2 >= t1, "\(t1) == \(t2) implies \(t2) >= \(t1)")
                } else {
                    XCTAssertFalse(t1 >= t2 && t2 >= t1, "\(t1) != \(t2) implies !(\(t1) >= \(t2) && \(t2) >= \(t1))")
                }
            }
        }
    }

    func testSubsumptionOperators() {
        // Test that the >= and <= operators and the .subsumes method
        // behave as expected for all types in the test suite
        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 {
                    XCTAssert(t1.subsumes(t2))
                    XCTAssert(t2 <= t1, "\(t1) >= \(t2) implies \(t2) <= \(t1)")
                } else if t2 >= t1 {
                    XCTAssert(t2.subsumes(t1))
                    XCTAssert(t1 <= t2, "\(t2) >= \(t1) implies \(t1) <= \(t2)")
                } else {
                    XCTAssertFalse(t1.subsumes(t2) || t2.subsumes(t1))
                }
            }
        }
    }

    func testIsAndMayBe() {
        // An A Is a B iff A <= B.
        // E.g. a object with a property "foo" is an object
        XCTAssert(ILType.object(withProperties: ["foo"]).Is(.object()))
        // and an integer is a number
        XCTAssert(ILType.integer.Is(.number))
        // but an integer is not an object
        XCTAssertFalse(ILType.integer.Is(.object()))
        // and is also not a boolean
        XCTAssertFalse(ILType.integer.Is(.boolean))
        // and a boolean is not a number
        XCTAssertFalse(ILType.boolean.Is(.number))
        // but an integer is a number
        XCTAssert(ILType.integer.Is(.number))
        XCTAssertFalse(ILType.integer.MayNotBe(.number))
        // even though a number may not be an integer (it could also be a float)
        XCTAssert(ILType.number.MayNotBe(.integer))
        // A function f1 is a function f2 if the signatures are compatible, such that f1
        // can be used when a function f2 is required (i.e. if the call to the functions
        // assumes the function has the signature of f2).
        // See also the signature subsumption test for more complicated examples.
        XCTAssert(ILType.function([.anything] => .integer).Is(.function([.integer] => .number)))
        XCTAssertFalse(ILType.function([.integer] => .integer).Is(.function([.anything] => .number)))
        XCTAssertFalse(ILType.function([.anything] => .number).Is(.function([.anything] => .integer)))

        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 {
                    XCTAssert(t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    XCTAssertFalse(t2.MayNotBe(t1), "\(t1) >= \(t2) <=> !((\(t2)).MayNotBe(\(t1)))")
                } else {
                    XCTAssertFalse(t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    XCTAssert(t2.MayNotBe(t1), "\(t1) >= \(t2) <=> !((\(t2)).MayNotBe(\(t1)))")
                }

                if t2.Is(t1) {
                    XCTAssertFalse(t2.MayNotBe(t1), "(\(t2)).Is(\(t1)) <=> !((\(t2)).MayNotBe(\(t1)))")
                    XCTAssert(t1 >= t2, "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                } else {
                    XCTAssertFalse(t1 >= t2, "\(t1) >= \(t2) <=> (\(t2)).Is(\(t1))")
                    XCTAssert(t2.MayNotBe(t1), "(\(t2)).Is(\(t1)) <=> !((\(t2)).MayNotBe(\(t1)))")
                }
            }
        }

        // An A MayBe a B iff the intersection between A and B is non-empty.
        // E.g. a .primitive MayBe a .number because the intersection of the two is non-empty (is .number).
        XCTAssert(ILType.primitive.MayBe(.number))
        // and a .number MayBe a .integer or a .float
        XCTAssert(ILType.number.MayBe(.integer))
        XCTAssert(ILType.number.MayBe(.float))
        // but a number can never be a .boolean or a .object etc.
        XCTAssertFalse(ILType.number.MayBe(.boolean))
        XCTAssertFalse(ILType.number.MayBe(.object()))
        // The union of two types MayBe eiher of the two types. Phrased differently,
        // if something is either a number or a boolean, then it may be either of these.
        XCTAssert((.integer | .boolean).MayBe(.integer))
        XCTAssert((.integer | .boolean).MayBe(.boolean))
        // But it may still not be a string.
        XCTAssertFalse((.integer | .boolean).MayBe(.string))
        // Less obviously, an object MayBe an object with a property "foo"
        XCTAssert(ILType.object().MayBe(.object(withProperties: ["foo"])))
        // and a function that takes an integer may be a function that also takes anything as first parameter.
        // The way to think about is is (probably) that a function taking .anything may still be called
        // with a .integer as argument. However, from a practical point of view the function that takes .integer
        // may in fact also be fine with a different argument.
        XCTAssert(ILType.function([.integer] => .anything).MayBe(.function([.anything] => .anything)))
        // But (at least from a theoretical point-of-view) a function taking a .integer is definitely not a function
        // that takes (only) a string as first parameter.
        XCTAssertFalse(ILType.function([.integer] => .anything).MayBe(.function([.string] => .anything)))

        XCTAssert((ILType.integer | ILType.boolean).MayBe(ILType.integer | ILType.string))
        XCTAssertFalse((ILType.integer + ILType.object()).MayBe(ILType.string + ILType.object()))

        // An object with properties .a and .b Is definitely an object with property .a. However, an
        // object with property .a MayBe an object with properties .a and .b.
        let o1 = ILType.object(withProperties: ["a", "b"], withMethods: ["m", "n"])
        let o2 = ILType.object(withProperties: ["a"], withMethods: ["m"])
        XCTAssert(o1.Is(o2))
        XCTAssertFalse(o2.Is(o1))
        XCTAssert(o1.MayBe(o2))
        XCTAssert(o2.MayBe(o2))

        for t1 in typeSuite {
            for t2 in typeSuite {
                // Below tests don't work for .nothing because that
                // is also the intersection of unrelated types.
                if t1 == .nothing || t2 == .nothing {
                    continue
                }

                // If t2 is a t1 then it clearly may be a t1.
                if t2.Is(t1) {
                    XCTAssert(t2.MayBe(t1), "(\(t2)).Is(a: \(t1)) => (\(t2)).MayBe(\(t1))")
                }

                if t1 & t2 != .nothing {
                    XCTAssert(t2.MayBe(t1), "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(\(t1))")
                } else {
                    XCTAssertFalse(t2.MayBe(t1), "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(\(t1))")
                }

                XCTAssert((t1 | t2).MayBe(t1), "A union type may be one of its parts")
                XCTAssert((t1 | t2).MayBe(t2), "A union type may be one of its parts")

                if t2.MayBe(t1) {
                    XCTAssert(t1 & t2 != .nothing, "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(\(t1))")
                } else {
                    XCTAssert(t1 & t2 == .nothing, "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(\(t1))")
                }
            }
        }

        // .anything MayBe anything, but definitely is only .anything
        for t in typeSuite where t != .anything && t != .nothing {
            XCTAssert(ILType.anything.MayBe(t), ".anything MayBe \(t)")
            XCTAssertFalse(ILType.anything.Is(t), ".anything Is not definitely \(t)")
        }
    }

    func testPrimitiveTypeSubsumption() {
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                if t1 == t2 {
                    XCTAssert(t1 >= t2 && t2 >= t1)
                } else {
                    XCTAssertFalse(t1 >= t2 || t2 >= t1)
                }
            }
        }
    }

    func testAnythingAndNothingSubsumption() {
        for t in typeSuite {
            // .anything subsumes every other type and no other type subsumes .anything
            XCTAssert(.anything >= t)
            if t != .anything {
                XCTAssertFalse(t >= .anything)
            }

            // .nothing is subsumed by all types and subsumes no other type but itself
            XCTAssert(t >= .nothing)
            if t != .nothing {
                XCTAssertFalse(.nothing >= t)
            }
        }
    }

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
                    XCTAssert(t1.properties.isSubset(of: t2.properties))
                    XCTAssert(t1.methods.isSubset(of: t2.methods))
                }

                // The opposite direction holds if the base types are equal and if the groups are compatible.
                // E.g. string objects never subsume objects, but can subsume other string objects if the
                // properties and methods are a subset.
                if t1.baseType == t2.baseType && (t1.group == nil || t1.group == t2.group) {
                    if t1.properties.isSubset(of: t2.properties) && t1.methods.isSubset(of: t2.methods) {
                        XCTAssert(t1 >= t2, "\(t1) >= \(t2)")
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
            let fooBarObj = ILType.object(withProperties: fooBarProperties, withMethods: fooBarMethods)
            let fooBazObj = ILType.object(withProperties: fooBazProperties, withMethods: fooBazMethods)

            // Foo, Bar, Baz, FooBar, and FooBaz objects are all objects, but not every object is a Foo, Bar, Baz, FooBar, or FooBaz object.
            XCTAssert(object >= fooObj)
            XCTAssertFalse(fooObj >= object)
            XCTAssert(object >= barObj)
            XCTAssertFalse(barObj >= object)
            XCTAssert(object >= bazObj)
            XCTAssertFalse(bazObj >= object)
            XCTAssert(object >= fooBarObj)
            XCTAssertFalse(fooBarObj >= object)
            XCTAssert(object >= fooBazObj)
            XCTAssertFalse(fooBazObj >= object)

            // Order of property and methods names does not matter.
            XCTAssert(fooBarObj >= ILType.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            XCTAssert(fooBarObj >= ILType.object(withProperties: fooBarProperties.reversed(), withMethods: fooBarMethods.reversed()))
            XCTAssert(fooBarObj == ILType.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            XCTAssert(fooBarObj == ILType.object(withProperties: fooBarProperties.reversed(), withMethods: fooBarMethods.reversed()))

            // No subsumption relationship between Foo, Bar, and Baz objects
            XCTAssertFalse(fooObj >= barObj)
            XCTAssertFalse(fooObj >= bazObj)
            XCTAssertFalse(barObj >= fooObj)
            XCTAssertFalse(barObj >= bazObj)
            XCTAssertFalse(bazObj >= fooObj)
            XCTAssertFalse(bazObj >= barObj)

            // ... However, their unions are still objects
            XCTAssert(object >= fooObj | barObj)
            XCTAssert(object >= fooObj | bazObj)
            XCTAssert(object >= barObj | bazObj)
            XCTAssert(object >= fooObj | barObj | bazObj)

            // ... And their merged type is a Foo, Bar, and Baz object
            XCTAssert(fooObj >= fooObj + barObj + bazObj)
            XCTAssert(barObj >= fooObj + barObj + bazObj)
            XCTAssert(bazObj >= fooObj + barObj + bazObj)

            // ... Moreover, Foo objects merged with Bar objects yields FooBar objects. Same for Foo and Baz.
            XCTAssert(fooBarObj == fooObj + barObj)
            XCTAssert(fooBazObj == fooObj + bazObj)

            // The intersection of FooBar and Foo or Bar objects again yield FooBar objects as they are a subtype. Same for FooBaz.
            XCTAssert(fooBarObj & fooObj == fooBarObj)
            XCTAssert(fooBarObj & barObj == fooBarObj)
            XCTAssert(fooBazObj & fooObj == fooBazObj)
            XCTAssert(fooBazObj & bazObj == fooBazObj)

            // ... However, the other intersections are empty.
            XCTAssert(fooObj & barObj == .nothing)
            XCTAssert(fooObj & bazObj == .nothing)
            XCTAssert(barObj & bazObj == .nothing)
            XCTAssert(barObj & fooBazObj == .nothing)
            XCTAssert(bazObj & fooBarObj == .nothing)
            XCTAssert(fooBarObj & fooBazObj == .nothing)

            // FooBar objects are Foo objects but not every Foo object is a FooBar object. Same for FooBar and Bar objects.
            XCTAssert(fooObj >= fooBarObj)
            XCTAssertFalse(fooBarObj >= fooObj)
            XCTAssert(barObj >= fooBarObj)
            XCTAssertFalse(fooBarObj >= barObj)

            // Same as above, but for FooBaz, Foo, and Baz objects.
            XCTAssert(fooObj >= fooBazObj)
            XCTAssertFalse(fooBazObj >= fooObj)
            XCTAssert(bazObj >= fooBazObj)
            XCTAssertFalse(fooBazObj >= bazObj)

            // FooBar objects are not Baz objects and FooBaz objects are not Bar objects.
            XCTAssertFalse(bazObj >= fooBarObj)
            XCTAssertFalse(barObj >= fooBazObj)

            // There is no subsumption relationship between FooBar and FooBaz objects
            XCTAssertFalse(fooBarObj >= fooBazObj)
            XCTAssertFalse(fooBazObj >= fooBarObj)

            // ... However, their union is still a Foo object
            XCTAssert(fooObj >= fooBarObj | fooBazObj)

            // ... And their merged type is a FooBar and a FooBaz object
            XCTAssert(fooBarObj >= fooBarObj + fooBazObj)
            XCTAssert(fooBazObj >= fooBarObj + fooBazObj)

            //... in particular, it is a FooBarBaz object.
            let fooBarBazProperties = fooProperties + barProperties + bazProperties
            let fooBarBazMethods = fooMethods + barMethods + bazMethods
            XCTAssert(fooObj + barObj + bazObj == fooBarObj + fooBazObj)
            XCTAssert(fooBarObj + fooBazObj == .object(withProperties: fooBarBazProperties, withMethods: fooBarBazMethods))
        }
    }

    func testObjectInspection() {
        let aObj = ILType.object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1", "m2"])
        let bObj = ILType.object(ofGroup: "B", withProperties: ["foo", "bar"])

        XCTAssert(aObj.properties.contains("foo"))
        XCTAssert(bObj.properties.contains("bar"))
        XCTAssert(bObj.properties.contains("foo"))

        XCTAssert(aObj.numProperties == 1)
        XCTAssert(aObj.numMethods == 2)
        XCTAssert(bObj.numProperties == 2)
        XCTAssert(bObj.numMethods == 0)

        // We can be more precise.
        XCTAssert(aObj.properties == ["foo"])
        XCTAssert(bObj.properties == ["foo", "bar"])

        XCTAssert(aObj.methods.contains("m1"))
        XCTAssert(aObj.methods.contains("m2"))

        XCTAssert(aObj.methods == ["m1", "m2"])
        XCTAssert(bObj.methods == [])

        XCTAssert(aObj.group == "A")
        XCTAssert(bObj.group == "B")

        let fooBarObj = ILType.object(withProperties: ["foo", "bar"])
        let fooBazObj = ILType.object(withProperties: ["foo", "baz"])
        XCTAssert((fooBarObj | fooBazObj).properties == ["foo"])
        XCTAssert((fooBarObj + fooBazObj).properties == ["foo", "bar", "baz"])
        XCTAssert((fooBarObj & fooBazObj).properties == [])

        // Unions of objects with non-objects do not have any definite properties or methods.
        XCTAssert((aObj | .integer).properties == [])
        XCTAssert((aObj | .integer).methods == [])

        // However, merging preserves the properties and methods as expected.
        XCTAssert((aObj + .integer).properties == ["foo"])
        XCTAssert((aObj + .integer).methods == ["m1", "m2"])
    }

    func testPropertyTypeTransitions() {
        let object = ILType.object(ofGroup: "A")
        let fooObj = ILType.object(ofGroup: "A", withProperties: ["foo"])
        let barObj = ILType.object(ofGroup: "A", withProperties: ["bar"])
        let bazObj = ILType.object(ofGroup: "A", withProperties: ["baz"])
        let fooBarObj = ILType.object(ofGroup: "A", withProperties: ["foo", "bar"])
        let fooBazObj = ILType.object(ofGroup: "A", withProperties: ["foo", "baz"])

        XCTAssertEqual(object.adding(property: "foo"), fooObj)
        XCTAssertEqual(fooObj.adding(property: "bar"), fooBarObj)
        XCTAssertEqual(barObj.adding(property: "foo"), fooBarObj)
        XCTAssertEqual(fooObj.adding(property: "baz"), fooBazObj)
        XCTAssertEqual(bazObj.adding(property: "foo"), fooBazObj)

        XCTAssertEqual(fooBarObj.removing(property: "baz"), fooBarObj)
        XCTAssertEqual(fooBarObj.removing(property: "foo"), barObj)
        XCTAssertEqual(barObj.removing(property: "bar"), object)
    }

    func testMethodTypeTransitions() {
        let object = ILType.object(ofGroup: "A")
        let fooObj = ILType.object(ofGroup: "A", withMethods: ["foo"])
        let barObj = ILType.object(ofGroup: "A", withMethods: ["bar"])
        let bazObj = ILType.object(ofGroup: "A", withMethods: ["baz"])
        let fooBarObj = ILType.object(ofGroup: "A", withMethods: ["foo", "bar"])
        let fooBazObj = ILType.object(ofGroup: "A", withMethods: ["foo", "baz"])

        XCTAssertEqual(object.adding(method: "foo"), fooObj)
        XCTAssertEqual(fooObj.adding(method: "bar"), fooBarObj)
        XCTAssertEqual(barObj.adding(method: "foo"), fooBarObj)
        XCTAssertEqual(fooObj.adding(method: "baz"), fooBazObj)
        XCTAssertEqual(bazObj.adding(method: "foo"), fooBazObj)

        XCTAssertEqual(fooBarObj.removing(method: "baz"), fooBarObj)
        XCTAssertEqual(fooBarObj.removing(method: "foo"), barObj)
        XCTAssertEqual(barObj.removing(method: "bar"), object)
    }

    func testCallableTypeSubsumption() {
        let signature1 = [.integer, .string] => .anything
        let signature2 = [.boolean, .rest(.anything)] => .object()

        // Repeat the below tests for functions, constructors, and function constructors (function and constructor at the same time)
        // We call something that is a function or a constructor (or both) a "callable".
        let anyCallables = [ILType.function(), ILType.constructor(), ILType.functionAndConstructor()]
        let callable1s = [ILType.function(signature1), ILType.constructor(signature1), ILType.functionAndConstructor(signature1)]
        let callable2s = [ILType.function(signature2), ILType.constructor(signature2), ILType.functionAndConstructor(signature2)]

        for i in 0..<3 {
            let anyCallable = anyCallables[i]
            let callable1 = callable1s[i]
            let callable2 = callable2s[i]

            // Both callable1 and callable2 are callables
            XCTAssert(anyCallable >= callable1)
            XCTAssert(anyCallable >= callable2)

            // Not every callable is a callable1 or a callable2
            XCTAssertFalse(callable1 >= anyCallable)
            XCTAssertFalse(callable2 >= anyCallable)

            // Callable1 is not a callable2 and vice versa
            XCTAssertFalse(callable1 >= callable2)
            XCTAssertFalse(callable2 >= callable1)

            // Callable1 and callable2 cannot be merged (because they have different signatures)
            XCTAssertFalse(callable1.canMerge(with: callable2))
            XCTAssertFalse(callable2.canMerge(with: callable1))

            // ... But they can be unioned, and the union is still a callable
            XCTAssert(anyCallable >= callable1 | callable2)
        }

        // See testSignatureSubsumption for more complicated examples related specifically to signatures.
    }

    func testObjectGroupSubsumption() {
        let aObj = ILType.object(ofGroup: "A", withProperties: ["foo"])
        let bObj = ILType.object(ofGroup: "B", withProperties: ["foo", "bar"])

        // Both aObj and bObj are objects.
        XCTAssert(.object() >= aObj)
        XCTAssert(.object() >= bObj)

        // aObj is an object with a property "foo",
        XCTAssert(.object(withProperties: ["foo"]) >= aObj)
        // and an object of group A,
        XCTAssert(.object(ofGroup: "A") >= aObj)
        // but is not an object of group B,
        XCTAssertFalse(.object(ofGroup: "B") >= aObj)
        // and not every object with a property "foo" is an object of group A.
        XCTAssertFalse(aObj >= .object(withProperties: ["foo"]))

        // Same as above.
        XCTAssert(.object(withProperties: ["bar"]) >= bObj)
        XCTAssert(.object(withProperties: ["foo"]) >= bObj)
        XCTAssert(.object(withProperties: ["foo", "bar"]) >= bObj)
        XCTAssert(.object(ofGroup: "B") >= bObj)
        XCTAssertFalse(.object(ofGroup: "A") >= bObj)
        XCTAssertFalse(bObj >= .object(withProperties: ["bar"]))
        XCTAssertFalse(bObj >= .object(withProperties: ["foo"]))
        XCTAssertFalse(bObj >= .object(withProperties: ["foo", "bar"]))

        // No relationship between different groups.
        XCTAssertFalse(bObj == aObj || bObj >= aObj || aObj >= bObj)
    }

    func testWasmGlobalSubsumption() {
        let wasmi32Mutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: false)
        let wasmi64Mutable = WasmGlobalType(valueType:ILType.wasmi64, isMutable: true)

        let ILTypeGlobalI32Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalI64Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable)

        XCTAssert(ILTypeGlobalI32Mutable >= ILTypeGlobalI32Mutable)
        // Types which don't have equal WasmTypeExtension don't subsume.
        XCTAssertFalse(ILTypeGlobalI32NonMutable >= ILTypeGlobalI32Mutable)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalI32NonMutable)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalI64Mutable)
        XCTAssertFalse(ILTypeGlobalI64Mutable >= ILTypeGlobalI32Mutable)
        XCTAssertFalse(ILTypeGlobalI32NonMutable >= ILTypeGlobalI64Mutable)

        let ILTypeGlobalI32MutableNoGroup: ILType = ILType.object(withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32MutableNoProperty: ILType = ILType.object(ofGroup: "WasmGlobal", withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32MutableNoWasmType: ILType = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"])
        let ILTypeGlobalOnlyGroup: ILType = ILType.object(ofGroup: "WasmGlobal")
        let ILTypeGlobalOnlyProperty: ILType = ILType.object(withProperties: ["value"])

        // If the WasmGlobalTypes are equal, the other subsumption rules apply.
        XCTAssert(ILTypeGlobalI32MutableNoGroup >= ILTypeGlobalI32Mutable)
        XCTAssert(ILTypeGlobalI32MutableNoProperty >= ILTypeGlobalI32Mutable)
        XCTAssert(ILTypeGlobalI32MutableNoWasmType >= ILTypeGlobalI32Mutable)
        XCTAssert(ILTypeGlobalOnlyGroup >= ILTypeGlobalI32Mutable)
        XCTAssert(ILTypeGlobalOnlyProperty >= ILTypeGlobalI32Mutable)
        // But not the other way around: the WasmGlobalType matters.
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoGroup)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoProperty)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalI32MutableNoWasmType)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalOnlyGroup)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeGlobalOnlyProperty)

        // Groups should match.
        let ILTypeWrongGroup = ILType.object(ofGroup: "SomeOtherGroup", withProperties: ["value"], withWasmType: wasmi32Mutable)
        XCTAssertFalse(ILTypeWrongGroup >= ILTypeGlobalI32Mutable)
        XCTAssertFalse(ILTypeGlobalI32Mutable >= ILTypeWrongGroup)
    }

    func testWasmGlobalUnion() {
        let wasmi32Mutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: false)
        let wasmf32Mutable = WasmGlobalType(valueType:ILType.wasmf32, isMutable: true)

        let ILTypeGlobalI32Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalF32Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf32Mutable)

        XCTAssertEqual(ILTypeGlobalI32Mutable | ILTypeGlobalI32Mutable, ILTypeGlobalI32Mutable)

        // Types with not equal WasmTypeExtension don't have a WasmTypeExtension in their union.
        let unionMutabilityDiff = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"])
        XCTAssertEqual(ILTypeGlobalI32Mutable | ILTypeGlobalI32NonMutable, unionMutabilityDiff)
        // Invariant: the union of two types subsumes both types.
        XCTAssert(unionMutabilityDiff >= ILTypeGlobalI32Mutable)
        XCTAssert(unionMutabilityDiff >= ILTypeGlobalI32NonMutable)

        let unionValueTypeDiff = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"])
        XCTAssertEqual(ILTypeGlobalI32Mutable | ILTypeGlobalF32Mutable, unionValueTypeDiff)
        XCTAssert(unionValueTypeDiff >= ILTypeGlobalI32Mutable)
        XCTAssert(unionValueTypeDiff >= ILTypeGlobalI32NonMutable)

        XCTAssertEqual(ILTypeGlobalI32Mutable | .object(ofGroup: "WasmGlobal"), .object(ofGroup: "WasmGlobal"))
        XCTAssert(.object(ofGroup: "WasmGlobal") >= ILTypeGlobalI32Mutable)
        XCTAssertEqual(ILTypeGlobalI32Mutable | .object(withProperties: ["value"]), .object(withProperties: ["value"]))
        XCTAssert(.object(withProperties: ["value"]) >= ILTypeGlobalI32Mutable)
    }

    func testWasmGlobalIntersection() {
        let wasmi64Mutable = WasmGlobalType(valueType:ILType.wasmi64, isMutable: true)
        let wasmi64NonMutable = WasmGlobalType(valueType:ILType.wasmi64, isMutable: false)
        let wasmf64Mutable = WasmGlobalType(valueType:ILType.wasmf64, isMutable: true)

        let ILTypeGlobalI64Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable)
        let ILTypeGlobalI64NonMutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64NonMutable)
        let ILTypeGlobalF64Mutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf64Mutable)

        XCTAssertEqual(ILTypeGlobalI64Mutable & ILTypeGlobalI64Mutable, ILTypeGlobalI64Mutable)
        XCTAssertEqual(ILTypeGlobalI64Mutable & ILTypeGlobalI64NonMutable, .nothing)
        XCTAssertEqual(ILTypeGlobalI64Mutable & ILTypeGlobalF64Mutable, .nothing)
        XCTAssertEqual(ILTypeGlobalI64Mutable & .object(withProperties: ["value"]), .nothing)
        XCTAssertEqual((ILTypeGlobalI64Mutable & ILType.object(withWasmType: wasmi64Mutable)), ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi64Mutable)) 
    }

    func testWasmGlobalIsAndMayBe() {
        let wasmi32Mutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: true)
        let wasmi32NonMutable = WasmGlobalType(valueType:ILType.wasmi32, isMutable: false)
        let wasmf64Mutable = WasmGlobalType(valueType:ILType.wasmf64, isMutable: true)

        let ILTypeGlobalI32Mutable: ILType = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32Mutable)
        let ILTypeGlobalI32NonMutable = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmi32NonMutable)
        let ILTypeGlobalF64Mutable: ILType = ILType.object(ofGroup: "WasmGlobal", withProperties: ["value"], withWasmType: wasmf64Mutable)

        XCTAssert(ILTypeGlobalI32Mutable.Is(.object(ofGroup: "WasmGlobal")))
        XCTAssert(ILTypeGlobalI32Mutable.Is(.object(withProperties: ["value"])))
        XCTAssert(ILTypeGlobalI32Mutable.Is(.object(withWasmType: wasmi32Mutable)))
        XCTAssertFalse(ILTypeGlobalI32Mutable.Is(ILTypeGlobalI32NonMutable))
        XCTAssertFalse(ILTypeGlobalI32NonMutable.Is(ILTypeGlobalI32Mutable))
        XCTAssertFalse(ILTypeGlobalI32Mutable.Is(ILTypeGlobalF64Mutable))
        XCTAssertFalse(ILTypeGlobalF64Mutable.Is(ILTypeGlobalI32Mutable))

        XCTAssertFalse(ILTypeGlobalI32Mutable.MayBe(.object(ofGroup: "WasmGlobal")))
        XCTAssertFalse(ILTypeGlobalI32Mutable.MayBe(.object(withProperties: ["value"])))
        XCTAssert(ILTypeGlobalI32Mutable.MayBe(.object(withWasmType: wasmi32Mutable)))
        XCTAssert(ILTypeGlobalI32Mutable.MayBe(ILTypeGlobalI32Mutable))
        XCTAssertFalse(ILTypeGlobalI32Mutable.MayBe(ILTypeGlobalI32NonMutable))
        XCTAssertFalse(ILTypeGlobalI32NonMutable.MayBe(ILTypeGlobalI32Mutable))
    }

    func testTypeUnioning() {
        // Basic union tests
        XCTAssert(.integer | .float >= .integer)
        XCTAssert(.integer | .float >= .float)

        XCTAssert(.integer | .float >= .integer | .float)
        XCTAssert(.integer | .float == .integer | .float)

        XCTAssert(.integer | .float | .string >= .integer)
        XCTAssert(.integer | .float | .string >= .float)
        XCTAssert(.integer | .float | .string >= .string)
        XCTAssert(.integer | .float | .string >= .integer | .float)
        XCTAssert(.integer | .float | .string >= .integer | .string)
        XCTAssert(.integer | .float | .string >= .float   | .string)
        XCTAssert(.integer | .float | .string >= .integer | .float | .string)
        XCTAssert(.integer | .float | .string == .integer | .float | .string)

        // Test special union cases
        XCTAssertEqual(.anything | .integer, .anything)
        XCTAssertEqual(.anything | .integer, .anything)
        XCTAssertEqual(.anything | .nothing, .anything)
        XCTAssertEqual(.nothing | .nothing, .nothing)
        XCTAssertEqual(.nothing | .anything, .anything)
        XCTAssertEqual(.nothing | .integer, .integer)

        // Test subsumption of unions of related types.
        let objectUnion = .object(withProperties: ["a"]) | .object(withProperties: ["b"])
        // The union is still definitely an object
        XCTAssert(.object() >= objectUnion)

        let objUnionA = .object(withProperties: ["a", "b"]) | .object(withProperties: ["a", "c"])
        // The union type is still an object with a property "a"
        XCTAssert(.object() >= objUnionA)
        XCTAssert(.object(withProperties: ["a"]) >= objUnionA)

        // Unioning primitive types a and b does not suddenly produce something that is a c
        // for an unrelated primitive type c. The same is true for other types, but is more
        // complicated to test there, mainly due to merged types. See below.
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                for t3 in primitiveTypes {
                    if t3 != t1 && t3 != t2 {
                        XCTAssertFalse(t1 | t2 >= t3, "\(t3) != \(t1) && \(t3) != \(t2) => \(t1) | \(t2) !>= \(t3)")
                    }
                }
            }
        }


        for t1 in typeSuite {
            XCTAssert(t1 | t1 == t1, "\(t1) | \(t1) (\(t1 | t1)) == \(t1)")

            for t2 in typeSuite {
                // Unioning is symmetric
                XCTAssert(t1 | t2 == t2 | t1)

                let union1 = t1 | t2

                // Union of a and b must subsume a and b: a | b >= a && a | b >= b
                XCTAssert(union1 >= t1, "\(t1) | \(t2) (\(union1)) >= \(t1)")
                XCTAssert(union1 >= t2, "\(t1) | \(t2) (\(union1)) >= \(t2)")

                // One additional guaruantee of the union operation is that it preserves properties common to
                // both input type. E.g. unioning something that is definitely an object with something else
                // that is also definitely an object again produces something that definitely is an object.
                // Test this here loosely by checking the base types.
                if t1.baseType == t2.baseType {
                    XCTAssert(union1.baseType == t1.baseType)
                }

                for t3 in typeSuite {
                    let union2 = union1 | t3
                    XCTAssert(union2 >= t1, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t1)")
                    XCTAssert(union2 >= t2, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t2)")
                    XCTAssert(union2 >= t3, "\(t1) | \(t2) | \(t3) (\(union2)) >= \(t3)")
                }
            }
        }
    }

    func testTypeIntersection() {
        // The intersection of .string and .object() is empty (as is the case for all unrelated types)
        XCTAssert(ILType.string & ILType.object() == .nothing)
        // the same is true for all "unrelated" types, in particular the primitive types
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                if t1 != t2 {
                    XCTAssert(t1 & t2 == .nothing, "\(t1) & \(t2) (\(t1 & t2)) == .nothing")
                }
            }
        }
        // however, the intersection of StringObject and .string is again a StringObject
        let stringObj = ILType.string + ILType.object()
        XCTAssertEqual(stringObj & .string, stringObj)
        // in the same way as the intersection of .number (.integer | .float) and .integer is .integer (the smaller type)
        XCTAssertEqual(ILType.number & ILType.integer, ILType.integer)
        // but the intersection of a StringObject and an IntegerObject is empty
        let integerObj = ILType.integer + ILType.object()
        XCTAssertEqual(stringObj & integerObj, .nothing)

        // There are some interesting edge cases here.
        // E.g. the intersection of .function() and .function() + .constructor() is the latter (because that's already a subtype)
        let funcCtor = ILType.function() + ILType.constructor()
        XCTAssertEqual(funcCtor & .function(), funcCtor)
        XCTAssertEqual(.function() & funcCtor, funcCtor)
        // and the intersection of .function() and .function([.string] => .float) is also the latter (for the same reason)
        let sig = [.string] => .float
        XCTAssertEqual(ILType.function() & .function(sig), .function(sig))
        // as such, the intersection of .function([.string] => .float) and .function() + .constructor() now becomes
        // .function([.string] => .float) + .constructor([.string] => .float)
        XCTAssertEqual(ILType.function(sig) & funcCtor, .constructor(sig) + .function(sig))
        // Maybe a bit less intuitively, the intersection of two functions with different signatures can also exist.
        // In the following example, the more general signature of the two functions is the intersection as that's what
        // both functions "have in common".
        XCTAssertEqual(ILType.function([.anything] => .integer) & .function([.integer] => .anything), .function([.anything] => .integer))
        XCTAssertEqual(ILType.function([.anything] => .anything) & .function([.integer] => .anything), .function([.anything] => .anything))
        // In this example, the parameter type is widened and the return type is narrowed.
        XCTAssertEqual(ILType.function([.integer] => .integer) & .function([.anything] => .anything), .function([.anything] => .integer))
        // However, here the return types are incompatible
        XCTAssertEqual(ILType.function([.integer] => .integer) & .function([.integer] => .string), .nothing)

        // Now test the basic invariants of intersections for all types in the type suite.
        for t1 in typeSuite {
            XCTAssert(t1 & t1 == t1, "\(t1) & \(t1) (\(t1 | t1)) == \(t1)")

            for t2 in typeSuite {
                // Intersecting is symmetric
                XCTAssert(t1 & t2 == t2 & t1, "\(t1) & \(t2) (\(t2 & t2)) == \(t2) & \(t1) (\(t2 & t1))")

                let intersection = t1 & t2

                // The intersection of a and b must be subsumed by both a and b: a >= a & b && b >= a & b
                XCTAssert(t1 >= intersection, "\(t1) >= \(t1) & \(t2) (\(intersection))")
                XCTAssert(t2 >= intersection, "\(t2) >= \(t1) & \(t2) (\(intersection))")

                // If one of the two inputs subsumes the other, then the result will be the subsumed type.
                if t1 >= t2 {
                    XCTAssert(t1 & t2 == t2, "\(t1) >= \(t2) => \(t1) & \(t2) (\(t1 & t2)) == \(t2)")
                }
            }
        }
    }

    func testTypeMerging() {
        let obj = ILType.object(withProperties: ["foo"])
        let str = ILType.string
        let strObj = obj + str

        // A string object is both a string and an object.
        XCTAssert(str >= strObj)
        XCTAssert(obj >= strObj)

        // But is not suddenly e.g. an integer.
        XCTAssertFalse(.integer >= strObj)
        // Or an integer object
        XCTAssertFalse(.integer + .object() >= strObj)

        // And not every string or every object is a string object.
        XCTAssertFalse(strObj >= str)
        XCTAssertFalse(strObj >= obj)

        // Test the above (as good as possible) for all types in the test suite.
        for t1 in typeSuite {
            for t2 in typeSuite {
                guard t1.canMerge(with: t2) else { continue }

                // Merging is symmetric
                XCTAssert(t1 + t2 == t2 + t1)

                let merged = t1 + t2

                // Merging t1 and t2 yields a type that is both a t1 and a t2
                XCTAssert(t1 >= merged, "\(t1) >= \(t1) + \(t2) (\(merged))")
                XCTAssert(t2 >= merged, "\(t2) >= \(t1) + \(t2) (\(merged))")

                for t3 in typeSuite {
                    if t3 >= t1 || t3 >= t2 {
                        // If t1 or t2 are a t3, than the merged type t1 + t2 must also be a t3.
                        XCTAssert(t3 >= merged, "\(t3) >= \(t1) || \(t3) >= \(t2) implies \(t3) >= \(t1) + \(t2) (\(merged))")
                    }

                    guard t1.canMerge(with: t3) && t2.canMerge(with: t3) else { continue }
                    if t1 >= t2 {
                        XCTAssert(t1 + t3 >= t2 + t3, "\(t1) >= \(t2) implies \(t1) + \(t3) >= \(t2) + \(t3)")
                    }
                }
            }
        }

        // Test that type merging is possible for the expected types.
        for t1 in typeSuite {
            for t2 in typeSuite {
                // Union types cannot be merged
                if t1.isUnion || t2.isUnion {
                    XCTAssertFalse(t1.canMerge(with: t2))
                }

                // .nothing cannot be merged
                else if t1 == .nothing || t2 == .nothing {
                    XCTAssertFalse(t1.canMerge(with: t2))
                }

                // Callables with different signatures cannot be merged
                else if t1.isCallable && t2.isCallable && t1.signature != nil && t2.signature != nil && t1.signature != t2.signature {
                    XCTAssertFalse(t1.canMerge(with: t2))
                }

                // Objects of different groups cannot be merged
                else if t1.group != nil && t2.group != nil && t1.group != t2.group {
                    XCTAssertFalse(t1.canMerge(with: t2))
                }

                // Everything else can be merged
                else {
                    XCTAssert(t1.canMerge(with: t2))
                    // Merging is symmetric
                    XCTAssert(t2.canMerge(with: t1))
                }
            }
        }
    }

    func testSignatureTypes() {
        let sig1 = [.anything, .string, .integer, .opt(.integer), .opt(.float)] => .undefined
        XCTAssertFalse(sig1.parameters[0].isOptionalParameter)
        XCTAssertFalse(sig1.parameters[1].isOptionalParameter)
        XCTAssertFalse(sig1.parameters[2].isOptionalParameter)
        XCTAssert(sig1.parameters[3].isOptionalParameter)
        XCTAssert(sig1.parameters[4].isOptionalParameter)

        let sig2 = [.integer, .opt(.integer), .rest(.float)] => .undefined
        XCTAssertFalse(sig2.parameters[0].isOptionalParameter)
        XCTAssertFalse(sig2.parameters[0].isRestParameter)
        XCTAssert(sig2.parameters[1].isOptionalParameter)
        XCTAssertFalse(sig2.parameters[1].isRestParameter)
        XCTAssertFalse(sig2.parameters[2].isOptionalParameter)
        XCTAssert(sig2.parameters[2].isRestParameter)
    }

    func testSignatureSubsumption() {
        // For sig1 to subsume sig2, sig1's parameters must be subsumed by their
        // counterparts in sig2.
        // In other words, if we need a function that accepts an integer as first
        // parameter, then we're fine receiving a function that accepts anything
        // (or e.g. a number) as first parameter.
        XCTAssert([.integer] => .undefined >= [.anything] => .undefined)
        XCTAssert([.integer, .string] => .undefined >= [.number, .string] => .undefined)
        XCTAssert([.integer, .string] => .undefined >= [.integer, .primitive] => .undefined)
        // but not one that requires a string.
        XCTAssertFalse([.integer] => .undefined >= [.string] => .undefined)
        XCTAssertFalse([.integer, .integer] => .undefined >= [.integer, .string] => .undefined)
        // Or, phrased differentley still, a function that accepts anything as first
        // parameter is a function that accepts an integer as first parameter.
        XCTAssert(ILType.function([.anything] => .undefined).Is(.function([.integer] => .undefined)))
        // However, the other direction does not hold: if we want a function that
        // accepts anything as first parameter, we cannot use a function that
        // requires an integer as first parameter instead.
        XCTAssertFalse([.anything] => .undefined >= [.integer] => .undefined)

        // Signatures with more parameters subsume signatures with fewer parameters
        // because the additional parameters are simply ignored.
        XCTAssert([.integer] => .undefined >= [] => .undefined)
        XCTAssert([.anything, .anything] => .undefined >= [.anything] => .undefined)
        // But the other way doesn't work: if we want a function that takes no parameters,
        // we cannot use one that requires parameters instead.
        XCTAssertFalse([] => .undefined >= [.anything] => .undefined)

        // A signature with rest parameters is subsumed by a signature with no rest parameters
        // if either there are no parameters that will "turn into" rest parameters, or if
        // they all have the correct type.
        XCTAssert([] => .undefined >= [.anything...] => .undefined)
        XCTAssert([.anything] => .undefined >= [.anything...] => .undefined)
        XCTAssert([.integer, .number] => .undefined >= [.anything...] => .undefined)
        XCTAssert([.integer, .integer] => .undefined >= [.integer...] => .undefined)
        XCTAssertFalse([.integer, .boolean] => .undefined >= [.integer...] => .undefined)
        XCTAssert([.integer, .boolean] => .undefined >= [.primitive...] => .undefined)
        // A signature with rest parameters subsumes a signature with no rest parameters
        // only if the subsumed function expects no parameters at the position of the
        // rest parameter (because it can be omitted by the caller).
        XCTAssert([.anything...] => .undefined >= [] => .undefined)
        XCTAssertFalse([.anything...] => .undefined >= [.anything] => .undefined)
        // If both signatures have rest parameters, then these must be compatible.
        XCTAssert([.anything...] => .undefined >= [.anything...] => .undefined)
        XCTAssert([.integer...] => .undefined >= [.anything...] => .undefined)
        XCTAssert([.integer, .integer...] => .undefined >= [.anything...] => .undefined)
        XCTAssertFalse([.integer, .boolean...] => .undefined >= [.number...] => .undefined)
        XCTAssertFalse([.anything...] => .undefined >= [.integer...] => .undefined)
        XCTAssertFalse([.integer, .anything...] => .undefined >= [.integer...] => .undefined)

        // Optional parameters behave mostlu identical to rest parameters, except that they
        // are only expanded once.
        XCTAssert([] => .undefined >= [.opt(.integer), .opt(.float)] => .undefined)
        XCTAssert([.opt(.integer)] => .undefined >= [.opt(.anything)] => .undefined)
        XCTAssert([.opt(.integer)] => .undefined >= [] => .undefined)
        XCTAssert([.string, .opt(.integer)] => .undefined >= [.string, .anything...] => .undefined)
        XCTAssert([.integer] => .undefined >= [.opt(.integer)] => .undefined)
        XCTAssertFalse([.integer, .integer] => .undefined >= [.opt(.integer), .opt(.string)] => .undefined)
        XCTAssertFalse([.opt(.integer)] => .undefined >= [.integer] => .undefined)
        XCTAssertFalse([.opt(.integer)] => .undefined >= [.string...] => .undefined)
        XCTAssertFalse([.string...] => .undefined >= [.opt(.integer)] => .undefined)

        // Test return value subsumption: sig1 subsumes sig2 if sig1's return value subsumes that
        // of sig2. For example, a function returning .integer is a function returning a .number.
        XCTAssert([] => .number >= [] => .integer)
        XCTAssert([] => .anything >= [] => .integer)
        XCTAssertFalse([] => .integer >= [] => .number)
        XCTAssertFalse([] => .integer >= [] => .anything)

        // Check that the unknown function signature is subsumed by most other signatures.
        XCTAssert(Signature.forUnknownFunction <= [] => .anything)
        XCTAssert(Signature.forUnknownFunction <= [.anything] => .anything)
        XCTAssert(Signature.forUnknownFunction <= [.integer, .string] => .anything)
    }

    func testTypeDescriptions() {
        // Test primitive types
        XCTAssertEqual(ILType.undefined.description, ".undefined")
        XCTAssertEqual(ILType.integer.description, ".integer")
        XCTAssertEqual(ILType.bigint.description, ".bigint")
        XCTAssertEqual(ILType.float.description, ".float")
        XCTAssertEqual(ILType.string.description, ".string")
        XCTAssertEqual(ILType.regexp.description, ".regexp")
        XCTAssertEqual(ILType.boolean.description, ".boolean")
        XCTAssertEqual(ILType.bigint.description, ".bigint")
        XCTAssertEqual(ILType.iterable.description, ".iterable")

        // Test object types
        XCTAssertEqual(ILType.object().description, ".object()")
        XCTAssertEqual(ILType.object(withProperties: ["foo"]).description, ".object(withProperties: [\"foo\"])")
        XCTAssertEqual(ILType.object(withMethods: ["m"]).description, ".object(withMethods: [\"m\"])")

        // Property and method order is not defined
        let fooBarObj = ILType.object(withProperties: ["foo", "bar"])
        XCTAssert(fooBarObj.description == ".object(withProperties: [\"foo\", \"bar\"])" || fooBarObj.description == ".object(withProperties: [\"bar\", \"foo\"])")

        let objWithMethods = ILType.object(withMethods: ["m1", "m2"])
        XCTAssert(objWithMethods.description == ".object(withMethods: [\"m1\", \"m2\"])" || objWithMethods.description == ".object(withMethods: [\"m2\", \"m1\"])")

        let fooBarObjWithMethod = ILType.object(withProperties: ["foo", "bar"], withMethods: ["m"])
        XCTAssert(fooBarObjWithMethod.description == ".object(withProperties: [\"foo\", \"bar\"], withMethods: [\"m\"])" || fooBarObjWithMethod.description == ".object(withProperties: [\"bar\", \"foo\"], withMethods: [\"m\"])")

        // Test function and constructor types
        XCTAssertEqual(ILType.function().description, ".function()")
        XCTAssertEqual(ILType.function([.rest(.anything)] => .anything).description, ".function([.anything...] => .anything)")
        XCTAssertEqual(ILType.function([.float, .opt(.integer)] => .object()).description, ".function([.float, .opt(.integer)] => .object())")
        XCTAssertEqual(ILType.function([.integer, .boolean, .rest(.anything)] => .object()).description, ".function([.integer, .boolean, .anything...] => .object())")

        XCTAssertEqual(ILType.constructor().description, ".constructor()")
        XCTAssertEqual(ILType.constructor([.rest(.anything)] => .anything).description, ".constructor([.anything...] => .anything)")
        XCTAssertEqual(ILType.constructor([.integer, .boolean, .rest(.anything)] => .object()).description, ".constructor([.integer, .boolean, .anything...] => .object())")

        XCTAssertEqual(ILType.functionAndConstructor().description, ".function() + .constructor()")
        XCTAssertEqual(ILType.functionAndConstructor([.rest(.anything)] => .anything).description, ".function([.anything...] => .anything) + .constructor([.anything...] => .anything)")
        XCTAssertEqual(ILType.functionAndConstructor([.integer, .boolean, .rest(.anything)] => .object()).description, ".function([.integer, .boolean, .anything...] => .object()) + .constructor([.integer, .boolean, .anything...] => .object())")

        // Test other "well-known" types
        XCTAssertEqual(ILType.nothing.description, ".nothing")
        XCTAssertEqual(ILType.anything.description, ".anything")

        XCTAssertEqual(ILType.primitive.description, ".primitive")
        XCTAssertEqual(ILType.number.description, ".number")

        // Test union types
        let strOrInt = ILType.integer | ILType.string
        XCTAssertEqual(strOrInt.description, ".integer | .string")

        let strOrIntOrObj = ILType.integer | ILType.string | ILType.object(withProperties: ["foo"])
        // Note: information about properties and methods is discarded when unioning with non-object types.
        XCTAssertEqual(strOrIntOrObj.description, ".integer | .string | .object()")

        let objOrFunc = ILType.object() | ILType.function([.integer, .integer] => .integer)
        // Note: information about signatures is discarded when unioning callable types.
        XCTAssertEqual(objOrFunc.description, ".object() | .function()")

        // Test merged types
        let strObj = ILType.string + ILType.object(withProperties: ["foo"])
        XCTAssertEqual(strObj.description, ".string + .object(withProperties: [\"foo\"])")

        let funcObj = ILType.object(withProperties: ["foo"], withMethods: ["m"]) + ILType.function([.integer, .rest(.anything)] => .boolean)
        XCTAssertEqual(funcObj.description, ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.integer, .anything...] => .boolean)")

        let funcConstrObj = ILType.object(withProperties: ["foo"], withMethods: ["m"]) + ILType.functionAndConstructor([.integer, .rest(.anything)] => .boolean)
        XCTAssertEqual(funcConstrObj.description, ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.integer, .anything...] => .boolean) + .constructor([.integer, .anything...] => .boolean)")

        // Test union of merged types
        let strObjOrFuncObj = (ILType.string + ILType.object(withProperties: ["foo"])) | (ILType.function([.rest(.anything)] => .float) + ILType.object(withProperties: ["foo"]))
        XCTAssertEqual(strObjOrFuncObj.description, ".string + .object(withProperties: [\"foo\"]) | .object(withProperties: [\"foo\"]) + .function()")
    }

    func testWasmSubsumptionRules() {
        let wasmTypes: [ILType] = [.wasmi32, .wasmi64, .wasmf32, .wasmf64, .wasmFuncRef, .wasmExternRef]
        // Make sure that no Wasm type is subsumed by (JS-)anything.
        for t in wasmTypes {
            XCTAssertEqual(t <= .anything, false)
        }
    }

    let primitiveTypes: [ILType] = [.undefined, .integer, .float, .string, .boolean, .bigint, .regexp]

    // A set of different types used by various tests.
    // TODO(cffsmith): Test and adjust types with a WasmTypeExtension.
    let typeSuite: [ILType] = [.undefined,
                               .integer,
                               .float,
                               .string,
                               .boolean,
                               .bigint,
                               .regexp,
                               .iterable,
                               .anything,
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
                               .function([.string] => .anything),
                               .function([.primitive] => .string),
                               .function([.string, .string] => .anything),
                               .function([.integer] => .number),
                               .function([.anything...] => .anything),
                               .function([.integer, .string, .opt(.anything)] => .float),
                               .constructor(),
                               .constructor([.string] => .string),
                               .constructor([.string] => .anything),
                               .constructor([.primitive] => .string),
                               .constructor([.string, .string] => .anything),
                               .constructor([.integer] => .number),
                               .constructor([.anything...] => .object()),
                               .constructor([.integer, .string, .opt(.anything)] => .object()),
                               .functionAndConstructor(),
                               .functionAndConstructor([.string] => .string),
                               .functionAndConstructor([.string] => .anything),
                               .functionAndConstructor([.primitive] => .string),
                               .functionAndConstructor([.string, .string] => .anything),
                               .functionAndConstructor([.integer] => .number),
                               .functionAndConstructor([.anything...] => .anything),
                               .functionAndConstructor([.integer, .string, .opt(.anything)] => .object()),
                               .number,
                               .primitive,
                               .string | .object(),
                               .string | .object(withProperties: ["foo"]),
                               .object(withProperties: ["foo"]) | .function(),
                               .object(withProperties: ["foo"]) | .constructor([.rest(.anything)] => .object()),
                               .primitive | .object() | .function() | .constructor(),
                               .string + .object(withProperties: ["foo", "bar"]),
                               .integer + .object(withProperties: ["foo"], withMethods: ["m"]),
                               .object(withProperties: ["foo", "bar"]) + .function([.integer] => .anything),
                               .object(ofGroup: "A", withProperties: ["foo", "bar"]) + .constructor([.integer] => .anything),
                               .object(withMethods: ["m1"]) + .functionAndConstructor([.integer, .boolean] => .anything),
                               .object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1"]) + .functionAndConstructor([.integer, .boolean] => .anything),
    ]
}
