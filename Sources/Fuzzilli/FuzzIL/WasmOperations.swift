// Copyright 2022 Google LLC
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

struct WasmConstants {
    static let specWasmMemPageSize: Int = 65536      // 64 KB
    // These are the limits defined in v8/src/wasm/wasm-limits.h which is based on https://www.w3.org/TR/wasm-js-api-2/#limits.
    // Note that the memory64 limits will be merged later on.
    // This constant limits the amount of *declared* memory. At runtime, memory can grow up to only a limit based on the architecture type.
    static let specMaxWasmMem32Pages: Int = 65536    // 4GB
    static let specMaxWasmMem64Pages: Int = 262144;  // 16GB
}

// Base class for all wasm operations.
public class WasmOperationBase : Operation {
}

// Base class for all wasm operations that use "automatic" typing based on the operation only.
// Note that this class shall be replaced by using WasmOperationBase and performing all typing of
// outputs / innerOutputs in the JSTyper directly. (This is mostly done because it is needed for
// wasm-gc operations where the result type depends on the actual instruction inputs which the
// operation does not have access to, but it also aligns wasm operations closer to JS operations
// hopefully reducing complexity.)
public class WasmTypedOperation: WasmOperationBase {
    var inputTypes: [ILType]
    // If this wasm operation does not have an output, it will have .nothing as an output type but its numOutputs will be 0.
    var outputType: ILType
    var innerOutputTypes: [ILType]

    init(inputTypes: [ILType] = [], outputType: ILType = .nothing, innerOutputTypes: [ILType] = [], firstVariadicInput: Int = -1, attributes: Attributes = [], requiredContext: Context, contextOpened: Context = .empty) {
        self.inputTypes = inputTypes
        self.outputType = outputType
        self.innerOutputTypes = innerOutputTypes
        super.init(numInputs: inputTypes.count, numOutputs: outputType == .nothing ? 0 : 1, numInnerOutputs: innerOutputTypes.count, firstVariadicInput: firstVariadicInput, attributes: attributes, requiredContext: requiredContext, contextOpened: contextOpened)
    }
}

final class Consti64: WasmOperationBase {
    override var opcode: Opcode { .consti64(self) }
    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Consti32: WasmOperationBase {
    override var opcode: Opcode { .consti32(self) }
    let value: Int32

    init(value: Int32) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Constf32: WasmOperationBase {
    override var opcode: Opcode { .constf32(self) }
    var value: Float32

    init(value: Float32) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Constf64: WasmOperationBase {
    override var opcode: Opcode { .constf64(self) }
    var value: Float64

    init(value: Float64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

//
// Control Instructions
//

final class WasmReturn: WasmOperationBase {
    override var opcode: Opcode { .wasmReturn(self) }
    let returnTypes: [ILType]

    init(returnTypes: [ILType]) {
        self.returnTypes = returnTypes
        super.init(numInputs: returnTypes.count, attributes: [.isJump], requiredContext: [.wasmFunction])
    }
}

//
// Numerical Instructions
//

//
// Integer Comparison Operations
//

public enum WasmIntegerCompareOpKind: UInt8, CaseIterable {
    case Eq   = 0
    case Ne   = 1
    case Lt_s = 2
    case Lt_u = 3
    case Gt_s = 4
    case Gt_u = 5
    case Le_s = 6
    case Le_u = 7
    case Ge_s = 8
    case Ge_u = 9
}

extension WasmIntegerCompareOpKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Eq: return "eq"
        case .Ne: return "ne"
        case .Lt_s: return "lt_s"
        case .Lt_u: return "lt_u"
        case .Gt_s: return "gt_s"
        case .Gt_u: return "gt_u"
        case .Le_s: return "le_s"
        case .Le_u: return "le_u"
        case .Ge_s: return "ge_s"
        case .Ge_u: return "ge_u"
        }
    }
}

final class Wasmi32CompareOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi32CompareOp(self) }
    let compareOpKind: WasmIntegerCompareOpKind

    init(compareOpKind: WasmIntegerCompareOpKind) {
        self.compareOpKind = compareOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmi64CompareOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi64CompareOp(self) }
    let compareOpKind: WasmIntegerCompareOpKind

    init(compareOpKind: WasmIntegerCompareOpKind) {
        self.compareOpKind = compareOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

//
// Float Comparison Operations
//

public enum WasmFloatCompareOpKind: UInt8, CaseIterable {
    case Eq = 0
    case Ne = 1
    case Lt = 2
    case Gt = 3
    case Le = 4
    case Ge = 5
}

extension WasmFloatCompareOpKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .Eq: return "eq"
        case .Ne: return "ne"
        case .Lt: return "lt"
        case .Gt: return "gt"
        case .Le: return "le"
        case .Ge: return "ge"
        }
    }
}

