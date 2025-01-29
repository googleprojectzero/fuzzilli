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

// This maps ILTypes to their respective binary encoding.
private let ILTypeMapping: [ILType: Data] = [
    .wasmi32 : Data([0x7f]),
    .wasmi64 : Data([0x7e]),
    .wasmf32 : Data([0x7D]),
    .wasmf64 : Data([0x7C]),
    .wasmExternRef: Data([0x6f]),
    .wasmFuncRef: Data([0x70]),
    .wasmSimd128: Data([0x7B]),

    .bigint  : Data([0x7e]), // Maps to .wasmi64
    .anything: Data([0x6f]), // Maps to .wasmExternRef
    .integer: Data([0x7f]), // Maps to .wasmi32
    .number: Data([0x7d]) // Maps to .wasmf32
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
    public static func nameOfFunction(_ idx: Int) -> String {
        return "w\(idx)"
    }

    // TODO(cffsmith): we could do some checking here that the global is actually defined, at that point it would not be static anymore though.
    public static func nameOfGlobal(_ idx: Int) -> String {
        return "wg\(idx)"
    }

    public static func nameOfTable(_ idx: Int) -> String {
        return "wt\(idx)"
    }

    // This contains imports, i.e. WasmJsCall arguments, tables, globals and memories that are not defined in this module. We need to track them here so that we can properly wire up the imports when lifting this module.
    // The Signature is only valid if the Variable is the argument to a WasmJsCall instruction, it is the Signature contained in the instruction. This Signature that is in the instruction is a loose approximation of the JS Signature, it depends on available Wasm types at the time when it was generated.
    private var imports: [(Variable, Signature?)] = []

    // This tracks instructions that define globals in this module. We track the instruction as all the information, as well as the actual value for initialization is stored in the Operation instead of the Variable.
    private var globals: [Instruction] = []

    // This tracks instructions that define memories in this module. We track the instruction here as the limits are also encoded in the Operation.
    private var memories: [Instruction] = []

    // This tracks instructions that define tables in this module. We track the instruction here as the table type and its limits are encoded in the Operation.
    private var tables: [Instruction] = []

    // The tags associated with this module.
    private var tags: VariableMap<ParameterList> = VariableMap()

    // The function index space
    private var functionIdxBase = 0

    // The signature index space.
    private var signatures : [Signature] = []
    private var signatureIndexMap : [Signature: Int] = [:]

    // This should only be set once we have preprocessed all imported globals, so that we know where internally defined globals start
    private var baseDefinedGlobals: Int? = nil

    // This should only be set once we have preprocessed all imported tables, so that we know where internally defined tables start
    private var baseDefinedTables: Int? = nil

    // This tracks in which order we have seen globals, this can probably be unified with the .globals and .imports properties, as they should match in their keys.
    private var globalOrder: [Variable] = []

    public init(withTyper typer: JSTyper) {
        self.typer = typer
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

        // Return all not-yet-emitted variables
        // TODO: this does not preserve order?
        func getPendingVars() -> [Variable] {
            varMap.filter({ !emittedVariables.contains($0.0) }).map { $0.0 }
        }

        public var isEmpty: Bool {
            return varMap.isEmpty
        }
    }

    private var writer = WasmExprWriter()

    var isEmpty: Bool {
        return instructionBuffer.isEmpty &&
               self.bytecode.isEmpty &&
               self.functions.isEmpty
    }

    // TODO: maybe we can do some analysis based on blocks.
    // Get the type index or something or infer the value type that it tries to return? With BlockInfo class or something like that?

    private func updateVariableAnalysis(forInstruction wasmInstruction: Instruction) {
        // Only analyze an instruction if we are inside a function definition.
        if let currentFunction = currentFunction {
            // We don't need to analyze the Begin instruction which opened this one.
            // TODO: can this be done more neatly? i.e. re-order analyis and emitting the instruction?
            if wasmInstruction.op is BeginWasmFunction {
                return
            }
            currentFunction.variableAnalyzer.analyze(wasmInstruction)
        }
    }

    // Holds various information for the functions in a wasm module.
    private class FunctionInfo {
        var signature: Signature
        var code: Data
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
        init(_ signature: Signature, _ code: Data, for lifter: WasmLifter, withArguments arguments: [Variable]) {
            // Infer the first few locals from this signature.
            self.signature = signature
            self.code = code
            self.localsInfo = [(Variable, ILType)]()
            self.lifter = lifter
            assert(signature.parameters.count == arguments.count)
            // Populate the localsInfo with the parameter types
            for (idx, argVar) in arguments.enumerated() {
                switch signature.parameters[idx] {
                case .plain(let argType):
                    self.localsInfo.append((argVar, argType))
                    // Emit the expressions for the parameters such that we can accesss them if we need them.
                    self.lifter!.writer.addExpr(for: argVar, bytecode: Data([0x20, UInt8(self.localsInfo.count - 1)]))
                default:
                    fatalError("Cannot have a non-plain argument as a function parameter")
                }
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
            self.code += Data([0x21, UInt8(localsInfo.count - 1)])
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
            self.code += Data([0x20, UInt8(getStackSlot(for: variable)!)])
        }
    }

    // The parameters, actual bytecode and number of locals of the functions.
    private var functions: [FunctionInfo] = []

    private var currentFunction: FunctionInfo? = nil

    public func addInstruction(_ instruction: Instruction) {
        self.instructionBuffer.append(instruction)
    }

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
            for function in functions {
                print("\(String(describing: function))")
            }
        }

        // Build the header section which includes the Wasm version first
        self.buildHeader()

        self.buildTypeSection()
        try self.buildImportSection()
        try self.buildFunctionSection()
        self.buildTableSection()
        self.buildMemorySection()
        try self.buildTagSection()
        try self.buildGlobalSection()

        // Export all functions by default.
        try self.buildExportedSection()

        // Build element segments for defined tables.
        try self.buildElementSection()

        // The actual bytecode of the functions.
        self.buildCodeSection(self.instructionBuffer)

        // Write the bytecode as file to the given path for debugging purposes.
        if let path = path {
            let url = URL(fileURLWithPath: path)
            try? bytecode.write(to: url)
        }

        //
        // Step 3 done
        //

        return (bytecode, imports.map { $0.0 })
    }

    private func buildHeader() {
        // Build the magic and the version of wasm we compile to.
        self.bytecode += [0x0]
        self.bytecode += "asm".data(using: .ascii)!

        // LE encoded 1 as the wasm version.
        self.bytecode += [0x1, 0x0, 0x0, 0x0]
    }

    private func buildTypeSection() {
        self.bytecode += [WasmSection.type.rawValue]


        var temp = Data()

        // Collect all signatures.
        for (_, signature) in self.imports {
            if let signature {
                registerSignature(signature)
            }
        }
        for tag in self.tags {
            registerSignature(tag.1 => .nothing)
        }
        for function in self.functions {
            registerSignature(function.signature)
        }

        let typeCount = self.signatures.count

        temp += Leb128.unsignedEncode(typeCount)

        for signature in self.signatures {
            temp += [0x60]
            temp += Leb128.unsignedEncode(signature.parameters.count)
            for paramType in signature.parameters {
                switch paramType {
                case .plain(let paramType):
                    temp += ILTypeMapping[paramType]!
                default:
                    fatalError("unreachable")
                }
            }
            if signature.outputType != .nothing {
                temp += Leb128.unsignedEncode(1) // num output types
                temp += ILTypeMapping[signature.outputType] ?? Data([0x6f])
            } else {
                temp += [0x00] // num output types
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

    private func registerSignature(_ signature: Signature) {
        assert(signatures.count == signatureIndexMap.count)
        if signatureIndexMap[signature] != nil {
            return
        }
        let signatureIndex = signatures.count
        signatures.append(signature)
        signatureIndexMap[signature] = signatureIndex
        assert(signatures.count == signatureIndexMap.count)
    }

    private func getSignatureIndex(_ signature: Signature) throws -> Int {
        if let idx = signatureIndexMap[signature] {
            return idx
        }

        throw WasmLifter.CompileError.failedSignatureLookUp
    }

    private func buildImportSection() throws {
        if self.imports.isEmpty {
            return
        }

        self.bytecode += [WasmSection.import.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.imports.map { $0 }.count)

        // Build the import components of this vector that consist of mod:name, nm:name, and d:importdesc
        for (idx, (importVariable, signature)) in self.imports.enumerated() {
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
            if type.Is(.function()) || type.Is(.object(ofGroup: "WebAssembly.SuspendableObject")) {
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
                let tableType = type.wasmTableType!.elementType
                assert(tableType == ILType.wasmExternRef)
                let minSize = type.wasmTableType!.limits.min
                let maxSize = type.wasmTableType!.limits.max
                temp += Data([0x1])
                temp += ILTypeMapping[tableType]!
                if let maxSize = maxSize {
                    temp += Data([0x1] + Leb128.unsignedEncode(minSize) + Leb128.unsignedEncode(maxSize))
                } else {
                    temp += Data([0x0] + Leb128.unsignedEncode(minSize))
                }
                continue
            }
            if type.Is(.object(ofGroup: "WasmGlobal")) {
                let valueType = type.wasmGlobalType!.valueType
                let mutability = type.wasmGlobalType!.isMutable
                temp += [0x3]
                temp += ILTypeMapping[valueType]!
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
        var temp = Leb128.unsignedEncode(self.functions.count)

        for info in self.functions {
            temp.append(Leb128.unsignedEncode(try getSignatureIndex(info.signature)))
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

    private func buildTableSection() {
        self.bytecode += [WasmSection.table.rawValue]

        var temp = Leb128.unsignedEncode(self.tables.count)

        for instruction in self.tables {
            let op = instruction.op as! WasmDefineTable
            let elementType = op.tableType.elementType
            let minSize = op.tableType.limits.min
            let maxSize = op.tableType.limits.max

            temp += ILTypeMapping[elementType]!
            if let maxSize = maxSize {
                temp += Data([0x1] + Leb128.unsignedEncode(minSize) + Leb128.unsignedEncode(maxSize))
            } else {
                temp += Data([0x0] + Leb128.unsignedEncode(minSize))
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
    // - active segments
    // - with custom table id
    // - function-indices-as-elements (i.e. case 2 of the spec: https://webassembly.github.io/spec/core/binary/modules.html#element-section)
    // - one segment per table (assumes entries are continuous)
    // - constant starting index.
    private func buildElementSection() throws {
        self.bytecode += [WasmSection.element.rawValue]
        var temp = Data();

        let numDefinedTablesWithEntries = self.tables.count { instruction in
            !(instruction.op as! WasmDefineTable).definedEntryIndices.isEmpty
        }

        // Element segment count.
        temp += Leb128.unsignedEncode(numDefinedTablesWithEntries);

        for instruction in self.tables {
            let definedEntryIndices = (instruction.op as! WasmDefineTable).definedEntryIndices
            assert(definedEntryIndices.count == instruction.inputs.count)
            if definedEntryIndices.isEmpty { continue }
            // Element segment case 2 definition.
            temp += [0x02]
            let tableIndex = try self.resolveIdx(ofType: .table, for: instruction.output)
            temp += Leb128.unsignedEncode(tableIndex)
            // Starting index. Assumes all entries are continuous.
            temp += [0x41]
            temp += Leb128.unsignedEncode(definedEntryIndices[0])
            temp += [0x0b]  // end
            // elemkind
            temp += [0x00]
            // entry count
            temp += Leb128.unsignedEncode(definedEntryIndices.count)
            // entries
            for entry in instruction.inputs {
                let functionId = try resolveIdx(ofType: .function, for: entry)
                temp += Leb128.unsignedEncode(functionId)
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

    private func buildCodeSection(_ instructions: Code) {
        self.bytecode += [WasmSection.code.rawValue]

        // Build the contents of the section
        var temp = Data()

        temp += Leb128.unsignedEncode(self.functions.count)

        for (_, functionInfo) in self.functions.enumerated() {
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
            funcTemp += Leb128.unsignedEncode(functionInfo.localsInfo.count - functionInfo.signature.parameters.count)
            for (_, type) in functionInfo.localsInfo[functionInfo.signature.parameters.count...] {
                // Encode the locals
                funcTemp += Leb128.unsignedEncode(1)
                // HINT: If you crash here, you might not have specified an encoding for your new type in `ILTypeMapping`.
                funcTemp += ILTypeMapping[type]!
            }
            // append the actual code and the end marker
            funcTemp += functionInfo.code
            funcTemp += [0x0b]

            // Append the function object to the section
            temp += Leb128.unsignedEncode(funcTemp.count)
            temp += funcTemp
        }

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

    private func buildGlobalSection() throws {
        self.bytecode += [WasmSection.global.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.globals.map { $0 }.count)

        // TODO: in the future this should maybe be a context that allows instructions? Such that we can fuzz this expression as well?
        for instruction in self.globals {
            let definition = instruction.op as! WasmDefineGlobal
            let global = definition.wasmGlobal

            temp += ILTypeMapping[global.toType()]!
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
            case .refNull,
                 .refFunc(_),
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
        temp += Leb128.unsignedEncode(memories.count)

        for instruction in memories {
            let type = typer.type(of: instruction.output)
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
        if self.tags.isEmpty {
            return // Skip the whole section.
        }

        self.bytecode.append(WasmSection.tag.rawValue)
        var section = Data()
        section += Leb128.unsignedEncode(self.tags.reduce(0, {res, _ in res + 1}))
        for tag in self.tags {
            section.append(0)
            section.append(Leb128.unsignedEncode(try getSignatureIndex(tag.1 => .nothing)))
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

    // Export all functions and globals by default.
    // TODO(manoskouk): Also export tables.
    private func buildExportedSection() throws {
        self.bytecode += [WasmSection.export.rawValue]

        var temp = Data()

        // TODO: Track the order in which globals are seen by the typer in the program builder and maybe export them by name here like they are seen.
        // This would just be a 'correctness' fix as this mismatch does not have any implications, it should be fixed though to avoid issues down the road as this is a very subtle mismatch.

        // Get the number of imported globals.
        let importedGlobals = self.imports.map({$0.0}).filter {
            typer.type(of: $0).Is(.object(ofGroup: "WasmGlobal"))
        }

        temp += Leb128.unsignedEncode(self.functions.count + importedGlobals.count + self.globals.count + self.tables.count)
        for (idx, _) in self.functions.enumerated() {
            // Append the name as a vector
            let name = WasmLifter.nameOfFunction(idx)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            // Add the base, as our exports start after the imports. This variable needs to be incremented in the `buildImportSection` function.
            temp += [0x0, UInt8(functionIdxBase + idx)]
        }
        // export all globals that are imported.
        for (idx, imp) in importedGlobals.enumerated() {
            // Append the name as a vector
            // Here for the name, we use the index as remembered by the globalsOrder array, to preserve the export order with what the typer of the ProgramBuilder has seen before.
            let index = self.globalOrder.firstIndex(of: imp)!
            let name = WasmLifter.nameOfGlobal(index)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            temp += [0x3, UInt8(idx)]
        }
        // Also export all globals that we have defined.
        for (idx, instruction) in self.globals.enumerated() {
            // Append the name as a vector
            // Again, the name that we export it as matches the order that the ProgramBuilder's typer has seen it when traversing the Code, which happen's way before our typer here sees it, as we are typing during *lifting* of the JS code.
            // This kinda solves a problem we don't actually have... but it's correct this way :)
            let index = self.globalOrder.firstIndex(of: instruction.output)!
            let name = WasmLifter.nameOfGlobal(index)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            // Add the base, as our exports start after the imports. This variable needs to be incremented in the `buildImportSection` function.
            // TODO: maybe add something like a global base?
            temp += [0x3, UInt8(importedGlobals.count + idx)]
        }

        for instruction in self.tables {
            let index = try resolveIdx(ofType: .table, for: instruction.output)
            let name = WasmLifter.nameOfTable(index)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            temp += [0x1, UInt8(index)]
        }

        // TODO(mliedtke): Export defined tags.

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
            // TODO(mliedtke): Repeat this for loops.
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
            assert(self.imports.contains(where: { $0.0 == instr.input(0)}) || self.tags.contains(instr.input(0)))
            // Needs typer analysis
            return true
        case .wasmBeginCatchAll(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth - 1
            // Needs typer analysis
            return true
        case .wasmNop(_):
            // Just analyze the instruction but do nothing else here.
            // This lets the typer know that we can skip this instruction without breaking any analysis.
            break
        case .beginWasmFunction(let op):
            functions.append(FunctionInfo(op.signature, Data(), for: self, withArguments: Array(instr.innerOutputs)))
            // Set the current active function as we are *actively* in it.
            currentFunction = functions.last
        case .endWasmFunction(_):
            // TODO: Make sure that the stack is matching the output of the function signature, at least depth wise
            // Make sure that we exit the current function, this is necessary such that the variableAnalyzer can be reset too, it is local to a function definition and we should only pass .wasmFunction context instructions to the variableAnalyzer.
            currentFunction!.outputVariable = instr.output
            currentFunction = nil
            break
        case .wasmDefineGlobal(_):
            assert(self.globals.contains(where: { $0.output == instr.output }))
        case .wasmDefineTable(_):
            assert(self.tables.contains(where: { $0.output == instr.output }))
        case .wasmDefineMemory(_):
            assert(self.memories.contains(where: { $0.output == instr.output }))
        case .wasmJsCall(_):
            assert(self.imports.contains(where: { $0.0 == instr.input(0)}))
            return true
        case .wasmThrow(_):
            assert(self.imports.contains(where: { $0.0 == instr.input(0)}) || self.tags.contains(instr.input(0)))
            return true
        case .wasmDefineTag(_):
            assert(self.tags.contains(instr.output))
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

            // Special inputs that aren't locals (e.g. memories, functions, tags, ...)
            let isLocallyDefined = inputType.isWasmTagType && tags.contains(input)
                || inputType.isWasmTableType && tables.contains(where: {$0.output == input})
                || inputType.Is(.wasmFuncRef) && functions.contains(where: {$0.outputVariable == input})
                || inputType.isWasmGlobalType && globals.contains(where: {$0.output == input})
                || inputType.isWasmMemoryType && memories.contains(where: {$0.output == input})
            if !isLocallyDefined {
                assert(self.imports.contains(where: {$0.0 == input}), "Variable \(input) needs to be imported during importAnalysis()")
            }
        }
    }

    private func emitBytesForInstruction(forInstruction instr: Instruction) throws {
        currentFunction!.appendToCode(try lift(instr))
    }

    private func emitStackSpillsIfNecessary(forInstruction instr: Instruction) {
        // Don't emit spills for reassigns. This is specially handled in the `lift` function for reassigns.
        if instr.op is WasmReassign {
            return
        }

        // If we have an output, make sure we store it on the stack as this is a "complex" instruction, i.e. has inputs and outputs
        if instr.numOutputs > 0 {
            assert(!typer.type(of: instr.output).Is(.anyLabel))
            // Also spill the instruction
            currentFunction!.spillLocal(forVariable: instr.output)
            // Add the corresponding stack load as an expression, this adds the number of arguments, as output vars always live after the function arguments.
            self.writer.addExpr(for: instr.output, bytecode: Data([0x20, UInt8(currentFunction!.localsInfo.count - 1)]))
        }

        // TODO(mliedtke): Reuse this for handling parameters in loops, if-else, ...
        if instr.op is WasmBeginBlock || instr.op is WasmBeginTry
            || instr.op is WasmBeginTryDelegate || instr.op is WasmBeginIf || instr.op is WasmBeginElse
            || instr.op is WasmBeginLoop {
            // As the parameters are pushed "in order" to the stack, they need to be popped in reverse order.
            for innerOutput in instr.innerOutputs(1...).reversed() {
                currentFunction!.spillLocal(forVariable: innerOutput)
            }
        }
        if instr.op is WasmBeginCatch {
            for innerOutput in instr.innerOutputs(2...).reversed() {
                currentFunction!.spillLocal(forVariable: innerOutput)
            }
        }
    }

    private func importTagIfNeeded(tag: Variable, parameters: ParameterList) {
        if (!self.tags.contains(tag) && self.imports.firstIndex(where: {variable, _ in variable == tag}) == nil) {
            self.imports.append((tag, parameters => .nothing))
        }
    }

    // Helper function for memory accessing instructions.
    private func memoryOpImportAnalysis(instr: Instruction, isMemory64: Bool) throws {
        let memory = instr.input(0)
        if !typer.type(of: memory).isWasmMemoryType {
            throw WasmLifter.CompileError.missingTypeInformation
        }
        assert(typer.type(of: memory).wasmMemoryType!.isMemory64 == isMemory64)
        if !self.memories.contains(where: {$0.output == memory}) {
            // TODO(cffsmith) this needs to be changed once we support multimemory as we probably also need to fix the ordering.
            if !self.imports.map({$0.0}).contains(memory) {
                self.imports.append((memory, nil))
            }
        }
    }

    // Analyze which Variables should be imported. Here we should analyze all instructions that could potentially force an import of a Variable that originates in JavaScript.
    // This usually means if your instruction takes an .object() as an input, it should be checked here.
    // TODO: check if this is still accurate as we now only have defined imports.
    // Also, we export the globals in the order we "see" them, which might mismatch the order in which they are laid out in the binary at the end, which is why we track the order of the globals separately.
    private func importAnalysis() throws {
        for instr in self.instructionBuffer {
            switch instr.op.opcode {
            case .wasmLoadGlobal(_),
                 .wasmStoreGlobal(_):
                let globalVariable = instr.input(0)
                if !self.globalOrder.contains(globalVariable) {
                    self.imports.append((globalVariable, nil))
                    self.globalOrder.append(globalVariable)
                }
            case .wasmDefineGlobal(_):
                self.globals.append(instr)
                self.globalOrder.append(instr.output)

            case .wasmDefineTable(let tableDef):
                self.tables.append(instr)
                if tableDef.tableType.elementType == .wasmFuncRef {
                    for definedEntry in instr.inputs {
                        if typer.type(of: definedEntry).Is(.function()) && !self.imports.contains(where: { $0.0 == definedEntry }) {
                            // Ensure deterministic lifting.

                            let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignatureDeterministic(typer.type(of: definedEntry).signature ?? Signature.forUnknownFunction)
                            self.imports.append((definedEntry, wasmSignature))
                        }
                    }
                }
            case .wasmDefineMemory:
                self.memories.append(instr)
            case .wasmMemoryLoad(let op):
                try memoryOpImportAnalysis(instr: instr, isMemory64: op.isMemory64)
            case .wasmMemoryStore(let op):
                try memoryOpImportAnalysis(instr: instr, isMemory64: op.isMemory64)
            case .wasmSimdLoad(let op):
                try memoryOpImportAnalysis(instr: instr, isMemory64: op.isMemory64)
            case .wasmTableGet(_),
                 .wasmTableSet(_):
                let table = instr.input(0)
                if !self.tables.contains(where: {$0.output == table}) {
                    // TODO: check if the ordering here is also somehow important?
                    if !self.imports.map({$0.0}).contains(table) {
                        self.imports.append((table, nil))
                    }
                }

            case .wasmJsCall(let op):
                self.imports.append((instr.input(0), op.functionSignature))

            case .wasmDefineTag(let op):
                self.tags[instr.output] = op.parameters

            case .wasmBeginCatch(let op):
                if !typer.type(of: instr.input(0)).isWasmTagType {
                    throw WasmLifter.CompileError.missingTypeInformation
                }
                assert(typer.type(of: instr.input(0)).wasmTagType!.parameters == op.signature.parameters)
                importTagIfNeeded(tag: instr.input(0), parameters: op.signature.parameters)

            case .wasmThrow(let op):
                if !typer.type(of: instr.input(0)).isWasmTagType {
                    throw WasmLifter.CompileError.missingTypeInformation
                }
                assert(typer.type(of: instr.input(0)).wasmTagType!.parameters == op.parameters)
                importTagIfNeeded(tag: instr.input(0), parameters: op.parameters)

            default:
                assert((instr.op as! WasmOperation).inputTypes.allSatisfy { type in
                    !type.Is(.object())
                }, "\(instr.op) has an input that is .object() it should probably be handled here.")
                continue
            }
        }

        // The base of the internally defined globals indices come after the imports.
        self.baseDefinedGlobals = self.imports.filter({typer.type(of: $0.0).Is(.object(ofGroup: "WasmGlobal")) }).count
        // The number of internally defined tables indices come after the imports.
        self.baseDefinedTables = self.imports.filter({ typer.type(of: $0.0).Is(.object(ofGroup: "WasmTable")) }).count
    }

    /// Describes the types of indexes in the different index spaces in the Wasm binary format.
    public enum IndexType {
        case global
        case table
        case tag
        case function
    }

    /// Helper function to resolve the index (as laid out in the binary format) of an instruction input Variable of a specific `IndexType`
    /// Intended to be called from `lift`.
    func resolveIdx(ofType type: IndexType, for input: Variable) throws -> Int {
        var base = 0
        var groupType: String? = nil

        switch type {
        case .global:
            groupType = "WasmGlobal"
            base = self.baseDefinedGlobals!
        case .table:
            groupType = "WasmTable"
            base = self.baseDefinedTables!
        case .tag:
            groupType = "WasmTag"
            base = self.imports.filter({
                self.typer.type(of: $0.0).Is(.object(ofGroup: groupType!))
            }).count
        case .function:
            base = self.functionIdxBase
        }

        let predicate: ((Variable) -> Bool) = switch type {
        case .global,
                .table,
                .tag:
            { variable in
                self.typer.type(of: variable).Is(.object(ofGroup: groupType!))
            }
        case .function:
            { variable in
                self.typer.type(of: variable).Is(.function()) || self.typer.type(of: variable).Is(.object(ofGroup: "WebAssembly.SuspendableObject"))
            }
        }

        let filteredImports = self.imports.filter({ predicate($0.0) })
        // Check if we can find this in the imports:
        if let idx = filteredImports.firstIndex(where: { $0.0 == input }) {
            return idx
        }

        // If we don't have it as an import, look into the respective internally defined sections.
        let idx: Int? = switch type {
        case .global:
            self.globals.firstIndex(where: {$0.output == input})
        case .tag:
            self.tags.map({$0}).firstIndex(where: {$0.0 == input})
        case .table:
            self.tables.firstIndex(where: {$0.output == input})
        case .function:
            self.functions.firstIndex { $0.outputVariable == input }
        }

        if let idx = idx {
            return base + idx
        }

        throw WasmLifter.CompileError.failedIndexLookUp
    }

    /// Returns the Bytes that correspond to this instruction.
    /// This will also automatically add bytes that are necessary based on the state of the Lifter.
    /// Example: LoadGlobal with an input variable will resolve the input variable to a concrete global index.
    private func lift(_ wasmInstruction: Instruction) throws -> Data {
        // Make sure that we actually have a Wasm operation here.
        assert(wasmInstruction.op is WasmOperation)

        switch wasmInstruction.op.opcode {
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
            let d = Data([0xFC])
            if op.isSigned {
                return d + Leb128.unsignedEncode(0)
            } else {
                return d + Leb128.unsignedEncode(1)
            }
        case .wasmTruncateSatf64Toi32(let op):
            let d = Data([0xFC])
            if op.isSigned {
                return d + Leb128.unsignedEncode(2)
            } else {
                return d + Leb128.unsignedEncode(3)
            }
        case .wasmTruncateSatf32Toi64(let op):
            let d = Data([0xFC])
            if op.isSigned {
                return d + Leb128.unsignedEncode(4)
            } else {
                return d + Leb128.unsignedEncode(5)
            }
        case .wasmTruncateSatf64Toi64(let op):
            let d = Data([0xFC])
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
        case .wasmMemoryLoad(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            return Data([op.loadType.rawValue]) + Leb128.unsignedEncode(0) + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmMemoryStore(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            return Data([op.storeType.rawValue]) + Leb128.unsignedEncode(0) + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmJsCall(let op):
            // We filter first, such that we get the index of functions only.
            if let index = imports.filter({
                // TODO, switch query?
                typer.type(of: $0.0).Is(.function()) || typer.type(of: $0.0).Is(.object(ofGroup: "WebAssembly.SuspendableObject"))
            }).firstIndex(where: {
                wasmInstruction.input(0) == $0.0 && op.functionSignature == $0.1
            }) {
                return Data([0x10]) + Leb128.unsignedEncode(index)
            } else {
                throw WasmLifter.CompileError.failedIndexLookUp
            }
        case .wasmBeginBlock(let op):
            // A Block can "produce" (push) an item on the value stack, just like a function. Similarly, a block can also have parameters.
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#binary-blocktype
            return Data([0x02] + Leb128.unsignedEncode(signatureIndexMap[op.signature]!))
        case .wasmBeginLoop(let op):
            return Data([0x03] + Leb128.unsignedEncode(signatureIndexMap[op.signature]!))
        case .wasmBeginTry(let op):
            return Data([0x06] + Leb128.unsignedEncode(signatureIndexMap[op.signature]!))
        case .wasmBeginTryDelegate(let op):
            return Data([0x06] + Leb128.unsignedEncode(signatureIndexMap[op.signature]!))
        case .wasmBeginCatchAll(_):
            return Data([0x19])
        case .wasmBeginCatch(_):
            return Data([0x07] + Leb128.unsignedEncode(try resolveIdx(ofType: .tag, for: wasmInstruction.input(0))))
        case .wasmEndLoop(_),
                .wasmEndIf(_),
                .wasmEndTry(_),
                .wasmEndBlock(_):
            // Basically the same as EndBlock, just an explicit instruction.
            return Data([0x0B])
        case .wasmEndTryDelegate(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            // Mutation might make this EndTryDelegate branch to itself, which should not happen.
            if branchDepth < 0 {
                throw WasmLifter.CompileError.invalidBranch
            }
            return Data([0x18]) + Leb128.unsignedEncode(branchDepth)
        case .wasmThrow(_):
            return Data([0x08] + Leb128.unsignedEncode(try resolveIdx(ofType: .tag, for: wasmInstruction.input(0))))
        case .wasmRethrow(_):
            let blockDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x09] + Leb128.unsignedEncode(blockDepth))
        case .wasmBranch(let op):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x0C]) + Leb128.unsignedEncode(branchDepth) + Data(op.labelTypes.map {_ in 0x1A})
        case .wasmBranchIf(let op):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x0D]) + Leb128.unsignedEncode(branchDepth) + Data(op.labelTypes.map {_ in 0x1A})
        case .wasmBeginIf(let op):
            return Data([0x04] + Leb128.unsignedEncode(signatureIndexMap[op.signature]!))
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
        case .wasmSelect(let op):
            return Data([0x1c, 0x01]) + ILTypeMapping[op.type]!
        case .constSimd128(let op):
            return Data([0xFD]) + Leb128.unsignedEncode(12) + Data(op.value)
        case .wasmSimd128IntegerUnOp(let op):
            assert(WasmSimd128IntegerUnOpKind.allCases.count == 13, "New WasmSimd128IntegerUnOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerUnOp")
            }
            var encoding = Data([0xFD]) + Leb128.unsignedEncode(base + op.unOpKind.rawValue)
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
            assert(WasmSimd128IntegerBinOpKind.allCases.count == 23, "New WasmSimd128IntegerBinOpKind added: check if the encoding is still correct!")
            let base = switch op.shape {
                case .i8x16: 0x5C
                case .i16x8: 0x7C
                case .i32x4: 0x9C
                case .i64x2: 0xBC
                default: fatalError("Shape \(op.shape) not supported for WasmSimd128IntegerBinOp")
            }
            var encoding =  Data([0xFD]) + Leb128.unsignedEncode(base + op.binOpKind.rawValue)
            // Apart from .i8x16 shape, the encoding has another 0x01 byte at the end of the encoding.
            if (op.shape != .i8x16) {
                encoding += Leb128.unsignedEncode(0x01)
            }
            return encoding
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
            return Data([0xFD]) + encoding
        case .wasmSimd128FloatBinOp(let op):
            assert(WasmSimd128FloatBinOpKind.allCases.count == 8, "New WasmSimd128FloatBinOpKind added: check if the encoding is still correct!")
            let base = (op.shape == .f32x4) ? 0xE4 : 0xF0;
            return Data([0xFD]) + Leb128.unsignedEncode(base + op.binOpKind.rawValue) + Leb128.unsignedEncode(0x01)
        case .wasmSimd128Compare(let op):
            assert(WasmIntegerCompareOpKind.allCases.count == 10, "New WasmIntegerCompareOpKind added: check if the encoding is still correct!")
            assert(WasmFloatCompareOpKind.allCases.count == 6, "New WasmFloatCompareOpKind added: check if the encoding is still correct!")
            switch op.shape {
            case .i8x16:
                return Data([0xFD]) + Leb128.unsignedEncode(0x23 + op.compareOpKind.toInt())
            case .i16x8:
                return Data([0xFD]) + Leb128.unsignedEncode(0x2D + op.compareOpKind.toInt())
            case .i32x4:
                return Data([0xFD]) + Leb128.unsignedEncode(0x37 + op.compareOpKind.toInt())
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
                    return Data([0xFD]) + Leb128.unsignedEncode(0xD6 + temp) + Leb128.unsignedEncode(0x01)
                }
                fatalError("unreachable")
            case .f32x4:
                return Data([0xFD]) + Leb128.unsignedEncode(0x41 + op.compareOpKind.toInt())
            case .f64x2:
                return Data([0xFD]) + Leb128.unsignedEncode(0x47 + op.compareOpKind.toInt())
            }
        case .wasmI64x2Splat(_):
            return Data([0xFD]) + Leb128.unsignedEncode(0x12)
        case .wasmI64x2ExtractLane(let op):
            return Data([0xFD]) + Leb128.unsignedEncode(0x1D) + Leb128.unsignedEncode(op.lane)
         case .wasmSimdLoad(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            return Data([0xFD, op.kind.rawValue]) + Leb128.unsignedEncode(0) + Leb128.signedEncode(Int(op.staticOffset))

        default:
             fatalError("unreachable")
        }
    }
}
