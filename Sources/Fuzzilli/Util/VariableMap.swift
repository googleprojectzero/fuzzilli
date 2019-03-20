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

struct VariableMap<Element> {
    var elements: [Element?]
    let defaultValue: Element?
    
    init(defaultValue: Element? = nil) {
        self.defaultValue = defaultValue
        self.elements = [Element]()
    }
    
    private mutating func growIfNecessary(to newLen: Int) {
        if newLen < elements.count {
            return
        }
        for _ in 0..<newLen - elements.count {
            elements.append(nil)
        }
    }
    subscript(variable: Variable) -> Element {
        get {
            let index = variable.number
            if index >= elements.count {
                return defaultValue!
            }
            
            let elem = elements[index]
            if elem == nil {
                return defaultValue!
            }
            return elem!
        }
        mutating set(newValue) {
            let index = variable.number
            growIfNecessary(to: index + 1)
            elements[index] = newValue
        }
    }
    
    func contains(_ variable: Variable) -> Bool {
        return elements.count > variable.number && elements[variable.number] != nil
    }
    
    mutating func remove(_ variable: Variable) {
        if elements.count > variable.number {
            elements[variable.number] = nil
        }
    }
}
