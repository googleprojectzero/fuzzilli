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

/// Model of the execution environment.
public protocol Environment: Component {
    /// List of integer values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingIntegers: [Int64] { get }

    /// List of floating point values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingFloats: [Double] { get }

    /// List of string values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingStrings: [String] { get }

    /// List of RegExp patterns.
    var interestingRegExps: [(pattern: String, incompatibleFlags: RegExpFlags)] { get }

    /// List of RegExp quantifiers.
    var interestingRegExpQuantifiers: [String] { get }

    /// List of all builtin objects in the target environment.
    var builtins: Set<String> { get }

    /// Custom property names to use when defining new properties on objects.
    /// These should not exist on builtin objects.
    var customProperties: Set<String> { get }

    /// List of properties that exist on at least one type of builtin objects.
    var builtinProperties: Set<String> { get }

    /// Custom method names to use when defining new methods on objects.
    /// These should not exist on builtin objects.
    var customMethods: Set<String> { get }

    /// List of methods that exist on at least one builtin object.
    var builtinMethods: Set<String> { get }


    /// The type representing integers in the target environment.
    var intType: ILType { get }

    /// The type representing bigints in the target environment.
    var bigIntType: ILType { get }

    /// The type representing RegExps in the target environment.
    var regExpType: ILType { get }

    /// The type representing floats in the target environment.
    var floatType: ILType { get }

    /// The type representing booleans in the target environment.
    var booleanType: ILType { get }

    /// The type representing strings in the target environment.
    var stringType: ILType { get }

    /// The type of an empty object (i.e. one to which no properties or methods have been added yet) in the target environment.
    var emptyObjectType: ILType { get }

    /// The type representing arrays in the target environment.
    /// Used e.g. for arrays created through a literal.
    var arrayType: ILType { get }

    /// The type of a function's arguments object, i.e. the output type of `LoadArguments`.
    var argumentsType: ILType { get }

    /// The return type of generator functions.
    var generatorType: ILType { get }

    /// The return type of async functions.
    var promiseType: ILType { get }


    /// Returns true if the given type is a builtin, e.g. can be constructed
    /// This is useful for types that are dictionary config objects, as we will have an object group for them, i.e. type(ofProperty, on) will work but type(ofBuiltin) won't
    func hasBuiltin(_ name: String) -> Bool

    /// Returns true if we have an object group associated with this name
    /// config objects have a group but no constructor, i.e. loadable builtin associated
    func hasGroup(_ name: String) -> Bool

    /// Returns the type of the builtin with the given name.
    func type(ofBuiltin builtinName: String) -> ILType

    /// Returns the instance type of the object group with the specified name.
    func type(ofGroup groupName: String) -> ILType

    /// Returns the type of the property on the provided base object.
    func type(ofProperty propertyName: String, on baseType: ILType) -> ILType

    /// Returns the signatures of the overloads of the specified method of the base object.
    func signatures(ofMethod methodName: String, on baseType: ILType) -> [Signature]

    /// Returns a list of (object group name, method name) pairs for a given type. The specified
    /// method on the specified object group can be called to generate the given type.
    func getProducingMethods(ofType type: ILType) -> [(group: String, method: String)]

    /// Returns a list of (object group name, property name) pairs for a given type. The specified
    /// property either has the given type, or is a constructor of that type. If the group name is
    /// empty, then the `property name` is either a global property, or a global constructor.
    func getProducingProperties(ofType type: ILType) -> [(group: String, property: String)]

    /// Returns a list of all subtypes of a given type.
    func getSubtypes(ofType type: ILType) -> [ILType]

    /// Helper function that checks if `type` is contained in the result of `getSubtypes`
    func isSubtype(_ type: ILType, of parent: ILType) -> Bool
}
