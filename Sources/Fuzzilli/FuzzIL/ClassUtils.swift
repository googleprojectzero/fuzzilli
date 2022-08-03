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

/// Helper class to store  information about a FuzzIL class definition.
///
/// This is mainly needed to retrieve information about method definitions, since the method name
/// and signature are only stored in the BeginClass operation, not in the BeginMethodDefinition.
class ClassDefinition {
    // An arbitrary name given to this class.
    let name: String

    // Instance type of the superclass. .nothing if there is no superclass
    let superType: Type
    // Instance type of this class, including the supertype
    let instanceType: Type

    // Signature of the constructor, with the instance type being the return type.
    let constructorSignature: FunctionSignature

    // Method definitions that haven't been processed yet by nextMethod().
    private var remainingMethods: [(name: String, signature: FunctionSignature)]

    private init(name: String, superType: Type, instanceType: Type, constructorSignature: FunctionSignature, methods: [(String, FunctionSignature)]) {
        self.name = name
        self.superType = superType
        self.instanceType = instanceType
        self.constructorSignature = constructorSignature
        self.remainingMethods = methods.reversed()         // reversed so nextMethod() works efficiently
    }

    convenience init(from op: BeginClass, withSuperType superType: Type = .nothing, name: String = "") {
        // Compute "pure" instance type
        var instanceType = Type.object(ofGroup: nil,
                                       withProperties: op.instanceProperties,
                                       withMethods: op.instanceMethods.map( { $0.name }))

        if instanceType.canMerge(with: superType) {
            Assert(superType != .unknown)
            // Merge pure instance type with super type
            instanceType += superType
        }

        let constructorSignature = op.constructorParameters => instanceType

        self.init(name: name,
                  superType: superType,
                  instanceType: instanceType,
                  constructorSignature: constructorSignature,
                  methods: op.instanceMethods)
    }

    /// True if not all method definitions have been processed yet.
    var hasPendingMethods: Bool {
        return !remainingMethods.isEmpty
    }

    /// Returns all method definitions that haven't yet been processed by nextMethod.
    func pendingMethods() -> [(name: String, signature: FunctionSignature)] {
        return remainingMethods.reversed()
    }

    /// Returns the next method definition that hasn't been processed yet and marks it as processed.
    func nextMethod() -> (name: String, signature: FunctionSignature) {
        Assert(hasPendingMethods)
        return remainingMethods.removeLast()
    }
}

/// Helper struct to track possibly nested class definitions in FuzzIL code.
struct ClassDefinitionStack {
    private var definitions: [ClassDefinition] = []

    var isEmpty: Bool {
        return definitions.isEmpty
    }

    var current: ClassDefinition {
        Assert(!isEmpty)
        return definitions.last!
    }

    mutating func push(_ def: ClassDefinition) {
        definitions.append(def)
    }

    mutating func pop() {
        Assert(!isEmpty)
        definitions.removeLast()
    }
}
