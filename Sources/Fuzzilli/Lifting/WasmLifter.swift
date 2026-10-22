// Copyright 2023 Google LLC
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
import OrderedCollections

/// Represents the type identifiers for each code section according to the wasm
/// spec.
private enum WasmSection: UInt8 {
    case custom = 0
    case type = 1
    case `import`
    case function
    case table
    case memory
    case global
    case export
    case start
    case element
    case code
    case data
    case datacount
    case tag
}

private enum Prefix: UInt8 {
    case GC = 0xFB
    case Numeric = 0xFC
    case Simd = 0xFD
    case Atomic = 0xFE
}

// This maps ILTypes to their respective binary encoding.
private let ILTypeMapping: [ILType: Data] = [
    .wasmi32: Data([0x7F]),
    .wasmi64: Data([0x7E]),
    .wasmf32: Data([0x7D]),
    .wasmf64: Data([0x7C]),
    .wasmSimd128: Data([0x7B]),
    .wasmPackedI8: Data([0x78]),
    .wasmPackedI16: Data([0x77]),

    .bigint: Data([0x7E]),  // Maps to .wasmi64
    .jsAnything: Data([0x6F]),  // Maps to .wasmExternRef
    .integer: Data([0x7F]),  // Maps to .wasmi32
    .number: Data([0x7D]),  // Maps to .wasmf32
]

extension WasmModuleInterface.Kind {
    /// The byte that encodes the kind of an imported or exported object in the binary format.
    fileprivate var externalKindByte: Int {
        switch self {
        case .function: return 0x0
        case .table: return 0x1
        case .memory: return 0x2
        case .global: return 0x3
        case .tag: return 0x4
        }
    }
}

/// This is the main compiler for Wasm instructions.
/// This lifter collects all wasm instructions during lifting
/// (The JavaScriptLifter passes them to this instance) and then it compiles them
/// at the end of the block when we see a EndWasmModule instruction.
/// This way the WasmLifter has full information before it actually emits any bytes.
public class WasmLifter {
    /// This enum describes various failure cases that might arise from mutation
    /// in the JS part of the sample, which can invalidate some of the Wasm code.
    public enum CompileError: Error {
        // If we invalidated some import from JavaScript, see `buildImportSection`.
        case unknownImportType
        // If we fail to lookup the index in one of the sections, see `resolveIdx`.
        case failedIndexLookUp
        // If the signature is not found, see `getSignatureIdx`.
        case failedSignatureLookUp
        // If the branch target is invalid.
        case invalidBranch
        // If type information is not available where we need it.
        case missingTypeInformation
        // If we fail to find a variable during import linking
        case failedRetrieval
        // This means likely some input has been reassigned in JS, which means it is not of the expected type in Wasm, this is similar to the unknownImportType
        case invalidInput
        // Any kind of error that should result in a fatal error instead of gracefully catching it.
        // (Use this over fatalError() to get better error reporting about the crashing program.
        case fatalError(String)
    }

    /// A function, table, memory, global or tag that the module defines.
    enum Definition {
        case function(FunctionInfo)
        case table(Instruction)
        case memory(Instruction)
        case global(Instruction)
        case tag(Instruction)

        var kind: WasmModuleInterface.Kind {
            switch self {
            case .function(_): .function
            case .table(_): .table
            case .memory(_): .memory
            case .global(_): .global
            case .tag(_): .tag
            }
        }

        func getDefInstr() -> Instruction? {
            switch self {
            case .function(_):
                return nil
            case .global(let instr),
                .table(let instr),
                .memory(let instr),
                .tag(let instr):
                return instr
            }
        }
    }

    private var logger = Logger(withLabel: "WasmLifter")

    // The actual bytecode we compile.
    private var bytecode: Data = Data()

    // The level of verboseness
    private var verbose: Bool = false

    // The string that is given to the script writer
    private var out: String = ""

    // This typer holds information from the "outside" JS world.
    // It is created during lifting of JavaScript and the JavaScriptLifter passes it into the WasmLifter.
    private var typer: JSTyper

    // This contains the instructions that we need to lift.
    private var instructionBuffer: Code = Code(isBundle: false)

    // This tracks the functions, tables, memories, globals and tags that the module defines. The
    // imports aren't part of this, they are tracked by the `moduleInterface`.
    // This is used to build the sections of the defined objects. The order of the definitions of a
    // kind determines their indices in the module, see `resolveIdx`.
    private var definitions: [Definition] = []

    private var dataSegments: [Instruction] = []
    private var elementSegments: [Instruction] = []

    //    // The tags associated with this module.
    //    private var tags: VariableMap<[ILType]> = VariableMap()

    private var typeGroups: Set<Int> = []

    private var typeDescToIndex: [WasmTypeDescription: Int] = [:]
    private var userDefinedTypesCount = 0

    private struct JSStringBuiltin: Equatable, Hashable {
        let field: String
        let signature: WasmSignature
        var index: Int?

        static func == (lhs: JSStringBuiltin, rhs: JSStringBuiltin) -> Bool {
            return lhs.field == rhs.field && lhs.signature == rhs.signature
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(field)
            hasher.combine(signature)
        }
    }
    private var jsStringBuiltins = OrderedSet<JSStringBuiltin>()

