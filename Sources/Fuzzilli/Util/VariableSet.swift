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

struct VariableSet: Equatable {
    // We can use a bitset for efficient operations.
    typealias Word = UInt64
    private var words: [Word]
    
    // Construct an empty VariableSet.
    init() {
        self.words = []
    }
    
    // Construct a VariableSet containing the given variables.
    init<S: Sequence>(_ initialVariables: S) where S.Element == Variable {
        self.words = []
        for v in initialVariables {
            insert(v)
        }
    }
    
    private func index(of v: Variable) -> (Int, Word) {
        let i = v.number / Word.bitWidth
        let s = v.number % Word.bitWidth
        return (i, 1 << s)
    }
    
    private mutating func ensureWordCount(atLeast n: Int) {
        if n > words.count {
            for _ in words.count..<n {
                words.append(0)
            }
        }
    }
    
    /// Inserts the given variable into this set.
    mutating func insert(_ v: Variable) {
        let (i, b) = index(of: v)
        ensureWordCount(atLeast: i + 1)
        words[i] |= b
    }
    
    /// Removes the given variable from this set.
    mutating func remove(_ v: Variable) {
        let (i, b) = index(of: v)
        if i < words.count {
            words[i] &= ~b
            
            // Must remove trailing words if they are empty so that set comparison works as expected.
            if i == words.count - 1 && words[i] == 0 {
                words.removeLast()
            }
        }
    }
    
    /// Returns true if this set contains the given variable, false otherwise.
    func contains(_ v: Variable) -> Bool {
        let (i, b) = index(of: v)
        if i < words.count {
            return words[i] & b == b
        }
        return false
    }
    
    /// Merges the variables from the given set into this set.
    mutating func formUnion(_ other: VariableSet) {
        ensureWordCount(atLeast: other.words.count)
        for (i, w) in other.words.enumerated() {
            words[i] |= w
        }
    }
    
    /// Merges the given variables into this set.
    mutating func formUnion<S: Sequence>(_ other: S) where S.Element == Variable {
        for v in other {
            insert(v)
        }
    }
    
    /// Returns a new set with the variables from this set and the provided set.
    func union(_ other: VariableSet) -> VariableSet {
        var result = self
        result.formUnion(other)
        return result
    }
    
    /// Returns true if this set and provided set have no variables in common.
    func isDisjoint(with other: VariableSet) -> Bool {
        for (i, w) in other.words.enumerated() {
            if i < words.count && words[i] & w != 0 {
                return false
            }
        }
        return true
    }
    
    /// Returns true if this and the provided set have no variables in common.
    func isDisjoint<S: Sequence>(with other: S) -> Bool where S.Element == Variable {
        for v in other {
            if contains(v) {
                return false
            }
        }
        return true
    }
    
    /// Returns true if the two given sets are equal.
    static func ==(lhs: VariableSet, rhs: VariableSet) -> Bool {
        return lhs.words == rhs.words
    }
}
