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

// A simple type system for the JavaScript language designed to be used for fuzzing.
//
// The goal of this type system is to be as simple as possible while still being able to express all the common
// operations that one can peform on values of the target language, e.g. calling a function or constructor,
// accessing properties, or calling methods.
// The type system is mainly used for two purposes:
//
//     1. to obtain a variable of a certain type when generating code. E.g. the method call code generator will want
//        a variable of type .object() as input because only that can have methods. Also, when generating function
//        calls it can be necessary to find variables of the types that the function expects as arguments. This task
//        is solved by defining a "Is a" relationship between types which can then be used to find suitable variables.
//     2. to determine possible actions that can be performed on a value. E.g. when having a reference to something
//        that is known to be a function, a function call can be performed. Also, the method call code generator will
//        want to know the available methods that it can call on an object, which it can query from the type system.
//
// The following base types are defined:
//     .undefined
//     .integer
//     .bigint
//     .float
//     .boolean
//     .string
//     .regexp
//     .object(ofGroup: G, withProperties: [...], withMethods: [...])
//          something that (potentially) has properties and methods. Can also have a "group", which is simply a string.
//          Groups can e.g. be used to store property and method type information for related objects. See JavaScriptEnvironment.swift for examples.
//     .function(signature: S)
//          something that can be invoked as a function
//     .constructor(signature: S)
//          something that can be invoked as a constructor
//     .iterable
//          something that can be iterated over, e.g. in a for-of loop
//
// Besides the base types, types can be combined to form new types:
//
// A type can be a union, essentially stating that it is one of multiple types. Union types occur in many scenarios, e.g.
// when reassigning a variable, when computing type information following a conditionally executing piece of code, or due to
// imprecise modelling of the environment, e.g. the + operation in JavaScript or return values of various APIs.
//
// Further, a type can also be a merged type, essentially stating that it is *all* of the contained types at the same type.
// As an example of a merged type, think of regular JavaScript functions which can be called but also constructed. On the other hand,
// some JavaScript builtins can be used as a function but not as a constructor or vice versa. As such, it is necessary to be able to
// differentiate between functions and constructors. Strings are another example for merged types. On the one hand they are a primitive
// type expected by various APIs, on the other hand they can be used like an object by accessing properties on them or invoking methods.
// As such, a JavaScript string would be represented as a merge of .string and .object(properties: [...], methods: [...]).
//
// The operations that can be performed on types are then:
//
//    1. Unioning (|)     : this operation on two types expresses that the result can either
//                          be the first or the second type.
//
//    2. Intersecting (&) : this operation computes the intersection, so the common type
//                          between the two argument types. This is used by the "MayBe" query,
//                          answering whether a value could potentially have the given type.
//                          In contrast to the other two operations, itersecting will not create
//                          new types.
//
//    3. Merging (+)      : this operation merges the two argument types into a single type
//                          which is both types. Not all types can be merged, however.
//
// Finally, types define the "is a" (subsumption) relation (>=) which amounts to set inclusion. A type T1 subsumes
// another type T2 if all instances of T2 are also instances of T1. See the .subsumes method for the exact subsumption
// rules. Some examples:
//
//    - .anything, the union of all types, subsumes every other type
//    - .nothing, the empty type, is subsumed by all other types. .nothing occurs e.g. during intersection
//    - .object() subsumes all other object type. I.e. objects with a property "foo" are sill objects
//          e.g. .object() >= .object(withProperties: ["foo"]) and .object() >= .object(withMethods: ["bar"])
//    - .object(withProperties: ["foo"]) subsumes all other object types that also have a property "foo"
//          e.g. .object(withProperties: ["foo"]) >= .object(withProperties: ["foo", "bar"], withMethods: ["baz"])
//    - .object(ofGroup: G) subsumes any other object of group G, but not of a different group
//    - .function([.integer] => .integer) only subsumes other functions with the same signature
//    - .primitive, the union of .integer, .float, and .string, subsumes its parts like every union
//    - .functionAndConstructor(), the merge of .function() and .constructor(), is subsumed by each of its parts like every merged type
//
// Internally, types are implemented as bitsets, with each base type corresponding to one bit.
// Types are then implemented as two bitsets: the definite type, indicating what it definitely
// is, and the possible type, indicating what types it could potentially be.
// A union type is one where the possible type is larger than the definite one.
//
// Examples:
//    .integer                      => definiteType = .integer,          possibleType = .integer
//    .integer | .float             => definiteType = .nothing (0),      possibleType = .integer | .float
//    .string + .object             => definiteType = .string | .object, possibleType = .string | .object
//    .string | (.string + .object) => definiteType = .string,           possibleType = .string | .object
//
// See also Tests/FuzzilliTests/TypeSystemTest.swift for examples of the various properties and features of this type system.
//
public struct ILType: Hashable {

    //
    // Types and type constructors
    //

    /// Corresponds to the undefined type in JavaScript
    public static let undefined = ILType(definiteType: .undefined)

    /// An integer type.
    public static let integer   = ILType(definiteType: .integer)

    /// A bigInt type.
    public static let bigint    = ILType(definiteType: .bigint)

    /// A floating point number.
    public static let float     = ILType(definiteType: .float)

    /// A string.
    public static let string    = ILType(definiteType: .string)

    /// A boolean.
    public static let boolean   = ILType(definiteType: .boolean)

    /// A RegExp
    public static let regexp    = ILType(definiteType: .regexp)

    /// A type that can be iterated over, such as an array or a generator.
    public static let iterable  = ILType(definiteType: .iterable)

    /// The type that subsumes all others.
    public static let anything  = ILType(definiteType: .nothing, possibleType: .anything)

    /// The type that is subsumed by all others.
    public static let nothing   = ILType(definiteType: .nothing, possibleType: .nothing)

    /// A number: either an integer or a float.
    public static let number: ILType = .integer | .float

    /// A primitive: either a number, a string, a boolean, or a bigint.
    public static let primitive: ILType = .integer | .float | .string | .boolean

