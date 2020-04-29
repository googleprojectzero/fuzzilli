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
    let numInputs: Int
    
    /// The number of newly created variables in the current scope.
    let numOutputs: Int
    
    /// The number of newly created variables in the inner scope if one is created.
    let numInnerOutputs: Int

    /// The unique id of this operation's type.
    var typeId: Int {
        // Slight hack here with the forced downcast, but should be fine or at
        // least crash during unit testing.
        return (self as! TypeIdentifiable).typeId
    }

    fileprivate init(numInputs: Int, numOutputs: Int, numInnerOutputs: Int = 0, attributes: Attributes = []) {
        self.attributes = attributes
        self.numInputs = numInputs
        self.numOutputs = numOutputs
        self.numInnerOutputs = numInnerOutputs
    }
    
    /// Possible attributes of an operation.
    /// See Instruction.swift for an explanation of each of them.
    struct Attributes: OptionSet {
        let rawValue: Int
        
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

/// A helper protocol for types that can be identified by a unique ID.
protocol TypeIdentifiable {
    static var typeId: Int { get }
}

extension TypeIdentifiable {
    var typeId: Int {
        return Self.typeId
    }
}

class Nop: Operation, TypeIdentifiable {
    static let typeId = 0
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isPrimitive])
    }
}

class LoadInteger: Operation, TypeIdentifiable {
    static let typeId = 1
    let value: Int
    
    init(value: Int) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadFloat: Operation, TypeIdentifiable {
    static let typeId = 2
    let value: Double
    
    init(value: Double) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadString: Operation, TypeIdentifiable {
    static let typeId = 3
    let value: String
    
    init(value: String) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadBoolean: Operation, TypeIdentifiable {
    static let typeId = 4
    let value: Bool
    
    init(value: Bool) {
        self.value = value
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isParametric, .isLiteral])
    }
}

class LoadUndefined: Operation, TypeIdentifiable {
    static let typeId = 5
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isLiteral])
    }
}

class LoadNull: Operation, TypeIdentifiable {
    static let typeId = 6
    init() {
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isPrimitive, .isLiteral])
    }
}

class CreateObject: Operation, TypeIdentifiable {
    static let typeId = 7
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

class CreateArray: Operation, TypeIdentifiable {
    static let typeId = 8
    var numInitialValues: Int {
        return numInputs
    }
    
    init(numInitialValues: Int) {
        super.init(numInputs: numInitialValues, numOutputs: 1, attributes: [.isVarargs, .isLiteral])
    }
}

class CreateObjectWithSpread: Operation, TypeIdentifiable {
    static let typeId = 9
    // The property names of the "regular" properties. The remaining input values will be spread.
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

class CreateArrayWithSpread: Operation, TypeIdentifiable {
    static let typeId = 10
    // Which inputs to spread.
    let spreads: [Bool]
    
    init(numInitialValues: Int, spreads: [Bool]) {
        assert(spreads.count == numInitialValues)
        self.spreads = spreads
        super.init(numInputs: numInitialValues, numOutputs: 1, attributes: [.isVarargs, .isLiteral, .isParametric])
    }
}

class LoadBuiltin: Operation, TypeIdentifiable {
    static let typeId = 11
    let builtinName: String
    
    init(builtinName: String) {
        self.builtinName = builtinName
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isParametric])
    }
}

class LoadProperty: Operation, TypeIdentifiable {
    static let typeId = 12
    let propertyName: String
    
    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreProperty: Operation, TypeIdentifiable {
    static let typeId = 13
    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isParametric])
    }
}

class DeleteProperty: Operation, TypeIdentifiable {
    static let typeId = 14
    let propertyName: String
    
    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isParametric])
    }
}

class LoadElement: Operation, TypeIdentifiable {
    static let typeId = 15
    let index: Int
    
    init(index: Int) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreElement: Operation, TypeIdentifiable {
    static let typeId = 16
    let index: Int
    
    init(index: Int) {
        self.index = index
        super.init(numInputs: 2, numOutputs: 0, attributes: [.isParametric])
    }
}

class DeleteElement: Operation, TypeIdentifiable {
    static let typeId = 17
    let index: Int
    
    init(index: Int) {
        self.index = index
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isParametric])
    }
}

