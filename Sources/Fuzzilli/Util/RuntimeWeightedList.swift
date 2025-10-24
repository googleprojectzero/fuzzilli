
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
public class RuntimeWeightedList<Element: Equatable>: WeightedList<Element> {
    private var elements = [(
        elem: Element,
        weight: Int,
        cumulativeWeight: Int,
        runtimeWeight: Float,
        cumulativeRuntimeWeight: Float
    )]()
    private(set) var totalRuntimeWeight: Float = 0.0
    // cache of most recently selected mutators
    private var lastElements: [Element] = []

    public func adjustWeight(_ elem: Element, _ factor: Float) {
        var hitElement = false;
        var diffWeight: Float = 0.0
        for i in 0..<elements.count {
            if (hitElement) {
                elements[i].cumulativeRuntimeWeight += diffWeight
            } else if elements[i].elem == elem {
                let ogRuntimeWeight = elements[i].runtimeWeight
                elements[i].runtimeWeight *= factor 
                diffWeight = elements[i].runtimeWeight - ogRuntimeWeight
                totalRuntimeWeight += factor - elements[i].runtimeWeight
                hitElement = true;
            }
        }
    }

    public func adjustBatchWeight(_ hitElements: [Element], _ factorHit: Float?, _ factorNotHit: Float?) {
        for element in elements {
            let elem: Element = element.elem
            if hitElements.contains(elem) {
                adjustWeight(elem, factorHit ?? 1.1)
            } else {
                adjustWeight(elem, factorNotHit ?? 0.9)
            }
        }
    }

    public override func filter(_ isIncluded: (Element) -> Bool) -> RuntimeWeightedList<Element> {
        var r: RuntimeWeightedList<Element> = RuntimeWeightedList()
        for (e, w, cw, rw, crw) in elements where isIncluded(e) {
            r.append(e, withWeight: w)
        }
        return r
    }
    
    public func append(_ elem: Element, withWeight weight: Int, runtimeWeight: Float) {
        assert(weight > 0)
        elements.append((elem, weight, totalWeight, runtimeWeight, totalRuntimeWeight))
        totalRuntimeWeight += runtimeWeight
    }

    public func weightedElement() -> Element {
        let k = Float.random(in: 0.0...totalRuntimeWeight)

        for i in 0..<elements.count {
            if elements[i].cumulativeRuntimeWeight > k {
                return elements[i].elem
            }
        }

        let randomElement = randomElement()

        lastElements.append(randomElement)
        return randomElement
    }

    public func getLastElements() -> [Element] {
        return lastElements
    }

    public func popLastElement() -> Void {
        lastElements.popLast()
    }

    public func flushLastElements() -> Void {
        lastElements = []
    }
}
