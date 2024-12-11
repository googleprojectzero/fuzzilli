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
// These insert one or more instructions into a wasm module.
//
public let WasmCodeGenerators: [CodeGenerator] = [

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
        let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
        let memSize = Int64(memoryTypeInfo.limits.min * WasmOperation.WasmConstants.specWasmMemPageSize)
        if (memSize == 0) {
            return
        }
        let function = b.currentWasmModule.currentWasmFunction

        let loadType = chooseUniform(from: WasmMemoryLoadType.allCases)

        // Most of the times, generate an in-bounds offset (dynamicOffset + staticOffset) into the memory.
        // With 10% probability, choose one randomly from the already existing ones.
        var staticOffset = b.randomNonNegativeIndex()
        var dynamicOffset: Variable
        if let randVar = b.randomVariable(ofType: memoryTypeInfo.isMemory64 ? .wasmi64 : .wasmi32), probability(0.1) {
            dynamicOffset = randVar
        } else {
            let dynamicOffsetValue = b.randomNonNegativeIndex() % memSize
            dynamicOffset = memoryTypeInfo.isMemory64 ? function.consti64(dynamicOffsetValue)
                                               : function.consti32(Int32(dynamicOffsetValue))
            staticOffset %= (memSize - dynamicOffsetValue)
        }

        function.wasmMemoryLoad(memory: memory, dynamicOffset: dynamicOffset, loadType: loadType, staticOffset: staticOffset)
    },

    CodeGenerator("WasmMemoryStoreGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
        let memSize = Int64(memoryTypeInfo.limits.min * WasmOperation.WasmConstants.specWasmMemPageSize)
        if (memSize == 0) {
            return
        }
        let function = b.currentWasmModule.currentWasmFunction

        // Most of the times, generate an in-bounds offset (dynamicOffset + staticOffset) into the memory.
        // With 10% probability, choose one randomly from the already existing ones.
        var staticOffset = b.randomNonNegativeIndex()
        var dynamicOffset: Variable
        if let randVar = b.randomVariable(ofType: memoryTypeInfo.isMemory64 ? .wasmi64 : .wasmi32), probability(0.1) {
            dynamicOffset = randVar
        } else {
            let dynamicOffsetValue = b.randomNonNegativeIndex() % memSize
            dynamicOffset = memoryTypeInfo.isMemory64 ? function.consti64(dynamicOffsetValue)
                                               : function.consti32(Int32(dynamicOffsetValue))
            staticOffset %= (memSize - dynamicOffsetValue)
        }

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

    CodeGenerator("WasmTruncatef32Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        // We are using a trick here and for all other unsigned truncations. If the input is a negative float, the operation will result in a runtime error, therefore we will always emit an f32UnOp Abs() operation to make sure that the operation wont throw.
        // Minimization will then automatically remove the f32UnOp instruction if it is not necessary.
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let res = function.wasmf32UnOp(input, unOpKind: .Abs)
            function.truncatef32Toi32(res, isSigned: false)
        } else {
            function.truncatef32Toi32(input, isSigned: true)
        }
    },

    CodeGenerator("WasmTruncatef64Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let res = function.wasmf64UnOp(input, unOpKind: .Abs)
            function.truncatef64Toi32(res, isSigned: false)
        } else {
            function.truncatef64Toi32(input, isSigned: true)
        }
    },

    CodeGenerator("WasmExtendi32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.extendi32Toi64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncatef32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let res = function.wasmf32UnOp(input, unOpKind: .Abs)
            function.truncatef32Toi64(res, isSigned: false)
        } else {
            function.truncatef32Toi64(input, isSigned: true)
        }
    },

    CodeGenerator("WasmTruncatef64Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        if probability(0.5) {
            let res = function.wasmf64UnOp(input, unOpKind: .Abs)
            function.truncatef64Toi64(res, isSigned: false)
        } else {
            function.truncatef64Toi64(input, isSigned: true)
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
        // TODO(mliedtke): Also add support for return values (and probably find a suitable mechanism that we can also use for functions).
        // A good solution would probably be to make the endBlock take the return type as an input.
        function.wasmBuildBlock(with: parameters => .nothing, args: args) { label, args in
            b.buildRecursive()
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

    RecursiveCodeGenerator("WasmLegacyTryGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildLegacyTry(with: [] => .nothing) { label, args in
            b.buildRecursive(block: 1, of: 2, n: 4)
        } catchAllBody: {
            b.buildRecursive(block: 2, of: 2, n: 4)
        }
    },

    RecursiveCodeGenerator("WasmLegacyCatchGenerator", inContext: .wasmTry, inputs: .required(.object(ofGroup: "WasmTag"))) { b, value in
        let function = b.currentWasmModule.currentWasmFunction
        function.WasmBuildLegacyCatch(tag: value) { exception, args in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("WasmLegacyTryDelegateGenerator", inContext: .wasmFunction, inputs: .required(.label)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildLegacyTryDelegate(with: [] => .nothing, body: { _, _ in
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

    CodeGenerator("WasmBranchGenerator", inContext: .wasmFunction, inputs: .required(.label)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBranch(to: label)
    },

    CodeGenerator("WasmBranchIfGenerator", inContext: .wasmFunction, inputs: .required(.label, .wasmi32)) { b, label, conditionVar in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBranchIf(conditionVar, to: label)
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

//    CodeGenerator("WasmI64x2LoadSplatGenerator", inContext: .wasmFunction, inputs: .required(.wasmMemory)) { b, memoryRef in
//        let function = b.currentWasmModule.currentWasmFunction
//        b.currentWasmModule.addMemory(importing: memoryRef);
//        function.wasmI64x2LoadSplat(memoryRef: memoryRef)
//    },
]
