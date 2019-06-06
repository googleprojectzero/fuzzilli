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

import Foundation

/// The building blocks of a FuzzIL program.
///
/// An instruction is an operation together with in- and output variables.
public struct Instruction: Codable {
    /// A NOP instruction for convenience.
    public static let NOP = Instruction(operation: Nop())
    
    
    /// The operation performed by this instruction.
    public let operation: Operation

    /// The index of this instruction in the program.
    ///
    /// Must only be accessed if the instruction is part of a program.
    public let index: Int!
    
    /// The input and output variables of this instruction.
    ///
    /// Format:
    ///      First numInputs Variables: inputs
    ///      Next numOutputs Variables: outputs visible in the outer scope
    ///      Next numInnerOutputs Variables: outputs only visible in the inner scope created by this instruction
    public let inouts: [Variable]
    
    /// The number of input variables.
    public var numInputs: Int {
        return operation.numInputs
    }
    
    /// The number of output variables.
    public var numOutputs: Int {
        return operation.numOutputs
    }
    
    /// The number of output variables that are visible in the inner scope (if this is a block begin).
    public var numInnerOutputs: Int {
        return operation.numInnerOutputs
    }
    
    /// Whether this instruction has any outputs.
    public var hasOutput: Bool {
        return numOutputs + numInnerOutputs > 0
    }
    
    /// Convenience getter for simple operations that produce a single output variable.
    public var output: Variable {
        assert(operation.numOutputs == 1)
        return inouts[operation.numInputs]
    }
    
    /// Convenience getter for simple operations that produce a single inner output variable.
    public var innerOutput: Variable {
        assert(operation.numInnerOutputs == 1)
        return inouts.last!
    }
    
    /// The input variables of this instruction.
    public var inputs: ArraySlice<Variable> {
        return inouts.prefix(upTo: numInputs)
    }
    
    /// The output variables of this instruction.
    public var outputs: ArraySlice<Variable> {
        return inouts[operation.numInputs..<operation.numInputs + operation.numOutputs]
    }
    
    /// The output variables of this instruction that are only visible in the inner scope.
    public var innerOutputs: ArraySlice<Variable> {
        return inouts.suffix(from: numInputs + numOutputs)
    }
    
    /// The inner and outer output variables of this instruction combined.
    public var allOutputs: ArraySlice<Variable> {
        return inouts.suffix(from: numInputs)
    }
    
    /// Returns the ith input variable.
    public func input(_ i: Int) -> Variable {
        assert(i < numInputs)
        return inouts[i]
    }
    
    ///
    /// Flag accessors.
    ///
    
    /// A primitive instructions is one that yields a primitive value and has no other side effects.
    public var isPrimitive: Bool {
        return operation.attributes.contains(.isPrimitive)
    }
    
    /// A literal in the target language.
    public var isLiteral: Bool {
        return operation.attributes.contains(.isLiteral)
    }
    
    /// Is this instruction parametric, i.e. contains any mutable values?
    public var isParametric: Bool {
        return operation.attributes.contains(.isParametric)
    }
    
    /// A simple instruction is not a block instruction.
    public var isSimple: Bool {
        return !isBlock
    }
    
    /// An instruction that performs a procedure call in some way.
    public var isCall: Bool {
        return operation.attributes.contains(.isCall)
    }
    
    /// An instruction whose operation can have a variable number of inputs.
    public var isVarargs: Bool {
        return operation.attributes.contains(.isVarargs)
    }
    
    /// A block instruction is part of a block in the program.
    public var isBlock: Bool {
        return isBlockBegin || isBlockEnd
    }
    
    /// Whether this instruction is the start of a block.
    public var isBlockBegin: Bool {
        return operation.attributes.contains(.isBlockBegin)
    }
    
    /// Whether this instruction is the end of a block.
    public var isBlockEnd: Bool {
        return operation.attributes.contains(.isBlockEnd)
    }
    
    /// Whether this instruction is the start of a block group (so a block begin but not a block end).
    public var isBlockGroupBegin: Bool {
        return isBlockBegin && !isBlockEnd
    }
    
    /// Whether this instruction is the end of a block group (so a block end but not a block begin).
    public var isBlockGroupEnd: Bool {
        return isBlockEnd && !isBlockBegin
    }
    
    /// Whether this instruction is the start of a loop.
    public var isLoopBegin: Bool {
        return operation.attributes.contains(.isLoopBegin)
    }
    
