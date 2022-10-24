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

public struct VariableSet: Hashable, Codable, Sequence {
    // We can use a bitset for efficient operations.
    typealias Word = UInt64

    // The bitset is implemented as array of words. This array must not have trailing
    // zero words at the end so that set comparison works correctly.
    private var words: [Word]

    // Constructs an empty VariableSet.
    public init() {
        self.words = []
    }

    // Constructs a VariableSet containing the given variables.
    public init<S: Sequence>(_ initialVariables: S) where S.Element == Variable {
        self.words = []
        for v in initialVariables {
            insert(v)
        }
    }

    public var isEmpty: Bool {
        return words.isEmpty
    }

    /// Inserts the given variable into this set.
    public mutating func insert(_ v: Variable) {
        let (i, b) = index(of: v)
        growIfNecessary(to: i + 1)
        words[i] |= b
    }

    /// Removes the given variable from this set.
    public mutating func remove(_ v: Variable) {
        let (i, b) = index(of: v)
        if i < words.count {
            words[i] &= ~b
            shrinkIfNecessary()
        }
    }

    /// Removes all variables from this set.
    public mutating func removeAll() {
        words = []
    }

    /// Returns true if this set contains the given variable, false otherwise.
    public func contains(_ v: Variable) -> Bool {
        let (i, b) = index(of: v)
        if i < words.count {
            return words[i] & b == b
        }
        return false
    }

    /// Merges the variables from the given set into this set.
    public mutating func formUnion(_ other: VariableSet) {
        growIfNecessary(to: other.words.count)
        for (i, w) in other.words.enumerated() {
            words[i] |= w
        }
    }

    /// Merges the given variables into this set.
    public mutating func formUnion<S: Sequence>(_ other: S) where S.Element == Variable {
        for v in other {
            self.insert(v)
        }
    }

    /// Removes the variables of this set that are not also present in the other set.
    public mutating func formIntersection(_ other: VariableSet) {
        for (i, w) in other.words.enumerated() {
            if i < words.count {
                words[i] &= w
            }
        }
        shrinkIfNecessary()
    }

    /// Removes the variables of this set that are not also present in the other set.
    public mutating func formIntersection<S: Sequence>(_ other: S) where S.Element == Variable {
        self = intersection(other)
    }

    /// Removes the elements of the given set from the set.
    public mutating func subtract(_ other: VariableSet) {
        for (i, w) in other.words.enumerated() {
            if i < words.count {
                words[i] &= ~w
            }
        }
        shrinkIfNecessary()
    }

    /// Removes the elements of the given sequence from the set.
    public mutating func subtract<S: Sequence>(_ other: S) where S.Element == Variable {
        for v in other {
            self.remove(v)
        }
        shrinkIfNecessary()
    }

    /// Returns a new set with the variables from this set and the provided set.
    public func union(_ other: VariableSet) -> VariableSet {
        var result = self
        result.formUnion(other)
        return result
    }

    /// Returns a new set with the variables from this set and the provided set.
    public func union<S: Sequence>(_ other: S) -> VariableSet where S.Element == Variable {
        var result = self
        result.formUnion(other)
        return result
    }

    /// Returns a new set with the variables that are common in this set and the other.
    public func intersection(_ other: VariableSet) -> VariableSet {
        var result = self
        result.formIntersection(other)
        return result
    }

    //// Returns a new set with the variables that are common in this set and the other.
    public func intersection<S: Sequence>(_ other: S) -> VariableSet where S.Element == Variable {
        var result = VariableSet()
        for v in other {
            if self.contains(v) {
                result.insert(v)
            }
        }
        return result
    }

    /// Returns a new set containing the elements of this set that do not occur in the given set.
    public func subtracting(_ other: VariableSet) -> VariableSet {
        var result = self
        result.subtract(other)
        return result
    }

    /// Returns a new set containing the elements of this set that do not occur in the given set.
    public func subtracting<S: Sequence>(_ other: S) -> VariableSet where S.Element == Variable {
        var result = self
        result.subtract(other)
        return result
    }

    /// Returns true if this set is a subset of the provided set.
    public func isSubset(of other: VariableSet) -> Bool {
        for (i, w) in words.enumerated() {
            if i >= other.words.count || w & other.words[i] != w {
                return false
            }
        }
        return true
    }

    /// Returns true if this set and the provided set have no variables in common.
    public func isDisjoint(with other: VariableSet) -> Bool {
        for (i, w) in other.words.enumerated() {
            if i < words.count && words[i] & w != 0 {
                return false
            }
        }
        return true
    }

    /// Returns true if this set and the provided set have no variables in common.
    public func isDisjoint<S: Sequence>(with other: S) -> Bool where S.Element == Variable {
        for v in other {
            if contains(v) {
                return false
            }
        }
        return true
    }

    public func makeIterator() -> VariableSet.Iterator {
        return Iterator(words: words)
    }

    public struct Iterator: IteratorProtocol {
        public typealias Element = Variable

        private let words: [Word]
        private var idx = 0

        init(words: [Word]) {
            self.words = words
        }

        public mutating func next() -> Variable? {
            while true {
                let wordIdx = idx / Word.bitWidth
                let mask = UInt64(1) << (idx % Word.bitWidth)
                idx += 1
                if wordIdx < words.count {
                    if words[wordIdx] & mask == mask {
                        return Variable(number: idx - 1)
                    }
                } else {
                    return nil
                }
            }
        }
    }

    /// Returns true if the two given sets are equal.
    public static func ==(lhs: VariableSet, rhs: VariableSet) -> Bool {
        return lhs.words == rhs.words
    }

    private func index(of v: Variable) -> (Int, Word) {
        let i = v.number / Word.bitWidth
        let s = v.number % Word.bitWidth
        return (i, 1 << s)
    }

    private mutating func growIfNecessary(to newLen: Int) {
        if newLen > words.count {
            for _ in words.count..<newLen {
                words.append(0)
            }
        }
    }

    private mutating func shrinkIfNecessary() {
        while words.count > 0 && words.last! == 0 {
            words.removeLast()
        }
    }
}