    /// A "nullish" type ('undefined' or 'null 'in JavaScript). Curently this is effectively an alias for .undefined since we also use .undefined for null.
    public static let nullish: ILType = .undefined

    /// Constructs an object type.
    public static func object(ofGroup group: String? = nil, withProperties properties: [String] = [], withMethods methods: [String] = [], withWasmType wasmExt: WasmTypeExtension? = nil) -> ILType {
        let ext = TypeExtension(group: group, properties: Set(properties), methods: Set(methods), signature: nil, wasmExt: wasmExt)
        return ILType(definiteType: .object, ext: ext)
    }

    /// Constructs an enum type, which is a string with a limited set of allowed values.
    public static func enumeration(ofName name: String, withValues values: [String]) -> ILType {
        let ext = TypeExtension(group: name, properties: Set(values), methods: Set(), signature: nil, wasmExt: nil)
        return ILType(definiteType: .string, ext: ext)
    }

    /// An object for which it is not known what properties or methods it has, if any.
    public static let unknownObject: ILType = .object()

    /// A function.
    public static func function(_ signature: Signature? = nil) -> ILType {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return ILType(definiteType: [.function], ext: ext)
    }

    /// A constructor.
    public static func constructor(_ signature: Signature? = nil) -> ILType {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return ILType(definiteType: [.constructor], ext: ext)
    }

    /// A function and constructor. Same as .function(signature) + .constructor(signature).
    public static func functionAndConstructor(_ signature: Signature? = nil) -> ILType {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return ILType(definiteType: [.function, .constructor], ext: ext)
    }

    // Internal types

    // This type is used to indicate block labels in wasm.
    public static func label(_ parameterTypes: [ILType] = [], isCatch: Bool = false) -> ILType {
        return ILType(definiteType: .label, ext: TypeExtension(group: "WasmLabel", properties: [], methods: [], signature: nil, wasmExt: WasmLabelType(parameterTypes, isCatch: isCatch)))
    }

    public static let anyLabel: ILType = ILType(definiteType: .label, ext: TypeExtension(group: "WasmLabel", properties: [], methods: [], signature: nil, wasmExt: nil))

    /// A label that allows rethrowing the caught exception of a catch block.
    public static let exceptionLabel: ILType = ILType(definiteType: .exceptionLabel)

    public static func wasmMemory(limits: Limits, isShared: Bool = false, isMemory64: Bool = false) -> ILType {
        let wasmMemExt = WasmMemoryType(limits: limits, isShared: isShared, isMemory64: isMemory64)
        return .object(ofGroup: "WasmMemory", withProperties: ["buffer"], withMethods: ["grow"], withWasmType: wasmMemExt)
    }

    public static func wasmTable(wasmTableType: WasmTableType) -> ILType {
        return .object(ofGroup: "WasmTable", withProperties: ["length"], withMethods: ["get", "grow", "set"], withWasmType: wasmTableType)
    }

    //
    // Wasm Types
    //

    public static let wasmi32 = ILType(definiteType: .wasmi32)
    public static let wasmi64 = ILType(definiteType: .wasmi64)
    public static let wasmf32 = ILType(definiteType: .wasmf32)
    public static let wasmf64 = ILType(definiteType: .wasmf64)
    public static let wasmExternRef = ILType(definiteType: .wasmExternRef)
    public static let wasmFuncRef = ILType(definiteType: .wasmFuncRef)
    public static let wasmSimd128 = ILType(definiteType: .wasmSimd128)

    // The union of all primitive wasm types
    public static let wasmPrimitive = .wasmi32 | .wasmi64 | .wasmf32 | .wasmf64 | .wasmExternRef | .wasmFuncRef | .wasmSimd128

    public static let wasmNumericalPrimitive = .wasmi32 | .wasmi64 | .wasmf32 | .wasmf64

    //
    // Type testing
    //

    // Whether it is a function or a constructor (or both).
    public var isCallable: Bool {
        return !definiteType.intersection([.function, .constructor]).isEmpty
    }

    /// Whether this type is a union, i.e can be one of multiple types.
    public var isUnion: Bool {
        return possibleType.isStrictSuperset(of: definiteType)
    }

    /// Whether this type is a merge of multiple base types.
    public var isMerged: Bool {
        return definiteType.rawValue.nonzeroBitCount > 1
    }

    /// The base type of this type.
    /// The base type of objects is .object(), of functions is .function(), of constructors is .constructor() and of callables is .callable(). For unions it can be .nothing. Otherwise it is the type itself.
    public var baseType: ILType {
        return ILType(definiteType: definiteType)
    }

    public static func ==(lhs: ILType, rhs: ILType) -> Bool {
        return lhs.definiteType == rhs.definiteType && lhs.possibleType == rhs.possibleType && lhs.ext == rhs.ext
    }
    public static func !=(lhs: ILType, rhs: ILType) -> Bool {
        return !(lhs == rhs)
    }

    /// Returns true if this type subsumes the given type, i.e. every instance of other is also an instance of this type.
    public func Is(_ other: ILType) -> Bool {
        return other.subsumes(self)
    }

    /// Returns true if this type could be the given type, i.e. the intersection of the two is nonempty.
    public func MayBe(_ other: ILType) -> Bool {
        return self.intersection(with: other) != .nothing
    }

    /// Returns true if this type could be something other than the specified type.
    public func MayNotBe(_ other: ILType) -> Bool {
        return !self.Is(other)
    }

