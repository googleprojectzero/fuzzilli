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

/// The building blocks of FuzzIL code.
///
/// An instruction is an operation together with in- and output variables.
public struct Instruction {
    /// The operation performed by this instruction.
    public let op: Operation

    /// The input and output variables of this instruction.
    ///
    /// Format:
    ///      First numInputs Variables: inputs
    ///      Next numOutputs Variables: outputs visible in the outer scope
    ///      Next numInnerOutputs Variables: outputs only visible in the inner scope created by this instruction
    ///      Final value, if present, the index of this instruction in the code object it is part of.
    private let inouts_: [Variable]


    /// The number of input variables of this instruction.
    public var numInputs: Int {
        return op.numInputs
    }

    /// The number of output variables of this instruction.
    public var numOutputs: Int {
        return op.numOutputs
    }

    /// The number of output variables of this instruction that are visible in the inner scope (if this is a block begin).
    public var numInnerOutputs: Int {
        return op.numInnerOutputs
    }

    /// The total number of inputs and outputs of this instruction.
    public var numInouts: Int {
        return numInputs + numOutputs + numInnerOutputs
    }

    /// Whether this instruction has any inputs.
    public var hasInputs: Bool {
        return numInputs > 0
    }

    /// Returns the ith input variable.
    public func input(_ i: Int) -> Variable {
        Assert(i < numInputs)
        return inouts_[i]
    }

    /// The input variables of this instruction.
    public var inputs: ArraySlice<Variable> {
        return inouts_[..<numInputs]
    }

    /// All variadic inputs of this instruction.
    public var variadicInputs: ArraySlice<Variable> {
        return inouts_[firstVariadicInput..<numInputs]
    }

    /// The index of the first variadic input of this instruction.
    public var firstVariadicInput: Int {
        return op.firstVariadicInput
    }

    /// Whether this instruction has any outputs.
    public var hasOutputs: Bool {
        return numOutputs + numInnerOutputs > 0
    }

    /// Convenience getter for simple operations that produce a single output variable.
    public var output: Variable {
        Assert(numOutputs == 1)
        return inouts_[numInputs]
    }

    /// Convenience getter for simple operations that produce a single inner output variable.
    public var innerOutput: Variable {
        Assert(numInnerOutputs == 1)
        return inouts_[numInputs + numOutputs]
    }

    /// The output variables of this instruction.
    public var outputs: ArraySlice<Variable> {
        return inouts_[numInputs ..< numInputs + numOutputs]
    }

    /// The output variables of this instruction that are only visible in the inner scope.
    public var innerOutputs: ArraySlice<Variable> {
        return inouts_[numInputs + numOutputs ..< numInouts]
    }

    public func innerOutput(_ i: Int) -> Variable {
        return inouts_[numInputs + numOutputs + i]
    }

    public func innerOutputs(_ r: PartialRangeFrom<Int>) -> ArraySlice<Variable> {
        return inouts_[numInputs + numOutputs + r.lowerBound ..< numInouts]
    }

    /// The inner and outer output variables of this instruction combined.
    public var allOutputs: ArraySlice<Variable> {
        return inouts_[numInputs ..< numInouts]
    }

    /// All inputs and outputs of this instruction combined.
    public var inouts: ArraySlice<Variable> {
        return inouts_[..<numInouts]
    }

    /// The index of this instruction in the Code it belongs to.
    /// A value of -1 indicates that this instruction does not belong to any code.
    public var index: Int {
        // We store the index in the internal inouts array for memory efficiency reasons.
        // In practice, this does not limit the size of programs/code since that's already
        // limited by the fact that variables are UInt16 internally.
        let indexVar = numInouts == inouts_.count ? nil : inouts_.last
        return Int(indexVar?.number ?? -1)
    }


    ///
    /// Flag accessors.
    ///

    /// A pure operation returns the same value given the same inputs and has no side effects.
    public var isPure: Bool {
        return op.attributes.contains(.isPure)
    }

