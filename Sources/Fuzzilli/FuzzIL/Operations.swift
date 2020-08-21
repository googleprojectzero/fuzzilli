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

/// An operation in the FuzzIL language.
///
/// Operations can be shared between different programs since they do not contain any
/// program specific data.
public class Operation {
    /// The attributes of this operation.
    let attributes: Attributes
    
    /// The number of input variables to this operation.
    private let numInputs_: UInt16
    var numInputs: Int {
        return Int(numInputs_)
    }
    
    /// The number of newly created variables in the current scope.
    private let numOutputs_: UInt16
    var numOutputs: Int {
        return Int(numOutputs_)
    }
    
    /// The number of newly created variables in the inner scope if one is created.
    private let numInnerOutputs_: UInt16
    var numInnerOutputs: Int {
        return Int(numInnerOutputs_)
    }

    fileprivate init(numInputs: Int, numOutputs: Int, numInnerOutputs: Int = 0, attributes: Attributes = []) {
        self.attributes = attributes
        self.numInputs_ = UInt16(numInputs)
        self.numOutputs_ = UInt16(numOutputs)
        self.numInnerOutputs_ = UInt16(numInnerOutputs)
    }
    
    /// Possible attributes of an operation.
    /// See Instruction.swift for an explanation of each of them.
    struct Attributes: OptionSet {
        let rawValue: UInt16
        
        static let isPrimitive        = Attributes(rawValue: 1 << 0)
        static let isLiteral          = Attributes(rawValue: 1 << 1)
        static let isParametric       = Attributes(rawValue: 1 << 2)
        static let isCall             = Attributes(rawValue: 1 << 3)
        static let isBlockBegin       = Attributes(rawValue: 1 << 4)
        static let isBlockEnd         = Attributes(rawValue: 1 << 5)
        static let isLoopBegin        = Attributes(rawValue: 1 << 6)
        static let isLoopEnd          = Attributes(rawValue: 1 << 7)
        static let isInternal         = Attributes(rawValue: 1 << 8)
        static let isJump             = Attributes(rawValue: 1 << 9)
        static let isImmutable        = Attributes(rawValue: 1 << 10)
        static let isVarargs          = Attributes(rawValue: 1 << 11)
    }
}

class Nop: Operation {    
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isPrimitive])
    }
}

class LoadInteger: Operation {
    let value: Int64
    
    init(value: Int64) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadBigInt: Operation {
    // This could be a bigger integer type, but it's most likely not worth the effort
    let value: Int64
    
    init(value: Int64) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadFloat: Operation {
    let value: Double
    
    init(value: Double) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadString: Operation {
    let value: String
    
    init(value: String) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadBoolean: Operation {
    let value: Bool
    
    init(value: Bool) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadUndefined: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isLiteral])
    }
}

class LoadNull: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isLiteral])
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

class LoadRegExp: Operation {
    let flags: RegExpFlags
    let value: String

    init(value: String, flags: RegExpFlags) {
        self.value = value
        self.flags = flags
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isLiteral])
    }
}

class CreateObject: Operation {
    // This array should be sorted to simplify comparison of two operations.
    let propertyNames: [String]
    
    init(propertyNames: [String]) {
        self.propertyNames = propertyNames
        var flags: Operation.Attributes = [.isVarargs, .isLiteral]
        if propertyNames.count > 0 {
            flags.insert(.isParametric)
        }
        super.init(numInputs: propertyNames.count, numOutputs: 1, attributes: flags)
    }
}

class CreateArray: Operation {
    var numInitialValues: Int {
        return numInputs
    }
    
    init(numInitialValues: Int) {
        super.init(numInputs: numInitialValues, numOutputs: 1, attributes: [.isVarargs, .isLiteral])
    }
}

class CreateObjectWithSpread: Operation {
    // The property names of the "regular" properties. The remaining input values will be spread.
    // This array should be sorted to simplify comparison of two operations.
    let propertyNames: [String]
    
    var numSpreads: Int {
        return numInputs - propertyNames.count
    }
    
    init(propertyNames: [String], numSpreads: Int) {
        self.propertyNames = propertyNames
        var flags: Operation.Attributes = [.isVarargs, .isLiteral]
        if propertyNames.count > 0 {
            flags.insert(.isParametric)
        }
        super.init(numInputs: propertyNames.count + numSpreads, numOutputs: 1, attributes: flags)
    }
}

class CreateArrayWithSpread: Operation {
    // Which inputs to spread.
    let spreads: [Bool]
    
    init(numInitialValues: Int, spreads: [Bool]) {
        assert(spreads.count == numInitialValues)
        self.spreads = spreads
        super.init(numInputs: numInitialValues, numOutputs: 1, attributes: [.isVarargs, .isLiteral, .isParametric])
    }
}

