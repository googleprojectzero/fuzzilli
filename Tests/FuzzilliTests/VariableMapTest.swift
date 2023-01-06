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

class VariableMapTests: XCTestCase {
    func testBasicVariableMapFeatures() {
        var m = VariableMap<Int>()
        XCTAssert(m.isEmpty)

        XCTAssert(!m.contains(v(0)) && m[v(0)] == nil)

        m[v(42)] = 42
        XCTAssert(m.contains(v(42)) && m[v(42)] == 42)

        m[v(0)] = 0
        XCTAssert(m.contains(v(0)) && m[v(0)] == 0)
        XCTAssert(!m.contains(v(1)) && m[v(1)] == nil)
        m[v(1)] = 1
        XCTAssert(m.contains(v(1)) && m[v(1)] == 1)

        m.removeValue(forKey: v(1))
        XCTAssert(!m.contains(v(1)) && m[v(1)] == nil)
        XCTAssert(m.contains(v(0)) && m[v(0)] == 0)

        m.removeAll()
        XCTAssertEqual(m, VariableMap<Int>())
        XCTAssert(m.isEmpty)

        m[v(43)] = 100
        XCTAssertFalse(m.isEmpty)
        m.removeValue(forKey: v(43))
        XCTAssert(m.isEmpty)
    }

    func testVariableMapEquality() {
        var m1 = VariableMap<Bool>()
        XCTAssertEqual(m1, m1)

        var m2 = VariableMap<Bool>()
        XCTAssertEqual(m1, m2)

        for i in 0..<128 {
            let val = Bool.random()
            m1[v(i)] = val
            m2[v(i)] = val
        }
        XCTAssertEqual(m1, m2)

        m1.removeValue(forKey: v(2))
        XCTAssertNotEqual(m1, m2)
        m2.removeValue(forKey: v(2))
        XCTAssertEqual(m1, m2)

        // Add another 128 elements and compare with a new map built up in the opposite order
        for i in 128..<256 {
            let val = Bool.random()
            m2[v(i)] = val
        }

        var m3 = VariableMap<Bool>()
        XCTAssertNotEqual(m1, m3)

        for i in (0..<256).reversed() {
            m3[v(i)] = m2[v(i)] ?? false
        }
        XCTAssertNotEqual(m1, m3)
        m3.removeValue(forKey: v(2))
        XCTAssertEqual(m3, m2)

        // Remove last 128 variables from m3, should now be equal to m1
        for i in 128..<256 {
            m3.removeValue(forKey: v(i))
        }
        XCTAssertEqual(m3, m1)

        // Remove all variables from m2, should now be equal to an empty map
        for i in 0..<256 {
            m2.removeValue(forKey: v(i))
        }
        XCTAssertEqual(m2, VariableMap<Bool>())
    }

    func testVariableMapEncoding() {
        var map = VariableMap<Int>()

        for i in 0..<1000 {
            withProbability(0.75) {
                map[v(i)] = Int.random(in: 0..<1000000)
            }
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try! encoder.encode(map)
        let mapCopy = try! decoder.decode(VariableMap<Int>.self, from: data)

        XCTAssertEqual(map, mapCopy)
    }

    func testVariableMapHashing() {
        var map1 = VariableMap<Int>()
        var map2 = VariableMap<Int>()

        for i in 0..<1000 {
            withProbability(0.75) {
                let value = Int.random(in: 0..<1000000)
                map1[v(i)] = value
                map2[v(i)] = value
            }
        }

        XCTAssertEqual(map1, map2)
        XCTAssertEqual(map1.hashValue, map2.hashValue)
    }

    func testVariableMapIteration() {
        var map = VariableMap<Int>()
        for i in 0..<1000 {
            withProbability(0.5) {
                map[v(i)] = Int.random(in: 0..<1000000)
            }
        }

        var copy = VariableMap<Int>()
        for (v, t) in map {
            copy[v] = t
        }
        XCTAssertEqual(map, copy)
    }

    func testEmptyVariableMapForHoles() {
        let m = VariableMap<Int>()

        XCTAssertEqual(m.hasHoles(), false)
    }

    func testDenseVariableMapForHoles() {
        var m = VariableMap<Int>()

        for i in 0..<20 {
            m[v(i)] = Int.random(in: 0..<20)
        }

        XCTAssertEqual(m.hasHoles(), false)
    }

    func testForHolesAfterLastElementRemoval() {
        var m = VariableMap<Int>()

        let mapSize = 15
        for i in 0..<mapSize {
            m[v(i)] = Int.random(in: 0..<20)
        }
        m.removeValue(forKey: v(mapSize-1))

        XCTAssertEqual(m.hasHoles(), false)
    }

    func testForHolesAfterFirstElementRemoval() {
        var m = VariableMap<Int>()

        let mapSize = 15
        for i in 0..<mapSize {
            m[v(i)] = Int.random(in: 0..<20)
        }
        m.removeValue(forKey: v(0))

        XCTAssertEqual(m.hasHoles(), true)
    }

    func testForHolesAfterArbitraryElementRemoval() {
        var m = VariableMap<Int>()

        let mapSize = 15
        for i in 0..<mapSize {
            m[v(i)] = Int.random(in: 0..<20)
        }
        m.removeValue(forKey: v(Int.random(in: 0..<mapSize-1)))

        XCTAssertEqual(m.hasHoles(), true)
    }
}
