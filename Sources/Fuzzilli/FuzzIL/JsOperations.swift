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

/// A JavaScript operation in the FuzzIL language.
public class JsOperation: Operation {
}

class LoadInteger: JsOperation {
    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class LoadBigInt: JsOperation {
    // This could be a bigger integer type, but it's most likely not worth the effort
    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class LoadFloat: JsOperation {
    let value: Double

    init(value: Double) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class LoadString: JsOperation {
    let value: String

    init(value: String) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class LoadBoolean: JsOperation {
    let value: Bool

    init(value: Bool) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class LoadUndefined: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure])
    }
}

class LoadNull: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure])
    }
}

class LoadThis: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure])
    }
}

class LoadArguments: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure], requiredContext: [.javascript, .subroutine])
    }
}

public struct RegExpFlags: OptionSet, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public func asString() -> String {
        var strRepr = ""
        for (flag, char) in RegExpFlags.flagToCharDict {
            if contains(flag) {
                strRepr += char
            }
        }
        return strRepr
    }

    static let caseInsensitive = RegExpFlags(rawValue: 1 << 0)
    static let global          = RegExpFlags(rawValue: 1 << 1)
    static let multiline       = RegExpFlags(rawValue: 1 << 2)
    static let dotall          = RegExpFlags(rawValue: 1 << 3)
    static let unicode         = RegExpFlags(rawValue: 1 << 4)
    static let sticky          = RegExpFlags(rawValue: 1 << 5)

    public static func random() -> RegExpFlags {
        return RegExpFlags(rawValue: UInt32.random(in: 0..<(1<<6)))
    }

    private static let flagToCharDict: [RegExpFlags:String] = [
        .caseInsensitive: "i",
        .global:          "g",
        .multiline:       "m",
        .dotall:          "s",
        .unicode:         "u",
        .sticky:          "y",
    ]
}

class LoadRegExp: JsOperation {
    let flags: RegExpFlags
    let value: String

    init(value: String, flags: RegExpFlags) {
        self.value = value
        self.flags = flags
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

class CreateObject: JsOperation {
    let propertyNames: [String]

    init(propertyNames: [String]) {
        self.propertyNames = propertyNames
        var flags: Operation.Attributes = [.isVariadic]
        if propertyNames.count > 0 {
            flags.insert(.isMutable)
        }
        super.init(numInputs: propertyNames.count, numOutputs: 1, firstVariadicInput: 0, attributes: flags)
    }
}

class CreateArray: JsOperation {
    var numInitialValues: Int {
        return numInputs
    }

    init(numInitialValues: Int) {
        super.init(numInputs: numInitialValues, numOutputs: 1, firstVariadicInput: 0, attributes: [.isVariadic])
    }
}

class CreateObjectWithSpread: JsOperation {
    // The property names of the "regular" properties. The remaining input values will be spread.
    let propertyNames: [String]

    var numSpreads: Int {
        return numInputs - propertyNames.count
    }

    init(propertyNames: [String], numSpreads: Int) {
        self.propertyNames = propertyNames
        var flags: Operation.Attributes = [.isVariadic]
        if propertyNames.count > 0 {
            flags.insert([.isMutable])
        }
        super.init(numInputs: propertyNames.count + numSpreads, numOutputs: 1, firstVariadicInput: 0, attributes: flags)
    }
}

class CreateArrayWithSpread: JsOperation {
    // Which inputs to spread.
    let spreads: [Bool]

    init(spreads: [Bool]) {
        self.spreads = spreads
        var flags: Operation.Attributes = [.isVariadic]
        if spreads.count > 0 {
            flags.insert([.isMutable])
        }
        super.init(numInputs: spreads.count, numOutputs: 1, firstVariadicInput: 0, attributes: flags)
    }
}

class CreateTemplateString: JsOperation {
    // Stores the string elements of the template literal
    let parts: [String]

    var numInterpolatedValues: Int {
        return numInputs
    }

    // This operation isn't mutable since it will most likely mutate imported templates (which would mostly be valid JS snippets) and
    // replace them with random strings and/or other template strings that may not be syntactically and/or semantically valid.
    init(parts: [String]) {
        assert(parts.count > 0)
        self.parts = parts
        super.init(numInputs: parts.count - 1, numOutputs: 1, firstVariadicInput: 0, attributes: [.isVariadic])
    }
}

class LoadBuiltin: JsOperation {
    let builtinName: String

    init(builtinName: String) {
        self.builtinName = builtinName
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isMutable])
    }
}

