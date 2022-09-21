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

import Foundation

public struct RingBuffer<Element>: Collection {
    /// The internal buffer used by this implementation.
    private var buffer: [Element]

    /// The index in the buffer that is the current start (the oldest element).
    private var start: Int

    /// The maximum size of this ring buffer.
    public let maxSize: Int

    /// The number of elements in this ring buffer.
    public var count: Int {
        return buffer.count
    }

    /// The index of the first element.
    public let startIndex = 0

    /// The first index after the end of this buffer.
    public var endIndex: Int {
        return count
    }

    public init(maxSize: Int) {
        self.buffer = []
        self.start = 0
        self.maxSize = maxSize
    }

    /// Returns the next index after the provided one.
    public func index(after i: Int) -> Int {
        return i + 1
    }

    /// Accesses the element at the given index.
    public subscript(index: Int) -> Element {
        get {
            return buffer[(start + index) % maxSize]
        }
        mutating set(newValue) {
            buffer[(start + index) % maxSize] = newValue
        }
    }

    /// Appends the element to this buffer, evicting the oldest element if necessary.
    public mutating func append(_ element: Element) {
        if buffer.count < maxSize {
            buffer.append(element)
        } else {
            buffer[(start + count) % maxSize] = element
            start += 1
        }
    }

    /// Removes all elements from this buffer, resetting its size to zero.
    public mutating func removeAll() {
        buffer.removeAll()
        start = 0
    }
}