    /// Returns whether this type subsumes the other type.
    ///
    /// A type T1 subsumes another type T2 if all instances of T2 are also instances of T1.
    ///
    /// Subsumption rules:
    ///
    ///  - T >= T
    ///  - except for the above, there is no subsumption relationship between
    ///    primitive types (.undefined, .integer, .float, .string, .boolean)
    ///  - .object(ofGroup: G1, withProperties: P1, withMethods: M1) >= .object(ofGroup: G2, withProperties: P2, withMethods: M2)
    ///        iff (G1 == nil || G1 == G2) && P1 is a subset of P2 && M1 is a subset of M2
    ///  - for .object(..., withWasmType: W) the WasmTypeExtensions have to be equal
    ///  - .function(S1) >= .function(S2) iff S1 = nil || S1 == S2
    ///  - .constructor(S1) >= .constructor(S2) iff S1 = nil || S1 == S2
    ///  - T1 | T2 >= T1 && T1 | T2 >= T2
    ///  - T1 >= T1 + T2 && T2 >= T1 + T2
    ///  - T1 >= T1 & T2 && T2 >= T1  & T2
    public func subsumes(_ other: ILType) -> Bool {
        // Handle trivial cases
        if self == other || other == .nothing {
            return true
        } else if self == .nothing {
            return false
        }

        // A multitype subsumes only multitypes containing at least the same necessary types.
        // E.g. every stringobject (a .string and .object) is a .string (.string subsumes stringobject), but not every .string
        // is also a stringobject (stringobject does not subsume .string).
        guard other.definiteType.isSuperset(of: self.definiteType) else {
            return false
        }

        // If we are a union (so our possible type is larger than the definite type)
        // then check that our possible type is larger than the other possible type.
        // However, there are some special rules to consider:
        //  1. If the other type is a merged type, it is enough if our possible
        //    type is a superset of one of the merged base types.
        if isUnion {
            // Verify that either the other definite type is empty or that there is some overlap between
            // our possible type and the other definite type
            guard other.definiteType.isEmpty || !other.definiteType.intersection(self.possibleType).isEmpty else {
                return false
            }

            // Given the above, we can subtract the other's definite type here from its possible type so that
            // e.g. StringObjects are correctly subsumed by both .string and .object.
            guard self.possibleType.isSuperset(of: other.possibleType.subtracting(other.definiteType)) else {
                return false
            }
        }

        // Base types match. Check extension type now.

        // Fast case.
        if self.ext == nil || self.ext === other.ext {
            return true
        }

        // The groups must either be identical or our group must be nil, in
        // which case we subsume all objects regardless of their group if
        // the properties and methods match (see below).
        guard group == nil || group == other.group else {
            return false
        }

        // Either our type must be a generic callable without a signature, or our signature must subsume the other type's signature.
        guard signature == nil || (other.signature != nil && signature!.subsumes(other.signature!)) else {
            return false
        }

        // The other object can have more properties/methods, but it must
        // have at least the ones we have for us to be a supertype.
        guard properties.isSubset(of: other.properties) else {
            return false
        }
        guard methods.isSubset(of: other.methods) else {
            return false
        }

        // Wasm type extension.
        guard !self.hasWasmTypeInfo || self.wasmType == other.wasmType else {
            return false
        }

        return true
    }

    public static func >=(lhs: ILType, rhs: ILType) -> Bool {
        return lhs.subsumes(rhs)
    }

    public static func <=(lhs: ILType, rhs: ILType) -> Bool {
        return rhs.subsumes(lhs)
    }


    //
    // Access to extended type data
    //

    public var signature: Signature? {
        return ext?.signature
    }

    public var functionSignature: Signature? {
        return Is(.function()) ? ext?.signature : nil
    }

    public var constructorSignature: Signature? {
        return Is(.constructor()) ? ext?.signature : nil
    }

    public var isEnumeration : Bool {
        return Is(.string) && ext != nil
    }

    public var group: String? {
        return ext?.group
    }

    public var hasWasmTypeInfo: Bool {
        return ext?.wasmExt != nil
    }

    public var wasmType: WasmTypeExtension? {
        return ext?.wasmExt
    }

    public var wasmGlobalType: WasmGlobalType? {
        return ext?.wasmExt as? WasmGlobalType
    }

    public var isWasmGlobalType: Bool {
        return wasmGlobalType != nil && ext?.group == "WasmGlobal"
    }

    public var wasmMemoryType: WasmMemoryType? {
        return ext?.wasmExt as? WasmMemoryType
    }

    public var isWasmMemoryType: Bool {
        return wasmMemoryType != nil && ext?.group == "WasmMemory"
    }

    public var wasmTableType: WasmTableType? {
        return ext?.wasmExt as? WasmTableType
    }

    public var isWasmTableType: Bool {
        return wasmTableType != nil && ext?.group == "WasmTable"
    }

    public var wasmTagType: WasmTagType? {
        return wasmType as? WasmTagType
    }

    public var isWasmTagType: Bool {
        return wasmTagType != nil && ext?.group == "WasmTag"
    }

    public var wasmLabelType: WasmLabelType? {
        return wasmType as? WasmLabelType
    }

    public var isWasmLabelType: Bool {
        return wasmTagType != nil
    }

    public var properties: Set<String> {
        return ext?.properties ?? Set()
    }

    public var enumValues: Set<String> {
        return properties
    }

    public var methods: Set<String> {
        return ext?.methods ?? Set()
    }

    public var numProperties: Int {
        return ext?.properties.count ?? 0
    }

    public var numMethods: Int {
        return ext?.methods.count ?? 0
    }

    public func randomProperty() -> String? {
        return ext?.properties.randomElement()
    }

    public func randomMethod() -> String? {
        return ext?.methods.randomElement()
    }


    //
    // Type operations
    //

