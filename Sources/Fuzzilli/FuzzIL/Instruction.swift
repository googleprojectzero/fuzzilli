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
public struct Instruction {
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
}

// Protobuf support.
//
// The protobuf conversion for operations is implemented here. The main reason for
// that is that operations cannot generally be decoded without knowledge of the
// instruction they occur in, as the number of in/outputs is only encoded once,
// in the instruction. For example, the CreateArray protobuf does not contain the
// number of initial array elements - that infomation is only captured once, in the
// inouts of the owning instruction.
extension Instruction: ProtobufConvertible {
    typealias ProtoType = Fuzzilli_Protobuf_Instruction

    func asProtobuf(with opCache: OperationCache?) -> ProtoType {
        func convertEnum<S: Equatable, P: RawRepresentable>(_ s: S, _ allValues: [S]) -> P where P.RawValue == Int {
            P(rawValue: allValues.firstIndex(of: s)!)!
        }
        
        let result = ProtoType.with {
            $0.inouts = inouts.map({ UInt32($0.number) })
            
            if isParametric {
                // See if we can use the cache instead.
                if let idx = opCache?.get(operation) {
                    $0.opIdx = UInt32(idx)
                    return
                }
            }
            
            switch operation {
            case is Nop:
                $0.nop = Fuzzilli_Protobuf_Nop()
            case let op as LoadInteger:
                $0.loadInteger = Fuzzilli_Protobuf_LoadInteger.with { $0.value = op.value }
            case let op as LoadBigInt:
                $0.loadBigInt = Fuzzilli_Protobuf_LoadBigInt.with { $0.value = op.value }
            case let op as LoadFloat:
                $0.loadFloat = Fuzzilli_Protobuf_LoadFloat.with { $0.value = op.value }
            case let op as LoadString:
                $0.loadString = Fuzzilli_Protobuf_LoadString.with { $0.value = op.value }
            case let op as LoadBoolean:
                $0.loadBoolean = Fuzzilli_Protobuf_LoadBoolean.with { $0.value = op.value }
            case is LoadUndefined:
                $0.loadUndefined = Fuzzilli_Protobuf_LoadUndefined()
            case is LoadNull:
                $0.loadNull = Fuzzilli_Protobuf_LoadNull()
            case let op as LoadRegExp:
                $0.loadRegExp = Fuzzilli_Protobuf_LoadRegExp.with { $0.value = op.value; $0.flags = op.flags.rawValue }
            case let op as CreateObject:
                $0.createObject = Fuzzilli_Protobuf_CreateObject.with { $0.propertyNames = op.propertyNames }
            case let op as CreateObjectWithSpread:
                $0.createObjectWithSpread = Fuzzilli_Protobuf_CreateObjectWithSpread.with { $0.propertyNames = op.propertyNames }
            case is CreateArray:
                $0.createArray = Fuzzilli_Protobuf_CreateArray()
            case let op as CreateArrayWithSpread:
                $0.createArrayWithSpread = Fuzzilli_Protobuf_CreateArrayWithSpread.with { $0.spreads = op.spreads }
            case let op as LoadBuiltin:
                $0.loadBuiltin = Fuzzilli_Protobuf_LoadBuiltin.with { $0.builtinName = op.builtinName }
            case let op as LoadProperty:
                $0.loadProperty = Fuzzilli_Protobuf_LoadProperty.with { $0.propertyName = op.propertyName }
            case let op as StoreProperty:
                $0.storeProperty = Fuzzilli_Protobuf_StoreProperty.with { $0.propertyName = op.propertyName }
            case let op as DeleteProperty:
                $0.deleteProperty = Fuzzilli_Protobuf_DeleteProperty.with { $0.propertyName = op.propertyName }
            case let op as LoadElement:
                $0.loadElement = Fuzzilli_Protobuf_LoadElement.with { $0.index = op.index }
            case let op as StoreElement:
                $0.storeElement = Fuzzilli_Protobuf_StoreElement.with { $0.index = op.index }
            case let op as DeleteElement:
                $0.deleteElement = Fuzzilli_Protobuf_DeleteElement.with { $0.index = op.index }
            case is LoadComputedProperty:
                $0.loadComputedProperty = Fuzzilli_Protobuf_LoadComputedProperty()
            case is StoreComputedProperty:
                $0.storeComputedProperty = Fuzzilli_Protobuf_StoreComputedProperty()
            case is DeleteComputedProperty:
                $0.deleteComputedProperty = Fuzzilli_Protobuf_DeleteComputedProperty()
            case is TypeOf:
                $0.typeOf = Fuzzilli_Protobuf_TypeOf()
            case is InstanceOf:
                $0.instanceOf = Fuzzilli_Protobuf_InstanceOf()
            case is In:
                $0.in = Fuzzilli_Protobuf_In()
            case let op as BeginPlainFunctionDefinition:
                $0.beginPlainFunctionDefinition = Fuzzilli_Protobuf_BeginPlainFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndPlainFunctionDefinition:
                $0.endPlainFunctionDefinition = Fuzzilli_Protobuf_EndPlainFunctionDefinition()
            case let op as BeginStrictFunctionDefinition:
                $0.beginStrictFunctionDefinition = Fuzzilli_Protobuf_BeginStrictFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndStrictFunctionDefinition:
                $0.endStrictFunctionDefinition = Fuzzilli_Protobuf_EndStrictFunctionDefinition()
            case let op as BeginArrowFunctionDefinition:
                $0.beginArrowFunctionDefinition = Fuzzilli_Protobuf_BeginArrowFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndArrowFunctionDefinition:
                $0.endArrowFunctionDefinition = Fuzzilli_Protobuf_EndArrowFunctionDefinition()
            case let op as BeginGeneratorFunctionDefinition:
                $0.beginGeneratorFunctionDefinition = Fuzzilli_Protobuf_BeginGeneratorFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndGeneratorFunctionDefinition:
                $0.endGeneratorFunctionDefinition = Fuzzilli_Protobuf_EndGeneratorFunctionDefinition()
            case let op as BeginAsyncFunctionDefinition:
                $0.beginAsyncFunctionDefinition = Fuzzilli_Protobuf_BeginAsyncFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndAsyncFunctionDefinition:
                $0.endAsyncFunctionDefinition = Fuzzilli_Protobuf_EndAsyncFunctionDefinition()
            case let op as BeginAsyncArrowFunctionDefinition:
                $0.beginAsyncArrowFunctionDefinition = Fuzzilli_Protobuf_BeginAsyncArrowFunctionDefinition.with { $0.signature = op.signature.asProtobuf() }
            case is EndAsyncArrowFunctionDefinition:
                $0.endAsyncArrowFunctionDefinition = Fuzzilli_Protobuf_EndAsyncArrowFunctionDefinition()
            case is Return:
                $0.return = Fuzzilli_Protobuf_Return()
            case is Yield:
                $0.yield = Fuzzilli_Protobuf_Yield()
            case is YieldEach:
                $0.yieldEach = Fuzzilli_Protobuf_YieldEach()
            case is Await:
                $0.await = Fuzzilli_Protobuf_Await()
            case let op as CallMethod:
                $0.callMethod = Fuzzilli_Protobuf_CallMethod.with { $0.methodName = op.methodName }
            case is CallFunction:
                $0.callFunction = Fuzzilli_Protobuf_CallFunction()
            case is Construct:
                $0.construct = Fuzzilli_Protobuf_Construct()
            case let op as CallFunctionWithSpread:
                $0.callFunctionWithSpread = Fuzzilli_Protobuf_CallFunctionWithSpread.with { $0.spreads = op.spreads }
            case let op as UnaryOperation:
                $0.unaryOperation = Fuzzilli_Protobuf_UnaryOperation.with { $0.op = convertEnum(op.op, allUnaryOperators) }
            case let op as BinaryOperation:
                $0.binaryOperation = Fuzzilli_Protobuf_BinaryOperation.with { $0.op = convertEnum(op.op, allBinaryOperators) }
            case is Phi:
                $0.phi = Fuzzilli_Protobuf_Phi()
            case is Copy:
                $0.copy = Fuzzilli_Protobuf_Copy()
            case let op as Compare:
                $0.compare = Fuzzilli_Protobuf_Compare.with { $0.op = convertEnum(op.op, allComparators) }
            case let op as Eval:
                $0.eval = Fuzzilli_Protobuf_Eval.with { $0.code = op.code }
            case is BeginWith:
                $0.beginWith = Fuzzilli_Protobuf_BeginWith()
            case is EndWith:
                $0.endWith = Fuzzilli_Protobuf_EndWith()
            case let op as LoadFromScope:
                $0.loadFromScope = Fuzzilli_Protobuf_LoadFromScope.with { $0.id = op.id }
            case let op as StoreToScope:
                $0.storeToScope = Fuzzilli_Protobuf_StoreToScope.with { $0.id = op.id }
            case is BeginIf:
                $0.beginIf = Fuzzilli_Protobuf_BeginIf()
            case is BeginElse:
                $0.beginElse = Fuzzilli_Protobuf_BeginElse()
            case is EndIf:
                $0.endIf = Fuzzilli_Protobuf_EndIf()
            case let op as BeginWhile:
                $0.beginWhile = Fuzzilli_Protobuf_BeginWhile.with { $0.comparator = convertEnum(op.comparator, allComparators) }
            case is EndWhile:
                $0.endWhile = Fuzzilli_Protobuf_EndWhile()
            case let op as BeginDoWhile:
                $0.beginDoWhile = Fuzzilli_Protobuf_BeginDoWhile.with { $0.comparator = convertEnum(op.comparator, allComparators) }
            case is EndDoWhile:
                $0.endDoWhile = Fuzzilli_Protobuf_EndDoWhile()
            case let op as BeginFor:
                $0.beginFor = Fuzzilli_Protobuf_BeginFor.with {
                    $0.comparator = convertEnum(op.comparator, allComparators)
                    $0.op = convertEnum(op.op, allBinaryOperators)
                }
            case is EndFor:
                $0.endFor = Fuzzilli_Protobuf_EndFor()
            case is BeginForIn:
                $0.beginForIn = Fuzzilli_Protobuf_BeginForIn()
            case is EndForIn:
                $0.endForIn = Fuzzilli_Protobuf_EndForIn()
            case is BeginForOf:
                $0.beginForOf = Fuzzilli_Protobuf_BeginForOf()
            case is EndForOf:
                $0.endForOf = Fuzzilli_Protobuf_EndForOf()
            case is Break:
                $0.break = Fuzzilli_Protobuf_Break()
            case is Continue:
                $0.continue = Fuzzilli_Protobuf_Continue()
            case is BeginTry:
                $0.beginTry = Fuzzilli_Protobuf_BeginTry()
            case is BeginCatch:
                $0.beginCatch = Fuzzilli_Protobuf_BeginCatch()
            case is EndTryCatch:
                $0.endTryCatch = Fuzzilli_Protobuf_EndTryCatch()
            case is ThrowException:
                $0.throwException = Fuzzilli_Protobuf_ThrowException()
            case let op as Comment:
                $0.comment = Fuzzilli_Protobuf_Comment.with { $0.content = op.content }
            case is BeginCodeString:
                $0.beginCodeString = Fuzzilli_Protobuf_BeginCodeString()
            case is EndCodeString:
                $0.endCodeString = Fuzzilli_Protobuf_EndCodeString()
            default:
                fatalError("Unhandled operation type in protobuf conversion: \(operation)")
            }
        }
        
        opCache?.add(operation)
        return result
    }
    