    private func createJSStringBuiltinInfo(forInstr instr: Instruction) -> JSStringBuiltin {
        switch instr.op.opcode {
        case .wasmJSStringLength:
            return JSStringBuiltin(
                field: "length", signature: [.wasmJSStringRef()] => [.wasmi32], index: nil)
        case .wasmJSStringFromCharCodeArray:
            let arrayDesc = typer.getTypeDescription(of: instr.input(0))
            let signatureArrayType = ILType.wasmIndexRef(arrayDesc, nullability: true)
            return JSStringBuiltin(
                field: "fromCharCodeArray",
                signature: [signatureArrayType, .wasmi32, .wasmi32] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringFromCharCode:
            return JSStringBuiltin(
                field: "fromCharCode",
                signature: [.wasmi32] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringFromCodePoint:
            return JSStringBuiltin(
                field: "fromCodePoint",
                signature: [.wasmi32] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringCharCodeAt:
            return JSStringBuiltin(
                field: "charCodeAt",
                signature: [.wasmJSStringRef(), .wasmi32] => [.wasmi32],
                index: nil)
        case .wasmJSStringCodePointAt:
            return JSStringBuiltin(
                field: "codePointAt",
                signature: [.wasmJSStringRef(), .wasmi32] => [.wasmi32],
                index: nil)
        case .wasmJSStringIntoCharCodeArray:
            let arrayDesc = typer.getTypeDescription(of: instr.input(1))
            let signatureArrayType = ILType.wasmIndexRef(arrayDesc, nullability: true)
            return JSStringBuiltin(
                field: "intoCharCodeArray",
                signature: [.wasmJSStringRef(), signatureArrayType, .wasmi32] => [.wasmi32],
                index: nil)
        case .wasmJSStringCast:
            return JSStringBuiltin(
                field: "cast",
                signature: [.wasmExternRef()] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringTest:
            return JSStringBuiltin(
                field: "test",
                signature: [.wasmExternRef()] => [.wasmi32],
                index: nil)
        case .wasmJSStringConcat:
            return JSStringBuiltin(
                field: "concat",
                signature: [.wasmJSStringRef(), .wasmJSStringRef()] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringSubstring:
            return JSStringBuiltin(
                field: "substring",
                signature: [.wasmJSStringRef(), .wasmi32, .wasmi32] => [.wasmRefJSString()],
                index: nil)
        case .wasmJSStringEquals:
            return JSStringBuiltin(
                field: "equals",
                signature: [.wasmJSStringRef(), .wasmJSStringRef()] => [.wasmi32],
                index: nil)
        case .wasmJSStringCompare:
            return JSStringBuiltin(
                field: "compare",
                signature: [.wasmJSStringRef(), .wasmJSStringRef()] => [.wasmi32],
                index: nil)
        default:
            fatalError("Unsupported JS string builtin: \(instr.op.opcode)")
        }
    }

    private func trackJSStringBuiltinUsage(forInstr instr: Instruction) {
        let info = createJSStringBuiltinInfo(forInstr: instr)
        jsStringBuiltins.append(info)
    }

    private func getJSStringBuiltin(forInstr instr: Instruction) -> JSStringBuiltin {
        let info = createJSStringBuiltinInfo(forInstr: instr)
        return jsStringBuiltins.first { $0 == info }!
    }

    // The signature index space.
    private var signatures: [WasmSignature] = []
    private var signatureIndexMap: [WasmSignature: Int] = [:]

    // This tracks in which order we have seen globals, this can probably be unified with the .globals and .imports properties, as they should match in their keys.
    private var globalOrder: [Variable] = []
    private var tagOrder: [Variable] = []

    private let startFunction: Variable?

    // The imports and exports of the module as recorded by the typer.
    private let moduleInterface: WasmModuleInterface

    public init(
        withTyper typer: JSTyper, withWasmCode instrs: Code,
        moduleInterface: WasmModuleInterface, startFunction: Variable? = nil
    ) {
        self.typer = typer
        self.instructionBuffer = instrs
        self.moduleInterface = moduleInterface
        self.startFunction = startFunction
    }

    private class WasmExprWriter {
        // This maps variables to its bytecode.
        // If we see an instruction we can just push it onto here, and if we actually see the variable as an input, we can then
        // Emit a load.
        // This either contains the rawByte code to construct the output, i.e. const.i64
        // Or it contains a load to a local variable if the instr has multiple inputs.
        private var varMap: VariableMap<Data> = VariableMap()
        // Tracks variables that we have emitted at least once.
        private var emittedVariables: Set<Variable> = []

        func addExpr(for variable: Variable, bytecode: Data) {
            self.varMap[variable] = bytecode
        }

        func getExpr(for variable: Variable) -> Data? {
            let expr = self.varMap[variable]
            emittedVariables.insert(variable)
            return expr
        }

        public var isEmpty: Bool {
            return varMap.isEmpty
        }
    }

    private var writer = WasmExprWriter()

    var isEmpty: Bool {
        return instructionBuffer.isEmpty && self.bytecode.isEmpty && self.definitions.isEmpty
    }

    // TODO: maybe we can do some analysis based on blocks.
    // Get the type index or something or infer the value type that it tries to return? With BlockInfo class or something like that?

    private func updateVariableAnalysis(forInstruction wasmInstruction: Instruction) {
        // Only analyze an instruction if we are inside a function definition.
        if let currentFunction = currentFunction {
            currentFunction.variableAnalyzer.analyze(wasmInstruction)
        }
    }

    // Holds various information for the functions in a wasm module.
    class FunctionInfo {
        var signature: WasmSignature
        var signatureDef: Variable
        var code: Data
        var branchHints: [(hint: WasmBranchHint, offset: Int)] = []
        var outputVariable: Variable? = nil
        // Locals that we spill to, this maps from the ordering to the stack.
        var localsInfo: [(Variable, ILType)]
        var variableAnalyzer = VariableAnalyzer()
        weak var lifter: WasmLifter?

        // Tracks the labels and the branch depth they've been emitted at. This is needed to calculate how far "out" we have to branch to
        // Whenever we start something that emits a label, we need to track the branch depth here.
        // This should be local to a function
        public var labelBranchDepthMapping: VariableMap<Int> = VariableMap()

        // Expects the withArguments array to contain the variables of the innerOutputs, they should map directly to the local indices.
        init(
            _ signature: WasmSignature, signatureDef: Variable, _ code: Data,
            for lifter: WasmLifter,
            withArguments arguments: [Variable]
        ) {
            // Infer the first few locals from this signature.
            self.signature = signature
            self.signatureDef = signatureDef
            self.code = code
            self.localsInfo = [(Variable, ILType)]()
            self.lifter = lifter
            assert(signature.parameterTypes.count + 1 == arguments.count)
            // Populate the localsInfo with the parameter types.
            for (idx, argVar) in arguments.dropFirst().enumerated() {
                self.localsInfo.append((argVar, signature.parameterTypes[idx]))
                // Emit the expressions for the parameters such that we can accesss them if we need them.
                self.lifter!.writer.addExpr(
                    for: argVar,
                    bytecode: Data([0x20]) + Leb128.unsignedEncode(self.localsInfo.count - 1))
            }
        }

        func appendToCode(_ code: Data) {
            self.code += code
        }

        // This collects the variables that we spill.
        func spillLocal(forVariable variable: Variable) {
            self.localsInfo.append((variable, lifter!.typer.type(of: variable)))
            assert(lifter!.typer.type(of: variable).Is(.wasmPrimitive))
            // Do a local.set on the stack slot
            self.code += Data([0x21]) + Leb128.unsignedEncode(localsInfo.count - 1)
        }

        func isLocal(_ variable: Variable) -> Bool {
            self.localsInfo.contains(where: { $0.0 == variable })
        }

        func getStackSlot(for variable: Variable) -> Int? {
            return self.localsInfo.firstIndex(where: { $0.0 == variable })
        }

        // This loads a variable from the stack. This is designed for arguments of functions
        func addStackLoad(for variable: Variable) {
            // We expect to do this for innerOutputs.
            assert(isLocal(variable) && getStackSlot(for: variable) != nil)
            // This emits a local.get for the function argument.
            self.code += Data([0x20]) + Leb128.unsignedEncode(getStackSlot(for: variable)!)
        }

        func addBranchHint(_ hint: WasmBranchHint) {
            if hint != .None {
                self.branchHints.append((hint: hint, offset: self.code.count))
            }
        }
    }

    private var currentFunction: FunctionInfo? = nil
    public private(set) var importedStringConstants: [String] = []

    public func lift(binaryOutPath path: String? = nil) throws -> (
        bytecode: Data, importRefs: [Variable], didUseJSStringBuiltins: Bool,
        didImportStringConstants: Bool
    ) {
        // Lifting currently happens in three stages.
        // 1. Collect all necessary information to build all sections later on.
        //    - For now this only the importAnalysis, which needs to know how many imported vs internally defined types exist.
        // 2. Lift each instruction within its local context using all information needed from the previous analysis inside of a given function
        // 3. Use the already lifted functions to emit the whole Wasm byte buffer.

        // Step 1:
        // Collect the definitions, type groups, string constants and JS string builtins of the module.
        try importAnalysis()
        // Todo: maybe add a def-use pass here to figure out where we need stack spills etc? e.g. if we have one use, we can omit the stack spill

        //
        // Step 1 Done
        //

        //
        // Step 2:
        //
        // Lift each instruction individually into a byte buffer. This happens sequentially, you better have all the information you will need here.

        // Collect function/type/signature information.
        for instr in self.instructionBuffer {
            let needsByteEmission = updateLifterState(wasmInstruction: instr)

            // TODO: Check if we are in a .wasmFunction context and if so, update variableAnalysis.
            updateVariableAnalysis(forInstruction: instr)

            if needsByteEmission {
                // If we require inputs for this instruction, we probably need to emit them now, either inline the corresponding instruction, iff this is a single use, or load the stack slot or the variable. TODO: not all of this is implemented.
                emitInputLoadsIfNecessary(forInstruction: instr)
                // Emit the actual bytes that correspond to this instruction to the corresponding function byte array.
                try emitBytesForInstruction(forInstruction: instr)
                // If this instruction produces any outputs, we might need to explicitly spill to the stack.
                emitStackSpillsIfNecessary(forInstruction: instr)
            }
        }

        //
        // Step 2 Done
        // All functions should have associated byte code at this point.
        //

        //
        // Step 3: Lift the whole module and put everything together.
        //

        if verbose {
            print("Got the following functions")
            for case .function(let functionInfo) in self.definitions {
                print("\(String(describing: functionInfo))")
            }
        }

        // Build the header section which includes the Wasm version first
        self.buildHeader()

        try self.buildTypeSection()
        try self.buildImportSection()
        try self.buildFunctionSection()
        try self.buildTableSection()
        self.buildMemorySection()
        try self.buildTagSection()
        try self.buildGlobalSection()

        // Export all imports and definitions by default.
        try self.buildExportedSection()

        // Build element segments for defined tables.
        try self.buildStartSection()
        try self.buildElementSection()

        try self.buildDataCountSection()

        // The actual bytecode of the functions.
        try self.buildCodeSection()

        try self.buildDataSection()

        // Write the bytecode as file to the given path for debugging purposes.
        if let path = path {
            let url = URL(fileURLWithPath: path)
            try? bytecode.write(to: url)
        }

        //
        // Step 3 done
        //

        let didUseJSStringBuiltins = !jsStringBuiltins.isEmpty
        let didImportStringConstants = !importedStringConstants.isEmpty

        return (
            bytecode, moduleInterface.imports.map { $0.variable }, didUseJSStringBuiltins,
            didImportStringConstants
        )
    }

    private func buildHeader() {
        // Build the magic and the version of wasm we compile to.
        self.bytecode += [0x0]
        self.bytecode += "asm".data(using: .ascii)!

        // LE encoded 1 as the wasm version.
        self.bytecode += [0x1, 0x0, 0x0, 0x0]
    }

    private func encodeAbstractHeapType(_ heapTypeInfo: HeapTypeInfo) -> Data {
        // Base of v8 implementation. See
        // https://source.chromium.org/chromium/chromium/src/+/main:v8/src/wasm/wasm-constants.h?q=symbol:ValueTypeCode
        let sharedFlagPrefix: [UInt8] = heapTypeInfo.shared ? [0x65] : []
        let opCode: UInt8 =
            switch heapTypeInfo.heapType {
            case .WasmExtern: 0x6F
            // WasmJSString is a wrapper around WasmExtern that we use to keep track
            // of JS strings in Fuzzilli. It is not a specified type.
            case .WasmJSString: 0x6F
            case .WasmFunc: 0x70
            case .WasmAny: 0x6E
            case .WasmEq: 0x6D
            case .WasmI31: 0x6C
            case .WasmStruct: 0x6B
            case .WasmArray: 0x6A
            case .WasmExn: 0x69
            case .WasmNone: 0x71
            case .WasmNoExtern: 0x72
            case .WasmNoFunc: 0x73
            case .WasmNoExn: 0x74
            }
        return Data(sharedFlagPrefix + [opCode])
    }

    private func encodeWasmGCType(_ description: WasmTypeDescription?) throws -> Data {
        guard let description else {
            throw WasmLifter.CompileError.missingTypeInformation
        }
        return Leb128.signedEncode(typeDescToIndex[description]!)
    }

    private func encodeType(_ type: ILType, defaultType: ILType? = nil) throws -> Data {
        if let refType = type.wasmReferenceType {
            let isNullable = refType.nullability
            let nullabilityByte: UInt8 = isNullable ? 0x63 : 0x64

            return try Data([nullabilityByte]) + encodeHeapType(refType.kind)
        }
        // HINT: If you crash here, you might not have specified an encoding for your new type in `ILTypeMapping`.
        return ILTypeMapping[type] ?? ILTypeMapping[defaultType!]!
    }

    private func encodeHeapType(_ refKind: WasmReferenceType.Kind) throws -> Data {
        switch refKind {
        case .Index(let description, let isExact):
            let typeIndexData = try encodeWasmGCType(description.get())
            return isExact ? Data([0x62]) + typeIndexData : typeIndexData
        case .Abstract(let heapTypeInfo):
            return encodeAbstractHeapType(heapTypeInfo)
        }
    }

    // Convienience method to avoid casting to wasmReferenceType on callers side.
    private func encodeHeapType(_ type: ILType) throws -> Data {
        if let refType = type.wasmReferenceType {
            return try encodeHeapType(refType.kind)
        }
        fatalError("This function supports only wasmReferenceType.")
    }

    // Helper method in cases we have either abstract type represented by ILType or an index type Variable
    private func encodeReferenceType(
        _ refType: WasmReferenceType, instr: Instruction, typeInput: Int
    ) throws -> Data {
        switch refType.kind {
        case .Abstract(let heapTypeInfo):
            return encodeAbstractHeapType(heapTypeInfo)
        case .Index(_, let isExact):
            let encodedTypeIndex = try encodeWasmGCType(
                typer.getTypeDescription(of: instr.input(typeInput)))
            return isExact ? Data([0x62]) + encodedTypeIndex : encodedTypeIndex
        }
    }

    private func encodeDescriptorReferenceType(
        _ refType: WasmReferenceType, instr: Instruction, descriptorInput: Int
    ) throws -> Data {
        let descriptorDesc =
            typer.getTypeDescription(of: instr.input(descriptorInput)) as! WasmStructTypeDescription
        let targetDesc = descriptorDesc.describes!
        let encodedTypeIndex = try encodeWasmGCType(targetDesc)
        return refType.kind.isExact ? Data([0x62]) + encodedTypeIndex : encodedTypeIndex
    }

    private func buildTypeEntry(for desc: WasmTypeDescription, data: inout Data) throws {
        if let supertype = desc.concreteHeapSupertype {
            data += [desc.isFinal ? 0x4F : 0x50, 0x01]
            data += try encodeWasmGCType(supertype)
        } else if desc is WasmArrayTypeDescription || desc is WasmStructTypeDescription
            || (desc as? WasmSignatureTypeDescription)?.isAdHoc == false
        {
            data += [desc.isFinal ? 0x4F : 0x50, 0x00]
        }
        if let arrayDesc = desc as? WasmArrayTypeDescription {
            data += [0x5E]
            data += try encodeType(arrayDesc.elementType)
            data += [arrayDesc.mutability ? 1 : 0]
        } else if let structDesc = desc as? WasmStructTypeDescription {
            if let describes = structDesc.describes {
                data += [0x4C]
                data += try encodeWasmGCType(describes)
            }
            if let descriptor = structDesc.descriptor {
                data += [0x4D]
                data += try encodeWasmGCType(descriptor)
            }
            data += [0x5F]
            data += Leb128.unsignedEncode(structDesc.fields.count)
            for field in structDesc.fields {
                data += try encodeType(field.type)
                data += [field.mutability ? 1 : 0]
            }
        } else if let signatureDesc = desc as? WasmSignatureTypeDescription {
            data += [0x60]
            data += Leb128.unsignedEncode(signatureDesc.signature.parameterTypes.count)
            for parameterType in signatureDesc.signature.parameterTypes {
                data += try encodeType(parameterType)
            }
            data += Leb128.unsignedEncode(signatureDesc.signature.outputTypes.count)
            for outputType in signatureDesc.signature.outputTypes {
                data += try encodeType(outputType)
            }
        } else {
            fatalError("Unsupported WasmTypeDescription!")
        }
    }

    private func buildTypeSection() throws {
        // Collect all signatures of imported functions, suspendable objects or tags.
        // TODO(mliedtke): Every usage should use `signatureDef` instead of `signature` to use consistent indices for signatures.
        for imp in moduleInterface.imports {
            if case .wasmSignature(let signature) = imp.functionSignature {
                registerSignature(signature)
            } else if imp.kind == .tag {
                registerSignature(typer.type(of: imp.variable).wasmTagType!.parameters => [])
            }
        }

        for builtin in jsStringBuiltins {
            registerSignature(builtin.signature)
        }

        let typeCount = self.signatures.count + typeGroups.count
        if typeCount == 0 {
            return
        }

        self.bytecode += [WasmSection.type.rawValue]
        var temp = Leb128.unsignedEncode(typeCount)

        // TODO(mliedtke): Integrate this with the whole signature mechanism as
        // these signatures could contain wasm-gc types.
        for typeGroupIndex in typeGroups.sorted() {
            let typeGroup = typer.getTypeGroup(typeGroupIndex)
            temp += [0x4E]
            temp += Leb128.unsignedEncode(typeGroup.count)
            for typeDef in typeGroup {
                try buildTypeEntry(for: typer.getTypeDescription(of: typeDef), data: &temp)
            }
        }

        for signature in self.signatures {
            temp += [0x60]
            temp += Leb128.unsignedEncode(signature.parameterTypes.count)
            for paramType in signature.parameterTypes {
                temp += try encodeType(paramType)
            }
            temp += Leb128.unsignedEncode(signature.outputTypes.count)
            for outputType in signature.outputTypes {
                temp += try encodeType(outputType, defaultType: .wasmExternRef())
            }
        }

        if verbose {
            print("Type section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }

        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)
    }

    private func registerSignature(_ signature: WasmSignature) {
        if signatureIndexMap[signature] != nil {
            return
        }

        let signatureIndex = userDefinedTypesCount + signatures.count
        signatures.append(signature)
        signatureIndexMap[signature] = signatureIndex
    }

    private func getSignatureIndex(_ signature: WasmSignature) throws -> Int {
        if let idx = signatureIndexMap[signature] {
            return idx
        }

        throw WasmLifter.CompileError.failedSignatureLookUp
    }

    private func getSignatureIndexStrict(_ signature: WasmSignature) -> Int {
        return signatureIndexMap[signature]!
    }

    private func buildImportSection() throws {
        let importsCount = moduleInterface.imports.count
        let staticImportsCount = jsStringBuiltins.count
        let stringConstantsCount = importedStringConstants.count

        if importsCount + staticImportsCount + stringConstantsCount == 0 {
            return
        }

        self.bytecode += [WasmSection.import.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(importsCount + staticImportsCount + stringConstantsCount)

        // Build the import components of this vector that consist of mod:name, nm:name, and d:importdesc
        for (idx, imp) in moduleInterface.imports.enumerated() {
            if verbose {
                print(imp.variable)
            }
            // Append the name as a vector
            temp += Leb128.unsignedEncode("imports".utf8.count)
            temp += "imports".data(using: .utf8)!
            let importName = "import_\(idx)_\(imp.variable)"
            temp += Leb128.unsignedEncode(importName.utf8.count)
            temp += importName.data(using: .utf8)!
            temp += Leb128.unsignedEncode(imp.kind.externalKindByte)
            let type = typer.type(of: imp.variable)
            switch imp.kind {
            case .function:
                switch imp.functionSignature! {
                case .signatureDef(let signatureDef):
                    let signatureDesc = typer.getTypeDescription(of: signatureDef)
                    temp += Leb128.unsignedEncode(typeDescToIndex[signatureDesc]!)
                case .wasmSignature(let signature):
                    temp += Leb128.unsignedEncode(try getSignatureIndex(signature))
                }
            case .memory:
                let mem = type.wasmMemoryType!
                let limits_byte: UInt8 =
                    (mem.isMemory64 ? 4 : 0) | (mem.isShared ? 2 : 0)
                    | (mem.limits.max != nil ? 1 : 0)
                temp += Data([limits_byte])

                temp += Data(Leb128.unsignedEncode(mem.limits.min))
                if let maxPages = mem.limits.max {
                    temp += Data(Leb128.unsignedEncode(maxPages))
                }
            case .table:
                let table = type.wasmTableType!
                temp += try encodeType(table.elementType)

                let limits_byte: UInt8 =
                    (table.isTable64 ? 4 : 0) | (table.limits.max != nil ? 1 : 0)
                temp += Data([limits_byte])

                temp += Data(Leb128.unsignedEncode(table.limits.min))
                if let maxSize = table.limits.max {
                    temp += Data(Leb128.unsignedEncode(maxSize))
                }
            case .global:
                let valueType = type.wasmGlobalType!.valueType
                let mutability = type.wasmGlobalType!.isMutable
                temp += try encodeType(valueType)
                temp += mutability ? [0x1] : [0x0]
            case .tag:
                let signature = type.wasmTagType!.parameters => []
                temp += [0x0] + Leb128.unsignedEncode(try getSignatureIndex(signature))
            }
        }

        for i in 0..<jsStringBuiltins.count {
            let moduleName = "wasm:js-string"
            let fieldName = jsStringBuiltins[i].field
            temp += Leb128.unsignedEncode(moduleName.utf8.count)
            temp += moduleName.data(using: .utf8)!
            temp += Leb128.unsignedEncode(fieldName.utf8.count)
            temp += fieldName.data(using: .utf8)!

            let sigIdx = getSignatureIndexStrict(jsStringBuiltins[i].signature)
            temp += [0x0] + Leb128.unsignedEncode(sigIdx)
        }

        for stringConstant in importedStringConstants {
            let moduleName = "\""
            temp += Leb128.unsignedEncode(moduleName.utf8.count)
            temp += moduleName.data(using: .utf8)!
            temp += Leb128.unsignedEncode(stringConstant.utf8.count)
            temp += stringConstant.data(using: .utf8)!

            temp += [0x3]  // global import
            temp += try encodeType(.wasmRefJSString())  // value type
            temp += [0x0]  // immutable
        }

        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("import section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildFunctionSection() throws {
        let functionCount = self.definitions.count { $0.kind == .function }
        if functionCount == 0 {
            return
        }

        self.bytecode += [WasmSection.function.rawValue]

        // The number of functions we have, as this is a vector of type idxs.
        // TODO(cffsmith): functions can share type indices. This could be an optimization later on.
        var temp = Leb128.unsignedEncode(functionCount)

        for case .function(let functionInfo) in self.definitions {
            let typeDesc = typer.getTypeDescription(of: functionInfo.signatureDef)
            temp.append(Leb128.unsignedEncode(typeDescToIndex[typeDesc]!))
        }

        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("function section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildTableSection() throws {
        let tableCount = self.definitions.count { $0.kind == .table }
        if tableCount == 0 {
            return
        }

        self.bytecode += [WasmSection.table.rawValue]

        var temp = Leb128.unsignedEncode(tableCount)

        for case .table(let instruction) in self.definitions {
            let op = instruction.op as! WasmDefineTable
            let elementType = op.elementType
            let minSize = op.limits.min
            let maxSize = op.limits.max
            let isTable64 = op.isTable64
            temp += try encodeType(elementType)

            let limits_byte: UInt8 = (isTable64 ? 4 : 0) | (maxSize != nil ? 1 : 0)
            temp += Data([limits_byte])

            temp += Data(Leb128.unsignedEncode(minSize))
            if let maxSize {
                temp += Data(Leb128.unsignedEncode(maxSize))
            }
        }
        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("table section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildStartSection() throws {
        guard let startFunction = self.startFunction else { return }

        self.bytecode += [WasmSection.start.rawValue]
        var temp = Data()

        let startIdx = try resolveIdx(ofType: .function, for: startFunction)
        temp += Leb128.unsignedEncode(startIdx)

        self.bytecode += Leb128.unsignedEncode(temp.count)
        self.bytecode += temp
    }

    // Only supports:
    // - passive & active segments
    // - with custom table id
    // - function-indices-as-elements (i.e. case 1 && 2 of the spec: https://webassembly.github.io/spec/core/binary/modules.html#element-section)
    // - one segment per table (assumes entries are continuous)
    // - constant starting index.
    private func buildElementSection() throws {
        let numDefinedTablesWithEntries = self.definitions.count {
            if case .table(let instruction) = $0 {
                return (instruction.op as! WasmDefineTable).initializedSlotCount != 0
            } else {
                return false
            }
        }

        if numDefinedTablesWithEntries == 0 && elementSegments.count == 0 { return }

        self.bytecode += [WasmSection.element.rawValue]
        var temp = Data()

        // Element segment count.
        temp += Leb128.unsignedEncode(numDefinedTablesWithEntries + elementSegments.count)

        // Passive element segments. They go first so that their indexes start with 0.
        for instruction in self.elementSegments {
            let size = (instruction.op as! WasmDefineElementSegment).size
            assert(size == instruction.numInputs)
            // Element segment case 1 definition.
            temp += [0x01]
            // elemkind
            temp += [0x00]
            // Elements
            temp += Leb128.unsignedEncode(instruction.numInputs)
            for f in instruction.inputs {
                let functionIdx = try resolveIdx(ofType: .function, for: f)
                temp += Leb128.unsignedEncode(functionIdx)
            }
        }

        // Active element segments
        for case .table(let instruction) in self.definitions {
            let table = instruction.op as! WasmDefineTable
            if table.initializedSlotCount == 0 { continue }
            // Element segment case 2 definition.
            temp += [0x02]
            let tableIndex = try self.resolveIdx(ofType: .table, for: instruction.output)
            temp += Leb128.unsignedEncode(tableIndex)
            // Starting index. Assumes all entries are continuous and start at zero.
            temp += table.isTable64 ? [0x42] : [0x41]
            temp += Leb128.unsignedEncode(0)
            temp += [0x0B]  // end
            // elemkind
            temp += [0x00]
            // entry count
            temp += Leb128.unsignedEncode(table.initializedSlotCount)
            // entries
            var i = 0
            assert(instruction.inputs.count % 2 == 0)
            while i < instruction.inputs.count {
                let fct = instruction.input(i)
                let functionIdx = try resolveIdx(
                    ofType: .function, for: fct,
                    functionSignature: .signatureDef(instruction.input(i + 1)))
                temp += Leb128.unsignedEncode(functionIdx)
                i += 2
            }
        }

        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("element section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildCodeSection() throws {
        let functionCount = self.definitions.count { $0.kind == .function }
        if functionCount == 0 {
            return
        }

        // Build the contents of the section
        var temp = Leb128.unsignedEncode(functionCount)

        var functionBranchHints = [Data]()

        let functions = self.definitions.filter({ $0.kind == .function })

        let importedFunctionCount =
            moduleInterface.imports.count { $0.kind == .function } + jsStringBuiltins.count

        for (defIndex, definition) in functions.enumerated() {
            guard case .function(let functionInfo) = definition else {
                fatalError("unreachable")
            }

            if verbose {
                print("code is:")
                for byte in functionInfo.code {
                    print(String(format: "%02X", byte))
                }
                print("end of code")
            }

            var funcTemp = Data()
            // TODO: this should be encapsulated more nicely. There should be an interface that gets the locals without the parameters. As this is currently mainly used to get the slots info.
            // Encode number of locals
            funcTemp += Leb128.unsignedEncode(
                functionInfo.localsInfo.count - functionInfo.signature.parameterTypes.count)
            for (_, type) in functionInfo.localsInfo[
                functionInfo.signature.parameterTypes.count...]
            {
                // Encode the locals
                funcTemp += Leb128.unsignedEncode(1)
                funcTemp += try encodeType(type)
            }
            let localsDefSizeInBytes = funcTemp.count
            // append the actual code and the end marker
            funcTemp += functionInfo.code
            funcTemp += [0x0B]

            // Append the function object to the section
            temp += Leb128.unsignedEncode(funcTemp.count)
            temp += funcTemp

            // Encode the branch hint section entry for this function.
            if !functionInfo.branchHints.isEmpty {
                // The function entry is the function index, followed by the counts of branch hints
                // for this function and then the bytes containing the actual branch hints.
                let functionIndex = defIndex + importedFunctionCount
                let hintsEncoded =
                    Leb128.unsignedEncode(functionIndex)
                    + Leb128.unsignedEncode(functionInfo.branchHints.count)
                    + functionInfo.branchHints.map {
                        // Each branch hint is the instruction offset starting from the locals
                        // definitions of the functions, a 0x01 byte, followed by the hint byte.
                        Leb128.unsignedEncode(localsDefSizeInBytes + $0.offset) + [0x01]
                            + [$0.hint == .Likely ? 1 : 0]
                    }.joined()
                functionBranchHints.append(hintsEncoded)
            }
        }

        // The branch hint section has to appear before the code section.
        if !functionBranchHints.isEmpty {
            self.bytecode += [WasmSection.custom.rawValue]
            let name = "metadata.code.branch_hint"
            let sectionContent =
                Leb128.unsignedEncode(name.utf8.count) + Data(name.data(using: .ascii)!)
                + Leb128.unsignedEncode(functionBranchHints.count) + functionBranchHints.joined()
            self.bytecode.append(Leb128.unsignedEncode(sectionContent.count))
            self.bytecode.append(sectionContent)
        }

        self.bytecode += [WasmSection.code.rawValue]
        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("Code section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildDataSection() throws {
        if self.dataSegments.isEmpty {
            return
        }

        self.bytecode += [WasmSection.data.rawValue]

        var temp = Data()
        temp += Leb128.unsignedEncode(self.dataSegments.count)

        for instruction in self.dataSegments {
            let segment = (instruction.op as! WasmDefineDataSegment).segment
            temp += Data([0x01])  // mode = passive
            temp += Leb128.unsignedEncode(segment.count)
            temp += Data(segment)
        }

        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("data section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildDataCountSection() throws {
        if self.dataSegments.isEmpty {
            return
        }

        self.bytecode += [WasmSection.datacount.rawValue]
        let temp = Leb128.unsignedEncode(self.dataSegments.count)
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("data count section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildGlobalSection() throws {
        let globalCount = self.definitions.count { $0.kind == .global }
        if globalCount == 0 {
            return
        }

        self.bytecode += [WasmSection.global.rawValue]
        var temp = Leb128.unsignedEncode(globalCount)

        // TODO: in the future this should maybe be a context that allows instructions? Such that we can fuzz this expression as well?
        for case .global(let instruction) in self.definitions {
            if let definition = instruction.op as? WasmDefineGlobal {
                let isExact: Bool? =
                    switch definition.wasmGlobal {
                    case .indexExactRef: true
                    case .indexRef: false
                    default: nil
                    }

                if let isExact = isExact {
                    let typeVar = instruction.input(0)
                    let typeDesc = typer.getTypeDescription(of: typeVar)
                    let typeIndexData = try encodeWasmGCType(typeDesc)
                    let exactByte = isExact ? Data([0x62]) : Data()

                    // Type: (ref null [exact] $typeIndex). 0x63 is nullable ref, 0x62 is exact
                    temp += Data([0x63]) + exactByte + typeIndexData
                    temp += Data([definition.isMutable ? 0x1 : 0x0])

                    // Init expr: ref.null [exact] $typeIndex, then end (0x0B)
                    temp += Data([0xD0]) + exactByte + typeIndexData + Data([0x0B])
                } else {
                    let global = definition.wasmGlobal
                    temp += try encodeType(global.toType())
                    temp += Data([definition.isMutable ? 0x1 : 0x0])
                    // This has to be a constant expression: https://webassembly.github.io/spec/core/valid/instructions.html#constant-expressions
                    var temporaryInstruction: Instruction? = nil
                    // Also create some temporary output variables that do not have a number, these are only to satisfy the instruction assertions, maybe this can be done more nicely somehow.
                    switch global {
                    case .wasmf32(let val):
                        temporaryInstruction = Instruction(Constf32(value: val), output: Variable())
                    case .wasmf64(let val):
                        temporaryInstruction = Instruction(Constf64(value: val), output: Variable())
                    case .wasmi32(let val):
                        temporaryInstruction = Instruction(Consti32(value: val), output: Variable())
                    case .wasmi64(let val):
                        temporaryInstruction = Instruction(Consti64(value: val), output: Variable())
                    case .externref:
                        temp += try! Data([0xD0]) + encodeHeapType(.wasmExternRef()) + Data([0x0B])
                        continue
                    case .exnref:
                        temp += try! Data([0xD0]) + encodeHeapType(.wasmExnRef()) + Data([0x0B])
                        continue
                    case .i31ref:
                        temp += try! Data([0xD0]) + encodeHeapType(.wasmI31Ref()) + Data([0x0B])
                        continue
                    case .refFunc(_),
                        .imported(_),
                        .indexRef,
                        .indexExactRef:
                        fatalError("unreachable")
                    }
                    temp += try lift(temporaryInstruction!)
                    temp += Data([0x0B])
                }
            }
        }

        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("global section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildMemorySection() {
        let memoryCount = self.definitions.count { $0.kind == .memory }
        if memoryCount == 0 {
            return
        }

        self.bytecode += [WasmSection.memory.rawValue]
        var temp = Leb128.unsignedEncode(memoryCount)

        for case .memory(let instruction) in self.definitions {
            let type = typer.type(of: instruction.output)
            assert(type.isWasmMemoryType)
            let mem = type.wasmMemoryType!

            let limits_byte: UInt8 =
                (mem.isMemory64 ? 4 : 0) | (mem.isShared ? 2 : 0) | (mem.limits.max != nil ? 1 : 0)
            temp += Data([limits_byte])

            temp += Data(Leb128.unsignedEncode(mem.limits.min))
            if let maxPages = mem.limits.max {
                temp += Data(Leb128.unsignedEncode(maxPages))
            }
        }

        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("memory section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    private func buildTagSection() throws {
        if self.definitions.count(where: { $0.kind == .tag }) == 0 {
            return  // Skip the whole section.
        }

        self.bytecode.append(WasmSection.tag.rawValue)
        var section = Data()

        section += Leb128.unsignedEncode(self.definitions.count { $0.kind == .tag })

        for case .tag(let instr) in self.definitions {
            let signatureDesc = typer.getTypeDescription(of: instr.input(0))
            section.append(0)
            section.append(Leb128.unsignedEncode(typeDescToIndex[signatureDesc]!))
        }

        self.bytecode.append(Leb128.unsignedEncode(section.count))
        self.bytecode.append(section)

        if verbose {
            print("tag section is")
            for byte in section {
                print(String(format: "%02X ", byte))
            }
        }
    }

    // Export all imports and defined things by default. The typer derives the type of the module's
    // exports object from the same `WasmModuleInterface`.
    private func buildExportedSection() throws {
        let moduleExports = moduleInterface.exports
        assert(moduleInterface.definitions.count == self.definitions.count)
        if moduleExports.isEmpty {
            return
        }

        self.bytecode += [WasmSection.export.rawValue]

        var temp = Data()

        // The number of all exports.
        temp += Leb128.unsignedEncode(moduleExports.count)

        for export in moduleExports {
            // Append the name as a vector
            temp += Leb128.unsignedEncode(export.name.utf8.count)
            temp += export.name.data(using: .utf8)!
            // The imports come first in each index space, followed by the JS string builtins and
            // the imported string constants, which we don't export, and then the definitions.
            let index = try resolveIdx(
                ofType: export.kind, for: export.variable,
                functionSignature: export.reexportedImport?.functionSignature)
            temp += Leb128.unsignedEncode(export.kind.externalKindByte)
            temp += Leb128.unsignedEncode(index)
        }

        // Append the length of the section and the section contents itself.
        self.bytecode.append(Leb128.unsignedEncode(temp.count))
        self.bytecode.append(temp)

        if verbose {
            print("export section is")
            for byte in temp {
                print(String(format: "%02X ", byte))
            }
        }
    }

    /// This function updates the internal state of the lifter before actually emitting code to the
    /// wasm module. This should be invoked before we try to get the corresponding bytes for the
    /// Instruction.
    /// Returns true if the instruction requires emitting code into the module's code section (which
    /// means it is true for almost all instructions appearing inside a wasm function and false for
    /// all instructions outside of a wasm function like a Wasm memory definition).
    private func updateLifterState(wasmInstruction instr: Instruction) -> Bool {
        // Make sure that we actually have a Wasm operation here.
        assert(instr.op is WasmOperation)

        switch instr.op.opcode {
        case .wasmBeginBlock(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginIf(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginElse(_):
            // Note: We need to subtract one because the begin else block closes the if block before opening the else block!
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmBeginTryTable(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginTry(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginTryDelegate(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginLoop(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginCatch(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(1)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmBeginCatchAll(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmNop(_):
            // Just analyze the instruction but do nothing else here.
            // This lets the typer know that we can skip this instruction without breaking any analysis.
            break
        case .beginWasmFunction(_):
            let signatureDef = instr.input(0)
            let signature = typer.type(of: instr.input(0)).wasmFunctionSignatureDefSignature
            let functionInfo = FunctionInfo(
                signature, signatureDef: signatureDef, Data(), for: self,
                withArguments: Array(instr.innerOutputs))
            self.definitions.append(.function(functionInfo))
            // Set the current active function as we are *actively* in it.
            currentFunction = functionInfo
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] =
                self.currentFunction!.variableAnalyzer.wasmBranchDepth
        case .endWasmFunction(_):
            currentFunction!.outputVariable = instr.output
            return true
        case .wasmDefineGlobal(_):
            assert(
                self.definitions.contains(where: {
                    $0.kind == .global && $0.getDefInstr()!.output == instr.output
                }))
        case .wasmDefineTable(_):
            assert(
                self.definitions.contains(where: {
                    $0.kind == .table && $0.getDefInstr()!.output == instr.output
                }))
        case .wasmDefineMemory(_):
            assert(
                self.definitions.contains(where: {
                    $0.kind == .memory && $0.getDefInstr()!.output == instr.output
                }))
        case .wasmDefineDataSegment(_):
            self.dataSegments.append(instr)
        case .wasmDefineElementSegment(_):
            self.elementSegments.append(instr)
        case .wasmJsCall(_):
            return true
        case .wasmThrow(_):
            return true
        case .wasmDefineTag(_):
            assert(
                self.definitions.contains(where: {
                    $0.kind == .tag && $0.getDefInstr()!.output == instr.output
                }))
        case .wasmDefineAdHocModuleSignatureType(_):
            break
        default:
            return true
        }

        return false
    }

    // requires that the instr has been analyzed before. Maybe assert that?
    private func emitInputLoadsIfNecessary(forInstruction instr: Instruction) {
        // Don't emit loads for reassigns. This is specially handled in the `lift` function for
        // reassigns. WasmDefineAdHocSignatureType isn't a wasm instruction and therefore also
        // doesn't have any Wasm stack inputs.
        if instr.op is WasmReassign || instr.op is WasmDefineAdHocSignatureType {
            return
        }

        // Check if instruction input is a parameter or if we have an expression for it, if so, we need to load it now.
        for input in instr.inputs {
            // Skip "internal" inputs, i.e. ones that don't map to a slot, such as .label variables
            let inputType = typer.type(of: input)
            if inputType.Is(.anyWasmLabel) || inputType.Is(.wasmExceptionLabel) {
                continue
            }

            // If we have a stackslot, i.e. it is a local, or argument, then add the stack load.
            if currentFunction!.getStackSlot(for: input) != nil {
                // Emit stack load here now.
                currentFunction!.addStackLoad(for: input)
                continue
            }

            // Load the input now. For "internal" variables, we should not have an expression.
            if let expr = self.writer.getExpr(for: input) {
                currentFunction!.appendToCode(expr)
                continue
            }
        }
    }

    private func emitBytesForInstruction(forInstruction instr: Instruction) throws {
        currentFunction!.appendToCode(try lift(instr))
    }

    private func emitStackSpillsIfNecessary(forInstruction instr: Instruction) {
        // Don't emit spills for reassigns. This is specially handled in the `lift` function for
        // reassigns. Similarly, the end of a function doesn't spill anything.
        // WasmDefineAdHocSignatureType isn't a wasm instruction and therefore also doesn't have any
        // Wasm stack inputs.
        if instr.op is WasmReassign || instr.op is EndWasmFunction
            || instr.op is WasmDefineAdHocSignatureType
        {
            return
        }

        // If we have an output, make sure we store it on the stack as this is a "complex" instruction, i.e. has inputs and outputs.
        if instr.numOutputs > 0 {
            assert(instr.outputs.allSatisfy { !typer.type(of: $0).Is(.anyWasmLabel) })
            for output in instr.outputs.reversed() {
                // Also spill the instruction
                currentFunction!.spillLocal(forVariable: output)
                // Add the corresponding stack load as an expression, this adds the number of arguments, as output vars always live after the function arguments.
                self.writer.addExpr(
                    for: output,
                    bytecode: Data([0x20])
                        + Leb128.unsignedEncode(currentFunction!.localsInfo.count - 1))
            }
        }

        if instr.op.attributes.contains(.isBlockStart) {
            // As the parameters are pushed "in order" to the stack, they need to be popped in reverse order.
            for innerOutput in instr.innerOutputs.reversed() {
                let t = typer.type(of: innerOutput)
                if !t.Is(.anyWasmLabel) && !t.Is(.wasmExceptionLabel) {
                    currentFunction!.spillLocal(forVariable: innerOutput)
                }
            }
        }
    }

    // Analyzes all instructions to add the module's globals, tables, memories and tags to the
    // definitions and to collect the type groups, string constants and JS string builtins that the
    // module uses.
    private func importAnalysis() throws {
        func registerTypeDependencies(for typeDesc: WasmTypeDescription) throws {
            guard typeDesc.typeGroupIndex != -1 else {
                throw CompileError.fatalError("Missing type group index for \(typeDesc)")
            }
            // Add typegroups and their dependencies.
            if typeGroups.insert(typeDesc.typeGroupIndex).inserted {
                typeGroups.formUnion(
                    typer.getTypeGroupDependencies(typeGroupIndex: typeDesc.typeGroupIndex))
            }
        }

        for instr in self.instructionBuffer {
            // If a variable is error typed, we cannot safely lift the module, and stop instead.
            // This can happen, for example, because data flow is not tracked for Wasm globals
            // across the Wasm <-> JS boundary.
            if instr.inouts.contains(where: { typer.type(of: $0) == .error }) {
                throw CompileError.missingTypeInformation
            }

            if let loadStringOp = instr.op as? WasmStringConstant {
                if !importedStringConstants.contains(loadStringOp.value) {
                    importedStringConstants.append(loadStringOp.value)
                }
            }

            for input in instr.inputs {
                let inputType = typer.type(of: input)

                if inputType.Is(.wasmTypeDef()) || inputType.Is(.anyIndexRef) {
                    // TODO(bettscheider): Remove this branch when debugging has concluded
                    if case .Index(let desc, _) = inputType.wasmReferenceType?.kind,
                        desc.get() == nil
                    {
                        print("Failed program:")
                        print(FuzzILLifter().lift(self.instructionBuffer))
                        fatalError(
                            "Failed to get WasmTypeDescription for \(input) with ILType \(inputType)."
                        )
                    }
                    let typeDesc = typer.getTypeDescription(of: input)
                    try registerTypeDependencies(for: typeDesc)
                }

                if inputType.Is(.object(ofGroup: "WasmTable"))
                    || inputType.Is(.object(ofGroup: "WasmGlobal"))
                {
                    // If the table or global uses a custom index type, ensure it's registered.
                    var valueType: ILType? = nil
                    if let globalType = inputType.wasmGlobalType {
                        valueType = globalType.valueType
                    } else if let tableType = inputType.wasmTableType {
                        valueType = tableType.elementType
                    }

                    if let valueType = valueType, valueType.Is(.anyIndexRef) {
                        let typeDesc = typer.getTypeDescription(of: valueType)
                        try registerTypeDependencies(for: typeDesc)
                    }
                }

                // Special handling for tag
                // TODO: Can we just use .isWasmTagType?
                if inputType.Is(.object(ofGroup: "WasmTag")) {
                    // We need the tag parameters here or we need to bail.
                    if !inputType.isWasmTagType {
                        throw WasmLifter.CompileError.missingTypeInformation
                    }
                }

                // Special handling for functions, we only expect them in WasmJSCalls, and WasmDefineTable instructions right now.
                // We can treat the suspendingObjects as function imports.
                if inputType.Is(.function())
                    || inputType.Is(.object(ofGroup: "WasmSuspendingObject"))
                {
                    switch instr.op.opcode {
                    case .wasmJsCall(_), .wasmDefineTable(_):
                        break
                    default:
                        // This instruction has likely expected some .object() of a specific group, as this variable can originate from outside wasm, it might have been reassigned to. Which means we will enter this path.
                        // Therefore we need to bail.
                        throw CompileError.invalidInput
                    }
                }
            }

            // The output handling needs to match on specific opcodes, it cannot just look at the output type as that might've been propagated.
            switch instr.op.opcode {
            case .wasmDefineGlobal(_):
                self.definitions.append(.global(instr))
            case .wasmDefineTable(_):
                self.definitions.append(.table(instr))
            case .wasmDefineMemory(_):
                self.definitions.append(.memory(instr))
            case .wasmDefineTag(_):
                self.definitions.append(.tag(instr))
            case .wasmJSStringLength(_), .wasmJSStringFromCharCodeArray(_),
                .wasmJSStringFromCharCode(_), .wasmJSStringFromCodePoint(_),
                .wasmJSStringCharCodeAt(_), .wasmJSStringCodePointAt(_),
                .wasmJSStringIntoCharCodeArray(_), .wasmJSStringCast(_), .wasmJSStringTest(_),
                .wasmJSStringConcat(_), .wasmJSStringSubstring(_), .wasmJSStringEquals(_),
                .wasmJSStringCompare(_):
                self.trackJSStringBuiltinUsage(forInstr: instr)

            default:
                continue
            }
        }

        // Eagerly map all types in typegroups to module-specific indices. (We can't do this when
        // building the type section as the instructions get lowered before we emit the type
        // section.)
        var currentTypeIndex = 0

        for typeGroupIndex in typeGroups.sorted() {
            for typeDef in typer.getTypeGroup(typeGroupIndex) {
                let typeDesc = typer.getTypeDescription(of: typeDef)
                typeDescToIndex[typeDesc] = currentTypeIndex
                currentTypeIndex += 1
            }
        }
        userDefinedTypesCount = currentTypeIndex

        // Find out how many "normal" imported functions we have
        let baseBuiltinIndex = moduleInterface.imports.count { $0.kind == .function }

        // Assign builtin imports to the next available indices, and
        // store their indices for emission later.
        for i in 0..<jsStringBuiltins.count {
            var builtin = jsStringBuiltins[i]
            builtin.index = baseBuiltinIndex + i
            jsStringBuiltins.updateOrAppend(builtin)
        }
    }

    /// Helper function to resolve the index (as laid out in the binary format) of an instruction
    /// input Variable of a specific `WasmModuleInterface.Kind`.
    /// Intended to be called from `lift`.
    /// A function can be imported multiple times with different signatures, so an imported function
    /// is only resolved with the `functionSignature` of its import.
    func resolveIdx(
        ofType kind: WasmModuleInterface.Kind, for input: Variable,
        functionSignature: WasmModuleInterface.FunctionSignature? = nil
    ) throws -> Int {
        // The imports of the requested type.
        let imports = moduleInterface.imports.filter { $0.kind == kind }

        // Now get the index in this "import space"
        if let idx = imports.firstIndex(where: {
            $0.variable == input && $0.functionSignature == functionSignature
        }) {
            return idx
        }

        // This is the defined space, i.e. where the type matches the predicate directly.
        let idx = self.definitions.filter({ $0.kind == kind }).firstIndex(where: { definition in
            // Functions don't have a defining instruction and as such have special handling here.
            if case .function(let fInfo) = definition {
                fInfo.outputVariable == input
            } else {
                definition.getDefInstr()!.output == input
            }
        })

        if let idx = idx {
            let offsetFunc = kind == .function ? jsStringBuiltins.count : 0
            let offsetGlobal = kind == .global ? importedStringConstants.count : 0
            return imports.count + offsetFunc + offsetGlobal + idx
        }

        throw WasmLifter.CompileError.failedIndexLookUp
    }

    func resolveDataSegmentIdx(for input: Variable) -> Int {
        dataSegments.firstIndex { $0.output == input }!
    }

    func resolveElementSegmentIdx(for input: Variable) -> Int {
        elementSegments.firstIndex { $0.output == input }!
    }

    // The memory immediate argument, which encodes the alignment and memory index.
    // For memory 0, this is just the alignment. For other memories, a flag is set
    // and the memory index is also encoded.
    // Memory zero: `[align]`.
    // Multi-memory: `[align | 0x40] + [mem_idx]`.
    private func alignmentAndMemoryBytes(
        _ memory: Variable, alignment: Int64 = 1,
        ordering: WasmMemoryOrdering = .sequentiallyConsistent, isRMW: Bool = false
    ) throws -> Data {
        assert(
            alignment > 0 && (alignment & (alignment - 1)) == 0, "Alignment must be a power of two")
        let memoryIdx = try resolveIdx(ofType: .memory, for: memory)

        let alignmentLog2 = alignment.trailingZeroBitCount
        assert(
            alignmentLog2 < 0x20, "Alignment \(alignment) is too large")

        var flags = UInt8(alignmentLog2)
        if memoryIdx != 0 {
            flags |= 0x40
        }
        if ordering != .sequentiallyConsistent {
            flags |= 0x10
        }

        var result = Data([flags])
        if memoryIdx != 0 {
            result.append(contentsOf: Leb128.unsignedEncode(memoryIdx))
        }
        if ordering != .sequentiallyConsistent {
            var orderingByte = ordering.rawValue
            if isRMW {
                // For RMWs, the low four bits encode the read ordering and the high four bits
                // encode the write ordering.
                orderingByte |= (orderingByte << 4)
            }
            result.append(orderingByte)
        }
        return result
    }

    private func branchDepthFor(label: Variable) throws -> Int {
        guard let labelDepth = self.currentFunction!.labelBranchDepthMapping[label] else {
            throw CompileError.fatalError("No branch depth information for label \(label)")
        }
        return self.currentFunction!.variableAnalyzer.wasmBranchDepth - labelDepth - 1
    }

    private func liftBranchOnCast(
        _ instr: Instruction,
        parameterCount: Int,
        targetType: ILType,
        gcOpcode: UInt8,
        isDescriptor: Bool = false
    ) throws -> Data {
        let branchDepth = try branchDepthFor(label: instr.input(0))
        let refInputIndex = 1 + parameterCount
        let targetTypeInputIndex = refInputIndex + 1

        let actualSourceType = typer.type(of: instr.input(refInputIndex)).wasmReferenceType!
        let targetRefType = targetType.wasmReferenceType!

        // When custom descriptors are disabled, br_on_cast* requires target <= source (both nullability
        // and heap type), so we widen the source type immediate to the (nullable) top type of the
        // hierarchy, e.g., anyref.
        // Custom descriptors relaxes this to only require the same type hierarchy, allowing us to
        // use the actual input type as the source type immediate.
        var flags: UInt8 = 0
        if !typer.enableCustomDescriptors || actualSourceType.nullability { flags |= 0x01 }
        if targetRefType.nullability { flags |= 0x02 }

        // When custom descriptors are disabled, we use the top type of the hierarchy as the source type,
        // in order to ensure br_on_cast* validation succeeds (target <= source).
        let sourceData =
            try typer.enableCustomDescriptors
            ? encodeHeapType(actualSourceType.kind)
            : encodeHeapType(actualSourceType.kind.topType())
        let targetData =
            isDescriptor
            ? try encodeDescriptorReferenceType(
                targetRefType, instr: instr, descriptorInput: targetTypeInputIndex)
            : try encodeReferenceType(
                targetRefType, instr: instr, typeInput: targetTypeInputIndex)
        return Data([Prefix.GC.rawValue, gcOpcode, flags]) + Leb128.unsignedEncode(branchDepth)
            + sourceData + targetData
    }

    /// Returns the Bytes that correspond to this instruction.
    /// This will also automatically add bytes that are necessary based on the state of the Lifter.
    /// Example: LoadGlobal with an input variable will resolve the input variable to a concrete global index.
    private func lift(_ wasmInstruction: Instruction) throws -> Data {
        // Make sure that we actually have a Wasm operation here.
        assert(wasmInstruction.op is WasmOperation)

        switch wasmInstruction.op.opcode {
        case .endWasmFunction(_):
            currentFunction = nil
            return Data([])
        case .consti64(let op):
            return Data([0x42]) + Leb128.signedEncode(Int(op.value))
        case .consti32(let op):
            return Data([0x41]) + Leb128.signedEncode(Int(op.value))
        case .constf32(let op):
            return Data([0x43]) + Data(bytes: &op.value, count: 4)
        case .constf64(let op):
            return Data([0x44]) + Data(bytes: &op.value, count: 8)
        case .wasmReturn(_):
            return Data([0x0F])
        case .wasmi32CompareOp(let op):
            return Data([0x46 + op.compareOpKind.rawValue])
        case .wasmi64CompareOp(let op):
            return Data([0x51 + op.compareOpKind.rawValue])
        case .wasmf32CompareOp(let op):
            return Data([0x5B + op.compareOpKind.rawValue])
        case .wasmf64CompareOp(let op):
            return Data([0x61 + op.compareOpKind.rawValue])
        case .wasmi32BinOp(let op):
            return Data([0x6A + op.binOpKind.rawValue])
        case .wasmi64BinOp(let op):
            return Data([0x7C + op.binOpKind.rawValue])
        case .wasmf32BinOp(let op):
            return Data([0x92 + op.binOpKind.rawValue])
        case .wasmf64BinOp(let op):
            return Data([0xA0 + op.binOpKind.rawValue])
        case .wasmi32UnOp(let op):
            return Data([0x67 + op.unOpKind.rawValue])
        case .wasmi64UnOp(let op):
            return Data([0x79 + op.unOpKind.rawValue])
        case .wasmf32UnOp(let op):
            return Data([0x8B + op.unOpKind.rawValue])
        case .wasmf64UnOp(let op):
            return Data([0x99 + op.unOpKind.rawValue])
        case .wasmi32EqualZero(_):
            return Data([0x45])
        case .wasmi64EqualZero(_):
            return Data([0x50])
        case .wasmi64WideBinOp(let op):
            return Data([Prefix.Numeric.rawValue])
                + Leb128.unsignedEncode(Int(op.binOpKind.rawValue))
        case .wasmi64WideMulOp(let op):
            return Data([Prefix.Numeric.rawValue])
                + Leb128.unsignedEncode(Int(op.mulOpKind.rawValue))

        // Numerical Conversion Operations
        case .wasmWrapi64Toi32(_):
            return Data([0xA7])
        case .wasmTruncatef32Toi32(let op):
            if op.isSigned {
                return Data([0xA8])
            } else {
                return Data([0xA9])
            }
        case .wasmTruncatef64Toi32(let op):
            if op.isSigned {
                return Data([0xAA])
            } else {
                return Data([0xAB])
            }
        case .wasmExtendi32Toi64(let op):
            if op.isSigned {
                return Data([0xAC])
            } else {
                return Data([0xAD])
            }
        case .wasmTruncatef32Toi64(let op):
            if op.isSigned {
                return Data([0xAE])
            } else {
                return Data([0xAF])
            }
        case .wasmTruncatef64Toi64(let op):
            if op.isSigned {
                return Data([0xB0])
            } else {
                return Data([0xB1])
            }
        case .wasmConverti32Tof32(let op):
            if op.isSigned {
                return Data([0xB2])
            } else {
                return Data([0xB3])
            }
        case .wasmConverti64Tof32(let op):
            if op.isSigned {
                return Data([0xB4])
            } else {
                return Data([0xB5])
            }
        case .wasmDemotef64Tof32(_):
            return Data([0xB6])
        case .wasmConverti32Tof64(let op):
            if op.isSigned {
                return Data([0xB7])
            } else {
                return Data([0xB8])
            }
        case .wasmConverti64Tof64(let op):
            if op.isSigned {
                return Data([0xB9])
            } else {
                return Data([0xBA])
            }
        case .wasmPromotef32Tof64(_):
            return Data([0xBB])
        case .wasmReinterpretf32Asi32(_):
            return Data([0xBC])
        case .wasmReinterpretf64Asi64(_):
            return Data([0xBD])
        case .wasmReinterpreti32Asf32(_):
            return Data([0xBE])
        case .wasmReinterpreti64Asf64(_):
            return Data([0xBF])
        case .wasmSignExtend8Intoi32(_):
            return Data([0xC0])
        case .wasmSignExtend16Intoi32(_):
            return Data([0xC1])
        case .wasmSignExtend8Intoi64(_):
            return Data([0xC2])
        case .wasmSignExtend16Intoi64(_):
            return Data([0xC3])
        case .wasmSignExtend32Intoi64(_):
            return Data([0xC4])
        case .wasmTruncateSatf32Toi32(let op):
            let d = Data([Prefix.Numeric.rawValue])
            if op.isSigned {
                return d + Leb128.unsignedEncode(0)
            } else {
                return d + Leb128.unsignedEncode(1)
            }
        case .wasmTruncateSatf64Toi32(let op):
            let d = Data([Prefix.Numeric.rawValue])
            if op.isSigned {
                return d + Leb128.unsignedEncode(2)
            } else {
                return d + Leb128.unsignedEncode(3)
            }
        case .wasmTruncateSatf32Toi64(let op):
            let d = Data([Prefix.Numeric.rawValue])
            if op.isSigned {
                return d + Leb128.unsignedEncode(4)
            } else {
                return d + Leb128.unsignedEncode(5)
            }
        case .wasmTruncateSatf64Toi64(let op):
            let d = Data([Prefix.Numeric.rawValue])
            if op.isSigned {
                return d + Leb128.unsignedEncode(6)
            } else {
                return d + Leb128.unsignedEncode(7)
            }

        case .wasmLoadGlobal(_):
            // Actually return the current known global index here.
            // We should have resolved all globals here (in a prepass) and know their respective global index.
            // Get the index for the global and emit it here magically.
            // The first input has to be in the global or imports arrays.
            let input = wasmInstruction.input(0)
            return Data([0x23]) + Leb128.unsignedEncode(try resolveIdx(ofType: .global, for: input))
        case .wasmStringConstant(let op):
            let importsCount = moduleInterface.imports.count { $0.kind == .global }
            let stringIdx = importedStringConstants.firstIndex(of: op.value)!
            return Data([0x23]) + Leb128.unsignedEncode(importsCount + stringIdx)
        case .wasmStoreGlobal(_):

            // Get the index for the global and emit it here magically.
            // The first input has to be in the global or imports arrays.
            let input = wasmInstruction.input(0)
            return Data([0x24]) + Leb128.unsignedEncode(try resolveIdx(ofType: .global, for: input))
        case .wasmTableGet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x25])
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableSet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x26])
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableSize(_):
            let tableRef = wasmInstruction.input(0)
            // Value 0x10 is table.size opcode
            return Data([Prefix.Numeric.rawValue]) + Leb128.unsignedEncode(0x10)
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableGrow(_):
            let tableRef = wasmInstruction.input(0)
            // Value 0x0f is table.grow opcode
            return Data([Prefix.Numeric.rawValue]) + Leb128.unsignedEncode(0x0f)
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmCallIndirect(_):
            let tableRef = wasmInstruction.input(0)
            let signatureDef = wasmInstruction.input(1)
            let typeDesc = typer.getTypeDescription(of: signatureDef)
            let sigIndex = typeDescToIndex[typeDesc]!
            return Data([0x11]) + Leb128.unsignedEncode(sigIndex)
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmCallDirect(_):
            let functionRef = wasmInstruction.input(0)
            return Data([0x10])
                + Leb128.unsignedEncode(try resolveIdx(ofType: .function, for: functionRef))
        case .wasmCallRef(_):
            let functionRef = wasmInstruction.inputs.last!
            let typeDesc = typer.getTypeDescription(of: functionRef)
            let sigIndex = typeDescToIndex[typeDesc]!
            return Data([0x14]) + Leb128.unsignedEncode(sigIndex)
        case .wasmReturnCallRef(_):
            let functionRef = wasmInstruction.inputs.last!
            let typeDesc = typer.getTypeDescription(of: functionRef)
            let sigIndex = typeDescToIndex[typeDesc]!
            return Data([0x15]) + Leb128.unsignedEncode(sigIndex)
        case .wasmReturnCallDirect(_):
            let functionRef = wasmInstruction.input(0)
            return Data([0x12])
                + Leb128.unsignedEncode(try resolveIdx(ofType: .function, for: functionRef))
        case .wasmReturnCallIndirect(_):
            let tableRef = wasmInstruction.input(0)
            let signatureDef = wasmInstruction.input(1)
            let typeDesc = typer.getTypeDescription(of: signatureDef)
            let sigIndex = typeDescToIndex[typeDesc]!
            return Data([0x13]) + Leb128.unsignedEncode(sigIndex)
                + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmMemoryLoad(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([op.loadType.rawValue]) + alignAndMemory
                + Leb128.unsignedEncode(op.staticOffset)
        case .wasmMemoryStore(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            let opCode = Data(
                op.storeType != .S128StoreMem
                    ? [op.storeType.rawValue]
                    : [Prefix.Simd.rawValue, op.storeType.rawValue])
            return opCode + alignAndMemory + Leb128.unsignedEncode(op.staticOffset)
        case .wasmAtomicLoad(let op):
            let opcode = [Prefix.Atomic.rawValue, op.loadType.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(
                wasmInstruction.input(0), alignment: op.loadType.naturalAlignment(),
                ordering: op.ordering)
            return Data(opcode) + alignAndMemory + Leb128.unsignedEncode(op.offset)

        case .wasmAtomicStore(let op):
            let opcode = [Prefix.Atomic.rawValue, op.storeType.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(
                wasmInstruction.input(0), alignment: op.storeType.naturalAlignment(),
                ordering: op.ordering)
            return Data(opcode) + alignAndMemory + Leb128.unsignedEncode(op.offset)
        case .wasmAtomicRMW(let op):
            let opcode = [Prefix.Atomic.rawValue, op.op.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(
                wasmInstruction.input(0), alignment: op.op.naturalAlignment(),
                ordering: op.ordering, isRMW: true)
            return Data(opcode) + alignAndMemory + Leb128.unsignedEncode(op.offset)
        case .wasmAtomicCmpxchg(let op):
            let opcode = [Prefix.Atomic.rawValue, op.op.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(
                wasmInstruction.input(0), alignment: op.op.naturalAlignment(),
                ordering: op.ordering, isRMW: true)
            return Data(opcode) + alignAndMemory + Leb128.unsignedEncode(op.offset)
        case .wasmMemorySize(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0x3F]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryGrow(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0x40]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryCopy(_):
            let dstMemIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            let srcMemIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0A]) + Leb128.unsignedEncode(dstMemIdx)
                + Leb128.unsignedEncode(srcMemIdx)
        case .wasmMemoryFill(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0xFC, 0x0B]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryInit(_):
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(0))
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(1))
            return Data([0xFC, 0x08]) + Leb128.unsignedEncode(dataSegmentIdx)
                + Leb128.unsignedEncode(memoryIdx)
        case .wasmDropDataSegment(_):
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(0))
            return Data([0xFC, 0x09]) + Leb128.unsignedEncode(dataSegmentIdx)
        case .wasmDropElementSegment(_):
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(0))
            return Data([0xFC, 0x0d]) + Leb128.unsignedEncode(elementSegmentIdx)
        case .wasmTableInit(_):
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(0))
            let tableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0c]) + Leb128.unsignedEncode(elementSegmentIdx)
                + Leb128.unsignedEncode(tableIdx)
        case .wasmTableCopy(_):
            let dstTableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(0))
            let srcTableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0e]) + Leb128.unsignedEncode(dstTableIdx)
                + Leb128.unsignedEncode(srcTableIdx)
        case .wasmTableFill(_):
            let tableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(0))
            return Data([0xFC, 0x11]) + Leb128.unsignedEncode(tableIdx)
        case .wasmJsCall(_):
            let wasmSignature = typer.type(of: wasmInstruction.input(0))
                .wasmFunctionSignatureDefSignature
            let functionIdx = try resolveIdx(
                ofType: .function, for: wasmInstruction.input(1),
                functionSignature: .wasmSignature(wasmSignature))
            return Data([0x10]) + Leb128.unsignedEncode(functionIdx)
        case .wasmBeginBlock(_):
            // A Block can "produce" (push) an item on the value stack, just like a function. Similarly, a block can also have parameters.
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#binary-blocktype
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            return Data([0x02] + Leb128.signedEncode(typeDescToIndex[signatureDesc]!))
        case .wasmBeginLoop(_):
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            return Data([0x03] + Leb128.signedEncode(typeDescToIndex[signatureDesc]!))
        case .wasmBeginTryTable(let op):
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            var inputIndex = 1 + op.parameterCount
            let catchTable: Data = try op.catches.map {
                switch $0 {
                case .Ref, .NoRef:
                    let tag = try resolveIdx(ofType: .tag, for: wasmInstruction.input(inputIndex))
                    let depth = try branchDepthFor(label: wasmInstruction.input(inputIndex + 1)) - 1
                    let result =
                        Data([$0.rawValue]) + Leb128.unsignedEncode(tag)
                        + Leb128.unsignedEncode(depth)
                    inputIndex += 2
                    return result
                case .AllRef, .AllNoRef:
                    let depth = try branchDepthFor(label: wasmInstruction.input(inputIndex)) - 1
                    inputIndex += 1
                    return Data([$0.rawValue]) + Leb128.unsignedEncode(depth)
                }
            }.reduce(Data(), +)
            return [0x1F]
                + Leb128.signedEncode(typeDescToIndex[signatureDesc]!)
                + Leb128.unsignedEncode(op.catches.count)
                + catchTable
        case .wasmBeginTry(_):
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            return Data([0x06] + Leb128.signedEncode(typeDescToIndex[signatureDesc]!))
        case .wasmBeginTryDelegate(_):
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            return Data([0x06] + Leb128.signedEncode(typeDescToIndex[signatureDesc]!))
        case .wasmBeginCatchAll(_):
            return Data([0x19])
        case .wasmBeginCatch(_):
            return Data(
                [0x07]
                    + Leb128.unsignedEncode(
                        try resolveIdx(ofType: .tag, for: wasmInstruction.input(1))))
        case .wasmEndLoop(_),
            .wasmEndIf(_),
            .wasmEndTryTable(_),
            .wasmEndTry(_),
            .wasmEndBlock(_):
            // Basically the same as EndBlock, just an explicit instruction.
            return Data([0x0B])
        case .wasmEndTryDelegate(_):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(1))
            // Mutation might make this EndTryDelegate branch to itself, which should not happen.
            if branchDepth < 0 {
                throw WasmLifter.CompileError.invalidBranch
            }
            return Data([0x18]) + Leb128.unsignedEncode(branchDepth)
        case .wasmThrow(_):
            return Data(
                [0x08]
                    + Leb128.unsignedEncode(
                        try resolveIdx(ofType: .tag, for: wasmInstruction.input(0))))
        case .wasmThrowRef(_):
            return Data([0x0A])
        case .wasmRethrow(_):
            let blockDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x09] + Leb128.unsignedEncode(blockDepth))
        case .wasmBranch(_):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x0C]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchIf(let op):
            currentFunction!.addBranchHint(op.hint)
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x0D]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchOnNull(_):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0xD5]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchOnCast(let op):
            return try liftBranchOnCast(
                wasmInstruction, parameterCount: op.parameterCount, targetType: op.targetType,
                gcOpcode: 0x18)
        case .wasmBranchOnCastFail(let op):
            return try liftBranchOnCast(
                wasmInstruction, parameterCount: op.parameterCount, targetType: op.targetType,
                gcOpcode: 0x19)
        case .wasmBranchOnCastDescEq(let op):
            return try liftBranchOnCast(
                wasmInstruction, parameterCount: op.parameterCount, targetType: op.targetType,
                gcOpcode: 0x25, isDescriptor: true)
        case .wasmBranchOnCastDescEqFail(let op):
            return try liftBranchOnCast(
                wasmInstruction, parameterCount: op.parameterCount, targetType: op.targetType,
                gcOpcode: 0x26, isDescriptor: true)
        case .wasmBranchOnNonNull(_):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0xD6]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchTable(let op):
            let depths = try (0...op.valueCount).map {
                try branchDepthFor(label: wasmInstruction.input($0))
            }
            return Data([0x0E]) + Leb128.unsignedEncode(op.valueCount)
                + depths.map(Leb128.unsignedEncode).joined()
        case .wasmBeginIf(let op):
            currentFunction!.addBranchHint(op.hint)
            let signatureDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let beginIf = Data([0x04] + Leb128.signedEncode(typeDescToIndex[signatureDesc]!))
            // Invert the condition with an `i32.eqz` (resulting in 0 becoming 1 and everything else becoming 0).
            return op.inverted ? Data([0x45]) + beginIf : beginIf
        case .wasmBeginElse(_):
            // 0x05 is the else block instruction.
            return Data([0x05])
        case .wasmReassign(_):
            // wasmReassign is quite special, it needs to work for variables stored in various places, e.g. local slots or even globals. As such the lifting here first needs to locate the destination variable.
            var out = Data()

            let storeInstruction: Data
            // If the variable is a local, we load the stack slot.
            // Check for the stack location of the `to` variable.
            if let stackSlot = currentFunction!.getStackSlot(for: wasmInstruction.input(0)) {

                // Emit the instruction now, with input and stackslot. Since we load this manually we don't need
                // to emit bytes in the emitInputLoadsIfNecessary.
                storeInstruction = Data([0x21]) + Leb128.unsignedEncode(stackSlot)
            } else {
                // It has to be global then. Do what StoreGlobal does.
                storeInstruction =
                    Data([0x24])
                    + Leb128.unsignedEncode(
                        try resolveIdx(ofType: .global, for: wasmInstruction.input(0)))
            }

            // Load the input now. For "internal" variables, we should not have an expression.
            if let expr = self.writer.getExpr(for: wasmInstruction.input(1)) {
                out += expr
            } else if let stackSlot = currentFunction!.getStackSlot(for: wasmInstruction.input(1)) {
                out += Data([0x20]) + Leb128.unsignedEncode(stackSlot)
            } else {
                // Has to be a global then. Do what LoadGlobal does.
                out +=
                    Data([0x23])
                    + Leb128.unsignedEncode(
                        try resolveIdx(ofType: .global, for: wasmInstruction.input(1)))
            }

            return out + storeInstruction
        case .wasmNop(_):
            return Data([0x01])
        case .wasmUnreachable(_):
            return Data([0x00])
        case .wasmSelect(_):
            return try Data([0x1c, 0x01]) + encodeType(typer.type(of: wasmInstruction.output))
        case .constSimd128(let op):
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(12) + Data(op.value)
        case .wasmSimd128IntegerUnOp(let op):
            assert(
                WasmSimd128IntegerUnOpKind.allCases.count == 17,
                "New WasmSimd128IntegerUnOpKind added: check if the encoding is still correct!")
            let base =
                switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerUnOp")
                }
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(base + op.unOpKind.rawValue)
        case .wasmSimd128IntegerBinOp(let op):
            assert(
                WasmSimd128IntegerBinOpKind.allCases.count == 26,
                "New WasmSimd128IntegerBinOpKind added: check if the encoding is still correct!")
            let base =
                switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerBinOp")
                }
            return Data([Prefix.Simd.rawValue])
                + Leb128.unsignedEncode(base + op.binOpKind.rawValue)
        case .wasmSimd128IntegerTernaryOp(let op):
            assert(
                WasmSimd128IntegerTernaryOpKind.allCases.count == 2,
                "New WasmSimd128IntegerTernaryOpKind added: check if the encoding is still correct!"
            )
            let base =
                switch op.shape {
                case .i8x16: 0x100
                case .i16x8: 0x101
                case .i32x4: 0x102
                case .i64x2: 0x103
                default:
                    fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerTernaryOp")
                }
            return Data([Prefix.Simd.rawValue])
                + Leb128.unsignedEncode(base + op.ternaryOpKind.rawValue)
        case .wasmSimd128FloatUnOp(let op):
            assert(
                WasmSimd128FloatUnOpKind.allCases.count == 7,
                "New WasmSimd128FloatUnOpKind added: check if the encoding is still correct!")
            let encoding =
                switch op.shape {
                case .f32x4:
                    switch op.unOpKind {
                    case .ceil: Leb128.unsignedEncode(0x67)
                    case .floor: Leb128.unsignedEncode(0x68)
                    case .trunc: Leb128.unsignedEncode(0x69)
                    case .nearest: Leb128.unsignedEncode(0x6A)
                    case .abs: Leb128.unsignedEncode(0xE0)
                    case .neg: Leb128.unsignedEncode(0xE1)
                    case .sqrt: Leb128.unsignedEncode(0xE3)
                    }
                case .f64x2:
                    switch op.unOpKind {
                    case .ceil: Leb128.unsignedEncode(0x74)
                    case .floor: Leb128.unsignedEncode(0x75)
                    case .trunc: Leb128.unsignedEncode(0x7A)
                    case .nearest: Leb128.unsignedEncode(0x94)
                    case .abs: Leb128.unsignedEncode(0xEC)
                    case .neg: Leb128.unsignedEncode(0xED)
                    case .sqrt: Leb128.unsignedEncode(0xEF)
                    }
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128FloatUnOp")
                }
            return Data([Prefix.Simd.rawValue]) + encoding
        case .wasmSimd128FloatBinOp(let op):
            assert(
                WasmSimd128FloatBinOpKind.allCases.count == 10,
                "New WasmSimd128FloatBinOpKind added: check if the encoding is still correct!")
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(op.getOpcode())
        case .wasmSimd128FloatTernaryOp(let op):
            assert(
                WasmSimd128FloatTernaryOpKind.allCases.count == 2,
                "New WasmSimd128FloatTernaryOpKind added: check if the encoding is still correct!")
            let base =
                switch op.shape {
                case .f32x4: 0x100
                case .f64x2: 0x102
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128FloatTernaryOp")
                }
            return Data([Prefix.Simd.rawValue])
                + Leb128.unsignedEncode(base + op.ternaryOpKind.rawValue)
        case .wasmSimd128Compare(let op):
            assert(
                WasmIntegerCompareOpKind.allCases.count == 10,
                "New WasmIntegerCompareOpKind added: check if the encoding is still correct!")
            assert(
                WasmFloatCompareOpKind.allCases.count == 6,
                "New WasmFloatCompareOpKind added: check if the encoding is still correct!")
            switch op.shape {
            case .i8x16:
                return Data([Prefix.Simd.rawValue])
                    + Leb128.unsignedEncode(0x23 + op.compareOpKind.toInt())
            case .i16x8:
                return Data([Prefix.Simd.rawValue])
                    + Leb128.unsignedEncode(0x2D + op.compareOpKind.toInt())
            case .i32x4:
                return Data([Prefix.Simd.rawValue])
                    + Leb128.unsignedEncode(0x37 + op.compareOpKind.toInt())
            case .i64x2:
                if case .iKind(let value) = op.compareOpKind {
                    let temp =
                        switch value {
                        case .Eq: 0
                        case .Ne: 1
                        case .Lt_s: 2
                        case .Gt_s: 3
                        case .Le_s: 4
                        case .Ge_s: 5
                        default:
                            fatalError(
                                "Shape \(op.shape) does not have \(op.compareOpKind) instruction")
                        }
                    return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0xD6 + temp)
                }
                fatalError("unreachable")
            case .f32x4:
                return Data([Prefix.Simd.rawValue])
                    + Leb128.unsignedEncode(0x41 + op.compareOpKind.toInt())
            case .f64x2:
                return Data([Prefix.Simd.rawValue])
                    + Leb128.unsignedEncode(0x47 + op.compareOpKind.toInt())
            }
        case .wasmSimdSplat(let op):
            return Data([Prefix.Simd.rawValue, op.kind.rawValue])
        case .wasmSimdExtractLane(let op):
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + Leb128.unsignedEncode(op.lane)
        case .wasmSimdReplaceLane(let op):
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + Leb128.unsignedEncode(op.lane)
        case .wasmSimdStoreLane(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + alignAndMemory
                + Leb128.unsignedEncode(op.staticOffset) + Leb128.unsignedEncode(op.lane)
        case .wasmSimdLoadLane(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + alignAndMemory
                + Leb128.unsignedEncode(op.staticOffset) + Leb128.unsignedEncode(op.lane)
        case .wasmSimdLoad(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + alignAndMemory
                + Leb128.unsignedEncode(op.staticOffset)
        case .wasmArrayNewFixed(let op):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x08]) + arrayIndex + Leb128.unsignedEncode(op.size)
        case .wasmArrayNewDefault(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x07]) + arrayIndex
        case .wasmArrayNewData(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(1))
            return Data([Prefix.GC.rawValue, 0x09]) + arrayIndex
                + Leb128.unsignedEncode(dataSegmentIdx)
        case .wasmArrayNewElem(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(1))
            return Data([Prefix.GC.rawValue, 0x0A]) + arrayIndex
                + Leb128.unsignedEncode(elementSegmentIdx)
        case .wasmArrayLen(_):
            return Data([Prefix.GC.rawValue, 0x0F])
        case .wasmArrayGet(let op):
            let typeDesc =
                typer.getTypeDescription(of: wasmInstruction.input(0)) as! WasmArrayTypeDescription
            let opCode: UInt8 = typeDesc.elementType.isPacked() ? (op.isSigned ? 0x0C : 0x0D) : 0x0B
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, opCode]) + arrayIndex
        case .wasmArraySet(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x0E]) + arrayIndex
        case .wasmArrayInitData(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(2))
            return Data([Prefix.GC.rawValue, 0x12]) + arrayIndex
                + Leb128.unsignedEncode(dataSegmentIdx)
        case .wasmArrayInitElem(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(2))
            return Data([Prefix.GC.rawValue, 0x13]) + arrayIndex
                + Leb128.unsignedEncode(elementSegmentIdx)
        case .wasmStructNew(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x00]) + structIndex
        case .wasmStructNewDefault(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x01]) + structIndex
        case .wasmStructNewDesc(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x20]) + structIndex
        case .wasmStructNewDefaultDesc(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x21]) + structIndex
        case .wasmRefGetDesc(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x22]) + structIndex
        case .wasmStructGet(let op):
            let typeDesc =
                typer.getTypeDescription(of: wasmInstruction.input(0)) as! WasmStructTypeDescription
            let opCode: UInt8 =
                typeDesc.fields[op.fieldIndex].type.isPacked() ? (op.isSigned ? 0x03 : 0x04) : 0x02
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let fieldIndex = Leb128.unsignedEncode(op.fieldIndex)
            return Data([Prefix.GC.rawValue, opCode]) + structIndex + fieldIndex
        case .wasmStructSet(let op):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            let fieldIndex = Leb128.unsignedEncode(op.fieldIndex)
            return Data([Prefix.GC.rawValue, 0x05]) + structIndex + fieldIndex
        case .wasmRefNull(_):
            return try Data([0xD0]) + encodeHeapType(typer.type(of: wasmInstruction.output))
        case .wasmRefIsNull(_):
            return Data([0xD1])
        case .wasmRefAsNonNull(_):
            return Data([0xD4])
        case .wasmRefFunc(_):
            let functionRef = wasmInstruction.input(0)
            return Data([0xD2])
                + Leb128.unsignedEncode(try resolveIdx(ofType: .function, for: functionRef))
        case .wasmRefEq(_):
            return Data([0xD3])
        case .wasmRefI31(let op):
            return Data([Prefix.GC.rawValue, op.isShared ? 0x1F : 0x1C])
        case .wasmI31Get(let op):
            let opCode: UInt8 = op.isSigned ? 0x1D : 0x1E
            return Data([Prefix.GC.rawValue, opCode])
        case .wasmAnyConvertExtern(_):
            return Data([Prefix.GC.rawValue, 0x1A])
        case .wasmExternConvertAny(_):
            return Data([Prefix.GC.rawValue, 0x1B])
        case .wasmRefTest(let op):
            let refType = op.type.wasmReferenceType!
            let opCode: UInt8 = refType.nullability ? 0x15 : 0x14
            let typeData = try encodeReferenceType(refType, instr: wasmInstruction, typeInput: 1)
            return Data([Prefix.GC.rawValue, opCode]) + typeData
        case .wasmRefCast(let op):
            let refType = op.type.wasmReferenceType!
            let opCode: UInt8 = refType.nullability ? 0x17 : 0x16
            let typeData = try encodeReferenceType(refType, instr: wasmInstruction, typeInput: 1)
            return Data([Prefix.GC.rawValue, opCode]) + typeData
        case .wasmRefCastDescEq(let op):
            let refType = op.type.wasmReferenceType!
            let opCode: UInt8 = refType.nullability ? 0x24 : 0x23
            let typeData = try encodeDescriptorReferenceType(
                refType, instr: wasmInstruction, descriptorInput: 1)
            return Data([Prefix.GC.rawValue, opCode]) + typeData
        case .wasmDefineAdHocSignatureType(_):
            // Nothing to do here, types are defined inside the typegroups, not inside a wasm
            // function.
            return Data()

        // Wasm JS String Builtins
        case .wasmJSStringLength(_), .wasmJSStringFromCharCodeArray(_),
            .wasmJSStringFromCharCode(_), .wasmJSStringFromCodePoint(_), .wasmJSStringCharCodeAt(_),
            .wasmJSStringCodePointAt(_), .wasmJSStringIntoCharCodeArray(_), .wasmJSStringCast(_),
            .wasmJSStringTest(_), .wasmJSStringConcat(_), .wasmJSStringSubstring(_),
            .wasmJSStringEquals(_), .wasmJSStringCompare(_):
            let builtin = self.getJSStringBuiltin(forInstr: wasmInstruction)
            return Data([0x10]) + Leb128.unsignedEncode(builtin.index!)

        default:
            fatalError("unreachable")
        }
    }
}
