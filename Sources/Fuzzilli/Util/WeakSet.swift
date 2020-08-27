// Copyright 2020 Google LLC
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
struct WeakVar<T: AnyObject>: Hashable where T: Hashable {
    weak var value: T?

    static func == (_ lhs: WeakVar, _ rhs: WeakVar) -> Bool {
        return lhs.value == rhs.value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

public struct WeakSet<Element: AnyObject> where Element: Hashable {
    private var elements: Set<WeakVar<Element> > = []

    var totalCount: Int {
        return elements.count
    }

    public mutating func insert(_ element: Element) -> (inserted: Bool, memberAfterInsert: Element) {
        let wrappedResponse = elements.insert(WeakVar(value: element))
        return (
            inserted: wrappedResponse.inserted, memberAfterInsert: wrappedResponse.memberAfterInsert.value!
        )
    }

    public func contains(_ element: Element) -> Bool {
        return elements.contains(WeakVar(value: element))
    }
    
    public mutating func removeNils() {
        elements = elements.filter{ $0.value != nil }
    }
}
