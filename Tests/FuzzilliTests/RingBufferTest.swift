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

@Suite struct RingBufferTests {
    @Test func testBasicRingBufferBehaviour() {
        var b = RingBuffer<Int>(maxSize: 3)

        #expect(b.count == 0)

        b.append(0)
        b.append(1)
        b.append(2)

        #expect(b.count == 3)

        #expect(b[0] == 0)
        #expect(b[1] == 1)
        #expect(b[2] == 2)

        b.append(3)

        #expect(b.count == 3)

        #expect(b[0] == 1)
        #expect(b[1] == 2)
        #expect(b[2] == 3)

        b.append(4)
        b.append(5)
        b.append(6)

        #expect(b.count == 3)

        #expect(b[0] == 4)
        #expect(b[1] == 5)
        #expect(b[2] == 6)
    }

    @Test func testRingBufferElementWriteAccess() {
        var b = RingBuffer<Int>(maxSize: 3)

        b.append(0)
        #expect(b[0] == 0)

        b[0] = 42
        #expect(b.count == 1)
        #expect(b[0] == 42)

        b.append(1)
        b.append(2)

        #expect(b.count == 3)
        #expect(b[0] == 42)
        #expect(b[1] == 1)
        #expect(b[2] == 2)

        b[2] = 1337
        #expect(b.count == 3)
        #expect(b[0] == 42)
        #expect(b[1] == 1)
        #expect(b[2] == 1337)

        b.append(3)
        b.append(4)
        #expect(b.count == 3)
        #expect(b[0] == 1337)
        #expect(b[1] == 3)
        #expect(b[2] == 4)
    }

    @Test func testRingBufferElementRemoval() {
        var b = RingBuffer<Int>(maxSize: 3)
        b.append(0)
        b.append(1)
        b.append(2)
        b.append(3)

        b.removeAll()
        #expect(b.count == 0)

        b.append(4)
        b.append(5)

        #expect(b.count == 2)
        #expect(b[0] == 4)
        #expect(b[1] == 5)
    }

    @Test func testRingBufferIteration() {
        var b = RingBuffer<Int>(maxSize: 3)
        b.append(0)
        b.append(1)
        b.append(2)
        b.append(0)
        b.append(1)
        b.append(2)

        var counter = 0
        for (i, e) in b.enumerated() {
            #expect(e == i)
            counter += 1
        }
        #expect(counter == 3)
    }
}