class LoadProperty: JsOperation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

class StoreProperty: JsOperation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isMutable])
    }
}

class StorePropertyWithBinop: JsOperation {
    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isMutable])
    }
}

class DeleteProperty: JsOperation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

class LoadElement: JsOperation {
    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

class StoreElement: JsOperation {
    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isMutable])
    }
}

class StoreElementWithBinop: JsOperation {
    let index: Int64
    let op: BinaryOperator

    init(index: Int64, operator op: BinaryOperator) {
        self.index = index
        self.op = op
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isMutable])
    }
}

class DeleteElement: JsOperation {
    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

class LoadComputedProperty: JsOperation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class StoreComputedProperty: JsOperation {
    init() {
        super.init(numInputs: 3, numOutputs: 0)
    }
}

class StoreComputedPropertyWithBinop: JsOperation {
    let op: BinaryOperator

    init(operator op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 3, numOutputs: 0)
    }
}

class DeleteComputedProperty: JsOperation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class TypeOf: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

class TestInstanceOf: JsOperation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class TestIn: JsOperation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

//
class Explore: JsOperation {
    let id: String

    init(id: String, numArguments: Int) {
        self.id = id
        super.init(numInputs: numArguments + 1, numOutputs: 0)
    }
}

// The parameters of a FuzzIL subroutine.
public struct Parameters {
    /// The total number of parameters.
    private let numParameters: UInt32
    /// Whether the last parameter is a rest parameter.
    let hasRestParameter: Bool

    /// The total number of parameters. This is equivalent to the number of inner outputs produced from the parameters.
    var count: Int {
        return Int(numParameters)
    }

    init(count: Int, hasRestParameter: Bool = false) {
        self.numParameters = UInt32(count)
        self.hasRestParameter = hasRestParameter
    }
}

// Subroutine definitions.
// A subroutine is the umbrella term for any invocable unit of code. Functions, (class) constructors, and methods are all subroutines.
// This intermediate Operation class contains the parameters of the surbroutine and makes it easy to identify whenever .subroutine context is opened.
class BeginAnySubroutine: JsOperation {
    let parameters: Parameters

    init(parameters: Parameters, numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, attributes: Operation.Attributes, contextOpened: Context) {
        assert(contextOpened.contains(.subroutine))
        self.parameters = parameters
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, attributes: attributes, contextOpened: contextOpened)
    }
}

class EndAnySubroutine: JsOperation {
    init(attributes: Operation.Attributes) {
        super.init(numInputs: 0, numOutputs: 0, attributes: attributes)
    }
}

// Function definitions.
// Roughly speaking, a function is any subroutine that is defined through the 'function' keyword in JavaScript or an arrow function.
// Functions beginnings are not considered mutable since it likely makes little sense to change things like the number of parameters.
// It also likely makes little sense to switch a function into/out of strict mode. As such, these attributes are permanent.
class BeginAnyFunction: BeginAnySubroutine {
    let isStrict: Bool

    init(parameters: Parameters, isStrict: Bool, contextOpened: Context = [.javascript, .subroutine]) {
        self.isStrict = isStrict
        super.init(parameters: parameters,
                   numInputs: 0,
                   numOutputs: 1,
                   numInnerOutputs: parameters.count,
                   attributes: [.isBlockStart], contextOpened: contextOpened)
    }
}

class EndAnyFunction: EndAnySubroutine {
    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

// A plain function
class BeginPlainFunction: BeginAnyFunction {}
class EndPlainFunction: EndAnyFunction {}

// A ES6 arrow function
class BeginArrowFunction: BeginAnyFunction {}
class EndArrowFunction: EndAnyFunction {}

// A ES6 generator function
class BeginGeneratorFunction: BeginAnyFunction {
    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .generatorFunction])
    }
}
class EndGeneratorFunction: EndAnyFunction {}