    /// Forms the union of this and the other type.
    ///
    /// The union of two types is the type that subsumes both: (T1 | T2) >= T1 && (T1 | T2) >= T2.
    ///
    /// Unioning is imprecise (over-approximative). For example, constructing the following union
    ///    let r = .object(withProperties: ["a", "b"]) | .object(withProperties: ["a", "c"])
    /// will result in r == .object(withProperties: ["a"]). Which is wider than it needs to be.
    /// To have a WasmTypeExtension in the union, they have to be equal.
    public func union(with other: ILType) -> ILType {
        // Trivial cases.
        if self == .anything || other == .anything {
            return .anything
        } else if self == .nothing {
            return other
        } else if other == .nothing {
            return self
        }

        // Form a union: the intersection of both definiteTypes and the union of both possibleTypes.
        // If the base types are the same, this will be a (cheap) Nop.
        let definiteType = self.definiteType.intersection(other.definiteType)
        let possibleType = self.possibleType.union(other.possibleType)

        // Fast union case.
        // Identity comparison avoids comparing each property of the class.
        if self.ext === other.ext {
            return ILType(definiteType: definiteType, possibleType: possibleType, ext: self.ext)
        }

        // Slow union case: need to union (or really widen) the extension. For properties and methods
        // that means finding the set of shared properties and methods, which is imprecise but correct.
        let commonProperties = self.properties.intersection(other.properties)
        let commonMethods = self.methods.intersection(other.methods)
        let signature = self.signature == other.signature ? self.signature : nil        // TODO: this is overly coarse, we could also see if one signature subsumes the other, then take the subsuming one.
        let group = self.group == other.group ? self.group : nil
        let wasmExt = self.wasmType == other.wasmType ? self.wasmType : nil

        return ILType(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: commonProperties, methods: commonMethods, signature: signature, wasmExt: wasmExt))
    }

    public static func |(lhs: ILType, rhs: ILType) -> ILType {
        return lhs.union(with: rhs)
    }

    public static func |=(lhs: inout ILType, rhs: ILType) {
        lhs = lhs | rhs
    }

    /// Forms the intersection of the two types.
    ///
    /// The intersection of T1 and T2 is the subtype that is contained in both T1 and T2.
    /// The result of this can be .nothing.
    public func intersection(with other: ILType) -> ILType {
        // The definite types must have a subset relationship.
        // E.g. a StringObject intersected with a String is a StringObject,
        // but a StringObject intersected with an IntegerObject is .nothing.
        let definiteType = self.definiteType.union(other.definiteType)
        guard definiteType == self.definiteType || definiteType == other.definiteType else {
            return .nothing
        }

        // Now intersect the possible type.
        var possibleType = self.possibleType.intersection(other.possibleType)
        guard !possibleType.isEmpty else {
            return .nothing
        }

        // E.g. the intersection of a StringObject and a String is a StringObject. As such, here we have to
        // "add back" the definite type to the possible type (which at this point would just be String).
        possibleType.formUnion(definiteType)

        // Fast intersection case.
        // Identity comparison avoids comparing each property of the class.
        if self.ext === other.ext {
            return ILType(definiteType: definiteType, possibleType: possibleType, ext: self.ext)
        }

        // Slow intersection case: intersect the type extension.
        //
        // The intersection between an object with properties ["foo"] and an
        // object with properties ["foo", "bar"] is an object with properties
        // ["foo", "bar"], as that is the "smaller" type, subsumed by the first.
        // The same rules apply for methods.
        let properties = self.properties.union(other.properties)
        guard properties.count == max(self.numProperties, other.numProperties) else {
            return .nothing
        }

        let methods = self.methods.union(other.methods)
        guard methods.count == max(self.numMethods, other.numMethods) else {
            return .nothing
        }

        // Groups must either be equal or one of them must be nil, in which case
        // the result will have the non-nil group as that is again the smaller type.
        guard self.group == nil || other.group == nil || self.group == other.group else {
            return .nothing
        }
        let group = self.group == nil ? other.group : self.group

        // For signatures we take a shortcut: if one signature subsumes the other, then the intersection
        // must be the subsumed signature. Additionally, we know that if there is an intersection, the
        // return value must be the intersection of the return values, so we can compute that up-front.
        let returnValue = (self.signature?.outputType ?? .anything) & (other.signature?.outputType ?? .anything)
        guard returnValue != .nothing else {
            return .nothing
        }
        let ourSignature = self.signature?.replacingOutputType(with: returnValue)
        let otherSignature = other.signature?.replacingOutputType(with: returnValue)
        let signature: Signature?
        if ourSignature == nil || (otherSignature != nil && ourSignature!.subsumes(otherSignature!)) {
            signature = otherSignature
        } else if otherSignature == nil || (ourSignature != nil && otherSignature!.subsumes(ourSignature!)) {
            signature = ourSignature
        } else {
            return .nothing
        }

        // Handling Wasm type extension.
        var wasmExt: WasmTypeExtension?
        if self.wasmType == other.wasmType {
            wasmExt = self.wasmType
        } else {
            return .nothing
        }

        return ILType(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: properties, methods: methods, signature: signature, wasmExt: wasmExt))
    }

    public static func &(lhs: ILType, rhs: ILType) -> ILType {
        return lhs.intersection(with: rhs)
    }

    public static func &=(lhs: inout ILType, rhs: ILType) {
        lhs = lhs & rhs
    }

    /// Returns whether this type can be merged with the other type.
    public func canMerge(with other: ILType) -> Bool {
        // Merging of unions is not allowed, mainly because it would be ambiguous in our internal representation and is not needed in practice.
        guard !self.isUnion && !other.isUnion else {
            return false
        }

        // Merging of callables with different signatures is not allowed.
        guard self.signature == nil || other.signature == nil || self.signature == other.signature else {
            return false
        }

        // Merging objects of different groups is not allowed.
        guard self.group == nil || other.group == nil || self.group == other.group else {
            return false
        }

        // Merging with .nothing is not supported as the result would have to be subsumed by .nothing but be != .nothing which is not allowed.
        guard self != .nothing && other != .nothing else {
            return false
        }

        return true
    }

    /// Merges this type with the other.
    ///
    /// Merging two types results in a new type that is both of its parts at the same type (i.e. is subsumed by both).
    /// Unlike intersection, this creates a new type if necessary and will never result in .nothing.
    ///
    /// Not all types can be merged, see canMerge.
    public func merging(with other: ILType) -> ILType {
        assert(canMerge(with: other))

        let definiteType = self.definiteType.union(other.definiteType)
        let possibleType = self.possibleType.union(other.possibleType)

        // Signatures must be equal here or one of them is nil (see canMerge)
        let signature = self.signature ?? other.signature

        // Same is true for the group name
        let group = self.group ?? other.group

        let ext = TypeExtension(group: group, properties: self.properties.union(other.properties), methods: self.methods.union(other.methods), signature: signature)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: ext)
    }

    public static func +(lhs: ILType, rhs: ILType) -> ILType {
        return lhs.merging(with: rhs)
    }

    public static func +=(lhs: inout ILType, rhs: ILType) {
        lhs = lhs.merging(with: rhs)
    }

    //
    // Type transitioning
    //
    // TODO cache these in some kind of type transition table data structure?
    //

    /// Returns a new type that represents this type with the added property.
    public func adding(property: String) -> ILType {
        guard Is(.object()) else {
            return self
        }
        var newProperties = properties
        newProperties.insert(property)
        let newExt = TypeExtension(group: group, properties: newProperties, methods: methods, signature: signature, wasmExt: wasmType)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Adds a property to this type.
    public mutating func add(property: String) {
        self = self.adding(property: property)
    }

    /// Returns a new ObjectType that represents this type without the removed property.
    public func removing(property: String) -> ILType {
        guard Is(.object()) else {
            return self
        }
        var newProperties = properties
        newProperties.remove(property)
        let newExt = TypeExtension(group: group, properties: newProperties, methods: methods, signature: signature, wasmExt: wasmType)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Returns a new ObjectType that represents this type with the added property.
    public func adding(method: String) -> ILType {
        guard Is(.object()) else {
            return self
        }
        var newMethods = methods
        newMethods.insert(method)
        let newExt = TypeExtension(group: group, properties: properties, methods: newMethods, signature: signature, wasmExt: wasmType)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Adds a method to this type.
    public mutating func add(method: String) {
        self = self.adding(method: method)
    }

    /// Returns a new ObjectType that represents this type without the removed property.
    public func removing(method: String) -> ILType {
        guard Is(.object()) else {
            return self
        }
        var newMethods = methods
        newMethods.remove(method)
        let newExt = TypeExtension(group: group, properties: properties, methods: newMethods, signature: signature, wasmExt: wasmType)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    public func settingSignature(to signature: Signature) -> ILType {
        guard Is(.function() | .constructor()) else {
            return self
        }
        let newExt = TypeExtension(group: group, properties: properties, methods: methods, signature: signature)
        return ILType(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    //
    // Type implementation internals
    //

    /// The base type is simply a bitset of (potentially multiple) basic types.
    private let definiteType: BaseType

    /// The possible type is always a superset of the necessary type.
    private let possibleType: BaseType

    /// The type extensions contains properties, methods, function signatures, etc.
    private let ext: TypeExtension?

    /// Types must be constructed through one of the public constructors.
    private init(definiteType: BaseType, possibleType: BaseType? = nil, ext: TypeExtension? = nil) {
        self.definiteType = definiteType
        self.possibleType = possibleType ?? definiteType
        self.ext = ext
        assert(self.possibleType.contains(self.definiteType))
    }
}

extension ILType: CustomStringConvertible {
    public func format(abbreviate: Bool) -> String {
        // Test for well-known union types and .nothing
        if self == .anything {
            return ".anything"
        } else if self == .nothing {
            return ".nothing"
        } else if self == .primitive {
            return ".primitive"
        } else if self == .number {
            return ".number"
        }

        if isUnion {
            // Unions with non-zero necessary types can only
            // occur if merged types are unioned.
            var mergedTypes: [ILType] = []
            for b in BaseType.allBaseTypes {
                if self.definiteType.contains(b) {
                    let subtype = ILType(definiteType: b, ext: ext)
                    mergedTypes.append(subtype)
                }
            }

            var parts: [String] = []
            for b in BaseType.allBaseTypes {
                if self.possibleType.contains(b) && !self.definiteType.contains(b) {
                    let subtype = ILType(definiteType: b, ext: ext)
                    parts.append(mergedTypes.reduce(subtype, +).format(abbreviate: abbreviate))
                }
            }

            return parts.joined(separator: " | ")
        }

        // Must now either be a simple type or a merged type

        // Handle simple types
        switch definiteType {
        case .undefined:
            return ".undefined"
        case .integer:
            return ".integer"
        case .bigint:
            return ".bigint"
        case .regexp:
            return ".regexp"
        case .float:
            return ".float"
        case .string:
            return ".string"
        case .boolean:
            return ".boolean"
        case .iterable:
            return ".iterable"
        case .object:
            var params: [String] = []
            if let group = group {
                params.append("ofGroup: \(group)")
            }
            if !properties.isEmpty {
                if abbreviate && properties.count > 5 {
                    let selection = properties.prefix(3).map { "\"\($0)\"" }
                    params.append("withProperties: [\(selection.joined(separator: ", ")), ...]")
                } else {
                    params.append("withProperties: \(properties)")
                }
            }
            if !methods.isEmpty {
                if abbreviate && methods.count > 5 {
                    let selection = methods.prefix(3).map { "\"\($0)\"" }
                    params.append("withMethods: [\(selection.joined(separator: ", ")), ...]")
                } else {
                    params.append("withMethods: \(methods)")
                }
            }
            return ".object(\(params.joined(separator: ", ")))"
        case .function:
            if let signature = functionSignature {
                return ".function(\(signature.format(abbreviate: abbreviate)))"
            } else {
                return ".function()"
            }
        case .constructor:
            if let signature = constructorSignature {
                return ".constructor(\(signature.format(abbreviate: abbreviate)))"
            } else {
                return ".constructor()"
            }
        case .wasmi32:
            return ".wasmi32"
        case .wasmi64:
            return ".wasmi64"
        case .wasmf32:
            return ".wasmf32"
        case .wasmf64:
            return ".wasmf64"
        case .wasmExternRef:
            return ".wasmExternRef"
        case .wasmFuncRef:
            return ".wasmFuncRef"
        case .wasmSimd128:
            return ".wasmSimd128"
        case .label:
            return ".label"
        default:
            break
        }

        // Must be a merged type

        if isMerged {
            var parts: [String] = []
            for b in BaseType.allBaseTypes {
                if self.definiteType.contains(b) {
                    let subtype = ILType(definiteType: b, ext: ext)
                    parts.append(subtype.format(abbreviate: abbreviate))
                }
            }
            return parts.joined(separator: " + ")
        }

        fatalError("Unhandled type")
    }

    public var description: String {
        return format(abbreviate: false)
    }

    public var abbreviated: String {
        return format(abbreviate: true)
    }
}

struct BaseType: OptionSet, Hashable {
    let rawValue: UInt32

    // Base types
    static let nothing     = BaseType([])
    static let undefined   = BaseType(rawValue: 1 << 0)
    static let integer     = BaseType(rawValue: 1 << 1)
    static let bigint      = BaseType(rawValue: 1 << 2)
    static let float       = BaseType(rawValue: 1 << 3)
    static let boolean     = BaseType(rawValue: 1 << 4)
    static let string      = BaseType(rawValue: 1 << 5)
    static let regexp      = BaseType(rawValue: 1 << 6)
    static let object      = BaseType(rawValue: 1 << 7)
    static let function    = BaseType(rawValue: 1 << 8)
    static let constructor = BaseType(rawValue: 1 << 9)
    static let iterable    = BaseType(rawValue: 1 << 10)

    // Wasm Types
    static let wasmi32     = BaseType(rawValue: 1 << 11)
    static let wasmi64     = BaseType(rawValue: 1 << 12)
    static let wasmf32     = BaseType(rawValue: 1 << 13)
    static let wasmf64     = BaseType(rawValue: 1 << 14)
    static let wasmExternRef = BaseType(rawValue: 1 << 15)
    static let wasmFuncRef = BaseType(rawValue: 1 << 16)

    // These are wasm internal types, these are never lifted as such and are only used to glue together dataflow in wasm.
    static let label       = BaseType(rawValue: 1 << 17)
    // Any catch block exposes such a label now to rethrow the exception caught by that catch.
    // Note that in wasm the label is actually the try block's label but as rethrows are only possible inside a catch
    // block, semantically having a label on the catch makes more sense.
    static let exceptionLabel = BaseType(rawValue: 1 << 18)
    // This is a reference to a table, which can be passed around to table instructions
    // The lifter will resolve this to the proper index when lifting.
    static let wasmSimd128    = BaseType(rawValue: 1 << 19)

    static let anything    = BaseType([.undefined, .integer, .float, .string, .boolean, .object, .function, .constructor, .bigint, .regexp, .iterable])

    static let allBaseTypes: [BaseType] = [.undefined, .integer, .float, .string, .boolean, .object, .function, .constructor, .bigint, .regexp, .iterable]
}

class TypeExtension: Hashable {
    // Properties and methods. Will only be populated if MayBe(.object()) is true.
    let properties: Set<String>
    let methods: Set<String>

    // The group name. Basically each group is its own sub type of the object type.
    // (For now), there is no subtyping for group: if two objects have a different
    // group then there is no subsumption relationship between them.
    let group: String?

    // The function signature. Will only be != nil if isFunction or isConstructor is true.
    let signature: Signature?

    // Wasm specific properties for Wasm types.
    let wasmExt: WasmTypeExtension?

    init?(group: String? = nil, properties: Set<String>, methods: Set<String>, signature: Signature?, wasmExt: WasmTypeExtension? = nil) {
        if group == nil && properties.isEmpty && methods.isEmpty && signature == nil && wasmExt == nil {
            return nil
        }

        self.properties = properties
        self.methods = methods
        self.group = group
        self.signature = signature
        self.wasmExt = wasmExt
    }

    static func ==(lhs: TypeExtension, rhs: TypeExtension) -> Bool {
        return lhs.properties == rhs.properties && lhs.methods == rhs.methods && lhs.group == rhs.group && lhs.signature == rhs.signature && lhs.wasmExt == rhs.wasmExt
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(group)
        hasher.combine(properties)
        hasher.combine(methods)
        hasher.combine(signature)
        hasher.combine(wasmExt)
    }
}

// Base class that all Wasm types wih TypeExtension should inherit from.
public class WasmTypeExtension: Hashable {

    public static func ==(lhs: WasmTypeExtension, rhs: WasmTypeExtension) -> Bool {
        lhs.isEqual(to: rhs)
    }

    func isEqual(to other: WasmTypeExtension) -> Bool {
        fatalError("unreachable")
    }

    public func hash(into hasher: inout Hasher) {
        fatalError("unreachable")
    }
}

public class WasmGlobalType: WasmTypeExtension {

    let valueType: ILType
    let isMutable: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmGlobalType else { return false }
        return self.valueType == other.valueType && self.isMutable == other.isMutable
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(valueType)
        hasher.combine(isMutable)
    }

    init(valueType: ILType, isMutable: Bool) {
        self.valueType = valueType
        self.isMutable = isMutable
    }
}

public class WasmTagType: WasmTypeExtension {
    public let parameters: ParameterList
    /// Flag whether the tag is the WebAssembly.JSTag.
    public let isJSTag: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmTagType else { return false }
        return self.parameters == other.parameters && self.isJSTag == other.isJSTag
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(parameters)
        hasher.combine(isJSTag)
    }

    init(_ parameters: ParameterList, isJSTag: Bool = false) {
        self.parameters = parameters
        self.isJSTag = isJSTag
    }
}

public class WasmLabelType: WasmTypeExtension {
    // The parameter types for the label, meaning the types of the values that need to be provided
    // when branching to this label. This is the list of result types for all wasm blocks excluding
    // the loop for which the parameter types are the parameter types of the block. (This is caused
    // by the branch instruction branching to the loop header and not the loop end.)
    let parameters: [ILType]
    let isCatch: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmLabelType else { return false }
        return self.parameters == other.parameters && self.isCatch == other.isCatch
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(parameters)
        hasher.combine(isCatch)
    }

    init(_ parameters: [ILType], isCatch: Bool) {
        self.parameters = parameters
        self.isCatch = isCatch
    }
}

public struct Limits: Hashable {
    var min: Int
    var max: Int?
}

public class WasmMemoryType: WasmTypeExtension {
    let limits: Limits
    let isShared: Bool
    let isMemory64: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmMemoryType else { return false }
        return self.limits == other.limits && self.isShared == other.isShared && self.isMemory64 == other.isMemory64
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(limits)
        hasher.combine(isShared)
        hasher.combine(isMemory64)
    }

    init(limits: Limits, isShared: Bool = false, isMemory64: Bool = false) {
        self.limits = limits
        self.isShared = isShared
        self.isMemory64 = isMemory64
    }
}

public class WasmTableType: WasmTypeExtension {
    let elementType: ILType
    let limits: Limits

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmTableType else { return false }
        return self.elementType == other.elementType && self.limits == other.limits
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(elementType)
        hasher.combine(limits)
    }

    init(elementType: ILType, limits: Limits) {
        // TODO(manoskouk): Assert table type is reference type.
        self.elementType = elementType
        self.limits = limits
    }
}

