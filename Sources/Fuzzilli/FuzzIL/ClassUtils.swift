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
/// and signature are only stored in the BeginClassDefinition operation, not in the BeginMethodDefinition.
class ClassDefinition {
    // An arbitrary name given to this class.
    let name: String

    private let instr: Instruction

    var output: Variable {
        return instr.output
    }

    // Allows the AI to track the sub context when parsing a class definition
    enum SubContext {
        case STATIC_METHOD
        case INSTANCE_METHOD
        case CLASS_CONSTRUCTOR
        case CLASS_DEFINITION
    }
 
    public var subContext: SubContext

    // Instance type of the superclass. .nothing if there is no superclass
    private let superType: Type

    // Constructor signature
    private var constructorSignature: FunctionSignature? = nil

    // List of public static properties/methods
    var publicStaticProperties: [String] = []
    var publicStaticMethods: [String] = []

    // List of public instance properties/methods
    var publicInstanceProperties: [String] = []
    var publicInstanceMethods: [String] = []

    // List of private static properties/methods
    var privateStaticProperties: [String] = []
    var privateStaticMethods: [String] = []

    // List of private instance properties/methods
    var privateInstanceProperties: [String] = []
    var privateInstanceMethods: [String] = []

    public init(from instr: Instruction, withSuperType superType: Type, name: String = "") {
        self.name = name
        self.superType = superType
        self.subContext = SubContext.CLASS_DEFINITION
        self.instr = instr
    }

    func addConstructor(signature: FunctionSignature) {
        self.constructorSignature = signature.inputTypes => Type.object(withProperties: publicInstanceProperties, withMethods: publicInstanceMethods)
    }

    func updateConstructor() {
        assert(constructorSignature != nil, "Class constructor not defined")
        self.constructorSignature = self.constructorSignature!.inputTypes => Type.object(withProperties: publicInstanceProperties, withMethods: publicInstanceMethods)
    }

    func addPublicStaticProperty(_ propertyName: String) {
        assert(subContext == .CLASS_DEFINITION || subContext == .STATIC_METHOD)
        if !publicStaticProperties.contains(propertyName) {
            publicStaticProperties.append(propertyName)
        }
    }

    func addPublicStaticMethod(_ methodName: String) {
        assert(subContext == .CLASS_DEFINITION || subContext == .STATIC_METHOD)
        if !publicStaticMethods.contains(methodName) {
            publicStaticMethods.append(methodName)
        }
    }

    func addPublicInstanceProperty(_ propertyName: String) {
        assert(subContext != .STATIC_METHOD)
        if !publicInstanceProperties.contains(propertyName) {
            publicInstanceProperties.append(propertyName)

            if constructorSignature != nil {
                updateConstructor()
            }
        }
    }

    func addPublicInstanceMethod(_ methodName: String) {
        assert(subContext != .STATIC_METHOD)
        if !publicInstanceMethods.contains(methodName) {
            publicInstanceMethods.append(methodName)

            if constructorSignature != nil {
                updateConstructor()
            }
        }
    }

    func addPrivateStaticProperty(_ propertyName: String) {
        assert(subContext == .CLASS_DEFINITION || subContext == .STATIC_METHOD)
        if !privateStaticProperties.contains(propertyName) {
            privateStaticProperties.append(propertyName)
        }
    }

    func addPrivateStaticMethod(_ methodName: String) {
        assert(subContext == .CLASS_DEFINITION || subContext == .STATIC_METHOD)
        if !privateStaticMethods.contains(methodName) {
            privateStaticMethods.append(methodName)
        }
    }

    func addPrivateInstanceProperty(_ propertyName: String) {
        assert(subContext != .STATIC_METHOD)
        if !privateInstanceProperties.contains(propertyName) {
            privateInstanceProperties.append(propertyName)
        }
    }

    func addPrivateInstanceMethod(_ methodName: String) {
        assert(subContext != .STATIC_METHOD)
        if !privateInstanceMethods.contains(methodName) {
            privateInstanceMethods.append(methodName)
        }
    }

    // Returns the type of the super class.
    func getSuperType() -> Type {
        return superType
    }

    // Returns a type of `this` binding at the current position
    func getThisType() -> Type {
        var thisType: Type = .unknown
        switch subContext {
            case .CLASS_DEFINITION:
                fallthrough
            case .CLASS_CONSTRUCTOR:
                fallthrough
            case .INSTANCE_METHOD:
                thisType = Type.object(withProperties: publicInstanceProperties + privateInstanceProperties, withMethods: publicInstanceMethods + privateInstanceMethods)
            case .STATIC_METHOD:
                thisType = Type.object(withProperties: publicStaticProperties + privateStaticProperties, withMethods: publicStaticMethods + privateStaticMethods)
        }

        if thisType.canMerge(with: superType) {
            assert(superType != .unknown)
            // Merge pure instance type with super type
            thisType += superType
        }

        return thisType
    }

    // Returns a type with a constructor definition
    func getInstanceType() -> Type {
        var instanceType = Type.object(withProperties: publicInstanceProperties, withMethods: publicInstanceMethods)

        if instanceType.canMerge(with: superType) {
            assert(superType != .unknown)
            // Merge pure instance type with super type
            instanceType += superType
        }

        if constructorSignature != nil {
            return .constructor(constructorSignature!.inputTypes => instanceType)
        } else {
            return .constructor([] => instanceType)
        }
    }
}

/// Helper struct to track possibly nested class definitions in FuzzIL code.
struct ClassDefinitionStack {
    private var definitions: [ClassDefinition] = []

    var isEmpty: Bool {
        return definitions.isEmpty
    }

    var current: ClassDefinition {
        assert(!isEmpty)
        return definitions.last!
    }

    mutating func push(_ def: ClassDefinition) {
        definitions.append(def)
    }

    mutating func pop() -> ClassDefinition {
        assert(!isEmpty)
        return definitions.removeLast()
    }
}