// A ES6 async function
class BeginAsyncFunction: BeginAnyFunction {
    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
class EndAsyncFunction: EndAnyFunction {}

// A ES6 async arrow function
class BeginAsyncArrowFunction: BeginAnyFunction {
    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
class EndAsyncArrowFunction: EndAnyFunction {}

// A ES6 async generator function
class BeginAsyncGeneratorFunction: BeginAnyFunction {
    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction, .generatorFunction])
    }
}
class EndAsyncGeneratorFunction: EndAnyFunction {}

class Return: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump], requiredContext: [.javascript, .subroutine])
    }
}

// A yield expression in JavaScript
class Yield: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

// A yield* expression in JavaScript
class YieldEach: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

class Await: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.javascript, .asyncFunction])
    }
}

class CallFunction: JsOperation {
    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int) {
        // The called function is the first input.
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

class CallFunctionWithSpread: JsOperation {
    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, spreads: [Bool]) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The called function is the first input.
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall, .isMutable])
    }
}

class Construct: JsOperation {
    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int) {
        // The constructor is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

class ConstructWithSpread: JsOperation {
    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, spreads: [Bool]) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The constructor is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall, .isMutable])
    }
}

class CallMethod: JsOperation {
    let methodName: String

    var numArguments: Int {
        return numInputs - 1
    }

    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        // reference object is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isMutable, .isVariadic, .isCall])
    }
}

class CallMethodWithSpread: JsOperation {
    let methodName: String
    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(methodName: String, numArguments: Int, spreads: [Bool]) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.methodName = methodName
        self.spreads = spreads
        // reference object is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isMutable, .isVariadic, .isCall])
    }
}

class CallComputedMethod: JsOperation {
    var numArguments: Int {
        return numInputs - 2
    }

    init(numArguments: Int) {
        // The reference object is the first input and method name is the second input
        super.init(numInputs: numArguments + 2, numOutputs: 1, firstVariadicInput: 2, attributes: [.isVariadic, .isCall])
    }
}

class CallComputedMethodWithSpread: JsOperation {
    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 2
    }

    init(numArguments: Int, spreads: [Bool]) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The reference object is the first input and the method name is the second input
        super.init(numInputs: numArguments + 2, numOutputs: 1, firstVariadicInput: 2, attributes: [.isVariadic, .isCall, .isMutable])
    }
}

public enum UnaryOperator: String, CaseIterable {
    case PreInc     = "++"
    case PreDec     = "--"
    case PostInc    = "++ "     // Raw value must be unique
    case PostDec    = "-- "     // Raw value must be unique
    case LogicalNot = "!"
    case BitwiseNot = "~"
    case Plus       = "+"
    case Minus      = "-"

    var token: String {
        return self.rawValue.trimmingCharacters(in: [" "])
    }

    var reassignsInput: Bool {
        return self == .PreInc || self == .PreDec || self == .PostInc || self == .PostDec
    }

    var isPostfix: Bool {
        return self == .PostInc || self == .PostDec
    }
}

// This array must be kept in sync with the UnaryOperator Enum in operations.proto
let allUnaryOperators = UnaryOperator.allCases

class UnaryOperation: JsOperation {
    let op: UnaryOperator

    init(_ op: UnaryOperator) {
        self.op = op
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

public enum BinaryOperator: String, CaseIterable {
    case Add      = "+"
    case Sub      = "-"
    case Mul      = "*"
    case Div      = "/"
    case Mod      = "%"
    case BitAnd   = "&"
    case BitOr    = "|"
    case LogicAnd = "&&"
    case LogicOr  = "||"
    case Xor      = "^"
    case LShift   = "<<"
    case RShift   = ">>"
    case Exp      = "**"
    case UnRShift = ">>>"

    var token: String {
        return self.rawValue
    }
}

// This array must be kept in sync with the BinaryOperator Enum in operations.proto
let allBinaryOperators = BinaryOperator.allCases

class BinaryOperation: JsOperation {
    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable])
    }
}

