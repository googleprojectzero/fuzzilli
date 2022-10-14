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

/// A list where each element also has a weight, which determines how frequently it is selected by randomElement().
/// For example, an element with weight 10 is 2x more likely to be selected by randomElement() than an element with weight 5.
public struct WeightedList<Element>: Sequence {
    private var elements = [(elem: Element, weight: Int, cumulativeWeight: Int)]()
    private var totalWeight = 0

    public init() {}

    public init(_ values: [(Element, Int)]) {
        for (e, w) in values {
            append(e, withWeight: w)
        }
    }

    public var count: Int {
        return elements.count
    }

    public var isEmpty: Bool {
        return count == 0
    }

    public mutating func append(_ elem: Element, withWeight weight: Int) {
        assert(weight > 0)
        elements.append((elem, weight, totalWeight))
        totalWeight += weight
    }

    public func filter(_ isIncluded: (Element) -> Bool) -> WeightedList<Element> {
        var r = WeightedList()
        for (e, w, _) in elements where isIncluded(e) {
            r.append(e, withWeight: w)
        }
        return r
    }

    public func randomElement() -> Element {
        // Binary search: pick a random value between 0 and the sum of all weights, then find the
        // first element whose cumulative weight is less-than or equal to the selected one.
        let v = Int.random(in: 0..<totalWeight)

        var low = 0
        var high = elements.count - 1
        while low != high {
            let mid = low + (high - low + 1) / 2

            // Verify the invariants of this binary search implementation.
            assert(0 <= low && low <= mid && mid <= high && high < elements.count)
            assert(elements[low].cumulativeWeight <= v)
            assert(high == elements.count - 1 || elements[high + 1].cumulativeWeight > v)

            if elements[mid].cumulativeWeight > v {
                high = mid - 1
            } else {
                low = mid
            }
        }

        // Also verify the results of this binary search implementation.
        assert(elements[low].cumulativeWeight <= v)
        assert(low == 0 || elements[low - 1].cumulativeWeight < v)
        assert(low == elements.count - 1 || elements[low + 1].cumulativeWeight > v)

        return elements[low].elem
    }

    public func makeIterator() -> Array<Element>.Iterator {
        return elements.map({ $0.elem }).makeIterator()
    }
}
