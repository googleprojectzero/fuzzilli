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

extension Int {
    /// Returns a random integer in the given range biased towards higher numbers.
    ///
    /// The probability of a value n being selected is the probability of the
    /// value (n - 1) times the bias factor.
    public static func random(in range: Range<Int>, bias: Double) -> Int {
        assert(bias >= 1)

        // s = sum(q^k, 0 <= k < n), see geometric series
        let q = bias
        let s = (1.0 - pow(q, Double(range.upperBound))) / (1.0 - q)

        var c = Double.random(in: 0..<s)

        // TODO improve this
        var p = 1.0
        for i in range {
            c -= p
            if c < 0 {
                return i
            }
            p *= q
        }
        fatalError()
    }
}

extension String {
    // Returns a random string of the specified length.
    public static func random(ofLength length: Int,
      withCharSet charSet: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
      ) -> String {
        var s = ""
        for _ in 0..<length {
            s += String(chooseUniform(from: charSet))
        }
        return s
    }
}

/// Returns a uniformly choosen, random element from the given collection.
public func chooseUniform<E>(from collection: [E]) -> E {
    assert(collection.count != 0, "cannot choose from an empty sequence")
    return collection[Int.random(in: 0..<collection.count)]
}

/// Returns a uniformly choosen, random element from the given collection.
public func chooseUniform<E>(from collection: ArraySlice<E>) -> E {
    assert(collection.count != 0, "cannot choose from an empty sequence")
    return collection[Int.random(in: 0..<collection.count)]
}

/// Returns a uniformly choosen, random element from the given collection.
public func chooseUniform<E>(from collection: Set<E>) -> E {
    assert(collection.count != 0, "cannot choose from an empty set")
    let i = collection.index(collection.startIndex, offsetBy: Int.random(in: 0..<collection.count))
    return collection[i]
}

/// Returns a random element from the given collection favouring later elements by the given factor.
public func chooseBiased<E>(from collection: [E], factor: Double) -> E {
    assert(collection.count != 0, "cannot choose from an empty sequence")
    return collection[Int.random(in: 0..<collection.count, bias: factor)]
}

/// Returns a random element from the given collection favouring later elements by the given factor.
public func chooseBiased<E>(from collection: ArraySlice<E>, factor: Double) -> E {
    assert(collection.count != 0, "cannot choose from an empty sequence")
    return collection[Int.random(in: 0..<collection.count, bias: factor)]
}

/// Returns true with the given probability, false otherwise.
public func probability(_ prob: Double) -> Bool {
    assert(prob >= 0 && prob <= 1.0)
    return prob == 1.0 || Double.random(in: 0..<1) < prob
}

/// Performs an action with a given probability.
public func withProbability(_ prob: Double, do action: () -> Void) {
    if probability(prob) {
        action()
    }
}

// Performs the first action with the given probability, otherwise performs the second action.
public func withProbability<T>(_ prob: Double, do action: () -> T, else alternative: () -> T) -> T {
    if probability(prob) {
        return action()
    } else {
        return alternative()
    }
}

// Performs one of the provided actions and return the result.
@discardableResult
public func withEqualProbability<T>(_ actions: () -> T...) -> T {
    return chooseUniform(from: actions)()
}