class LoadComputedProperty: Operation, TypeIdentifiable {
    static let typeId = 18
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class StoreComputedProperty: Operation, TypeIdentifiable {
    static let typeId = 19
    init() {
        super.init(numInputs: 3, numOutputs: 0)
    }
}

class DeleteComputedProperty: Operation, TypeIdentifiable {
    static let typeId = 20
    init() {
        super.init(numInputs: 2, numOutputs: 0)
    }
}

class TypeOf: Operation, TypeIdentifiable {
    static let typeId = 21
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

class InstanceOf: Operation, TypeIdentifiable {
    static let typeId = 22
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class In: Operation, TypeIdentifiable {
    static let typeId = 23
    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

class BeginFunctionDefinition: Operation, TypeIdentifiable {
    static let typeId = 24
    let signature: FunctionSignature
    let isJSStrictMode: Bool
    
    /// Whether the last parameter is a rest parameter.
    var hasRestParam: Bool {
        return signature.inputTypes.last?.isList ?? false
    }
    
    init(signature: FunctionSignature, isJSStrictMode: Bool) {
        self.signature = signature
        self.isJSStrictMode = isJSStrictMode
        super.init(numInputs: 0, numOutputs: 1, numInnerOutputs: signature.inputTypes.count, attributes: [.isBlockBegin])
    }
}

class Return: Operation, TypeIdentifiable {
    static let typeId = 25
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump])
    }
}

class EndFunctionDefinition: Operation, TypeIdentifiable {
    static let typeId = 26
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class CallMethod: Operation, TypeIdentifiable {
    static let typeId = 27
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

class CallFunction: Operation, TypeIdentifiable {
    static let typeId = 28
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(numArguments: Int) {
        // function object is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isCall, .isVarargs])
    }
}

class Construct: Operation, TypeIdentifiable {
    static let typeId = 29
    var numArguments: Int {
        return numInputs - 1
    }
    
    init(numArguments: Int) {
        // constructor is the first input
        super.init(numInputs: numArguments + 1, numOutputs: 1, attributes: [.isCall, .isVarargs])
    }
}

class CallFunctionWithSpread: Operation, TypeIdentifiable {
    static let typeId = 30
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
    
    var token: String {
        return self.rawValue
    }
}

let allUnaryOperators: [UnaryOperator] = [.Inc, .Dec, .LogicalNot, .BitwiseNot]

class UnaryOperation: Operation, TypeIdentifiable {
    static let typeId = 31
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
    
    var token: String {
        return self.rawValue
    }
}

let allBinaryOperators: [BinaryOperator] = [.Add, .Sub, .Mul, .Div, .Mod, .BitAnd, .BitOr, .LogicAnd, .LogicOr, .LShift, .RShift]

class BinaryOperation: Operation, TypeIdentifiable {
    static let typeId = 32
    let op: BinaryOperator
    
    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isParametric])
    }
}

/// This creates a variable that can be reassigned.
class Phi: Operation, TypeIdentifiable {
    static let typeId = 33
    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

/// Reassigns an existing Phi variable.
class Copy: Operation, TypeIdentifiable {
    static let typeId = 34
    init() {
        super.init(numInputs: 2, numOutputs: 0)
    }
}

public enum Comparator: String {
    case equal              = "=="
    case strictEqual        = "==="
    case notEqual           = "!="
    case lessThan           = "<"
    case lessThanOrEqual    = "<="
    case greaterThan        = ">"
    case greaterThanOrEqual = ">="
    
    var token: String {
        return self.rawValue
    }
}

let allComparators: [Comparator] = [.equal, .strictEqual, .notEqual, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual]

class Compare: Operation, TypeIdentifiable {
    static let typeId = 35
    let comparator: Comparator
    
    init(_ comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isParametric])
    }
}

/// An operation that will be lowered to a given string. The string can use %@ placeholders which
/// will be replaced by the input variables during lowering. Eval operations will also never be mutated.
class Eval: Operation, TypeIdentifiable {
    static let typeId = 36
    let string: String
    
    init(_ string: String, numArguments: Int) {
        self.string = string
        super.init(numInputs: numArguments, numOutputs: 0, numInnerOutputs: 0, attributes: [.isImmutable])
    }
}

class BeginWith: Operation, TypeIdentifiable {
    static let typeId = 37
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isBlockBegin])
    }
}

