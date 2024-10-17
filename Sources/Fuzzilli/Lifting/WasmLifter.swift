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
    private var nextSignatureIdx = 0

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

    public func lift(binaryOutPath path: String? = nil) -> (Data, [Variable]) {
        // Lifting currently happens in three stages.
        // 1. Collect all necessary information to build all sections later on.
        //    - For now this only the importAnalysis, which needs to know how many imported vs internally defined types exist.
        // 2. Lift each instruction within its local context using all information needed from the previous analysis inside of a given function
        // 3. Use the already lifted functions to emit the whole Wasm byte buffer.

        // Step 1:
        // Collect all information that we need to later wire up the imports correctly, this means we look at instructions that can potentially import any variable that originated outside the Wasm module.
        importAnalysis()
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

        self.buildTypeSection()
        self.buildImportSection()
        self.buildFunctionSection()
        self.buildTableSection()
        self.buildMemorySection()
        self.buildTagSection()
        self.buildGlobalSection()

        // Export all functions by default.
        self.buildExportedSection()

        // Build element segments for defined tables.
        self.buildElementSection()

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

        // Currently we also need to build a type section entry for the JSPI types, e.g. objects that are of this specific group.
        let importCount = self.imports.filter( {
            typer.type(of: $0.0).Is(.function()) ||
            typer.type(of: $0.0).Is(.object(ofGroup: "WebAssembly.SuspendableObject")) ||
            typer.type(of: $0.0).Is(.object(ofGroup: "WasmTag"))
        }).count
        let typeCount = importCount + self.functions.count + self.tags.reduce(0, {res, _ in res + 1})

        temp += Leb128.unsignedEncode(typeCount)

        for (importVariable, signature) in self.imports {
            let type = typer.type(of: importVariable)

            // Currently we also need to build a type section entry for the JSPI types, e.g. objects that are of this specific group.
            if type.Is(.function()) || type.Is(.object(ofGroup: "WebAssembly.SuspendableObject")) || type.Is(.object(ofGroup: "WasmTag")) {
                // Get the signature from the imports array.
                // The signature of this function is a JS signature, it was converted when we decided to perform a WasmJSCall. This means we have selected a somewhat matching signature (see convertJsSignatureToWasmSignature).
                // The code that follows and the code that performs the call depends on this signature and as such we need to build the right signature here that matches this.
                // The signature was encoded in the instruction and is also tracked in the imports array, so we use that here.
                // One could assert that the seen signature here is a possible converted signature, not sure that is necessary though.
                let signature = signature!
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
        }

        // We only need the parameters here.
        for functionInfo in self.functions {
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

        for (_, parameters) in self.tags {
            temp += [0x60]
            temp += Leb128.unsignedEncode(parameters.count)
            for paramType in parameters {
                switch paramType {
                case .plain(let paramType):
                    temp += ILTypeMapping[paramType]!
                default:
                    fatalError("unreachable")
                }
            }
            // Tag signatures don't have a return type.
            temp += Leb128.unsignedEncode(0)
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

    private func buildImportSection() {
        if self.imports.isEmpty {
            return
        }

        self.bytecode += [WasmSection.import.rawValue]

        var temp = Data()

        temp += Leb128.unsignedEncode(self.imports.map { $0 }.count)

        // Build the import components of this vector that consist of mod:name, nm:name, and d:importdesc
        for (idx, importVariable) in self.imports.map({$0.0}).enumerated() {
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
                temp += [0x0, UInt8(nextSignatureIdx)] // import kind and signature (type) idx

                // Update the index space, these indices have to be set before the exports are set
                functionIdxBase += 1
                nextSignatureIdx += 1
                continue
            }
            if type.Is(.object(ofGroup: "WasmMemory")) {
                let minPages = type.wasmMemoryType!.limits.min
                let maxPages = type.wasmMemoryType!.limits.max
                temp += Data([0x2])
                if let maxPages = maxPages {
                    temp += Data([0x1] + Leb128.unsignedEncode(minPages) + Leb128.unsignedEncode(maxPages))
                } else {
                    temp += Data([0x0] + Leb128.unsignedEncode(minPages))
                }
                continue
            }
            if type.Is(.object(ofGroup: "WasmTable")) {
                // let tableType = type.wasmTableType!.tableType
                let tableType = ILType.wasmExternRef
                // let minSize = type.wasmTableType!.minSize
                let minSize = 10
                // let maxSize = type.wasmTableType!.maxSize
                let maxSize: Int? = 20
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
                temp += [0x4, 0x0] + Leb128.unsignedEncode(nextSignatureIdx)
                nextSignatureIdx += 1
                continue
            }
            fatalError("unreachable")
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
            temp.append(Leb128.unsignedEncode(nextSignatureIdx + idx))
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
            let tableType = op.tableType
            let minSize = op.minSize
            let maxSize = op.maxSize

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

    // Only supports:
    // - active segments
    // - with custom table id
    // - function-indices-as-elements (i.e. case 2 of the spec: https://webassembly.github.io/spec/core/binary/modules.html#element-section)
    // - one segment per table (assumes entries are continuous)
    // - constant starting index.
    private func buildElementSection() {
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
        let tableIndex = self.resolveTableIdx(forInput: instruction.output)
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
          let functionId = resolveFunctionIdx(forInput: entry)
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

        temp += Leb128.unsignedEncode(memories.count)

        // TODO(evih): Encode sharedness.
        for instruction in memories {
            let type = typer.type(of: instruction.output)
            let minPages = type.wasmMemoryType!.limits.min
            let maxPages = type.wasmMemoryType!.limits.max
            if let maxPages = maxPages {
                temp += Data([0x1] + Leb128.unsignedEncode(minPages) + Leb128.unsignedEncode(maxPages))
            } else {
                temp += Data([0x0] + Leb128.unsignedEncode(minPages))
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

    private func buildTagSection() {
        if self.tags.isEmpty {
            return // Skip the whole section.
        }

        self.bytecode.append(WasmSection.tag.rawValue)
        var section = Data()
        section += Leb128.unsignedEncode(self.tags.reduce(0, {res, _ in res + 1}))
        for (i, _) in self.tags.enumerated() {
            section.append(0)
            section.append(Leb128.unsignedEncode(nextSignatureIdx + self.functions.count + i))
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
    private func buildExportedSection() {
        self.bytecode += [WasmSection.export.rawValue]

        var temp = Data()

        // TODO: Track the order in which globals are seen by the typer in the program builder and maybe export them by name here like they are seen.
        // This would just be a 'correctness' fix as this mismatch does not have any implications, it should be fixed though to avoid issues down the road as this is a very subtle mismatch.

        // Get the number of imported globals.
        let importedGlobals = self.imports.map({$0.0}).filter {
            typer.type(of: $0).Is(.object(ofGroup: "WasmGlobal"))
        }

        temp += Leb128.unsignedEncode(self.functions.count + importedGlobals.count + self.globals.map { $0 }.count)
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
        case .wasmBeginBlock(_),
             .wasmBeginLoop(_),
             .wasmBeginTry(_),
             .wasmBeginTryDelegate(_):
             self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
             // Needs typer analysis
            return true
        case .wasmBeginCatch(_):
            self.currentFunction!.labelBranchDepthMapping[instr.innerOutput(0)] = self.currentFunction!.variableAnalyzer.wasmBranchDepth
            assert(self.imports.contains(where: { $0.0 == instr.input(0)}) || self.tags.contains(instr.input(0)))
            // Needs typer analysis
            return true
        case .wasmNop(_):
            // Just analyze the instruction but do nothing else here.
            // This lets the typer know that we can skip this instruction without breaking any analysis.
            break
        case .beginWasmFunction(let op):
            functions.append(FunctionInfo(op.signature, Data(), for: self, withArguments: Array(instr.innerOutputs)))
            // Set the current active function as we are *actively* in it.
            currentFunction = self.functions[self.functions.count - 1]
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
            if typer.type(of: input).Is(.label) {
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

            // Instruction has to be a glue instruction now, maybe add an attribute to the instruction that it may have non-wasm inputs, i.e. inputs that do not have a local slot.
            if instr.op is WasmLoadGlobal || instr.op is WasmStoreGlobal || instr.op is WasmJsCall || instr.op is WasmMemoryStore || instr.op is WasmMemoryLoad || instr.op is WasmTableGet || instr.op is WasmTableSet || instr.op is WasmBeginCatch || instr.op is WasmThrow || instr.op is WasmRethrow {
                continue
            }
            fatalError("unreachable")
        }

    }

    private func emitBytesForInstruction(forInstruction instr: Instruction) {
        currentFunction!.appendToCode(lift(instr))
    }

    private func emitStackSpillsIfNecessary(forInstruction instr: Instruction) {
        // Don't emit spills for reassigns. This is specially handled in the `lift` function for reassigns.
        if instr.op is WasmReassign {
            return
        }

        // If we have an output, make sure we store it on the stack as this is a "complex" instruction, i.e. has inputs and outputs
        if instr.numOutputs > 0 {
            assert(!typer.type(of: instr.output).Is(.label))
            // Also spill the instruction
            currentFunction!.spillLocal(forVariable: instr.output)
            // Add the corresponding stack load as an expression, this adds the number of arguments, as output vars always live after the function arguments.
            self.writer.addExpr(for: instr.output, bytecode: Data([0x20, UInt8(currentFunction!.localsInfo.count - 1)]))
        }

        // TODO(cffsmith): Reuse this for handling parameters in loops and blocks.
        if instr.op is WasmBeginCatch {
            // As the parameters are pushed "in order" to the stack, they need to be popped in reverse order.
            for innerOutput in instr.innerOutputs(1...).reversed() {
                currentFunction!.spillLocal(forVariable: innerOutput)
            }
        }
    }

    private func importTagIfNeeded(tag: Variable, parameters: ParameterList) {
        if (!self.tags.contains(tag) && self.imports.firstIndex(where: {variable, _ in variable == tag}) == nil) {
            self.imports.append((tag, parameters => .nothing))
        }
    }

    // Analyze which Variables should be imported. Here we should analyze all instructions that could potentially force an import of a Variable that originates in JavaScript.
    // This usually means if your instruction takes an .object() as an input, it should be checked here.
    // TODO: check if this is still accurate as we now only have defined imports.
    // Also, we export the globals in the order we "see" them, which might mismatch the order in which they are laid out in the binary at the end, which is why we track the order of the globals separately.
    private func importAnalysis() {
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
                if tableDef.tableType == .wasmFuncRef {
                    for definedEntry in instr.inputs {
                        if typer.type(of: definedEntry).Is(.function()) && !self.imports.contains(where: { $0.0 == definedEntry }) {
                            // Ensure deterministic lifting.
                            let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignatureDeterministic(typer.type(of: definedEntry).signature!)
                            self.imports.append((definedEntry, wasmSignature))
                        }
                    }
                }
            case .wasmDefineMemory:
                self.memories.append(instr)
            case .wasmMemoryLoad(_),
                 .wasmMemoryStore(_):
                let memory = instr.input(0)
                if !self.memories.contains(where: {$0.output == memory}) {
                    // TODO(cffsmith) this needs to be changed once we support multimemory as we probably also need to fix the ordering.
                    if !self.imports.map({$0.0}).contains(memory) {
                        self.imports.append((memory, nil))
                    }
                }
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
                importTagIfNeeded(tag: instr.input(0), parameters: op.signature.parameters)

            case .wasmThrow(let op):
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

    /// Helper function to resolve the index, as laid out in the binary format, of an instruction input Variable for a global.
    /// Intended to be called from `lift`.
    func resolveGlobalIdx(forInput input: Variable) -> Int {
        // Get the index for the global and emit it here magically.
        var idx: Int?
        // Can be nil now
        // Check if it is an imported global.
        idx = self.imports.filter({ typer.type(of: $0.0).Is(.object(ofGroup: "WasmGlobal"))}).firstIndex(where: { $0.0 == input })
        // It has to be nil if we enter here, and now we need to find it in the locally defined globals.
        if idx == nil && self.globals.map({ $0.output }).contains(input) {
            // Add the number of imported globals here.
            idx = self.baseDefinedGlobals! + self.globals.firstIndex(where: {$0.output == input})!
        }
        if idx == nil {
            fatalError("WasmStore/LoadGlobal variable \(input) not found as global!")
        }
        return idx!
    }

    func resolveTagIdx(forInput input: Variable) -> Int {
        let tagImports = self.imports.filter{ typer.type(of: $0.0).Is(.object(ofGroup: "WasmTag")) }
        if let idx = tagImports.firstIndex(where: { $0.0 == input }) {
            return idx
        }
        if let idx = self.tags.map({$0}).firstIndex(where: {$0.0 == input}) {
            return tagImports.count + idx
        }
        fatalError("Invalid tag \(input)")
    }
  
    // This is almost identical to the resolveGlobalIdx.
    func resolveTableIdx(forInput input: Variable) -> Int {
        var idx: Int?
        // Can be nil now
        // Check if it is an imported table.
        idx = self.imports.filter({ typer.type(of: $0.0).Is(.object(ofGroup: "WasmTable"))}).firstIndex(where: { $0.0 == input })
        // It has to be nil if we enter here, and now we need to find it in the locally defined tables map.
        if idx == nil && self.tables.map({ $0.output }).contains(input) {
            // Add the number of imported tables here.
            idx = self.baseDefinedTables! + self.tables.firstIndex(where: {$0.output == input})!
        }
        if idx == nil {
            fatalError("WasmTableGet/WasmTableSet variable \(input) not found as table!")
        }
        return idx!
    }

    func resolveFunctionIdx(forInput input: Variable) -> Int {
        return self.imports.filter({typer.type(of: $0.0).Is(.function()) || typer.type(of: $0.0).Is(.object(ofGroup: "WebAssembly.SuspendableObject"))}).firstIndex { $0.0 == input } ??
            self.functionIdxBase + self.functions.firstIndex { $0.outputVariable == input }!
    }

    /// Returns the Bytes that correspond to this instruction.
    /// This will also automatically add bytes that are necessary based on the state of the Lifter.
    /// Example: LoadGlobal with an input variable will resolve the input variable to a concrete global index.
    private func lift(_ wasmInstruction: Instruction) -> Data {
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
        case .wasmMemoryLoad(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            return Data([op.loadType.rawValue]) + Leb128.unsignedEncode(0) + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmMemoryStore(let op):
            // The memory immediate is {staticOffset, align} where align is 0 by default. Use signed encoding for potential bad (i.e. negative) offsets.
            return Data([op.storeType.rawValue]) + Leb128.unsignedEncode(0) + Leb128.signedEncode(Int(op.staticOffset))
        case .wasmJsCall(let op):
            // We filter first, such that we get the index of functions only.
            let index = imports.filter({
                // TODO, switch query?
                typer.type(of: $0.0).Is(.function()) || typer.type(of: $0.0).Is(.object(ofGroup: "WebAssembly.SuspendableObject"))
            }).firstIndex(where: {
                wasmInstruction.input(0) == $0.0 && op.functionSignature == $0.1
            })!
            return Data([0x10]) + Leb128.unsignedEncode(index)
        case .wasmBeginBlock(_):
            // A Block can expect an item on the stack at the end, just like a function. This would be encoded just after the block begin (0x02) byte.
            // For now, we just have the empty block but this instruction could take another input which determines the value that we expect on the stack.
            // It would then behave similar to a function just with different branching behavior.
            // Ref: https://webassembly.github.io/spec/core/binary/instructions.html#binary-blocktype
            return Data([0x02] + [0x40])
        case .wasmBeginLoop(_):
            // 0x03 is the loop instruction and 0x40 is the empty block type, just like in .wasmBeginBlock
            return Data([0x03] + [0x40])
        case .wasmBeginTry(_),
             .wasmBeginTryDelegate(_):
            // 0x06 is the try instruction and 0x40 is the empty block type, just like in .wasmBeginBlock
            return Data([0x06] + [0x40])
        case .wasmBeginCatchAll(_):
            return Data([0x19])
        case .wasmBeginCatch(_):
            return Data([0x07] + Leb128.unsignedEncode(resolveTagIdx(forInput: wasmInstruction.input(0))))
        case .wasmEndCatch(_):
            return Data([])
        case .wasmEndLoop(_),
                .wasmEndIf(_),
                .wasmEndTry(_),
                .wasmEndBlock(_):
            // Basically the same as EndBlock, just an explicit instruction.
            return Data([0x0B])
        case .wasmEndTryDelegate(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x18]) + Leb128.unsignedEncode(branchDepth)
        case .wasmThrow(_):
            return Data([0x08] + Leb128.unsignedEncode(resolveTagIdx(forInput: wasmInstruction.input(0))))
        case .wasmRethrow(_):
            let blockDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]!
            return Data([0x09] + Leb128.unsignedEncode(blockDepth))
        case .wasmBranch(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
            return Data([0x0C]) + Leb128.unsignedEncode(branchDepth)
        case .wasmBranchIf(_):
            let branchDepth = self.currentFunction!.variableAnalyzer.wasmBranchDepth - self.currentFunction!.labelBranchDepthMapping[wasmInstruction.input(0)]! - 1
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
            if let stackSlot = currentFunction!.getStackSlot(for: wasmInstruction.input(0)) {

                // Emit the instruction now, with input and stackslot. Since we load this manually we don't need
                // to emit bytes in the emitInputLoadsIfNecessary.
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
            return Data([0x01])
        case .wasmUnreachable(_):
            return Data([0x00])
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
         case .wasmI64x2LoadSplat(let op):
            return Data([0xFD]) + Leb128.unsignedEncode(0x0A) + Leb128.unsignedEncode(0) + Leb128.unsignedEncode(op.offset)

        default:
             fatalError("unreachable")
        }
    }
}