// Represents one parameter of a function signature.
public enum Parameter: Hashable {
    case plain(ILType)
    case opt(ILType)
    case rest(ILType)

    // Convenience constructors for plain parameters.
    public static let integer   = Parameter.plain(.integer)
    public static let bigint    = Parameter.plain(.bigint)
    public static let float     = Parameter.plain(.float)
    public static let string    = Parameter.plain(.string)
    public static let boolean   = Parameter.plain(.boolean)
    public static let regexp    = Parameter.plain(.regexp)
    public static let iterable  = Parameter.plain(.iterable)
    public static let anything  = Parameter.plain(.anything)
    public static let number    = Parameter.plain(.number)
    public static let primitive = Parameter.plain(.primitive)
    public static let wasmi32   = Parameter.plain(.wasmi32)
    public static let wasmi64   = Parameter.plain(.wasmi64)
    public static let wasmf32   = Parameter.plain(.wasmf32)
    public static let wasmf64   = Parameter.plain(.wasmf64)
    public static let wasmExternRef   = Parameter.plain(.wasmExternRef)
    public static func object(ofGroup group: String? = nil, withProperties properties: [String] = [], withMethods methods: [String] = []) -> Parameter {
        return Parameter.plain(.object(ofGroup: group, withProperties: properties, withMethods: methods))
    }
    public static func function(_ signature: Signature? = nil) -> Parameter {
        return Parameter.plain(.function(signature))
    }
    public static func constructor(_ signature: Signature? = nil) -> Parameter {
        return Parameter.plain(.constructor(signature))
    }

