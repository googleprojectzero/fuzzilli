// Copyright 2024 Google LLC
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

//
// Wasm Code generators.
//
// These Generators all relate to Wasm and either use the WebAssembly object or
// insert one or more instructions into a wasm module.
//
public let WasmCodeGenerators: [CodeGenerator] = [

    /// Wasm related generators in JavaScript

    CodeGenerator("WasmGlobalGenerator", inContext: .javascript) { b in
        // TODO: add externref/funcref?
        // TODO: maybe put this as static func into WasmGlobal enum? no access to builder for interesting values though....
        let wasmGlobal: WasmGlobal = withEqualProbability({
            return .wasmf32(Float32(b.randomFloat()))
        }, {
            return .wasmf64(b.randomFloat())
        }, {
            return .wasmi32(Int32(truncatingIfNeeded: b.randomInt()))
        }, {
            return .wasmi64(b.randomInt())
        })
        b.createWasmGlobal(value: wasmGlobal, isMutable: probability(0.5))
    },

    CodeGenerator("WasmMemoryGenerator", inContext: .javascript) { b in
        let minPages = Int.random(in: 0..<10)
        var maxPages: Int? = nil
        if probability(0.5) {
            maxPages = Int.random(in: minPages...WasmOperation.WasmConstants.specMaxWasmMem32Pages)
        }
        b.createWasmMemory(minPages: minPages, maxPages: maxPages, isShared: probability(0.5))
    },

    CodeGenerator("WasmTagGenerator", inContext: .javascript) { b in
        if probability(0.5) {
            b.createWasmJSTag()
        } else {
            b.createWasmTag(parameterTypes: b.randomTagParameters())
        }
    },

    // Wasm Module Generator, this is fairly important as it creates the context necessary to run the Wasm CodeGenerators.
    RecursiveCodeGenerator("WasmModuleGenerator", inContext: .javascript) { b in
        let m = b.buildWasmModule { m in
            b.buildRecursive()
        }

        let exports = m.loadExports()

        for (methodName, signature) in m.getExportedMethods() {
            b.callMethod(methodName, on: exports, withArgs: b.randomArguments(forCallingFunctionWithSignature: signature))
        }
    },

    RecursiveCodeGenerator("WasmLegacyTryCatchComplexGenerator", inContext: .javascript) { b in
        let emitCatchAll = Int.random(in: 0...1)
        let catchCount = Int.random(in: 0...3)
        var blockIndex = 1
        let blockCount = 2 + catchCount + emitCatchAll
        // Create a few tags in JS.
        b.createWasmJSTag()
        b.createWasmTag(parameterTypes: b.randomTagParameters())
        let m = b.buildWasmModule { m in
            // Create a few tags in Wasm.
            m.addTag(parameterTypes: b.randomTagParameters())
            m.addTag(parameterTypes: b.randomTagParameters())
            // Build some other wasm module stuff (tables, memories, gobals, ...)
            b.buildRecursive(block: blockIndex, of: blockCount, n: 4)
            blockIndex += 1
            m.addWasmFunction(with: b.randomWasmSignature()) { function, _ in
                b.buildPrefix()
                function.wasmBuildLegacyTry(with: [] => .nothing, args: [], body: {label, _ in
                    b.buildRecursive(block: blockIndex, of: blockCount, n: 4)
                    blockIndex += 1
                    for _ in 0..<catchCount {
                        function.WasmBuildLegacyCatch(tag: b.randomVariable(ofType: .object(ofGroup: "WasmTag"))!) { label, exception, args in
                            b.buildRecursive(block: blockIndex, of: blockCount, n: 4)
                            blockIndex += 1
                        }
                    }
                }, catchAllBody: emitCatchAll == 1 ? { label in
                    b.buildRecursive(block: blockIndex, of: blockCount, n: 4)
                    blockIndex += 1
                } : nil)
            }
        }
        assert(blockIndex == blockCount + 1)

        let exports = m.loadExports()
        for (methodName, signature) in m.getExportedMethods() {
            b.callMethod(methodName, on: exports, withArgs: b.randomArguments(forCallingFunctionWithSignature: signature))
        }
    },

    // Primitive Value Generators

    ValueGenerator("WasmLoadi32Generator", inContext: .wasmFunction) { b, n in
        let function = b.currentWasmModule.currentWasmFunction
        for _ in 0..<n {
            function.consti32(Int32(truncatingIfNeeded: b.randomInt()))
        }
    },

    ValueGenerator("WasmLoadi64Generator", inContext: .wasmFunction) { b, n in
        let function = b.currentWasmModule.currentWasmFunction
        for _ in 0..<n {
            function.consti64(b.randomInt())
        }
    },

    ValueGenerator("WasmLoadf32Generator", inContext: .wasmFunction) { b, n in
        let function = b.currentWasmModule.currentWasmFunction
        for _ in 0..<n {
            function.constf32(Float(b.randomFloat()))
        }
    },

    ValueGenerator("WasmLoadf64Generator", inContext: .wasmFunction) { b, n in
        let function = b.currentWasmModule.currentWasmFunction
        for _ in 0..<n {
            function.constf64(b.randomFloat())
        }
    },

    ValueGenerator("WasmLoadPrimitivesGenerator", inContext: .wasmFunction) { b, n in
        let function = b.currentWasmModule.currentWasmFunction

        for _ in 0..<n {
            withEqualProbability({
                function.consti32(Int32(truncatingIfNeeded: b.randomInt()))
            }, {
                function.consti64(b.randomInt())
            }, {
                function.constf32(Float32(b.randomFloat()))
            }, {
                function.constf64(b.randomFloat())
            })
        }
    },

    // Memory Generators

    // TODO(evih): Implement shared memories and memory64.
    CodeGenerator("WasmDefineMemoryGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule
        // TODO(evih): We can define only one memory so far.
        if (module.memory != nil) {
            return
        }
        let isMemory64 = probability(0.5)

        let minPages = Int.random(in: 1..<10)
        let maxPages: Int?
        if probability(0.5) {
            maxPages = nil
        } else {
            maxPages = Int.random(in: minPages...(isMemory64 ? WasmOperation.WasmConstants.specMaxWasmMem64Pages
                                                             : WasmOperation.WasmConstants.specMaxWasmMem32Pages))
        }
        module.memory = module.addMemory(minPages: minPages, maxPages: maxPages, isShared: false, isMemory64: isMemory64)
    },

    CodeGenerator("WasmMemoryLoadGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let (dynamicOffset, staticOffset) = b.generateMemoryIndexes(forMemory: memory)
        let loadType = chooseUniform(from: WasmMemoryLoadType.allCases)

        function.wasmMemoryLoad(memory: memory, dynamicOffset: dynamicOffset, loadType: loadType, staticOffset: staticOffset)
    },

    CodeGenerator("WasmMemoryStoreGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let (dynamicOffset, staticOffset) = b.generateMemoryIndexes(forMemory: memory)

        // Choose a `WasmMemoryStoreType` for which there is an existing Variable with a matching number type.
        // Shuffle them so we don't have a bias in the ordering.
        let storeTypes = WasmMemoryStoreType.allCases.shuffled()
        for storeType in storeTypes {
            if let storeVar = b.randomVariable(ofType: storeType.numberType()) {
                function.wasmMemoryStore(memory: memory, dynamicOffset: dynamicOffset, value: storeVar, storeType: storeType, staticOffset: staticOffset)
                return
            }
        }
    },

    // Global Generators

    CodeGenerator("WasmDefineGlobalGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule

        let wasmGlobal: WasmGlobal = b.randomWasmGlobal()
        module.addGlobal(wasmGlobal: wasmGlobal, isMutable: probability(0.5))
    },

    CodeGenerator("WasmDefineTableGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule
        // TODO(manoskouk): Generalize these.
        let minSize = 10
        let maxSize: Int? = nil
        let elementType = ILType.wasmFuncRef

        var definedEntryIndices: [Int] = []
        var definedEntryValues: [Variable] = []

        let entryType = elementType == .wasmFuncRef ? .wasmFuncRef | .function() : .object()

        // Currently, only generate entries for funcref tables.
        // TODO(manoskouk): Generalize this.
        if (elementType == .wasmFuncRef) {
            let entryValue = b.randomVariable(ofType: entryType)

            if entryValue != nil {
                // There is at least one function in scope. Add some initial entries to the table.
                // TODO(manoskouk): Generalize this.
                definedEntryIndices = [0, 1, 2, 3, 4]
                for _ in definedEntryIndices {
                    definedEntryValues.append(b.randomVariable(ofType: entryType)!)
                }
            }
        }

        module.addTable(elementType: elementType, minSize: minSize, maxSize: maxSize, definedEntryIndices: definedEntryIndices, definedEntryValues: definedEntryValues)
    },

    CodeGenerator("WasmGlobalStoreGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmGlobal"))) { b, global in
        let function = b.currentWasmModule.currentWasmFunction

        let type = b.type(of: global)

        if !type.wasmGlobalType!.isMutable {
            return
        }

        let globalType = type.wasmGlobalType!.valueType

        let storeVar = b.randomVariable(ofType: globalType)

        if let storeVar = storeVar {
            function.wasmStoreGlobal(globalVariable: global, to: storeVar)
        }
    },

    CodeGenerator("WasmGlobalLoadGenerator", inContext: [.wasmFunction], inputs: .required(.object(ofGroup: "WasmGlobal"))) { b, global in
        let function = b.currentWasmModule.currentWasmFunction

        function.wasmLoadGlobal(globalVariable: global)
    },


    // Binary Operations Generators

    CodeGenerator("Wasmi32BinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32, .wasmi32)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmIntegerBinaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi32BinOp(inputA, inputB, binOpKind: op)
    },

    CodeGenerator("Wasmi64BinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi64, .wasmi64)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmIntegerBinaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi64BinOp(inputA, inputB, binOpKind: op)
    },

    CodeGenerator("Wasmf32BinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf32, .wasmf32)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmFloatBinaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf32BinOp(inputA, inputB, binOpKind: op)
    },

    CodeGenerator("Wasmf64BinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf64, .wasmf64)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmFloatBinaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf64BinOp(inputA, inputB, binOpKind: op)
    },

    // Unary Operations Generators

    CodeGenerator("Wasmi32UnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let op = chooseUniform(from: WasmIntegerUnaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi32UnOp(input, unOpKind: op)
    },

    CodeGenerator("Wasmi64UnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let op = chooseUniform(from: WasmIntegerUnaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi64UnOp(input, unOpKind: op)
    },

    CodeGenerator("Wasmf32UnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let op = chooseUniform(from: WasmFloatUnaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf32UnOp(input, unOpKind: op)
    },

    CodeGenerator("Wasmf64UnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let op = chooseUniform(from: WasmFloatUnaryOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf64UnOp(input, unOpKind: op)
    },

    // Compare Operations Generators

    CodeGenerator("Wasmi32CompareOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32, .wasmi32)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmIntegerCompareOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi32CompareOp(inputA, inputB, using: op)
    },

    CodeGenerator("Wasmi64CompareOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmi64, .wasmi64)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmIntegerCompareOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi64CompareOp(inputA, inputB, using: op)
    },

    CodeGenerator("Wasmf32CompareOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf32, .wasmf32)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmFloatCompareOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf32CompareOp(inputA, inputB, using: op)
    },

    CodeGenerator("Wasmf64CompareOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmf64, .wasmf64)) { b, inputA, inputB  in
        let op = chooseUniform(from: WasmFloatCompareOpKind.allCases)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmf64CompareOp(inputA, inputB, using: op)
    },

    CodeGenerator("Wasmi32EqzGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi32EqualZero(input)
    },

    CodeGenerator("Wasmi64EqzGenerator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmi64EqualZero(input)
    },

    // Numerical Conversion Operations

    CodeGenerator("WasmWrapi64Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.wrapi64Toi32(input)
    },

    CodeGenerator("WasmTruncatef32Toi32Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let value = function.constf32(Float32(b.randomSize(upTo: Int64(Int32.max))))
            function.truncatef32Toi32(value, isSigned: false)
        } else {
            let value = function.constf32(Float32(b.randomInt() % Int64(Int32.max)))
            function.truncatef32Toi32(value, isSigned: true)
        }
    },

    CodeGenerator("WasmTruncatef64Toi32Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let value = function.constf64(Float64(b.randomSize(upTo: Int64(Int32.max))))
            function.truncatef64Toi32(value, isSigned: false)
        } else {
            let value = function.constf64(Float64(b.randomInt() % Int64(Int32.max)))
            function.truncatef64Toi32(value, isSigned: true)
        }
    },

    CodeGenerator("WasmExtendi32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.extendi32Toi64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncatef32Toi64Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let value = function.constf32(Float32(b.randomSize(upTo: Int64(Int32.max))))
            function.truncatef32Toi64(value, isSigned: false)
        } else {
            let value = function.constf32(Float32(b.randomInt() % Int64(Int32.max)))
            function.truncatef32Toi64(value, isSigned: true)
        }
    },

    CodeGenerator("WasmTruncatef64Toi64Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let value = function.constf64(Float64(b.randomSize()))
            function.truncatef64Toi64(value, isSigned: false)
        } else {
            let value = function.constf64(Float64(b.randomInt()))
            function.truncatef64Toi64(value, isSigned: true)
        }
    },

    CodeGenerator("WasmConverti32Tof32Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.converti32Tof32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmConverti64Tof32Generator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.converti64Tof32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmDemotef64Tof32Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.demotef64Tof32(input)
    },

    CodeGenerator("WasmConverti32Tof64Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.converti32Tof64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmConverti64Tof64Generator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.converti64Tof64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmPromotef32Tof64Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.promotef32Tof64(input)
    },

    CodeGenerator("WasmReinterpretGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32 | .wasmf32 | .wasmi64 | .wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        switch b.type(of: input) {
        case .wasmf32:
            function.reinterpretf32Asi32(input)
        case .wasmf64:
            function.reinterpretf64Asi64(input)
        case .wasmi32:
            function.reinterpreti32Asf32(input)
        case .wasmi64:
            function.reinterpreti64Asf64(input)
        default:
            fatalError("Unexpected wasm primitive type")
        }
    },

    CodeGenerator("WasmSignExtendIntoi32Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        withEqualProbability({
            function.signExtend8Intoi32(input)
        }, {
            function.signExtend16Intoi32(input)
        })
    },

    CodeGenerator("WasmSignExtendIntoi64Generator", inContext: .wasmFunction, inputs: .required(.wasmi64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        withEqualProbability({
            function.signExtend8Intoi64(input)
        }, {
            function.signExtend16Intoi64(input)
        }, {
            function.signExtend32Intoi64(input)
        })
    },

    CodeGenerator("WasmTruncateSatf32Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncateSatf32Toi32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncateSatf64Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncateSatf64Toi32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncateSatf32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncateSatf32Toi64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncateSatf64Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncateSatf64Toi64(input, isSigned: probability(0.5))
    },

    // Control Flow Generators

    RecursiveCodeGenerator("WasmFunctionGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule
        module.addWasmFunction(with: b.randomWasmSignature()) { _, _ in
            b.buildPrefix()
            b.buildRecursive()
        }
    },

    CodeGenerator("WasmReturnGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction

        if function.signature.outputType.Is(.nothing) {
            function.wasmReturn()
        } else {
            let returnVariable = b.randomVariable(ofType: function.signature.outputType) ?? function.generateRandomWasmVar(ofType: function.signature.outputType)

            function.wasmReturn(returnVariable)
        }
    },

    CodeGenerator("WasmJsCallGenerator", inContext: .wasmFunction, inputs: .required(.function())) { b, callable in
        let function = b.currentWasmModule.currentWasmFunction
        if let (wasmSignature, arguments) = b.randomWasmArguments(forCallingJsFunction: callable) {
            function.wasmJsCall(function: callable, withArgs: arguments, withWasmSignature: wasmSignature)
        }
    },

    // We cannot store to funcRefs or externRefs if they are not in a slot.
    CodeGenerator("WasmReassignmentGenerator", inContext: .wasmFunction, inputs: .oneWasmNumericalPrimitive) { b, v in
        let module = b.currentWasmModule
        let function = module.currentWasmFunction

        let reassignmentVariable = b.randomVariable(ofType: b.type(of: v)) ?? function.generateRandomWasmVar(ofType: b.type(of: v))

        assert(b.type(of: reassignmentVariable).Is(.wasmPrimitive))

        function.wasmReassign(variable: v, to: reassignmentVariable)
    },

    RecursiveCodeGenerator("WasmBlockGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildBlock(with: [] => .nothing, args: []) { label, args in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("WasmBlockWithSignatureGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = (0..<5).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        let outputType = b.randomWasmBlockOutputType()
        if outputType != .nothing {
            function.wasmBuildBlockWithResult(with: parameters => outputType, args: args) { label, args in
                b.buildRecursive()
                return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
            }
        } else {
            function.wasmBuildBlock(with: parameters => outputType, args: args) { label, args in
                b.buildRecursive()
            }
        }
    },

    RecursiveCodeGenerator("WasmLoopGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        let loopCtr = function.consti32(10)

        function.wasmBuildLoop(with: [] => .nothing) { label, args in
            let result = function.wasmi32BinOp(loopCtr, function.consti32(1), binOpKind: .Sub)
            function.wasmReassign(variable: loopCtr, to: result)

            b.buildRecursive()

            // Backedge of loop, we continue if it is not equal to zero.
            let isNotZero = function.wasmi32CompareOp(loopCtr, function.consti32(0), using: .Ne)
            function.wasmBranchIf(isNotZero, to: label)

        }
    },

    RecursiveCodeGenerator("WasmLoopWithSignatureGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Count upwards here to make it slightly more different from the other loop generator.
        // Also, instead of using reassign, this generator uses the signature to pass and update the loop counter.
        let randomArgs = (0..<5).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let randomArgTypes = randomArgs.map{b.type(of: $0)}
        let args = [function.consti32(0)] + randomArgs
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        let outputType = b.randomWasmBlockOutputType(allowVoid: false)
        // Note that due to the do-while style implementation, the actual iteration count is at least 1.
        let iterationCount = Int32.random(in: 0...16)

        function.wasmBuildLoop(with: parameters => outputType, args: args) { label, loopArgs in
            b.buildRecursive()
            let loopCtr = function.wasmi32BinOp(args[0], function.consti32(1), binOpKind: .Add)
            let condition = function.wasmi32CompareOp(loopCtr, function.consti32(iterationCount), using: .Lt_s)
            let backedgeArgs = [loopCtr] + randomArgTypes.map{b.randomVariable(ofType: $0)!}
            function.wasmBranchIf(condition, to: label, args: backedgeArgs)
            return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
        }
    },

    RecursiveCodeGenerator("WasmLegacyTryCatchGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        // TODO(mliedtke): Make the argument count random here and in other block generators.
        let args = (0..<5).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        let tags = (0..<Int.random(in: 0...5)).map {_ in b.findVariable { b.type(of: $0).isWasmTagType }}.filter {$0 != nil}.map {$0!}
        let recursiveCallCount = 2 + tags.count
        function.wasmBuildLegacyTry(with: parameters => .nothing, args: args) { label, args in
            b.buildRecursive(block: 1, of: recursiveCallCount, n: 4)
            for (i, tag) in tags.enumerated() {
                function.WasmBuildLegacyCatch(tag: tag) { _, _, _ in
                    b.buildRecursive(block: 2 + i, of: recursiveCallCount, n: 4)
                }
            }
        } catchAllBody: { label in
            b.buildRecursive(block: 2 + tags.count, of: recursiveCallCount, n: 4)
        }
    },

    RecursiveCodeGenerator("WasmLegacyTryCatchWithResultGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = (0..<Int.random(in: 0...5)).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        let tags = (0..<Int.random(in: 0...5)).map {_ in b.findVariable { b.type(of: $0).isWasmTagType }}.filter {$0 != nil}.map {$0!}
        // Disallowing void here to simplify the logic. The WasmLegacyTryCatchGenerator generates try-catch blocks without a result type.
        let outputType = b.randomWasmBlockOutputType(allowVoid: false)
        let signature = parameters => outputType
        let recursiveCallCount = 2 + tags.count
        function.wasmBuildLegacyTryWithResult(with: signature, args: args, body: { label, args in
            b.buildRecursive(block: 1, of: recursiveCallCount, n: 4)
            return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
        }, catchClauses: tags.enumerated().map {i, tag in (tag, {_, _, _ in
                b.buildRecursive(block: 2 + i, of: recursiveCallCount, n: 4)
                return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
        })}, catchAllBody: { label in
            b.buildRecursive(block: 2 + tags.count, of: recursiveCallCount, n: 4)
            return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
        })
    },

    RecursiveCodeGenerator("WasmLegacyTryDelegateGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = (0..<5).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        function.wasmBuildLegacyTryDelegate(with: parameters => .nothing, args: args, body: { _, _ in
            b.buildRecursive()
        }, delegate: label)
    },

    // The variable we reassign to has to be a numerical primitive, e.g. something that looks like a number (can be a global)
    // We cannot reassign to a .wasmFuncRef or .wasmExternRef though, as they need to be in a local slot.
    RecursiveCodeGenerator("WasmIfElseGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32, .wasmNumericalPrimitive)) { b, conditionVar, outputVar in
        let function = b.currentWasmModule.currentWasmFunction

        let assignProb = probability(0.2)

        function.wasmBuildIfElse(conditionVar) {
            b.buildRecursive(block: 1, of: 2, n: 4)
            if let variable = b.randomVariable(ofType: b.type(of: outputVar)) {
                function.wasmReassign(variable: variable, to: outputVar)
            }
        } elseBody: {
            b.buildRecursive(block: 2, of: 2, n: 4)
            if let variable = b.randomVariable(ofType: b.type(of: outputVar)) {
                function.wasmReassign(variable: variable, to: outputVar)
            }
        }
    },

    RecursiveCodeGenerator("WasmIfElseWithSignatureGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, conditionVar in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = (0..<5).map {_ in b.findVariable {b.type(of: $0).Is(.wasmPrimitive)}}.filter {$0 != nil}.map {$0!}
        let parameters = args.map {arg in Parameter.plain(b.type(of: arg))}
        let outputType = b.randomWasmBlockOutputType()
        if outputType != .nothing {
            function.wasmBuildIfElseWithResult(conditionVar, signature: parameters => outputType, args: args) { label, args in
                b.buildRecursive(block: 1, of: 2, n: 4)
                return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
            } elseBody: { label, args in
                b.buildRecursive(block: 2, of: 2, n: 4)
                return b.randomVariable(ofType: outputType) ?? function.generateRandomWasmVar(ofType: outputType)
            }
        } else {
            function.wasmBuildIfElse(conditionVar, signature: parameters => outputType, args: args) { label, args in
                b.buildRecursive(block: 1, of: 2, n: 4)
            } elseBody: { label, args in
                b.buildRecursive(block: 2, of: 2, n: 4)
            }
        }
    },

    CodeGenerator("WasmSelectGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, condition in
        let function = b.currentWasmModule.currentWasmFunction
        let supportedTypes : ILType = .wasmi32 | .wasmi64 | .wasmf32 | .wasmf64 | .wasmExternRef
        // The condition is an i32, so we should always find at least that one as a possible input.
        let trueValue = b.randomVariable(ofType: supportedTypes)!
        let selectType = b.type(of: trueValue)
        let falseValue = b.randomVariable(ofType: selectType)!
        function.wasmSelect(type: selectType, on: condition, trueValue: trueValue, falseValue: falseValue)
    },

    CodeGenerator("WasmThrowGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTag"))) { b, tag in
        let function = b.currentWasmModule.currentWasmFunction
        let wasmTagType = b.type(of: tag).wasmTagType!
        if wasmTagType.isJSTag {
            // A JSTag cannot be thrown from Wasm.
            return
        }
        var args : [Variable] = []
        for param in wasmTagType.parameters {
            switch(param) {
                case .plain(let t):
                    if let randVar = b.randomVariable(ofType: t) {
                        args.append(randVar)
                    } else {
                        args.append(function.generateRandomWasmVar(ofType: t))
                    }
                default:
                    fatalError("Unexpected non-plain type in tag")
            }
        }
        function.WasmBuildThrow(tag: tag, inputs: args)
    },

    CodeGenerator("WasmRethrowGenerator", inContext: .wasmFunction, inputs: .required(.exceptionLabel)) { b, exception in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildRethrow(exception)
    },

    CodeGenerator("WasmDefineTagGenerator", inContext: .wasm) {b in
        b.currentWasmModule.addTag(parameterTypes: b.randomTagParameters())
    },

    CodeGenerator("WasmBranchGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        let args = b.type(of: label).wasmLabelType!.parameters.map {
            b.randomVariable(ofType: $0) ?? function.generateRandomWasmVar(ofType: $0)
        }
        function.wasmBranch(to: label, args: args)
    },

    CodeGenerator("WasmBranchIfGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel, .wasmi32)) { b, label, conditionVar in
        let function = b.currentWasmModule.currentWasmFunction
        let args = b.type(of: label).wasmLabelType!.parameters.map {
            b.randomVariable(ofType: $0) ?? function.generateRandomWasmVar(ofType: $0)
        }
        function.wasmBranchIf(conditionVar, to: label, args: args)
    },

    CodeGenerator("ConstSimd128Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.constSimd128(value: (0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    },

    CodeGenerator("WasmSimd128IntegerUnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ return !$0.isFloat() })
        let unOpKind = chooseUniform(from: WasmSimd128IntegerUnOpKind.allCases.filter{
            return $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128IntegerUnOp(input, shape, unOpKind)
    },

    CodeGenerator("WasmSimd128IntegerBinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, lhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ return !$0.isFloat() })
        let binOpKind = chooseUniform(from: WasmSimd128IntegerBinOpKind.allCases.filter{
            return $0.isValidForShape(shape: shape)
        })
        let function = b.currentWasmModule.currentWasmFunction;

        // Shifts take an i32 as an rhs input, the others take a regular .wasmSimd128 input.
        var rhs = switch binOpKind {
        case .shl, .shr_s, .shr_u:
            b.randomVariable(ofType: .wasmi32) ?? function.consti32(Int32(truncatingIfNeeded: b.randomInt()))
        default:
            b.randomVariable(ofType: .wasmSimd128) ?? function.constSimd128(value: (0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        }

        function.wasmSimd128IntegerBinOp(lhs, rhs, shape, binOpKind)
    },

    CodeGenerator("WasmSimd128FloatUnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ return $0.isFloat() })
        let unOpKind = chooseUniform(from: WasmSimd128FloatUnOpKind.allCases.filter{
            return $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128FloatUnOp(input, shape, unOpKind)
    },

    CodeGenerator("WasmSimd128FloatBinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128)) { b, lhs, rhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ return $0.isFloat() })
        let binOpKind = chooseUniform(from: WasmSimd128FloatBinOpKind.allCases.filter{
            return $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128FloatBinOp(lhs, rhs, shape, binOpKind)
    },

    CodeGenerator("WasmSimd128CompareGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128)) { b, lhs, rhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases)
        let compareOpKind = if shape.isFloat() {
            WasmSimd128CompareOpKind.fKind(value: chooseUniform(from: WasmFloatCompareOpKind.allCases))
        } else {
            if shape == .i64x2 {
                // i64x2 does not provide unsigned comparison.
                WasmSimd128CompareOpKind.iKind(value:
                    chooseUniform(from: WasmIntegerCompareOpKind.allCases.filter{
                        return $0 != .Lt_u && $0 != .Le_u && $0 != .Gt_u && $0 != .Ge_u
                    }))
            } else {
                WasmSimd128CompareOpKind.iKind(value:
                    chooseUniform(from: WasmIntegerCompareOpKind.allCases))
            }
        }

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmSimd128Compare(lhs, rhs, shape, compareOpKind)
    },

    CodeGenerator("WasmI64x2SplatGenerator", inContext: .wasmFunction, inputs: .required(.wasmi64)) {b, input in
        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmI64x2Splat(input)
    },

    CodeGenerator("WasmI64x2ExtractLaneGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmI64x2ExtractLane(input, 0)
    },

    CodeGenerator("WasmSimdLoadGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let (dynamicOffset, staticOffset) = b.generateMemoryIndexes(forMemory: memory)
        let kind = chooseUniform(from: WasmSimdLoad.Kind.allCases)
        function.wasmSimdLoad(kind: kind, memory: memory, dynamicOffset: dynamicOffset, staticOffset: staticOffset)
    },

    // TODO: Add three generators for JSPI
    // We need a WrapSuspendingGenerator that takes a callable and wraps it, this should get typed as .object(ofGroup: "WasmSuspenderObject" and we should attach a WasmTypeExtension that stores the signature of the wrapped function
    // Then we need a WasmJsCallSuspendingFunctionGenerator that takes such a WasmSuspenderObject function, unpacks the signature and emits a WasmJsCall
    // Then we also need a WrapPromisingGenerator that requires a WebAssembly module object, gets the exports field and its methods and then wraps one of those.
    // For all of this to work we need to add a WasmTypeExtension and ideally the dynamic object group inference.
]