/// Assigns a value to its left operand based on the value of its right operand.
class ReassignWithBinop: JsOperation {
    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 0)
    }
}

/// Duplicates a variable, essentially doing `output = input;`
class Dup: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

/// Reassigns an existing variable, essentially doing `input1 = input2;`
class Reassign: JsOperation {
    init() {
        super.init(numInputs: 2, numOutputs: 0)
    }
}

/// Destructs an array into n output variables
class DestructArray: JsOperation {
    let indices: [Int]
    let hasRestElement: Bool

    init(indices: [Int], hasRestElement: Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numOutputs: indices.count)
    }
}

/// Destructs an array and reassigns the output to n existing variables
class DestructArrayAndReassign: JsOperation {
    let indices: [Int]
    let hasRestElement: Bool

    init(indices: [Int], hasRestElement:Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.hasRestElement = hasRestElement
        // The first input is the array being destructed
        super.init(numInputs: 1 + indices.count, numOutputs: 0)
    }
}

/// Destructs an object into n output variables
class DestructObject: JsOperation {
    let properties: [String]
    let hasRestElement: Bool

    init(properties: [String], hasRestElement: Bool) {
        assert(!properties.isEmpty || hasRestElement, "Must have at least one output")
        self.properties = properties
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numOutputs: properties.count + (hasRestElement ? 1 : 0))
    }
}

/// Destructs an object and reassigns the output to n existing variables
class DestructObjectAndReassign: JsOperation {
    let properties: [String]
    let hasRestElement: Bool

    init(properties: [String], hasRestElement:Bool) {
        assert(!properties.isEmpty || hasRestElement, "Must have at least one input variable to reassign")
        self.properties = properties
        self.hasRestElement = hasRestElement
        // The first input is the object being destructed
        super.init(numInputs: 1 + properties.count + (hasRestElement ? 1 : 0), numOutputs: 0)
    }
}

// This array must be kept in sync with the Comparator Enum in operations.proto
public enum Comparator: String {
    case equal              = "=="
    case strictEqual        = "==="
    case notEqual           = "!="
    case strictNotEqual     = "!=="
    case lessThan           = "<"
    case lessThanOrEqual    = "<="
    case greaterThan        = ">"
    case greaterThanOrEqual = ">="

    var token: String {
        return self.rawValue
    }
}

let allComparators: [Comparator] = [.equal, .strictEqual, .notEqual, .strictNotEqual, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual]

class Compare: JsOperation {
    let op: Comparator

    init(_ comparator: Comparator) {
        self.op = comparator
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable])
    }
}

/// Allows generation of conditional (i.e. condition ? exprIfTrue : exprIfFalse) statements
class ConditionalOperation: JsOperation {
    init() {
        super.init(numInputs: 3, numOutputs: 1)
    }
}

/// An operation that will be lifted to a given string. The string can use %@ placeholders which
/// will be replaced by the expressions for the input variables during lifting.
class Eval: JsOperation {
    let code: String

    init(_ string: String, numArguments: Int) {
        self.code = string
        super.init(numInputs: numArguments, numOutputs: 0, numInnerOutputs: 0)
    }
}

class BeginWith: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .with])
    }
}

class EndWith: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class LoadFromScope: JsOperation {
    let id: String

    init(id: String) {
        self.id = id
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .with])
    }
}

class StoreToScope: JsOperation {
    let id: String

    init(id: String) {
        self.id = id
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isMutable], requiredContext: [.javascript, .with])
    }
}

///
/// Classes
///
/// Classes in FuzzIL look roughly as follows:
///
///     BeginClass superclass, properties, methods, constructor parameters
///         < constructor code >
///     BeginMethod
///         < code of first method >
///     BeginMethod
///         < code of second method >
///     EndClass
///
///  This design solves the following two requirements:
///  - All information about the instance type must be contained in the BeginClass operation so that
///    the JSTyper and other static analyzers have the instance type when processing the body
///  - Method definitions must be part of a block group and not standalone blocks. Otherwise, splicing might end
///    up copying only a method definition without the surrounding class definition, which would be syntactically invalid.
///
/// TODO refactor this by creating BeginMethod/EndMethod pairs (and similar for the constructor). Then use BeginAnySubroutine as well.
class BeginClass: JsOperation {
    let hasSuperclass: Bool
    let constructorParameters: Parameters
    let instanceProperties: [String]
    let instanceMethods: [(name: String, parameters: Parameters)]