    /// True if the operation of this instruction be mutated in a meaningful way.
    /// An instruction with inputs is always mutable. This only indicates whether the operation can be mutated.
    /// See Operation.Attributes.isMutable
    public var isOperationMutable: Bool {
        return op.attributes.contains(.isMutable)
    }

    /// A simple instruction is not a block instruction.
    public var isSimple: Bool {
        return !isBlock
    }

    /// An instruction that performs a procedure call.
    /// See Operation.Attributes.isCall
    public var isCall: Bool {
        return op.attributes.contains(.isCall)
    }

    /// An operation is variadic if it can have a variable number of inputs.
    /// See Operation.Attributes.isVariadic
    public var isVariadic: Bool {
        return op.attributes.contains(.isVariadic)
    }

    /// A block instruction is part of a block in the program.
    public var isBlock: Bool {
        return isBlockStart || isBlockEnd
    }

    /// Whether this instruction is the start of a block.
    /// See Operation.Attributes.isBlockStart.
    public var isBlockStart: Bool {
        return op.attributes.contains(.isBlockStart)
    }

    /// Whether this instruction is the end of a block.
    /// See Operation.Attributes.isBlockEnd.
    public var isBlockEnd: Bool {
        return op.attributes.contains(.isBlockEnd)
    }

    /// Whether this instruction is the start of a block group (so a block start but not a block end).
    public var isBlockGroupStart: Bool {
        return isBlockStart && !isBlockEnd
    }

    /// Whether this instruction is the end of a block group (so a block end but not also a block start).
    public var isBlockGroupEnd: Bool {
        return isBlockEnd && !isBlockStart
    }

    /// Whether the block opened or closed by this instruction is a loop.
    /// See See Operation.Attributes.isLoop
    public var isLoop: Bool {
        return op.attributes.contains(.isLoop)
    }

    /// Whether this instruction is a jump.
    /// See See Operation.Attributes.isJump.
    public var isJump: Bool {
        return op.attributes.contains(.isJump)
    }

    /// Whether this instruction propagates contexts.
    /// See Operation.Attributes.propagatesSurroundingContext.
    public var propagatesSurroundingContext: Bool {
        Assert(isBlockStart)
        return op.attributes.contains(.propagatesSurroundingContext)
    }

    /// Whether this instruction is an internal instruction that should not "leak" into
    /// the corpus or generally out of the component that generated it.
    public var isInternal: Bool {
        return op.attributes.contains(.isInternal)
    }


    public init<Variables: Collection>(_ op: Operation, inouts: Variables, index: Int? = nil) where Variables.Element == Variable {
        self.op = op
        var inouts_ = Array(inouts)
        if let idx = index {
            inouts_.append(Variable(number: idx))
        }
        self.inouts_ = inouts_
    }

    public init(_ op: Operation, output: Variable, index: Int? = nil) {
        Assert(op.numInputs == 0 && op.numOutputs == 1 && op.numInnerOutputs == 0)
        self.init(op, inouts: [output], index: index)
    }