    // Convenience constructor for parameters with union types.
    public static func oneof(_ t1: ILType, _ t2: ILType) -> Parameter {
        return .plain(t1 | t2)
    }

    public var isOptionalParameter: Bool {
        if case .opt(_) = self { return true } else { return false }
    }

    public var isRestParameter: Bool {
        if case .rest(_) = self { return true } else { return false }
    }

    fileprivate func format(abbreviate: Bool) -> String {
        switch self {
            case .plain(let t):
                return t.format(abbreviate: abbreviate)
            case .opt(let t):
                return ".opt(\(t.format(abbreviate: abbreviate)))"
            case .rest(let t):
                return "\(t.format(abbreviate: abbreviate))..."
        }
    }
}

// A ParameterList represents all parameters in a function signature.
public typealias ParameterList = Array<Parameter>
extension ParameterList {
    // Construct a generic parameter list with `numParameters` parameters of type `.anything`
    init(numParameters: Int, hasRestParam: Bool) {
        assert(!hasRestParam || numParameters > 0)
        self.init(repeating: .anything, count: numParameters)
        if hasRestParam {
            self[endIndex - 1] = .anything...
        }
    }

    public var hasRestParameter: Bool {
        return last?.isRestParameter ?? false
    }

    func areValid() -> Bool {
        var sawOptionals = false
        for (i, p) in self.enumerated() {
            switch p {
            case .rest(let t):
                assert(!t.Is(.nothing))
                // Only the last parameter can be a rest parameter.
                guard i == count - 1 else { return false }
            case .opt(let t):
                assert(!t.Is(.nothing))
                sawOptionals = true
            case .plain(let t):
                assert(!t.Is(.nothing))
                // Optional parameters must not be followed by regular parameters.
                guard !sawOptionals else { return false }
            }
        }
        return true
    }

