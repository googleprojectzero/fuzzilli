// Copyright 2021 Google LLC
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

/// Helper class to store  information about a FuzzIL object definition.
///
/// This is mainly needed to retrieve information about properties, since the property name and types
/// are stored in several FuzzIL instructions that form part of the object definition.
class ObjectDefinition {
    private let instr: Instruction

    var properties: [String] = []

    var methods: [String] = []

    var output: Variable {
        return instr.output
    }

    init(from instr: Instruction) {
        self.instr = instr
    }

    func addProperty(_ propertyName: String) {
        if !properties.contains(propertyName) {
            properties.append(propertyName)
        }
    }

    func addProperty(_ propertyNames: Set<String>) {
        for propertyName in propertyNames {
            self.addProperty(propertyName)
        }
    }

    func addMethod(_ methodName: String) {
        if !methods.contains(methodName) {
            methods.append(methodName)
        }
    }

    func addMethod(_ methodNames: Set<String>){
        for methodName in methodNames {
            self.addMethod(methodName)
        }
    }

    func getType() -> Type {
        return .object(withProperties: properties, withMethods: methods)
    }
}

/// Helper struct to track possibly nested object definitions in FuzzIL code.
struct ObjectDefinitionStack {
    private var definitions: [ObjectDefinition] = []

    var isEmpty: Bool {
        return definitions.isEmpty
    }

    var current: ObjectDefinition {
        assert(!isEmpty)
        return definitions.last!
    }

    mutating func push(_ def: ObjectDefinition) {
        definitions.append(def)
    }

    mutating func pop() -> ObjectDefinition {
        assert(!isEmpty)
        return definitions.removeLast()
    }
}