final class Wasmf32CompareOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf32CompareOp(self) }
    let compareOpKind: WasmFloatCompareOpKind

    init(compareOpKind: WasmFloatCompareOpKind) {
        self.compareOpKind = compareOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmf64CompareOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf64CompareOp(self) }
    let compareOpKind: WasmFloatCompareOpKind

    init(compareOpKind: WasmFloatCompareOpKind) {
        self.compareOpKind = compareOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmi32EqualZero: WasmOperationBase {
    override var opcode: Opcode { .wasmi32EqualZero(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

final class Wasmi64EqualZero: WasmOperationBase {
    override var opcode: Opcode { .wasmi64EqualZero(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

//
// Integer Unary and Binary Operations
//

public enum WasmIntegerUnaryOpKind: UInt8, CaseIterable {
    // Just like with the i32 binary operators, ordering here is imporant.
    case Clz = 0
    case Ctz = 1
    case Popcnt = 2
}

public enum WasmIntegerBinaryOpKind: UInt8, CaseIterable {
    // This ordering here is important, we just take the offset and add it to a base constant to encode the binary representation.
    // See the `lift` function in WasmLifter.swift and the case .wasmi32BinOp
    // The values for this can be found here: https://webassembly.github.io/spec/core/binary/instructions.html#numeric-instructions
    case Add = 0
    case Sub = 1
    case Mul = 2
    case Div_s = 3
    case Div_u = 4
    case Rem_s = 5
    case Rem_u = 6
    case And = 7
    case Or = 8
    case Xor = 9
    case Shl = 10
    case Shr_s = 11
    case Shr_u = 12
    case Rotl = 13
    case Rotr = 14
}

final class Wasmi32BinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi32BinOp(self) }
    let binOpKind: WasmIntegerBinaryOpKind

    init(binOpKind: WasmIntegerBinaryOpKind) {
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmi64BinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi64BinOp(self) }
    let binOpKind: WasmIntegerBinaryOpKind

    init(binOpKind: WasmIntegerBinaryOpKind) {
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmi32UnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi32UnOp(self) }
    let unOpKind: WasmIntegerUnaryOpKind

    init(unOpKind: WasmIntegerUnaryOpKind) {
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmi64UnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmi64UnOp(self) }
    let unOpKind: WasmIntegerUnaryOpKind

    init(unOpKind: WasmIntegerUnaryOpKind) {
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

//
// Float Unary and Binary Operations
//

public enum WasmFloatUnaryOpKind: UInt8, CaseIterable {
    // Just like with the i32 binary operators, ordering here is imporant.
    case Abs = 0
    case Neg = 1
    case Ceil = 2
    case Floor = 3
    case Trunc = 4
    case Nearest = 5
    case Sqrt = 6
}

public enum WasmFloatBinaryOpKind: UInt8, CaseIterable {
    // This ordering here is important, we just take the offset and add it to a base constant to encode the binary representation.
    // See the `lift` function in WasmLifter.swift and the case .wasmf32BinOp
    // The values for this can be found here: https://webassembly.github.io/spec/core/binary/instructions.html#numeric-instructions
    case Add = 0
    case Sub = 1
    case Mul = 2
    case Div = 3
    case Min = 4
    case Max = 5
    case Copysign = 6
}

final class Wasmf32BinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf32BinOp(self) }
    let binOpKind: WasmFloatBinaryOpKind

    init(binOpKind: WasmFloatBinaryOpKind) {
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmf64BinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf64BinOp(self) }
    let binOpKind: WasmFloatBinaryOpKind

    init(binOpKind: WasmFloatBinaryOpKind) {
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmf32UnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf32UnOp(self)}
    let unOpKind: WasmFloatUnaryOpKind

    init(unOpKind: WasmFloatUnaryOpKind) {
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class Wasmf64UnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmf64UnOp(self)}
    let unOpKind: WasmFloatUnaryOpKind

    init(unOpKind: WasmFloatUnaryOpKind) {
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

//
// Numerical Conversion Operations
//

final class WasmWrapi64Toi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmWrapi64Toi32(self) }

    init() {
        super.init(inputTypes: [.wasmi64], outputType: .wasmi32, requiredContext: [.wasmFunction])
    }
}

final class WasmTruncatef32Toi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncatef32Toi32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf32], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmTruncatef64Toi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncatef64Toi32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf64], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmExtendi32Toi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmExtendi32Toi64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmi32], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmTruncatef32Toi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncatef32Toi64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf32], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmTruncatef64Toi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncatef64Toi64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmConverti32Tof32: WasmTypedOperation {
    override var opcode: Opcode { .wasmConverti32Tof32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmi32], outputType: .wasmf32, requiredContext: .wasmFunction)
    }
}

final class WasmConverti64Tof32: WasmTypedOperation {
    override var opcode: Opcode { .wasmConverti64Tof32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmi64], outputType: .wasmf32, requiredContext: .wasmFunction)
    }
}

final class WasmDemotef64Tof32: WasmTypedOperation {
    override var opcode: Opcode { .wasmDemotef64Tof32(self) }

    init() {
        super.init(inputTypes: [.wasmf64], outputType: .wasmf32, requiredContext: .wasmFunction)
    }
}

final class WasmConverti32Tof64: WasmTypedOperation {
    override var opcode: Opcode { .wasmConverti32Tof64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmi32], outputType: .wasmf64, requiredContext: .wasmFunction)
    }
}

final class WasmConverti64Tof64: WasmTypedOperation {
    override var opcode: Opcode { .wasmConverti64Tof64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmi64], outputType: .wasmf64, requiredContext: .wasmFunction)
    }
}

final class WasmPromotef32Tof64: WasmTypedOperation {
    override var opcode: Opcode { .wasmPromotef32Tof64(self) }

    init() {
        super.init(inputTypes: [.wasmf32], outputType: .wasmf64, requiredContext: .wasmFunction)
    }
}