class LoadBuiltin: Operation {
    let builtinName: String
    
    init(builtinName: String) {
        self.builtinName = builtinName
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isParametric])
    }
}

class LoadProperty: Operation {
    let propertyName: String
    
    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreProperty: Operation {
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isParametric])
    }
}

class DeleteProperty: Operation {
    let propertyName: String
    
    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isParametric])
    }
}

class LoadElement: Operation {
    let index: Int64
    
    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreElement: Operation {
    let index: Int64
    
    init(index: Int64) {
        self.index = index
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isParametric])
    }
}

class DeleteElement: Operation {
    let index: Int64
    
    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isParametric])
    }
}

class LoadComputedProperty: Operation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class StoreComputedProperty: Operation {
    init() {
        super.init(numInputs: 3, numOutputs: 0)
    }
}

class DeleteComputedProperty: Operation {
    init() {
        super.init(numInputs: 2, numOutputs: 0)
    }
}

class TypeOf: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

class InstanceOf: Operation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class In: Operation {
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class BeginAnyFunctionDefinition: Operation {
    let signature: FunctionSignature
    
    /// Whether the last parameter is a rest parameter.
    var hasRestParam: Bool {
        return signature.hasVarargsParameter()
    }
    
    init(signature: FunctionSignature) {
        self.signature = signature
        super.init(numInputs: 0, numOutputs: 1, numInnerOutputs: signature.inputTypes.count, attributes: [.isBlockBegin])
    }
}

class EndAnyFunctionDefinition: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

// A plain function
class BeginPlainFunctionDefinition: BeginAnyFunctionDefinition {}
class EndPlainFunctionDefinition: EndAnyFunctionDefinition {}

// A ES5 strict mode function
class BeginStrictFunctionDefinition: BeginAnyFunctionDefinition {}
class EndStrictFunctionDefinition: EndAnyFunctionDefinition {}

// A ES6 arrow function
class BeginArrowFunctionDefinition: BeginAnyFunctionDefinition {}
class EndArrowFunctionDefinition: EndAnyFunctionDefinition {}

// A ES6 generator function
class BeginGeneratorFunctionDefinition: BeginAnyFunctionDefinition {}
class EndGeneratorFunctionDefinition: EndAnyFunctionDefinition {}

// A ES6 async function
class BeginAsyncFunctionDefinition: BeginAnyFunctionDefinition {}
class EndAsyncFunctionDefinition: EndAnyFunctionDefinition {}

// A ES6 async arrow function
class BeginAsyncArrowFunctionDefinition: BeginAnyFunctionDefinition {}
class EndAsyncArrowFunctionDefinition: EndAnyFunctionDefinition {}

// A ES6 async generator function
class BeginAsyncGeneratorFunctionDefinition: BeginAnyFunctionDefinition {}
class EndAsyncGeneratorFunctionDefinition: EndAnyFunctionDefinition {}

class Return: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump])
    }
}

// A yield expression in JavaScript
class Yield: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [])
    }
}

// A yield* expression in JavaScript
class YieldEach: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [])
    }
}

class Await: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [])
    }
}

class CallMethod: Operation {
    let methodName: String
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        // reference object is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isParametric, .isVarargs, .isCall])
    }
}

class CallFunction: Operation {
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(numArguments: Int) {
        // function object is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isCall, .isVarargs])
    }
}

class Construct: Operation {
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(numArguments: Int) {
        // constructor is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isCall, .isVarargs])
    }
}

class CallFunctionWithSpread: Operation {
    // Which inputs to spread
    let spreads: [Bool]
    
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(numArguments: Int, spreads: [Bool]) {
        assert(spreads.count == numArguments)
        self.spreads = spreads
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isCall, .isVarargs, .isParametric])
    }
}

public enum UnaryOperator: String {
    // Note: these *do not* modify their input. They will essentially be translated to `vX = vY + 1`
    case Inc        = "++"
    case Dec        = "--"
    case LogicalNot = "!"
    case BitwiseNot = "~"
    case Plus       = "+"
    case Minus      = "-"

    var token: String {
        return self.rawValue
    }
}

// This array must be kept in sync with the UnaryOperator Enum in operations.proto
let allUnaryOperators: [UnaryOperator] = [.Inc, .Dec, .LogicalNot, .BitwiseNot, .Plus, .Minus]

class UnaryOperation: Operation {
    let op: UnaryOperator
    
    init(_ op: UnaryOperator) {
        self.op = op
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isParametric])
    }
}

public enum BinaryOperator: String {
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
let allBinaryOperators: [BinaryOperator] = [.Add, .Sub, .Mul, .Div, .Mod, .BitAnd, .BitOr, .LogicAnd, .LogicOr, .Xor, .LShift, .RShift, .Exp, .UnRShift]

class BinaryOperation: Operation {
    let op: BinaryOperator
    
    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isParametric])
    }
}

