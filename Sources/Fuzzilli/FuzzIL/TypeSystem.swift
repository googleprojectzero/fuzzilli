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
//        Notice that the relationship is not reflexive. Think of it as "Is contained by" or <=.
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
//    - .jsAnything, the union of all js types, subsumes every other type in js
//    - .wasmAnything, the union of all wasm types, subsumes every other type in wasm.
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

    /// The type that subsumes all others (in js).
    public static let jsAnything  = ILType(definiteType: .nothing, possibleType: .jsAnything)

    /// The type that subsumes all others (in wasm).
    public static let wasmAnything  = ILType(definiteType: .nothing, possibleType: .wasmAnything)

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

    /// Constructs an named string: this is a string that typically has some complex format.
    ///
    /// Most code will treat these as strings, but the JavaScriptEnvironment can register
    /// producingGenerators for them so they can be generated more intelligently.
    public static func namedString(ofName name: String) -> ILType {
        let ext = TypeExtension(group: name, properties: Set(), methods: Set(), signature: nil, wasmExt: nil)
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

    /// An unbound function. This is a function with this === null which requires to get a this
    /// bound (e.g. via .bind(), .call() or .apply()).
    public static func unboundFunction(_ signature: Signature? = nil, receiver: ILType? = nil) -> ILType {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature, receiver: receiver)
        return ILType(definiteType: [.unboundFunction], ext: ext)
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
        return .object(ofGroup: "WasmMemory", withProperties: ["buffer"], withMethods: ["grow", "toResizableBuffer", "toFixedLengthBuffer"], withWasmType: wasmMemExt)
    }

    public static func  wasmDataSegment(segmentLength: Int? = nil) -> ILType {
        let maybeWasmExtention = segmentLength.map { WasmDataSegmentType(segmentLength: $0) }
        let typeExtension = TypeExtension(group: "WasmDataSegment", properties: Set(), methods: Set(), signature: nil, wasmExt: maybeWasmExtention)
        return ILType(definiteType: .wasmDataSegment, ext: typeExtension)
    }

    public static func  wasmElementSegment(segmentLength: Int? = nil) -> ILType {
        let maybeWasmExtention = segmentLength.map { WasmElementSegmentType(segmentLength: $0) }
        let typeExtension = TypeExtension(group: "WasmElementSegment", properties: Set(), methods: Set(), signature: nil, wasmExt: maybeWasmExtention)
        return ILType(definiteType: .wasmElementSegment, ext: typeExtension)
    }

    public static func wasmTable(wasmTableType: WasmTableType) -> ILType {
        return .object(ofGroup: "WasmTable", withProperties: ["length"], withMethods: ["get", "grow", "set"], withWasmType: wasmTableType)
    }

    public static func wasmFunctionDef(_ signature: WasmSignature? = nil) -> ILType {
        return ILType(definiteType: .wasmFunctionDef,
            ext: TypeExtension(properties: Set(), methods: Set(), signature: nil, wasmExt: WasmFunctionDefinition(signature)))
    }

    //
    // Wasm Types
    //

    public static let wasmPackedI8 = ILType(definiteType: .wasmPackedI8)
    public static let wasmPackedI16 = ILType(definiteType: .wasmPackedI16)
    public static let wasmi32 = ILType(definiteType: .wasmi32)
    public static let wasmi64 = ILType(definiteType: .wasmi64)
    public static let wasmf32 = ILType(definiteType: .wasmf32)
    public static let wasmf64 = ILType(definiteType: .wasmf64)
    public static let wasmExternRef = ILType.wasmRef(.Abstract(.WasmExtern), nullability: true)
    public static let wasmRefExtern = ILType.wasmRef(.Abstract(.WasmExtern), nullability: false)
    public static let wasmFuncRef = ILType.wasmRef(.Abstract(.WasmFunc), nullability: true)
    public static let wasmExnRef = ILType.wasmRef(.Abstract(.WasmExn), nullability: true)
    public static let wasmI31Ref = ILType.wasmRef(.Abstract(.WasmI31), nullability: true)
    public static let wasmRefI31 = ILType.wasmRef(.Abstract(.WasmI31), nullability: false)
    public static let wasmAnyRef = ILType.wasmRef(.Abstract(.WasmAny), nullability: true)
    public static let wasmRefAny = ILType.wasmRef(.Abstract(.WasmAny), nullability: false)
    public static let wasmNullRef = ILType.wasmRef(.Abstract(.WasmNone), nullability: true)
    public static let wasmNullExternRef = ILType.wasmRef(.Abstract(.WasmNoExtern), nullability: true)
    public static let wasmNullFuncRef = ILType.wasmRef(.Abstract(.WasmNoFunc), nullability: true)
    public static let wasmEqRef = ILType.wasmRef(.Abstract(.WasmEq), nullability: true)
    public static let wasmStructRef = ILType.wasmRef(.Abstract(.WasmStruct), nullability: true)
    public static let wasmArrayRef = ILType.wasmRef(.Abstract(.WasmArray), nullability: true)
    public static let wasmSimd128 = ILType(definiteType: .wasmSimd128)
    public static let wasmGenericRef = ILType(definiteType: .wasmRef)

    static func wasmTypeDef(description: WasmTypeDescription? = nil) -> ILType {
        let typeDef = WasmTypeDefinition()
        typeDef.description = description
        return ILType(definiteType: .wasmTypeDef, ext: TypeExtension(
            properties: [], methods: [], signature: nil, wasmExt: typeDef))
    }

    static func wasmSelfReference() -> ILType {
        wasmTypeDef(description: .selfReference)
    }

    static func wasmRef(_ kind: WasmReferenceType.Kind, nullability: Bool) -> ILType {
        return ILType(definiteType: .wasmRef, ext: TypeExtension(
            properties: [], methods: [], signature: nil,
            wasmExt: WasmReferenceType(kind, nullability: nullability)))
    }

    static func wasmIndexRef(_ desc: WasmTypeDescription, nullability: Bool) -> ILType {
        return wasmRef(.Index(UnownedWasmTypeDescription(desc)), nullability: nullability)
    }

    // The union of all primitive wasm types
    public static let wasmPrimitive = .wasmi32 | .wasmi64 | .wasmf32 | .wasmf64 | .wasmExternRef | .wasmFuncRef | .wasmI31Ref | .wasmSimd128 | .wasmGenericRef

    public static let wasmNumericalPrimitive = .wasmi32 | .wasmi64 | .wasmf32 | .wasmf64

    public static let anyNonNullableIndexRef = wasmRef(.Index(), nullability: false)

    //
    // Type testing
    //

    // Whether it is a function or a constructor (or both).
    public var isCallable: Bool {
        return !definiteType.intersection([.function, .constructor, .unboundFunction]).isEmpty
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

    /// Returns true if other type subsumes this type, i.e. every instance of this is also an instance of other type.
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
        // Alternatively, if the groups match by prefix for specific custom
        // tracked ObjectGroups, they also subsume such that we can interchange
        // them in JS for efficient fuzzing, i.e. object0 and object1 can be
        // considered to have the same group, we then proceed with the other checks for subsumption.
        guard group == nil || group == other.group || groupsMatchByPrefix(group, other.group) else {
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

        guard receiver == nil || (other.receiver != nil && receiver!.subsumes(other.receiver!)) else {
            return false
        }

        // Wasm type extension.
        guard !self.hasWasmTypeInfo || (other.hasWasmTypeInfo
            && self.wasmType!.subsumes(other.wasmType!)) else {
            return false
        }

        return true
    }

    // This helps with the custom object groups.
    // This basically says that even though objects might have program local object groups, they can still subsume, if they belong to the same "subclass" indicated by having the same prefix (with a different number as a suffix).
    // These should match the custom object group types in JSTyper.swift
    public func groupsMatchByPrefix(_ groupLhs: String?, _ groupRhs: String?) -> Bool {
        guard let lhs = groupLhs else {
            return false
        }
        guard let rhs = groupRhs else {
            return false
        }

        // If you add a new custom object group, please check the logic below.
        // Make sure that the groups themselves are not prefixes.
        assert(JSTyper.ObjectGroupManager.ObjectGroupType.allCases == [.wasmModule, .wasmExports, .objectLiteral, .jsClass])

        let objectGroupTypes = ["_fuzz_Object", "_fuzz_WasmModule", "_fuzz_WasmExports", "_fuzz_Class", "_fuzz_Constructor"]

        for groupType in objectGroupTypes {
            if rhs.hasPrefix(groupType) && lhs.hasPrefix(groupType) {
                // Check that they differ only in a number at the end.
                assert(rhs.range(of: "\(groupType)\\d+", options: .regularExpression, range: nil, locale: nil) != nil &&
                       lhs.range(of: "\(groupType)\\d+", options: .regularExpression, range: nil, locale: nil) != nil)
                return true
            }
        }

        return false
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

    public var receiver: ILType? {
        return ext?.receiver
    }

    public var functionSignature: Signature? {
        return Is(.function()) ? ext?.signature : nil
    }

    public var constructorSignature: Signature? {
        return Is(.constructor()) ? ext?.signature : nil
    }

    public var isEnumeration : Bool {
        return Is(.string) && ext != nil && !ext!.properties.isEmpty
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


    public var wasmDataSegmentType: WasmDataSegmentType? {
        return ext?.wasmExt as? WasmDataSegmentType
    }

    public var isWasmDataSegmentType: Bool {
        return wasmDataSegmentType != nil
    }

    public var wasmElementSegmentType: WasmElementSegmentType? {
        return ext?.wasmExt as? WasmElementSegmentType
    }

    public var isWasmElementSegmentType: Bool {
        return wasmElementSegmentType != nil
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

    public var wasmReferenceType: WasmReferenceType? {
        return wasmType as? WasmReferenceType
    }

    public var isWasmReferenceType: Bool {
        return wasmReferenceType != nil
    }

    public var wasmTypeDefinition: WasmTypeDefinition? {
        return wasmType as? WasmTypeDefinition
    }

    public var isWasmTypeDefinition: Bool {
        return wasmTypeDefinition != nil
    }

    public var isWasmFunctionDef: Bool {
        return self.definiteType == .wasmFunctionDef
    }

    public var wasmFunctionDefSignature: WasmSignature? {
        assert(self.definiteType == .wasmFunctionDef)
        return (wasmType as! WasmFunctionDefinition).signature
    }

    public var isWasmDefaultable: Bool {
        return Is(.wasmPrimitive) && !(isWasmReferenceType && !wasmReferenceType!.nullability)
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

    // Returns how many additional inputs an operation using this type will need
    // to "refine" the type. This value is 1 for indexed wasm-gc reference
    // types, zero otherwise.
    public func requiredInputCount() -> Int {
        if let ref = wasmReferenceType {
            switch ref.kind {
                case .Index: return 1
                case .Abstract: return 0
            }
        }
        return 0
    }

    // Returns true if the type is .wasmPackedI8 or .wasmPackedI16.
    public func isPacked() -> Bool {
        self == .wasmPackedI8 || self == .wasmPackedI16
    }
    // Returns the same type but "unpacks" .wasmPackedI8 and .wasmPackedI16 to .wasmi32.
    public func unpacked() -> ILType {
        return isPacked() ? .wasmi32 : self
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
    ///
    /// By default, a WasmTypeExtension only appears in the union if they are equal. For some
    /// WasmTypeExtensions (currently WasmReferenceType), there are more complex union rules.
    public func union(with other: ILType) -> ILType {
        // Trivial cases.
        if self == .jsAnything && other.Is(.jsAnything) || other == .jsAnything && self.Is(.jsAnything) {
            return .jsAnything
        } else if self == .nothing {
            return other
        } else if other == .nothing {
            return self
        } else if self == .wasmAnything && other.Is(.wasmAnything) || other == .wasmAnything && self.Is(.wasmAnything) {
            return .wasmAnything
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
        let receiver = other.receiver != nil ? self.receiver?.intersection(with: other.receiver!) : nil
        var group = self.group == other.group ? self.group : nil
        let wasmExt = self.wasmType != nil && other.wasmType != nil ? self.wasmType!.union(other.wasmType!) : nil
        // Object groups are used to describe certain wasm types. If the WasmTypeExtension is lost,
        // the group should also be invalidated. This ensures that e.g. any
        // `.object(ofGroup: "WasmTag")` always has a `.wasmTagType` extension.
        if wasmExt == nil && (self.wasmType ?? other.wasmType) != nil {
            group = nil
        }

        return ILType(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: commonProperties, methods: commonMethods, signature: signature, wasmExt: wasmExt, receiver: receiver))
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
        let group = self.group ?? other.group

        // For signatures we take a shortcut: if one signature subsumes the other, then the intersection
        // must be the subsumed signature. Additionally, we know that if there is an intersection, the
        // return value must be the intersection of the return values, so we can compute that up-front.
        let returnValue = (self.signature?.outputType ?? .jsAnything) & (other.signature?.outputType ?? .jsAnything)
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

        let receiver = self.receiver != nil && other.receiver != nil ? self.receiver!.union(with: other.receiver!) : self.receiver ?? other.receiver

        // If either value is nil, the result is the non-nil value. If both are non-nil, the result
        // is their intersection if valid, otherwise .nothing is returned.
        var wasmExt: WasmTypeExtension? = self.wasmType ?? other.wasmType
        if self.wasmType != nil && other.wasmType != nil {
            guard let wasmIntersection = self.wasmType!.intersection(other.wasmType!) else { return .nothing }
            wasmExt = wasmIntersection
        }

        return ILType(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: properties, methods: methods, signature: signature, wasmExt: wasmExt, receiver: receiver))
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

        // Merging of unbound fucntions with different receivers is not allowed.
        guard self.receiver == nil || other.receiver == nil || self.receiver == other.receiver else {
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

        // Merging objects with different wasm extensions is not allowed.
        guard self.ext?.wasmExt == nil || other.ext?.wasmExt == nil || self.ext?.wasmExt == other.ext?.wasmExt else {
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

        let receiver = self.receiver ?? other.receiver

        // Same is true for the group name
        let group = self.group ?? other.group

        let wasmExt = self.wasmType ?? other.wasmType

        // We just take the self.wasmExt as they have to be the same, see `canMerge`.
        let ext = TypeExtension(group: group, properties: self.properties.union(other.properties), methods: self.methods.union(other.methods), signature: signature, wasmExt: wasmExt, receiver: receiver)
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

    /// Returns a new ObjectType that represents this type without the removed property or method.
    public func removing(propertyOrMethod name: String) -> ILType {
        guard Is(.object()) else {
            return self
        }

        // Deleting a property in JavaScript will remove it from either one, whereever it is present.
        var newProperties = properties
        newProperties.remove(name)
        var newMethods = methods
        newMethods.remove(name)
        let newExt = TypeExtension(group: group, properties: newProperties, methods: newMethods, signature: signature, wasmExt: wasmType)
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
    private var ext: TypeExtension?

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
        if self == .jsAnything {
            return ".jsAnything"
        } else if self == .wasmAnything {
            return ".wasmAnything"
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
        case .unboundFunction:
               return ".unboundFunction(\(signature?.format(abbreviate: abbreviate) ?? "nil"), receiver: \(receiver?.format(abbreviate: abbreviate) ?? "nil"))"
        case .wasmi32:
            return ".wasmi32"
        case .wasmi64:
            return ".wasmi64"
        case .wasmf32:
            return ".wasmf32"
        case .wasmf64:
            return ".wasmf64"
        case .wasmSimd128:
            return ".wasmSimd128"
        case .wasmPackedI8:
            return ".wasmPackedI8"
        case .wasmPackedI16:
            return ".wasmPackedI16"
        case .label:
            if let labelType = self.wasmLabelType {
                return ".label(\(labelType.parameters))"
            }
            return ".label"
        case .wasmRef:
            guard let refType = self.wasmReferenceType else {
                return ".wasmGenericRef"
            }
            let nullPrefix = refType.nullability ? "null " : ""
            switch refType.kind {
                case .Abstract(let heapType):
                    return ".wasmRef(.Abstract(\(nullPrefix)\(heapType)))"
                case .Index(let indexRef):
                    if let desc = indexRef.get() {
                        return ".wasmRef(\(nullPrefix)Index \(desc.format(abbreviate: abbreviate)))"
                    }
                    return ".wasmRef(\(nullPrefix)Index)"
            }
        case .wasmFunctionDef:
            if let signature = wasmFunctionDefSignature {
                return ".wasmFunctionDef(\(signature.format(abbreviate: abbreviate)))"
            } else {
                return ".wasmFunctionDef()"
            }
        case .wasmTypeDef:
            if let desc = self.wasmTypeDefinition?.description {
                return ".wasmTypeDef(\(desc))"
            }
            return ".wasmTypeDef(nil)"
        case .exceptionLabel:
            return ".exceptionLabel"
        case .wasmDataSegment:
            return ".wasmDataSegment"
        case .wasmElementSegment:
            return ".wasmElementSegment"
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
    static let unboundFunction = BaseType(rawValue: 1 << 10)
    static let iterable    = BaseType(rawValue: 1 << 11)

    // Wasm Types
    static let wasmi32     = BaseType(rawValue: 1 << 12)
    static let wasmi64     = BaseType(rawValue: 1 << 13)
    static let wasmf32     = BaseType(rawValue: 1 << 14)
    static let wasmf64     = BaseType(rawValue: 1 << 15)

    // These are wasm internal types, these are never lifted as such and are only used to glue together dataflow in wasm.
    static let label       = BaseType(rawValue: 1 << 16)
    // Any catch block exposes such a label now to rethrow the exception caught by that catch.
    // Note that in wasm the label is actually the try block's label but as rethrows are only possible inside a catch
    // block, semantically having a label on the catch makes more sense.
    static let exceptionLabel = BaseType(rawValue: 1 << 17)
    // This is a reference to a table, which can be passed around to table instructions
    // The lifter will resolve this to the proper index when lifting.
    static let wasmSimd128     = BaseType(rawValue: 1 << 18)
    static let wasmFunctionDef = BaseType(rawValue: 1 << 19)

    // Wasm-gc types
    static let wasmRef = BaseType(rawValue: 1 << 20)
    static let wasmTypeDef = BaseType(rawValue: 1 << 21)

    // Wasm packed types. These types only exist as part of struct / array definitions. A wasm value
    // can never have the type i8 or i16 (they will always be extended to i32 by any operation
    // loading them.)
    static let wasmPackedI8 = BaseType(rawValue: 1 << 22)
    static let wasmPackedI16 = BaseType(rawValue: 1 << 23)

    static let wasmDataSegment = BaseType(rawValue: 1 << 24)
    static let wasmElementSegment = BaseType(rawValue: 1 << 25)

    static let jsAnything    = BaseType([.undefined, .integer, .float, .string, .boolean, .object, .function, .constructor, .unboundFunction, .bigint, .regexp, .iterable])

    static let wasmAnything = BaseType([.wasmf32, .wasmi32, .wasmf64, .wasmi64, .wasmRef, .wasmSimd128, .wasmTypeDef, .wasmFunctionDef])

    static let allBaseTypes: [BaseType] = [.undefined, .integer, .float, .string, .boolean, .object, .function, .constructor, .unboundFunction, .bigint, .regexp, .iterable, .wasmf32, .wasmi32, .wasmf64, .wasmi64, .wasmRef, .wasmSimd128, .wasmTypeDef, .wasmFunctionDef]
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

    // The receiver type of a function (used for unbound functions).
    let receiver: ILType?

    init?(group: String? = nil, properties: Set<String>, methods: Set<String>, signature: Signature?, wasmExt: WasmTypeExtension? = nil, receiver: ILType? = nil) {
        if group == nil && properties.isEmpty && methods.isEmpty && signature == nil && wasmExt == nil && receiver == nil {
            return nil
        }

        self.properties = properties
        self.methods = methods
        self.group = group
        self.signature = signature
        self.wasmExt = wasmExt
        self.receiver = receiver
    }

    static func ==(lhs: TypeExtension, rhs: TypeExtension) -> Bool {
        return lhs.properties == rhs.properties
            && lhs.methods == rhs.methods
            && lhs.group == rhs.group
            && lhs.signature == rhs.signature
            && lhs.wasmExt == rhs.wasmExt
            && lhs.receiver == rhs.receiver
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(group)
        hasher.combine(properties)
        hasher.combine(methods)
        hasher.combine(signature)
        hasher.combine(wasmExt)
        hasher.combine(receiver)
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

    func subsumes(_ other: WasmTypeExtension) -> Bool {
        // Default: Only if the type extensions are equal, one subsumes the other.
        self == other
    }

    func union(_ other: WasmTypeExtension) -> WasmTypeExtension? {
        // Default: The union is specified only if both type extensions are the same.
        self == other ? self : nil
    }

    func intersection(_ other: WasmTypeExtension) -> WasmTypeExtension? {
        // Default: The intersection is only valid if both type extensions are the same.
        self == other ? self : nil
    }
}

public class WasmFunctionDefinition: WasmTypeExtension {
    let signature: WasmSignature?

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmFunctionDefinition else { return false }
        return self.signature == other.signature
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(signature)
    }

    override func subsumes(_ other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmFunctionDefinition else { return false }
        return signature == nil || signature == other.signature
    }

    init(_ signature: WasmSignature?) {
        self.signature = signature
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
    public let parameters: [ILType]
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

    init(_ parameters: [ILType], isJSTag: Bool = false) {
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

public class WasmTypeDefinition: WasmTypeExtension {
    var description : WasmTypeDescription? = nil

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmTypeDefinition else { return false }
        return description == other.description
    }

    override func subsumes(_ other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmTypeDefinition else { return false }
        return description == nil || other.description == nil || description == other.description
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(description)
    }

    func getReferenceTypeTo(nullability: Bool) -> ILType {
        assert(description != nil)
        return .wasmIndexRef(description!, nullability: nullability)
    }
}

// TODO: Add continuation types for core stack switching.
// TODO: Add shared bit for shared-everything-threads.
// TODO: Add internal string type for JS string builtins.
enum WasmAbstractHeapType: CaseIterable, Comparable {
    // Note: The union, intersection, ... implementations are inspired by Binaryen's implementation,
    // so when extending the type system, feel free to use that implemenation as an orientation.
    // https://github.com/WebAssembly/binaryen/blob/main/src/wasm/wasm-type.cpp
    case WasmExtern
    case WasmFunc
    case WasmAny
    case WasmEq
    case WasmI31
    case WasmStruct
    case WasmArray
    case WasmExn
    case WasmNone
    case WasmNoExtern
    case WasmNoFunc
    case WasmNoExn

    // True if the type can be used from JS, i.e. either passing the value from JS as a parameter or
    // returning the value to JS as a result. (exnrefs cannot be passed from/to JS and throw
    // runtime errors when trying to do so.)
    func isUsableInJS() -> Bool {
        switch self {
            case .WasmExn, .WasmNoExn:
                return false
            default:
                return true
        }
    }

    func isBottom() -> Bool {
        getBottom() == self
    }

    func getBottom() -> Self {
        switch self {
            case .WasmExtern, .WasmNoExtern:
                return .WasmNoExtern
            case .WasmFunc, .WasmNoFunc:
                return .WasmNoFunc
            case .WasmAny, .WasmEq, .WasmI31, .WasmStruct, .WasmArray, .WasmNone:
                return .WasmNone
            case .WasmExn, .WasmNoExn:
                return .WasmNoExn
        }
    }

    func inSameHierarchy(_ other: Self) -> Bool {
        return getBottom() == other.getBottom()
    }

    func union(_ other: Self) -> Self? {
        if self == other {
            return self
        }
        if !self.inSameHierarchy(other) {
            return nil  // Incompatible heap types.
        }
        if self.isBottom() {
            return other
        }
        if other.isBottom() {
            return self
        }
        // Let `a` be the lesser type.
        let a = min(self, other)
        let b = max(self, other)
        return switch a {
            case .WasmAny:
                .WasmAny
            case .WasmEq, .WasmI31, .WasmStruct:
                .WasmEq
            case .WasmArray:
                .WasmAny
            case .WasmExtern, .WasmFunc, .WasmExn, .WasmNone, .WasmNoExtern, .WasmNoFunc, .WasmNoExn:
                fatalError("unhandled subtyping for a=\(a) b=\(b)")
        }
    }

    func intersection(_ other: Self) -> Self? {
        if self == other {
            return self
        }
        if self.getBottom() != other.getBottom() {
            return nil
        }
        if self.subsumes(other) {
            return other
        }
        if other.subsumes(self) {
            return self
        }
        return self.getBottom()
    }

    func subsumes(_ other: Self) -> Bool {
        union(other) == self
    }
}

// A wrapper around a WasmTypeDescription without owning the WasmTypeDescription.
struct UnownedWasmTypeDescription : Hashable {
    private unowned var description: WasmTypeDescription?

    init(_ description: WasmTypeDescription? = nil) {
        self.description = description
    }

    func get() -> WasmTypeDescription? {
        return description
    }
}

public class WasmReferenceType: WasmTypeExtension {
    enum Kind : Hashable {
        // A user defined (indexed) wasm-gc type. Note that the WasmReferenceType may not own the
        // WasmTypeDescription as that would create cyclic references in case of self or forward
        // references (e.g. an array could have its own type as an element type) leading to memory
        // leaks. The underlying WasmTypeDescription is always owned and kept alive by the
        // corresponding WasmTypeDefinition extension attached to the type of the operation
        // defining the wasm-gc type (and is kept alive by the JSTyper).
        case Index(UnownedWasmTypeDescription = UnownedWasmTypeDescription())
        case Abstract(WasmAbstractHeapType)

        func union(_ other: Self) -> Self? {
            switch self {
                case .Index(let desc):
                    switch other {
                        case .Index(let otherDesc):
                            if desc.get() == nil || otherDesc.get() == nil {
                                return .Index(.init())
                            }
                            if desc.get() == otherDesc.get() {
                                return self
                            }
                            if let abstract = desc.get()?.abstractHeapSupertype,
                               let otherAbstract = otherDesc.get()?.abstractHeapSupertype,
                               let upperBound = abstract.union(otherAbstract) {
                                return .Abstract(upperBound)
                               }
                        case .Abstract(let otherAbstract):
                            if let abstractSuper = desc.get()?.abstractHeapSupertype,
                               let upperBound = abstractSuper.union(otherAbstract) {
                                return .Abstract(upperBound)
                            }
                    }
                case .Abstract(let heapType):
                    switch other {
                        case .Index(let otherDesc):
                            if let otherAbstract = otherDesc.get()?.abstractHeapSupertype,
                               let upperBound = heapType.union(otherAbstract) {
                                return .Abstract(upperBound)
                            }
                        case .Abstract(let otherHeapType):
                            if let upperBound = heapType.union(otherHeapType) {
                                return .Abstract(upperBound)
                            }
                    }
            }
            return nil
        }

        func intersection(_ other: Self) -> Self? {
            switch self {
                case .Index(let desc):
                    switch other {
                        case .Index(let otherDesc):
                            if desc.get() == otherDesc.get() || desc.get() == nil || otherDesc.get() == nil {
                                return .Index(desc)
                            }
                        case .Abstract(let otherAbstract):
                            if let abstractSuper = desc.get()?.abstractHeapSupertype,
                               otherAbstract.subsumes(abstractSuper) {
                                return self
                            }
                    }
                case .Abstract(let heapType):
                    switch other {
                        case .Index(let otherDesc):
                            if let otherAbstract = otherDesc.get()?.abstractHeapSupertype,
                                heapType.subsumes(otherAbstract) {
                                return other
                            }
                        case .Abstract(let otherHeapType):
                            if let lowerBound = heapType.intersection(otherHeapType) {
                                return .Abstract(lowerBound)
                            }
                    }
            }
            return nil
        }
    }
    var kind: Kind
    let nullability: Bool

    init(_ kind: Kind, nullability: Bool) {
        self.kind = kind
        self.nullability = nullability
    }

    func isAbstract() -> Bool {
        switch self.kind {
            case .Abstract(_):
                return true
            case .Index(_):
                return false
        }
    }

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmReferenceType else { return false }
        return kind == other.kind && self.nullability == other.nullability
    }

    override func subsumes(_ other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmReferenceType else { return false }
        return self.kind.union(other.kind) == self.kind && (self.nullability || !other.nullability)
    }

    override func union(_ other: WasmTypeExtension) -> WasmTypeExtension? {
        guard let other = other as? WasmReferenceType else { return nil }
        if let kind = self.kind.union(other.kind) {
            // The union is nullable if either of the two types input types is nullable.
            let nullability = self.nullability || other.nullability
            return WasmReferenceType(kind, nullability: nullability)
        }
        return nil
    }

    override func intersection(_ other: WasmTypeExtension) -> WasmTypeExtension? {
        guard let other = other as? WasmReferenceType else { return nil }
        if let kind = self.kind.intersection(other.kind) {
            // The intersection is nullable if both are nullable.
            let nullability = self.nullability && other.nullability
            return WasmReferenceType(kind, nullability: nullability)
        }
        return nil
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(nullability)
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
    let addrType: ILType

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
        assert(!isShared || limits.max != nil, "Shared memories must have a maximum size")
        self.limits = limits
        self.isShared = isShared
        self.isMemory64 = isMemory64
        self.addrType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
    }
}

public class WasmDataSegmentType: WasmTypeExtension {
    let segmentLength: Int
    private(set) var isDropped: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmDataSegmentType else { return false }
        return self.segmentLength == other.segmentLength && self.isDropped == other.isDropped
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(segmentLength)
        hasher.combine(isDropped)
    }

    init(segmentLength: Int) {
        self.segmentLength = segmentLength
        self.isDropped = false
    }

    public func markAsDropped() {
        self.isDropped = true
    }
}

public class WasmElementSegmentType: WasmTypeExtension {
    let segmentLength: Int
    private(set) var isDropped: Bool

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmElementSegmentType else { return false }
        return self.segmentLength == other.segmentLength && self.isDropped == other.isDropped
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(segmentLength)
        hasher.combine(isDropped)
    }

    init(segmentLength: Int) {
        self.segmentLength = segmentLength
        self.isDropped = false
    }

    public func markAsDropped() {
        self.isDropped = true
    }
}

public class WasmTableType: WasmTypeExtension {
    public struct IndexInTableAndWasmSignature: Hashable {
        let indexInTable: Int
        let signature: WasmSignature

        public init(indexInTable: Int, signature: WasmSignature) {
            self.indexInTable = indexInTable
            self.signature = signature
        }
    }

    let elementType: ILType
    let limits: Limits
    let isTable64: Bool
    let knownEntries: [IndexInTableAndWasmSignature]

    override func isEqual(to other: WasmTypeExtension) -> Bool {
        guard let other = other as? WasmTableType else { return false }
        return self.elementType == other.elementType && self.limits == other.limits && self.isTable64 == other.isTable64 && self.knownEntries == other.knownEntries
    }

    override public func hash(into hasher: inout Hasher) {
        hasher.combine(elementType)
        hasher.combine(limits)
        hasher.combine(isTable64)
        hasher.combine(knownEntries)
    }

    init(elementType: ILType, limits: Limits, isTable64: Bool, knownEntries: [IndexInTableAndWasmSignature]) {
        // TODO(manoskouk): Assert table type is reference type.
        self.elementType = elementType
        self.limits = limits
        self.isTable64 = isTable64
        self.knownEntries = knownEntries
    }
}

// Represents one parameter of a function signature.
public enum Parameter: Hashable {
    case plain(ILType)
    case opt(ILType)
    case rest(ILType)

    // Convenience constructors for plain parameters.
    public static let integer    = Parameter.plain(.integer)
    public static let bigint     = Parameter.plain(.bigint)
    public static let float      = Parameter.plain(.float)
    public static let string     = Parameter.plain(.string)
    public static let boolean    = Parameter.plain(.boolean)
    public static let regexp     = Parameter.plain(.regexp)
    public static let iterable   = Parameter.plain(.iterable)
    public static let jsAnything = Parameter.plain(.jsAnything)
    public static let number     = Parameter.plain(.number)
    public static let primitive  = Parameter.plain(.primitive)
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
    // Construct a generic parameter list with `numParameters` parameters of type `.jsAnything`
    init(numParameters: Int, hasRestParam: Bool) {
        assert(!hasRestParam || numParameters > 0)
        self.init(repeating: .jsAnything, count: numParameters)
        if hasRestParam {
            self[endIndex - 1] = .jsAnything...
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

    // Constructs a function with N parameters of any type and returning .jsAnything.
    public init(withParameterCount numParameters: Int, hasRestParam: Bool = false) {
        let parameters = ParameterList(numParameters: numParameters, hasRestParam: hasRestParam)
        self.init(expects: parameters, returns: .jsAnything)
    }

    // Returns a new signature with the output type replaced with the given type.
    public func replacingOutputType(with newOutputType: ILType) -> Signature {
        return parameters => newOutputType
    }

    // The most generic function signature: varargs function returning .jsAnything
    public static let forUnknownFunction = [.jsAnything...] => .jsAnything

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
    //   [.integer, .boolean] => .undefined subsumes [.jsAnything] => .undefined
    //   [.integer] => .undefined subsumes [.number] => .undefined
    //   [.jsAnything] => .undefined *only* subsumes [.jsAnything] => undefined or [] => .undefined
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
        // [.jsAnything...] => .undefined does *not* subsume [.jsAnything] => .undefined
        // because the first function may be legitimately called with no arguments.
        // [...integer] => .undefined subsumes [.jsAnything...] => .undefined
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

public struct WasmSignature: Hashable, CustomStringConvertible {
    public let parameterTypes: [ILType]
    public let outputTypes: [ILType]

    init(expects parameters: [ILType], returns returnTypes: [ILType]) {
        self.parameterTypes = parameters
        self.outputTypes = returnTypes
    }

    init(from signature: Signature) {
        self.parameterTypes = signature.parameters.convertPlainToILTypes()
        self.outputTypes = signature.outputType != .nothing ? [signature.outputType] : []
    }

    func format(abbreviate: Bool) -> String {
        let inputs = parameterTypes.map({ $0.format(abbreviate: abbreviate) }).joined(separator: ", ")
        let outputs = outputTypes.map({ $0.format(abbreviate: abbreviate) }).joined(separator: ", ")
        return "[\(inputs)] => [\(outputs)]"
    }

    public var description: String {
        return format(abbreviate: false)
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

public func => (parameters: [ILType], returnTypes: [ILType]) -> WasmSignature {
    return WasmSignature(expects: parameters, returns: returnTypes)
}

class WasmTypeDescription: Hashable, CustomStringConvertible {
    static let selfReference = WasmTypeDescription(typeGroupIndex: -1)
    public let typeGroupIndex: Int
    // The "closest" super type that is an abstract type (.WasmArray for arrays, .WasmStruct for
    // structs). It is nil for unresolved forward/self references for which the concrete abstract
    // super type is still undecided.
    public let abstractHeapSupertype: WasmAbstractHeapType?

    // TODO(gc): We will also need to support subtyping of struct and array types at some point.
    init(typeGroupIndex: Int, superType: WasmAbstractHeapType? = nil) {
        self.typeGroupIndex = typeGroupIndex
        self.abstractHeapSupertype = superType
    }

    static func == (lhs: WasmTypeDescription, rhs: WasmTypeDescription) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func format(abbreviate: Bool) -> String {
        if self == .selfReference {
            return "selfReference"
        }
        return "\(typeGroupIndex)"
    }

    public var description: String {
        return format(abbreviate: false)
    }
}

class WasmSignatureTypeDescription: WasmTypeDescription {
    var signature: WasmSignature

    init(signature: WasmSignature, typeGroupIndex: Int) {
        self.signature = signature
        super.init(typeGroupIndex: typeGroupIndex, superType: .WasmFunc)
    }

    override func format(abbreviate: Bool) -> String {
        let abbreviated = "\(super.format(abbreviate: abbreviate)) Func"
        if abbreviate {
            return abbreviated
        }
        let paramTypes = signature.parameterTypes.map {$0.abbreviated}.joined(separator: ", ")
        let outputTypes = signature.outputTypes.map {$0.abbreviated}.joined(separator: ", ")
        return "\(abbreviated)[[\(paramTypes)] => [\(outputTypes)]]"
    }
}

class WasmArrayTypeDescription: WasmTypeDescription {
    var elementType: ILType
    let mutability: Bool

    init(elementType: ILType, mutability: Bool, typeGroupIndex: Int) {
        self.elementType = elementType
        self.mutability = mutability
        super.init(typeGroupIndex: typeGroupIndex, superType: .WasmArray)
    }

    override func format(abbreviate: Bool) -> String {
        let abbreviated = "\(super.format(abbreviate: abbreviate)) Array"
        if abbreviate {
            return abbreviated
        }
        return "\(abbreviated)[\(mutability ? "mutable" : "immutable") \(elementType.abbreviated)]"
    }
}

class WasmStructTypeDescription: WasmTypeDescription {
    class Field: CustomStringConvertible {
        var type: ILType
        let mutability: Bool

        init(type: ILType, mutability: Bool) {
            self.type = type
            self.mutability = mutability
        }

        var description: String {
            return "\(mutability ? "mutable" : "immutable") \(type.abbreviated)"
        }
    }

    let fields: [Field]

    init(fields: [Field], typeGroupIndex: Int) {
        self.fields = fields
        super.init(typeGroupIndex: typeGroupIndex, superType: .WasmStruct)
    }

    override func format(abbreviate: Bool) -> String {
        let abbreviated = "\(super.format(abbreviate: abbreviate)) Struct"
        if abbreviate {
            return abbreviated
        }
        return "\(abbreviated)[\(fields.map {$0.description}.joined(separator: ", "))]"
    }
}