final class WasmReinterpretf32Asi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmReinterpretf32Asi32(self) }

    init() {
        super.init(inputTypes: [.wasmf32], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmReinterpretf64Asi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmReinterpretf64Asi64(self) }

    init() {
        super.init(inputTypes: [.wasmf64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmReinterpreti32Asf32: WasmTypedOperation {
    override var opcode: Opcode { .wasmReinterpreti32Asf32(self) }

    init() {
        super.init(inputTypes: [.wasmi32], outputType: .wasmf32, requiredContext: .wasmFunction)
    }
}

final class WasmReinterpreti64Asf64: WasmTypedOperation {
    override var opcode: Opcode { .wasmReinterpreti64Asf64(self) }

    init() {
        super.init(inputTypes: [.wasmi64], outputType: .wasmf64, requiredContext: .wasmFunction)
    }
}

final class WasmSignExtend8Intoi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmSignExtend8Intoi32(self) }

    init() {
        super.init(inputTypes: [.wasmi32], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmSignExtend16Intoi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmSignExtend16Intoi32(self) }

    init() {
        super.init(inputTypes: [.wasmi32], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmSignExtend8Intoi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmSignExtend8Intoi64(self) }

    init() {
        super.init(inputTypes: [.wasmi64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmSignExtend16Intoi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmSignExtend16Intoi64(self) }

    init() {
        super.init(inputTypes: [.wasmi64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmSignExtend32Intoi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmSignExtend32Intoi64(self) }

    init() {
        super.init(inputTypes: [.wasmi64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmTruncateSatf32Toi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncateSatf32Toi32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf32], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmTruncateSatf64Toi32: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncateSatf64Toi32(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf64], outputType: .wasmi32, requiredContext: .wasmFunction)
    }
}

final class WasmTruncateSatf32Toi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncateSatf32Toi64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf32], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

final class WasmTruncateSatf64Toi64: WasmTypedOperation {
    override var opcode: Opcode { .wasmTruncateSatf64Toi64(self) }

    let isSigned: Bool

    init(isSigned: Bool) {
        self.isSigned = isSigned
        super.init(inputTypes: [.wasmf64], outputType: .wasmi64, requiredContext: .wasmFunction)
    }
}

//
// Global Instructions
//

public enum WasmGlobal {
    case wasmi64(Int64)
    case wasmi32(Int32)
    case wasmf32(Float32)
    case wasmf64(Float64)
    // Empty reference
    case externref
    case exnref
    // function reference
    case refFunc(Int)

    // This is the case for imported Globals, we just need the type here.
    case imported(ILType)


    func toType() -> ILType {
        switch self {
        case .wasmi64:
            return .wasmi64
        case .wasmi32:
            return .wasmi32
        case .wasmf32:
            return .wasmf32
        case .wasmf64:
            return .wasmf64
        case .externref:
            return .wasmExternRef
        case .exnref:
            return .wasmExnRef
        case .imported(let type):
            assert(type.wasmGlobalType != nil)
            return type.wasmGlobalType!.valueType
        default:
            fatalError("Unimplemented / unhandled")
        }
    }

    func typeString() -> String {
        switch self {
        case .wasmi64(_):
            return "i64"
        case .wasmi32(_):
            return "i32"
        case .wasmf32(_):
            return "f32"
        case .wasmf64(_):
            return "f64"
        case .externref:
            return "externref"
        default:
            fatalError("Unimplemented / unhandled")
        }
    }

    func valueToString() -> String {
        switch self {
        case .wasmi64(let val):
            return "\(val)"
        case .wasmi32(let val):
            return "\(val)"
        case .wasmf32(let val):
            return "\(val)"
        case .wasmf64(let val):
            return "\(val)"
        case .externref:
            return ""
        default:
            fatalError("Unimplemented / unhandled")
        }
    }
    // Maybe add static random func?
}

final class WasmDefineGlobal: WasmTypedOperation {
    override var opcode: Opcode { .wasmDefineGlobal(self) }

    let isMutable: Bool
    let wasmGlobal: WasmGlobal

    init(wasmGlobal: WasmGlobal, isMutable: Bool) {
        self.wasmGlobal = wasmGlobal
        self.isMutable = isMutable
        let outputType = ILType.object(ofGroup: "WasmGlobal", withWasmType: WasmGlobalType(valueType: wasmGlobal.toType(), isMutable: isMutable))
        super.init(outputType: outputType, attributes: [.isMutable], requiredContext: [.wasm])
    }
}

final class WasmDefineTable: WasmTypedOperation {
    override var opcode: Opcode { .wasmDefineTable(self) }

    let elementType: ILType
    let limits: Limits
    let definedEntries: [WasmTableType.IndexInTableAndWasmSignature]
    let isTable64: Bool

    init(elementType: ILType, limits: Limits, definedEntries: [WasmTableType.IndexInTableAndWasmSignature], isTable64: Bool) {
        self.elementType = elementType
        self.limits = limits
        self.isTable64 = isTable64
        self.definedEntries = definedEntries

        // TODO(manoskouk): Find a way to define non-function tables with initializers.
        assert(elementType == .wasmFuncRef || definedEntries.isEmpty)
        let inputTypes = if elementType == .wasmFuncRef {
            Array(repeating: .wasmFunctionDef() | .function(), count: definedEntries.count)
        } else {
            [ILType]()
        }

        super.init(inputTypes: inputTypes,
                   outputType: .wasmTable(wasmTableType: WasmTableType(elementType: elementType, limits: limits, isTable64: isTable64, knownEntries: definedEntries)),
                   attributes: [.isMutable],
                   requiredContext: [.wasm])
    }
}

// TODO: Wasm memory can be initialized in the data segment, theoretically one could initialize them with this instruction as well.
// Currently they are by default zero initialized and fuzzilli should then just store or load from there.
// Also note: https://webassembly.github.io/spec/core/syntax/modules.html#memories
// There may only be one memory defined or imported at any given time and any instructions uses this memory implicitly
final class WasmDefineMemory: WasmTypedOperation {
    override var opcode: Opcode { .wasmDefineMemory(self) }

    let wasmMemory: ILType

    init(limits: Limits, isShared: Bool = false, isMemory64: Bool = false) {
        self.wasmMemory = .wasmMemory(limits: limits, isShared: isShared, isMemory64: isMemory64)
        super.init(outputType: self.wasmMemory, attributes: [.isMutable], requiredContext: [.wasm])
    }
}

final class WasmDefineTag: WasmTypedOperation {
    override var opcode: Opcode { .wasmDefineTag(self) }
    public let parameterTypes: [ILType]

    init(parameterTypes: [ILType]) {
        self.parameterTypes = parameterTypes
        // Note that tags in wasm are nominal (differently to types) meaning that two tags with the same input are not
        // the same, therefore this operation is not considered to be .pure.
        super.init(outputType: .object(ofGroup: "WasmTag", withWasmType: WasmTagType(parameterTypes)), attributes: [], requiredContext: [.wasm])
    }
}

final class WasmLoadGlobal: WasmTypedOperation {
    override var opcode: Opcode { .wasmLoadGlobal(self) }

    let globalType: ILType

    init(globalType: ILType) {
        assert(globalType.Is(.wasmPrimitive))
        self.globalType = globalType
        let inputType = ILType.object(ofGroup: "WasmGlobal")
        super.init(inputTypes: [inputType], outputType: globalType, attributes: [.isNotInputMutable], requiredContext: [.wasmFunction])
    }
}

final class WasmStoreGlobal: WasmTypedOperation {
    override var opcode: Opcode { .wasmStoreGlobal(self) }

    let globalType: ILType

    init(globalType: ILType) {
        self.globalType = globalType
        assert(globalType.Is(.wasmPrimitive))
        let inputType = ILType.object(ofGroup: "WasmGlobal", withWasmType: WasmGlobalType(valueType: globalType, isMutable: true))
        // Takes two inputs, one is the global reference the other is the value that is being stored in the global
        super.init(inputTypes: [inputType, globalType], attributes: [.isNotInputMutable], requiredContext: [.wasmFunction])
    }
}

final class WasmTableGet: WasmTypedOperation {
    override var opcode: Opcode { .wasmTableGet(self) }

    let tableType: WasmTableType

    init(tableType: ILType) {
        assert(tableType.isWasmTableType)
        self.tableType = tableType.wasmTableType!
        let elementType = self.tableType.elementType
        let offsetType = self.tableType.isTable64 ? ILType.wasmi64 : ILType.wasmi32
        super.init(inputTypes: [tableType, offsetType], outputType: elementType, requiredContext: [.wasmFunction])
    }
}

final class WasmTableSet: WasmTypedOperation {
    override var opcode: Opcode { .wasmTableSet(self) }

    let tableType: WasmTableType

    init(tableType: ILType) {
        assert(tableType.isWasmTableType)
        self.tableType = tableType.wasmTableType!
        let elementType = self.tableType.elementType
        let offsetType = self.tableType.isTable64 ? ILType.wasmi64 : ILType.wasmi32
        super.init(inputTypes: [tableType, offsetType, elementType], requiredContext: [.wasmFunction])
    }
}

final class WasmCallIndirect: WasmOperationBase {
    override var opcode: Opcode { .wasmCallIndirect(self) }
    let signature: WasmSignature

    init(signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: 2 + signature.parameterTypes.count, numOutputs: signature.outputTypes.count, requiredContext: [.wasmFunction])
    }
}

final class WasmCallDirect: WasmOperationBase {
    override var opcode: Opcode { .wasmCallDirect(self) }
    let signature: WasmSignature

    init(signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: 1 + signature.parameterTypes.count, numOutputs: signature.outputTypes.count, requiredContext: [.wasmFunction])
    }
}

// WasmMemory operations
//
// The format of memory instructions is
// (numberType).(LOAD|STORE)(storageSize)?(signedness)? (memarg) where:
//   - The numberType is i32, i64, f32 or f64;
//   - The storageSize can be optionally specified for integers to specify a bit width smaller than the respective integer numberType;
//   - The signedness is required in case of LOADs and if the storageSize is specified;
//   - The memarg is the memory immediate, consisting of {offset, align}. We refer to this offset as the staticOffset. For the align, we use 0 as default.
// The instructions expect a memory offset (index into the memory) on the stack, we refer to this as the dynamicOffset. STORE expects also a numberType value on the stack.
// As the result of the instruction, LOAD pushes a numberType value on the stack.
// TODO(evih): Support variable alignments in the memarg.

// Types of Wasm memory load instructions with the corresponding encoding as the raw value.
public enum WasmMemoryLoadType: UInt8, CaseIterable {
    case I32LoadMem = 0x28
    case I64LoadMem = 0x29
    case F32LoadMem = 0x2a
    case F64LoadMem = 0x2b
    case I32LoadMem8S = 0x2c
    case I32LoadMem8U = 0x2d
    case I32LoadMem16S = 0x2e
    case I32LoadMem16U = 0x2f
    case I64LoadMem8S = 0x30
    case I64LoadMem8U = 0x31
    case I64LoadMem16S = 0x32
    case I64LoadMem16U = 0x33
    case I64LoadMem32S = 0x34
    case I64LoadMem32U = 0x35

    func numberType() -> ILType {
        switch self {
            case .I32LoadMem,
                 .I32LoadMem8S,
                 .I32LoadMem8U,
                 .I32LoadMem16S,
                 .I32LoadMem16U:
                return .wasmi32
            case .I64LoadMem,
                 .I64LoadMem8S,
                 .I64LoadMem8U,
                 .I64LoadMem16S,
                 .I64LoadMem16U,
                 .I64LoadMem32S,
                 .I64LoadMem32U:
                return .wasmi64
            case .F32LoadMem:
                return .wasmf32
            case .F64LoadMem:
                return .wasmf64
        }
    }
}

final class WasmMemoryLoad: WasmTypedOperation {
    override var opcode: Opcode { .wasmMemoryLoad(self) }

    let loadType: WasmMemoryLoadType
    let staticOffset: Int64
    let isMemory64: Bool

    init(loadType: WasmMemoryLoadType, staticOffset: Int64, isMemory64: Bool) {
        self.loadType = loadType
        self.staticOffset = staticOffset
        self.isMemory64 = isMemory64
        let dynamicOffsetType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
        super.init(inputTypes: [.object(ofGroup: "WasmMemory"), dynamicOffsetType], outputType: loadType.numberType(), attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

// Types of Wasm memory store instructions with the corresponding encoding as the raw value.
public enum WasmMemoryStoreType: UInt8, CaseIterable {
    case I32StoreMem = 0x36
    case I64StoreMem = 0x37
    case F32StoreMem = 0x38
    case F64StoreMem = 0x39
    case I32StoreMem8 = 0x3a
    case I32StoreMem16 = 0x3b
    case I64StoreMem8 = 0x3c
    case I64StoreMem16 = 0x3d
    case I64StoreMem32 = 0x3e

    func numberType() -> ILType {
        switch self {
            case .I32StoreMem,
                 .I32StoreMem8,
                 .I32StoreMem16:
                return .wasmi32
            case .I64StoreMem,
                 .I64StoreMem8,
                 .I64StoreMem16,
                 .I64StoreMem32:
                return .wasmi64
            case .F32StoreMem:
                return .wasmf32
            case .F64StoreMem:
                return .wasmf64
        }
    }
}

final class WasmMemoryStore: WasmTypedOperation {
    override var opcode: Opcode { .wasmMemoryStore(self) }

    let storeType: WasmMemoryStoreType
    let staticOffset: Int64
    let isMemory64: Bool

    init(storeType: WasmMemoryStoreType, staticOffset: Int64, isMemory64: Bool) {
        self.storeType = storeType
        self.staticOffset = staticOffset
        self.isMemory64 = isMemory64
        let dynamicOffsetType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
        super.init(inputTypes: [.object(ofGroup: "WasmMemory"), dynamicOffsetType, storeType.numberType()], attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

final class WasmJsCall: WasmTypedOperation {
    override var opcode: Opcode { .wasmJsCall(self) }

    let functionSignature: WasmSignature

    init(signature: WasmSignature) {
        self.functionSignature = signature
        assert(signature.outputTypes.count < 2, "multi-return js calls are not supported")
        let outputType: ILType = signature.outputTypes.isEmpty ? .nothing : signature.outputTypes[0]
        super.init(inputTypes: [.function() | .object(ofGroup: "WebAssembly.SuspendableObject")] + signature.parameterTypes, outputType: outputType, requiredContext: [.wasmFunction])
    }
}

final class WasmSelect: WasmOperationBase {
    override var opcode: Opcode { .wasmSelect(self) }

    init() {
        // Note that the condition is the third input. This is due to the lifting that pushes all
        // inputs to the value stack in reverse order (and the select expects the condition as the
        // first value on the stack.)
        super.init(numInputs: 3, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

final class WasmBeginBlock: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginBlock(self) }

    let signature: WasmSignature

    init(with signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: signature.parameterTypes.count, numInnerOutputs: signature.parameterTypes.count + 1, attributes: [.isBlockStart, .propagatesSurroundingContext], requiredContext: [.wasmFunction], contextOpened: [.wasmBlock])
    }
}

final class WasmEndBlock: WasmOperationBase {
    override var opcode: Opcode { .wasmEndBlock(self) }

    let outputTypes: [ILType]

    init(outputTypes: [ILType]) {
        self.outputTypes = outputTypes
        super.init(numInputs: outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd, .resumesSurroundingContext], requiredContext: [.wasmFunction, .wasmBlock])
    }
}

final class WasmBeginIf: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginIf(self) }
    let signature: WasmSignature
    let inverted: Bool

    init(with signature: WasmSignature = [] => [], inverted: Bool = false) {
        self.signature = signature
        self.inverted = inverted
        // TODO(mliedtke): Why does this set .isNotInputMutable? Try to remove it and see if the WasmLifter failure rate is affected.

        // Note that the condition is the last input! This is due to how lifting works for the wasm
        // value stack and that the condition is the first value to be removed from the stack, so
        // it needs to be the last one pushed to it.
        // Inner outputs: 1 label (used for branch instructions) plus all the parameters.
        super.init(numInputs: signature.parameterTypes.count + 1, numInnerOutputs: 1 + signature.parameterTypes.count, attributes: [.isBlockStart, .propagatesSurroundingContext, .isNotInputMutable], requiredContext: [.wasmFunction], contextOpened: [.wasmBlock])
    }
}

final class WasmBeginElse: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginElse(self) }
    let signature: WasmSignature

    init(with signature: WasmSignature = [] => []) {
        self.signature = signature
        // The WasmBeginElse acts both as a block end for the true case and as a block start for the
        // false case. As such, its input types are the results from the true block and its inner
        // output types are the same as for the corresponding WasmBeginIf.
        super.init(numInputs: signature.outputTypes.count, numInnerOutputs: 1 + signature.parameterTypes.count, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], requiredContext: [.wasmFunction], contextOpened: [.wasmBlock])
    }
}

final class WasmEndIf: WasmOperationBase {
    override var opcode: Opcode { .wasmEndIf(self) }
    let outputTypes: [ILType]

    init(outputTypes: [ILType] = []) {
        self.outputTypes = outputTypes
        super.init(numInputs: outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd], requiredContext: [.wasmBlock, .wasmFunction])
    }
}

final class WasmBeginLoop: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginLoop(self) }
    let signature: WasmSignature

    init(with signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: signature.parameterTypes.count, numInnerOutputs: 1 + signature.parameterTypes.count, attributes: [.isBlockStart, .propagatesSurroundingContext], requiredContext: [.wasmFunction])
    }
}

final class WasmEndLoop: WasmOperationBase {
    override var opcode: Opcode { .wasmEndLoop(self) }
    let outputTypes: [ILType]

    init(outputTypes: [ILType] = []) {
        self.outputTypes = outputTypes
        super.init(numInputs: outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd, .resumesSurroundingContext], requiredContext: [.wasmFunction])
    }
}

