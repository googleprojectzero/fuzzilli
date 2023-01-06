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

class VariableSetTests: XCTestCase {
    func testBasicVariableSetFeatures() {
        var s = VariableSet()
        XCTAssert(s.isEmpty)

        XCTAssert(!s.contains(v(0)))

        s.insert(v(42))
        XCTAssert(s.contains(v(42)))

        s.insert(v(0))
        XCTAssert(s.contains(v(0)))
        XCTAssert(!s.contains(v(1)))
        s.insert(v(1))
        XCTAssert(s.contains(v(1)))

        s.remove(v(1))
        XCTAssert(!s.contains(v(1)))

        XCTAssert(!s.contains(v(63)))
        XCTAssert(!s.contains(v(64)))
        XCTAssert(!s.contains(v(65)))

        s.insert(v(63))
        XCTAssert(s.contains(v(63)))
        s.insert(v(64))
        XCTAssert(s.contains(v(64)))
        s.insert(v(65))
        XCTAssert(s.contains(v(65)))

        s.remove(v(65))
        XCTAssert(!s.contains(v(65)))
        s.remove(v(64))
        XCTAssert(!s.contains(v(64)))
        s.remove(v(63))
        XCTAssert(!s.contains(v(63)))

        XCTAssert(s.contains(v(0)))
        XCTAssert(s.contains(v(42)))
        XCTAssert(!s.contains(v(62)))

        s.removeAll()
        XCTAssertEqual(s, VariableSet())
        XCTAssert(s.isEmpty)
    }

    func testVariableSetEquality() {
        let vars = Array(0..<256).map { v($0) }

        var s1 = VariableSet(vars)
        XCTAssertEqual(s1, s1)

        var s2 = VariableSet()
        XCTAssertEqual(s2, s2)
        for i in 0..<256 {
            s2.insert(v(i))
        }

        XCTAssertEqual(s1, s2)

        s1.remove(v(42))
        XCTAssertNotEqual(s1, s2)
        s2.remove(v(42))
        XCTAssertEqual(s1, s2)

        var s3 = VariableSet(vars[0..<128])
        XCTAssertNotEqual(s1, s3)
        s3.remove(v(42))
        XCTAssertNotEqual(s1, s3)

        // Remove last 128 variables in s1, should then be equal to s3
        for i in 128..<256 {
            s1.remove(v(i))
        }
        XCTAssertEqual(s1, s3)


        // Add 128 variables to s3, should then be equal to s2
        for i in 128..<256 {
            s3.insert(v(i))
        }
        XCTAssertEqual(s2, s3)

        // Remove all variables from s3, should now equal an empty set
        for i in 0..<256 {
            s3.remove(v(i))
        }
        XCTAssertEqual(s3, VariableSet())
    }

    func testVariableSetUnion() {
        var s1 = VariableSet([v(0), v(2), v(4), v(100)])
        var s2 = VariableSet([v(0), v(1), v(5), v(200)])

        let s3 = s1.union(s2)
        for i in 0...5 {
            XCTAssert(i == 3 || s3.contains(v(i)))
        }
        XCTAssert(s3.contains(v(100)))

        s1.formUnion(s2)
        XCTAssertEqual(s1, s3)

        s2.formUnion([v(2), v(4), v(100)])
        XCTAssertEqual(s1, s2)
    }

    func testVariableSetIntersection() {
        var s1 = VariableSet([v(0), v(2), v(4), v(100)])
        var s2 = VariableSet([v(0), v(1), v(4), v(200)])
        let s3 = VariableSet([v(0), v(4)])

        let s4 = s1.intersection(s2)
        XCTAssertEqual(s4, s3)

        s1.formIntersection(s2)
        XCTAssertEqual(s1, s4)

        s2.formIntersection([v(0), v(2), v(4), v(100)])
        XCTAssertEqual(s1, s2)
    }

