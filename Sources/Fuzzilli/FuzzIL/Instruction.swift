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
    private let inouts_: [Variable]

    /// The index of this instruction if it belongs to a `Code`, otherwise it is `UInt16.max`.
    /// In practice, this does not limit the size of programs/code since that's already
    /// limited by the fact that variables are UInt16 internally.
    private var indexValue: UInt16 = UInt16.max

    /// The flags associated with this instruction, right now these are mainly used during minimization.
    public var flags: Self.Flags

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

    /// Whether this instruction has exaclty one output.
    public var hasOneOutput: Bool {
        return numOutputs == 1
    }

    /// Convenience getter for simple operations that produce a single output variable.
    public var output: Variable {
        assert(hasOneOutput)
        return inouts_[numInputs]
    }

    /// Convenience getter for simple operations that produce a single inner output variable.
    public var innerOutput: Variable {
        assert(numInnerOutputs == 1)
        return inouts_[numInputs + numOutputs]
    }

    /// The output variables of this instruction in the surrounding scope.
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

    /// The index of this instruction in the `Code` it belongs to.
    public var index: Int {
        // Check that this instruction belongs to a `Code` object, i.e. it has a proper value
        assert(self.indexValue != UInt16.max)
        return Int(self.indexValue)
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

    /// An operation is singular if there must only be one of its kind in its surrounding block.
    /// See Operation.Attributes.isSingular.
    public var isSingular: Bool {
        return op.attributes.contains(.isSingular)
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

    /// Whether this instruction's operation is a GuardableOperations _and_ the guarding is active.
    /// Guarded operations "swallow" runtime exceptions, for example by wrapping them into a try-catch during lifting.
    public var isGuarded: Bool {
        return (op as? GuardableOperation)?.isGuarded ?? false
    }

    /// Whether this instruction is an internal instruction that should not "leak" into
    /// the corpus or generally out of the component that generated it.
    public var isInternal: Bool {
        return op.attributes.contains(.isInternal)
    }

    /// Whether this instruction is a Nop instruction.
    public var isNop: Bool {
        return op.attributes.contains(.isNop)
    }

    /// Whether this instruction can be mutated with the input mutator
    public var isNotInputMutable: Bool {
        return op.attributes.contains(.isNotInputMutable)
    }


    public init<Variables: Collection>(_ op: Operation, inouts: Variables, index: Int? = nil, flags: Self.Flags) where Variables.Element == Variable {
        assert(op.numInputs + op.numOutputs + op.numInnerOutputs == inouts.count)
        self.op = op
        self.inouts_ = Array(inouts)
        if let idx = index {
            self.indexValue = UInt16(idx)
        }
        self.flags = flags
    }

    public init(_ op: Operation, output: Variable) {
        assert(op.numInputs == 0 && op.numOutputs == 1 && op.numInnerOutputs == 0)
        self.init(op, inouts: [output], flags: .empty)
    }

    public init(_ op: Operation, output: Variable, inputs: [Variable]) {
        assert(op.numOutputs == 1)
        assert(op.numInnerOutputs == 0)
        assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs + [output], flags: .empty)
    }

    public init(_ op: Operation, inputs: [Variable]) {
        assert(op.numOutputs + op.numInnerOutputs == 0)
        assert(op.numInputs == inputs.count)
        self.init(op, inouts: inputs, flags: .empty)
    }

    public init(_ op: Operation, innerOutput: Variable) {
        assert(op.numInnerOutputs == 1)
        assert(op.numOutputs == 0)
        assert(op.numInputs == 0)
        self.init(op, inouts: [innerOutput], flags: .empty)
    }

    public init(_ op: Operation) {
        assert(op.numOutputs + op.numInnerOutputs == 0)
        assert(op.numInputs == 0)
        self.init(op, inouts: [], flags: .empty)
    }

    /// Flags associated with an Instruction.
    /// This can be useful to mark instructions in some way, for example during minimization.
    public struct Flags: OptionSet, CaseIterable {
        public static var allCases: [Instruction.Flags] = [.notRemovable]

        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
        /// If this is set, the minimizer cannot remove this instruction.
        public static let notRemovable = Self(rawValue: 1 << 0)
        public static let empty = Self([])
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

        func ILTypeToWasmTypeEnum(_ wasmType: ILType) -> Fuzzilli_Protobuf_WasmILType {
            let value: Int
            if wasmType == .nothing {
                // This is used as sentinel for function signatures that don't have a return value
                return Fuzzilli_Protobuf_WasmILType(rawValue: 9)!
            }
            if wasmType.Is(.object()) {
                switch wasmType.group {
                case "WasmGlobal.i32":
                    value = 0
                case "WasmGlobal.i64":
                    value = 1
                case "WasmGlobal.f32":
                    value = 2
                case "WasmGlobal.f64":
                    value = 3
                case "WasmTable.externref":
                    value = 6
                case "WasmTable.funcref":
                    value = 7
                case "WasmMemory":
                    value = 8
                default:
                    fatalError("Can not serialize a non-wasm type \(wasmType) into a WasmILType! for instruction \(self)")
                }
            } else {
                switch wasmType {
                case .wasmi32:
                    value = 0
                case .wasmi64:
                    value = 1
                case .wasmf32:
                    value = 2
                case .wasmf64:
                    value = 3
                case .wasmExternRef:
                    value = 4
                case .wasmFuncRef:
                    value = 5
                case .externRefTable:
                    value = 6
                case .funcRefTable:
                    value = 7
                case .wasmMemory:
                    value = 8
                default:
                    fatalError("Can not serialize a non-wasm type \(wasmType) into a WasmILType! for instruction \(self)")
                }
            }
            return Fuzzilli_Protobuf_WasmILType(rawValue: value)!
        }

        func convertWasmGlobal(wasmGlobal: WasmGlobal) -> Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal {
            switch wasmGlobal {
            case .wasmi32(let val):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.valuei32(val)
            case .wasmi64(let val):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.valuei64(val)
            case .wasmf32(let val):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.valuef32(val)
            case .wasmf64(let val):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.valuef64(val)
            case .refFunc(let val):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.funcref(Int64(val))
            case .refNull:
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.nullref(0)
            case .imported(let ilType):
                return Fuzzilli_Protobuf_WasmGlobal.OneOf_WasmGlobal.imported(ILTypeToWasmTypeEnum(ilType))
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
            case .loadDisposableVariable:
                $0.loadDisposableVariable = Fuzzilli_Protobuf_LoadDisposableVariable()
            case .loadAsyncDisposableVariable:
                $0.loadAsyncDisposableVariable = Fuzzilli_Protobuf_LoadAsyncDisposableVariable()
            case .loadRegExp(let op):
                $0.loadRegExp = Fuzzilli_Protobuf_LoadRegExp.with { $0.pattern = op.pattern; $0.flags = op.flags.rawValue }
            case .beginObjectLiteral:
                $0.beginObjectLiteral = Fuzzilli_Protobuf_BeginObjectLiteral()
            case .objectLiteralAddProperty(let op):
                $0.objectLiteralAddProperty = Fuzzilli_Protobuf_ObjectLiteralAddProperty.with { $0.propertyName = op.propertyName }
            case .objectLiteralAddElement(let op):
                $0.objectLiteralAddElement = Fuzzilli_Protobuf_ObjectLiteralAddElement.with { $0.index = op.index }
            case .objectLiteralAddComputedProperty:
                $0.objectLiteralAddComputedProperty = Fuzzilli_Protobuf_ObjectLiteralAddComputedProperty()
            case .objectLiteralCopyProperties:
                $0.objectLiteralCopyProperties = Fuzzilli_Protobuf_ObjectLiteralCopyProperties()
            case .objectLiteralSetPrototype:
                $0.objectLiteralSetPrototype = Fuzzilli_Protobuf_ObjectLiteralSetPrototype()
            case .beginObjectLiteralMethod(let op):
                $0.beginObjectLiteralMethod = Fuzzilli_Protobuf_BeginObjectLiteralMethod.with {
                    $0.methodName = op.methodName
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endObjectLiteralMethod:
                $0.endObjectLiteralMethod = Fuzzilli_Protobuf_EndObjectLiteralMethod()
            case .beginObjectLiteralComputedMethod(let op):
                $0.beginObjectLiteralComputedMethod = Fuzzilli_Protobuf_BeginObjectLiteralComputedMethod.with { $0.parameters = convertParameters(op.parameters) }
            case .endObjectLiteralComputedMethod:
                $0.endObjectLiteralComputedMethod = Fuzzilli_Protobuf_EndObjectLiteralComputedMethod()
            case .beginObjectLiteralGetter(let op):
                $0.beginObjectLiteralGetter = Fuzzilli_Protobuf_BeginObjectLiteralGetter.with { $0.propertyName = op.propertyName }
            case .endObjectLiteralGetter:
                $0.endObjectLiteralGetter = Fuzzilli_Protobuf_EndObjectLiteralGetter()
            case .beginObjectLiteralSetter(let op):
                $0.beginObjectLiteralSetter = Fuzzilli_Protobuf_BeginObjectLiteralSetter.with { $0.propertyName = op.propertyName }
            case .endObjectLiteralSetter:
                $0.endObjectLiteralSetter = Fuzzilli_Protobuf_EndObjectLiteralSetter()
            case .endObjectLiteral:
                $0.endObjectLiteral = Fuzzilli_Protobuf_EndObjectLiteral()
            case .beginClassDefinition(let op):
                $0.beginClassDefinition = Fuzzilli_Protobuf_BeginClassDefinition.with { $0.hasSuperclass_p = op.hasSuperclass }
            case .beginClassConstructor(let op):
                $0.beginClassConstructor = Fuzzilli_Protobuf_BeginClassConstructor.with { $0.parameters = convertParameters(op.parameters) }
            case .endClassConstructor:
                $0.endClassConstructor = Fuzzilli_Protobuf_EndClassConstructor()
            case .classAddInstanceProperty(let op):
                $0.classAddInstanceProperty = Fuzzilli_Protobuf_ClassAddInstanceProperty.with {
                    $0.propertyName = op.propertyName
                    $0.hasValue_p = op.hasValue
                }
            case .classAddInstanceElement(let op):
                $0.classAddInstanceElement = Fuzzilli_Protobuf_ClassAddInstanceElement.with {
                    $0.index = op.index
                    $0.hasValue_p = op.hasValue
                }
            case .classAddInstanceComputedProperty(let op):
                $0.classAddInstanceComputedProperty = Fuzzilli_Protobuf_ClassAddInstanceComputedProperty.with { $0.hasValue_p = op.hasValue }
            case .beginClassInstanceMethod(let op):
                $0.beginClassInstanceMethod = Fuzzilli_Protobuf_BeginClassInstanceMethod.with {
                    $0.methodName = op.methodName
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endClassInstanceMethod:
                $0.endClassInstanceMethod = Fuzzilli_Protobuf_EndClassInstanceMethod()
            case .beginClassInstanceGetter(let op):
                $0.beginClassInstanceGetter = Fuzzilli_Protobuf_BeginClassInstanceGetter.with { $0.propertyName = op.propertyName }
            case .endClassInstanceGetter:
                $0.endClassInstanceGetter = Fuzzilli_Protobuf_EndClassInstanceGetter()
            case .beginClassInstanceSetter(let op):
                $0.beginClassInstanceSetter = Fuzzilli_Protobuf_BeginClassInstanceSetter.with { $0.propertyName = op.propertyName }
            case .endClassInstanceSetter:
                $0.endClassInstanceSetter = Fuzzilli_Protobuf_EndClassInstanceSetter()
            case .classAddStaticProperty(let op):
                $0.classAddStaticProperty = Fuzzilli_Protobuf_ClassAddStaticProperty.with {
                    $0.propertyName = op.propertyName
                    $0.hasValue_p = op.hasValue
                }
            case .classAddStaticElement(let op):
                $0.classAddStaticElement = Fuzzilli_Protobuf_ClassAddStaticElement.with {
                    $0.index = op.index
                    $0.hasValue_p = op.hasValue
                }
            case .classAddStaticComputedProperty(let op):
                $0.classAddStaticComputedProperty = Fuzzilli_Protobuf_ClassAddStaticComputedProperty.with { $0.hasValue_p = op.hasValue }
            case .beginClassStaticInitializer:
                $0.beginClassStaticInitializer = Fuzzilli_Protobuf_BeginClassStaticInitializer()
            case .endClassStaticInitializer:
                $0.endClassStaticInitializer = Fuzzilli_Protobuf_EndClassStaticInitializer()
            case .beginClassStaticMethod(let op):
                $0.beginClassStaticMethod = Fuzzilli_Protobuf_BeginClassStaticMethod.with {
                    $0.methodName = op.methodName
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endClassStaticMethod:
                $0.endClassStaticMethod = Fuzzilli_Protobuf_EndClassStaticMethod()
            case .beginClassStaticGetter(let op):
                $0.beginClassStaticGetter = Fuzzilli_Protobuf_BeginClassStaticGetter.with { $0.propertyName = op.propertyName }
            case .endClassStaticGetter:
                $0.endClassStaticGetter = Fuzzilli_Protobuf_EndClassStaticGetter()
            case .beginClassStaticSetter(let op):
                $0.beginClassStaticSetter = Fuzzilli_Protobuf_BeginClassStaticSetter.with { $0.propertyName = op.propertyName }
            case .endClassStaticSetter:
                $0.endClassStaticSetter = Fuzzilli_Protobuf_EndClassStaticSetter()
            case .classAddPrivateInstanceProperty(let op):
                $0.classAddPrivateInstanceProperty = Fuzzilli_Protobuf_ClassAddPrivateInstanceProperty.with {
                    $0.propertyName = op.propertyName
                    $0.hasValue_p = op.hasValue
                }
            case .beginClassPrivateInstanceMethod(let op):
                $0.beginClassPrivateInstanceMethod = Fuzzilli_Protobuf_BeginClassPrivateInstanceMethod.with {
                    $0.methodName = op.methodName
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endClassPrivateInstanceMethod:
                $0.endClassPrivateInstanceMethod = Fuzzilli_Protobuf_EndClassPrivateInstanceMethod()
            case .classAddPrivateStaticProperty(let op):
                $0.classAddPrivateStaticProperty = Fuzzilli_Protobuf_ClassAddPrivateStaticProperty.with {
                    $0.propertyName = op.propertyName
                    $0.hasValue_p = op.hasValue
                }
            case .beginClassPrivateStaticMethod(let op):
                $0.beginClassPrivateStaticMethod = Fuzzilli_Protobuf_BeginClassPrivateStaticMethod.with {
                    $0.methodName = op.methodName
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endClassPrivateStaticMethod:
                $0.endClassPrivateStaticMethod = Fuzzilli_Protobuf_EndClassPrivateStaticMethod()
            case .endClassDefinition:
                $0.endClassDefinition = Fuzzilli_Protobuf_EndClassDefinition()
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
            case .getProperty(let op):
                $0.getProperty = Fuzzilli_Protobuf_GetProperty.with {
                    $0.propertyName = op.propertyName
                    $0.isGuarded = op.isGuarded
                }
            case .setProperty(let op):
                $0.setProperty = Fuzzilli_Protobuf_SetProperty.with { $0.propertyName = op.propertyName }
            case .updateProperty(let op):
                $0.updateProperty = Fuzzilli_Protobuf_UpdateProperty.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .deleteProperty(let op):
                $0.deleteProperty = Fuzzilli_Protobuf_DeleteProperty.with {
                    $0.propertyName = op.propertyName
                    $0.isGuarded = op.isGuarded
                }
            case .configureProperty(let op):
                $0.configureProperty = Fuzzilli_Protobuf_ConfigureProperty.with {
                    $0.propertyName = op.propertyName
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .getElement(let op):
                $0.getElement = Fuzzilli_Protobuf_GetElement.with {
                    $0.index = op.index
                    $0.isGuarded = op.isGuarded
                }
            case .setElement(let op):
                $0.setElement = Fuzzilli_Protobuf_SetElement.with { $0.index = op.index }
            case .updateElement(let op):
                $0.updateElement = Fuzzilli_Protobuf_UpdateElement.with {
                    $0.index = op.index
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .deleteElement(let op):
                $0.deleteElement = Fuzzilli_Protobuf_DeleteElement.with {
                    $0.index = op.index
                    $0.isGuarded = op.isGuarded
                }
            case .configureElement(let op):
                $0.configureElement = Fuzzilli_Protobuf_ConfigureElement.with {
                    $0.index = op.index
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .getComputedProperty(let op):
                $0.getComputedProperty = Fuzzilli_Protobuf_GetComputedProperty.with { $0.isGuarded = op.isGuarded }
            case .setComputedProperty:
                $0.setComputedProperty = Fuzzilli_Protobuf_SetComputedProperty()
            case .updateComputedProperty(let op):
                $0.updateComputedProperty = Fuzzilli_Protobuf_UpdateComputedProperty.with{ $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .deleteComputedProperty(let op):
                $0.deleteComputedProperty = Fuzzilli_Protobuf_DeleteComputedProperty.with { $0.isGuarded = op.isGuarded }
            case .configureComputedProperty(let op):
                $0.configureComputedProperty = Fuzzilli_Protobuf_ConfigureComputedProperty.with {
                    $0.isWritable = op.flags.contains(.writable)
                    $0.isConfigurable = op.flags.contains(.configurable)
                    $0.isEnumerable = op.flags.contains(.enumerable)
                    $0.type = convertEnum(op.type, PropertyType.allCases)
                }
            case .typeOf:
                $0.typeOf = Fuzzilli_Protobuf_TypeOf()
            case .void:
                $0.void = Fuzzilli_Protobuf_Void()
            case .testInstanceOf:
                $0.testInstanceOf = Fuzzilli_Protobuf_TestInstanceOf()
            case .testIn:
                $0.testIn = Fuzzilli_Protobuf_TestIn()
            case .beginPlainFunction(let op):
                $0.beginPlainFunction = Fuzzilli_Protobuf_BeginPlainFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    if let name = op.functionName {
                        $0.name = name
                    }
                }
            case .endPlainFunction:
                $0.endPlainFunction = Fuzzilli_Protobuf_EndPlainFunction()
            case .beginArrowFunction(let op):
                $0.beginArrowFunction = Fuzzilli_Protobuf_BeginArrowFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endArrowFunction:
                $0.endArrowFunction = Fuzzilli_Protobuf_EndArrowFunction()
            case .beginGeneratorFunction(let op):
                $0.beginGeneratorFunction = Fuzzilli_Protobuf_BeginGeneratorFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    if let name = op.functionName {
                        $0.name = name
                    }
                }
            case .endGeneratorFunction:
                $0.endGeneratorFunction = Fuzzilli_Protobuf_EndGeneratorFunction()
            case .beginAsyncFunction(let op):
                $0.beginAsyncFunction = Fuzzilli_Protobuf_BeginAsyncFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    if let name = op.functionName {
                        $0.name = name
                    }
                }
            case.endAsyncFunction:
                $0.endAsyncFunction = Fuzzilli_Protobuf_EndAsyncFunction()
            case .beginAsyncArrowFunction(let op):
                $0.beginAsyncArrowFunction = Fuzzilli_Protobuf_BeginAsyncArrowFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endAsyncArrowFunction:
                $0.endAsyncArrowFunction = Fuzzilli_Protobuf_EndAsyncArrowFunction()
            case .beginAsyncGeneratorFunction(let op):
                $0.beginAsyncGeneratorFunction = Fuzzilli_Protobuf_BeginAsyncGeneratorFunction.with {
                    $0.parameters = convertParameters(op.parameters)
                    if let name = op.functionName {
                        $0.name = name
                    }
                }
            case .endAsyncGeneratorFunction:
                $0.endAsyncGeneratorFunction = Fuzzilli_Protobuf_EndAsyncGeneratorFunction()
            case .beginConstructor(let op):
                $0.beginConstructor = Fuzzilli_Protobuf_BeginConstructor.with {
                    $0.parameters = convertParameters(op.parameters)
                }
            case .endConstructor:
                $0.endConstructor = Fuzzilli_Protobuf_EndConstructor()
            case .directive(let op):
                $0.directive = Fuzzilli_Protobuf_Directive.with { $0.content = op.content }
            case .return:
                $0.return = Fuzzilli_Protobuf_Return()
            case .yield:
                $0.yield = Fuzzilli_Protobuf_Yield()
            case .yieldEach:
                $0.yieldEach = Fuzzilli_Protobuf_YieldEach()
            case .await:
                $0.await = Fuzzilli_Protobuf_Await()
            case .callFunction(let op):
                $0.callFunction = Fuzzilli_Protobuf_CallFunction.with { $0.isGuarded = op.isGuarded }
            case .callFunctionWithSpread(let op):
                $0.callFunctionWithSpread = Fuzzilli_Protobuf_CallFunctionWithSpread.with {
                    $0.spreads = op.spreads
                    $0.isGuarded = op.isGuarded
                }
            case .construct(let op):
                $0.construct = Fuzzilli_Protobuf_Construct.with { $0.isGuarded = op.isGuarded }
            case .constructWithSpread(let op):
                $0.constructWithSpread = Fuzzilli_Protobuf_ConstructWithSpread.with {
                    $0.spreads = op.spreads
                    $0.isGuarded = op.isGuarded
                }
            case .callMethod(let op):
                $0.callMethod = Fuzzilli_Protobuf_CallMethod.with {
                    $0.methodName = op.methodName
                    $0.isGuarded = op.isGuarded
                }
            case .callMethodWithSpread(let op):
                $0.callMethodWithSpread = Fuzzilli_Protobuf_CallMethodWithSpread.with {
                    $0.methodName = op.methodName
                    $0.spreads = op.spreads
                    $0.isGuarded = op.isGuarded
                }
            case .callComputedMethod(let op):
                $0.callComputedMethod = Fuzzilli_Protobuf_CallComputedMethod.with { $0.isGuarded = op.isGuarded }
            case .callComputedMethodWithSpread(let op):
                $0.callComputedMethodWithSpread = Fuzzilli_Protobuf_CallComputedMethodWithSpread.with {
                    $0.spreads = op.spreads
                    $0.isGuarded = op.isGuarded
                }
            case .unaryOperation(let op):
                $0.unaryOperation = Fuzzilli_Protobuf_UnaryOperation.with { $0.op = convertEnum(op.op, UnaryOperator.allCases) }
            case .binaryOperation(let op):
                $0.binaryOperation = Fuzzilli_Protobuf_BinaryOperation.with { $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .ternaryOperation:
                $0.ternaryOperation = Fuzzilli_Protobuf_TernaryOperation()
            case .reassign:
                $0.reassign = Fuzzilli_Protobuf_Reassign()
            case .update(let op):
                $0.update = Fuzzilli_Protobuf_Update.with { $0.op = convertEnum(op.op, BinaryOperator.allCases) }
            case .dup:
                $0.dup = Fuzzilli_Protobuf_Dup()
            case .destructArray(let op):
                $0.destructArray = Fuzzilli_Protobuf_DestructArray.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.lastIsRest = op.lastIsRest
                }
            case .destructArrayAndReassign(let op):
                $0.destructArrayAndReassign = Fuzzilli_Protobuf_DestructArrayAndReassign.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.lastIsRest = op.lastIsRest
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
            case .createNamedVariable(let op):
                $0.createNamedVariable = Fuzzilli_Protobuf_CreateNamedVariable.with {
                    $0.variableName = op.variableName
                    $0.declarationMode = convertEnum(op.declarationMode, NamedVariableDeclarationMode.allCases)
                }
            case .eval(let op):
                $0.eval = Fuzzilli_Protobuf_Eval.with {
                    $0.code = op.code
                    $0.hasOutput_p = op.hasOutput
                }
            case .callSuperConstructor:
                $0.callSuperConstructor = Fuzzilli_Protobuf_CallSuperConstructor()
            case .callSuperMethod(let op):
                $0.callSuperMethod = Fuzzilli_Protobuf_CallSuperMethod.with { $0.methodName = op.methodName }
            case .getPrivateProperty(let op):
                $0.getPrivateProperty = Fuzzilli_Protobuf_GetPrivateProperty.with { $0.propertyName = op.propertyName }
            case .setPrivateProperty(let op):
                $0.setPrivateProperty = Fuzzilli_Protobuf_SetPrivateProperty.with { $0.propertyName = op.propertyName }
            case .updatePrivateProperty(let op):
                $0.updatePrivateProperty = Fuzzilli_Protobuf_UpdatePrivateProperty.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .callPrivateMethod(let op):
                $0.callPrivateMethod = Fuzzilli_Protobuf_CallPrivateMethod.with { $0.methodName = op.methodName }
            case .getSuperProperty(let op):
                $0.getSuperProperty = Fuzzilli_Protobuf_GetSuperProperty.with { $0.propertyName = op.propertyName }
            case .setSuperProperty(let op):
                $0.setSuperProperty = Fuzzilli_Protobuf_SetSuperProperty.with { $0.propertyName = op.propertyName }
            case .getComputedSuperProperty(_):
                $0.getComputedSuperProperty = Fuzzilli_Protobuf_GetComputedSuperProperty()
            case .setComputedSuperProperty(_):
                $0.setComputedSuperProperty = Fuzzilli_Protobuf_SetComputedSuperProperty()
            case .updateSuperProperty(let op):
                $0.updateSuperProperty = Fuzzilli_Protobuf_UpdateSuperProperty.with {
                    $0.propertyName = op.propertyName
                    $0.op = convertEnum(op.op, BinaryOperator.allCases)
                }
            case .explore(let op):
                $0.explore = Fuzzilli_Protobuf_Explore.with {
                    $0.id = op.id
                    $0.rngSeed = Int64(op.rngSeed)
                }
            case .probe(let op):
                $0.probe = Fuzzilli_Protobuf_Probe.with { $0.id = op.id }
            case .fixup(let op):
                $0.fixup = Fuzzilli_Protobuf_Fixup.with {
                    $0.id = op.id
                    $0.action = op.action
                    $0.originalOperation = op.originalOperation
                    $0.hasOutput_p = op.hasOutput
                }
            case .beginWith:
                $0.beginWith = Fuzzilli_Protobuf_BeginWith()
            case .endWith:
                $0.endWith = Fuzzilli_Protobuf_EndWith()
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
            case .beginWhileLoopHeader:
                $0.beginWhileLoopHeader = Fuzzilli_Protobuf_BeginWhileLoopHeader()
            case .beginWhileLoopBody:
                $0.beginWhileLoopBody = Fuzzilli_Protobuf_BeginWhileLoopBody()
            case .endWhileLoop:
                $0.endWhileLoop = Fuzzilli_Protobuf_EndWhileLoop()
            case .beginDoWhileLoopBody:
                $0.beginDoWhileLoopBody = Fuzzilli_Protobuf_BeginDoWhileLoopBody()
            case .beginDoWhileLoopHeader:
                $0.beginDoWhileLoopHeader = Fuzzilli_Protobuf_BeginDoWhileLoopHeader()
            case .endDoWhileLoop:
                $0.endDoWhileLoop = Fuzzilli_Protobuf_EndDoWhileLoop()
            case .beginForLoopInitializer:
                $0.beginForLoopInitializer = Fuzzilli_Protobuf_BeginForLoopInitializer()
            case .beginForLoopCondition:
                $0.beginForLoopCondition = Fuzzilli_Protobuf_BeginForLoopCondition()
            case .beginForLoopAfterthought:
                $0.beginForLoopAfterthought = Fuzzilli_Protobuf_BeginForLoopAfterthought()
            case .beginForLoopBody:
                $0.beginForLoopBody = Fuzzilli_Protobuf_BeginForLoopBody()
            case .endForLoop:
                $0.endForLoop = Fuzzilli_Protobuf_EndForLoop()
            case .beginForInLoop:
                $0.beginForInLoop = Fuzzilli_Protobuf_BeginForInLoop()
            case .endForInLoop:
                $0.endForInLoop = Fuzzilli_Protobuf_EndForInLoop()
            case .beginForOfLoop:
                $0.beginForOfLoop = Fuzzilli_Protobuf_BeginForOfLoop()
            case .beginForOfLoopWithDestruct(let op):
                $0.beginForOfLoopWithDestruct = Fuzzilli_Protobuf_BeginForOfLoopWithDestruct.with {
                    $0.indices = op.indices.map({ Int32($0) })
                    $0.hasRestElement_p = op.hasRestElement
                }
            case .endForOfLoop:
                $0.endForOfLoop = Fuzzilli_Protobuf_EndForOfLoop()
            case .beginRepeatLoop(let op):
                $0.beginRepeatLoop = Fuzzilli_Protobuf_BeginRepeatLoop.with {
                    $0.iterations = Int64(op.iterations)
                    $0.exposesLoopCounter = op.exposesLoopCounter
                }
            case .endRepeatLoop:
                $0.endRepeatLoop = Fuzzilli_Protobuf_EndRepeatLoop()
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
                $0.endTryCatchFinally = Fuzzilli_Protobuf_EndTryCatchFinally()
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
            case .loadNewTarget:
                $0.loadNewTarget = Fuzzilli_Protobuf_LoadNewTarget()
            case .beginWasmModule:
                $0.beginWasmModule = Fuzzilli_Protobuf_BeginWasmModule()
            case .endWasmModule:
                $0.endWasmModule = Fuzzilli_Protobuf_EndWasmModule()
            case .createWasmGlobal(let op):
                $0.createWasmGlobal = Fuzzilli_Protobuf_CreateWasmGlobal.with {
                    $0.wasmGlobal.isMutable = op.isMutable
                    $0.wasmGlobal.wasmGlobal = convertWasmGlobal(wasmGlobal: op.wasmGlobal)
                }
            case .createWasmTable(let op):
                $0.createWasmTable = Fuzzilli_Protobuf_CreateWasmTable.with {
                    $0.tableType = ILTypeToWasmTypeEnum(op.tableType)
                    $0.minSize = Int64(op.minSize)
                    if let maxSize = op.maxSize {
                        $0.maxSize = Int64(maxSize)
                    }
                }
            case .print(_):
                fatalError("Print operations should not be serialized")
            // Wasm Operations
            case .consti64(let op):
                $0.consti64 = Fuzzilli_Protobuf_Consti64.with { $0.value = Int64(op.value) }
            case .consti32(let op):
                $0.consti32 = Fuzzilli_Protobuf_Consti32.with { $0.value = Int32(op.value) }
            case .constf64(let op):
                $0.constf64 = Fuzzilli_Protobuf_Constf64.with { $0.value = Float(op.value) }
            case .constf32(let op):
                $0.constf32 = Fuzzilli_Protobuf_Constf32.with { $0.value = Float(op.value) }
            case .wasmReturn(let op):
                $0.wasmReturn = Fuzzilli_Protobuf_WasmReturn.with { $0.returnType = ILTypeToWasmTypeEnum(op.returnType) }
            case .wasmJsCall(let op):
                $0.wasmJsCall = Fuzzilli_Protobuf_WasmJsCall.with {
                    var plainParams: [ILType] = []
                    for param in op.functionSignature.parameters {
                        switch param {
                        case .plain(let p):
                            plainParams.append(p)
                        default:
                            fatalError("Only plain parameters are expected for WasmJsCalls")
                        }
                    }
                    $0.parameters = plainParams.map(ILTypeToWasmTypeEnum)
                    $0.returnType = ILTypeToWasmTypeEnum(op.functionSignature.outputType)
                }
            case .wasmi32CompareOp(let op):
                $0.wasmi32CompareOp = Fuzzilli_Protobuf_Wasmi32CompareOp.with { $0.compareOperator = Int32(op.compareOpKind.offset) }
            case .wasmi64CompareOp(let op):
                $0.wasmi64CompareOp = Fuzzilli_Protobuf_Wasmi64CompareOp.with { $0.compareOperator = Int32(op.compareOpKind.offset) }
            case .wasmf32CompareOp(let op):
                $0.wasmf32CompareOp = Fuzzilli_Protobuf_Wasmf32CompareOp.with { $0.compareOperator = Int32(op.compareOpKind.offset) }
            case .wasmf64CompareOp(let op):
                $0.wasmf64CompareOp = Fuzzilli_Protobuf_Wasmf64CompareOp.with { $0.compareOperator = Int32(op.compareOpKind.offset) }
            case .wasmi64BinOp(let op):
                $0.wasmi64BinOp = Fuzzilli_Protobuf_Wasmi64BinOp.with {
                    $0.op = convertEnum(op.binOperator, BinaryOperator.allCases)
                }
            case .wasmi32BinOp(let op):
                $0.wasmi32BinOp = Fuzzilli_Protobuf_Wasmi32BinOp.with {
                    $0.op = convertEnum(op.binOperator, BinaryOperator.allCases)
                }
            case .wasmReassign(let op):
                $0.wasmReassign = Fuzzilli_Protobuf_WasmReassign.with { $0.variableType = ILTypeToWasmTypeEnum(op.variableType) }
            case .wasmDefineGlobal(let op):
                $0.wasmDefineGlobal = Fuzzilli_Protobuf_WasmDefineGlobal.with {
                    $0.wasmGlobal.isMutable = op.isMutable
                    $0.wasmGlobal.wasmGlobal = convertWasmGlobal(wasmGlobal: op.wasmGlobal)
                }
            case .wasmImportGlobal(let op):
                $0.wasmImportGlobal = Fuzzilli_Protobuf_WasmImportGlobal.with {
                    $0.mutability = op.mutability
                    $0.valueType = ILTypeToWasmTypeEnum(op.valueType)
                }
            case .wasmDefineTable(let op):
                $0.wasmDefineTable = Fuzzilli_Protobuf_WasmDefineTable.with {
                    $0.tableType = ILTypeToWasmTypeEnum(op.tableType)
                    $0.minSize = Int64(op.minSize)
                    if let maxSize = op.maxSize {
                        $0.maxSize = Int64(maxSize)
                    }

                }
            case .wasmImportTable(let op):
                $0.wasmImportTable = Fuzzilli_Protobuf_WasmImportTable.with { $0.tableType = ILTypeToWasmTypeEnum(op.tableType) }
            case .wasmDefineMemory(let op):
                $0.wasmDefineMemory = Fuzzilli_Protobuf_WasmDefineMemory.with {
                    $0.minSize = Int64(op.minSize)
                    if let maxSize = op.maxSize {
                        $0.maxSize = Int64(maxSize)
                    }
                }
            case .wasmImportMemory(_):
                $0.wasmImportMemory = Fuzzilli_Protobuf_WasmImportMemory()
            case .wasmLoadGlobal(let op):
                $0.wasmLoadGlobal = Fuzzilli_Protobuf_WasmLoadGlobal.with {
                    $0.globalType = ILTypeToWasmTypeEnum(op.globalType)
                }
            case .wasmStoreGlobal(let op):
                $0.wasmStoreGlobal = Fuzzilli_Protobuf_WasmStoreGlobal.with {
                    $0.globalType = ILTypeToWasmTypeEnum(op.globalType)
                }
            case .wasmTableGet(_):
                $0.wasmTableGet = Fuzzilli_Protobuf_WasmTableGet()
            case .wasmTableSet(_):
                $0.wasmTableSet = Fuzzilli_Protobuf_WasmTableSet()
            case .wasmMemoryGet(let op):
                $0.wasmMemoryGet = Fuzzilli_Protobuf_WasmMemoryGet.with { $0.loadType = ILTypeToWasmTypeEnum(op.loadType); $0.offset = Int64(op.offset) }
            case .wasmMemorySet(let op):
                $0.wasmMemorySet = Fuzzilli_Protobuf_WasmMemorySet.with { $0.storeType = ILTypeToWasmTypeEnum(op.storeType); $0.offset = Int64(op.offset) }
            case .beginWasmFunction(let op):
                $0.beginWasmFunction = Fuzzilli_Protobuf_BeginWasmFunction.with {
                    var plainParams: [ILType] = []
                    for param in op.signature.parameters {
                        switch param {
                        case .plain(let p):
                            plainParams.append(p)
                        default:
                            fatalError("Only plain parameters are expected for wasm functions.")
                        }
                    }
                    $0.parameters = plainParams.map { ILTypeToWasmTypeEnum($0) }
                    $0.returnType = ILTypeToWasmTypeEnum(op.signature.outputType)
                }
            case .endWasmFunction(_):
                $0.endWasmFunction = Fuzzilli_Protobuf_EndWasmFunction()
            case .wasmBeginBlock(let op):
                $0.wasmBeginBlock = Fuzzilli_Protobuf_WasmBeginBlock.with {
                    var plainParams: [ILType] = []
                    for param in op.signature.parameters {
                        switch param {
                        case .plain(let p):
                            plainParams.append(p)
                        default:
                            fatalError("Only plain parameters are expected for wasm blocks")
                        }
                    }
                    $0.parameters = plainParams.map { ILTypeToWasmTypeEnum($0) }
                    $0.returnType = ILTypeToWasmTypeEnum(op.signature.outputType)
                }
            case .wasmEndBlock(_):
                $0.wasmEndBlock = Fuzzilli_Protobuf_WasmEndBlock()
            case .wasmBeginLoop(let op):
                $0.wasmBeginLoop = Fuzzilli_Protobuf_WasmBeginLoop.with {
                    var plainParams: [ILType] = []
                    for param in op.signature.parameters {
                        switch param {
                        case .plain(let p):
                            plainParams.append(p)
                        default:
                            fatalError("Only plain parameters are expexted for wasm loops")
                        }
                    }
                    $0.parameters = plainParams.map { ILTypeToWasmTypeEnum($0) }
                    $0.returnType = ILTypeToWasmTypeEnum(op.signature.outputType)
                }
            case .wasmEndLoop(_):
                $0.wasmEndLoop = Fuzzilli_Protobuf_WasmEndLoop()
            case .wasmBranch(_):
                $0.wasmBranch = Fuzzilli_Protobuf_WasmBranch()
            case .wasmBranchIf(_):
                $0.wasmBranchIf = Fuzzilli_Protobuf_WasmBranchIf()
            case .wasmBeginIf(let op):
                $0.wasmBeginIf = Fuzzilli_Protobuf_WasmBeginIf.with {
                    $0.conditionType = ILTypeToWasmTypeEnum(op.inputTypes[0])
                }
            case .wasmBeginElse(_):
                $0.wasmBeginElse = Fuzzilli_Protobuf_WasmBeginElse()
            case .wasmEndIf(_):
                $0.wasmEndIf = Fuzzilli_Protobuf_WasmEndIf()
            case .wasmNop(_):
                fatalError("Should never be serialized")
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

        // Converts to the Wasm world global type
        func WasmTypeEnumToILType(_ wasmType: Fuzzilli_Protobuf_WasmILType) -> ILType {
            switch wasmType {
            case .constf32:
                return .wasmf32
            case .constf64:
                return .wasmf64
            case .consti32:
                return .wasmi32
            case .consti64:
                return .wasmi64
            case .externref:
                return .wasmExternRef
            case .funcref:
                return .wasmFuncRef
            case .externreftable:
                return .externRefTable
            case .funcreftable:
                return .funcRefTable
            case .wasmmemory:
                return .wasmMemory
            case .nothing:
                return .nothing
            default:
                fatalError("Unrecognized wasmType enum value")
            }
        }

        // This converts to the JS world object type
        func WasmTypeEnumToJsWasmObjectType(_ wasmType: Fuzzilli_Protobuf_WasmILType) -> ILType {
            switch wasmType {
            case .constf32:
                return .object(ofGroup: "WasmGlobal.f32")
            case .constf64:
                return .object(ofGroup: "WasmGlobal.f64")
            case .consti32:
                return .object(ofGroup: "WasmGlobal.i32")
            case .consti64:
                return .object(ofGroup: "WasmGlobal.i64")
            case .externreftable:
                return .object(ofGroup: "WasmTable.externref")
            case .funcreftable:
                return .object(ofGroup: "WasmTable.funcref")
            default:
                fatalError("Unrecognized wasmType enum value")
            }
        }

        func convertWasmGlobal(_ proto: Fuzzilli_Protobuf_WasmGlobal) -> WasmGlobal {
            switch proto.wasmGlobal {
            case .nullref(_):
                return .refNull
            case .funcref(let val):
                return .refFunc(Int(val))
            case .valuei64(let val):
                return .wasmi64(val)
            case .valuei32(let val):
                return .wasmi32(val)
            case .valuef64(let val):
                return .wasmf64(val)
            case .valuef32(let val):
                return .wasmf32(val)
            case .imported(let ilType):
                return .imported(WasmTypeEnumToILType(ilType))
            case .none:
                fatalError("unreachable")
            }
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
        case .loadDisposableVariable:
            op = LoadDisposableVariable()
        case .loadAsyncDisposableVariable:
            op = LoadAsyncDisposableVariable()
        case .loadRegExp(let p):
            op = LoadRegExp(pattern: p.pattern, flags: RegExpFlags(rawValue: p.flags))
        case .beginObjectLiteral:
            op = BeginObjectLiteral()
        case .objectLiteralAddProperty(let p):
            op = ObjectLiteralAddProperty(propertyName: p.propertyName)
        case .objectLiteralAddElement(let p):
            op = ObjectLiteralAddElement(index: p.index)
        case .objectLiteralAddComputedProperty:
            op = ObjectLiteralAddComputedProperty()
        case .objectLiteralCopyProperties:
            op = ObjectLiteralCopyProperties()
        case .objectLiteralSetPrototype:
            op = ObjectLiteralSetPrototype()
        case .beginObjectLiteralMethod(let p):
            op = BeginObjectLiteralMethod(methodName: p.methodName, parameters: convertParameters(p.parameters))
        case .endObjectLiteralMethod:
            op = EndObjectLiteralMethod()
        case .beginObjectLiteralComputedMethod(let p):
            op = BeginObjectLiteralComputedMethod(parameters: convertParameters(p.parameters))
        case .endObjectLiteralComputedMethod:
            op = EndObjectLiteralComputedMethod()
        case .beginObjectLiteralGetter(let p):
            op = BeginObjectLiteralGetter(propertyName: p.propertyName)
        case .endObjectLiteralGetter:
            op = EndObjectLiteralGetter()
        case .beginObjectLiteralSetter(let p):
            op = BeginObjectLiteralSetter(propertyName: p.propertyName)
        case .endObjectLiteralSetter:
            op = EndObjectLiteralSetter()
        case .endObjectLiteral:
            op = EndObjectLiteral()
        case .beginClassDefinition(let p):
            op = BeginClassDefinition(hasSuperclass: p.hasSuperclass_p)
        case .beginClassConstructor(let p):
            op = BeginClassConstructor(parameters: convertParameters(p.parameters))
        case .endClassConstructor:
            op = EndClassConstructor()
        case .classAddInstanceProperty(let p):
            op = ClassAddInstanceProperty(propertyName: p.propertyName, hasValue: p.hasValue_p)
        case .classAddInstanceElement(let p):
            op = ClassAddInstanceElement(index: p.index, hasValue: p.hasValue_p)
        case .classAddInstanceComputedProperty(let p):
            op = ClassAddInstanceComputedProperty(hasValue: p.hasValue_p)
        case .beginClassInstanceMethod(let p):
            op = BeginClassInstanceMethod(methodName: p.methodName, parameters: convertParameters(p.parameters))
        case .endClassInstanceMethod:
            op = EndClassInstanceMethod()
        case .beginClassInstanceGetter(let p):
            op = BeginClassInstanceGetter(propertyName: p.propertyName)
        case .endClassInstanceGetter:
            op = EndClassInstanceGetter()
        case .beginClassInstanceSetter(let p):
            op = BeginClassInstanceSetter(propertyName: p.propertyName)
        case .endClassInstanceSetter:
            op = EndClassInstanceSetter()
        case .classAddStaticProperty(let p):
            op = ClassAddStaticProperty(propertyName: p.propertyName, hasValue: p.hasValue_p)
        case .classAddStaticElement(let p):
            op = ClassAddStaticElement(index: p.index, hasValue: p.hasValue_p)
        case .classAddStaticComputedProperty(let p):
            op = ClassAddStaticComputedProperty(hasValue: p.hasValue_p)
        case .beginClassStaticInitializer:
            op = BeginClassStaticInitializer()
        case .endClassStaticInitializer:
            op = EndClassStaticInitializer()
        case .beginClassStaticMethod(let p):
            op = BeginClassStaticMethod(methodName: p.methodName, parameters: convertParameters(p.parameters))
        case .endClassStaticMethod:
            op = EndClassStaticMethod()
        case .beginClassStaticGetter(let p):
            op = BeginClassStaticGetter(propertyName: p.propertyName)
        case .endClassStaticGetter:
            op = EndClassStaticGetter()
        case .beginClassStaticSetter(let p):
            op = BeginClassStaticSetter(propertyName: p.propertyName)
        case .endClassStaticSetter:
            op = EndClassStaticSetter()
        case .classAddPrivateInstanceProperty(let p):
            op = ClassAddPrivateInstanceProperty(propertyName: p.propertyName, hasValue: p.hasValue_p)
        case .beginClassPrivateInstanceMethod(let p):
            op = BeginClassPrivateInstanceMethod(methodName: p.methodName, parameters: convertParameters(p.parameters))
        case .endClassPrivateInstanceMethod:
            op = EndClassPrivateInstanceMethod()
        case .classAddPrivateStaticProperty(let p):
            op = ClassAddPrivateStaticProperty(propertyName: p.propertyName, hasValue: p.hasValue_p)
        case .beginClassPrivateStaticMethod(let p):
            op = BeginClassPrivateStaticMethod(methodName: p.methodName, parameters: convertParameters(p.parameters))
        case .endClassPrivateStaticMethod:
            op = EndClassPrivateStaticMethod()
        case .endClassDefinition:
            op = EndClassDefinition()
        case .createArray:
            op = CreateArray(numInitialValues: inouts.count - 1)
        case .createIntArray(let p):
            op = CreateIntArray(values: p.values)
        case .createFloatArray(let p):
            op = CreateFloatArray(values: p.values)
        case .createArrayWithSpread(let p):
            op = CreateArrayWithSpread(spreads: p.spreads)
        case .createTemplateString(let p):
            op = CreateTemplateString(parts: p.parts)
        case .getProperty(let p):
            op = GetProperty(propertyName: p.propertyName, isGuarded: p.isGuarded)
        case .setProperty(let p):
            op = SetProperty(propertyName: p.propertyName)
        case .updateProperty(let p):
            op = UpdateProperty(propertyName: p.propertyName, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteProperty(let p):
            op = DeleteProperty(propertyName: p.propertyName, isGuarded: p.isGuarded)
        case .configureProperty(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureProperty(propertyName: p.propertyName, flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .getElement(let p):
            op = GetElement(index: p.index, isGuarded: p.isGuarded)
        case .setElement(let p):
            op = SetElement(index: p.index)
        case .updateElement(let p):
            op = UpdateElement(index: p.index, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteElement(let p):
            op = DeleteElement(index: p.index, isGuarded: p.isGuarded)
        case .configureElement(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureElement(index: p.index, flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .getComputedProperty(let p):
            op = GetComputedProperty(isGuarded: p.isGuarded)
        case .setComputedProperty:
            op = SetComputedProperty()
        case .updateComputedProperty(let p):
            op = UpdateComputedProperty(operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .deleteComputedProperty(let p):
            op = DeleteComputedProperty(isGuarded: p.isGuarded)
        case .configureComputedProperty(let p):
            var flags = PropertyFlags()
            if p.isWritable { flags.insert(.writable) }
            if p.isConfigurable { flags.insert(.configurable) }
            if p.isEnumerable { flags.insert(.enumerable) }
            op = ConfigureComputedProperty(flags: flags, type: try convertEnum(p.type, PropertyType.allCases))
        case .typeOf:
            op = TypeOf()
        case .void:
            op = Void_()
        case .testInstanceOf:
            op = TestInstanceOf()
        case .testIn:
            op = TestIn()
        case .beginPlainFunction(let p):
            let parameters = convertParameters(p.parameters)
            let functionName = p.name.isEmpty ? nil : p.name
            op = BeginPlainFunction(parameters: parameters, functionName: functionName)
        case .endPlainFunction:
            op = EndPlainFunction()
        case .beginArrowFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginArrowFunction(parameters: parameters)
        case .endArrowFunction:
            op = EndArrowFunction()
        case .beginGeneratorFunction(let p):
            let parameters = convertParameters(p.parameters)
            let functionName = p.name.isEmpty ? nil : p.name
            op = BeginGeneratorFunction(parameters: parameters, functionName: functionName)
        case .endGeneratorFunction:
            op = EndGeneratorFunction()
        case .beginAsyncFunction(let p):
            let parameters = convertParameters(p.parameters)
            let functionName = p.name.isEmpty ? nil : p.name
            op = BeginAsyncFunction(parameters: parameters, functionName: functionName)
        case .endAsyncFunction:
            op = EndAsyncFunction()
        case .beginAsyncArrowFunction(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginAsyncArrowFunction(parameters: parameters)
        case .endAsyncArrowFunction:
            op = EndAsyncArrowFunction()
        case .beginAsyncGeneratorFunction(let p):
            let parameters = convertParameters(p.parameters)
            let functionName = p.name.isEmpty ? nil : p.name
            op = BeginAsyncGeneratorFunction(parameters: parameters, functionName: functionName)
        case .endAsyncGeneratorFunction:
            op = EndAsyncGeneratorFunction()
        case .beginConstructor(let p):
            let parameters = convertParameters(p.parameters)
            op = BeginConstructor(parameters: parameters)
        case .endConstructor:
            op = EndConstructor()
        case .directive(let p):
            op = Directive(p.content)
        case .return:
            let hasReturnValue = inouts.count == 1
            op = Return(hasReturnValue: hasReturnValue)
        case .yield:
            let hasArgument = inouts.count == 2
            op = Yield(hasArgument: hasArgument)
        case .yieldEach:
            op = YieldEach()
        case .await:
            op = Await()
        case .callFunction(let p):
            op = CallFunction(numArguments: inouts.count - 2, isGuarded: p.isGuarded)
        case .callFunctionWithSpread(let p):
            op = CallFunctionWithSpread(numArguments: inouts.count - 2, spreads: p.spreads, isGuarded: p.isGuarded)
        case .construct(let p):
            op = Construct(numArguments: inouts.count - 2, isGuarded: p.isGuarded)
        case .constructWithSpread(let p):
            op = ConstructWithSpread(numArguments: inouts.count - 2, spreads: p.spreads, isGuarded: p.isGuarded)
        case .callMethod(let p):
            op = CallMethod(methodName: p.methodName, numArguments: inouts.count - 2, isGuarded: p.isGuarded)
        case .callMethodWithSpread(let p):
            op = CallMethodWithSpread(methodName: p.methodName, numArguments: inouts.count - 2, spreads: p.spreads, isGuarded: p.isGuarded)
        case .callComputedMethod(let p):
            op = CallComputedMethod(numArguments: inouts.count - 3, isGuarded: p.isGuarded)
        case .callComputedMethodWithSpread(let p):
            op = CallComputedMethodWithSpread(numArguments: inouts.count - 3, spreads: p.spreads, isGuarded: p.isGuarded)
        case .unaryOperation(let p):
            op = UnaryOperation(try convertEnum(p.op, UnaryOperator.allCases))
        case .binaryOperation(let p):
            op = BinaryOperation(try convertEnum(p.op, BinaryOperator.allCases))
        case .ternaryOperation:
            op = TernaryOperation()
        case .update(let p):
            op = Update(try convertEnum(p.op, BinaryOperator.allCases))
        case .dup:
            op = Dup()
        case .reassign:
            op = Reassign()
        case .destructArray(let p):
            op = DestructArray(indices: p.indices.map({ Int64($0) }), lastIsRest: p.lastIsRest)
        case .destructArrayAndReassign(let p):
            op = DestructArrayAndReassign(indices: p.indices.map({ Int64($0) }), lastIsRest: p.lastIsRest)
        case .destructObject(let p):
            op = DestructObject(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .destructObjectAndReassign(let p):
            op = DestructObjectAndReassign(properties: p.properties, hasRestElement: p.hasRestElement_p)
        case .compare(let p):
            op = Compare(try convertEnum(p.op, Comparator.allCases))
        case .createNamedVariable(let p):
            op = CreateNamedVariable(p.variableName, declarationMode: try convertEnum(p.declarationMode, NamedVariableDeclarationMode.allCases))
        case .eval(let p):
            let numArguments = inouts.count - (p.hasOutput_p ? 1 : 0)
            op = Eval(p.code, numArguments: numArguments, hasOutput: p.hasOutput_p)
        case .callSuperConstructor:
            op = CallSuperConstructor(numArguments: inouts.count)
        case .callSuperMethod(let p):
            op = CallSuperMethod(methodName: p.methodName, numArguments: inouts.count - 1)
        case .getPrivateProperty(let p):
            op = GetPrivateProperty(propertyName: p.propertyName)
        case .setPrivateProperty(let p):
            op = SetPrivateProperty(propertyName: p.propertyName)
        case .updatePrivateProperty(let p):
            op = UpdatePrivateProperty(propertyName: p.propertyName, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .callPrivateMethod(let p):
            op = CallPrivateMethod(methodName: p.methodName, numArguments: inouts.count - 2)
        case .getSuperProperty(let p):
            op = GetSuperProperty(propertyName: p.propertyName)
        case .setSuperProperty(let p):
            op = SetSuperProperty(propertyName: p.propertyName)
        case .getComputedSuperProperty(_):
            op = GetComputedSuperProperty()
        case .setComputedSuperProperty(_):
            op = SetComputedSuperProperty()
        case .updateSuperProperty(let p):
            op = UpdateSuperProperty(propertyName: p.propertyName, operator: try convertEnum(p.op, BinaryOperator.allCases))
        case .explore(let p):
            op = Explore(id: p.id, numArguments: inouts.count - 1, rngSeed: UInt32(p.rngSeed))
        case .probe(let p):
            op = Probe(id: p.id)
        case .fixup(let p):
            op = Fixup(id: p.id, action: p.action, originalOperation: p.originalOperation, numArguments: inouts.count - (p.hasOutput_p ? 1 : 0), hasOutput: p.hasOutput_p)
        case .beginWith:
            op = BeginWith()
        case .endWith:
            op = EndWith()
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
        case .beginWhileLoopHeader:
            op = BeginWhileLoopHeader()
        case .beginWhileLoopBody:
            op = BeginWhileLoopBody()
        case .endWhileLoop:
            op = EndWhileLoop()
        case .beginDoWhileLoopBody:
            op = BeginDoWhileLoopBody()
        case .beginDoWhileLoopHeader:
            op = BeginDoWhileLoopHeader()
        case .endDoWhileLoop:
            op = EndDoWhileLoop()
        case .beginForLoopInitializer:
            op = BeginForLoopInitializer()
        case .beginForLoopCondition:
            assert(inouts.count % 2 == 0)
            op = BeginForLoopCondition(numLoopVariables: inouts.count / 2)
        case .beginForLoopAfterthought:
            // First input is the condition
            op = BeginForLoopAfterthought(numLoopVariables: inouts.count - 1)
        case .beginForLoopBody:
            op = BeginForLoopBody(numLoopVariables: inouts.count)
        case .endForLoop:
            op = EndForLoop()
        case .beginForInLoop:
            op = BeginForInLoop()
        case .endForInLoop:
            op = EndForInLoop()
        case .beginForOfLoop:
            op = BeginForOfLoop()
        case .beginForOfLoopWithDestruct(let p):
            op = BeginForOfLoopWithDestruct(indices: p.indices.map({ Int64($0) }), hasRestElement: p.hasRestElement_p)
        case .endForOfLoop:
            op = EndForOfLoop()
        case .beginRepeatLoop(let p):
            op = BeginRepeatLoop(iterations: Int(p.iterations), exposesLoopCounter: p.exposesLoopCounter)
        case .endRepeatLoop:
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
        case .endTryCatchFinally:
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
        case .loadNewTarget:
            op = LoadNewTarget()
        case .nop:
            op = Nop()
        case .createWasmGlobal(let p):
            op = CreateWasmGlobal(wasmGlobal: convertWasmGlobal(p.wasmGlobal), isMutable: p.wasmGlobal.isMutable)
        case .createWasmTable(let p):
            let maxSize: Int?
            if p.hasMaxSize {
                maxSize = Int(p.maxSize)
            } else {
                maxSize = nil
            }
            op = CreateWasmTable(tableType: WasmTypeEnumToILType(p.tableType), minSize: Int(p.minSize), maxSize: maxSize)
        case .print(_):
            fatalError("Should not deserialize a Print instruction!")

        // Wasm cases
        case .beginWasmModule(_):
            op = BeginWasmModule()
        case .endWasmModule(_):
            op = EndWasmModule()
        case .consti64(let p):
            op = Consti64(value: p.value)
        case .consti32(let p):
            op = Consti32(value: p.value)
        case .constf32(let p):
            op = Constf32(value: p.value)
        case .constf64(let p):
            op = Constf64(value: Float64(p.value))
        case .wasmReturn(let p):
            op = WasmReturn(returnType: WasmTypeEnumToILType(p.returnType))
        case .wasmJsCall(let p):
            let parameters: [Parameter] = p.parameters.map({ param in
                Parameter.plain(WasmTypeEnumToILType(param))
            })
            op = WasmJsCall(signature: parameters => WasmTypeEnumToILType(p.returnType))
        case .wasmi32CompareOp(let p):
            op = Wasmi32CompareOp(compareOpKind: WasmIntCompareOpKind(offset: UInt8(p.compareOperator)))
        case .wasmi64CompareOp(let p):
            op = Wasmi64CompareOp(compareOpKind: WasmIntCompareOpKind(offset: UInt8(p.compareOperator)))
        case .wasmf32CompareOp(let p):
            op = Wasmf32CompareOp(compareOpKind: WasmFloatCompareOpKind(offset: UInt8(p.compareOperator)))
        case .wasmf64CompareOp(let p):
            op = Wasmf64CompareOp(compareOpKind: WasmFloatCompareOpKind(offset: UInt8(p.compareOperator)))
        case .wasmi64BinOp(let p):
            op = Wasmi64BinOp(binOperator: try convertEnum(p.op, BinaryOperator.allCases))
        case .wasmi32BinOp(let p):
            op = Wasmi32BinOp(binOperator: try convertEnum(p.op, BinaryOperator.allCases))
        case .wasmReassign(let p):
            op = WasmReassign(variableType: WasmTypeEnumToILType(p.variableType))
        case .wasmDefineGlobal(let p):
            op = WasmDefineGlobal(wasmGlobal: convertWasmGlobal(p.wasmGlobal), isMutable: p.wasmGlobal.isMutable)
        case .wasmImportGlobal(let p):
            op = WasmImportGlobal(valueType: WasmTypeEnumToJsWasmObjectType(p.valueType), mutability: p.mutability)
        case .wasmDefineTable(let p):
            op = WasmDefineTable(tableInfo: (WasmTypeEnumToILType(p.tableType), Int(p.minSize), p.hasMaxSize ? Int(p.maxSize) : nil))
        case .wasmImportTable(let p):
            op = WasmImportTable(tableType: WasmTypeEnumToJsWasmObjectType(p.tableType))
        case .wasmDefineMemory(let p):
            op = WasmDefineMemory(memoryInfo: (Int(p.minSize), p.hasMaxSize ? Int(p.maxSize) : nil))
        case .wasmImportMemory(_):
            op = WasmImportMemory()
        case .wasmLoadGlobal(let p):
            op = WasmLoadGlobal(globalType: WasmTypeEnumToILType(p.globalType))
        case .wasmStoreGlobal(let p):
            op = WasmStoreGlobal(globalType: WasmTypeEnumToILType(p.globalType))
        case .wasmTableGet(let p):
            op = WasmTableGet(tableType: WasmTypeEnumToILType(p.tableType))
        case .wasmTableSet(let p):
            op = WasmTableSet(tableType: WasmTypeEnumToILType(p.tableType))
        case .wasmMemoryGet(let p):
            op = WasmMemoryGet(loadType: WasmTypeEnumToILType(p.loadType), offset: Int(p.offset))
        case .wasmMemorySet(let p):
            op = WasmMemorySet(storeType: WasmTypeEnumToILType(p.storeType), offset: Int(p.offset))
        case .beginWasmFunction(let p):
            op = BeginWasmFunction(parameterTypes: p.parameters.map { WasmTypeEnumToILType($0) }, returnType: WasmTypeEnumToILType(p.returnType))
        case .endWasmFunction(_):
            op = EndWasmFunction()
        case .wasmBeginBlock(_):
            fatalError("unimplemented")
        case .wasmEndBlock(_):
            op = WasmEndBlock()
        case .wasmBeginLoop(_):
            fatalError("unimplemented")
        case .wasmEndLoop(_):
            op = WasmEndLoop()
        case .wasmBranch(_):
            op = WasmBranch()
        case .wasmBranchIf(_):
            op = WasmBranchIf()
        case .wasmBeginIf(let p):
            op = WasmBeginIf(conditionType: WasmTypeEnumToILType(p.conditionType))
        case .wasmBeginElse(_):
            op = WasmBeginElse()
        case .wasmEndIf(_):
            op = WasmEndIf()
        case .wasmNop(_):
            fatalError("Should never be deserialized!")
        }

        guard op.numInputs + op.numOutputs + op.numInnerOutputs == inouts.count else {
            throw FuzzilliError.instructionDecodingError("incorrect number of in- and outputs")
        }

        opCache?.add(op)

        self.init(op, inouts: inouts, flags: .empty)
    }

    init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}