// A try_table is a mix between a `br_table` (just with target blocks associated with different tags)
// and the legacy `try` block.
final class WasmBeginTryTable: WasmOperationBase {
    enum CatchKind : UInt8 {
        case NoRef = 0x0
        case Ref = 0x1
        case AllNoRef = 0x2
        case AllRef = 0x3
    }

    override var opcode: Opcode { .wasmBeginTryTable(self) }
    let signature: WasmSignature
    let catches: [CatchKind]

    init(with signature: WasmSignature, catches: [CatchKind]) {
        self.signature = signature
        self.catches = catches
        let inputTagCount = catches.count {$0 == .Ref || $0 == .NoRef}
        let inputLabelCount = catches.count
        super.init(numInputs: signature.parameterTypes.count + inputLabelCount + inputTagCount , numInnerOutputs: signature.parameterTypes.count + 1, attributes: [.isBlockStart, .propagatesSurroundingContext], requiredContext: [.wasmFunction], contextOpened: [.wasmBlock])
    }
}

final class WasmEndTryTable: WasmOperationBase {
    override var opcode: Opcode { .wasmEndTryTable(self) }
    let outputTypes: [ILType]

    init(outputTypes: [ILType]) {
        self.outputTypes = outputTypes
        super.init(numInputs: outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd, .resumesSurroundingContext], requiredContext: [.wasmFunction, .wasmBlock])
    }
}

