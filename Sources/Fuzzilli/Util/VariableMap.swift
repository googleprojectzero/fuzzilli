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

// TODO this should probably be a Collection, not a Sequence.
// Note that this means that if you add an entry for Variable v123 as the first
// and only element in the map, then 122 empty elements are allocated too.
public struct VariableMap<Value>: Sequence {
    public typealias Element = (Variable, Value)

    private var elements: [Value?]

    public init() {
        self.elements = []
        // Reserve capacity for roughly as many elements as the average number of variables in generated Programs
        elements.reserveCapacity(128)
    }

    public init(_ elementsMap: [Int: Value]) {
        self.init()
        for (varNumber, value) in elementsMap {
            self[Variable(number: varNumber)] = value
        }
    }

    init(_ elements: [Value?]) {
        self.elements = elements
    }

    public var isEmpty: Bool {
        return elements.isEmpty
    }

    public subscript(variable: Variable) -> Value? {
        get {
            let index = variable.number
            if index >= elements.count {
                return nil
            }

            return elements[index]
        }
        mutating set(newValue) {
            let index = variable.number
            growIfNecessary(to: index + 1)
            elements[index] = newValue
        }
    }

    public func contains(_ variable: Variable) -> Bool {
        return elements.count > variable.number && elements[variable.number] != nil
    }

    public func hasHoles() -> Bool {
        return elements.contains(where: {$0 == nil})
    }

    public mutating func removeValue(forKey variable: Variable) {
        if elements.count > variable.number {
            elements[variable.number] = nil
            shrinkIfNecessary()
        }
    }

    public mutating func removeAll() {
        elements = []
    }

    public func makeIterator() -> VariableMap<Value>.Iterator {
        return Iterator(elements: elements)
    }

    public struct Iterator: IteratorProtocol {
        public typealias Element = (Variable, Value)

        private let elements: [Value?]
        private var idx = 0

        init(elements: [Value?]) {
            self.elements = elements
        }

        public mutating func next() -> Element? {
            while idx < elements.count {
                idx += 1
                if let elem = elements[idx - 1] {
                    return (Variable(number: idx - 1), elem)
                }
            }
            return nil
        }
    }

    private mutating func growIfNecessary(to newLen: Int) {
        if newLen < elements.count {
            return
        }
        for _ in 0..<newLen - elements.count {
            elements.append(nil)
        }
    }

    private mutating func shrinkIfNecessary() {
        while elements.count > 0 && elements.last! == nil {
            elements.removeLast()
        }
    }
}

// VariableMaps can be compared for equality if their elements can.
extension VariableMap: Equatable where Value: Equatable {
    public static func == (lhs: VariableMap<Value>, rhs: VariableMap<Value>) -> Bool {
        return lhs.elements == rhs.elements
    }
}

// VariableMaps can be hashed if their elements can.
extension VariableMap: Hashable where Value: Hashable {}

// VariableMaps can be encoded and decoded if their elements can.
extension VariableMap: Codable where Value: Codable {}
