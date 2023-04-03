// Copyright 2023 Google LLC
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

/// Simple stack implementation on top of Arrays.
///
/// The main benefit over plain Arrays is that this struct also provides a setter for the top element. As such, instead of writing
///
///     myStack[myStack.endIndex - 1].changeValue()
///
/// Client code can simply do:
///
///     myStack.top.changeValue()
///
public struct Stack<Element> {
    private var buffer: [Element]

    public init() {
        self.buffer = []
    }

    public init(_ initial: [Element]) {
        self.buffer = initial
    }

    public var count: Int {
        return buffer.count
    }

    public var isEmpty: Bool {
        return buffer.isEmpty
    }

    public var top: Element {
        get {
            assert(!buffer.isEmpty)
            return buffer.last!
        }
        set(newValue) {
            assert(!buffer.isEmpty)
            buffer[buffer.endIndex - 1] = newValue
        }
    }

    public var secondToTop: Element {
        assert(buffer.count >= 2)
        return buffer[buffer.endIndex - 2]
    }

    public mutating func push(_ element: Element) {
        buffer.append(element)
    }

    @discardableResult
    public mutating func pop() -> Element {
        return buffer.removeLast()
    }

    public mutating func removeAll() {
        buffer.removeAll()
    }

    public func contains(where condition: (Element) -> Bool) -> Bool {
        return buffer.contains(where: condition)
    }

    public func elementsStartingAtTop() -> ReversedCollection<[Element]> {
        return buffer.reversed()
    }

    public func elementsStartingAtBottom() -> [Element] {
        return buffer
    }
}

extension Stack where Element: Comparable {
    public func contains(_ element: Element) -> Bool {
        return buffer.contains(element)
    }
}