class EndWith: Operation, TypeIdentifiable {
    static let typeId = 38
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isBlockEnd])
    }
}

class LoadFromScope: Operation, TypeIdentifiable {
    static let typeId = 39
    let id: String
    
    init(id: String) {
        self.id = id
        super.init(numInputs: 0, numOutputs: 1, attributes: [.isParametric])
    }
}

class StoreToScope: Operation, TypeIdentifiable {
    static let typeId = 40
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

class BeginIf: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 41
    init() {
        super.init(numInputs: 1, attributes: [.isBlockBegin])
    }
}

class BeginElse: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 42
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isBlockBegin])
    }
}

class EndIf: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 43
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class BeginWhile: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 44
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isParametric, .isBlockBegin, .isLoopBegin])
    }
}

class EndWhile: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 45
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginDoWhile: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 46
    init() {
        super.init(numInputs: 0, attributes: [.isBlockBegin, .isLoopBegin])
    }
}

class EndDoWhile: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 47
    let comparator: Comparator
    init(comparator: Comparator) {
        self.comparator = comparator
        super.init(numInputs: 2, attributes: [.isParametric, .isBlockEnd, .isLoopEnd])
    }
}

class BeginFor: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 48
    let comparator: Comparator
    let op: BinaryOperator
    init(comparator: Comparator, op: BinaryOperator) {
        self.comparator = comparator
        self.op = op    
        super.init(numInputs: 3, numInnerOutputs: 1, attributes: [.isParametric, .isBlockBegin, .isLoopBegin])
    }
}

class EndFor: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 49
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginForIn: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 50
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockBegin, .isLoopBegin])
    }
}

class EndForIn: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 51
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class BeginForOf: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 52
    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockBegin, .isLoopBegin])
    }
}

class EndForOf: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 53
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd, .isLoopEnd])
    }
}

class Break: Operation, TypeIdentifiable {
    static let typeId = 54
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump])
    }
}

class Continue: Operation, TypeIdentifiable {
    static let typeId = 55
    init() {
        super.init(numInputs: 0, numOutputs: 0, attributes: [.isJump])
    }
}

class BeginTry: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 56
    init() {
        super.init(numInputs: 0, attributes: [.isBlockBegin])
    }
}

class BeginCatch: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 57
    init() {
        super.init(numInputs: 0, numInnerOutputs: 1, attributes: [.isBlockBegin, .isBlockEnd])
    }
}

class EndTryCatch: ControlFlowOperation, TypeIdentifiable {
    static let typeId = 58
    init() {
        super.init(numInputs: 0, attributes: [.isBlockEnd])
    }
}

class ThrowException: Operation, TypeIdentifiable {
    static let typeId = 59
    init() {
        super.init(numInputs: 1, numOutputs: 0, attributes: [.isJump])
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
class Print: InternalOperation, TypeIdentifiable {
    static let typeId = 60
    init() {
        super.init(numInputs: 1)
    }
}

/// Writes the type of the input value to the output stream.
class InspectType: InternalOperation, TypeIdentifiable {
    static let typeId = 61
    init() {
        super.init(numInputs: 1)
    }
}

/// Writes the properties and methods of the input value to the output stream.
class InspectValue: InternalOperation, TypeIdentifiable {
    static let typeId = 62
    init() {
        super.init(numInputs: 1)
    }
}

/// Writes the globally accessible objects to the output stream.
class EnumerateBuiltins: InternalOperation, TypeIdentifiable {
    static let typeId = 63
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

// TODO think of a better mechanism for this?
func Matches(_ op1: Operation, _ op2: Operation) -> Bool {
    switch op1 {
    case is BeginFunctionDefinition:
        return op2 is EndFunctionDefinition
    case is BeginWith:
        return op2 is EndWith
    case is BeginIf:
        return op2 is BeginElse || op2 is EndIf
    case is BeginElse:
        return op2 is EndIf
    case is BeginWhile:
        return op2 is EndWhile
    case is BeginDoWhile:
        return op2 is EndDoWhile
    case is BeginFor:
        return op2 is EndFor
    case is BeginForIn:
        return op2 is EndForIn
    case is BeginForOf:
        return op2 is EndForOf
    case is BeginTry:
        return op2 is BeginCatch
    case is BeginCatch:
        return op2 is EndTryCatch
    default:
        fatalError()
    }
}
