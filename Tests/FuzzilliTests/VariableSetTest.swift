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

    func testVariableSetUnion() {
        var s1 = VariableSet([v(0), v(2), v(4)])
        var s2 = VariableSet([v(0), v(1), v(5), v(100)])

        let s3 = s1.union(s2)
        for i in 0...5 {
            XCTAssert(i == 3 || s3.contains(v(i)))
        }
        XCTAssert(s3.contains(v(100)))

        s1.formUnion(s2)
        XCTAssert(s1 == s3)
        s2.formUnion([v(2), v(4)])
        XCTAssert(s2 == s1 && s2 == s1)
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
            ("testVariableSetUnion", testVariableSetUnion),
            ("testVariableSetDisjointTest", testVariableSetDisjointTest)
        ]
    }
}
