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

    // Global Generators

    CodeGenerator("WasmImportGlobalGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule
        // TODO(cffsmith): Ideally this should have a .required(.wasmJsGlobal) and then we could just query the real underlying type and
        // then import that because right now this might not add any instructions and if this generator is picked a lot it might
        // result in a generation failure as we fail to fulfill the quota.
        let visibleJsWasmGlobals = b.getVisibleJsWasmGlobals()
        guard !visibleJsWasmGlobals.isEmpty else {
            return
        }
        let global = chooseUniform(from: visibleJsWasmGlobals)
        module.addGlobal(importing: global)
    },

    CodeGenerator("WasmDefineGlobalGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule

        // TODO: add funcrefs and null refs
        let wasmGlobal: WasmGlobal = b.randomWasmGlobal()

        module.addGlobal(wasmGlobal: wasmGlobal, isMutable: probability(0.5))
    },

    CodeGenerator("WasmGlobalStoreGenerator", inContext: .wasmFunction) { b in
        let module = b.currentWasmModule
        let function = module.currentWasmFunction

        // TODO(cffsmith): Here we should also require this input through some form of type.
        if module.globals.isEmpty {
            return
        }

        let randomGlobal: (Variable, WasmGlobal) = chooseUniform(from: module.globals.map { $0 })

        let storeVar = b.randomVariable(ofType: randomGlobal.1.toType())

        if let storeVar = storeVar {
            function.wasmStoreGlobal(globalVariable: randomGlobal.0, to: storeVar)
        }
    },

    // TODO: this does not see any js variables, as they are hidden when entering wasm(?) (is this true?)
    // Same with the global store generator
    CodeGenerator("WasmGlobalLoadGenerator", inContext: [.wasmFunction]) { b in
        let module = b.currentWasmModule
        let function = module.currentWasmFunction

        if module.globals.isEmpty {
            return
        }

        let randomGlobal: (Variable, WasmGlobal) = chooseUniform(from: module.globals.map { $0 })

        function.wasmLoadGlobal(globalVariable: randomGlobal.0)
    },

    // TODO: add wasmstore/load global generator that does interesting stuff with globals that are defined or imported
    // TODO: add wasmDefineGlobal generator

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
        let function = b.currentWasmModule.currentWasmFunction
        function.truncatef32Toi32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncatef64Toi32Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncatef64Toi32(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmExtendi32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.extendi32Toi64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncatef32Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf32)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncatef32Toi64(input, isSigned: probability(0.5))
    },

    CodeGenerator("WasmTruncatef64Toi64Generator", inContext: .wasmFunction, inputs: .required(.wasmf64)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        function.truncatef64Toi64(input, isSigned: probability(0.5))
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

    CodeGenerator("WasmReinterpretGenerator", inContext: .wasmFunction, inputs: .oneWasmPrimitive) { b, input in
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

    // Control Flow Generators

    RecursiveCodeGenerator("WasmFunctionGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule

        // TODO: add other types here.
        let returnType: ILType = chooseUniform(from: [.wasmi32, .wasmi64, .wasmf32, .wasmf64, .nothing])

        let signature = [] => returnType

        module.addWasmFunction(with: signature) { _, _ in
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

    CodeGenerator("WasmReassignmentGenerator", inContext: .wasmFunction, inputs: .oneWasmPrimitive) { b, v in
        let module = b.currentWasmModule
        let function = module.currentWasmFunction

        let reassignmentVariable = b.randomVariable(ofType: b.type(of: v)) ?? function.generateRandomWasmVar(ofType: b.type(of: v))

        assert(b.type(of: reassignmentVariable).Is(.wasmPrimitive))

        function.wasmReassign(variable: v, to: reassignmentVariable)
    },

    RecursiveCodeGenerator("WasmIfElseGenerator", inContext: .wasmFunction, inputs: .oneWasmPrimitive) { b, conditionVar in
        let function = b.currentWasmModule.currentWasmFunction

        let assignProb = probability(0.2)

        let outputVar = b.randomVariable()

        // We get a random output variable that we want to reassign to, we can only do this, if that type is a wasm primitive though. We cannot reassign to e.g. WasmGlobals or WasmTables.
        let reassignable = b.type(of: outputVar).Is(.wasmPrimitive)

        function.wasmBuildIfElse(conditionVar) {
            b.buildRecursive(block: 1, of: 2, n: 4)
            if let variable = b.randomVariable(ofType: b.type(of: outputVar)), assignProb, reassignable {
                function.wasmReassign(variable: variable, to: outputVar)
            }
        } elseBody: {
            b.buildRecursive(block: 2, of: 2, n: 4)
            if let variable = b.randomVariable(ofType: b.type(of: outputVar)), assignProb, reassignable {
                function.wasmReassign(variable: variable, to: outputVar)
            }
        }

    }
]