    public init(_ op: Operation, output: Variable, inputs: [Variable], index: Int? = nil) {
        Assert(op.numOutputs == 1)
        Assert(op.numInnerOutputs == 0)
        Assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs + [output], index: index)
    }

    public init(_ op: Operation, inputs: [Variable], index: Int? = nil) {
        Assert(op.numOutputs + op.numInnerOutputs == 0)
        Assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs, index: index)
    }

    public init(_ op: Operation, index: Int? = nil) {
        Assert(op.numOutputs == 0)
        Assert(op.numInputs == 0)
        self.init(op, inouts: [], index: index)
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
    typealias ProtobufType = Fuzzilli_Protobuf_Instruction

    func asProtobuf(with opCache: OperationCache?) -> ProtobufType {
        func convertEnum<S: Equatable, P: RawRepresentable>(_ s: S, _ allValues: [S]) -> P where P.RawValue == Int {
            return P(rawValue: allValues.firstIndex(of: s)!)!
        }

        let result = ProtobufType.with {
            $0.inouts = inouts.map({ UInt32($0.number) })

            if isOperationMutable {
                // It's probably a somewhat complex operation, so see if we can use the cache instead.
                if let idx = opCache?.get(op) {
                    $0.opIdx = UInt32(idx)
                    return
                }
            }

            switch op {
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
            case is LoadThis:
                $0.loadThis = Fuzzilli_Protobuf_LoadThis()
            case is LoadArguments:
                $0.loadArguments = Fuzzilli_Protobuf_LoadArguments()
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
            case let op as CreateTemplateString:
                $0.createTemplateString = Fuzzilli_Protobuf_CreateTemplateString.with { $0.parts = op.parts }
            case let op as LoadBuiltin:
                $0.loadBuiltin = Fuzzilli_Protobuf_LoadBuiltin.with { $0.builtinName = op.builtinName }
            case let op as LoadProperty:
                $0.loadProperty = Fuzzilli_Protobuf_LoadProperty.with { $0.propertyName = op.propertyName }
            case let op as StoreProperty:
                $0.storeProperty = Fuzzilli_Protobuf_StoreProperty.with { $0.propertyName = op.propertyName }
            case let op as StorePropertyWithBinop:
                $0.storePropertyWithBinop = Fuzzilli_Protobuf_StorePropertyWithBinop.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, allBinaryOperators)
                }
            case let op as DeleteProperty:
                $0.deleteProperty = Fuzzilli_Protobuf_DeleteProperty.with { $0.propertyName = op.propertyName }
            case let op as LoadElement:
                $0.loadElement = Fuzzilli_Protobuf_LoadElement.with { $0.index = op.index }
            case let op as StoreElement:
                $0.storeElement = Fuzzilli_Protobuf_StoreElement.with { $0.index = op.index }
            case let op as StoreElementWithBinop:
                $0.storeElementWithBinop = Fuzzilli_Protobuf_StoreElementWithBinop.with {
                    $0.index = op.index
                    $0.op = convertEnum(op.op, allBinaryOperators)
                }
            case let op as DeleteElement:
                $0.deleteElement = Fuzzilli_Protobuf_DeleteElement.with { $0.index = op.index }
            case is LoadComputedProperty:
                $0.loadComputedProperty = Fuzzilli_Protobuf_LoadComputedProperty()
            case is StoreComputedProperty:
                $0.storeComputedProperty = Fuzzilli_Protobuf_StoreComputedProperty()
            case let op as StoreComputedPropertyWithBinop:
                $0.storeComputedPropertyWithBinop = Fuzzilli_Protobuf_StoreComputedPropertyWithBinop.with{ $0.op = convertEnum(op.op, allBinaryOperators) }
            case is DeleteComputedProperty:
                $0.deleteComputedProperty = Fuzzilli_Protobuf_DeleteComputedProperty()
            case is TypeOf:
                $0.typeOf = Fuzzilli_Protobuf_TypeOf()
            case is TestInstanceOf:
                $0.testInstanceOf = Fuzzilli_Protobuf_TestInstanceOf()
            case is TestIn:
                $0.testIn = Fuzzilli_Protobuf_TestIn()
            case let op as BeginPlainFunction:
                $0.beginPlainFunction = Fuzzilli_Protobuf_BeginPlainFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndPlainFunction:
                $0.endPlainFunction = Fuzzilli_Protobuf_EndPlainFunction()
            case let op as BeginArrowFunction:
                $0.beginArrowFunction = Fuzzilli_Protobuf_BeginArrowFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndArrowFunction:
                $0.endArrowFunction = Fuzzilli_Protobuf_EndArrowFunction()
            case let op as BeginGeneratorFunction:
                $0.beginGeneratorFunction = Fuzzilli_Protobuf_BeginGeneratorFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndGeneratorFunction:
                $0.endGeneratorFunction = Fuzzilli_Protobuf_EndGeneratorFunction()
            case let op as BeginAsyncFunction:
                $0.beginAsyncFunction = Fuzzilli_Protobuf_BeginAsyncFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndAsyncFunction:
                $0.endAsyncFunction = Fuzzilli_Protobuf_EndAsyncFunction()
            case let op as BeginAsyncArrowFunction:
                $0.beginAsyncArrowFunction = Fuzzilli_Protobuf_BeginAsyncArrowFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndAsyncArrowFunction:
                $0.endAsyncArrowFunction = Fuzzilli_Protobuf_EndAsyncArrowFunction()
            case let op as BeginAsyncGeneratorFunction:
                $0.beginAsyncGeneratorFunction = Fuzzilli_Protobuf_BeginAsyncGeneratorFunction.with {
                    $0.signature = op.signature.asProtobuf()
                    $0.isStrict = op.isStrict
                }
            case is EndAsyncGeneratorFunction:
                $0.endAsyncGeneratorFunction = Fuzzilli_Protobuf_EndAsyncGeneratorFunction()
            case is Return:
                $0.return = Fuzzilli_Protobuf_Return()
            case is Yield:
                $0.yield = Fuzzilli_Protobuf_Yield()
            case is YieldEach:
                $0.yieldEach = Fuzzilli_Protobuf_YieldEach()
            case is Await:
                $0.await = Fuzzilli_Protobuf_Await()
            case is CallFunction:
                $0.callFunction = Fuzzilli_Protobuf_CallFunction()
            case let op as CallFunctionWithSpread:
                $0.callFunctionWithSpread = Fuzzilli_Protobuf_CallFunctionWithSpread.with { $0.spreads = op.spreads }
            case is Construct:
                $0.construct = Fuzzilli_Protobuf_Construct()
            case let op as ConstructWithSpread:
                $0.constructWithSpread = Fuzzilli_Protobuf_ConstructWithSpread.with { $0.spreads = op.spreads }
            case let op as CallMethod:
                $0.callMethod = Fuzzilli_Protobuf_CallMethod.with {
                    $0.methodName = op.methodName
                }
            case let op as CallMethodWithSpread:
                $0.callMethodWithSpread = Fuzzilli_Protobuf_CallMethodWithSpread.with {
                    $0.methodName = op.methodName
                    $0.spreads = op.spreads
                }
            case is CallComputedMethod:
                $0.callComputedMethod = Fuzzilli_Protobuf_CallComputedMethod()
            case let op as CallComputedMethodWithSpread:
                $0.callComputedMethodWithSpread = Fuzzilli_Protobuf_CallComputedMethodWithSpread.with { $0.spreads = op.spreads }
            case let op as UnaryOperation:
                $0.unaryOperation = Fuzzilli_Protobuf_UnaryOperation.with { $0.op = convertEnum(op.op, allUnaryOperators) }
            case let op as BinaryOperation:
                $0.binaryOperation = Fuzzilli_Protobuf_BinaryOperation.with { $0.op = convertEnum(op.op, allBinaryOperators) }
            case let op as ReassignWithBinop:
                $0.reassignWithBinop = Fuzzilli_Protobuf_ReassignWithBinop.with { $0.op = convertEnum(op.op, allBinaryOperators) }
            case is Dup:
                $0.dup = Fuzzilli_Protobuf_Dup()
            case is Reassign:
                $0.reassign = Fuzzilli_Protobuf_Reassign()
            case let op as DestructArray:
                $0.destructArray = Fuzzilli_Protobuf_DestructArray.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case let op as DestructArrayAndReassign:
                $0.destructArrayAndReassign = Fuzzilli_Protobuf_DestructArrayAndReassign.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case let op as DestructObject:
                $0.destructObject = Fuzzilli_Protobuf_DestructObject.with {
                    $0.properties = op.properties
                    $0.hasRestElement_p = op.hasRestElement
                }
            case let op as DestructObjectAndReassign:
                $0.destructObjectAndReassign = Fuzzilli_Protobuf_DestructObjectAndReassign.with {
                    $0.properties = op.properties
                    $0.hasRestElement_p = op.hasRestElement
                }
            case let op as Compare:
                $0.compare = Fuzzilli_Protobuf_Compare.with { $0.op = convertEnum(op.op, allComparators) }
            case is ConditionalOperation:
                $0.conditionalOperation = Fuzzilli_Protobuf_ConditionalOperation()
            case let op as Eval:
                $0.eval = Fuzzilli_Protobuf_Eval.with { $0.code = op.code }
            case let op as BeginClass:
                $0.beginClass = Fuzzilli_Protobuf_BeginClass.with {
                    $0.hasSuperclass_p = op.hasSuperclass
                    $0.constructorParameters = op.constructorParameters.map({ $0.asProtobuf() })
                    $0.instanceProperties = op.instanceProperties
                    $0.instanceMethodNames = op.instanceMethods.map({ $0.name })
                    $0.instanceMethodSignatures = op.instanceMethods.map({ $0.signature.asProtobuf() })
                }
            case let op as BeginMethod:
                $0.beginMethod = Fuzzilli_Protobuf_BeginMethod.with { $0.numParameters = UInt32(op.numParameters) }
            case is EndClass:
                $0.endClass = Fuzzilli_Protobuf_EndClass()
            case is CallSuperConstructor:
                $0.callSuperConstructor = Fuzzilli_Protobuf_CallSuperConstructor()
            case let op as CallSuperMethod:
                $0.callSuperMethod = Fuzzilli_Protobuf_CallSuperMethod.with { $0.methodName = op.methodName }
            case let op as LoadSuperProperty:
                $0.loadSuperProperty = Fuzzilli_Protobuf_LoadSuperProperty.with { $0.propertyName = op.propertyName }
            case let op as StoreSuperProperty:
                $0.storeSuperProperty = Fuzzilli_Protobuf_StoreSuperProperty.with { $0.propertyName = op.propertyName }
            case let op as StoreSuperPropertyWithBinop:
                $0.storeSuperPropertyWithBinop = Fuzzilli_Protobuf_StoreSuperPropertyWithBinop.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, allBinaryOperators)
                }
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
            case is BeginSwitch:
                $0.beginSwitch = Fuzzilli_Protobuf_BeginSwitch()
            case let op as BeginSwitchCase:
                $0.beginSwitchCase = Fuzzilli_Protobuf_BeginSwitchCase.with { $0.previousCaseFallsThrough = op.previousCaseFallsThrough }
            case is SwitchBreak:
                $0.switchBreak = Fuzzilli_Protobuf_SwitchBreak()
            case is EndSwitch:
                $0.endSwitch = Fuzzilli_Protobuf_EndSwitch()
            case let op as BeginWhileLoop:
                $0.beginWhile = Fuzzilli_Protobuf_BeginWhile.with { $0.comparator = convertEnum(op.comparator, allComparators) }
            case is EndWhileLoop:
                $0.endWhile = Fuzzilli_Protobuf_EndWhile()
            case let op as BeginDoWhileLoop:
                $0.beginDoWhile = Fuzzilli_Protobuf_BeginDoWhile.with { $0.comparator = convertEnum(op.comparator, allComparators) }
            case is EndDoWhileLoop:
                $0.endDoWhile = Fuzzilli_Protobuf_EndDoWhile()
            case let op as BeginForLoop:
                $0.beginFor = Fuzzilli_Protobuf_BeginFor.with {
                    $0.comparator = convertEnum(op.comparator, allComparators)
                    $0.op = convertEnum(op.op, allBinaryOperators)
                }
            case is EndForLoop:
                $0.endFor = Fuzzilli_Protobuf_EndFor()
            case is BeginForInLoop:
                $0.beginForIn = Fuzzilli_Protobuf_BeginForIn()
            case is EndForInLoop:
                $0.endForIn = Fuzzilli_Protobuf_EndForIn()
            case is BeginForOfLoop:
                $0.beginForOf = Fuzzilli_Protobuf_BeginForOf()
            case let op as BeginForOfWithDestructLoop:
                $0.beginForOfWithDestruct = Fuzzilli_Protobuf_BeginForOfWithDestruct.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case is EndForOfLoop:
                $0.endForOf = Fuzzilli_Protobuf_EndForOf()
            case is LoopBreak:
                $0.loopBreak = Fuzzilli_Protobuf_LoopBreak()
            case is LoopContinue:
                $0.loopContinue = Fuzzilli_Protobuf_LoopContinue()
            case is BeginTry:
                $0.beginTry = Fuzzilli_Protobuf_BeginTry()
            case is BeginCatch:
                $0.beginCatch = Fuzzilli_Protobuf_BeginCatch()
            case is BeginFinally:
                $0.beginFinally = Fuzzilli_Protobuf_BeginFinally()
            case is EndTryCatchFinally:
                $0.endTryCatch = Fuzzilli_Protobuf_EndTryCatch()
            case is ThrowException:
                $0.throwException = Fuzzilli_Protobuf_ThrowException()
            case is BeginCodeString:
                $0.beginCodeString = Fuzzilli_Protobuf_BeginCodeString()
            case is EndCodeString:
                $0.endCodeString = Fuzzilli_Protobuf_EndCodeString()
            case is BeginBlockStatement:
                $0.beginBlockStatement = Fuzzilli_Protobuf_BeginBlockStatement()
            case is EndBlockStatement:
                $0.endBlockStatement = Fuzzilli_Protobuf_EndBlockStatement()
            default:
                fatalError("Unhandled operation type in protobuf conversion: \(op)")
            }
        }

        opCache?.add(op)
        return result
    }

    func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtobufType, with opCache: OperationCache?) throws {
        guard proto.inouts.allSatisfy({ Variable.isValidVariableNumber(Int(clamping: $0)) }) else {
            throw FuzzilliError.instructionDecodingError("invalid variables in instruction")
        }
        let inouts = proto.inouts.map({ Variable(number: Int($0)) })

        // Helper function to convert between the Swift and Protobuf enums.
        func convertEnum<S: Equatable, P: RawRepresentable>(_ p: P, _ allValues: [S]) throws -> S where P.RawValue == Int {
            guard allValues.indices.contains(p.rawValue) else {
                throw FuzzilliError.instructionDecodingError("invalid enum value \(p.rawValue) for type \(S.self)")
            }
            return allValues[p.rawValue]
        }

        guard let operation = proto.operation else {
            throw FuzzilliError.instructionDecodingError("missing operation for instruction")
        }

        let op: Operation
        switch operation {
        case .opIdx(let idx):
            guard let cachedOp = opCache?.get(Int(idx)) else {
                throw FuzzilliError.instructionDecodingError("invalid operation index or no decoding context available")
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
        case .loadThis(_):
            op = LoadThis()
        case .loadArguments(_):
            op = LoadArguments()
        case .loadRegExp(let p):
            op = LoadRegExp(value: p.value, flags: RegExpFlags(rawValue: p.flags))
        case .createObject(let p):
            op = CreateObject(propertyNames: p.propertyNames)
        case .createArray(_):
            op = CreateArray(numInitialValues: inouts.count - 1)
        case .createObjectWithSpread(let p):
            op = CreateObjectWithSpread(propertyNames: p.propertyNames, numSpreads: inouts.count - 1 - p.propertyNames.count)
        case .createArrayWithSpread(let p):
            op = CreateArrayWithSpread(spreads: p.spreads)
        case .createTemplateString(let p):
            op = CreateTemplateString(parts: p.parts)
        case .loadBuiltin(let p):
            op = LoadBuiltin(builtinName: p.builtinName)
        case .loadProperty(let p):
            op = LoadProperty(propertyName: p.propertyName)
        case .storeProperty(let p):
            op = StoreProperty(propertyName: p.propertyName)
        case .storePropertyWithBinop(let p):
            op = StorePropertyWithBinop(propertyName: p.propertyName, operator: try convertEnum(p.op, allBinaryOperators))
        case .deleteProperty(let p):
            op = DeleteProperty(propertyName: p.propertyName)
        case .loadElement(let p):
            op = LoadElement(index: p.index)
        case .storeElement(let p):
            op = StoreElement(index: p.index)
        case .storeElementWithBinop(let p):
            op = StoreElementWithBinop(index: p.index, operator: try convertEnum(p.op, allBinaryOperators))
        case .deleteElement(let p):
            op = DeleteElement(index: p.index)
        case .loadComputedProperty(_):
            op = LoadComputedProperty()
        case .storeComputedProperty(_):
            op = StoreComputedProperty()
        case .storeComputedPropertyWithBinop(let p):
            op = StoreComputedPropertyWithBinop(operator: try convertEnum(p.op, allBinaryOperators))
        case .deleteComputedProperty(_):
            op = DeleteComputedProperty()
        case .typeOf(_):
            op = TypeOf()
        case .testInstanceOf(_):
            op = TestInstanceOf()
        case .testIn(_):
            op = TestIn()
        case .beginPlainFunction(let p):
            op = BeginPlainFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endPlainFunction(_):
            op = EndPlainFunction()
        case .beginArrowFunction(let p):
            op = BeginArrowFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endArrowFunction(_):
            op = EndArrowFunction()
        case .beginGeneratorFunction(let p):
            op = BeginGeneratorFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endGeneratorFunction(_):
            op = EndGeneratorFunction()
        case .beginAsyncFunction(let p):
            op = BeginAsyncFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endAsyncFunction(_):
            op = EndAsyncFunction()
        case .beginAsyncArrowFunction(let p):
            op = BeginAsyncArrowFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endAsyncArrowFunction(_):
            op = EndAsyncArrowFunction()
        case .beginAsyncGeneratorFunction(let p):
            op = BeginAsyncGeneratorFunction(signature: try FunctionSignature(from: p.signature), isStrict: p.isStrict)
        case .endAsyncGeneratorFunction(_):
            op = EndAsyncGeneratorFunction()
        case .return(_):
            op = Return()
        case .yield(_):
            op = Yield()
        case .yieldEach(_):
            op = YieldEach()
        case .await(_):
            op = Await()
        case .callFunction(_):
            op = CallFunction(numArguments: inouts.count - 2)
        case .callFunctionWithSpread(let p):
            op = CallFunctionWithSpread(numArguments: inouts.count - 2, spreads: p.spreads)
        case .construct(_):
            op = Construct(numArguments: inouts.count - 2)
        case .constructWithSpread(let p):
            op = ConstructWithSpread(numArguments: inouts.count - 2, spreads: p.spreads)
        case .callMethod(let p):
            op = CallMethod(methodName: p.methodName, numArguments: inouts.count - 2)
        case .callMethodWithSpread(let p):
            op = CallMethodWithSpread(methodName: p.methodName, numArguments: inouts.count - 2, spreads: p.spreads)
        case .callComputedMethod(_):
            op = CallComputedMethod(numArguments: inouts.count - 3)
        case .callComputedMethodWithSpread(let p):
            op = CallComputedMethodWithSpread(numArguments: inouts.count - 3, spreads: p.spreads)
        case .unaryOperation(let p):
            op = UnaryOperation(try convertEnum(p.op, allUnaryOperators))
        case .binaryOperation(let p):
            op = BinaryOperation(try convertEnum(p.op, allBinaryOperators))
        case .reassignWithBinop(let p):
            op = ReassignWithBinop(try convertEnum(p.op, allBinaryOperators))
        case .dup(_):
            op = Dup()
        case .reassign(_):
            op = Reassign()
        case .destructArray(let p):
            op = DestructArray(indices: p.indices.map({ Int($0) }), hasRestElement: p.hasRestElement_p)
        case .destructArrayAndReassign(let p):
            op = DestructArrayAndReassign(indices: p.indices.map({ Int($0) }), hasRestElement: p.hasRestElement_p)
        case .destructObject(let p):
            op = DestructObject(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .destructObjectAndReassign(let p):
            op = DestructObjectAndReassign(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .compare(let p):
            op = Compare(try convertEnum(p.op, allComparators))
        case .conditionalOperation(_):
            op = ConditionalOperation()
        case .eval(let p):
            op = Eval(p.code, numArguments: inouts.count)
        case .beginClass(let p):
            op = BeginClass(hasSuperclass: p.hasSuperclass_p,
                                      constructorParameters: try p.constructorParameters.map({ try Parameter(from: $0) }),
                                      instanceProperties: p.instanceProperties,
                                      instanceMethods: Array(zip(p.instanceMethodNames, try p.instanceMethodSignatures.map({ try FunctionSignature(from: $0) }))))
        case .beginMethod(let p):
            op = BeginMethod(numParameters: Int(p.numParameters))
        case .endClass(_):
            op = EndClass()
        case .callSuperConstructor(_):
            op = CallSuperConstructor(numArguments: inouts.count)
        case .callSuperMethod(let p):
            op = CallSuperMethod(methodName: p.methodName, numArguments: inouts.count - 1)
        case .loadSuperProperty(let p):
            op = LoadSuperProperty(propertyName: p.propertyName)
        case .storeSuperProperty(let p):
            op = StoreSuperProperty(propertyName: p.propertyName)
        case .storeSuperPropertyWithBinop(let p):
            op = StoreSuperPropertyWithBinop(propertyName: p.propertyName, operator: try convertEnum(p.op, allBinaryOperators))
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
        case .beginSwitch(_):
            op = BeginSwitch(numArguments: inouts.count)
        case .beginSwitchCase(let p):
            op = BeginSwitchCase(numArguments: inouts.count, fallsThrough: p.previousCaseFallsThrough)
        case .switchBreak(_):
            op = SwitchBreak()
        case .endSwitch(_):
            op = EndSwitch()
        case .beginWhile(let p):
            op = BeginWhileLoop(comparator: try convertEnum(p.comparator, allComparators))
        case .endWhile(_):
            op = EndWhileLoop()
        case .beginDoWhile(let p):
            op = BeginDoWhileLoop(comparator: try convertEnum(p.comparator, allComparators))
        case .endDoWhile(_):
            op = EndDoWhileLoop()
        case .beginFor(let p):
            op = BeginForLoop(comparator: try convertEnum(p.comparator, allComparators), op: try convertEnum(p.op, allBinaryOperators))
        case .endFor(_):
            op = EndForLoop()
        case .beginForIn(_):
            op = BeginForInLoop()
        case .endForIn(_):
            op = EndForInLoop()
        case .beginForOf(_):
            op = BeginForOfLoop()
        case .beginForOfWithDestruct(let p):
            op = BeginForOfWithDestructLoop(indices: p.indices.map({ Int($0) }), hasRestElement: p.hasRestElement_p)
        case .endForOf(_):
            op = EndForOfLoop()
        case .loopBreak(_):
            op = LoopBreak()
        case .loopContinue(_):
            op = LoopContinue()
        case .beginTry(_):
            op = BeginTry()
        case .beginCatch(_):
            op = BeginCatch()
        case .beginFinally(_):
            op = BeginFinally()
        case .endTryCatch(_):
            op = EndTryCatchFinally()
        case .throwException(_):
            op = ThrowException()
        case .beginCodeString(_):
            op = BeginCodeString()
        case .endCodeString(_):
            op = EndCodeString()
        case .beginBlockStatement(_):
            op = BeginBlockStatement()
        case .endBlockStatement(_):
            op = EndBlockStatement()
        case .nop(_):
            op = Nop()
        }

        guard op.numInputs + op.numOutputs + op.numInnerOutputs == inouts.count else {
            throw FuzzilliError.instructionDecodingError("incorrect number of in- and outputs")
        }

        opCache?.add(op)

        self.init(op, inouts: inouts)
    }

    init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}
