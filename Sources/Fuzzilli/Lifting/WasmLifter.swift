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
}

// This maps ILTypes to their respective binary encoding.
private let ILTypeMapping: [ILType: Data] = [
    .wasmi32 : Data([0x7f]),
    .wasmi64 : Data([0x7e]),
    .wasmf32 : Data([0x7D]),
    .wasmf64 : Data([0x7C]),
    .wasmExternRef: Data([0x6f]),
    .wasmFuncRef: Data([0x70]),

    .bigint  : Data([0x7e]), // Maps to .wasmi64
    .anything: Data([0x6f]), // Maps to .wasmExternRef
    .integer: Data([0x7f]), // Maps to .wasmi32
    .number: Data([0x7d]) // Maps to .wasmf32
]

/// Maps global types that are imported from the JS world to their respective Wasm equivalent.
private func globalImportMapping(type: ILType) -> Data {
    if type.Is(.object(ofGroup: "WasmGlobal.i64")) {
        return Data([0x7e])
    }
    if type.Is(.object(ofGroup: "WasmGlobal.i32")) {
        return Data([0x7f])
    }
    if type.Is(.object(ofGroup: "WasmGlobal.f64")) {
        return Data([0x7C])
    }
    if type.Is(.object(ofGroup: "WasmGlobal.f32")) {
        return Data([0x7D])
    }
    fatalError("unimplemented for iltype \(type)!")
}

/// This is the main compiler for Wasm instructions.
/// This lifter collects all wasm instructions during lifting
/// (The JavaScriptLifter passes them to this instance) and then it compiles them
/// at the end of the block when we see a EndWasmModule instruction.
/// This way the WasmLifter has full information before it actually emits any bytes.
public class WasmLifter {
    // The actual bytecode we compile.
    private var bytecode: Data = Data()

    // The level of verboseness
    private var verbose: Bool = false

    // The string that is given to the script writer
    private var out: String = ""

    // We need this typer to emit the correct bytecode but at the time when we are lifting this module, the Typer that lives during ProgramBuilding is already gone here.
    // It would be nice to have e.g. information of JS functions here that were defined in JS, that way we could always pass the correct number of arguments to the JS function. Right now, we instead store the signature in the wasmJsCall instruction.
    // TODO: we could optimize this and just pass in the typing information gathered during ProgramBuilding.
    private var typer = JSTyper(for: JavaScriptEnvironment())

    // This contains the instructions that we need to lift.
    private var instructionBuffer: Code = Code()

    private typealias Limit = (Int, Int?)

    // TODO(cffsmith): we could do some checking here that the function is actually defined, at that point it would not be static anymore though.
    public static func nameOfFunction(_ idx: Int) -> String {
        return "w\(idx)"
    }

    // TODO(cffsmith): we could do some checking here that the global is actually defined, at that point it would not be static anymore though.
    public static func nameOfGlobal(_ idx: Int) -> String {
        return "wg\(idx)"
    }

    private struct Import {
        let importType: ImportType
        let outputVariable: Variable?

        public enum ImportType {
            case function(Signature)
            // Encodes the limits of the memory
            case memory(Limit)
            // Encodes the table type, can only be externref or funcref and the limits
            case table(tableType: ILType, limit: Limit)
            // Encodes the value type and the mutability of the global
            case global(globalType: ILType, mutability: Bool)
        }

        fileprivate var isGlobal: Bool {
            switch self.importType {
            case .global:
                return true
            default:
                return false
            }
        }

        fileprivate var isTable: Bool {
            switch self.importType {
            case .table:
                return true
            default:
                return false
            }
        }

        fileprivate var isFunction: Bool {
            switch self.importType {
            case .function(_):
                return true
            default:
                return false
            }
        }
    }

    // The list of imports that we need.
    // Maps Js world Variables to their import type and their potential Wasm World equivalent outputvariable
    // I.e. importGlobal returns a Wasm world variable.
    private var imports: VariableMap<Import> = VariableMap()

