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

/// Hacky implementation of a weighted list of elements.
///
/// An element with weight 2 is 2x more likely to be selected by randomElement() than an element with weight 1. And so on.
public struct WeightedList<Element>: Sequence {
    fileprivate var array = [Element]()
    fileprivate var elementsAndWeights = [(elem: Element, weight: Int)]()

    public init() {}

    public init(_ values: [(Element, Int)]) {
        for (e, w) in values {
            append(e, withWeight: w)
        }
    }

    public var count: Int {
        return elementsAndWeights.count
    }

    public var isEmpty: Bool {
        return count == 0
    }

    public mutating func append(_ elem: Element, withWeight weight: Int) {
        for _ in 0..<weight {
            array.append(elem)
        }
        elementsAndWeights.append((elem, weight))
    }

    public func randomElement() -> Element {
        return chooseUniform(from: array)
    }

    public func makeIterator() -> Array<Element>.Iterator {
        return elementsAndWeights.map({ $0.elem }).makeIterator()
    }

    public func elementsWithWeights() -> [(Element, Int)] {
        return elementsAndWeights
    }

    public mutating func append(_ rhs: WeightedList<Element>) {
        array += rhs.array
        elementsAndWeights += rhs.elementsAndWeights
    }
}
