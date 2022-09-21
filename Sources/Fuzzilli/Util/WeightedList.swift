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
    fileprivate var elems = [Element]()

    public init(_ values: [(Element, Int)]) {
        for (e, w) in values {
            append(e, withWeight: w)
        }
    }

    fileprivate init(_ array: [Element], _ elems: [Element]) {
        self.array = array
        self.elems = elems
    }

    public mutating func append(_ elem: Element, withWeight weight: Int) {
        for _ in 0..<weight {
            array.append(elem)
        }
        elems.append(elem)
    }

    public func randomElement() -> Element {
        return chooseUniform(from: array)
    }

    public func makeIterator() -> Array<Element>.Iterator {
        return elems.makeIterator()
    }

    public var count: Int {
        return elems.count
    }

    public mutating func append(_ rhs: WeightedList<Element>) {
        array += rhs.array
        elems += rhs.elems
    }
}

public func +<Element>(lhs: WeightedList<Element>, rhs: WeightedList<Element>) -> WeightedList<Element> {
    return WeightedList<Element>(lhs.array + rhs.array, lhs.elems + rhs.elems)
}
