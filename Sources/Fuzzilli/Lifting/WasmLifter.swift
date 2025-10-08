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
    .wasmi32 : Data([0x7F]),
    .wasmi64 : Data([0x7E]),
    .wasmf32 : Data([0x7D]),
    .wasmf64 : Data([0x7C]),
    .wasmSimd128: Data([0x7B]),
    .wasmPackedI8: Data([0x78]),
    .wasmPackedI16: Data([0x77]),

    .bigint  : Data([0x7E]), // Maps to .wasmi64
    .jsAnything: Data([0x6F]), // Maps to .wasmExternRef
    .integer: Data([0x7F]), // Maps to .wasmi32
    .number: Data([0x7D]) // Maps to .wasmf32
]

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

    indirect enum Export {
        // The associated data can be nil, which means that this is a re-export of an import.
        case function(FunctionInfo?)
        // This should only be an import, this is always of type .import(.suspendingObject, variable, signature)
        case suspendingObject
        case table(Instruction?)
        case memory(Instruction?)
        case global(Instruction?)
        case tag(Instruction?)
        // This import case is special.
        //
        // We only expect a single level of "indirectness". I.e. if the export is an import, the type can never be import, it can only be other enum cases.
        // Additionally, if it is an import, the type's associated data should always be nil.
        // We do this because the exports array will serve multiple purposes:
        //  - It tracks the exports and the types we define in the Wasm module
        //  - It tracks the imports we see while traversing the module's code
        //  - It keeps the ordering of seen variables correct, so that when we refer to variables in instructions `resolveIdx` can only look at the exports array and return the correct index
        //  - The `importAnalysis` function should add these entries, exports and imports, to the array in the order it sees them, that keeps the indexes correct.
        //
        // The variable that is associated with this import is later used to pass the variables back to the JavaScript lifter such that it can get the right expressions for the needed imports.
        // Imported functions also have signatures, we need these as we might call a function through two different WasmJSCall instructions.
        // We then cannot distinguish them and we need two different type entries and two different imports.
        case `import`(type: Export, variable: Variable, signature: WasmSignature?)

        // These accessors below don't look into the imports.
        // This is by design, it allows us to easily traverse the exports array to build the sections without filtering out the imports.
        // If we need access to the imports, we can always do
        //  `exports.compactMap({$0.getImport()})`
        // Which will now "unwrap" these imports essentially.
        // It will drop all non-imported entries and return a list of `(type, variable, signature)` for all imports.
        // This can further be filtered for only e.g. tag imports by doing this.
        // `exports.compactMap({$0.getImport()}).filter({$0.type.isFunction})`

        var isFunction : Bool {
            if case .function(_) = self {
                return true
            } else {
                return false
            }
        }

        var isTable : Bool {
            if case .table(_) = self {
                return true
            } else {
                return false
            }
        }

        var isMemory : Bool {
            if case .memory(_) = self {
                return true
            } else {
                return false
            }
        }

        var isGlobal : Bool {
            if case .global(_) = self {
                return true
            } else {
                return false
            }
        }

        var isTag : Bool {
            if case .tag(_) = self {
                return true
            } else {
                return false
            }
        }

        var isSuspendingObject : Bool {
            if case .suspendingObject = self {
                return true
            } else {
                return false
            }
        }

        func getImport() -> (type: Self, variable: Variable, signature: WasmSignature?)? {
            if case let .import(export, variable, signature) = self {
                return (export, variable, signature)
            }
            return nil
        }

        func getDefInstr() -> Instruction? {
            switch self {
            case .function(_),
                 .import(_, _, _),
                 .suspendingObject:
                return nil
            case .global(let instr),
                 .table(let instr),
                 .memory(let instr),
                 .tag(let instr):
                return instr!
            }
        }

        func groupName() -> String {
            switch self {
            case .function,
                 .import,
                 .suspendingObject:
                // Functions and imports don't have group names, this is used for getting imports of that type.
                fatalError("unreachable")
            case .table:
                return "WasmTable"
            case .memory:
                return "WasmMemory"
            case .global:
                return "WasmGlobal"
            case .tag:
                return "WasmTag"
            }
        }

        func exportName(forIdx idx: Int) -> String {
            return switch self {
            case .function,
                 .suspendingObject:
                WasmLifter.nameOfFunction(idx)
            case .table:
                WasmLifter.nameOfTable(idx)
            case .memory:
                WasmLifter.nameOfMemory(idx)
            case .global:
                WasmLifter.nameOfGlobal(idx)
            case .tag:
                WasmLifter.nameOfTag(idx)
            case .import(let exp, _, _):
                "i\(exp.exportName(forIdx: idx))"
            }
        }

        func exportTypeByte() -> Int {
            switch self {
            case .function,
                 .suspendingObject:
                return 0x0
            case .table:
                return 0x1
            case .memory:
                return 0x2
            case .global:
                return 0x3
            case .tag:
                return 0x4
            case .import(let exp, _, _):
                return exp.exportTypeByte()
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
    private var instructionBuffer: Code = Code()

    // TODO(cffsmith): we could do some checking here that the function is actually defined, at that point it would not be static anymore though.
    private static func nameOfFunction(_ idx: Int) -> String {
        return "w\(idx)"
    }

    // TODO(cffsmith): we could do some checking here that the global is actually defined, at that point it would not be static anymore though.
    private static func nameOfGlobal(_ idx: Int) -> String {
        return "wg\(idx)"
    }

    private static func nameOfTable(_ idx: Int) -> String {
        return "wt\(idx)"
    }

    private static func nameOfTag(_ idx: Int) -> String {
        return "wex\(idx)"
    }

    private static func nameOfMemory(_ idx: Int) -> String {
        return "wm\(idx)"
    }

    // This tracks instructions that create exports of the specific ExportType.
    // This is later used to build parts of the export section.
    // The order here matches the order of the exports as seen by the ProgramBuilder, this is necessary so that we use the correct indices when emitting instructions.
    private var exports: [Export] = []

    private var dataSegments: [Instruction] = []
    private var elementSegments: [Instruction] = []

//    // The tags associated with this module.
//    private var tags: VariableMap<[ILType]> = VariableMap()

    private var typeGroups: Set<Int> = []
    private var freeTypes: Set<Variable> = []

    private var typeDescToIndex : [WasmTypeDescription:Int] = [:]
    private var userDefinedTypesCount = 0

    // The function index space
    private var functionIdxBase = 0

    // The signature index space.
    private var signatures : [WasmSignature] = []
    private var signatureIndexMap : [WasmSignature: Int] = [:]

    // This tracks in which order we have seen globals, this can probably be unified with the .globals and .imports properties, as they should match in their keys.
    private var globalOrder: [Variable] = []
    private var tagOrder: [Variable] = []

    public init(withTyper typer: JSTyper, withWasmCode instrs: Code) {
        self.typer = typer
        self.instructionBuffer = instrs
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
        return instructionBuffer.isEmpty &&
               self.bytecode.isEmpty &&
               self.exports.isEmpty
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
        init(_ signature: WasmSignature, _ code: Data, for lifter: WasmLifter, withArguments arguments: [Variable]) {
            // Infer the first few locals from this signature.
            self.signature = signature
            self.code = code
            self.localsInfo = [(Variable, ILType)]()
            self.lifter = lifter
            assert(signature.parameterTypes.count + 1 == arguments.count)
            // Populate the localsInfo with the parameter types.
            for (idx, argVar) in arguments.dropFirst().enumerated() {
                self.localsInfo.append((argVar, signature.parameterTypes[idx]))
                // Emit the expressions for the parameters such that we can accesss them if we need them.
                self.lifter!.writer.addExpr(for: argVar, bytecode: Data([0x20]) + Leb128.unsignedEncode(self.localsInfo.count - 1))
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
            self.localsInfo.contains(where: {$0.0 == variable})
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

    public func lift(binaryOutPath path: String? = nil) throws -> (Data, [Variable]) {
        // Lifting currently happens in three stages.
        // 1. Collect all necessary information to build all sections later on.
        //    - For now this only the importAnalysis, which needs to know how many imported vs internally defined types exist.
        // 2. Lift each instruction within its local context using all information needed from the previous analysis inside of a given function
        // 3. Use the already lifted functions to emit the whole Wasm byte buffer.

        // Step 1:
        // Collect all information that we need to later wire up the imports correctly, this means we look at instructions that can potentially import any variable that originated outside the Wasm module.
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
            for case let .function(functionInfo) in self.exports {
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

        // Export all functions by default.
        try self.buildExportedSection()

        // Build element segments for defined tables.
        try self.buildElementSection()

        try self.buildDataCountSection()

        // The actual bytecode of the functions.
        try self.buildCodeSection(self.instructionBuffer)

        try self.buildDataSection()

        // Write the bytecode as file to the given path for debugging purposes.
        if let path = path {
            let url = URL(fileURLWithPath: path)
            try? bytecode.write(to: url)
        }

        //
        // Step 3 done
        //

        return (bytecode, exports.compactMap { $0.getImport()?.variable })
    }

    private func buildHeader() {
        // Build the magic and the version of wasm we compile to.
        self.bytecode += [0x0]
        self.bytecode += "asm".data(using: .ascii)!

        // LE encoded 1 as the wasm version.
        self.bytecode += [0x1, 0x0, 0x0, 0x0]
    }

    private func encodeAbstractHeapType(_ heapType: WasmAbstractHeapType) -> Data {
        switch (heapType) {
            case .WasmExtern:
                return Data([0x6F])
            case .WasmFunc:
                return Data([0x70])
            case .WasmAny:
                return Data([0x6E])
            case .WasmEq:
                return Data([0x6D])
            case .WasmI31:
                return Data([0x6C])
            case .WasmStruct:
                return Data([0x6B])
            case .WasmArray:
                return Data([0x6A])
            case .WasmExn:
                return Data([0x69])
            case .WasmNone:
                return Data([0x71])
            case .WasmNoExtern:
                return Data([0x72])
            case .WasmNoFunc:
                return Data([0x73])
            case .WasmNoExn:
                return Data([0x74])
        }
    }

    private func encodeWasmGCType(_ description: WasmTypeDescription?) throws -> Data {
        guard let description else {
            throw WasmLifter.CompileError.missingTypeInformation
        }
        return Leb128.unsignedEncode(typeDescToIndex[description]!)
    }

    private func encodeType(_ type: ILType, defaultType: ILType? = nil) throws -> Data {
        if let refType = type.wasmReferenceType {
            let isNullable = refType.nullability
            let nullabilityByte: UInt8 = isNullable ? 0x63 : 0x64

            switch refType.kind {
            case .Index(let description):
                return try Data([nullabilityByte]) + encodeWasmGCType(description.get())
            case .Abstract(let heapType):
                return Data([nullabilityByte]) + encodeAbstractHeapType(heapType)
            }
        }
        // HINT: If you crash here, you might not have specified an encoding for your new type in `ILTypeMapping`.
        return ILTypeMapping[type] ?? ILTypeMapping[defaultType!]!
    }

    private func encodeHeapType(_ type: ILType, defaultType: ILType? = nil)  throws -> Data {
        if let refType = type.wasmReferenceType {
            switch refType.kind {
            case .Index(let description):
                return try encodeWasmGCType(description.get())
            case .Abstract(let heapType):
                return encodeAbstractHeapType(heapType)
            }
        }
        // HINT: If you crash here, you might not have specified an encoding for your new type in `ILTypeMapping`.
        return ILTypeMapping[type] ?? ILTypeMapping[defaultType!]!
    }

    private func buildTypeEntry(for desc: WasmTypeDescription, data: inout Data) throws {
        if let arrayDesc = desc as? WasmArrayTypeDescription {
            data += [0x5E]
            data += try encodeType(arrayDesc.elementType)
            data += [arrayDesc.mutability ? 1 : 0]
        } else if let structDesc = desc as? WasmStructTypeDescription {
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
        self.bytecode += [WasmSection.type.rawValue]

        var temp = Data()

        // Collect all signatures of imported functions, suspendable objects or tags.
        // See importAnalysis for more details.
        for signature in self.exports.compactMap({ $0.getImport()?.signature }) {
            registerSignature(signature)
        }

        // Special handling for defined Tags
        for case let .tag(instr) in self.exports {
            let tagSignature = (instr!.op as! WasmDefineTag).parameterTypes => []
            assert(tagSignature.outputTypes.isEmpty)
            registerSignature(tagSignature)
        }
        // Special handling for defined functions
        for case let .function(functionInfo) in self.exports {
            registerSignature(functionInfo!.signature)
        }

        let typeCount = self.signatures.count + typeGroups.count
        temp += Leb128.unsignedEncode(typeCount)

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
        // TODO(mliedtke): Also add "free types" which aren't in any explicit type group.

        for signature in self.signatures {
            temp += [0x60]
            temp += Leb128.unsignedEncode(signature.parameterTypes.count)
            for paramType in signature.parameterTypes {
                temp += try encodeType(paramType)
            }
            temp += Leb128.unsignedEncode(signature.outputTypes.count)
            for outputType in signature.outputTypes {
                temp += try encodeType(outputType, defaultType: .wasmExternRef)
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
        assert(signatures.count == signatureIndexMap.count)
        if signatureIndexMap[signature] != nil {
            return
        }
        let signatureIndex = userDefinedTypesCount + signatures.count
        signatures.append(signature)
        signatureIndexMap[signature] = signatureIndex
        assert(signatures.count == signatureIndexMap.count)
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
        if self.exports.compactMap({ $0.getImport() }).isEmpty {
            return
        }

        self.bytecode += [WasmSection.import.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.exports.count { $0.getImport() != nil })

        // Build the import components of this vector that consist of mod:name, nm:name, and d:importdesc
        for (idx, (_, importVariable, signature)) in self.exports.compactMap({ $0.getImport() }).enumerated() {
            if verbose {
                print(importVariable)
            }
            // Append the name as a vector
            temp += Leb128.unsignedEncode("imports".count)
            temp += "imports".data(using: .utf8)!
            var importName : String
            importName = "import_\(idx)_\(importVariable)"
            temp += Leb128.unsignedEncode(importName.count)
            temp += importName.data(using: .utf8)!
            let type = typer.type(of: importVariable)
            // This is a temporary workaround for functions that have been marked as suspendable.
            if type.Is(.function()) || type.Is(.object(ofGroup: "WasmSuspendingObject")) {
                if verbose {
                    print(functionIdxBase)
                }
                temp += [0x0] + Leb128.unsignedEncode(try getSignatureIndex(signature!))

                // Update the index space, these indices have to be set before the exports are set
                functionIdxBase += 1
                continue
            }
            if type.Is(.object(ofGroup: "WasmMemory")) {
                // Emit import type.
                temp += Data([0x2])

                let mem = type.wasmMemoryType!
                let limits_byte: UInt8 = (mem.isMemory64 ? 4 : 0) | (mem.isShared ? 2 : 0) | (mem.limits.max != nil ? 1 : 0);
                temp += Data([limits_byte])

                temp += Data(Leb128.unsignedEncode(mem.limits.min))
                if let maxPages = mem.limits.max {
                    temp += Data(Leb128.unsignedEncode(maxPages))
                }
                continue
            }
            if type.Is(.object(ofGroup: "WasmTable")) {
                // Emit import type.
                temp += Data([0x1])

                let table = type.wasmTableType!
                temp += try encodeType(table.elementType)

                let limits_byte: UInt8 = (table.isTable64 ? 4 : 0) | (table.limits.max != nil ? 1 : 0)
                temp += Data([limits_byte])

                temp += Data(Leb128.unsignedEncode(table.limits.min))
                if let maxSize = table.limits.max {
                    temp += Data(Leb128.unsignedEncode(maxSize))
                }
                continue
            }
            if type.Is(.object(ofGroup: "WasmGlobal")) {
                let valueType = type.wasmGlobalType!.valueType
                let mutability = type.wasmGlobalType!.isMutable
                temp += [0x3]
                temp += try encodeType(valueType)
                temp += mutability ? [0x1] : [0x0]
                continue
            }
            if type.Is(.object(ofGroup: "WasmTag")) {
                temp += [0x4, 0x0] + Leb128.unsignedEncode(try getSignatureIndex(signature!))
                continue
            }

            throw WasmLifter.CompileError.unknownImportType
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
        self.bytecode += [WasmSection.function.rawValue]

        // The number of functions we have, as this is a vector of type idxs.
        // TODO(cffsmith): functions can share type indices. This could be an optimization later on.
        var temp = Leb128.unsignedEncode(self.exports.count { $0.isFunction })

        for case let .function(functionInfo) in self.exports {
            temp.append(Leb128.unsignedEncode(try getSignatureIndex(functionInfo!.signature)))
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
        self.bytecode += [WasmSection.table.rawValue]

        var temp = Leb128.unsignedEncode(self.exports.count { $0.isTable })

        for case let .table(instruction) in self.exports {
            let op = instruction!.op as! WasmDefineTable
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

    // Only supports:
    // - passive & active segments
    // - with custom table id
    // - function-indices-as-elements (i.e. case 1 && 2 of the spec: https://webassembly.github.io/spec/core/binary/modules.html#element-section)
    // - one segment per table (assumes entries are continuous)
    // - constant starting index.
    private func buildElementSection() throws {
        let numDefinedTablesWithEntries = self.exports.count {
            if case let .table(instruction) = $0 {
                return !(instruction!.op as! WasmDefineTable).definedEntries.isEmpty
            } else {
                return false
            }
        }

        if numDefinedTablesWithEntries == 0  && elementSegments.count == 0 { return }

        self.bytecode += [WasmSection.element.rawValue]
        var temp = Data();

        // Element segment count.
        temp += Leb128.unsignedEncode(numDefinedTablesWithEntries + elementSegments.count);

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
        for case let .table(instruction) in self.exports {
            let table = instruction!.op as! WasmDefineTable
            let definedEntries = table.definedEntries
            assert(definedEntries.count == instruction!.inputs.count)
            if definedEntries.isEmpty { continue }
            // Element segment case 2 definition.
            temp += [0x02]
            let tableIndex = try self.resolveIdx(ofType: .table, for: instruction!.output)
            temp += Leb128.unsignedEncode(tableIndex)
            // Starting index. Assumes all entries are continuous.
            temp += table.isTable64 ? [0x42] : [0x41]
            temp += Leb128.unsignedEncode(definedEntries[0].indexInTable)
            temp += [0x0B]  // end
            // elemkind
            temp += [0x00]
            // entry count
            temp += Leb128.unsignedEncode(definedEntries.count)
            // entries
            for entry in instruction!.inputs {
                let functionIdx = try resolveIdx(ofType: .function, for: entry)
                temp += Leb128.unsignedEncode(functionIdx)
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

    private func buildCodeSection(_ instructions: Code) throws {
        // Build the contents of the section
        var temp = Data()
        temp += Leb128.unsignedEncode(self.exports.count { $0.isFunction })

        var functionBranchHints = [Data]()

        let functions = self.exports.filter({ $0.isFunction })

        let importedFunctionCount = self.exports.compactMap({$0.getImport()}).count {
            $0.type.isFunction
        }

        for (defIndex, export) in functions.enumerated() {
            guard case .function(let functionInfo) = export else {
                fatalError("unreachable")
            }

            if verbose {
                print("code is:")
                for byte in functionInfo!.code {
                    print(String(format: "%02X", byte))
                }
                print("end of code")
            }

            var funcTemp = Data()
            // TODO: this should be encapsulated more nicely. There should be an interface that gets the locals without the parameters. As this is currently mainly used to get the slots info.
            // Encode number of locals
            funcTemp += Leb128.unsignedEncode(functionInfo!.localsInfo.count - functionInfo!.signature.parameterTypes.count)
            for (_, type) in functionInfo!.localsInfo[functionInfo!.signature.parameterTypes.count...] {
                // Encode the locals
                funcTemp += Leb128.unsignedEncode(1)
                funcTemp += try encodeType(type)
            }
            let localsDefSizeInBytes = funcTemp.count
            // append the actual code and the end marker
            funcTemp += functionInfo!.code
            funcTemp += [0x0B]

            // Append the function object to the section
            temp += Leb128.unsignedEncode(funcTemp.count)
            temp += funcTemp

            // Encode the branch hint section entry for this function.
            if !functionInfo!.branchHints.isEmpty {
                // The function entry is the function index, followed by the counts of branch hints
                // for this function and then the bytes containing the actual branch hints.
                let functionIndex = defIndex + importedFunctionCount
                let hintsEncoded = Leb128.unsignedEncode(functionIndex)
                    + Leb128.unsignedEncode(functionInfo!.branchHints.count)
                    + functionInfo!.branchHints.map {
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
            let sectionContent = Leb128.unsignedEncode(name.count) + Data(name.data(using: .ascii)!)
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
        self.bytecode += [WasmSection.data.rawValue]

        var temp = Data()
        temp += Leb128.unsignedEncode(self.dataSegments.count)

        for instruction in self.dataSegments {
            let segment = (instruction.op as! WasmDefineDataSegment).segment
            temp += Data([0x01]) // mode = passive
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
        self.bytecode += [WasmSection.datacount.rawValue]

        var temp = Data()
        temp += Leb128.unsignedEncode(self.dataSegments.count)

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
        self.bytecode += [WasmSection.global.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.exports.count { $0.isGlobal })

        // TODO: in the future this should maybe be a context that allows instructions? Such that we can fuzz this expression as well?
        for case let .global(instruction) in self.exports {
            let definition = instruction!.op as! WasmDefineGlobal
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
                temp += try! Data([0xD0]) + encodeHeapType(.wasmExternRef) + Data([0x0B])
                continue
            case .exnref:
                temp += try! Data([0xD0]) + encodeHeapType(.wasmExnRef) + Data([0x0B])
                continue
            case .i31ref:
                temp += try! Data([0xD0]) + encodeHeapType(.wasmI31Ref) + Data([0x0B])
                continue
            case .refFunc(_),
                 .imported(_):
                fatalError("unreachable")
            }
            temp += try lift(temporaryInstruction!)
            temp += Data([0x0B])
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
        self.bytecode += [WasmSection.memory.rawValue]

        var temp = Data()

        // The amount of memories we have, per standard this can currently only be one, either defined or imported
        // https://webassembly.github.io/spec/core/syntax/modules.html#memories
        temp += Leb128.unsignedEncode(self.exports.count { $0.isMemory })

        for case let .memory(instruction) in self.exports {
            let type = typer.type(of: instruction!.output)
            assert(type.isWasmMemoryType)
            let mem = type.wasmMemoryType!

            let limits_byte: UInt8 = (mem.isMemory64 ? 4 : 0) | (mem.isShared ? 2 : 0) | (mem.limits.max != nil ? 1 : 0);
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
        if self.exports.count(where: { $0.isTag }) == 0 {
            return // Skip the whole section.
        }

        self.bytecode.append(WasmSection.tag.rawValue)
        var section = Data()

        section += Leb128.unsignedEncode(self.exports.count { $0.isTag })

        for case let .tag(instr) in self.exports {
            let tagSignature = (instr!.op as! WasmDefineTag).parameterTypes => []
            section.append(0)
            section.append(Leb128.unsignedEncode(try getSignatureIndex(tagSignature)))
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

    // Export all imports and defined things by default.
    private func buildExportedSection() throws {
        self.bytecode += [WasmSection.export.rawValue]

        var temp = Data()

        // The number of all exports.
        temp += Leb128.unsignedEncode(self.exports.count)

        // The offset can be used to shift the internally defined functions up
        // While still maintaining their name, e.g. iw0, and w0 will co-exist.
        func writeExportData(_ export: Export, _ idx: Int, offset: Int = 0) {
            let name = export.exportName(forIdx: idx)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            // Add the base, as our exports start after the imports. This variable needs to be incremented in the `buildImportSection` function.
            temp += Leb128.unsignedEncode(export.exportTypeByte()) + Leb128.unsignedEncode(idx + offset)
        }

        // The predicate is used to filter for only a specific type of import.
        let reexportAndExport: ((Export) -> Bool) -> () = { predicate in
            let imported = self.exports.filter({
                $0.getImport() != nil && predicate($0.getImport()!.type)
            })

            for (idx, imp) in imported.enumerated() {
                // Append the name as a vector
                // Here for the name, we use the index as remembered by the globalsOrder array, to preserve the export order with what the typer of the ProgramBuilder has seen before.
                writeExportData(imp, idx)
            }

            let defined = self.exports.filter { predicate($0) }

            for (idx, exp) in defined.enumerated() {
                writeExportData(exp, idx, offset: imported.count)
            }
        }

        reexportAndExport {
            $0.isFunction
        }
        reexportAndExport {
            $0.isGlobal
        }
        reexportAndExport {
            $0.isTable
        }
        reexportAndExport {
            $0.isMemory
        }
        reexportAndExport {
            $0.isTag
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

    /// This function updates the internal state of the lifter before actually emitting code to the wasm module. This should be invoked before we try to get the corresponding bytes for the Instruction
    private func updateLifterState(wasmInstruction instr: Instruction) -> Bool {
        // Make sure that we actually have a Wasm operation here.
        assert(instr.op is WasmOperation)

        switch instr.op.opcode {
        case .wasmBeginBlock(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginIf(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginElse(_):
            // Note: We need to subtract one because the begin else block closes the if block before opening the else block!
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmBeginTryTable(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginTry(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginTryDelegate(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginLoop(let op):
            registerSignature(op.signature)
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            // Needs typer analysis
            return true
        case .wasmBeginCatch(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(1)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmBeginCatchAll(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmCallIndirect(let op):
            registerSignature(op.signature)
            return true
        case .wasmReturnCallIndirect(let op):
            registerSignature(op.signature)
            return true
        case .wasmNop(_):
            // Just analyze the instruction but do nothing else here.
            // This lets the typer know that we can skip this instruction without breaking any analysis.
            break
        case .beginWasmFunction(let op):
            let functionInfo = FunctionInfo(op.signature, Data(), for: self, withArguments: Array(instr.innerOutputs))
            self.exports.append(.function(functionInfo))
            // Set the current active function as we are *actively* in it.
            currentFunction = functionInfo
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
        case .endWasmFunction(_):
            currentFunction!.outputVariable = instr.output
            return true
        case .wasmDefineGlobal(_):
            assert(self.exports.contains(where: {
                $0.isGlobal && $0.getDefInstr()!.output == instr.output
            }))
        case .wasmDefineTable(_):
            assert(self.exports.contains(where: {
                $0.isTable && $0.getDefInstr()!.output == instr.output
            }))
        case .wasmDefineMemory(_):
            assert(self.exports.contains(where: {
                $0.isMemory && $0.getDefInstr()!.output == instr.output
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
            assert(self.exports.contains(where: {
                if case .tag(let i) = $0 {
                    return i!.output == instr.output
                } else {
                    return false
                }
            }))
            assert(self.exports.contains(where: {
                $0.isTag && $0.getDefInstr()!.output == instr.output
            }))
        default:
            return true
        }

        return false
    }

    // requires that the instr has been analyzed before. Maybe assert that?
    private func emitInputLoadsIfNecessary(forInstruction instr: Instruction) {
        // Don't emit loads for reassigns. This is specially handled in the `lift` function for reassigns.
        if instr.op is WasmReassign {
            return
        }

        // Check if instruction input is a parameter or if we have an expression for it, if so, we need to load it now.
        for input in instr.inputs {
            // Skip "internal" inputs, i.e. ones that don't map to a slot, such as .label variables
            let inputType = typer.type(of: input)
            if inputType.Is(.anyLabel) || inputType.Is(.exceptionLabel) {
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
        // Don't emit spills for reassigns. This is specially handled in the `lift` function for reassigns.
        // Similarly, the end of a function doesn't spill anything.
        if instr.op is WasmReassign || instr.op is EndWasmFunction {
            return
        }

        // If we have an output, make sure we store it on the stack as this is a "complex" instruction, i.e. has inputs and outputs.
        if instr.numOutputs > 0 {
            assert(instr.outputs.allSatisfy {!typer.type(of: $0).Is(.anyLabel)})
            for output in instr.outputs.reversed() {
                // Also spill the instruction
                currentFunction!.spillLocal(forVariable: output)
                // Add the corresponding stack load as an expression, this adds the number of arguments, as output vars always live after the function arguments.
                self.writer.addExpr(for: output, bytecode: Data([0x20]) + Leb128.unsignedEncode(currentFunction!.localsInfo.count - 1))
            }
        }

        if instr.op.attributes.contains(.isBlockStart) {
            // As the parameters are pushed "in order" to the stack, they need to be popped in reverse order.
            for innerOutput in instr.innerOutputs.reversed() {
                let t = typer.type(of: innerOutput)
                if !t.Is(.anyLabel) && !t.Is(.exceptionLabel) {
                    currentFunction!.spillLocal(forVariable: innerOutput)
                }
            }
        }
    }

    private func importIfNeeded(_ imp: Export) {
        guard case .import(let type, let variable, let signature) = imp else {
            fatalError("This needs an import.")
        }

        // Check if we define this variable in Wasm, i.e. it is defined.
        if self.exports.contains(where: { exp in
            exp.getDefInstr()?.output == variable
        }) {
            return
        }

        // Check all imports to see if we have this already.
        let imports = self.exports.compactMap { $0.getImport() }

        // We also need a signature for this import to distinguish it from other imports.
        if type.isFunction || type.isSuspendingObject {
            if !imports.contains(where: {
                if let otherSig = $0.signature {
                    $0.variable == variable && otherSig == signature
                } else {
                    false
                }
            }) {
                self.exports.append(imp)
            }

            return
        }


        // Now check for generic imports that we can just import as is without using a signature.
        if !imports.contains(where: {
            // if we have a signature, we need to make sure that create a new import with that signature.
            $0.variable == variable
        }) {
            self.exports.append(imp)
        }
    }

    // Analyze which Variables should be imported. Here we should analyze all instructions that could potentially force an import of a Variable that originates in JavaScript.
    // This usually means if your instruction takes an .object() as an input, it should be checked here.
    // TODO: check if this is still accurate as we now only have defined imports.
    // Also, we export the globals in the order we "see" them, which might mismatch the order in which they are laid out in the binary at the end, which is why we track the order of the globals separately.
    private func importAnalysis() throws {
        for instr in self.instructionBuffer {
            for (idx, input) in instr.inputs.enumerated() {
                let inputType = typer.type(of: input)

                if inputType.Is(.wasmTypeDef()) || inputType.Is(.wasmRef(.Index(), nullability: true)) {
                    let typeDesc = typer.getTypeDescription(of: input)
                    if typeDesc.typeGroupIndex != -1 {
                        // Add typegroups and their dependencies.
                        if typeGroups.insert(typeDesc.typeGroupIndex).inserted {
                            typeGroups.formUnion(typer.getTypeGroupDependencies(typeGroupIndex: typeDesc.typeGroupIndex))
                        }
                    } else {
                        freeTypes.insert(input)
                    }
                }

                for importType in [Export.table(nil), Export.memory(nil), Export.global(nil)] {
                    if inputType.Is(.object(ofGroup: importType.groupName())) {
                        importIfNeeded(.import(type: importType, variable: input, signature: nil))
                    }
                }

                // Special handling for tag
                // TODO: Can we just use .isWasmTagType?
                if inputType.Is(.object(ofGroup: "WasmTag")) {
                    // We need the tag parameters here or we need to bail.
                    if !inputType.isWasmTagType {
                        throw WasmLifter.CompileError.missingTypeInformation
                    }
                    // TODO: This now uses the typer here but the op also carries this information?
                    importIfNeeded(.import(type: .tag(nil), variable: input, signature: inputType.wasmTagType!.parameters => []))
                }

                // Special handling for functions, we only expect them in WasmJSCalls, and WasmDefineTable instructions right now.
                // We can treat the suspendingObjects as function imports.
                if inputType.Is(.function()) || inputType.Is(.object(ofGroup: "WasmSuspendingObject")) {
                    if case .wasmJsCall(let op) = instr.op.opcode {
                        importIfNeeded(.import(type: .function(nil), variable: input, signature: op.functionSignature))
                    } else if case .wasmDefineTable(let op) = instr.op.opcode {
                        // Find the signature in the defined entries
                        let sig = op.definedEntries[idx].signature
                        importIfNeeded(.import(type: .function(nil), variable: input, signature: sig))
                    } else {
                        // This instruction has likely expected some .object() of a specific group, as this variable can originate from outside wasm, it might have been reassigned to. Which means we will enter this path.
                        // Therefore we need to bail.
                        throw CompileError.invalidInput
                    }
                }
            }

            // The output handling needs to match on specific opcodes, it cannot just look at the output type as that might've been propagated.
            switch instr.op.opcode {
            case .wasmDefineGlobal(_):
                self.exports.append(.global(instr))
            case .wasmDefineTable(let tableDef):
                self.exports.append(.table(instr))
                if tableDef.elementType == .wasmFuncRef {
                    for (value, definedEntry) in zip(instr.inputs, tableDef.definedEntries) {
                        if !typer.type(of: value).Is(.wasmFunctionDef()) {
                            // Check if we need to import the inputs.
                            importIfNeeded(.import(type: .function(nil), variable: value, signature: definedEntry.signature))
                        }
                    }
                }
            case .wasmDefineMemory(_):
                self.exports.append(.memory(instr))
            case .wasmDefineTag(_):
                self.exports.append(.tag(instr))

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
    }

    /// Describes the types of indexes in the different index spaces in the Wasm binary format.
    public enum IndexType {
        case global
        case table
        case memory
        case tag
        case function

        func matches(_ export: Export) -> Bool {
            switch self {
            case .global:
                return export.isGlobal
            case .table:
                return export.isTable
            case .memory:
                return export.isMemory
            case .tag:
                return export.isTag
            case .function:
                return export.isFunction || export.isSuspendingObject

            }
        }
    }

    /// Helper function to resolve the index (as laid out in the binary format) of an instruction input Variable of a specific `IndexType`
    /// Intended to be called from `lift`.
    func resolveIdx(ofType importType: IndexType, for input: Variable) throws -> Int {
        // The imports of the requested type.
        let imports = self.exports.compactMap({
            $0.getImport()
        }).filter({
            importType.matches($0.type)
        })

        // Now get the index in this "import space"
        if let idx =  imports.firstIndex(where: {
            $0.variable == input
        }) {
            return idx
        }

        // This is the defined space, i.e. where the type matches the predicate directly.
        let idx = self.exports.filter({ importType.matches($0) }).firstIndex(where: { export in
            // Functions don't have a defining instruction and as such have special handling here.
            if case .function(let fInfo) = export {
                fInfo!.outputVariable == input
            } else {
                export.getDefInstr()!.output == input
            }
        })

        if let idx = idx {
            return imports.count + idx
        }

        throw WasmLifter.CompileError.failedIndexLookUp
    }

    func resolveDataSegmentIdx(for input: Variable) -> Int {
        dataSegments.firstIndex {$0.output == input}!
    }

    func resolveElementSegmentIdx(for input: Variable) -> Int {
        elementSegments.firstIndex {$0.output == input}!
    }

    // The memory immediate argument, which encodes the alignment and memory index.
    // For memory 0, this is just the alignment. For other memories, a flag is set
    // and the memory index is also encoded.
    // Memory zero: `[align]`.
    // Multi-memory: `[align | 0x40] + [mem_idx]`.
    private func alignmentAndMemoryBytes(_ memory: Variable, alignment: Int64 = 1) throws -> Data {
        assert(alignment > 0 && (alignment & (alignment - 1)) == 0, "Alignment must be a power of two")
        let memoryIdx = try resolveIdx(ofType: .memory, for: memory)


        let alignmentLog2 = alignment.trailingZeroBitCount
        assert(alignmentLog2 < 0x40, "Alignment \(alignment) is too large for multi-memory encoding")

        if memoryIdx == 0 {
            return Leb128.unsignedEncode(alignmentLog2)
        } else {
            let flags = UInt8(alignmentLog2) | 0x40
            return Data([flags]) + Leb128.unsignedEncode(memoryIdx)
        }
    }

    private func branchDepthFor(label: Variable) throws -> Int {
        guard let labelDepth = self.currentFunction!.labelBranchDepthMapping[label] else {
            throw CompileError.fatalError("No branch depth information for label \(label)")
        }
        return self.currentFunction!.variableAnalyzer.wasmBranchDepth - labelDepth - 1
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
        case .wasmStoreGlobal(_):

            // Get the index for the global and emit it here magically.
            // The first input has to be in the global or imports arrays.
            let input = wasmInstruction.input(0)
            return Data([0x24]) + Leb128.unsignedEncode(try resolveIdx(ofType: .global, for: input))
        case .wasmTableGet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x25]) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableSet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x26]) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableSize(_):
            let tableRef = wasmInstruction.input(0)
            // Value 0x10 is table.size opcode
            return Data([Prefix.Numeric.rawValue]) + Leb128.unsignedEncode(0x10) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmTableGrow(_):
            let tableRef = wasmInstruction.input(0)
            // Value 0x0f is table.grow opcode
            return Data([Prefix.Numeric.rawValue]) + Leb128.unsignedEncode(0x0f) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmCallIndirect(let op):
            let tableRef = wasmInstruction.input(0)
            let sigIndex = try getSignatureIndex(op.signature)
            return Data([0x11]) + Leb128.unsignedEncode(sigIndex) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmCallDirect(_):
            let functionRef = wasmInstruction.input(0)
            return Data([0x10]) + Leb128.unsignedEncode(try resolveIdx(ofType: .function, for: functionRef))
        case .wasmReturnCallDirect(_):
            let functionRef = wasmInstruction.input(0)
            return Data([0x12]) + Leb128.unsignedEncode(try resolveIdx(ofType: .function, for: functionRef))
        case .wasmReturnCallIndirect(let op):
            let tableRef = wasmInstruction.input(0)
            let sigIndex = try getSignatureIndex(op.signature)
            return Data([0x13]) + Leb128.unsignedEncode(sigIndex) + Leb128.unsignedEncode(try resolveIdx(ofType: .table, for: tableRef))
        case .wasmMemoryLoad(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([op.loadType.rawValue]) + alignAndMemory + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmMemoryStore(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            let opCode = Data(op.storeType != .S128StoreMem
                ? [op.storeType.rawValue]
                : [Prefix.Simd.rawValue, op.storeType.rawValue])
            return opCode + alignAndMemory + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmAtomicLoad(let op):
            let opcode = [Prefix.Atomic.rawValue, op.loadType.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0), alignment: op.loadType.naturalAlignment())
            return Data(opcode) + alignAndMemory + Leb128.signedEncode(Int(op.offset))

        case .wasmAtomicStore(let op):
            let opcode = [Prefix.Atomic.rawValue, op.storeType.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0), alignment: op.storeType.naturalAlignment())
            return Data(opcode) + alignAndMemory + Leb128.signedEncode(Int(op.offset))
        case .wasmAtomicRMW(let op):
            let opcode = [Prefix.Atomic.rawValue, op.op.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0), alignment: op.op.naturalAlignment())
            return Data(opcode) + alignAndMemory + Leb128.signedEncode(Int(op.offset))
        case .wasmAtomicCmpxchg(let op):
            let opcode = [Prefix.Atomic.rawValue, op.op.rawValue]
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0), alignment: op.op.naturalAlignment())
            return Data(opcode) + alignAndMemory + Leb128.signedEncode(Int(op.offset))
        case .wasmMemorySize(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0x3F]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryGrow(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0x40]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryCopy(_):
            let dstMemIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            let srcMemIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0A]) + Leb128.unsignedEncode(dstMemIdx) + Leb128.unsignedEncode(srcMemIdx)
        case .wasmMemoryFill(_):
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(0))
            return Data([0xFC, 0x0B]) + Leb128.unsignedEncode(memoryIdx)
        case .wasmMemoryInit(_):
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(0))
            let memoryIdx = try resolveIdx(ofType: .memory, for: wasmInstruction.input(1))
            return Data([0xFC, 0x08]) + Leb128.unsignedEncode(dataSegmentIdx) + Leb128.unsignedEncode(memoryIdx)
        case .wasmDropDataSegment(_):
            let dataSegmentIdx = resolveDataSegmentIdx(for: wasmInstruction.input(0))
            return Data([0xFC, 0x09]) + Leb128.unsignedEncode(dataSegmentIdx)
        case .wasmDropElementSegment(_):
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(0))
            return Data([0xFC, 0x0d]) + Leb128.unsignedEncode(elementSegmentIdx)
        case .wasmTableInit(_):
            let elementSegmentIdx = resolveElementSegmentIdx(for: wasmInstruction.input(0))
            let tableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0c]) + Leb128.unsignedEncode(elementSegmentIdx) + Leb128.unsignedEncode(tableIdx)
        case .wasmTableCopy(_):
            let dstTableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(0))
            let srcTableIdx = try resolveIdx(ofType: .table, for: wasmInstruction.input(1))
            return Data([0xFC, 0x0e]) + Leb128.unsignedEncode(dstTableIdx) + Leb128.unsignedEncode(srcTableIdx)
        case .wasmJsCall(let op):
            // We filter first, such that we get the index of functions only.
            let wasmSignature = op.functionSignature

            // This has somewhat special handling as we might have multiple imports for this variable, we also need to get the right index that matches that signature that we expect here.
            // TODO(cffsmith): consider adding that signature matching feature to resolveIdx.
            if let index = self.exports.filter({
                if let imp = $0.getImport() {
                    return imp.type.isFunction || imp.type.isSuspendingObject
                } else {
                    return false
                }
            }).firstIndex(where: {
                wasmInstruction.input(0) == $0.getImport()!.variable && wasmSignature == $0.getImport()!.signature
            }) {
                return Data([0x10]) + Leb128.unsignedEncode(index)
            } else {
                throw WasmLifter.CompileError.failedIndexLookUp
            }
        case .wasmBeginBlock(let op):
            // A Block can "produce" (push) an item on the value stack, just like a function. Similarly, a block can also have parameters.
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#binary-blocktype
            return Data([0x02] + Leb128.unsignedEncode(getSignatureIndexStrict(op.signature)))
        case .wasmBeginLoop(let op):
            return Data([0x03] + Leb128.unsignedEncode(getSignatureIndexStrict(op.signature)))
        case .wasmBeginTryTable(let op):
            var inputIndex = op.signature.parameterTypes.count
            let catchTable: Data = try op.catches.map {
                    switch $0 {
                    case .Ref, .NoRef:
                        let tag = try resolveIdx(ofType: .tag, for: wasmInstruction.input(inputIndex))
                        let depth = try branchDepthFor(label: wasmInstruction.input(inputIndex + 1)) - 1
                        let result = Data([$0.rawValue]) + Leb128.unsignedEncode(tag) + Leb128.unsignedEncode(depth)
                        inputIndex += 2
                        return result
                    case .AllRef, .AllNoRef:
                        let depth = try branchDepthFor(label: wasmInstruction.input(inputIndex)) - 1
                        inputIndex += 1
                        return Data([$0.rawValue]) + Leb128.unsignedEncode(depth)
                    }
                }.reduce(Data(), +)
            return [0x1F]
                + Leb128.unsignedEncode(signatureIndexMap[op.signature]!)
                + Leb128.unsignedEncode(op.catches.count)
                + catchTable
        case .wasmBeginTry(let op):
            return Data([0x06] + Leb128.unsignedEncode(getSignatureIndexStrict(op.signature)))
        case .wasmBeginTryDelegate(let op):
            return Data([0x06] + Leb128.unsignedEncode(getSignatureIndexStrict(op.signature)))
        case .wasmBeginCatchAll(_):
            return Data([0x19])
        case .wasmBeginCatch(_):
            return Data([0x07] + Leb128.unsignedEncode(try resolveIdx(ofType: .tag, for: wasmInstruction.input(0))))
        case .wasmEndLoop(_),
                .wasmEndIf(_),
                .wasmEndTryTable(_),
                .wasmEndTry(_),
                .wasmEndBlock(_):
            // Basically the same as EndBlock, just an explicit instruction.
            return Data([0x0B])
        case .wasmEndTryDelegate(_):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            // Mutation might make this EndTryDelegate branch to itself, which should not happen.
            if branchDepth < 0 {
                throw WasmLifter.CompileError.invalidBranch
            }
            return Data([0x18]) + Leb128.unsignedEncode(branchDepth)
        case .wasmThrow(_):
            return Data([0x08] + Leb128.unsignedEncode(try resolveIdx(ofType: .tag, for: wasmInstruction.input(0))))
        case .wasmThrowRef(_):
            return Data([0x0A])
        case .wasmRethrow(_):
            let blockDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x09] + Leb128.unsignedEncode(blockDepth))
        case .wasmBranch(let op):
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x0C]) + Leb128.unsignedEncode(branchDepth) + Data(op.labelTypes.map {_ in 0x1A})
        case .wasmBranchIf(let op):
            currentFunction!.addBranchHint(op.hint)
            let branchDepth = try branchDepthFor(label: wasmInstruction.input(0))
            return Data([0x0D]) + Leb128.unsignedEncode(branchDepth) + Data(op.labelTypes.map {_ in 0x1A})
        case .wasmBranchTable(let op):
            let depths = try (0...op.valueCount).map {
                try branchDepthFor(label: wasmInstruction.input($0))
            }
            return Data([0x0E]) + Leb128.unsignedEncode(op.valueCount) + depths.map(Leb128.unsignedEncode).joined()
        case .wasmBeginIf(let op):
            currentFunction!.addBranchHint(op.hint)
            let beginIf = Data([0x04] + Leb128.unsignedEncode(try getSignatureIndex(op.signature)))
            // Invert the condition with an `i32.eqz` (resulting in 0 becoming 1 and everything else becoming 0).
            return op.inverted ? Data([0x45]) + beginIf : beginIf
        case .wasmBeginElse(_):
            // 0x05 is the else block instruction.
            return Data([0x05])
        case .wasmReassign(_):
            // wasmReassign is quite special, it needs to work for variables stored in various places, e.g. local slots or even globals. As such the lifting here first needs to locate the destination variable.
            var out = Data()

            var storeInstruction = Data()
            // If the variable is a local, we load the stack slot.
            // Check for the stack location of the `to` variable.
            if let stackSlot = currentFunction!.getStackSlot(for: wasmInstruction.input(0)) {

                // Emit the instruction now, with input and stackslot. Since we load this manually we don't need
                // to emit bytes in the emitInputLoadsIfNecessary.
                storeInstruction = Data([0x21]) + Leb128.unsignedEncode(stackSlot)
            } else {
                // It has to be global then. Do what StoreGlobal does.
                storeInstruction = Data([0x24]) + Leb128.unsignedEncode(try resolveIdx(ofType: .global, for: wasmInstruction.input(0)))
            }

            // Load the input now. For "internal" variables, we should not have an expression.
            if let expr = self.writer.getExpr(for: wasmInstruction.input(1)) {
                out += expr
            } else if let stackSlot = currentFunction!.getStackSlot(for: wasmInstruction.input(1)) {
                out += Data([0x20]) + Leb128.unsignedEncode(stackSlot)
            } else {
                // Has to be a global then. Do what LoadGlobal does.
                out += Data([0x23]) + Leb128.unsignedEncode(try resolveIdx(ofType: .global, for: wasmInstruction.input(1)))
            }

            return out + storeInstruction
        case .wasmNop(_):
            return Data([0x01])
        case .wasmUnreachable(_):
            return Data([0x00])
        case .wasmSelect(_):
            return try Data([0x1c, 0x01]) + encodeType(typer.type(of: wasmInstruction.input(0)))
        case .constSimd128(let op):
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(12) + Data(op.value)
        case .wasmSimd128IntegerUnOp(let op):
            assert(WasmSimd128IntegerUnOpKind.allCases.count == 17, "New WasmSimd128IntegerUnOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerUnOp")
            }
            var encoding = Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(base + op.unOpKind.rawValue)
            // For most of the instructions we have to add another 0x01 byte add the end of the encoding.
            switch op.shape {
                case .i8x16:
                    break
                case .i16x8, .i32x4, .i64x2: switch op.unOpKind {
                    case .extadd_pairwise_i8x16_s,
                         .extadd_pairwise_i8x16_u:
                        break
                    default:
                        encoding += Leb128.unsignedEncode(0x01)
                }
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerUnOp")
            }
            return encoding
        case .wasmSimd128IntegerBinOp(let op):
            assert(WasmSimd128IntegerBinOpKind.allCases.count == 26, "New WasmSimd128IntegerBinOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerBinOp")
            }
            var encoding =  Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(base + op.binOpKind.rawValue)
            // Apart from .i8x16 shape, the encoding has another 0x01 byte at the end of the encoding.
            if (op.shape != .i8x16) {
                encoding += Leb128.unsignedEncode(0x01)
            }
            return encoding
        case .wasmSimd128IntegerTernaryOp(let op):
            assert(WasmSimd128IntegerTernaryOpKind.allCases.count == 2, "New WasmSimd128IntegerTernaryOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .i8x16: 0x100
                case .i16x8: 0x101
                case .i32x4: 0x102
                case .i64x2: 0x103
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerTernaryOp")
            }
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(base + op.ternaryOpKind.rawValue) + Leb128.unsignedEncode(0x01)
        case .wasmSimd128FloatUnOp(let op):
            assert(WasmSimd128FloatUnOpKind.allCases.count == 7, "New WasmSimd128FloatUnOpKind added: check if the encoding is still correct!")
            let encoding = switch op.shape {
                case .f32x4: switch op.unOpKind {
                    case .ceil: Leb128.unsignedEncode(0x67)
                    case .floor: Leb128.unsignedEncode(0x68)
                    case .trunc: Leb128.unsignedEncode(0x69)
                    case .nearest: Leb128.unsignedEncode(0x6A)
                    case .abs: Leb128.unsignedEncode(0xE0) + Leb128.unsignedEncode(0x01)
                    case .neg: Leb128.unsignedEncode(0xE1) + Leb128.unsignedEncode(0x01)
                    case .sqrt: Leb128.unsignedEncode(0xE3) + Leb128.unsignedEncode(0x01)
                }
                case .f64x2: switch op.unOpKind {
                    case .ceil: Leb128.unsignedEncode(0x74)
                    case .floor: Leb128.unsignedEncode(0x75)
                    case .trunc: Leb128.unsignedEncode(0x7A)
                    case .nearest: Leb128.unsignedEncode(0x94) + Leb128.unsignedEncode(0x01)
                    case .abs: Leb128.unsignedEncode(0xEC) + Leb128.unsignedEncode(0x01)
                    case .neg: Leb128.unsignedEncode(0xED) + Leb128.unsignedEncode(0x01)
                    case .sqrt: Leb128.unsignedEncode(0xEF) + Leb128.unsignedEncode(0x01)
                }
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128FloatUnOp")
            }
            return Data([Prefix.Simd.rawValue]) + encoding
        case .wasmSimd128FloatBinOp(let op):
            assert(WasmSimd128FloatBinOpKind.allCases.count == 10, "New WasmSimd128FloatBinOpKind added: check if the encoding is still correct!")
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(op.getOpcode()) + Leb128.unsignedEncode(0x01)
        case .wasmSimd128FloatTernaryOp(let op):
            assert(WasmSimd128FloatTernaryOpKind.allCases.count == 2, "New WasmSimd128FloatTernaryOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .f32x4: 0x100
                case .f64x2: 0x102
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128FloatTernaryOp")
            }
            return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(base + op.ternaryOpKind.rawValue) + Leb128.unsignedEncode(0x01)
        case .wasmSimd128Compare(let op):
            assert(WasmIntegerCompareOpKind.allCases.count == 10, "New WasmIntegerCompareOpKind added: check if the encoding is still correct!")
            assert(WasmFloatCompareOpKind.allCases.count == 6, "New WasmFloatCompareOpKind added: check if the encoding is still correct!")
            switch op.shape {
            case .i8x16:
                return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0x23 + op.compareOpKind.toInt())
            case .i16x8:
                return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0x2D + op.compareOpKind.toInt())
            case .i32x4:
                return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0x37 + op.compareOpKind.toInt())
            case .i64x2:
                if case .iKind(let value) = op.compareOpKind {
                    let temp = switch value {
                        case .Eq: 0
                        case .Ne: 1
                        case .Lt_s: 2
                        case .Gt_s: 3
                        case .Le_s: 4
                        case .Ge_s: 5
                        default: fatalError("Shape \(op.shape) does not have \(op.compareOpKind) instruction")
                    }
                    return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0xD6 + temp) + Leb128.unsignedEncode(0x01)
                }
                fatalError("unreachable")
            case .f32x4:
                return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0x41 + op.compareOpKind.toInt())
            case .f64x2:
                return Data([Prefix.Simd.rawValue]) + Leb128.unsignedEncode(0x47 + op.compareOpKind.toInt())
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
                + Leb128.signedEncode(Int(op.staticOffset)) + Leb128.unsignedEncode(op.lane)
        case .wasmSimdLoadLane(let op):
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + alignAndMemory
                + Leb128.signedEncode(Int(op.staticOffset)) + Leb128.unsignedEncode(op.lane)
         case .wasmSimdLoad(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            let alignAndMemory = try alignmentAndMemoryBytes(wasmInstruction.input(0))
            return Data([Prefix.Simd.rawValue, op.kind.rawValue]) + alignAndMemory + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmArrayNewFixed(let op):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x08]) + arrayIndex + Leb128.unsignedEncode(op.size)
        case .wasmArrayNewDefault(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x07]) + arrayIndex
        case .wasmArrayLen(_):
            return Data([Prefix.GC.rawValue, 0x0F])
        case .wasmArrayGet(let op):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0)) as! WasmArrayTypeDescription
            let opCode: UInt8 = typeDesc.elementType.isPacked() ? (op.isSigned ? 0x0C : 0x0D) : 0x0B
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, opCode]) + arrayIndex
        case .wasmArraySet(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let arrayIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x0E]) + arrayIndex
        case .wasmStructNewDefault(_):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0))
            let structIndex = Leb128.unsignedEncode(typeDescToIndex[typeDesc]!)
            return Data([Prefix.GC.rawValue, 0x01]) + structIndex
        case .wasmStructGet(let op):
            let typeDesc = typer.getTypeDescription(of: wasmInstruction.input(0)) as! WasmStructTypeDescription
            let opCode: UInt8 = typeDesc.fields[op.fieldIndex].type.isPacked() ? (op.isSigned ? 0x03 : 0x04) : 0x02
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
        case .wasmRefI31(_):
            return Data([Prefix.GC.rawValue, 0x1C])
        case .wasmI31Get(let op):
            let opCode: UInt8 = op.isSigned ? 0x1D : 0x1E
            return Data([Prefix.GC.rawValue, opCode])
        case .wasmAnyConvertExtern(_):
            return Data([Prefix.GC.rawValue, 0x1A])
        case .wasmExternConvertAny(_):
            return Data([Prefix.GC.rawValue, 0x1B])

        default:
             fatalError("unreachable")
        }
    }
}
