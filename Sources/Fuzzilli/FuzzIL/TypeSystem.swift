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

/// A simple type system designed for use during fuzzing.
///
/// The goal of this type system is to be as simple as possible while still being able to express all the common
/// operations that one can peform on values of the target language, e.g. calling a function or constructor,
/// accessing properties, or calling methods.
/// The type system is mainly used for two purposes:
///
///     1. to obtain a variable of a certain type when generating code. E.g. the method call code generator will want
///        a variable of type .object() as input because only that can have methods. Also, when generating function
///        calls it can be necessary to find variables of the types that the function expects as arguments. This task
///        is solved by defining a "Is a" relationship between types which can then be used to find suitable variables.
///     2. to determine possible actions that can be performed on a value. E.g. when having a reference to something
///        that is known to be a function, a function call can be performed. Also, the method call code generator will
///        want to know the available methods that it can call on an object, which it can query from the type system.
///
/// Type information can generally either be computed statically (see AbstractInterpreter.swift) or collected dynamically
/// at runtime by instrumenting generated programs and executing them.
///
/// The following base types are defined:
///     .undefined
///     .integer
///     .float
///     .string
///     .boolean
///     .object(ofGroup: G, withProperties: [...], withMethods: [...])
///          something that (potentially) has properties and methods. Can also have a "group", which is simply a string.
///          Groups can e.g. be used to store property and method type information for related objects. See JavaScriptEnvironment.swift for examples.
///     .function(signature: S)
///          something that can be invoked as a function
///     .constructor(signature: S)
///          something that can be invoked as a constructor
///     .unknown
///          a pseudotype to indicate that the real type is unknown
///
/// Besides the base types, types can be combined to form new types:
///
/// A type can be a union, essentially stating that it is one of multiple types. Union types occur in many scenarios, e.g.
/// when reassigning a variable, when computing type information following a conditionally executing piece of code, or due to
/// imprecise modelling of the environment, e.g. the + operation in JavaScript or return values of various APIs.
///
/// Further, a type can also be a merged type, essentially stating that it is *all* of the contained types at the same type.
/// As an example of a merged type, think of regular JavaScript functions which can be called but also constructed. On the other hand,
/// some JavaScript builtins can be used as a function but not as a constructor or vice versa. As such, it is necessary to be able to
/// differentiate between functions and constructors. Strings are another example for merged types. On the one hand they are a primitive
/// type expected by various APIs, on the other hand they can be used like an object by accessing properties on them or invoking methods.
/// As such, a JavaScript string would be represented as a merge of .string and .object(properties: [...], methods: [...]).
///
/// The operations that can be performed on types are then:
///
///    1. Unioning (|)     : this operation on two types expresses that the result can either
///                          be the first or the second type.
///
///    2. Intersecting (&) : this operation computes the intersection, so the common type
///                          between the two argument types. This is used by the "MayBe" query,
///                          answering whether a value could potentially have the given type.
///                          In contrast to the other two operations, itersecting will not create
///                          new types.
///
///    3. Merging (+)      : this operation merges the two argument types into a single type
///                          which is both types. Not all types can be merged, however.
///
/// Finally, types define the "is a" (subsumption) relation (>=) which amounts to set inclusion. A type T1 subsumes
/// another type T2 if all instances of T2 are also instances of T1. See the .subsumes method for the exact subsumption
/// rules. Some examples:
///
///    - .anything, the union of all types, subsumes every other type
///    - .nothing, the empty type, is subsumed by all other types. .nothing occurs e.g. during intersection
///    - .object() subsumes all other object type. I.e. objects with a property "foo" are sill objects
///          e.g. .object() >= .object(withProperties: ["foo"]) and .object() >= .object(withMethods: ["bar"])
///    - .object(withProperties: ["foo"]) subsumes all other object types that also have a property "foo"
///          e.g. .object(withProperties: ["foo"]) >= .object(withProperties: ["foo", "bar"], withMethods: ["baz"])
///    - .object(ofGroup: G) subsumes any other object of group G, but not of a different group
///    - .function([.integer] => .integer) only subsumes other functions with the same signature
///    - .primitive, the union of .integer, .float, and .string, subsumes its parts like every union
///    - .functionAndConstructor(), the merge of .function() and .constructor(), is subsumed by each of its parts like every merged type
///
/// Internally, types are implemented as bitsets, with each base type corresponding to one bit.
/// Types are then implemented as two bitsets: the definite type, indicating what it definitely
/// is, and the possible type, indicating what types it could potentially be.
/// A union type is one where the possible type is larger than the definite one.
///
/// Examples:
///    .integer                      => definiteType = .integer,          possibleType = .integer
///    .integer | .float             => definiteType = .nothing (0),      possibleType = .integer | .float
///    .string + .object             => definiteType = .string | .object, possibleType = .string | .object
///    .string | (.string + .object) => definiteType = .string,           possibleType = .string | .object
///
/// See also Tests/FuzzilliTests/TypeSystemTest.swift for examples of the various properties and features of this type system.
///
public struct Type: Hashable {