    /// Whether this instruction is the end of a loop.
    public var isLoopEnd: Bool {
        return operation.attributes.contains(.isLoopEnd)
    }
    
    /// Whether this instruction is a jump.
    /// An instruction is considered a jump if it unconditionally transfers control flow somewhere else and doesn't "come back" to the following instruction.
    public var isJump: Bool {
        return operation.attributes.contains(.isJump)
    }
    
    /// Whether this instruction should not be mutated.
    public var isImmutable: Bool {
        return operation.attributes.contains(.isImmutable)
    }
    
    /// Whether this instruction can be mutated.
    public var isMutable: Bool {
        return !isImmutable
    }
    
    /// Whether this instruction is an internal instruction that should not "leak" into
    /// the corpus or generally out of the component that generated it.
    public var isInternal: Bool {
        return operation.attributes.contains(.isInternal)
    }
    
    public init(operation: Operation, inouts: [Variable], index: Int? = nil) {
        assert(operation.numInputs + operation.numOutputs + operation.numInnerOutputs == inouts.count)
        self.operation = operation
        self.index = index
        self.inouts = inouts
    }
    
    public init(operation: Operation, output: Variable, index: Int? = nil) {
        assert(operation.numInputs == 0 && operation.numOutputs == 1 && operation.numInnerOutputs == 0)
        self.operation = operation
        self.inouts = [output]
        self.index = index
    }
    
    public init(operation: Operation, output: Variable, inputs: [Variable], index: Int? = nil) {
        assert(operation.numOutputs == 1)
        assert(operation.numInnerOutputs == 0)
        assert(operation.numInputs == inputs.count)
        self.operation = operation
        var inouts = inputs
        inouts.append(output)
        self.inouts = inouts
        self.index = index
    }
    
    public init(operation: Operation, inputs: [Variable], index: Int? = nil) {
        assert(operation.numOutputs + operation.numInnerOutputs == 0)
        assert(operation.numInputs == inputs.count)
        self.operation = operation
        self.inouts = inputs
        self.index = index
    }
    
    public init(operation: Operation, index: Int? = nil) {
        assert(operation.numOutputs == 0)
        assert(operation.numInputs == 0)
        self.operation = operation
        self.inouts = []
        self.index = index
    }
    
    //
    // Decoding and encoding
    //
    private enum CodingKeys: String, CodingKey {
        case operation
        case opData1
        case opData2
        case index
        case inouts
    }
    