final class WasmBeginTry: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginTry(self) }
    let signature: WasmSignature

    init(with signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: signature.parameterTypes.count, numInnerOutputs: signature.parameterTypes.count + 1, attributes: [.isBlockStart, .propagatesSurroundingContext], requiredContext: [.wasmFunction], contextOpened: [.wasmBlock])
    }
}

final class WasmBeginCatchAll : WasmOperationBase {
    override var opcode: Opcode { .wasmBeginCatchAll(self) }
    let inputTypes: [ILType]

    init(inputTypes: [ILType]) {
        self.inputTypes = inputTypes

        super.init(
            numInputs: inputTypes.count,
            numInnerOutputs: 1, // the label
            attributes: [
                .isBlockEnd,
                .isBlockStart,
                .propagatesSurroundingContext,
                // Wasm only allows a single catch_all per try block.
                .isSingular
            ],
            requiredContext: [.wasmFunction])
    }
}

final class WasmBeginCatch : WasmOperationBase {
    override var opcode: Opcode { .wasmBeginCatch(self) }
    let signature: WasmSignature

    init(with signature: WasmSignature) {
        self.signature = signature
        // TODO: In an ideal world, the catch would only have one label that is used both for
        // branching as well as for rethrowing the exception. However, rethrows may only use labels
        // from catch blocks and branches may use any label but need to be very precise on the type
        // of the label parameters, so typing the label would require different subtyping based on
        // the usage. For now, we just emit a label for branching and the ".exceptionLabel" for
        // rethrows.
        super.init(
            numInputs: 1 + signature.outputTypes.count,
            // Inner outputs are the branch label, the exception label and the tag parameters.
            numInnerOutputs: 2 + signature.parameterTypes.count,
            attributes: [
                .isBlockEnd,
                .isBlockStart,
                .propagatesSurroundingContext,
            ],
            requiredContext: [.wasmFunction])
    }
}