    //
    // Types and type constructors
    //

    /// Corresponds to the undefined type in JavaScript
    public static let undefined = Type(definiteType: .undefined)

    /// An integer type.
    public static let integer   = Type(definiteType: .integer)

    /// A bigInt type.
    public static let bigint    = Type(definiteType: .bigint)

    /// A floating point number.
    public static let float     = Type(definiteType: .float)

    /// A string.
    public static let string    = Type(definiteType: .string)

    /// A boolean.
    public static let boolean   = Type(definiteType: .boolean)

    /// A RegExp
    public static let regexp    = Type(definiteType: .regexp)

    /// Type one can iterate over
    public static let iterable   = Type(definiteType: .iterable)        // TODO rename to .array?

    /// A value for which the type is not known.
    public static let unknown   = Type(definiteType: .unknown)

    /// The type that subsumes all others.
    public static let anything  = Type(definiteType: .nothing, possibleType: .anything)

    /// The type that is subsumed by all others.
    public static let nothing   = Type(definiteType: .nothing, possibleType: .nothing)

    /// A number: either an integer or a float.
    public static let number: Type = .integer | .float

    /// A primitive: either a number, a string, a boolean, or a bigint.
    public static let primitive: Type = .integer | .float | .string | .boolean

    /// Constructs an object type.
    public static func object(ofGroup group: String? = nil, withProperties properties: [String] = [], withMethods methods: [String] = []) -> Type {
        let ext = TypeExtension(group: group, properties: Set(properties), methods: Set(methods), signature: nil)
        return Type(definiteType: .object, ext: ext)
    }

    /// A function.
    public static func function(_ signature: FunctionSignature? = nil) -> Type {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return Type(definiteType: [.function], ext: ext)
    }

    /// A constructor.
    public static func constructor(_ signature: FunctionSignature? = nil) -> Type {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return Type(definiteType: [.constructor], ext: ext)
    }

    /// A function and constructor. Same as .function(signature) + .constructor(signature).
    public static func functionAndConstructor(_ signature: FunctionSignature? = nil) -> Type {
        let ext = TypeExtension(properties: Set(), methods: Set(), signature: signature)
        return Type(definiteType: [.function, .constructor], ext: ext)
    }

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
    public var baseType: Type {
        return Type(definiteType: definiteType)
    }

    public static func ==(lhs: Type, rhs: Type) -> Bool {
        return lhs.definiteType == rhs.definiteType && lhs.possibleType == rhs.possibleType && lhs.ext == rhs.ext
    }
    public static func !=(lhs: Type, rhs: Type) -> Bool {
        return !(lhs == rhs)
    }

    /// Returns true if this type subsumes the given type, i.e. every instance of other is also an instance of this type.
    public func Is(_ other: Type) -> Bool {
        return other.subsumes(self)
    }

    /// Returns true if this type could be the given type, i.e. the intersection of the two is nonempty.
    public func MayBe(_ other: Type) -> Bool {
        return self.intersection(with: other) != .nothing
    }

    func uniquified(with deduplicationSet: inout Set<TypeExtension>) -> Type {
        guard let typeExtension = self.ext else { return self }
        let (inserted, memberAfterInsert) = deduplicationSet.insert(typeExtension)

        if inserted {
            return self
        } else {
            return Type(definiteType: definiteType, possibleType: possibleType, ext: memberAfterInsert)
        }
    }