    /// Returns an array of `ILType`s. Requires the parameters to be plain parameters only.
    func convertPlainToILTypes() -> [ILType] {
        return map { param in
            switch (param) {
                case .plain(let plain):
                    return plain
                default:
                    fatalError("Unexpected non-plain parameter \(param)")
            }
        }
    }
}

// The signature of a (builtin or generated) function or method as seen by the caller.
// This is in contrast to the Parameters struct which essentially contains the callee-side information, most importantly the number of parameters.
// The main difference between the two "views" of a function is that the Signature contains type information
// for every parameter, which is inferred by the JSTyper (for example from the static environment model).
// The callee-side Parameters does not contain any type information as any such information would quickly become
// invalid due to mutations to the function (or its callers), but also because type information cannot generally be
// produced by e.g. a JavaScript -> FuzzIL compiler.
public struct Signature: Hashable, CustomStringConvertible {
    // A function signature consists of a list of parameters and an output type.
    public let parameters: ParameterList
    public let outputType: ILType

    public var numParameters: Int {
        return parameters.count
    }

    public var hasRestParameter: Bool {
        return parameters.hasRestParameter
    }

    public func format(abbreviate: Bool) -> String {
        let inputs = parameters.map({ $0.format(abbreviate: abbreviate) }).joined(separator: ", ")
        return "[\(inputs)] => \(outputType.format(abbreviate: abbreviate))"
    }