    /// Encodes an instruction.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation.name, forKey: .operation)
        switch operation {
        case let op as LoadInteger:
            try container.encode(op.value, forKey: .opData1)
        case let op as LoadFloat:
            // Workaround: we don't want doubles in the JSON data so we store them as string
            // change this once we move to a different encoding
            try container.encode(String(op.value), forKey: .opData1)
        case let op as LoadString:
            try container.encode(op.value, forKey: .opData1)
        case let op as LoadBoolean:
            try container.encode(op.value, forKey: .opData1)
        case let op as CreateObject:
            try container.encode(op.propertyNames, forKey: .opData1)
        case let op as CreateObjectWithSpread:
            try container.encode(op.propertyNames, forKey: .opData1)
        case let op as CreateArrayWithSpread:
            try container.encode(op.spreads, forKey: .opData1)
        case let op as LoadBuiltin:
            try container.encode(op.builtinName, forKey: .opData1)
        case let op as LoadProperty:
            try container.encode(op.propertyName, forKey: .opData1)
        case let op as StoreProperty:
            try container.encode(op.propertyName, forKey: .opData1)
        case let op as DeleteProperty:
            try container.encode(op.propertyName, forKey: .opData1)
        case let op as LoadElement:
            try container.encode(op.index, forKey: .opData1)
        case let op as StoreElement:
            try container.encode(op.index, forKey: .opData1)
        case let op as DeleteElement:
            try container.encode(op.index, forKey: .opData1)
        case let op as BeginFunctionDefinition:
            try container.encode(op.isJSStrictMode, forKey: .opData1)
            try container.encode(op.hasRestParam, forKey: .opData2)
        case let op as CallMethod:
            try container.encode(op.methodName, forKey: .opData1)
        case let op as CallFunctionWithSpread:
            try container.encode(op.spreads, forKey: .opData1)
        case let op as UnaryOperation:
            try container.encode(op.op.rawValue, forKey: .opData1)
        case let op as BinaryOperation:
            try container.encode(op.op.rawValue, forKey: .opData1)
        case let op as Compare:
            try container.encode(op.comparator.rawValue, forKey: .opData1)
        case let op as Eval:
            try container.encode(op.string, forKey: .opData1)
        case let op as LoadFromScope:
            try container.encode(op.id, forKey: .opData1)
        case let op as StoreToScope:
            try container.encode(op.id, forKey: .opData1)
        case let op as BeginWhile:
            try container.encode(op.comparator.rawValue, forKey: .opData1)
        case let op as EndDoWhile:
            try container.encode(op.comparator.rawValue, forKey: .opData1)
        case let op as BeginFor:
            try container.encode(op.comparator.rawValue, forKey: .opData1)
            try container.encode(op.op.rawValue, forKey: .opData2)
        case is LoadUndefined,
             is LoadNull,
             is CreateArray,
             is LoadComputedProperty,
             is StoreComputedProperty,
             is DeleteComputedProperty,
             is EndFunctionDefinition,
             is TypeOf,
             is InstanceOf,
             is In,
             is Return,
             is CallFunction,
             is Construct,
             is Phi,
             is Copy,
             is BeginWith,
             is EndWith,
             is BeginIf,
             is BeginElse,
             is EndIf,
             is EndWhile,
             is BeginDoWhile,
             is EndFor,
             is BeginForIn,
             is EndForIn,
             is BeginForOf,
             is EndForOf,
             is Break,
             is Continue,
             is BeginTry,
             is BeginCatch,
             is EndTryCatch,
             is ThrowException:
                break
        default:
            fatalError("Unhandled operation type: \(operation)")
        }
        try container.encode(index, forKey: .index)
        try container.encode(inouts, forKey: .inouts)
    }
    
    private enum DecodingError: Error {
        case unknownOperationError(String)
    }
    
    /// Decodes an instruction from a decoder.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.index = try container.decode(Int.self, forKey: .index)
        self.inouts = try container.decode([Variable].self, forKey: .inouts)

        let opName = try container.decode(String.self, forKey: .operation)
        switch opName {
        case Nop.name:
            self.operation = Nop()
        case LoadInteger.name:
            self.operation = LoadInteger(value: try container.decode(Int.self, forKey: .opData1))
        case LoadFloat.name:
            let data = try container.decode(String.self, forKey: .opData1)
            if let value = Double(data) {
                self.operation = LoadFloat(value: value)
            } else {
                // Just assume it was either Double.greatestFiniteMagnitude or -Double.greatestFiniteMagnitude since these two values lead to this case during normal operations
                if data.hasPrefix("-") {
                    self.operation = LoadFloat(value: -Double.greatestFiniteMagnitude)
                } else {
                    self.operation = LoadFloat(value: Double.greatestFiniteMagnitude)
                }
            }
        case LoadString.name:
            self.operation = LoadString(value: try container.decode(String.self, forKey: .opData1))
        case LoadBoolean.name:
            self.operation = LoadBoolean(value: try container.decode(Bool.self, forKey: .opData1))
        case LoadUndefined.name:
            self.operation = LoadUndefined()
        case LoadNull.name:
            self.operation = LoadNull()
        case CreateObject.name:
            self.operation = CreateObject(propertyNames: try container.decode([String].self, forKey: .opData1))
        case CreateArray.name:
            self.operation = CreateArray(numInitialValues: inouts.count - 1)
        case CreateObjectWithSpread.name:
            let propertyNames = try container.decode([String].self, forKey: .opData1)
            self.operation = CreateObjectWithSpread(propertyNames: propertyNames, numSpreads: self.inouts.count - 1 - propertyNames.count)
        case CreateArrayWithSpread.name:
            let spreads = try container.decode([Bool].self, forKey: .opData1)
            self.operation = CreateArrayWithSpread(numInitialValues: inouts.count - 1, spreads: spreads)
        case LoadBuiltin.name:
            self.operation = LoadBuiltin(builtinName: try container.decode(String.self, forKey: .opData1))
        case LoadProperty.name:
            self.operation = LoadProperty(propertyName: try container.decode(String.self, forKey: .opData1))
        case StoreProperty.name:
            self.operation = StoreProperty(propertyName: try container.decode(String.self, forKey: .opData1))
        case DeleteProperty.name:
            self.operation = DeleteProperty(propertyName: try container.decode(String.self, forKey: .opData1))
        case LoadElement.name:
            self.operation = LoadElement(index: try container.decode(Int.self, forKey: .opData1))
        case StoreElement.name:
            self.operation = StoreElement(index: try container.decode(Int.self, forKey: .opData1))
        case DeleteElement.name:
            self.operation = DeleteElement(index: try container.decode(Int.self, forKey: .opData1))
        case LoadComputedProperty.name:
            self.operation = LoadComputedProperty()
        case StoreComputedProperty.name:
            self.operation = StoreComputedProperty()
        case DeleteComputedProperty.name:
            self.operation = DeleteComputedProperty()
        case TypeOf.name:
            self.operation = TypeOf()
        case InstanceOf.name:
            self.operation = InstanceOf()
        case In.name:
            self.operation = In()
        case BeginFunctionDefinition.name:
            self.operation = BeginFunctionDefinition(numParameters: inouts.count - 1, isJSStrictMode: try container.decode(Bool.self, forKey: .opData1), hasRestParam: try container.decode(Bool.self, forKey: .opData2))
        case Return.name:
            self.operation = Return()
        case EndFunctionDefinition.name:
            self.operation = EndFunctionDefinition()
        case CallMethod.name:
            self.operation = CallMethod(methodName: try container.decode(String.self, forKey: .opData1), numArguments: inouts.count - 2)
        case CallFunction.name:
            self.operation = CallFunction(numArguments: inouts.count - 2)
        case Construct.name:
            self.operation = Construct(numArguments: inouts.count - 2)
        case CallFunctionWithSpread.name:
            let spreads = try container.decode([Bool].self, forKey: .opData1)
            self.operation = CallFunctionWithSpread(numArguments: inouts.count - 2, spreads: spreads)
        case UnaryOperation.name:
            self.operation = UnaryOperation(UnaryOperator(rawValue: try container.decode(String.self, forKey: .opData1))!)
        case BinaryOperation.name:
            self.operation = BinaryOperation(BinaryOperator(rawValue: try container.decode(String.self, forKey: .opData1))!)
        case Phi.name:
            self.operation = Phi()
        case Copy.name:
            self.operation = Copy()
        case Compare.name:
            self.operation = Compare(Comparator(rawValue: try container.decode(String.self, forKey: .opData1))!)
        case Eval.name:
            self.operation = Eval(try container.decode(String.self, forKey: .opData1), numArguments: inouts.count)
        case BeginWith.name:
            self.operation = BeginWith()
        case EndWith.name:
            self.operation = EndWith()
        case LoadFromScope.name:
            self.operation = LoadFromScope(id: try container.decode(String.self, forKey: .opData1))
        case StoreToScope.name:
            self.operation = StoreToScope(id: try container.decode(String.self, forKey: .opData1))
        case BeginIf.name:
            self.operation = BeginIf()
        case BeginElse.name:
            self.operation = BeginElse()
        case EndIf.name:
            self.operation = EndIf()
        case BeginWhile.name:
            self.operation = BeginWhile(comparator: Comparator(rawValue: try container.decode(String.self, forKey: .opData1))!)
        case EndWhile.name:
            self.operation = EndWhile()
        case BeginDoWhile.name:
            self.operation = BeginDoWhile()
        case EndDoWhile.name:
            self.operation = EndDoWhile(comparator: Comparator(rawValue: try container.decode(String.self, forKey: .opData1))!)
        case BeginFor.name:
            self.operation = BeginFor(comparator: Comparator(rawValue: try container.decode(String.self, forKey: .opData1))!, op: BinaryOperator(rawValue: try container.decode(String.self, forKey: .opData2))!)
        case EndFor.name:
            self.operation = EndFor()
        case BeginForIn.name:
            self.operation = BeginForIn()
        case EndForIn.name:
            self.operation = EndForIn()
        case BeginForOf.name:
            self.operation = BeginForOf()
        case EndForOf.name:
            self.operation = EndForOf()
        case Break.name:
            self.operation = Break()
        case Continue.name:
            self.operation = Continue()
        case BeginTry.name:
            self.operation = BeginTry()
        case BeginCatch.name:
            self.operation = BeginCatch()
        case EndTryCatch.name:
            self.operation = EndTryCatch()
        case ThrowException.name:
            self.operation = ThrowException()
        default:
            throw DecodingError.unknownOperationError("Unexpected operation type: \(opName)")
        }
    }
}