    init(hasSuperclass: Bool,
         constructorParameters: Parameters,
         instanceProperties: [String],
         instanceMethods: [(String, Parameters)]) {
        self.hasSuperclass = hasSuperclass
        self.constructorParameters = constructorParameters
        self.instanceProperties = instanceProperties
        self.instanceMethods = instanceMethods
        super.init(numInputs: hasSuperclass ? 1 : 0,
                   numOutputs: 1,
                   numInnerOutputs: 1 + constructorParameters.count,    // Implicit this is first inner output
                   attributes: [.isBlockStart], contextOpened: [.javascript, .classDefinition, .subroutine])
    }
}

// A class instance method. Always has the implicit |this| parameter as first inner output.
class BeginMethod: JsOperation {
    // TODO refactor this: move the Parameters and name into BeginMethod.
    var numParameters: Int {
        return numInnerOutputs - 1
    }

    init(numParameters: Int) {
        super.init(numInputs: 0,
                   numOutputs: 0,
                   numInnerOutputs: 1 + numParameters,      // Implicit this is first inner output
                   attributes: [.isBlockStart, .isBlockEnd], requiredContext: .classDefinition, contextOpened: [.javascript, .classDefinition, .subroutine])
    }
}

class EndClass: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class CallSuperConstructor: JsOperation {
    var numArguments: Int {
        return numInputs
    }

    init(numArguments: Int) {
        super.init(numInputs: numArguments, numOutputs: 0, firstVariadicInput: 0, attributes: [.isVariadic, .isCall], requiredContext: [.javascript, .classDefinition])
    }
}

class CallSuperMethod: JsOperation {
    let methodName: String

    var numArguments: Int {
        return numInputs
    }

    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        super.init(numInputs: numArguments, numOutputs: 1, firstVariadicInput: 0, attributes: [.isCall, .isMutable, .isVariadic], requiredContext: [.javascript, .classDefinition])
    }
}

class LoadSuperProperty: JsOperation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

class StoreSuperProperty: JsOperation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

class StoreSuperPropertyWithBinop: JsOperation {
    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

///
/// Control Flow
///
class ControlFlowOperation: JsOperation {
    init(numInputs: Int, numInnerOutputs: Int = 0, attributes: Operation.Attributes, contextOpened: Context = .javascript) {
        assert(attributes.contains(.isBlockStart) || attributes.contains(.isBlockEnd))
        super.init(numInputs: numInputs, numOutputs: 0, numInnerOutputs: numInnerOutputs, attributes: attributes.union(.propagatesSurroundingContext), contextOpened: contextOpened)
    }
}

class BeginIf: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart])
    }
}

class BeginElse: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isBlockStart])
    }
}

class EndIf: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class BeginWhileLoop: ControlFlowOperation {
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class EndWhileLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoop])
    }
}

// Even though the loop condition is evaluated during EndDoWhile,
// the inputs are kept in BeginDoWhile as they have to come from
// the outer scope. Otherwise, special handling of EndDoWhile would
// be necessary throughout the IL, this way, only the Lifter has to
// be a bit more clever.
class BeginDoWhileLoop: ControlFlowOperation {
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class EndDoWhileLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoop])
    }
}

class BeginForLoop: ControlFlowOperation {
    let comparator: Comparator
    let op: BinaryOperator
    init(comparator: Comparator, op: BinaryOperator) {
        self.comparator = comparator
        self.op = op
        super.init(numInputs: 3, numInnerOutputs: 1, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class EndForLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoop])
    }
}

class BeginForInLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class EndForInLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoop])
    }
}

class BeginForOfLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class BeginForOfWithDestructLoop: ControlFlowOperation {
    let indices: [Int]
    let hasRestElement: Bool

    init(indices: [Int], hasRestElement: Bool) {
        assert(indices.count >= 1)
        self.indices = indices
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numInnerOutputs: indices.count, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

class EndForOfLoop: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoop])
    }
}

