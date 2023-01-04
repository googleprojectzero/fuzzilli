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
    ///      Final value, if present: the index of this instruction in the code object it belongs to
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
        assert(i < numInputs)
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

    /// Whether this instruction has any variadic inputs.
    public var hasAnyVariadicInputs: Bool {
        return firstVariadicInput < numInputs
    }

    /// Whether this instruction has any outputs.
    public var hasOutputs: Bool {
        return numOutputs + numInnerOutputs > 0
    }

    /// Convenience getter for simple operations that produce a single output variable.
    public var output: Variable {
        assert(numOutputs == 1)
        return inouts_[numInputs]
    }

    /// Convenience getter for simple operations that produce a single inner output variable.
    public var innerOutput: Variable {
        assert(numInnerOutputs == 1)
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

    /// Whether this instruction contains its index in the code it belongs to.
    public var hasIndex: Bool {
        // If the index is present, it is the last value in inouts. See comment in index getter.
        return inouts_.count == numInouts + 1
    }

    /// The index of this instruction in the Code it belongs to.
    public var index: Int {
        // We store the index in the internal inouts array for memory efficiency reasons.
        // In practice, this does not limit the size of programs/code since that's already
        // limited by the fact that variables are UInt16 internally.
        assert(hasIndex)
        return Int(inouts_.last!.number)
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

    /// Whether this block start instruction propagates the outer context into the newly started block.
    /// See Operation.Attributes.propagatesSurroundingContext.
    public var propagatesSurroundingContext: Bool {
        assert(isBlockStart)
        return op.attributes.contains(.propagatesSurroundingContext)
    }

    /// Whether this instruction skips the last context and resumes the
    /// ContextAnalysis from the second last context stack, this is useful for
    /// BeginSwitch/EndSwitch Blocks. See BeginSwitchCase.
    public var skipsSurroundingContext: Bool {
        assert(isBlockStart)
        return op.attributes.contains(.resumesSurroundingContext)
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
        assert(op.numInputs == 0 && op.numOutputs == 1 && op.numInnerOutputs == 0)
        self.init(op, inouts: [output], index: index)
    }

    public init(_ op: Operation, output: Variable, inputs: [Variable], index: Int? = nil) {
        assert(op.numOutputs == 1)
        assert(op.numInnerOutputs == 0)
        assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs + [output], index: index)
    }

    public init(_ op: Operation, inputs: [Variable], index: Int? = nil) {
        assert(op.numOutputs + op.numInnerOutputs == 0)
        assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs, index: index)
    }

    public init(_ op: Operation, index: Int? = nil) {
        assert(op.numOutputs == 0)
        assert(op.numInputs == 0)
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

        func convertParameters(_ parameters: Parameters) -> Fuzzilli_Protobuf_Parameters {
            return Fuzzilli_Protobuf_Parameters.with {
                $0.count = UInt32(parameters.count)
                $0.hasRest_p = parameters.hasRestParameter
            }
        }

        let result = ProtobufType.with {
            $0.inouts = inouts.map({ UInt32($0.number) })

            // First see if we can use the cache.
            if let idx = opCache?.get(op) {
                $0.opIdx = UInt32(idx)
                return
            }

            // Otherwise, encode the operation.
            switch op.opcode {
            case .nop:
                $0.nop = Fuzzilli_Protobuf_Nop()
            case .loadInteger(let op):
                $0.loadInteger = Fuzzilli_Protobuf_LoadInteger.with { $0.value = op.value }
            case .loadBigInt(let op):
                $0.loadBigInt = Fuzzilli_Protobuf_LoadBigInt.with { $0.value = op.value }
            case .loadFloat(let op):
                $0.loadFloat = Fuzzilli_Protobuf_LoadFloat.with { $0.value = op.value }
            case .loadString(let op):
                $0.loadString = Fuzzilli_Protobuf_LoadString.with { $0.value = op.value }
            case .loadBoolean(let op):
                $0.loadBoolean = Fuzzilli_Protobuf_LoadBoolean.with { $0.value = op.value }
            case .loadUndefined:
                $0.loadUndefined = Fuzzilli_Protobuf_LoadUndefined()
            case .loadNull:
                $0.loadNull = Fuzzilli_Protobuf_LoadNull()
            case .loadThis:
                $0.loadThis = Fuzzilli_Protobuf_LoadThis()
            case .loadArguments:
                $0.loadArguments = Fuzzilli_Protobuf_LoadArguments()
            case .loadRegExp(let op):
                $0.loadRegExp = Fuzzilli_Protobuf_LoadRegExp.with { $0.value = op.value; $0.flags = op.flags.rawValue }
            case .createObject(let op):
                $0.createObject = Fuzzilli_Protobuf_CreateObject.with { $0.propertyNames = op.propertyNames }
            case .createObjectWithSpread(let op):
                $0.createObjectWithSpread = Fuzzilli_Protobuf_CreateObjectWithSpread.with { $0.propertyNames = op.propertyNames }
            case .createArray:
                $0.createArray = Fuzzilli_Protobuf_CreateArray()
            case .createIntArray(let op):
                $0.createIntArray = Fuzzilli_Protobuf_CreateIntArray.with { $0.values = op.values }
            case .createFloatArray(let op):
                $0.createFloatArray = Fuzzilli_Protobuf_CreateFloatArray.with { $0.values = op.values }
            case .createArrayWithSpread(let op):
                $0.createArrayWithSpread = Fuzzilli_Protobuf_CreateArrayWithSpread.with { $0.spreads = op.spreads }
            case .createTemplateString(let op):
                $0.createTemplateString = Fuzzilli_Protobuf_CreateTemplateString.with { $0.parts = op.parts }
            case .loadBuiltin(let op):
                $0.loadBuiltin = Fuzzilli_Protobuf_LoadBuiltin.with { $0.builtinName = op.builtinName }
            case .loadProperty(let op):
                $0.loadProperty = Fuzzilli_Protobuf_LoadProperty.with { $0.propertyName = op.propertyName }
            case .storeProperty(let op):
                $0.storeProperty = Fuzzilli_Protobuf_StoreProperty.with { $0.propertyName = op.propertyName }
            case .storePropertyWithBinop(let op):
                $0.storePropertyWithBinop = Fuzzilli_Protobuf_StorePropertyWithBinop.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .deleteProperty(let op):
                $0.deleteProperty = Fuzzilli_Protobuf_DeleteProperty.with { $0.propertyName = op.propertyName }
            case .configureProperty(let op):
                $0.configureProperty = Fuzzilli_Protobuf_ConfigureProperty.with {
                    $0.propertyName = op.propertyName
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .loadElement(let op):
                $0.loadElement = Fuzzilli_Protobuf_LoadElement.with { $0.index = op.index }
            case .storeElement(let op):
                $0.storeElement = Fuzzilli_Protobuf_StoreElement.with { $0.index = op.index }
            case .storeElementWithBinop(let op):
                $0.storeElementWithBinop = Fuzzilli_Protobuf_StoreElementWithBinop.with {
                    $0.index = op.index
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .deleteElement(let op):
                $0.deleteElement = Fuzzilli_Protobuf_DeleteElement.with { $0.index = op.index }
            case .configureElement(let op):
                $0.configureElement = Fuzzilli_Protobuf_ConfigureElement.with {
                    $0.index = op.index
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .loadComputedProperty:
                $0.loadComputedProperty = Fuzzilli_Protobuf_LoadComputedProperty()
            case .storeComputedProperty:
                $0.storeComputedProperty = Fuzzilli_Protobuf_StoreComputedProperty()
            case .storeComputedPropertyWithBinop(let op):
                $0.storeComputedPropertyWithBinop = Fuzzilli_Protobuf_StoreComputedPropertyWithBinop.with{ $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .deleteComputedProperty:
                $0.deleteComputedProperty = Fuzzilli_Protobuf_DeleteComputedProperty()
            case .configureComputedProperty(let op):
                $0.configureComputedProperty = Fuzzilli_Protobuf_ConfigureComputedProperty.with {
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .typeOf:
                $0.typeOf = Fuzzilli_Protobuf_TypeOf()
            case .testInstanceOf:
                $0.testInstanceOf = Fuzzilli_Protobuf_TestInstanceOf()
            case .testIn:
                $0.testIn = Fuzzilli_Protobuf_TestIn()
            case .beginPlainFunction(let op):
                $0.beginPlainFunction = Fuzzilli_Protobuf_BeginPlainFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case .endPlainFunction:
                $0.endPlainFunction = Fuzzilli_Protobuf_EndPlainFunction()
            case .beginArrowFunction(let op):
                $0.beginArrowFunction = Fuzzilli_Protobuf_BeginArrowFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case .endArrowFunction:
                $0.endArrowFunction = Fuzzilli_Protobuf_EndArrowFunction()
            case .beginGeneratorFunction(let op):
                $0.beginGeneratorFunction = Fuzzilli_Protobuf_BeginGeneratorFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case .endGeneratorFunction:
                $0.endGeneratorFunction = Fuzzilli_Protobuf_EndGeneratorFunction()
            case .beginAsyncFunction(let op):
                $0.beginAsyncFunction = Fuzzilli_Protobuf_BeginAsyncFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case.endAsyncFunction:
                $0.endAsyncFunction = Fuzzilli_Protobuf_EndAsyncFunction()
            case .beginAsyncArrowFunction(let op):
                $0.beginAsyncArrowFunction = Fuzzilli_Protobuf_BeginAsyncArrowFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case .endAsyncArrowFunction:
                $0.endAsyncArrowFunction = Fuzzilli_Protobuf_EndAsyncArrowFunction()
            case .beginAsyncGeneratorFunction(let op):
                $0.beginAsyncGeneratorFunction = Fuzzilli_Protobuf_BeginAsyncGeneratorFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    $0.isStrict = op.isStrict
                }
            case .endAsyncGeneratorFunction:
                $0.endAsyncGeneratorFunction = Fuzzilli_Protobuf_EndAsyncGeneratorFunction()
            case .beginConstructor(let op):
                $0.beginConstructor = Fuzzilli_Protobuf_BeginConstructor.with {
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endConstructor:
                $0.endConstructor = Fuzzilli_Protobuf_EndConstructor()
            case .return:
                $0.return = Fuzzilli_Protobuf_Return()
            case .yield:
                $0.yield = Fuzzilli_Protobuf_Yield()
            case .yieldEach:
                $0.yieldEach = Fuzzilli_Protobuf_YieldEach()
            case .await:
                $0.await = Fuzzilli_Protobuf_Await()
            case .callFunction:
                $0.callFunction = Fuzzilli_Protobuf_CallFunction()
            case .callFunctionWithSpread(let op):
                $0.callFunctionWithSpread = Fuzzilli_Protobuf_CallFunctionWithSpread.with { $0.spreads = op.spreads }
            case .construct:
                $0.construct = Fuzzilli_Protobuf_Construct()
            case .constructWithSpread(let op):
                $0.constructWithSpread = Fuzzilli_Protobuf_ConstructWithSpread.with { $0.spreads = op.spreads }
            case .callMethod(let op):
                $0.callMethod = Fuzzilli_Protobuf_CallMethod.with {
                    $0.methodName = op.methodName
                }
            case .callMethodWithSpread(let op):
                $0.callMethodWithSpread = Fuzzilli_Protobuf_CallMethodWithSpread.with {
                    $0.methodName = op.methodName
                    $0.spreads = op.spreads
                }
            case .callComputedMethod:
                $0.callComputedMethod = Fuzzilli_Protobuf_CallComputedMethod()
            case .callComputedMethodWithSpread(let op):
                $0.callComputedMethodWithSpread = Fuzzilli_Protobuf_CallComputedMethodWithSpread.with { $0.spreads = op.spreads }
            case .unaryOperation(let op):
                $0.unaryOperation = Fuzzilli_Protobuf_UnaryOperation.with { $0.op = convertEnum(op.op, UnaryOperator.allCases) }
            case .binaryOperation(let op):
                $0.binaryOperation = Fuzzilli_Protobuf_BinaryOperation.with { $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .ternaryOperation:
                $0.ternaryOperation = Fuzzilli_Protobuf_TernaryOperation()
            case .reassign:
                $0.reassign = Fuzzilli_Protobuf_Reassign()
            case .reassignWithBinop(let op):
                $0.reassignWithBinop = Fuzzilli_Protobuf_ReassignWithBinop.with { $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .dup:
                $0.dup = Fuzzilli_Protobuf_Dup()
            case .destructArray(let op):
                $0.destructArray = Fuzzilli_Protobuf_DestructArray.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .destructArrayAndReassign(let op):
                $0.destructArrayAndReassign = Fuzzilli_Protobuf_DestructArrayAndReassign.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .destructObject(let op):
                $0.destructObject = Fuzzilli_Protobuf_DestructObject.with {
                    $0.properties = op.properties
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .destructObjectAndReassign(let op):
                $0.destructObjectAndReassign = Fuzzilli_Protobuf_DestructObjectAndReassign.with {
                    $0.properties = op.properties
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .compare(let op):
                $0.compare = Fuzzilli_Protobuf_Compare.with { $0.op = convertEnum(op.op, Comparator.allCases) }
            case .eval(let op):
                $0.eval = Fuzzilli_Protobuf_Eval.with { $0.code = op.code }
            case .beginClass(let op):
                $0.beginClass = Fuzzilli_Protobuf_BeginClass.with {
                    $0.hasSuperclass_p = op.hasSuperclass
                    $0.constructorParameters = convertParameters(op.constructorParameters)
                    $0.instanceProperties = op.instanceProperties
                    $0.instanceMethodNames = op.instanceMethods.map({ $0.name })
                    $0.instanceMethodParameters = op.instanceMethods.map({ convertParameters($0.parameters) })
                }
            case .beginMethod(let op):
                $0.beginMethod = Fuzzilli_Protobuf_BeginMethod.with { $0.numParameters = UInt32(op.numParameters) }
            case .endClass:
                $0.endClass = Fuzzilli_Protobuf_EndClass()
            case .callSuperConstructor:
                $0.callSuperConstructor = Fuzzilli_Protobuf_CallSuperConstructor()
            case .callSuperMethod(let op):
                $0.callSuperMethod = Fuzzilli_Protobuf_CallSuperMethod.with { $0.methodName = op.methodName }
            case .loadSuperProperty(let op):
                $0.loadSuperProperty = Fuzzilli_Protobuf_LoadSuperProperty.with { $0.propertyName = op.propertyName }
            case .storeSuperProperty(let op):
                $0.storeSuperProperty = Fuzzilli_Protobuf_StoreSuperProperty.with { $0.propertyName = op.propertyName }
            case .storeSuperPropertyWithBinop(let op):
                $0.storeSuperPropertyWithBinop = Fuzzilli_Protobuf_StoreSuperPropertyWithBinop.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .explore(let op):
                $0.explore = Fuzzilli_Protobuf_Explore.with { $0.id = op.id }
            case .probe(let op):
                $0.probe = Fuzzilli_Protobuf_Probe.with { $0.id = op.id }
            case .beginWith:
                $0.beginWith = Fuzzilli_Protobuf_BeginWith()
            case .endWith:
                $0.endWith = Fuzzilli_Protobuf_EndWith()
            case .loadFromScope(let op):
                $0.loadFromScope = Fuzzilli_Protobuf_LoadFromScope.with { $0.id = op.id }
            case .storeToScope(let op):
                $0.storeToScope = Fuzzilli_Protobuf_StoreToScope.with { $0.id = op.id }
            case .beginIf(let op):
                $0.beginIf = Fuzzilli_Protobuf_BeginIf.with {
                    $0.inverted = op.inverted
                }
            case .beginElse:
                $0.beginElse = Fuzzilli_Protobuf_BeginElse()
            case .endIf:
                $0.endIf = Fuzzilli_Protobuf_EndIf()
            case .beginSwitch:
                $0.beginSwitch = Fuzzilli_Protobuf_BeginSwitch()
            case .beginSwitchCase:
                $0.beginSwitchCase = Fuzzilli_Protobuf_BeginSwitchCase()
            case .beginSwitchDefaultCase:
                $0.beginSwitchDefaultCase = Fuzzilli_Protobuf_BeginSwitchDefaultCase()
            case .switchBreak:
                $0.switchBreak = Fuzzilli_Protobuf_SwitchBreak()
            case .endSwitchCase(let op):
                $0.endSwitchCase = Fuzzilli_Protobuf_EndSwitchCase.with { $0.fallsThrough = op.fallsThrough }
            case .endSwitch:
                $0.endSwitch = Fuzzilli_Protobuf_EndSwitch()
            case .beginWhileLoop(let op):
                $0.beginWhile = Fuzzilli_Protobuf_BeginWhile.with { $0.comparator = convertEnum(op.comparator, Comparator.allCases) }
            case .endWhileLoop:
                $0.endWhile = Fuzzilli_Protobuf_EndWhile()
            case .beginDoWhileLoop(let op):
                $0.beginDoWhile = Fuzzilli_Protobuf_BeginDoWhile.with { $0.comparator = convertEnum(op.comparator, Comparator.allCases) }
            case .endDoWhileLoop:
                $0.endDoWhile = Fuzzilli_Protobuf_EndDoWhile()
            case .beginForLoop(let op):
                $0.beginFor = Fuzzilli_Protobuf_BeginFor.with {
                    $0.comparator = convertEnum(op.comparator, Comparator.allCases)
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .endForLoop:
                $0.endFor = Fuzzilli_Protobuf_EndFor()
            case .beginForInLoop:
                $0.beginForIn = Fuzzilli_Protobuf_BeginForIn()
            case .endForInLoop:
                $0.endForIn = Fuzzilli_Protobuf_EndForIn()
            case .beginForOfLoop:
                $0.beginForOf = Fuzzilli_Protobuf_BeginForOf()
            case .beginForOfWithDestructLoop(let op):
                $0.beginForOfWithDestruct = Fuzzilli_Protobuf_BeginForOfWithDestruct.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .endForOfLoop:
                $0.endForOf = Fuzzilli_Protobuf_EndForOf()
            case .beginRepeatLoop(let op):
                $0.beginRepeat = Fuzzilli_Protobuf_BeginRepeat.with { $0.iterations = Int64(op.iterations) }
            case .endRepeatLoop:
                $0.endRepeat = Fuzzilli_Protobuf_EndRepeat()
            case .loopBreak:
                $0.loopBreak = Fuzzilli_Protobuf_LoopBreak()
            case .loopContinue:
                $0.loopContinue = Fuzzilli_Protobuf_LoopContinue()
            case .beginTry:
                $0.beginTry = Fuzzilli_Protobuf_BeginTry()
            case .beginCatch:
                $0.beginCatch = Fuzzilli_Protobuf_BeginCatch()
            case .beginFinally:
                $0.beginFinally = Fuzzilli_Protobuf_BeginFinally()
            case .endTryCatchFinally:
                $0.endTryCatch = Fuzzilli_Protobuf_EndTryCatch()
            case .throwException:
                $0.throwException = Fuzzilli_Protobuf_ThrowException()
            case .beginCodeString:
                $0.beginCodeString = Fuzzilli_Protobuf_BeginCodeString()
            case .endCodeString:
                $0.endCodeString = Fuzzilli_Protobuf_EndCodeString()
            case .beginBlockStatement:
                $0.beginBlockStatement = Fuzzilli_Protobuf_BeginBlockStatement()
            case .endBlockStatement:
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

        func convertParameters(_ parameters: Fuzzilli_Protobuf_Parameters) -> Parameters {
            return Parameters(count: Int(parameters.count), hasRestParameter: parameters.hasRest_p)
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
        case .loadUndefined:
            op = LoadUndefined()
        case .loadNull:
            op = LoadNull()
        case .loadThis:
            op = LoadThis()
        case .loadArguments:
            op = LoadArguments()
        case .loadRegExp(let p):
            op = LoadRegExp(value: p.value, flags: RegExpFlags(rawValue: p.flags))
        case .createObject(let p):
            op = CreateObject(propertyNames: p.propertyNames)
        case .createArray:
            op = CreateArray(numInitialValues: inouts.count - 1)
        case .createIntArray(let p):
            op = CreateIntArray(values: p.values)
        case .createFloatArray(let p):
            op = CreateFloatArray(values: p.values)
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
            op = StorePropertyWithBinop(propertyName: p.propertyName, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteProperty(let p):
            op = DeleteProperty(propertyName: p.propertyName)
        case .configureProperty(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureProperty(propertyName: p.propertyName, flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .loadElement(let p):
            op = LoadElement(index: p.index)
        case .storeElement(let p):
            op = StoreElement(index: p.index)
        case .storeElementWithBinop(let p):
            op = StoreElementWithBinop(index: p.index, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteElement(let p):
            op = DeleteElement(index: p.index)
        case .configureElement(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureElement(index: p.index, flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .loadComputedProperty:
            op = LoadComputedProperty()
        case .storeComputedProperty:
            op = StoreComputedProperty()
        case .storeComputedPropertyWithBinop(let p):
            op = StoreComputedPropertyWithBinop(operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteComputedProperty:
            op = DeleteComputedProperty()
        case .configureComputedProperty(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureComputedProperty(flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .typeOf:
            op = TypeOf()
        case .testInstanceOf:
            op = TestInstanceOf()
        case .testIn:
            op = TestIn()
        case .beginPlainFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginPlainFunction(parameters: parameters, isStrict: p.isStrict)
        case .endPlainFunction:
            op = EndPlainFunction()
        case .beginArrowFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginArrowFunction(parameters: parameters, isStrict: p.isStrict)
        case .endArrowFunction:
            op = EndArrowFunction()
        case .beginGeneratorFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginGeneratorFunction(parameters: parameters, isStrict: p.isStrict)
        case .endGeneratorFunction:
            op = EndGeneratorFunction()
        case .beginAsyncFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginAsyncFunction(parameters: parameters, isStrict: p.isStrict)
        case .endAsyncFunction:
            op = EndAsyncFunction()
        case .beginAsyncArrowFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginAsyncArrowFunction(parameters: parameters, isStrict: p.isStrict)
        case .endAsyncArrowFunction:
            op = EndAsyncArrowFunction()
        case .beginAsyncGeneratorFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginAsyncGeneratorFunction(parameters: parameters, isStrict: p.isStrict)
        case .endAsyncGeneratorFunction:
            op = EndAsyncGeneratorFunction()
        case .beginConstructor(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginConstructor(parameters: parameters)
        case .endConstructor:
            op = EndConstructor()
        case .return:
            op = Return()
        case .yield:
            op = Yield()
        case .yieldEach:
            op = YieldEach()
        case .await:
            op = Await()
        case .callFunction:
            op = CallFunction(numArguments: inouts.count - 2)
        case .callFunctionWithSpread(let p):
            op = CallFunctionWithSpread(numArguments: inouts.count - 2, spreads: p.spreads)
        case .construct:
            op = Construct(numArguments: inouts.count - 2)
        case .constructWithSpread(let p):
            op = ConstructWithSpread(numArguments: inouts.count - 2, spreads: p.spreads)
        case .callMethod(let p):
            op = CallMethod(methodName: p.methodName, numArguments: inouts.count - 2)
        case .callMethodWithSpread(let p):
            op = CallMethodWithSpread(methodName: p.methodName, numArguments: inouts.count - 2, spreads: p.spreads)
        case .callComputedMethod:
            op = CallComputedMethod(numArguments: inouts.count - 3)
        case .callComputedMethodWithSpread(let p):
            op = CallComputedMethodWithSpread(numArguments: inouts.count - 3, spreads: p.spreads)
        case .unaryOperation(let p):
            op = UnaryOperation(try convertEnum(p.op, UnaryOperator.allCases))
        case .binaryOperation(let p):
            op = BinaryOperation(try convertEnum(p.op, BinaryOperator.allCases))
        case .ternaryOperation:
            op = TernaryOperation()
        case .reassignWithBinop(let p):
            op = ReassignWithBinop(try convertEnum(p.op, BinaryOperator.allCases))
        case .dup:
            op = Dup()
        case .reassign:
            op = Reassign()
        case .destructArray(let p):
            op = DestructArray(indices: p.indices.map({ Int64($0) }), hasRestElement: p.hasRestElement_p)
        case .destructArrayAndReassign(let p):
            op = DestructArrayAndReassign(indices: p.indices.map({ Int64($0) }), hasRestElement: p.hasRestElement_p)
        case .destructObject(let p):
            op = DestructObject(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .destructObjectAndReassign(let p):
            op = DestructObjectAndReassign(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .compare(let p):
            op = Compare(try convertEnum(p.op, Comparator.allCases))
        case .eval(let p):
            op = Eval(p.code, numArguments: inouts.count)
        case .beginClass(let p):
            op = BeginClass(hasSuperclass: p.hasSuperclass_p,
                            constructorParameters: convertParameters(p.constructorParameters),
                            instanceProperties: p.instanceProperties,
                            instanceMethods: Array(zip(p.instanceMethodNames, p.instanceMethodParameters.map(convertParameters))))
        case .beginMethod(let p):
            op = BeginMethod(numParameters: Int(p.numParameters))
        case .endClass:
            op = EndClass()
        case .callSuperConstructor:
            op = CallSuperConstructor(numArguments: inouts.count)
        case .callSuperMethod(let p):
            op = CallSuperMethod(methodName: p.methodName, numArguments: inouts.count - 1)
        case .loadSuperProperty(let p):
            op = LoadSuperProperty(propertyName: p.propertyName)
        case .storeSuperProperty(let p):
            op = StoreSuperProperty(propertyName: p.propertyName)
        case .storeSuperPropertyWithBinop(let p):
            op = StoreSuperPropertyWithBinop(propertyName: p.propertyName, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .explore(let p):
            op = Explore(id: p.id, numArguments: inouts.count - 1)
        case .probe(let p):
            op = Probe(id: p.id)
        case .beginWith:
            op = BeginWith()
        case .endWith:
            op = EndWith()
        case .loadFromScope(let p):
            op = LoadFromScope(id: p.id)
        case .storeToScope(let p):
            op = StoreToScope(id: p.id)
        case .beginIf(let p):
            op = BeginIf(inverted: p.inverted)
        case .beginElse:
            op = BeginElse()
        case .endIf:
            op = EndIf()
        case .beginSwitch:
            op = BeginSwitch()
        case .beginSwitchCase:
            op = BeginSwitchCase()
        case .beginSwitchDefaultCase:
            op = BeginSwitchDefaultCase()
        case .switchBreak:
            op = SwitchBreak()
        case .endSwitchCase(let p):
            op = EndSwitchCase(fallsThrough: p.fallsThrough)
        case .endSwitch:
            op = EndSwitch()
        case .beginWhile(let p):
            op = BeginWhileLoop(comparator: try convertEnum(p.comparator, Comparator.allCases))
        case .endWhile:
            op = EndWhileLoop()
        case .beginDoWhile(let p):
            op = BeginDoWhileLoop(comparator: try convertEnum(p.comparator, Comparator.allCases))
        case .endDoWhile:
            op = EndDoWhileLoop()
        case .beginFor(let p):
            op = BeginForLoop(comparator: try convertEnum(p.comparator, Comparator.allCases), op: try convertEnum(p.op, BinaryOperator.allCases))
        case .endFor:
            op = EndForLoop()
        case .beginForIn:
            op = BeginForInLoop()
        case .endForIn:
            op = EndForInLoop()
        case .beginForOf:
            op = BeginForOfLoop()
        case .beginForOfWithDestruct(let p):
            op = BeginForOfWithDestructLoop(indices: p.indices.map({ Int64($0) }), hasRestElement: p.hasRestElement_p)
        case .endForOf:
            op = EndForOfLoop()
        case .beginRepeat(let p):
            op = BeginRepeatLoop(iterations: Int(p.iterations))
        case .endRepeat:
            op = EndRepeatLoop()
        case .loopBreak:
            op = LoopBreak()
        case .loopContinue:
            op = LoopContinue()
        case .beginTry:
            op = BeginTry()
        case .beginCatch:
            op = BeginCatch()
        case .beginFinally:
            op = BeginFinally()
        case .endTryCatch:
            op = EndTryCatchFinally()
        case .throwException:
            op = ThrowException()
        case .beginCodeString:
            op = BeginCodeString()
        case .endCodeString:
            op = EndCodeString()
        case .beginBlockStatement:
            op = BeginBlockStatement()
        case .endBlockStatement:
            op = EndBlockStatement()
        case .nop:
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
