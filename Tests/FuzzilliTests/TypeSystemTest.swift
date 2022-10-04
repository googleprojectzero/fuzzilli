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
        XCTAssert(.function([.plain(.integer), .rest(.integer)] => .undefined) == .function([.plain(.integer), .rest(.integer)] => .undefined))
        XCTAssert(.function([.plain(.integer), .rest(.integer)] => .undefined) != .function())

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
        XCTAssert(Type.object(withProperties: ["foo"]).Is(.object()))
        // but an integer is not an object
        XCTAssertFalse(Type.integer.Is(.object()))
        // and is also not a boolean
        XCTAssertFalse(Type.integer.Is(.boolean))
        // and a boolean is not a number
        XCTAssertFalse(Type.boolean.Is(.number))
        // but an integer is a number
        XCTAssert(Type.integer.Is(.number))

        for t1 in typeSuite {
            for t2 in typeSuite {
                if t1 >= t2 {
                    XCTAssert(t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(a: \(t1))")
                } else {
                    XCTAssertFalse(t2.Is(t1), "\(t1) >= \(t2) <=> (\(t2)).Is(a: \(t1))")
                }

                if t2.Is(t1) {
                    XCTAssert(t1 >= t2, "\(t1) >= \(t2) <=> (\(t2)).Is(a: \(t1))")
                } else {
                    XCTAssertFalse(t1 >= t2, "\(t1) >= \(t2) <=> (\(t2)).Is(a: \(t1))")
                }
            }
        }

        // An A MayBe a B iff the intersection between A and B is non-empty.
        // E.g. a .primitive MayBe a .number because the intersection of the two is non-empty (is .number).
        XCTAssert(Type.primitive.MayBe(.number))
        // and a .number MayBe a .integer or a .float
        XCTAssert(Type.number.MayBe(.integer))
        XCTAssert(Type.number.MayBe(.float))
        // but a number can never be a .boolean or a .object etc.
        XCTAssertFalse(Type.number.MayBe(.boolean))
        XCTAssertFalse(Type.number.MayBe(.object()))

        for t1 in typeSuite {
            for t2 in typeSuite {
                // Below tests don't work for .nothing because that
                // is also the intersection of unrelated types.
                if t1 == .nothing || t2 == .nothing {
                    continue
                }

                // If t2 is a t1 then it clearly may be a t1.
                if t2.Is(t1) {
                    XCTAssert(t2.MayBe(t1), "(\(t2)).Is(a: \(t1)) => (\(t2)).MayBe(a: \(t1))")
                }

                if t1 & t2 != .nothing {
                    XCTAssert(t2.MayBe(t1), "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(a: \(t1))")
                } else {
                    XCTAssertFalse(t2.MayBe(t1), "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(a: \(t1))")
                }

                if t2.MayBe(t1) {
                    XCTAssert(t1 & t2 != .nothing, "\(t1) & \(t2) != .nothing <=> (\(t2)).MayBe(a: \(t1))")
                } else {
                    XCTAssert(t1 & t2 == .nothing, "\(t1) & \(t2) == .nothing <=> !(\(t2)).MayBe(a: \(t1))")
                }
            }
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

    func testUnknownTypeSubsumption() {
        // The .unknown type only subsumes itself and .nothing (like a primitive type).
        for t in typeSuite {
            if t != .unknown && t != .nothing {
                XCTAssertFalse(.unknown >= t, "\(t) != .unknown implies .unknown !>= \(t)")
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
            let object = Type.object()
            let fooObj = Type.object(withProperties: fooProperties, withMethods: fooMethods)
            let barObj = Type.object(withProperties: barProperties, withMethods: barMethods)
            let bazObj = Type.object(withProperties: bazProperties, withMethods: bazMethods)
            let fooBarObj = Type.object(withProperties: fooBarProperties, withMethods: fooBarMethods)
            let fooBazObj = Type.object(withProperties: fooBazProperties, withMethods: fooBazMethods)

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
            XCTAssert(fooBarObj >= Type.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            XCTAssert(fooBarObj >= Type.object(withProperties: fooBarProperties.reversed(), withMethods: fooBarMethods.reversed()))
            XCTAssert(fooBarObj == Type.object(withProperties: fooBarProperties, withMethods: fooBarMethods))
            XCTAssert(fooBarObj == Type.object(withProperties: fooBarProperties.reversed(), withMethods: fooBarMethods.reversed()))

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
        let aObj = Type.object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1", "m2"])
        let bObj = Type.object(ofGroup: "B", withProperties: ["foo", "bar"])

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

        let fooBarObj = Type.object(withProperties: ["foo", "bar"])
        let fooBazObj = Type.object(withProperties: ["foo", "baz"])
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
        let object = Type.object(ofGroup: "A")
        let fooObj = Type.object(ofGroup: "A", withProperties: ["foo"])
        let barObj = Type.object(ofGroup: "A", withProperties: ["bar"])
        let bazObj = Type.object(ofGroup: "A", withProperties: ["baz"])
        let fooBarObj = Type.object(ofGroup: "A", withProperties: ["foo", "bar"])
        let fooBazObj = Type.object(ofGroup: "A", withProperties: ["foo", "baz"])

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
        let object = Type.object(ofGroup: "A")
        let fooObj = Type.object(ofGroup: "A", withMethods: ["foo"])
        let barObj = Type.object(ofGroup: "A", withMethods: ["bar"])
        let bazObj = Type.object(ofGroup: "A", withMethods: ["baz"])
        let fooBarObj = Type.object(ofGroup: "A", withMethods: ["foo", "bar"])
        let fooBazObj = Type.object(ofGroup: "A", withMethods: ["foo", "baz"])

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
        let signature1 = [.plain(.integer), .plain(.string)] => .unknown
        let signature2 = [.plain(.boolean), .rest(.anything)] => .object()

        // Repeat the below tests for functions, constructors, and function constructors (function and constructor at the same time)
        // We call something that is a function or a constructor (or both) a "callable".
        let anyCallables = [Type.function(), Type.constructor(), Type.functionAndConstructor()]
        let callable1s = [Type.function(signature1), Type.constructor(signature1), Type.functionAndConstructor(signature1)]
        let callable2s = [Type.function(signature2), Type.constructor(signature2), Type.functionAndConstructor(signature2)]

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
    }

    func testObjectGroupSubsumption() {
        let aObj = Type.object(ofGroup: "A", withProperties: ["foo"])
        let bObj = Type.object(ofGroup: "B", withProperties: ["foo", "bar"])

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


    func testGeneralization() {
        let aObj = Type.object(ofGroup: "A", withProperties: ["bar"], withMethods: ["m2"])
        XCTAssertEqual(.object(ofGroup: "A"), aObj.generalize())

        let f = Type.function([.plain(.anything), .plain(.anything)] => .integer)
        XCTAssertEqual(.function(), f.generalize())

        for t in typeSuite {
            XCTAssert(t.Is(t.generalize()))
        }
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
        XCTAssert(Type.string & Type.object() == .nothing)
        // the same is true for all "unrelated" types, in particular the primitive types
        for t1 in primitiveTypes {
            for t2 in primitiveTypes {
                if t1 != t2 {
                    XCTAssert(t1 & t2 == .nothing, "\(t1) & \(t2) (\(t1 & t2)) == .nothing")
                }
            }
        }
        // however, the intersection of StringObject and .string is again a StringObject
        let stringObj = Type.string + Type.object()
        XCTAssert(stringObj & .string == stringObj)
        // in the same way as the intersection of .number (.integer | .float) and .integer is .integer (the smaller type)
        XCTAssert(Type.number & Type.integer == Type.integer)
        // but the intersection of a StringObject and an IntegerObject is empty
        let integerObj = Type.integer + Type.object()
        XCTAssert(stringObj & integerObj == .nothing)

        // There are some interesting edge cases here.
        // E.g. the intersection of .function() and .function() + .constructor() is the latter (because that's already a subtype)
        let funcCtor = Type.function() + Type.constructor()
        XCTAssert(funcCtor & .function() == funcCtor)
        // on the other hand, the intersection of .function() and .function([.string] => .float) is also the latter (for the same reason)
        let sig = [.plain(.string)] => .float
        XCTAssert(Type.function() & .function(sig) == .function(sig))
        // as such, the intersection of .function([.string] => .float) and .function() + .constructor() now becomes
        // .function([.string] => .float) + .constructor([.string] => .float)
        XCTAssert(Type.function(sig) & funcCtor == .constructor(sig) + .function(sig))

        // Now test the basic invariants of intersections for all types in the type suite.
        for t1 in typeSuite {
            XCTAssert(t1 & t1 == t1, "\(t1) & \(t1) (\(t1 | t1)) == \(t1)")

            for t2 in typeSuite {
                // Intersecting is symmetric
                XCTAssert(t1 & t2 == t2 & t1)

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
        let obj = Type.object(withProperties: ["foo"])
        let str = Type.string
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

                // .unknown cannot be merged
                else if t1 == .unknown || t2 == .unknown {
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
        let sig1 = [.plain(.anything), .plain(.string), .plain(.integer), .opt(.integer), .opt(.float)] => .undefined
        XCTAssertFalse(sig1.parameters[0].isOptional)
        XCTAssertFalse(sig1.parameters[1].isOptional)
        XCTAssertFalse(sig1.parameters[2].isOptional)
        XCTAssert(sig1.parameters[3].isOptional)
        XCTAssert(sig1.parameters[4].isOptional)

        let sig2 = [.plain(.integer), .opt(.integer), .rest(.float)] => .undefined
        XCTAssertFalse(sig2.parameters[0].isOptional)
        XCTAssertFalse(sig2.parameters[0].isRestParam)
        XCTAssert(sig2.parameters[1].isOptional)
        XCTAssertFalse(sig2.parameters[1].isRestParam)
        XCTAssertFalse(sig2.parameters[2].isOptional)
        XCTAssert(sig2.parameters[2].isRestParam)
    }

    func testTypeDescriptions() {
        // Test primitive types
        XCTAssertEqual(Type.undefined.description, ".undefined")
        XCTAssertEqual(Type.integer.description, ".integer")
        XCTAssertEqual(Type.float.description, ".float")
        XCTAssertEqual(Type.string.description, ".string")
        XCTAssertEqual(Type.boolean.description, ".boolean")
        XCTAssertEqual(Type.unknown.description, ".unknown")
        XCTAssertEqual(Type.bigint.description, ".bigint")
        XCTAssertEqual(Type.regexp.description, ".regexp")
        XCTAssertEqual(Type.iterable.description, ".iterable")

        // Test object types
        XCTAssertEqual(Type.object().description, ".object()")
        XCTAssertEqual(Type.object(withProperties: ["foo"]).description, ".object(withProperties: [\"foo\"])")
        XCTAssertEqual(Type.object(withMethods: ["m"]).description, ".object(withMethods: [\"m\"])")

        // Property and method order is not defined
        let fooBarObj = Type.object(withProperties: ["foo", "bar"])
        XCTAssert(fooBarObj.description == ".object(withProperties: [\"foo\", \"bar\"])" || fooBarObj.description == ".object(withProperties: [\"bar\", \"foo\"])")

        let objWithMethods = Type.object(withMethods: ["m1", "m2"])
        XCTAssert(objWithMethods.description == ".object(withMethods: [\"m1\", \"m2\"])" || objWithMethods.description == ".object(withMethods: [\"m2\", \"m1\"])")

        let fooBarObjWithMethod = Type.object(withProperties: ["foo", "bar"], withMethods: ["m"])
        XCTAssert(fooBarObjWithMethod.description == ".object(withProperties: [\"foo\", \"bar\"], withMethods: [\"m\"])" || fooBarObjWithMethod.description == ".object(withProperties: [\"bar\", \"foo\"], withMethods: [\"m\"])")

        // Test function and constructor types
        XCTAssertEqual(Type.function().description, ".function()")
        XCTAssertEqual(Type.function([.rest(.anything)] => .unknown).description, ".function([.rest(.anything)] => .unknown)")
        XCTAssertEqual(Type.function([.plain(.float), .opt(.integer)] => .object()).description, ".function([.plain(.float), .opt(.integer)] => .object())")
        XCTAssertEqual(Type.function([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object()).description, ".function([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object())")

        XCTAssertEqual(Type.constructor().description, ".constructor()")
        XCTAssertEqual(Type.constructor([.rest(.anything)] => .unknown).description, ".constructor([.rest(.anything)] => .unknown)")
        XCTAssertEqual(Type.constructor([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object()).description, ".constructor([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object())")

        XCTAssertEqual(Type.functionAndConstructor().description, ".function() + .constructor()")
        XCTAssertEqual(Type.functionAndConstructor([.rest(.anything)] => .unknown).description, ".function([.rest(.anything)] => .unknown) + .constructor([.rest(.anything)] => .unknown)")
        XCTAssertEqual(Type.functionAndConstructor([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object()).description, ".function([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object()) + .constructor([.plain(.integer), .plain(.boolean), .rest(.anything)] => .object())")

        // Test other "well-known" types
        XCTAssertEqual(Type.nothing.description, ".nothing")
        XCTAssertEqual(Type.anything.description, ".anything")

        XCTAssertEqual(Type.primitive.description, ".primitive")
        XCTAssertEqual(Type.number.description, ".number")

        // Test union types
        let strOrInt = Type.integer | Type.string
        XCTAssertEqual(strOrInt.description, ".integer | .string")

        let strOrIntOrObj = Type.integer | Type.string | Type.object(withProperties: ["foo"])
        // Note: information about properties and methods is discarded when unioning with non-object types.
        XCTAssertEqual(strOrIntOrObj.description, ".integer | .string | .object()")

        let objOrFunc = Type.object() | Type.function([.plain(.integer), .plain(.integer)] => .integer)
        // Note: information about signatures is discarded when unioning callable types.
        XCTAssertEqual(objOrFunc.description, ".object() | .function()")

        // Test merged types
        let strObj = Type.string + Type.object(withProperties: ["foo"])
        XCTAssertEqual(strObj.description, ".string + .object(withProperties: [\"foo\"])")

        let funcObj = Type.object(withProperties: ["foo"], withMethods: ["m"]) + Type.function([.plain(.integer), .rest(.anything)] => .boolean)
        XCTAssertEqual(funcObj.description, ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.plain(.integer), .rest(.anything)] => .boolean)")

        let funcConstrObj = Type.object(withProperties: ["foo"], withMethods: ["m"]) + Type.functionAndConstructor([.plain(.integer), .rest(.anything)] => .boolean)
        XCTAssertEqual(funcConstrObj.description, ".object(withProperties: [\"foo\"], withMethods: [\"m\"]) + .function([.plain(.integer), .rest(.anything)] => .boolean) + .constructor([.plain(.integer), .rest(.anything)] => .boolean)")

        // Test union of merged types
        let strObjOrFuncObj = (Type.string + Type.object(withProperties: ["foo"])) | (Type.function([.rest(.anything)] => .float) + Type.object(withProperties: ["foo"]))
        XCTAssertEqual(strObjOrFuncObj.description, ".string + .object(withProperties: [\"foo\"]) | .object(withProperties: [\"foo\"]) + .function()")
    }

    func testTypeSerialization() {
        for t in typeSuite {
            var proto = t.asProtobuf()
            let data = try! proto.serializedData()
            proto = try! Fuzzilli_Protobuf_Type(serializedData: data)
            let tCopy = try! Type(from: proto)
            XCTAssertEqual(t, tCopy)
        }
    }

    let primitiveTypes: [Type] = [.undefined, .integer, .float, .string, .boolean, .bigint, .regexp]

    // A set of different types used by various tests.
    let typeSuite: [Type] = [.undefined,
                             .integer,
                             .float,
                             .string,
                             .boolean,
                             .unknown,
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
                             .function([.rest(.anything)] => .unknown),
                             .function([.plain(.integer), .plain(.string), .opt(.anything)] => .float),
                             .constructor(),
                             .constructor([.rest(.anything)] => .object()),
                             .constructor([.plain(.integer), .plain(.string), .opt(.anything)] => .object()),
                             .functionAndConstructor(),
                             .functionAndConstructor([.rest(.anything)] => .unknown),
                             .functionAndConstructor([.plain(.integer), .plain(.string), .opt(.anything)] => .object()),
                             .number,
                             .primitive,
                             .string | .object(),
                             .string | .object(withProperties: ["foo"]),
                             .object(withProperties: ["foo"]) | .function(),
                             .object(withProperties: ["foo"]) | .constructor([.rest(.anything)] => .object()),
                             .primitive | .object() | .function() | .constructor(),
                             .string + .object(withProperties: ["foo", "bar"]),
                             .integer + .object(withProperties: ["foo"], withMethods: ["m"]),
                             .object(withProperties: ["foo", "bar"]) + .function([.plain(.integer)] => .unknown),
                             .object(ofGroup: "A", withProperties: ["foo", "bar"]) + .constructor([.plain(.integer)] => .unknown),
                             .object(withMethods: ["m1"]) + .functionAndConstructor([.plain(.integer), .plain(.boolean)] => .unknown),
                             .object(ofGroup: "A", withProperties: ["foo"], withMethods: ["m1"]) + .functionAndConstructor([.plain(.integer), .plain(.boolean)] => .unknown),
    ]
}

extension TypeSystemTests {
    static var allTests : [(String, (TypeSystemTests) -> () throws -> Void)] {
        return [
            ("testSubsumptionReflexivity", testSubsumptionReflexivity),
            ("testSubsumptionTransitivity", testSubsumptionTransitivity),
            ("testSubsumptionAntisymmetry", testSubsumptionAntisymmetry),
            ("testTypeEquality", testTypeEquality),
            ("testSubsumptionOperators", testSubsumptionOperators),
            ("testIsAndMayBe", testIsAndMayBe),
            ("testPrimitiveTypeSubsumption", testPrimitiveTypeSubsumption),
            ("testAnythingAndNothingSubsumption", testAnythingAndNothingSubsumption),
            ("testUnknownTypeSubsumption", testUnknownTypeSubsumption),
            ("testObjectTypeSubsumption", testObjectTypeSubsumption),
            ("testObjectGroupSubsumption", testObjectGroupSubsumption),
            ("testObjectInspection", testObjectInspection),
            ("testPropertyTypeTransitions", testPropertyTypeTransitions),
            ("testMethodTypeTransitions", testMethodTypeTransitions),
            ("testCallableTypeSubsumption", testCallableTypeSubsumption),
            ("testGeneralization", testGeneralization),
            ("testTypeUnioning", testTypeUnioning),
            ("testTypeIntersection", testTypeIntersection),
            ("testTypeMerging", testTypeMerging),
            ("testSignatureTypes", testSignatureTypes),
            ("testTypeDescriptions", testTypeDescriptions),
            ("testTypeSerialization", testTypeSerialization),
        ]
    }
}
