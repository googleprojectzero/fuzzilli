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

class RingBufferTests: XCTestCase {
    func testBasicRingBufferBehaviour() {
        var b = RingBuffer<Int>(maxSize: 3)

        XCTAssertEqual(b.count, 0)

        b.append(0)
        b.append(1)
        b.append(2)

        XCTAssertEqual(b.count, 3)

        XCTAssertEqual(b[0], 0)
        XCTAssertEqual(b[1], 1)
        XCTAssertEqual(b[2], 2)

        b.append(3)

        XCTAssertEqual(b.count, 3)

        XCTAssertEqual(b[0], 1)
        XCTAssertEqual(b[1], 2)
        XCTAssertEqual(b[2], 3)

        b.append(4)
        b.append(5)
        b.append(6)

        XCTAssertEqual(b.count, 3)

        XCTAssertEqual(b[0], 4)
        XCTAssertEqual(b[1], 5)
        XCTAssertEqual(b[2], 6)
    }

    func testRingBufferElementWriteAccess() {
        var b = RingBuffer<Int>(maxSize: 3)

        b.append(0)
        XCTAssertEqual(b[0], 0)

        b[0] = 42
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0], 42)

        b.append(1)
        b.append(2)

        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0], 42)
        XCTAssertEqual(b[1], 1)
        XCTAssertEqual(b[2], 2)

        b[2] = 1337
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0], 42)
        XCTAssertEqual(b[1], 1)
        XCTAssertEqual(b[2], 1337)

        b.append(3)
        b.append(4)
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0], 1337)
        XCTAssertEqual(b[1], 3)
        XCTAssertEqual(b[2], 4)
    }

    func testRingBufferElementRemoval() {
        var b = RingBuffer<Int>(maxSize: 3)
        b.append(0)
        b.append(1)
        b.append(2)
        b.append(3)

        b.removeAll()
        XCTAssertEqual(b.count, 0)

        b.append(4)
        b.append(5)

        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b[0], 4)
        XCTAssertEqual(b[1], 5)
    }

    func testRingBufferIteration() {
        var b = RingBuffer<Int>(maxSize: 3)
        b.append(0)
        b.append(1)
        b.append(2)
        b.append(0)
        b.append(1)
        b.append(2)

        var counter = 0
        for (i, e) in b.enumerated() {
            XCTAssertEqual(e, i)
            counter += 1
        }
        XCTAssertEqual(counter, 3)
    }
}