    func asProtobuf() -> ProtoType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtoType, with opCache: OperationCache?) throws {
        guard proto.inouts.allSatisfy({ Variable.isValidVariableNumber(Int(clamping: $0)) }) else {
            throw FuzzilliError.instructionDecodingError("Invalid variables in instruction")
        }
        let inouts = proto.inouts.map({ Variable(number: Int($0)) })
        
        // Helper function to convert between the Swift and Protobuf enums.
        func convertEnum<S: Equatable, P: RawRepresentable>(_ p: P, _ allValues: [S]) throws -> S where P.RawValue == Int {
            guard allValues.indices.contains(p.rawValue) else {
                throw FuzzilliError.instructionDecodingError("Invalid enum value \(p.rawValue) for type \(S.self)")
            }
            return allValues[p.rawValue]
        }
    
        guard let operation = proto.operation else {
            throw FuzzilliError.instructionDecodingError("Missing operation for instruction")
        }
        
        let op: Operation
        switch operation {
        case .opIdx(let i):
            guard let cachedOp = opCache?.get(Int(i)) else {
                throw FuzzilliError.instructionDecodingError("Invalid operation index or no decoding context available")
            }
            op = cachedOp
        case .loadInteger(let p):
            op = LoadInteger(value: p.value)
        case .loadBigInt(let p):
            op = LoadBigInt(value: p.value)
        case .loadFloat(let p):
            op = LoadFloat(value: p.value)
        case .loadString(let p):
            op = LoadString(value: p.value)
        case .loadBoolean(let p):
            op = LoadBoolean(value: p.value)
        case .loadUndefined(_):
            op = LoadUndefined()
        case .loadNull(_):
            op = LoadNull()
        case .loadRegExp(let p):
            op = LoadRegExp(value: p.value, flags: RegExpFlags(rawValue: p.flags))
        case .createObject(let p):
            op = CreateObject(propertyNames: p.propertyNames)
        case .createArray(_):
            op = CreateArray(numInitialValues: inouts.count - 1)
        case .createObjectWithSpread(let p):
            op = CreateObjectWithSpread(propertyNames: p.propertyNames, numSpreads: inouts.count - 1 - p.propertyNames.count)
        case .createArrayWithSpread(let p):
            op = CreateArrayWithSpread(numInitialValues: inouts.count - 1, spreads: p.spreads)
        case .loadBuiltin(let p):
            op = LoadBuiltin(builtinName: p.builtinName)
        case .loadProperty(let p):
            op = LoadProperty(propertyName: p.propertyName)
        case .storeProperty(let p):
            op = StoreProperty(propertyName: p.propertyName)
        case .deleteProperty(let p):
            op = DeleteProperty(propertyName: p.propertyName)
        case .loadElement(let p):
            op = LoadElement(index: p.index)
        case .storeElement(let p):
            op = StoreElement(index: p.index)
        case .deleteElement(let p):
            op = DeleteElement(index: p.index)
        case .loadComputedProperty(_):
            op = LoadComputedProperty()
        case .storeComputedProperty(_):
            op = StoreComputedProperty()
        case .deleteComputedProperty(_):
            op = DeleteComputedProperty()
        case .typeOf(_):
            op = TypeOf()
        case .instanceOf(_):
            op = InstanceOf()
        case .in(_):
            op = In()
        case .beginPlainFunctionDefinition(let p):
            op = BeginPlainFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endPlainFunctionDefinition(_):
            op = EndPlainFunctionDefinition()
        case .beginStrictFunctionDefinition(let p):
            op = BeginStrictFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endStrictFunctionDefinition(_):
            op = EndStrictFunctionDefinition()
        case .beginArrowFunctionDefinition(let p):
            op = BeginArrowFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endArrowFunctionDefinition(_):
            op = EndArrowFunctionDefinition()
        case .beginGeneratorFunctionDefinition(let p):
            op = BeginGeneratorFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endGeneratorFunctionDefinition(_):
            op = EndGeneratorFunctionDefinition()
        case .beginAsyncFunctionDefinition(let p):
            op = BeginAsyncFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endAsyncFunctionDefinition(_):
            op = EndAsyncFunctionDefinition()
        case .beginAsyncArrowFunctionDefinition(let p):
            op = BeginAsyncArrowFunctionDefinition(signature: try FunctionSignature(from: p.signature))
        case .endAsyncArrowFunctionDefinition(_):
            op = EndAsyncArrowFunctionDefinition()
        case .return(_):
            op = Return()
        case .yield(_):
            op = Yield()
        case .yieldEach(_):
            op = YieldEach()
        case .await(_):
            op = Await()
        case .callMethod(let p):
            op = CallMethod(methodName: p.methodName, numArguments: inouts.count - 2)
        case .callFunction(_):
            op = CallFunction(numArguments: inouts.count - 2)
        case .construct(_):
            op = Construct(numArguments: inouts.count - 2)
        case .callFunctionWithSpread(let p):
            op = CallFunctionWithSpread(numArguments: inouts.count - 2, spreads: p.spreads)
        case .unaryOperation(let p):
            op = UnaryOperation(try convertEnum(p.op, allUnaryOperators))
        case .binaryOperation(let p):
            op = BinaryOperation(try convertEnum(p.op, allBinaryOperators))
        case .phi(_):
            op = Phi()
        case .copy(_):
            op = Copy()
        case .compare(let p):
            op = Compare(try convertEnum(p.op, allComparators))
        case .eval(let p):
            op = Eval(p.code, numArguments: inouts.count)
        case .beginWith(_):
            op = BeginWith()
        case .endWith(_):
            op = EndWith()
        case .loadFromScope(let p):
            op = LoadFromScope(id: p.id)
        case .storeToScope(let p):
            op = StoreToScope(id: p.id)
        case .beginIf(_):
            op = BeginIf()
        case .beginElse(_):
            op = BeginElse()
        case .endIf(_):
            op = EndIf()
        case .beginWhile(let p):
            op = BeginWhile(comparator: try convertEnum(p.comparator, allComparators))
        case .endWhile(_):
            op = EndWhile()
        case .beginDoWhile(let p):
            op = BeginDoWhile(comparator: try convertEnum(p.comparator, allComparators))
        case .endDoWhile(_):
            op = EndDoWhile()
        case .beginFor(let p):
            op = BeginFor(comparator: try convertEnum(p.comparator, allComparators), op: try convertEnum(p.op, allBinaryOperators))
        case .endFor(_):
            op = EndFor()
        case .beginForIn(_):
            op = BeginForIn()
        case .endForIn(_):
            op = EndForIn()
        case .beginForOf(_):
            op = BeginForOf()
        case .endForOf(_):
            op = EndForOf()
        case .break(_):
            op = Break()
        case .continue(_):
            op = Continue()
        case .beginTry(_):
            op = BeginTry()
        case .beginCatch(_):
            op = BeginCatch()
        case .endTryCatch(_):
            op = EndTryCatch()
        case .throwException(_):
            op = ThrowException()
        case .comment(let p):
            op = Comment(p.content)
        case .beginCodeString(_):
            op = BeginCodeString()
        case .endCodeString(_):
            op = EndCodeString()
        case .nop(_):
            op = Nop()
        }
        
        guard op.numInputs + op.numOutputs + op.numInnerOutputs == inouts.count else {
            throw FuzzilliError.instructionDecodingError("Incorrect number of in- and outputs")
        }
        
        opCache?.add(op)
        
        self.init(operation: op, inouts: inouts)
    }
    
    init(from proto: ProtoType) throws {
        try self.init(from: proto, with: nil)
    }
}
