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
class JsOperation: Operation {
    override init(numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, firstVariadicInput: Int = -1, attributes: Attributes = [], requiredContext: Context = .javascript, contextOpened: Context = .empty) {
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, firstVariadicInput: firstVariadicInput, attributes: attributes, requiredContext: requiredContext, contextOpened: contextOpened)
    }
}

final class LoadInteger: JsOperation {
    override var opcode: Opcode { .loadInteger(self) }

    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class LoadBigInt: JsOperation {
    override var opcode: Opcode { .loadBigInt(self) }

    // This could be a bigger integer type, but it's most likely not worth the effort
    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class LoadFloat: JsOperation {
    override var opcode: Opcode { .loadFloat(self) }

    let value: Double

    init(value: Double) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class LoadString: JsOperation {
    override var opcode: Opcode { .loadString(self) }

    let value: String

    init(value: String) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class LoadBoolean: JsOperation {
    override var opcode: Opcode { .loadBoolean(self) }

    let value: Bool

    init(value: Bool) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class LoadUndefined: JsOperation {
    override var opcode: Opcode { .loadUndefined(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isPure])
    }
}

final class LoadNull: JsOperation {
    override var opcode: Opcode { .loadNull(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isPure])
    }
}

final class LoadThis: JsOperation {
    override var opcode: Opcode { .loadThis(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isPure])
    }
}

final class LoadArguments: JsOperation {
    override var opcode: Opcode { .loadArguments(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isPure], requiredContext: [.javascript, .subroutine])
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

final class LoadRegExp: JsOperation {
    override var opcode: Opcode { .loadRegExp(self) }

    let flags: RegExpFlags
    let value: String

    init(value: String, flags: RegExpFlags) {
        self.value = value
        self.flags = flags
        super.init(numOutputs: 1, attributes: [.isPure, .isMutable])
    }
}

final class CreateObject: JsOperation {
    override var opcode: Opcode { .createObject(self) }

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

final class CreateArray: JsOperation {
    override var opcode: Opcode { .createArray(self) }

    var numInitialValues: Int {
        return numInputs
    }

    init(numInitialValues: Int) {
        super.init(numInputs: numInitialValues, numOutputs: 1, firstVariadicInput: 0, attributes: [.isVariadic])
    }
}

final class CreateIntArray: JsOperation {
    override var opcode: Opcode { .createIntArray(self) }

    let values: [Int64]

    init(values: [Int64]) {
        self.values = values
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class CreateFloatArray: JsOperation {
    override var opcode: Opcode { .createFloatArray(self) }

    let values: [Double]

    init(values: [Double]) {
        self.values = values
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class CreateObjectWithSpread: JsOperation {
    override var opcode: Opcode { .createObjectWithSpread(self) }

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

final class CreateArrayWithSpread: JsOperation {
    override var opcode: Opcode { .createArrayWithSpread(self) }

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

final class CreateTemplateString: JsOperation {
    override var opcode: Opcode { .createTemplateString(self) }

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

final class LoadBuiltin: JsOperation {
    override var opcode: Opcode { .loadBuiltin(self) }

    let builtinName: String

    init(builtinName: String) {
        self.builtinName = builtinName
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadProperty: JsOperation {
    override var opcode: Opcode { .loadProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

final class StoreProperty: JsOperation {
    override var opcode: Opcode { .storeProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 2, attributes: [.isMutable])
    }
}

final class StorePropertyWithBinop: JsOperation {
    override var opcode: Opcode { .storePropertyWithBinop(self) }

    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 2, attributes: [.isMutable])
    }
}

final class DeleteProperty: JsOperation {
    override var opcode: Opcode { .deleteProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

public struct PropertyFlags: OptionSet {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let writable         = PropertyFlags(rawValue: 1 << 0)
    static let configurable     = PropertyFlags(rawValue: 1 << 1)
    static let enumerable       = PropertyFlags(rawValue: 1 << 2)

    public static func random() -> PropertyFlags {
        return PropertyFlags(rawValue: UInt8.random(in: 0..<8))
    }
}

enum PropertyType: CaseIterable {
    case value
    case getter
    case setter
    case getterSetter
}

final class ConfigureProperty: JsOperation {
    override var opcode: Opcode { .configureProperty(self) }

    let propertyName: String
    let flags: PropertyFlags
    let type: PropertyType

    init(propertyName: String, flags: PropertyFlags, type: PropertyType) {
        self.propertyName = propertyName
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 3 : 2, attributes: [.isMutable])
    }
}

final class LoadElement: JsOperation {
    override var opcode: Opcode { .loadElement(self) }

    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

final class StoreElement: JsOperation {
    override var opcode: Opcode { .storeElement(self) }

    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 2, attributes: [.isMutable])
    }
}

final class StoreElementWithBinop: JsOperation {
    override var opcode: Opcode { .storeElementWithBinop(self) }

    let index: Int64
    let op: BinaryOperator

    init(index: Int64, operator op: BinaryOperator) {
        self.index = index
        self.op = op
        super.init(numInputs: 2, attributes: [.isMutable])
    }
}

final class DeleteElement: JsOperation {
    override var opcode: Opcode { .deleteElement(self) }

    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable])
    }
}

final class ConfigureElement: JsOperation {
    override var opcode: Opcode { .configureElement(self) }

    let index: Int64
    let flags: PropertyFlags
    let type: PropertyType

    init(index: Int64, flags: PropertyFlags, type: PropertyType) {
        self.index = index
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 3 : 2, attributes: [.isMutable])
    }
}

final class LoadComputedProperty: JsOperation {
    override var opcode: Opcode { .loadComputedProperty(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

final class StoreComputedProperty: JsOperation {
    override var opcode: Opcode { .storeComputedProperty(self) }

    init() {
        super.init(numInputs: 3, numOutputs: 0)
    }
}

final class StoreComputedPropertyWithBinop: JsOperation {
    override var opcode: Opcode { .storeComputedPropertyWithBinop(self) }

    let op: BinaryOperator

    init(operator op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 3, numOutputs: 0)
    }
}

final class DeleteComputedProperty: JsOperation {
    override var opcode: Opcode { .deleteComputedProperty(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

final class ConfigureComputedProperty: JsOperation {
    override var opcode: Opcode { .configureComputedProperty(self) }

    let flags: PropertyFlags
    let type: PropertyType

    init(flags: PropertyFlags, type: PropertyType) {
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 4 : 3, attributes: [.isMutable])
    }
}

final class TypeOf: JsOperation {
    override var opcode: Opcode { .typeOf(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

final class TestInstanceOf: JsOperation {
    override var opcode: Opcode { .testInstanceOf(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

final class TestIn: JsOperation {
    override var opcode: Opcode { .testIn(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
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

    init(parameters: Parameters, numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, contextOpened: Context) {
        assert(contextOpened.contains(.subroutine))
        self.parameters = parameters
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, attributes:.isBlockStart, contextOpened: contextOpened)
    }
}

class EndAnySubroutine: JsOperation {
    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

// Function definitions.
// Roughly speaking, a function is any subroutine that is supposed to be invoked via CallFunction. In JavaScript, they are typically defined through the 'function' keyword or an arrow function.
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
                   contextOpened: contextOpened)
    }
}
class EndAnyFunction: EndAnySubroutine {}

// A plain function
final class BeginPlainFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginPlainFunction(self) }
}
final class EndPlainFunction: EndAnyFunction {
    override var opcode: Opcode { .endPlainFunction(self) }
}

// A ES6 arrow function
final class BeginArrowFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginArrowFunction(self) }
}
final class EndArrowFunction: EndAnyFunction {
    override var opcode: Opcode { .endArrowFunction(self) }
}

// A ES6 generator function
final class BeginGeneratorFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginGeneratorFunction(self) }

    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .generatorFunction])
    }
}
final class EndGeneratorFunction: EndAnyFunction {
    override var opcode: Opcode { .endGeneratorFunction(self) }
}

// A ES6 async function
final class BeginAsyncFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginAsyncFunction(self) }

    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
final class EndAsyncFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncFunction(self) }
}

// A ES6 async arrow function
final class BeginAsyncArrowFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginAsyncArrowFunction(self) }

    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
final class EndAsyncArrowFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncArrowFunction(self) }
}

// A ES6 async generator function
final class BeginAsyncGeneratorFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginAsyncGeneratorFunction(self) }

    init(parameters: Parameters, isStrict: Bool) {
        super.init(parameters: parameters, isStrict: isStrict, contextOpened: [.javascript, .subroutine, .asyncFunction, .generatorFunction])
    }
}
final class EndAsyncGeneratorFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncGeneratorFunction(self) }
}

// A constructor.
// This will also be lifted to a plain function in JavaScript. However, in FuzzIL it has an explicit |this| parameter as first inner output.
// A constructor is not a function since it is supposed to be constructed, not called.
final class BeginConstructor: BeginAnySubroutine {
    override var opcode: Opcode { .beginConstructor(self) }

    init(parameters: Parameters) {
        super.init(parameters: parameters, numOutputs: 1, numInnerOutputs: parameters.count + 1, contextOpened: [.javascript, .subroutine])
    }
}
final class EndConstructor: EndAnySubroutine {
    override var opcode: Opcode { .endConstructor(self) }
}

final class Return: JsOperation {
    override var opcode: Opcode { .return(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isJump], requiredContext: [.javascript, .subroutine])
    }
}

// A yield expression in JavaScript
final class Yield: JsOperation {
    override var opcode: Opcode { .yield(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

// A yield* expression in JavaScript
final class YieldEach: JsOperation {
    override var opcode: Opcode { .yieldEach(self) }

    init() {
        super.init(numInputs: 1, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

final class Await: JsOperation {
    override var opcode: Opcode { .await(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.javascript, .asyncFunction])
    }
}

final class CallFunction: JsOperation {
    override var opcode: Opcode { .callFunction(self) }

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int) {
        // The called function is the first input.
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

final class CallFunctionWithSpread: JsOperation {
    override var opcode: Opcode { .callFunctionWithSpread(self) }

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

final class Construct: JsOperation {
    override var opcode: Opcode { .construct(self) }

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int) {
        // The constructor is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

final class ConstructWithSpread: JsOperation {
    override var opcode: Opcode { .constructWithSpread(self) }

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

final class CallMethod: JsOperation {
    override var opcode: Opcode { .callMethod(self) }

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

final class CallMethodWithSpread: JsOperation {
    override var opcode: Opcode { .callMethodWithSpread(self) }

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

final class CallComputedMethod: JsOperation {
    override var opcode: Opcode { .callComputedMethod(self) }

    var numArguments: Int {
        return numInputs - 2
    }

    init(numArguments: Int) {
        // The reference object is the first input and method name is the second input
        super.init(numInputs: numArguments + 2, numOutputs: 1, firstVariadicInput: 2, attributes: [.isVariadic, .isCall])
    }
}

final class CallComputedMethodWithSpread: JsOperation {
    override var opcode: Opcode { .callComputedMethodWithSpread(self) }

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

final class UnaryOperation: JsOperation {
    override var opcode: Opcode { .unaryOperation(self) }

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

final class BinaryOperation: JsOperation {
    override var opcode: Opcode { .binaryOperation(self) }

    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable])
    }
}

/// Ternary operator: a ? b : c.
final class TernaryOperation: JsOperation {
    override var opcode: Opcode { .ternaryOperation(self) }

    init() {
        super.init(numInputs: 3, numOutputs: 1)
    }
}

/// Reassigns an existing variable, essentially doing `input1 = input2;`
final class Reassign: JsOperation {
    override var opcode: Opcode { .reassign(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 0)
    }
}

/// Assigns a value to its left operand based on the value of its right operand.
final class ReassignWithBinop: JsOperation {
    override var opcode: Opcode { .reassignWithBinop(self) }

    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 0)
    }
}

/// Duplicates a variable, essentially doing `output = input;`
final class Dup: JsOperation {
    override var opcode: Opcode { .dup(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

/// Destructs an array into n output variables.
final class DestructArray: JsOperation {
    override var opcode: Opcode { .destructArray(self) }

    let indices: [Int64]
    let hasRestElement: Bool

    init(indices: [Int64], hasRestElement: Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numOutputs: indices.count)
    }
}

/// Destructs an array and reassigns the output to n existing variables.
final class DestructArrayAndReassign: JsOperation {
    override var opcode: Opcode { .destructArrayAndReassign(self) }

    let indices: [Int64]
    let hasRestElement: Bool

    init(indices: [Int64], hasRestElement:Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.hasRestElement = hasRestElement
        // The first input is the array being destructed
        super.init(numInputs: 1 + indices.count, numOutputs: 0)
    }
}

/// Destructs an object into n output variables
final class DestructObject: JsOperation {
    override var opcode: Opcode { .destructObject(self) }

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
final class DestructObjectAndReassign: JsOperation {
    override var opcode: Opcode { .destructObjectAndReassign(self) }

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
public enum Comparator: String, CaseIterable {
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

final class Compare: JsOperation {
    override var opcode: Opcode { .compare(self) }

    let op: Comparator

    init(_ comparator: Comparator) {
        self.op = comparator
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable])
    }
}

/// An operation that will be lifted to a given string. The string can use %@ placeholders which
/// will be replaced by the expressions for the input variables during lifting.
final class Eval: JsOperation {
    override var opcode: Opcode { .eval(self) }

    let code: String

    init(_ string: String, numArguments: Int) {
        self.code = string
        super.init(numInputs: numArguments, numInnerOutputs: 0)
    }
}

final class BeginWith: JsOperation {
    override var opcode: Opcode { .beginWith(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .with])
    }
}

final class EndWith: JsOperation {
    override var opcode: Opcode { .endWith(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class LoadFromScope: JsOperation {
    override var opcode: Opcode { .loadFromScope(self) }

    let id: String

    init(id: String) {
        self.id = id
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .with])
    }
}

final class StoreToScope: JsOperation {
    override var opcode: Opcode { .storeToScope(self) }

    let id: String

    init(id: String) {
        self.id = id
        super.init(numInputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .with])
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
final class BeginClass: JsOperation {
    override var opcode: Opcode { .beginClass(self) }

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
                   numInnerOutputs: 1 + constructorParameters.count,    // Explicit this is first inner output
                   attributes: [.isBlockStart], contextOpened: [.javascript, .classDefinition, .subroutine])
    }
}

// A class instance method. Always has the explicit |this| parameter as first inner output.
final class BeginMethod: JsOperation {
    override var opcode: Opcode { .beginMethod(self) }

    // TODO refactor this: move the Parameters and name into BeginMethod.
    var numParameters: Int {
        return numInnerOutputs - 1
    }

    init(numParameters: Int) {
        super.init(numInputs: 0,
                   numOutputs: 0,
                   numInnerOutputs: 1 + numParameters,      // Explicit this is first inner output
                   attributes: [.isBlockStart, .isBlockEnd], requiredContext: .classDefinition, contextOpened: [.javascript, .classDefinition, .subroutine])
    }
}

final class EndClass: JsOperation {
    override var opcode: Opcode { .endClass(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class CallSuperConstructor: JsOperation {
    override var opcode: Opcode { .callSuperConstructor(self) }

    var numArguments: Int {
        return numInputs
    }

    init(numArguments: Int) {
        super.init(numInputs: numArguments, firstVariadicInput: 0, attributes: [.isVariadic, .isCall], requiredContext: [.javascript, .classDefinition])
    }
}

final class CallSuperMethod: JsOperation {
    override var opcode: Opcode { .callSuperMethod(self) }

    let methodName: String

    var numArguments: Int {
        return numInputs
    }

    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        super.init(numInputs: numArguments, numOutputs: 1, firstVariadicInput: 0, attributes: [.isCall, .isMutable, .isVariadic], requiredContext: [.javascript, .classDefinition])
    }
}

final class LoadSuperProperty: JsOperation {
    override var opcode: Opcode { .loadSuperProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

final class StoreSuperProperty: JsOperation {
    override var opcode: Opcode { .storeSuperProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

final class StoreSuperPropertyWithBinop: JsOperation {
    override var opcode: Opcode { .storeSuperPropertyWithBinop(self) }

    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 1, attributes: [.isMutable], requiredContext: [.javascript, .classDefinition])
    }
}

///
/// Control Flow
///
class ControlFlowOperation: JsOperation {
    init(numInputs: Int = 0, numInnerOutputs: Int = 0, attributes: Operation.Attributes, contextOpened: Context = .javascript) {
        assert(attributes.contains(.isBlockStart) || attributes.contains(.isBlockEnd))
        super.init(numInputs: numInputs, numInnerOutputs: numInnerOutputs, attributes: attributes.union(.propagatesSurroundingContext), contextOpened: contextOpened)
    }
}

final class BeginIf: ControlFlowOperation {
    override var opcode: Opcode { .beginIf(self) }

    // If true, the condition for this if block will be negated.
    let inverted: Bool

    init(inverted: Bool) {
        self.inverted = inverted
        super.init(numInputs: 1, attributes: [.isBlockStart, .isMutable])
    }
}

final class BeginElse: ControlFlowOperation {
    override var opcode: Opcode { .beginElse(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isBlockStart])
    }
}

final class EndIf: ControlFlowOperation {
    override var opcode: Opcode { .endIf(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class BeginWhileLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginWhileLoop(self) }

    let comparator: Comparator

    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndWhileLoop: ControlFlowOperation {
    override var opcode: Opcode { .endWhileLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

// Even though the loop condition is evaluated during EndDoWhile,
// the inputs are kept in BeginDoWhile as they have to come from
// the outer scope. Otherwise, special handling of EndDoWhile would
// be necessary throughout the IL, this way, only the Lifter has to
// be a bit more clever.
final class BeginDoWhileLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginDoWhileLoop(self) }

    let comparator: Comparator

    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndDoWhileLoop: ControlFlowOperation {
    override var opcode: Opcode { .endDoWhileLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

final class BeginForLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginForLoop(self) }

    let comparator: Comparator
    let op: BinaryOperator

    init(comparator: Comparator, op: BinaryOperator) {
        self.comparator = comparator
        self.op = op
        super.init(numInputs: 3, numInnerOutputs: 1, attributes: [.isMutable, .isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndForLoop: ControlFlowOperation {
    override var opcode: Opcode { .endForLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

final class BeginForInLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginForInLoop(self) }

    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndForInLoop: ControlFlowOperation {
    override var opcode: Opcode { .endForInLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

final class BeginForOfLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginForOfLoop(self) }

    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class BeginForOfWithDestructLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginForOfWithDestructLoop(self) }

    let indices: [Int64]
    let hasRestElement: Bool

    init(indices: [Int64], hasRestElement: Bool) {
        assert(indices.count >= 1)
        self.indices = indices
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numInnerOutputs: indices.count, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndForOfLoop: ControlFlowOperation {
    override var opcode: Opcode { .endForOfLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

// A loop that simply runs N times. Useful for example to force JIT compilation without creating new variables that contain the loop counts etc.
final class BeginRepeatLoop: ControlFlowOperation {
    override var opcode: Opcode { .beginRepeatLoop(self) }

    let iterations: Int

    init(iterations: Int) {
        self.iterations = iterations
        super.init(numInnerOutputs: 1, attributes: [.isBlockStart, .isLoop], contextOpened: [.javascript, .loop])
    }
}

final class EndRepeatLoop: ControlFlowOperation {
    override var opcode: Opcode { .endRepeatLoop(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isLoop])
    }
}

final class LoopBreak: JsOperation {
    override var opcode: Opcode { .loopBreak(self) }

    init() {
        super.init(attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

final class LoopContinue: JsOperation {
    override var opcode: Opcode { .loopContinue(self) }

    init() {
        super.init(attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

final class BeginTry: ControlFlowOperation {
    override var opcode: Opcode { .beginTry(self) }

    init() {
        super.init(attributes: [.isBlockStart])
    }
}

final class BeginCatch: ControlFlowOperation {
    override var opcode: Opcode { .beginCatch(self) }

    init() {
        super.init(numInnerOutputs: 1, attributes: [.isBlockStart, .isBlockEnd])
    }
}

final class BeginFinally: ControlFlowOperation {
    override var opcode: Opcode { .beginFinally(self) }

    init() {
        super.init(attributes: [.isBlockStart, .isBlockEnd])
    }
}

final class EndTryCatchFinally: ControlFlowOperation {
    override var opcode: Opcode { .endTryCatchFinally(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class ThrowException: JsOperation {
    override var opcode: Opcode { .throwException(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isJump])
    }
}

/// Generates a block of instructions, which is lifted to a string literal, that is a suitable as an argument to eval()
final class BeginCodeString: JsOperation {
    override var opcode: Opcode { .beginCodeString(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isBlockStart], contextOpened: .javascript)
    }
}

final class EndCodeString: JsOperation {
    override var opcode: Opcode { .endCodeString(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

/// Generates a block of instructions, which is lifted to a block statement.
final class BeginBlockStatement: JsOperation {
    override var opcode: Opcode { .beginBlockStatement(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class EndBlockStatement: JsOperation {
    override var opcode: Opcode { .endBlockStatement(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
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
final class BeginSwitch: JsOperation {
    override var opcode: Opcode { .beginSwitch(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart], contextOpened: [.switchBlock])
    }
}

final class BeginSwitchCase: JsOperation {
    override var opcode: Opcode { .beginSwitchCase(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart, .resumesSurroundingContext], requiredContext: [.switchBlock], contextOpened: [.switchCase, .javascript])
    }
}

/// This is the default case, it has no inputs, this is always in a BeginSwitch/EndSwitch block group.
/// We currently do not minimize this away. It is expected for other minimizers to reduce the contents of this block,
/// such that, if necessary, the BeginSwitch/EndSwitch reducer can remove the whole switch case altogether.
final class BeginSwitchDefaultCase: JsOperation {
    override var opcode: Opcode { .beginSwitchDefaultCase(self) }

    init() {
        super.init(attributes: [.isBlockStart, .resumesSurroundingContext], requiredContext: [.switchBlock], contextOpened: [.switchCase, .javascript])
    }
}

/// This ends BeginSwitchCase and BeginDefaultSwitchCase blocks.
final class EndSwitchCase: JsOperation {
    override var opcode: Opcode { .endSwitchCase(self) }

    /// If true, causes this case to fall through (and so no "break;" is emitted by the Lifter)
    let fallsThrough: Bool

    init(fallsThrough: Bool) {
        self.fallsThrough = fallsThrough
        super.init(attributes: [.isBlockEnd])
    }
}

final class EndSwitch: JsOperation {
    override var opcode: Opcode { .endSwitch(self) }

    init() {
        super.init(attributes: [.isBlockEnd], requiredContext: [.switchBlock])
    }
}

final class SwitchBreak: JsOperation {
    override var opcode: Opcode { .switchBreak(self) }

    init() {
        super.init(attributes: [.isJump], requiredContext: [.javascript, .switchCase])
    }
}

/// Internal operations.
///
/// These can be used for internal fuzzer operations but will not appear in the corpus.
class JsInternalOperation: JsOperation {
    init(numInputs: Int) {
        super.init(numInputs: numInputs, attributes: [.isInternal])
    }
}

/// Writes the argument to the output stream.
final class Print: JsInternalOperation {
    override var opcode: Opcode { .print(self) }

    init() {
        super.init(numInputs: 1)
    }
}

/// Explore the input variable at runtime to determine which actions can be performed on it.
/// Used by the ExplorationMutator.
final class Explore: JsInternalOperation {
    override var opcode: Opcode { .explore(self) }

    let id: String

    init(id: String, numArguments: Int) {
        self.id = id
        super.init(numInputs: numArguments + 1)
    }
}

/// Turn the input value into a probe that records the actions performed on it.
/// Used by the ProbingMutator.
final class Probe: JsInternalOperation {
    override var opcode: Opcode { .probe(self) }

    let id: String

    init(id: String) {
        self.id = id
        super.init(numInputs: 1)
    }
}