    func testVariableSetIsSubset() {
        let s1 = VariableSet([v(0), v(2), v(4), v(100)])
        let s2 = VariableSet([v(0), v(200)])
        let s3 = VariableSet()
        XCTAssert(!s1.isSubset(of: s2))
        XCTAssert(!s2.isSubset(of: s1))
        XCTAssert(s3.isSubset(of: s1))
        XCTAssert(s3.isSubset(of: s2))

        let s4 = VariableSet([v(0), v(99), v(100), v(101), v(200)])
        let s5 = VariableSet([v(100), v(200)])
        XCTAssert(s5.isSubset(of: s4))
        XCTAssert(!s4.isSubset(of: s5))
        let s6 = VariableSet([v(0)])
        XCTAssert(s6.isSubset(of: s4))
        XCTAssert(!s6.isSubset(of: s5))
        XCTAssert(!s4.isSubset(of: s6))
        XCTAssert(!s5.isSubset(of: s6))
    }

    func testVariableSetIsDisjoint() {
        let s1 = VariableSet([v(0), v(2), v(4), v(100)])
        let s2 = VariableSet([v(0), v(1)])
        XCTAssert(!s1.isDisjoint(with: s2))
        XCTAssert(!s2.isDisjoint(with: s1))
        XCTAssert(!s1.isDisjoint(with: s1))

        let s3 = VariableSet([v(0), v(100), v(200)])
        let s4 = VariableSet([v(1)])
        XCTAssert(s3.isDisjoint(with: s4))
        XCTAssert(s4.isDisjoint(with: s3))
        XCTAssert(!s3.isDisjoint(with: s3))

        let s5 = VariableSet([v(0), v(64)])
        XCTAssert(s5.isDisjoint(with: [v(1)]))
        XCTAssert(!s5.isDisjoint(with: [v(0)]))
    }

    func testVariableSetSubtraction() {
        let initial = VariableSet([v(0), v(1), v(2), v(100), v(200)])
        // sX = set to be subtraced, rX = result
        let s0: [Variable] = []
        let r0 = initial
        let s1 = [v(100), v(200), v(300), v(400), v(500)]
        let r1 = VariableSet([v(0), v(1), v(2)])
        let s2 = [v(1)]
        let r2 = VariableSet([v(0), v(2)])
        let s3 = [v(0), v(1), v(2), v(3)]
        let r3 = VariableSet()

        // Test removing VariableSets and generic sequences
        var c = initial
        c.subtract(VariableSet(s0))
        XCTAssertEqual(c, r0)
        c.subtract(VariableSet(s1))
        XCTAssertEqual(c, r1)
        c.subtract(VariableSet(s2))
        XCTAssertEqual(c, r2)
        c.subtract(VariableSet(s3))
        XCTAssertEqual(c, r3)
        XCTAssert(c.isEmpty)

        c = initial
        c.subtract(s0)
        XCTAssertEqual(c, r0)
        c.subtract(s1)
        XCTAssertEqual(c, r1)
        c.subtract(s2)
        XCTAssertEqual(c, r2)
        c.subtract(s3)
        XCTAssertEqual(c, r3)
        XCTAssert(c.isEmpty)
    }

    func testVariableSetIteration() {
        let a0 = [v(0), v(1), v(2), v(100), v(200)]
        let a1 = [v(63), v(64), v(65), v(66)]
        let a2 = (0..<1000).map({ v($0) })
        let a3 = [Variable]()
        let a4 = [v(1337)]

        let s0 = VariableSet(a0)
        let s1 = VariableSet(a1)
        let s2 = VariableSet(a2)
        let s3 = VariableSet(a3)
        let s4 = VariableSet(a4)

        XCTAssertEqual(Array(s0), a0)
        XCTAssertEqual(Array(s1), a1)
        XCTAssertEqual(Array(s2), a2)
        XCTAssertEqual(Array(s3), a3)
        XCTAssertEqual(Array(s4), a4)
    }
}