final class WasmEndTry: WasmOperationBase {
    override var opcode: Opcode { .wasmEndTry(self) }
    let outputTypes: [ILType]

    init(outputTypes: [ILType] = []) {
        self.outputTypes = outputTypes
        super.init(numInputs: outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd], requiredContext: [.wasmFunction])
    }
}

/// A special try block that does not have any catch / catch_all handlers but ends with a delegate to handle the exception.
final class WasmBeginTryDelegate: WasmOperationBase {
    override var opcode: Opcode { .wasmBeginTryDelegate(self) }
    let signature: WasmSignature

    init(with signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: signature.parameterTypes.count, numInnerOutputs: 1 + signature.parameterTypes.count, attributes: [.isBlockStart, .propagatesSurroundingContext], requiredContext: [.wasmFunction], contextOpened: [])
    }
}

/// Delegates any exception thrown inside WasmBeginTryDelegate and this end to another block defined by the label.
/// This can be a "proper" try block (in which case its catch blocks apply) or any other block like a loop or an if.
final class WasmEndTryDelegate: WasmOperationBase {
    override var opcode: Opcode { .wasmEndTryDelegate(self) }
    let outputTypes: [ILType]

    init(outputTypes: [ILType] = []) {
        self.outputTypes = outputTypes
        // Inputs: 1 label to delegate an exception to plus all the outputs of the try block.
        super.init(numInputs: 1 + outputTypes.count, numOutputs: outputTypes.count, attributes: [.isBlockEnd, .resumesSurroundingContext], requiredContext: [.wasmFunction])
    }
}

final class WasmThrow: WasmOperationBase {
    override var opcode: Opcode { .wasmThrow(self) }
    public let parameterTypes: [ILType]

    init(parameterTypes: [ILType]) {
        self.parameterTypes = parameterTypes
        // Inputs: the tag to be thrown plus the arguments for each parameter type of the tag.
        super.init(numInputs: 1 + parameterTypes.count, attributes: [.isJump], requiredContext: [.wasmFunction])
    }
}

final class WasmThrowRef: WasmOperationBase {
    override var opcode: Opcode { .wasmThrowRef(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isJump], requiredContext: [.wasmFunction])
    }
}

// The rethrow instruction of the legacy exception-handling proposal. This operation is replaced
// with the throw_ref instruction in the updated proposal.
final class WasmRethrow: WasmTypedOperation {
    override var opcode: Opcode { .wasmRethrow(self) }

    init() {
        super.init(inputTypes: [.exceptionLabel], attributes: [.isJump], requiredContext: [.wasmFunction])
    }
}

final class WasmBranch: WasmTypedOperation {
    override var opcode: Opcode { .wasmBranch(self) }
    let labelTypes: [ILType]

    init(labelTypes: [ILType]) {
        self.labelTypes = labelTypes
        super.init(inputTypes: [.label(self.labelTypes)] + labelTypes, requiredContext: [.wasmFunction])

    }
}

final class WasmBranchIf: WasmTypedOperation {
    override var opcode: Opcode { .wasmBranchIf(self) }
    let labelTypes: [ILType]

    init(labelTypes: [ILType]) {
        self.labelTypes = labelTypes
        super.init(inputTypes: [.label(self.labelTypes)] + labelTypes + [.wasmi32], requiredContext: [.wasmFunction])
    }
}

final class WasmBranchTable: WasmTypedOperation {
    override var opcode: Opcode { .wasmBranchTable(self) }
    let labelTypes: [ILType]
    // The number of cases in the br_table. Note that the number of labels is one higher as each
    // br_table has a default label.
    let valueCount: Int

    init(labelTypes: [ILType], valueCount: Int) {
        self.labelTypes = labelTypes
        self.valueCount = valueCount
        super.init(inputTypes: (0...valueCount).map {_ in .label(labelTypes)} + labelTypes + [.wasmi32], requiredContext: [.wasmFunction])
    }
}

// TODO: make this comprehensive, currently only works for locals, or assumes every thing it reassigns to is a local.
// This should be doable in the lifter, where we can see what we reassign to.
final class WasmReassign: WasmTypedOperation {
    override var opcode: Opcode { .wasmReassign(self) }

    let variableType: ILType

    init(variableType: ILType) {
        self.variableType = variableType
        super.init(inputTypes: [variableType, variableType], attributes: [.isNotInputMutable], requiredContext: [.wasmFunction])
    }
}

//
// Fuzzilli Wasm Instructions.
// These are internal, such that we have more information in the IL for mutation.
// They should all require at least .wasm.
//

final class BeginWasmFunction: WasmOperationBase {
    override var opcode: Opcode { .beginWasmFunction(self) }
    public let signature: WasmSignature

    init(signature: WasmSignature) {
        self.signature = signature
        super.init(numInnerOutputs: 1 + signature.parameterTypes.count, attributes: [.isBlockStart], requiredContext: [.wasm], contextOpened: [.wasmFunction])
    }
}

final class EndWasmFunction: WasmOperationBase {
    override var opcode: Opcode { .endWasmFunction(self) }
    let signature: WasmSignature

    init(signature: WasmSignature) {
        self.signature = signature
        super.init(numInputs: signature.outputTypes.count, numOutputs: 1, attributes: [.isBlockEnd], requiredContext: [.wasmFunction])
    }
}

