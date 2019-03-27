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
    func v(_ n: Int) -> Variable {
        return Variable(number: n)
    }

    func testBasicVariableSetFeatures() {
        var s = VariableSet()

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
        var s1 = VariableSet([v(0), v(2), v(4)])
        var s2 = VariableSet([v(0), v(1), v(5), v(100)])

        let s3 = s1.union(s2)
        for i in 0...5 {
            XCTAssert(i == 3 || s3.contains(v(i)))
        }
        XCTAssert(s3.contains(v(100)))

        s1.formUnion(s2)
        XCTAssertEqual(s1, s3)
        s2.formUnion([v(2), v(4)])
        XCTAssertEqual(s1, s2)
    }

    func testVariableSetDisjointTest() {
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
}

extension VariableSetTests {
    static var allTests : [(String, (VariableSetTests) -> () throws -> Void)] {
        return [
            ("testBasicVariableSetFeatures", testBasicVariableSetFeatures),
            ("testVariableSetEquality", testVariableSetEquality),
            ("testVariableSetUnion", testVariableSetUnion),
            ("testVariableSetDisjointTest", testVariableSetDisjointTest)
        ]
    }
}
