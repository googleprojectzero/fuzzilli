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

public struct VariableMap<Element> {
    private var elements: [Element?]
    
    public init() {
        self.elements = []
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
    
    public subscript(variable: Variable) -> Element? {
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
    
    public mutating func remove(_ variable: Variable) {
        if elements.count > variable.number {
            elements[variable.number] = nil
            shrinkIfNecessary()
        }
    }
}

// VariableMaps can be compared for equality if their elements can.
extension VariableMap: Equatable where Element: Equatable {
    public static func == (lhs: VariableMap<Element>, rhs: VariableMap<Element>) -> Bool {
        return lhs.elements == rhs.elements
    }
}

// VariableMaps can be hashed if their elements can.
extension VariableMap: Hashable where Element: Hashable {}

// VariableMaps can be encoded and decoded if their elements can.
extension VariableMap: Codable where Element: Codable {}