class LoopBreak: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

class LoopContinue: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

class BeginTry: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockStart])
    }
}

class BeginCatch: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, numInnerOutputs: 1, attributes: [.isBlockStart, .isBlockEnd])
    }
}

class BeginFinally: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockStart, .isBlockEnd])
    }
}

class EndTryCatchFinally: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class ThrowException: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump])
    }
}

/// Generates a block of instructions, which is lifted to a string literal, that is a suitable as an argument to eval()
class BeginCodeString: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isBlockStart], contextOpened: .javascript)
    }
}

class EndCodeString: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

/// Generates a block of instructions, which is lifted to a block statement.
class BeginBlockStatement: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

class EndBlockStatement: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

///
/// Switch-Cases
///
/// (1) Represent switch-case as a single block group, started by a BeginSwitch
///     and with each case started by a BeginSwitchCase:
///
///         BeginSwitch
///             // instructions of the first case
///         BeginSwitchCase
///             // instructions of the second case
///         BeginSwitchCase
///             // instructions of the third case
///         BeginSwitchDefaultCase
///             // instructions of the default case
///         ...
///         EndSwitch
///
///     The main issue with this design is that it makes it hard to add new
///     cases through splicing or code generation add new BeginSwitchCase
///     instructions into this program as this would 'cut' an existing
///     BeginSwitchCase sub-block into two halves, producing invalid code. Due
///     to that limitation, the minimizer is then also unable to minize these
///     BeginSwitchCase blocks as this would violate the "any feature removed
///     by the minimizer can be added back by a mutator" invariant. The result
///     is static switch blocks that are never mutated and often nedlessly keep
///     many other variables alive.
///
/// (2) Represent switch-case as a switch block with sub-blocks for the cases:
///
///         BeginSwitch
///             BeginSwitchCase
///                // instructions of the first case
///             EndSwitchCase
///             BeginSwitchCase
///                // instructions of the second case
///             EndSwitchCase
///             BeginSwitchCase
///                 // instructions of the third case
///             EndSwitchCase
///             BeginSwitchDefaultCase
///                 // instructions of the default case
///             EndSwitchCase
///             ...
///         EndSwitch
///
///     Inside the BeginSwitch, there is a .switchBlock but no .script context
///     and so only BeginSwitchCase and EndSwitchCase can be placed there. This
///     then trivially allows adding new cases from code generation or splicing,
///     in turn allowing proper minimization of switch-case blocks.
///
class BeginSwitch: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isBlockStart], contextOpened: [.switchBlock])
    }
}

class BeginSwitchCase: JsOperation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isBlockStart, .skipsSurroundingContext], requiredContext: [.switchBlock], contextOpened: [.switchCase])
    }
}

/// This is the default case, it has no inputs, this is always in a BeginSwitch/EndSwitch block group.
/// We currently do not minimize this away. It is expected for other minimizers to reduce the contents of this block,
/// such that, if necessary, the BeginSwitch/EndSwitch reducer can remove the whole switch case altogether.
class BeginSwitchDefaultCase: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockStart, .skipsSurroundingContext], requiredContext: [.switchBlock], contextOpened: [.switchCase])
    }
}

/// This ends BeginSwitchCase and BeginDefaultSwitchCase blocks.
class EndSwitchCase: JsOperation {
    /// If true, causes this case to fall through (and so no "break;" is emitted by the Lifter)
    let fallsThrough: Bool

    init(fallsThrough: Bool) {
        self.fallsThrough = fallsThrough
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class EndSwitch: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd], requiredContext: [.switchBlock])
    }
}

class SwitchBreak: JsOperation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump], requiredContext: [.javascript, .switchCase])
    }
}

/// Internal operations.
///
/// These can be used for internal fuzzer operations but will not appear in the corpus.
class InternalOperation: Operation {
    init(numInputs: Int) {
        super.init(numInputs: numInputs, numOutputs: 0, attributes: [.isInternal])
    }
}

/// Writes the argument to the output stream.
class Print: InternalOperation {
    init() {
        super.init(numInputs: 1)
    }
}
