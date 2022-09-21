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
    var interestingRegExps: [String] { get }

    /// List of RegExp quantifiers.
    var interestingRegExpQuantifiers: [String] { get }

    /// List of all builtin objects in the target environment.
    var builtins: Set<String> { get }

    /// List of all method names in the target environment.
    var methodNames: Set<String> { get }

    /// List of all property names in the target environment that can be read. This generally includes method names.
    var readPropertyNames: Set<String> { get }

    /// List of all property names in the target environment that can be written. This is expected to be a subset of readPropertyNames.
    var writePropertyNames: Set<String> { get }

    /// List of all custom property names, i.e. ones that don't exist by default on any object. This is expected to be a subset of writePropertyNames.
    var customPropertyNames: Set<String> { get }

    /// List of custom Method names, this is used during ProgramBuilder.generateVariable and in ProgramTemplate.generateType
    var customMethodNames: Set<String> { get }

    /// The type representing integers in the target environment.
    var intType: Type { get }

    /// The type representing bigints in the target environment.
    var bigIntType: Type { get }

    /// The type representing RegExps in the target environment.
    var regExpType: Type { get }

    /// The type representing floats in the target environment.
    var floatType: Type { get }

    /// The type representing booleans in the target environment.
    var booleanType: Type { get }

    /// The type representing strings in the target environment.
    var stringType: Type { get }

    /// The type representing plain objects in the target environment.
    /// Used e.g. for objects created through a literal.
    var objectType: Type { get }

    /// The type representing arrays in the target environment.
    /// Used e.g. for arrays created through a literal.
    var arrayType: Type { get }

    /// All other types exposed by the environment for which a constructor builtin exists. E.g. Uint8Array or Symbol in Javascript.
    var constructables: [String] { get }

    /// Retuns the type representing a function with the given signature.
    func functionType(forSignature signature: FunctionSignature) -> Type

    /// Retuns the type of the builtin with the given name.
    func type(ofBuiltin builtinName: String) -> Type

    /// Returns the type of the property on the provided base object.
    func type(ofProperty propertyName: String, on baseType: Type) -> Type

    /// Returns the signature of the specified method of he base object.
    func signature(ofMethod methodName: String, on baseType: Type) -> FunctionSignature
}