/// This class is used to indicate nops in the wasm world, this makes handling of minimization much easier.
final class WasmNop: WasmTypedOperation {
    override var opcode: Opcode { .wasmNop(self) }
    init(outputType: ILType, innerOutputTypes: [ILType]) {
        super.init(outputType: outputType, innerOutputTypes: innerOutputTypes, attributes: [.isInternal, .isNop], requiredContext: [.wasmFunction])
    }
}

final class WasmUnreachable: WasmTypedOperation {
    override var opcode: Opcode { .wasmUnreachable(self) }
    init() {
        super.init(outputType: .nothing, attributes: [], requiredContext: [.wasmFunction])
    }
}

final class ConstSimd128: WasmOperationBase {
    override var opcode: Opcode { .constSimd128(self) }
    let value: [UInt8]

    init(value: [UInt8]) {
        self.value = value;
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

// This array must be kept in sync with the Comparator Enum in operations.proto
public enum WasmSimd128CompareOpKind {
    case iKind(value: WasmIntegerCompareOpKind)
    case fKind(value: WasmFloatCompareOpKind)

    func toInt() -> Int {
        switch self {
        case .iKind(let value):
            return Int(value.rawValue)
        case .fKind(let value):
            return Int(value.rawValue)
        }
    }
}

extension WasmSimd128CompareOpKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .iKind(let value):
            return "\(value)"
        case .fKind(let value):
            return "\(value)"
        }
    }
}

public enum WasmSimd128Shape: UInt8, CaseIterable {
    case i8x16              = 0
    case i16x8              = 1
    case i32x4              = 2
    case i64x2              = 3
    case f32x4              = 4
    case f64x2              = 5

    func isFloat() -> Bool {
        switch self {
            case .i8x16,
                 .i16x8,
                 .i32x4,
                 .i64x2:
                return false
            case .f32x4,
                 .f64x2:
                return true
        }
    }
}

final class WasmSimd128Compare: WasmOperationBase {
    override var opcode: Opcode { .wasmSimd128Compare(self) }
    let shape: WasmSimd128Shape
    let compareOpKind: WasmSimd128CompareOpKind

    init(shape: WasmSimd128Shape, compareOpKind: WasmSimd128CompareOpKind) {
        self.shape = shape
        self.compareOpKind = compareOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

public enum WasmSimd128IntegerUnOpKind: Int, CaseIterable {
    // The offsets are added to a base value for each shape:
    // i8x16: 0x5C + offset
    // i16x8: 0x7C + offset
    // i32x4: 0x9C + offset
    // i64x2: 0xBC + offset
    case extadd_pairwise_i8x16_s = 0
    case extadd_pairwise_i8x16_u = 1
    case extadd_pairwise_i16x8_s = -30
    case extadd_pairwise_i16x8_u = -29
    case abs                     = 4
    case neg                     = 5
    case popcnt                  = 6
    case all_true                = 7
    case bitmask                 = 8
    case extend_low_s            = 11
    case extend_high_s           = 12
    case extend_low_u            = 13
    case extend_high_u           = 14

    func isValidForShape(shape: WasmSimd128Shape) -> Bool {
        if shape.isFloat() { return false }
        switch self {
        case .extadd_pairwise_i8x16_s:  return shape == .i16x8
        case .extadd_pairwise_i8x16_u:  return shape == .i16x8
        case .extadd_pairwise_i16x8_s:  return shape == .i32x4
        case .extadd_pairwise_i16x8_u:  return shape == .i32x4
        case .abs:                      return true
        case .neg:                      return true
        case .popcnt:                   return shape == .i8x16
        case .all_true:                 return true
        case .bitmask:                  return true
        case .extend_low_s:             return shape != .i8x16
        case .extend_high_s:            return shape != .i8x16
        case .extend_low_u:             return shape != .i8x16
        case .extend_high_u:            return shape != .i8x16
        }
    }
}

final class WasmSimd128IntegerUnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmSimd128IntegerUnOp(self) }
    let shape: WasmSimd128Shape
    let unOpKind: WasmSimd128IntegerUnOpKind

    init(shape: WasmSimd128Shape, unOpKind: WasmSimd128IntegerUnOpKind) {
        assert(unOpKind.isValidForShape(shape: shape))
        self.shape = shape
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

public enum WasmSimd128IntegerBinOpKind: Int, CaseIterable {
    // The offsets are added to a base value for each shape:
    // i8x16: 0x5C + offset
    // i16x8: 0x7C + offset
    // i32x4: 0x9C + offset
    // i64x2: 0xBC + offset
    case q15mulr_sat_s = 6
    case narrow_s      = 9
    case narrow_u      = 10

    case shl           = 15
    case shr_s         = 16
    case shr_u         = 17
    case add           = 18
    case add_sat_s     = 19
    case add_sat_u     = 20
    case sub           = 21
    case sub_sat_s     = 22
    case sub_sat_u     = 23

    case mul           = 25
    case min_s         = 26
    case min_u         = 27
    case max_s         = 28
    case max_u         = 29
    case dot_i16x8_s   = 30
    case avgr_u        = 31
    case extmul_low_s  = 32
    case extmul_high_s = 33
    case extmul_low_u  = 34
    case extmul_high_u = 35

    func isValidForShape(shape: WasmSimd128Shape) -> Bool {
        if shape.isFloat() { return false }
        switch self {
        case .q15mulr_sat_s: return shape == .i16x8
        case .narrow_s:      return shape == .i8x16 || shape == .i16x8
        case .narrow_u:      return shape == .i8x16 || shape == .i16x8
        case .shl:           return true
        case .shr_s:         return true
        case .shr_u:         return true
        case .add:           return true
        case .add_sat_s:     return shape == .i8x16 || shape == .i16x8
        case .add_sat_u:     return shape == .i8x16 || shape == .i16x8
        case .sub:           return true
        case .sub_sat_s:     return shape == .i8x16 || shape == .i16x8
        case .sub_sat_u:     return shape == .i8x16 || shape == .i16x8
        case .mul:           return shape != .i8x16
        case .min_s:         return shape != .i64x2
        case .min_u:         return shape != .i64x2
        case .max_s:         return shape != .i64x2
        case .max_u:         return shape != .i64x2
        case .dot_i16x8_s:   return shape == .i32x4
        case .avgr_u:        return shape == .i8x16 || shape == .i16x8
        case .extmul_low_s:  return shape != .i8x16
        case .extmul_high_s: return shape != .i8x16
        case .extmul_low_u:  return shape != .i8x16
        case .extmul_high_u: return shape != .i8x16
        }
    }
}

final class WasmSimd128IntegerBinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmSimd128IntegerBinOp(self) }
    let shape: WasmSimd128Shape
    let binOpKind: WasmSimd128IntegerBinOpKind