/// This creates a variable that can be reassigned.
class Phi: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

/// Reassigns an existing Phi variable.
class Copy: Operation {
    init() {
        super.init(numInputs: 2, numOutputs: 0)
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

class Compare: Operation {
    let op: Comparator
    
    init(_ comparator: Comparator) {
        self.op = comparator
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isParametric])
    }
}

/// An operation that will be lifted to a given string. The string can use %@ placeholders which
/// will be replaced by the input variables during lowering. Eval operations will also never be mutated.
class Eval: Operation {
    let code: String
    
    init(_ string: String, numArguments: Int) {
        self.code = string
        super.init(numInputs: numArguments, numOutputs: 0, numInnerOutputs: 0, attributes: [.isImmutable])
    }
}

class BeginWith: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isBlockBegin])
    }
}

class EndWith: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class LoadFromScope: Operation {
    let id: String
    
    init(id: String) {
        self.id = id
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreToScope: Operation {
    let id: String
    
    init(id: String) {
        self.id = id
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isParametric])
    }
}

///
/// Control Flow
///
class ControlFlowOperation: Operation {
    init(numInputs: Int, numInnerOutputs: Int = 0, attributes: Operation.Attributes) {
        assert(attributes.contains(.isBlockBegin) || attributes.contains(.isBlockEnd))
        super.init(numInputs: numInputs, numOutputs: 0, numInnerOutputs: numInnerOutputs, attributes: attributes)
    }
}

class BeginIf: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, attributes: [.isBlockBegin])
    }
}

class BeginElse: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isBlockBegin])
    }
}

class EndIf: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class BeginWhile: ControlFlowOperation {
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isParametric, .isBlockBegin, .isLoopBegin])
    }
}

class EndWhile: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

// Even though the loop condition is evaluated during EndDoWhile,
// the inputs are kept in BeginDoWhile as they have to come from
// the outer scope. Otherwise, special handling of EndDoWhile would
// be necessary throughout the IL, this way, only the Lifter has to
// be a bit more clever.
class BeginDoWhile: ControlFlowOperation {
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isParametric, .isBlockBegin, .isLoopBegin])
    }
}

class EndDoWhile: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginFor: ControlFlowOperation {
    let comparator: Comparator
    let op: BinaryOperator
    init(comparator: Comparator, op: BinaryOperator) {
        self.comparator = comparator
        self.op = op
        super.init(numInputs: 3, numInnerOutputs: 1, attributes: [.isParametric, .isBlockBegin, .isLoopBegin])
    }
}

class EndFor: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginForIn: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockBegin, .isLoopBegin])
    }
}

class EndForIn: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginForOf: ControlFlowOperation {
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockBegin, .isLoopBegin])
    }
}

class EndForOf: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class Break: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump])
    }
}

class Continue: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump])
    }
}

class BeginTry: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockBegin])
    }
}

class BeginCatch: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, numInnerOutputs: 1, attributes: [.isBlockBegin, .isBlockEnd])
    }
}

class EndTryCatch: ControlFlowOperation {
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class ThrowException: Operation {
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump])
    }
}

// Useful to attach miscellaneous information to a program
class Comment: Operation {
    let content: String
    
    init(_ content: String) {
        self.content = content
        super.init(numInputs: 0, numOutputs: 0, numInnerOutputs: 0, attributes: [.isImmutable])
    }
}

/// Generates a block of instructions, which is lifted to a string literal, that is a suitable as an argument to eval()
class BeginCodeString: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isBlockBegin])
    }
}

class EndCodeString: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

/// Generates a block of instructions, which is lifted to a block statement.
class BeginBlockStatement: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockBegin])
    }
}

class EndBlockStatement: Operation {
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

/// Internal operations.
///
/// These are never emitted through a code generator and are never mutated.
/// In fact, these will never appear in a program that has been added to the corpus.
/// Instead they are used in programs emitted by the fuzzer backend for various
/// internal purposes, e.g. to retrieve type information for a variable.
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

/// Writes the type of the input value to the output stream.
class InspectType: InternalOperation {
    init() {
        super.init(numInputs: 1)
    }
}

/// Writes the properties and methods of the input value to the output stream.
class InspectValue: InternalOperation {
    init() {
        super.init(numInputs: 1)
    }
}

/// Writes the globally accessible objects to the output stream.
class EnumerateBuiltins: InternalOperation {
    init() {
        super.init(numInputs: 0)
    }
}

// Expose the name of an operation as instance and class variable
extension Operation {
    var name: String {
        return String(describing: type(of: self))
    }
    
    class var name: String {
        return String(describing: self)
    }
}