    public var description: String {
        return format(abbreviate: false)
    }

    public init(expects parameters: ParameterList, returns returnType: ILType) {
        assert(parameters.areValid())
        self.parameters = parameters
        self.outputType = returnType
    }

    // Constructs a function with N parameters of any type and returning .anything.
    public init(withParameterCount numParameters: Int, hasRestParam: Bool = false) {
        let parameters = ParameterList(numParameters: numParameters, hasRestParam: hasRestParam)
        self.init(expects: parameters, returns: .anything)
    }

    // Returns a new signature with the output type replaced with the given type.
    public func replacingOutputType(with newOutputType: ILType) -> Signature {
        return parameters => newOutputType
    }

    // The most generic function signature: varargs function returning .anything
    public static let forUnknownFunction = [.anything...] => .anything

    // Signature subsumption.
    //
    // Currently we ignore return values and just check:
    //   - that this signature has the same number of parameters or has more parameters
    //   - that all our parameter types are subsumed by their counterpart in the other signature
    //   - that rest- and optional parameters are handled appropriately
    //
    // The subsumption rules make sure then when requesting a callable with our signature,
    // and our signature subsumes the other signature, then using a callable with the other
    // signature works fine. In other words, the other signature is an instance of us.
    //
    // Some examples:
    //   [.integer, .boolean] => .undefined subsumes [.anything] => .undefined
    //   [.integer] => .undefined subsumes [.number] => .undefined
    //   [.anything] => .undefined *only* subsumes [.anything] => undefined or [] => .undefined
    //   [.number] => .undefined does *not* subsume [.integer] => .undefined
    public func subsumes(_ other: Signature) -> Bool {
        // First, check that the return types are compatible:
        guard self.outputType.subsumes(other.outputType) else {
            return false
        }

        // Some pre-processing of the parameters to deal with optional- and rest parameters.
        var ourParameters = parameters
        var otherParameters = other.parameters

        // Optional paramaters behave very similar to rest parameters, see below, except
        // that they can only be expanded once.
        for (i, p) in ourParameters.enumerated() {
            guard case .opt(let paramType) = p else { continue }
            // If this is an optional parameter, then the other signature must also have an
            // optional or a rest parameter at the same position, or none at all.
            if otherParameters.count > i, case .plain(_) = otherParameters[i] { return false }
            // In that case, the parameter types must be compatible. So convert this parameter
            // to a plain one so that the code at the end of this function ensures that they
            // are compatible.
            ourParameters[i] = .plain(paramType)
        }
        for (i, p) in otherParameters.enumerated() {
            guard case .opt(let paramType) = p else { continue }
            if ourParameters.count > i || ourParameters.hasRestParameter {
                // There is a corresponding parameter in our signature, so the types must be compatible
                otherParameters[i] = .plain(paramType)
            } else {
                // Our signature is shorter, so this optional parameter (and all following ones) won't
                // be used.
                otherParameters.removeLast(otherParameters.count - i)
                break
            }
        }

        // If the other signature has a rest parameter, then we must expand it until every one
        // of our parameters has a corresponding parameter in the other signature. For example,
        // if we are [.integer, .string, .float], and the other has [.number...], we must
        // expand that to [.number, .number, .number] and then check the parameter subsumption.
        // (in this example we don't subsume the other signature since the 2nd parameter is
        // incompatible).
        if case .rest(let paramType) = otherParameters.last {
            assert(otherParameters.hasRestParameter)
            otherParameters.removeLast()
            while otherParameters.count < ourParameters.count {
                otherParameters.append(.plain(paramType))
            }
        }
        // If we have a rest parameter:
        //  - If the other signature did not have a rest parameter, we remove our rest parameter
        //    since we must assume that no argument will be specified for it. In that case, if
        //    the other signature expects a parameter at that position, we will not subsume it.
        //  - If the other signature did have a rest parameter, that parameter will now have
        //    been replaced with a single parameter of the same type. In that case, we must
        //    also convert our rest parameter to a plain parameter so that the code below
        //    then ensures that the rest parameters are compatible.
        //
        // For example:
        // [.anything...] => .undefined does *not* subsume [.anything] => .undefined
        // because the first function may be legitimately called with no arguments.
        // [...integer] => .undefined subsumes [.anything...] => .undefined
        // but not the other way around.
        if case .rest(let paramType) = ourParameters.last {
            ourParameters.removeLast()
            if other.hasRestParameter {
                ourParameters.append(.plain(paramType))
            }
        }
        assert(!ourParameters.hasRestParameter && !otherParameters.hasRestParameter)

        // If we have fewer parameters than the other signature, then we cannot subsume it because
        // we must be able to call a function with the other signature in our stead, but in that
        // case the other function would receive too few parameters.
        // The other direction works though: it's ok to pass more arguments than a function has parameters.
        guard ourParameters.count >= otherParameters.count else {
            return false
        }

        // Finally, check that every one of our parameters is subsumed by the corresponding parameter
        // in the other signature.
        for (p1, p2) in zip(ourParameters, otherParameters) {
            switch (p1, p2) {
            case (.plain(let t1), .plain(let t2)):
                guard t2.subsumes(t1) else { return false }
            default:
                fatalError("All parameters must by now have been converted to plain parameters")
            }
        }

        return true
    }

    public static func >=(lhs: Signature, rhs: Signature) -> Bool {
        return lhs.subsumes(rhs)
    }

    public static func <=(lhs: Signature, rhs: Signature) -> Bool {
        return rhs.subsumes(lhs)
    }
}

/// The convenience postfix operator ... is used to construct rest parameters.
postfix operator ...
public postfix func ... (t: ILType) -> Parameter {
    assert(t != .nothing)
    return .rest(t)
}

/// The convenience infix operator => is used to construct function signatures.
infix operator =>: AdditionPrecedence
public func => (parameters: [Parameter], returnType: ILType) -> Signature {
    return Signature(expects: ParameterList(parameters), returns: returnType)
}