    init(shape: WasmSimd128Shape, binOpKind: WasmSimd128IntegerBinOpKind) {
        assert(binOpKind.isValidForShape(shape: shape))
        self.shape = shape
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

public enum WasmSimd128FloatUnOpKind: Int, CaseIterable {
    case ceil
    case floor
    case trunc
    case nearest
    case abs
    case neg
    case sqrt

    func isValidForShape(shape: WasmSimd128Shape) -> Bool {
        return shape.isFloat()
    }
}

final class WasmSimd128FloatUnOp: WasmOperationBase {
    override var opcode: Opcode { .wasmSimd128FloatUnOp(self) }
    let shape: WasmSimd128Shape
    let unOpKind: WasmSimd128FloatUnOpKind

    init(shape: WasmSimd128Shape, unOpKind: WasmSimd128FloatUnOpKind) {
        assert(unOpKind.isValidForShape(shape: shape))
        self.shape = shape
        self.unOpKind = unOpKind
        super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

public enum WasmSimd128FloatBinOpKind: Int, CaseIterable {
    // The offsets are added to a base value for each shape:
    // f32x4: 0xE4 + offset
    // f64x2: 0xF0 + offset
    case add = 0
    case sub = 1
    case mul = 2
    case div = 3
    case min = 4
    case max = 5
    case pmin = 6
    case pmax = 7

    func isValidForShape(shape: WasmSimd128Shape) -> Bool {
        return shape.isFloat()
    }
}

final class WasmSimd128FloatBinOp: WasmOperationBase {
    override var opcode: Opcode { .wasmSimd128FloatBinOp(self) }
    let shape: WasmSimd128Shape
    let binOpKind: WasmSimd128FloatBinOpKind

    init(shape: WasmSimd128Shape, binOpKind: WasmSimd128FloatBinOpKind) {
        assert(binOpKind.isValidForShape(shape: shape))
        self.shape = shape
        self.binOpKind = binOpKind
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

// TODO: Generalize to other shapes.
final class WasmI64x2Splat: WasmOperationBase {
    override var opcode: Opcode { .wasmI64x2Splat(self) }
    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.wasmFunction])
    }
}

// TODO: Generalize to other shapes.
final class WasmI64x2ExtractLane: WasmOperationBase {
  override var opcode: Opcode { .wasmI64x2ExtractLane(self) }
  let lane: Int

  init(lane: Int) {
    self.lane = lane;
    super.init(numInputs: 1, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
  }
}

final class WasmSimdLoad: WasmOperationBase {
    enum Kind: UInt8, CaseIterable {
        // TODO(mliedtke): Test all the other variants!
        case LoadS128    = 0x00
        case Load8x8S    = 0x01
        case Load8x8U    = 0x02
        case Load16x4S   = 0x03
        case Load16x4U   = 0x04
        case Load32x2S   = 0x05
        case Load32x2U   = 0x06
        case Load8Splat  = 0x07
        case Load16Splat = 0x08
        case Load32Splat = 0x09
        case Load64Splat = 0x0A
    }

    override var opcode: Opcode { .wasmSimdLoad(self) }

    let kind: Kind
    let staticOffset: Int64
    let isMemory64: Bool

    init(kind: Kind, staticOffset: Int64, isMemory64: Bool) {
        self.kind = kind
        self.staticOffset = staticOffset
        self.isMemory64 = isMemory64
        super.init(numInputs: 2, numOutputs: 1, attributes: [.isMutable], requiredContext: [.wasmFunction])
    }
}

class WasmArrayNewFixed: WasmOperationBase {
    override var opcode: Opcode { .wasmArrayNewFixed(self) }

    let size: Int

    init(size: Int) {
        self.size = size
        // TODO(mliedtke): Mark this operation variadic and extend
        // OperationMutator::extendVariadicOperationByOneInput and ensure correct types of added
        // inputs. (This requires some integration for .wasmRef(Index) to ensure it isn't just an
        // index type but a matching one!)
        super.init(numInputs: size + 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmArrayNewDefault: WasmOperationBase {
    override var opcode: Opcode { .wasmArrayNewDefault(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmArrayLen: WasmOperationBase {
    override var opcode: Opcode { .wasmArrayLen(self) }

    init() {
        // TODO(mliedtke): Once we have struct types, we'll need to adapt these input types to
        // be limited to array types (similar in other operations like array.get and operations
        // expecting an array type definiiton like array.new_fixed.)
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmArrayGet: WasmOperationBase {
    override var opcode: Opcode { .wasmArrayGet(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmArraySet: WasmOperationBase {
    override var opcode: Opcode { .wasmArraySet(self) }

    init() {
        super.init(numInputs: 3, numOutputs: 0, requiredContext: [.wasmFunction])
    }
}

class WasmStructNewDefault: WasmOperationBase {
    override var opcode: Opcode { .wasmStructNewDefault(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmStructGet: WasmOperationBase {
    override var opcode: Opcode { .wasmStructGet(self) }
    let fieldIndex: Int

    init(fieldIndex: Int) {
        self.fieldIndex = fieldIndex
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmStructSet: WasmOperationBase {
    override var opcode: Opcode { .wasmStructSet(self) }
    let fieldIndex: Int

    init(fieldIndex: Int) {
        self.fieldIndex = fieldIndex
        super.init(numInputs: 2, numOutputs: 0, requiredContext: [.wasmFunction])
    }
}

class WasmRefNull: WasmOperationBase {
    override var opcode: Opcode { .wasmRefNull(self) }

    let type: ILType?  // Only present if this operation has no input.

    init(type: ILType?) {
        self.type = type
        assert(type == nil || type!.requiredInputCount() == 0)
        super.init(numInputs: type == nil ? 1 : 0, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}

class WasmRefIsNull: WasmOperationBase {
    override var opcode: Opcode { .wasmRefIsNull(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.wasmFunction])
    }
}