    /// Returns whether this type subsumes the other type.
    ///
    /// A type T1 subsumes another type T2 if all instances of T2 are also instances of T1.
    ///
    /// Subsumption rules:
    ///
    ///  - T >= T
    ///  - except for the above, there is no subsumption relationship between
    ///    primitive types (.undefined, .integer, .float, .string, .boolean) and .unknown
    ///  - .object(ofGroup: G1, withProperties: P1, withMethods: M1) >= .object(ofGroup: G2, withProperties: P2, withMethods: M2)
    ///        iff (G1 == nil || G1 == G2) && P1 is a subset of P2 && M1 is a subset of M2
    ///  - .function(S1) >= .function(S2) iff S1 = nil || S1 == S2
    ///  - .constructor(S1) >= .constructor(S2) iff S1 = nil || S1 == S2
    ///  - T1 | T2 >= T1 && T1 | T2 >= T2
    ///  - T1 >= T1 + T2 && T2 >= T1 + T2
    ///  - T1 >= T1 & T2 && T2 >= T1  & T2
    public func subsumes(_ other: Type) -> Bool {
        // Handle trivial cases
        if self == .anything || self == other || other == .nothing {
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

        // Similarly, there is no signature subsumption, either we don't care about the signature or they must match.
        guard signature == nil || signature == other.signature else {
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

        return true
    }

    public static func >=(lhs: Type, rhs: Type) -> Bool {
        return lhs.subsumes(rhs)
    }

    public static func <=(lhs: Type, rhs: Type) -> Bool {
        return rhs.subsumes(lhs)
    }


    //
    // Access to extended type data
    //

    public var signature: FunctionSignature? {
        return ext?.signature
    }

    public var functionSignature: FunctionSignature? {
        return Is(.function()) ? ext?.signature : nil
    }

    public var constructorSignature: FunctionSignature? {
        return Is(.constructor()) ? ext?.signature : nil
    }

    public var group: String? {
        return ext?.group
    }

    public var properties: Set<String> {
        return ext?.properties ?? Set()
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
    /// Unioning also discards flag types.
    public func union(with other: Type) -> Type {

        // Form a union: the intersection of both definiteTypes and the union of both possibleTypes.
        // If the base types are the same, this will be a (cheap) Nop.
        let definiteType = self.definiteType.intersection(other.definiteType)
        let possibleType = self.possibleType.union(other.possibleType)

        // Fast union case
        if self.ext === other.ext {
            return Type(definiteType: definiteType, possibleType: possibleType, ext: self.ext)
        }

        // Slow union case: need to union (or really widen) the extension. For properties and methods
        // that means finding the set of shared properties and methods, which is imprecise but correct.
        let commonProperties = self.properties.intersection(other.properties)
        let commonMethods = self.methods.intersection(other.methods)
        let signature = self.signature == other.signature ? self.signature : nil
        let group = self.group == other.group ? self.group : nil
        return Type(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: commonProperties, methods: commonMethods, signature: signature))
    }

    public static func |(lhs: Type, rhs: Type) -> Type {
        return lhs.union(with: rhs)
    }

    public static func |=(lhs: inout Type, rhs: Type) {
        lhs = lhs | rhs
    }

    /// Forms the intersection of the two types.
    ///
    /// The intersection of T1 and T2 is the subtype that is contained in both T1 and T2.
    /// The result of this can be .nothing.
    public func intersection(with other: Type) -> Type {
        // The definite types must have a subset relationship.
        // E.g. a StringObject intersected with a String is a StringObject,
        // but a StringObject intersected with an IntegerObject is .nothing.
        let definiteType = self.definiteType.union(other.definiteType)
        guard definiteType == self.definiteType || definiteType == other.definiteType else {
            return .nothing
        }

        // Now intersect the possible type, ignoring flags as otherwise the intersection might just be flags, which is invalid.
        var possibleType = self.possibleType.intersection(other.possibleType)
        guard !possibleType.isEmpty else {
            return .nothing
        }

        // E.g. the intersection of a StringObject and a String is a StringObject. As such, here we have to
        // "add back" the definite type to the possible type (which at this point would just be String).
        possibleType.formUnion(definiteType)

        // Fast intersection case
        if self.ext === other.ext {
            return Type(definiteType: definiteType, possibleType: possibleType, ext: self.ext)
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

        // The same rules apply for function signatures.
        guard self.signature == nil || other.signature == nil || self.signature == other.signature else {
            return .nothing
        }
        let signature = self.signature == nil ? other.signature : self.signature

        return Type(definiteType: definiteType, possibleType: possibleType, ext: TypeExtension(group: group, properties: properties, methods: methods, signature: signature))
    }

    public static func &(lhs: Type, rhs: Type) -> Type {
        return lhs.intersection(with: rhs)
    }

    public static func &=(lhs: inout Type, rhs: Type) {
        lhs = lhs & rhs
    }

    /// Returns whether this type can be merged with the other type.
    public func canMerge(with other: Type) -> Bool {
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

        // Mergin with .nothing is not supported as the result would have to be subsumed by .nothing but be != .nothing which is not allowed.
        guard self != .nothing && other != .nothing else {
            return false
        }

        // Merging with .unknown is not supported as the result wouldn't make much sense interpretation wise.
        guard self != .unknown && other != .unknown else {
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
    public func merging(with other: Type) -> Type {
        Assert(canMerge(with: other))

        let definiteType = self.definiteType.union(other.definiteType)
        let possibleType = self.possibleType.union(other.possibleType)

        // Signatures must be equal here or one of them is nil (see canMerge)
        let signature = self.signature ?? other.signature

        // Same is true for the group name
        let group = self.group ?? other.group

        let ext = TypeExtension(group: group, properties: self.properties.union(other.properties), methods: self.methods.union(other.methods), signature: signature)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: ext)
    }

    public static func +(lhs: Type, rhs: Type) -> Type {
        return lhs.merging(with: rhs)
    }

    public static func +=(lhs: inout Type, rhs: Type) {
        lhs = lhs.merging(with: rhs)
    }

    public func generalize() -> Type {
        // Only keep the group of an object.
        let newExt = TypeExtension(group: group, properties: Set(), methods: Set(), signature: nil)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    //
    // Type transitioning
    //
    // TODO cache these in some kind of type transition table data structure?
    //

    /// Returns a new ObjectType that represents this type with the added property.
    public func adding(property: String) -> Type {
        guard Is(.object()) else {
            return self
        }
        var newProperties = properties
        newProperties.insert(property)
        let newExt = TypeExtension(group: group, properties: newProperties, methods: methods, signature: signature)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Returns a new ObjectType that represents this type without the removed property.
    public func removing(property: String) -> Type {
        guard Is(.object()) else {
            return self
        }
        var newProperties = properties
        newProperties.remove(property)
        let newExt = TypeExtension(group: group, properties: newProperties, methods: methods, signature: signature)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Returns a new ObjectType that represents this type with the added property.
    public func adding(method: String) -> Type {
        guard Is(.object()) else {
            return self
        }
        var newMethods = methods
        newMethods.insert(method)
        let newExt = TypeExtension(group: group, properties: properties, methods: newMethods, signature: signature)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    /// Returns a new ObjectType that represents this type without the removed property.
    public func removing(method: String) -> Type {
        guard Is(.object()) else {
            return self
        }
        var newMethods = methods
        newMethods.remove(method)
        let newExt = TypeExtension(group: group, properties: properties, methods: newMethods, signature: signature)
        return Type(definiteType: definiteType, possibleType: possibleType, ext: newExt)
    }

    //
    // Type implementation internals
    //

    /// The base type is simply a bitset of (potentially multiple) basic types.
    private let definiteType: BaseType

    /// A bit in this
    /// The possible type is always a superset of the necessary type.
    private let possibleType: BaseType

    /// The type extensions contains properties, methods, function signatures, etc.
    private let ext: TypeExtension?

    /// Types must be constructed through one of the public constructors below.
    private init(definiteType: BaseType, possibleType: BaseType? = nil, ext: TypeExtension? = nil) {
        self.definiteType = definiteType
        self.possibleType = possibleType ?? definiteType
        self.ext = ext
        Assert(self.possibleType.contains(self.definiteType))
    }
}

extension Type: CustomStringConvertible {
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
            var mergedTypes: [Type] = []
            for b in BaseType.allBaseTypes {
                if self.definiteType.contains(b) {
                    let subtype = Type(definiteType: b, ext: ext)
                    mergedTypes.append(subtype)
                }
            }

            var parts: [String] = []
            for b in BaseType.allBaseTypes {
                if self.possibleType.contains(b) && !self.definiteType.contains(b) {
                    let subtype = Type(definiteType: b, ext: ext)
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
        case .unknown:
            return ".unknown"
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
        default:
            break
        }

        // Must be a merged type

        if isMerged {
            var parts: [String] = []
            for b in BaseType.allBaseTypes {
                if self.definiteType.contains(b) {
                    let subtype = Type(definiteType: b, ext: ext)
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

    // The compiler has these values hardcoded, in ProgramBuilder.ml.
    // If these values are changed, make sure to update them there as well.
    static let undefined   = BaseType(rawValue: 1 << 0)
    static let integer     = BaseType(rawValue: 1 << 1)
    static let float       = BaseType(rawValue: 1 << 2)
    static let string      = BaseType(rawValue: 1 << 3)
    static let boolean     = BaseType(rawValue: 1 << 4)
    static let object      = BaseType(rawValue: 1 << 5)
    static let function    = BaseType(rawValue: 1 << 6)
    static let constructor = BaseType(rawValue: 1 << 7)
    static let unknown     = BaseType(rawValue: 1 << 8)
    static let bigint      = BaseType(rawValue: 1 << 9)
    static let regexp      = BaseType(rawValue: 1 << 10)
    static let iterable    = BaseType(rawValue: 1 << 11)

    /// The union of all types.
    static let anything    = BaseType([.undefined, .integer, .float, .string, .boolean, .object, .unknown, .function, .constructor, .bigint, .regexp, .iterable])

    static let allBaseTypes: [BaseType] = [.undefined, .integer, .float, .string, .boolean, .object, .unknown, .function, .constructor, .bigint, .regexp, .iterable]
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
    let signature: FunctionSignature?

    init?(group: String? = nil, properties: Set<String>, methods: Set<String>, signature: FunctionSignature?) {
        if group == nil && properties.isEmpty && methods.isEmpty && signature == nil {
            return nil
        }

        self.properties = properties
        self.methods = methods
        self.group = group
        self.signature = signature
    }

    static func ==(lhs: TypeExtension, rhs: TypeExtension) -> Bool {
        return lhs.properties == rhs.properties && lhs.methods == rhs.methods && lhs.group == rhs.group && lhs.signature == rhs.signature
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(group)
        hasher.combine(properties)
        hasher.combine(methods)
        hasher.combine(signature)
    }
}

public enum Parameter: Equatable, Hashable {
    case plain(Type)
    case opt(Type)
    case rest(Type)

    fileprivate func format(abbreviate: Bool) -> String {
        switch self {
            case .plain(let t):
                return ".plain(\(t.format(abbreviate: abbreviate)))"
            case .opt(let t):
                return ".opt(\(t.format(abbreviate: abbreviate)))"
            case .rest(let t):
               return ".rest(\(t.format(abbreviate: abbreviate)))"
        }
    }

    var callerType: Type {
        switch self {
            case .plain(let t):
                return t
            case .opt(let t):
                return t
            case .rest(let t):
               return t
        }
    }

    var isRestParam: Bool {
        switch self {
            case .rest(_):
                return true
            default:
                return false
        }
    }

    var isOptional: Bool {
        switch self {
            case .opt(_):
                return true
            default:
                return false
        }
    }

    public typealias ProtobufType = Fuzzilli_Protobuf_Parameter

    func asProtobuf(with typeCache: TypeCache?) -> ProtobufType {
        switch self {
            case .plain(let inputType):
                return ProtobufType.with {
                    $0.plainParameter = Fuzzilli_Protobuf_PlainParameter.with {
                        $0.inputType = inputType.asProtobuf(with: typeCache)
                    }
                }
            case .opt(let inputType):
                return ProtobufType.with {
                    $0.optionalParameter = Fuzzilli_Protobuf_OptionalParameter.with {
                        $0.inputType = inputType.asProtobuf(with: typeCache)
                    }
                }
            case .rest(let inputType):
                return ProtobufType.with {
                    $0.restParameter = Fuzzilli_Protobuf_RestParameter.with {
                        $0.inputType = inputType.asProtobuf(with: typeCache)
                    }
                }
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtobufType, with typeCache: TypeCache?) throws {
        switch proto.param {
            case .plainParameter(let p):
                self = .plain(try Type(from: p.inputType, with: typeCache))
            case .optionalParameter(let p):
                self = .opt(try Type(from: p.inputType, with: typeCache))
            case .restParameter(let p):
                self = .rest(try Type(from: p.inputType, with: typeCache))
            default:
              throw FuzzilliError.typeDecodingError("invalid parameter type")
        }
    }

    public init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}

public struct FunctionSignature: Hashable, CustomStringConvertible {
    public let parameters: [Parameter]
    public let outputType: Type

    public func format(abbreviate: Bool) -> String {
        let params = parameters.map({ $0.format(abbreviate: abbreviate) }).joined(separator: ", ")
        return "[\(params)] => \(outputType.format(abbreviate: abbreviate))"
    }

    public var description: String {
        return format(abbreviate: false)
    }

    // Returns the number of innerOutputs that are generated from the function signature
    public var numOutputVariablesInCallee: Int {
        return parameters.count
    }

    // Returns type information of expected arguments to the function
    public var callerTypes: [Type] {
        return parameters.map({ $0.callerType })
    }

    public init(expects parameters: [Parameter], returns returnType: Type) {
        self.parameters = parameters
        self.outputType = returnType
        Assert(isValid())
    }

    /// Constructs a function with N parameters of type .anything and producing .unknown.
    public init(withParameterCount numParameters: Int, hasRestParam: Bool = false) {
        self.outputType = .unknown
        var parameters = Array<Parameter>(repeating: .plain(.anything), count: numParameters)
        if hasRestParam && numParameters > 0 {
            parameters[parameters.endIndex - 1] = .rest(.anything)
        }
        self.parameters = parameters
    }

    // The most generic function signature: varargs function returning .unknown
    public static let forUnknownFunction = [.rest(.anything)] => .unknown

    func hasVarargsParameter() -> Bool {
        return parameters.last?.isRestParam ?? false
    }

    func isValid() -> Bool {
        var sawOptionals = false
        for (i, p) in parameters.enumerated() {
            // Must not have .nothing, .unknown as parameters.
            if p.callerType == .nothing || p.callerType == .unknown {
                return false
            }

            // Must not have varargs except in the last position.
            if p.isRestParam {
                return i == parameters.count - 1
            }

            // Once we saw the first optional parameter (one that may be .undefined),
            // we must not see any more non-optional parameters.
            if p.isOptional {
                sawOptionals = true
            } else if sawOptionals {
                return false
            }
        }
        return true
    }
}

/// The custom infix operator => is used to build up function signatures.
infix operator =>: AdditionPrecedence
public func => (paramTypes: [Parameter], returnType: Type) -> FunctionSignature {
    return FunctionSignature(expects: paramTypes, returns: returnType)
}

extension Type: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_Type

    func asProtobuf(with typeCache: TypeCache?) -> ProtobufType {
        return ProtobufType.with {
            $0.definiteType = definiteType.rawValue
            $0.possibleType = possibleType.rawValue

            if let typeExtension = ext {
                // See if we can use the cache
                if let idx = typeCache?.get(typeExtension) {
                    $0.extensionIdx = UInt32(idx)
                    return
                }

                $0.extension.properties = Array(typeExtension.properties)
                $0.extension.methods = Array(typeExtension.methods)

                if let group = typeExtension.group {
                    $0.extension.group = group
                }
                if let signature = typeExtension.signature {
                    $0.extension.signature = signature.asProtobuf(with: typeCache)
                }

                typeCache?.add(typeExtension)
            }
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtobufType, with typeCache: TypeCache?) throws {
        var ext: TypeExtension? = nil

        if let protoExt = proto.ext {
            switch protoExt {
            case .extensionIdx(let idx):
                guard let cachedExt = typeCache?.get(Int(idx)) else {
                    throw FuzzilliError.typeDecodingError("invalid type extension index or no type cache used")
                }
                ext = cachedExt
            case .extension(let protoExtension):
                ext = TypeExtension(group: !protoExtension.group.isEmpty ? protoExtension.group : nil,
                                    properties: Set(protoExtension.properties),
                                    methods: Set(protoExtension.methods),
                                    signature: protoExtension.hasSignature ? try FunctionSignature(from: protoExtension.signature, with: typeCache) : nil)
                typeCache?.add(ext!)
            }
        }

        let definiteType = BaseType(rawValue: proto.definiteType)
        let possibleType = BaseType(rawValue: proto.possibleType)
        let allowedTypes = BaseType([BaseType.anything])
        guard allowedTypes.contains(definiteType) && allowedTypes.contains(possibleType) else {
            throw FuzzilliError.typeDecodingError("invalid base type")
        }

        self.init(definiteType: definiteType, possibleType: possibleType, ext: ext)
    }

    public init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}

extension FunctionSignature: ProtobufConvertible {
    typealias ProtobufType = Fuzzilli_Protobuf_FunctionSignature

    func asProtobuf(with typeCache: TypeCache?) -> ProtobufType {
        return ProtobufType.with {
            $0.parameters = parameters.map({ $0.asProtobuf(with: typeCache) })
            $0.outputType = outputType.asProtobuf(with: typeCache)
        }
    }

    func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtobufType, with typeCache: TypeCache?) throws {
        self.init(expects: try proto.parameters.map({ try Parameter(from: $0, with: typeCache) }),
                  returns: try Type(from: proto.outputType, with: typeCache))
    }

    init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}