    // The globals that this module defines
    // The variable key is the output of the instruction that has created it.
    // The bool signifies if the global is mutable or not
    private var globals: VariableMap<(global: WasmGlobal, mutability: Bool)> = VariableMap()

    // The Tables associated with this module, the elements of the tuple describe the element type, minSize and maxSize respectively.
    private var tables: VariableMap<(ILType, Int, Int?)> = VariableMap()

    // The Memories associated with this module, the elements of the tuple describe the minSize and maxSize respectively
    // This only holds memories defined in the module, if there is an import of a memory, it is in the imports array.
    private var memories: [(Int, Int?)] = []

    // The function index space
    private var functionIdxBase = 0

    // This should only be set, once we have preprocessed all imported globals, so that we know where internally defined globals start
    private var baseDefinedGlobals: Int? = nil

    // This should only be set, once we have preprocessed all imported tables, so that we know where internally defined tables start
    private var baseDefinedTables: Int? = nil

    // This signals that we will need to append a function index after the bytes of the instruction
    private var emitCallToImport: Variable?


    // This tracks in which order we have seen globals, this can probably be unified with the .globals and .imports properties, as they should match in their keys.
    private var globalOrder: [Variable] = []

    public func reset() {
        self.imports = VariableMap()
        self.globals = VariableMap()
        self.tables = VariableMap()
        self.memories = []
        self.functionIdxBase = 0
        self.typer.reset()
        self.out = ""
        self.bytecode = Data()
        self.instructionBuffer = Code()
        self.functions = []
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
            assert(wasmInstruction.op.requiredContext.contains(.wasmFunction))
            currentFunction.variableAnalyzer.analyze(wasmInstruction)
        }
    }

    // Holds various information for the functions in a wasm module.
    private class FunctionInfo {
        var signature: Signature
        var code: Data
        // Locals that we spill to, this maps from the ordering to the stack.
        var localsInfo: [(Variable, ILType)]
        var variableAnalyzer = VariableAnalyzer()
        weak var lifter: WasmLifter?

        // Tracks the labels and the scope depth the've been emitted at. This is needed to calculate how far "out" we have to branch to
        // Whenever we start something that emits a label, we need to track the scope depth here.
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
            assert(isLocal(variable) && getStackSlot(for: variable)! < self.signature.parameters.count)
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

    public func lift(writer: inout JavaScriptLifter.JavaScriptWriter, binaryOutPath path: String? = nil) -> (Data, [Variable]) {
        // Lifting currently happens in three stages.
        // 1. Collect all necessary information to build all tables later on.
        //    - For now this only the globalAnalysis, which needs to know how many globals are defined.
        // 2. Lift each instruction within its local context using all information needed from the previous analysis inside of a given function
        // 3. Use the already lifted functions to emit the whole wasm byte buffer.

        // Step 1:
        // Collect all global and table information that we need.
        globalAndTableAnalysis(forInstructions: self.instructionBuffer)
        // Todo: maybe add a def-use pass here to figure out where we need stack spills etc? e.g. if we have one use, we can omit the stack spill

        // The typer that lives here in the wasmLifter has not seen the BeginWasmModule instruction, as it only lives "within" it, as such we create an empty definition here.
        typer.addEmptyWasmModuleDefinition()

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

            typer.analyze(instr)

            if needsByteEmission {
//                typer.analyze(instr)

                // If we require inputs for this instruction, we probably need to emit them now, either inline the corresponding instruction, iff this is a single use, or load the stack slot or the variable. TODO: not all of this is implemented.
                emitInputLoadsIfNecessary(forInstruction: instr)
                // Emit the actual bytes that correspond to this instruction to the corresponding function byte array.
                emitBytesForInstruction(forInstruction: instr)
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

        // Build the type section next
        self.buildTypeSection()

        // Build the import section next
        self.buildImportSection(writer: &writer)

        // build the function section next
        self.buildFunctionSection()

        self.buildTableSection()

        self.buildMemorySection()

        // Built the global section next
        self.buildGlobalSection()

        // Export all functions by default.
        self.buildExportedSection()

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

        let importCount = self.imports.filter( {
            switch $0.1.importType {
            case .function:
                return true
            default:
                return false
            }
        }).count + self.functions.count

        temp += Leb128.unsignedEncode(importCount)


        for (_, importElem) in self.imports {

            switch importElem.importType {
            case .function(let signature):
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
                temp += Leb128.unsignedEncode(1) // num output types
                temp += ILTypeMapping[signature.outputType] ?? Data([0x6f])
            default:
                continue
            }
        }

        // We only need the parameters here.
        for (_, functionInfo) in self.functions.enumerated() {
            // The 0x60 encodes functypes, which now expects two vector of
            // returntypes
            temp += [0x60]
            temp += Leb128.unsignedEncode(functionInfo.signature.parameters.count)
            for paramType in functionInfo.signature.parameters {
                switch paramType {
                case .plain(let paramType):
                    temp += ILTypeMapping[paramType]!
                default:
                    fatalError("unreachable")
                }
            }
            if !functionInfo.signature.outputType.Is(.nothing) {
                temp += Leb128.unsignedEncode(1) // num output types
                temp += ILTypeMapping[functionInfo.signature.outputType]!
            } else {
                temp += Leb128.unsignedEncode(0) // num output types
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

    private func buildImportSection(writer: inout JavaScriptLifter.JavaScriptWriter) {
        if self.imports.isEmpty {
            return
        }

        self.bytecode += [WasmSection.import.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.imports.map { $0 }.count)

        // Build the import components of this vector that consist of mod:name, nm:name, and d:importdesc
        for (importVariable, importElem) in self.imports {
            if verbose {
                print(importElem)
            }
            // Append the name as a vector
            temp += Leb128.unsignedEncode("imports".count)
            temp += "imports".data(using: .utf8)!
            let importName = "\(writer.retrieve(expressionsFor: [importVariable])[0])"
            temp += Leb128.unsignedEncode(importName.count)
            temp += importName.data(using: .utf8)!
            switch importElem.importType {
            case .function(_):
                if verbose {
                    print(functionIdxBase)
                }
                temp += [0x0, UInt8(functionIdxBase)] // import kind and signature (type) idx

                // Update the index space, these indices have to be set before the exports are set
                functionIdxBase += 1
            case .memory((let minSize, let maxSize)):
                temp += Data([0x2])
                if let maxSize = maxSize {
                    temp += Data([0x1] + Leb128.unsignedEncode(minSize) + Leb128.unsignedEncode(maxSize))
                } else {
                    temp += Data([0x0] + Leb128.unsignedEncode(minSize))
                }
            case .table(let tableType, (let minSize, let maxSize)):
                temp += Data([0x1])
                temp += ILTypeMapping[tableType]!
                if let maxSize = maxSize {
                    temp += Data([0x1] + Leb128.unsignedEncode(minSize) + Leb128.unsignedEncode(maxSize))
                } else {
                    temp += Data([0x0] + Leb128.unsignedEncode(minSize))
                }
            case .global(let valueType, let mutability):
                temp += [0x3]
                temp += globalImportMapping(type: valueType)
                temp += mutability ? [0x1] : [0x0]
            }
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

    private func buildFunctionSection() {
        self.bytecode += [WasmSection.function.rawValue]

        // The number of functions we have, as this is a vector of type idxs.
        // TODO(cffsmith): functions can share type indices. This could be an optimization later on.
        var temp = Leb128.unsignedEncode(self.functions.count)

        for (idx, _) in self.functions.enumerated() {
            temp.append(Leb128.unsignedEncode(functionIdxBase + idx))
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

        var temp = Leb128.unsignedEncode(self.tables.map { $0 }.count)

        for (_, (tableType, minSize, maxSize)) in self.tables {
            temp += ILTypeMapping[tableType]!
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
                funcTemp += ILTypeMapping[type]!
            }
            // append the actual code and the end marker
            funcTemp += functionInfo.code
            funcTemp += [0x0b]

            // Append the function object to the section
            temp += Leb128.unsignedEncode(funcTemp.count)
            temp += funcTemp

//            let localsCount = functionInfo.localsInfo.count < 0 ? 0 : functionInfo.localsInfo.count
//            let localsCountBytes = Leb128.unsignedEncode(localsCount)
//            // TODO(cffsmith): remove this as well.
//            /*let code = (functionInfo.code ?? Data([0x01, 0x01]))*/
////            let code = functionInfo.code
////            assert(localsCount >= 0)
////            assert(localsCountBytes.count == 1)
//            // Encode the size of the locals, the size of the code and the end marker
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

    private func buildGlobalSection() {
        self.bytecode += [WasmSection.global.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.globals.map { $0 }.count)

        // TODO: in the future this should maybe be a context that allows instructions? Such that we can fuzz this expression as well?
        for (_, (global, isMutable)) in self.globals {
            temp += ILTypeMapping[global.toType()]!
            temp += Data([isMutable ? 0x1 : 0x0])
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
            temp += lift(temporaryInstruction!)
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

        assert(memories.count <= 1, "Can only define at most one memory")
        temp += Leb128.unsignedEncode(memories.count)

        for (minSize, maxSize) in memories {
            if let maxSize = maxSize {
                temp += Data([0x1] + Leb128.unsignedEncode(minSize) + Leb128.unsignedEncode(maxSize))
            } else {
                temp += Data([0x0] + Leb128.unsignedEncode(minSize))
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

    // Export all functions by default.
    private func buildExportedSection() {
        self.bytecode += [WasmSection.export.rawValue]

        var temp = Data()

        // TODO: Track the order in which globals are seen by the typer in the program builder and maybe export them by name here like they are seen.
        // This would just be a 'correctness' fix as this mismatch does not have any implications, it should be fixed though to avoid issues down the road as this is a very subtle mismatch.

        // Get the number of imported globals.
        let importedGlobalsCount = self.imports.filter { $1.isGlobal }.count
        let importedGlobals = self.imports.filter { $1.isGlobal }

        temp += Leb128.unsignedEncode(self.functions.count + importedGlobalsCount + self.globals.map { $0 }.count)
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
            let index = self.globalOrder.firstIndex(of: imp.1.outputVariable!)!
            let name = WasmLifter.nameOfGlobal(index)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            temp += [0x3, UInt8(idx)]
        }
        // Also export all globals that we have defined.
        for (idx, (outputVariable, _)) in self.globals.enumerated() {
            // Append the name as a vector
            // Again, the name that we export it as matches the order that the ProgramBuilder's typer has seen it when traversing the Code, which happen's way before our typer here sees it, as we are typing during *lifting* of the JS code.
            // This kinda solves a problem we don't actually have... but it's correct this way :) 
            let index = self.globalOrder.firstIndex(of: outputVariable)!
            let name = WasmLifter.nameOfGlobal(index)
            temp += Leb128.unsignedEncode(name.count)
            temp += name.data(using: .utf8)!
            // Add the base, as our exports start after the imports. This variable needs to be incremented in the `buildImportSection` function.
            // TODO: maybe add something like a global base?
            temp += [0x3, UInt8(importedGlobalsCount + idx)]
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
        assert((instr.op as? WasmOperation) != nil)

        switch instr.op.opcode {
        case .wasmBeginBlock(_),
             .wasmBeginLoop(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.scopes.count
            // Needs typer analysis
            return true
        case .wasmNop(_):
            // Just analyze the instruction but do nothing else here.
            // This lets the typer know that we can skip this instruction without breaking any analysis.
            break
//            typer.analyze(instr)
        case .beginWasmFunction(let op):
//            typer.setIndexOfLastInstruction(to: instr.index)
            functions.append(FunctionInfo(op.signature, Data(), for: self, withArguments: Array(instr.innerOutputs)))
            // Set the current active function as we are *actively* in it.
            currentFunction = self.functions[self.functions.count - 1]
        case .endWasmFunction(_):
            // TODO: Make sure that the stack is matching the output of the function signature, at least depth wise
            // Make sure that we exit the current function, this is necessary such that the variableAnalyzer can be reset too, it is local to a function definition and we should only pass .wasmFunction context instructions to the variableAnalyzer.
            currentFunction = nil
            break
        case .wasmDefineGlobal(_):
            // We have already collected this above
            assert(self.globals.contains(instr.output))
        case .wasmImportGlobal(_):
            // We have already collected this above
            assert(self.imports.contains(instr.input(0)))
        case .wasmDefineTable(_):
            // This should have been collected above in the global analysis
            assert(self.tables.contains(instr.output))
        case .wasmImportTable(_):
            assert(self.imports.contains(instr.input(0)))
            // TODO: fix this in version 1.1
            // Should be collected in analysis pass.
            // We don't know the type and limits of this import. Assume opaque externref and some limits for now
//            self.imports[instr.input(0)] = Import(importType: .table(tableType: .wasmExternRef, limit: (10, 20)), outputVariable: nil)
        case .wasmDefineMemory(let op):
            self.memories.append((op.minSize, op.maxSize))
        case .wasmImportMemory(_):
            // We don't know the limits of this memory as it is defined in JavaScript
            // Therefore we hardcore these limits here for now, this should be fixed in version 1.1.
            // TODO: Do something proper here.
            self.imports[instr.input(0)] = Import(importType: .memory((10, 20)), outputVariable: nil)
        case .wasmJsCall(let op):
            // Make sure that we have the input variable as an import if we see a call to a JS function.
            // Here we also see the inputs, which describe the input types that we need.
            self.imports[instr.input(0)] = Import(importType: .function(Signature(expects: op.inputTypes[1...].map { .plain($0) }, returns: op.outputType)), outputVariable: nil)
            emitCallToImport = instr.input(0)
            return true
        default:
            return true
        }

        return false
    }

    // requires that the instr has been analyzed before. Maybe assert that?
    private func emitInputLoadsIfNecessary(forInstruction instr: Instruction) {
        switch instr.op.opcode {
            // Don't emit loads for reassigns. This is specially handled in the `lift` function for reassigns.
        case .wasmReassign(_):
            return
        default:
            break
        }

        // Check if instruction input is a parameter or if we have an expression for it, if so, we need to load it now.
        for input in instr.inputs {
            // If we have a stackslot, i.e. it is a local, or argument, then add the stack load.
            if let stackSlot = currentFunction!.getStackSlot(for: input), stackSlot < currentFunction!.signature.parameters.count {
                // Emit stack load here now.
                currentFunction!.addStackLoad(for: input)
                continue
            }
            // Load the input now. For "internal" variables, we should not have an expression.
            if let expr = self.writer.getExpr(for: input) {
                currentFunction!.appendToCode(expr)
                continue
            }
            // We might not do anything here, if the variable is a global in a WasmStoreGlobal operation. The global input does not need a load as it is encoded in the bytecode directly, see the `lift` function.
            // We could assert that the input then must be a global.
//            assert(!self.imports.filter({ $0.1.outputVariable == input }).isEmpty ||
//                   self.globals.contains(input) ||
//                   self.tables.contains(input) ||
//                   typer.type(of: input).Is(.label) ||
//                   typer.type(of: input).Is(.wasmMemory) ||
//                   !self.imports.filter({ $0.1.isFunction && $0.0 == input}).isEmpty)
        }

    }

    private func emitBytesForInstruction(forInstruction instr: Instruction) {
        functions[functions.count - 1].appendToCode(lift(instr))
    }

    private func emitStackSpillsIfNecessary(forInstruction instr: Instruction) {
        // If we have an output, make sure we store it on the stack as this is a "complex" instruction, i.e. has inputs and outputs
            if instr.numOutputs > 0 {
                // Also spill the instruction
                functions[functions.count - 1].spillLocal(forVariable: instr.output)
                // Add the corresponding stack load as an expression, this adds the number of arguments, as output vars always live after the function arguments.
                self.writer.addExpr(for: instr.output, bytecode: Data([0x20, UInt8(currentFunction!.localsInfo.count - 1)]))
            }

    }

    // Analyze which globals we have and how many are internally defined vs imported.
    private func globalAndTableAnalysis(forInstructions instrs: Code) {
        // Collect global information, i.e. definitions and imports here. This allows us to refer to the correct indices from here on.
        // Also, export the globals in the order we "see" them, which might mismatch the order in which they are laid out in the binary at the end.
        for instr in self.instructionBuffer {
            switch instr.op.opcode {
            case .wasmImportGlobal(let op):
                // Here we need to record the input variable, as this will be used for the import section.
                // And the expression retriever needs to know here it came frome.
                self.imports[instr.input(0)] = Import(importType: .global(globalType: op.valueType, mutability: op.mutability), outputVariable: instr.output)
                // Append this global as seen.
                self.globalOrder.append(instr.output)
            case .wasmDefineGlobal(let op):
                self.globals[instr.output] = (global: op.wasmGlobal, mutability: op.isMutable)
                // Append this global as seen.
                self.globalOrder.append(instr.output)

            case .wasmImportTable(_):
                // TODO: we don't know anything about the size and type here right now. this should be done properly in a later version.
                self.imports[instr.input(0)] = Import(importType: .table(tableType: typer.type(of: instr.input(0)), limit: (0, nil)), outputVariable: instr.output)
            case .wasmDefineTable(let op):
                self.tables[instr.output] = (op.tableType, op.minSize, op.maxSize)
            default:
                continue
            }
        }

        // The base of the internally defined globals indices come after the imports.
        self.baseDefinedGlobals = self.imports.filter { $0.1.isGlobal }.count
        // The number of internally defined tables indices come after the imports.
        self.baseDefinedTables = self.imports.filter { $0.1.isTable }.count
    }

    /// Returns the Bytes that correspond to this instruction.
    /// This will also automatically add bytes that are necessary based on the state of the Lifter.
    /// Example: LoadGlobal with an input variable will resolve the input variable to a concrete global index.
    private func lift(_ wasmInstruction: Instruction) -> Data {
        // Make sure that we actually have a Wasm operation here.
        assert((wasmInstruction.op as? WasmOperation) != nil)

        /// Helper function to resolve the index of an input variable in the Wasm global array.
        func resolveGlobalIdx(forInput input: Variable) -> Int {
            // Get the index for the global and emit it here magically.
            // The first input has to be in the global or imports arrays.
            var idx: Int?
            // Can be nil now
            // Check if it is an imported global.
            idx = self.imports.filter { $0.1.isGlobal}.firstIndex(where: { $0.1.outputVariable == input })
            // It has to be nil if we enter here, and now we need to find it in the locally defined globals map.
            if self.globals.contains(input) && idx == nil {
                // Add the number of imported globals here.
                idx = self.baseDefinedGlobals! + self.globals.map { $0 }.firstIndex(where: {$0.0 == input})!
            }
            if idx == nil {
                fatalError("WasmStore/LoadGlobal variable \(input) not found as global!")
            }
            return idx!
        }

        func resolveTableIdx(forInput input: Variable) -> Int {
            // Get the index for the table and emit it here magically.
            // The first input has to be in the table or imports arrays.
            var idx: Int?
            // Can be nil now
            // Check if it is an imported table.
            idx = self.imports.filter { $0.1.isTable}.firstIndex(where: { $0.1.outputVariable == input })
            // It has to be nil if we enter here, and now we need to find it in the locally defined tables map.
            if self.tables.contains(input) && idx == nil {
                // Add the number of imported tables here.
                idx = self.baseDefinedTables! + self.tables.map { $0 }.firstIndex(where: {$0.0 == input})!
            }
            if idx == nil {
                fatalError("WasmTableGet/WasmTableSet variable \(input) not found as table!")
            }
            return idx!
        }

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
            return Data([0x23]) + Leb128.unsignedEncode(resolveGlobalIdx(forInput: input))
        case .wasmStoreGlobal(_):

            // Get the index for the global and emit it here magically.
            // The first input has to be in the global or imports arrays.
            let input = wasmInstruction.input(0)
            return Data([0x24]) + Leb128.unsignedEncode(resolveGlobalIdx(forInput: input))
        case .wasmTableGet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x25]) + Leb128.unsignedEncode(resolveTableIdx(forInput: tableRef))
        case .wasmTableSet(_):
            let tableRef = wasmInstruction.input(0)
            return Data([0x26]) + Leb128.unsignedEncode(resolveTableIdx(forInput: tableRef))
        case .wasmMemoryGet(let op):
            switch op.loadType {
            case .wasmi64:
                return Data([0x29]) + Leb128.unsignedEncode(0) + Leb128.unsignedEncode(op.offset)
            default:
                fatalError("WasmMemoryGet loadType unimplemented")
            }
        case .wasmMemorySet(let op):
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#memory-instructions
            switch op.storeType {
            case .wasmi64:
                // The zero is the alignment
                return Data([0x37]) + Leb128.unsignedEncode(0) + Leb128.unsignedEncode(op.offset)
            case .wasmi32:
                // Zero is alignment
                return Data([0x36]) + Leb128.unsignedEncode(0) + Leb128.unsignedEncode(op.offset)
            default:
                fatalError("WasmMemorySet storeType unimplemented")
            }
        case .wasmJsCall(_):
            let callVar = emitCallToImport!
            // TODO: do this right, we currently only now the index of the import here, not in the instruction itself.
            return Data([0x10]) + Data([UInt8(self.imports.map { $0 }.firstIndex(where: { $0.0 == callVar })!)])
        case .wasmBeginBlock(_):
            // A Block can expect an item on the stack at the end, just like a function. This would be encoded just after the block begin (0x02) byte.
            // For now, we just have the empty block but this instruction could take another input which determines the value that we expect on the stack.
            // It would then behave similar to a function just with different branching behavior.
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#binary-blocktype
            return Data([0x02] + [0x40])
        case .wasmBeginLoop(_):
            // 0x03 is the loop instruction and 0x40 is the empty block type, just like in .wasmBeginBlock
            return Data([0x03] + [0x40])
        case .wasmEndLoop(_),
                .wasmEndIf(_),
                .wasmEndBlock(_):
            // Basically the same as EndBlock, just an explicit instruction.
            return Data([0x0B])
        case .wasmBranch(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.scopes.count - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x0C]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchIf(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.scopes.count - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x0D]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBeginIf(_):
            return Data([0x04] + [0x40])
        case .wasmBeginElse(_):
            // 0x05 is the else block instruction.
            return Data([0x05])
        case .wasmReassign(_):
            // wasmReassign is quite special, it needs to work for variables stored in various places, e.g. local slots or even globals. As such the lifting here first needs to locate the destination variable.
            var out = Data()

            var storeInstruction = Data()
            // If the variable is a local, we load the stack slot.
            // Check for the stack location of the `to` variable.
            if let stackSlot = functions[functions.count - 1].getStackSlot(for: wasmInstruction.input(0)) {

                // Emit the instruction now, with input and stackslot. Since we load this manually we don't need
                // to emit bytes in the emitInputLoadsIfNeeded.
                storeInstruction = Data([0x21]) + Leb128.unsignedEncode(stackSlot)
            } else {
                // It has to be global then. Do what StoreGlobal does.
                storeInstruction = Data([0x24]) + Leb128.unsignedEncode(resolveGlobalIdx(forInput: wasmInstruction.input(0)))
            }

            // Load the input now. For "internal" variables, we should not have an expression.
            if let expr = self.writer.getExpr(for: wasmInstruction.input(1)) {
                out += expr
            } else {
                // Has to be a global then. Do what LoadGlobal does.
                out += Data([0x23]) + Leb128.unsignedEncode(resolveGlobalIdx(forInput: wasmInstruction.input(1)))
            }

            return out + storeInstruction
        case .wasmNop(_):
            // This should return something...?
            return Data()

        default:
             fatalError("unreachable")
        }
    }
}


