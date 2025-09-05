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
        b.createWasmGlobal(value: b.randomWasmGlobal(), isMutable: probability(0.5))
    },

    CodeGenerator("WasmMemoryGenerator", inContext: .javascript) { b in
        let minPages = Int.random(in: 0..<10)
        let isShared = probability(0.5)
        var maxPages: Int? = nil
        if isShared || probability(0.5) {
            maxPages = Int.random(in: minPages...WasmConstants.specMaxWasmMem32Pages)
        }
        b.createWasmMemory(minPages: minPages, maxPages: maxPages, isShared: isShared)
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
    },

    RecursiveCodeGenerator("WasmTypeAndModuleGenerator", inContext: .javascript) { b in
        // TODO(cffsmith): We might want to lower this once we can CodeGen into a TypeGroup.
        let numRandomTypes = Int.random(in: 0...5)

        for i in 1..<(numRandomTypes + 1) {
            b.wasmDefineTypeGroup {
                b.buildRecursive(block: i, of: numRandomTypes + 1)
            }
        }

        let m = b.buildWasmModule { m in
            b.buildRecursive(block: numRandomTypes + 1, of: numRandomTypes + 1)
        }

        let exports = m.loadExports()
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
            let functionSignature = b.randomWasmSignature()
            m.addWasmFunction(with: functionSignature) { function, functionLabel, args in
                b.buildPrefix()
                function.wasmBuildLegacyTry(with: [] => [], args: [], body: {label, _ in
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
                return functionSignature.outputTypes.map(function.findOrGenerateWasmVar)
            }
        }
        assert(blockIndex == blockCount + 1)

        let exports = m.loadExports()
    },

    RecursiveCodeGenerator("WasmRecursiveTypeGroupGenerator", inContext: .javascript) { b in
        b.wasmDefineTypeGroup { b.buildRecursive() }
    },

    CodeGenerator("WasmArrayTypeGenerator", inContext: .wasmTypeGroup) { b in
        let mutability = probability(0.75)
        if let elementType = b.randomVariable(ofType: .wasmTypeDef()), probability(0.25) {
            // Excluding non-nullable references from referring to a self-reference ensures we do not end up with cycles of non-nullable references.
            let nullability = b.type(of: elementType).wasmTypeDefinition!.description == .selfReference || probability(0.5)
            b.wasmDefineArrayType(elementType: .wasmRef(.Index(), nullability: nullability), mutability: mutability, indexType: elementType)
        } else {
            b.wasmDefineArrayType(elementType: chooseUniform(from: [.wasmPackedI8, .wasmPackedI16, .wasmi32, .wasmi64, .wasmf32, .wasmf64, .wasmSimd128]), mutability: mutability)
        }
    },

    CodeGenerator("WasmStructTypeGenerator", inContext: .wasmTypeGroup) { b in
        var indexTypes: [Variable] = []
        let fields = (0..<Int.random(in: 0...10)).map { _ in
            var type: ILType
            if let elementType = b.randomVariable(ofType: .wasmTypeDef()), probability(0.25) {
                let nullability = b.type(of: elementType).wasmTypeDefinition!.description == .selfReference || probability(0.5)
                indexTypes.append(elementType)
                type = .wasmRef(.Index(), nullability: nullability)
            } else {
                type = chooseUniform(from: [.wasmPackedI8, .wasmPackedI16, .wasmi32, .wasmi64, .wasmf32, .wasmf64, .wasmSimd128])
            }
            return WasmStructTypeDescription.Field(type: type, mutability: probability(0.75))
        }

        b.wasmDefineStructType(fields: fields, indexTypes: indexTypes)
    },

    CodeGenerator("WasmSelfReferenceGenerator", inContext: .wasmTypeGroup) { b in
        b.wasmDefineForwardOrSelfReference()
    },

    RecursiveCodeGenerator("WasmForwardReferenceGenerator", inContext: .wasmTypeGroup) { b in
        b.wasmDefineAndResolveForwardReference {b.buildRecursive()}
    },

    CodeGenerator("WasmArrayNewGenerator", inContext: .wasmFunction, inputs: .required(.wasmTypeDef())) { b, arrayType in
        if let typeDesc = b.type(of: arrayType).wasmTypeDefinition?.description as? WasmArrayTypeDescription {
            let function = b.currentWasmModule.currentWasmFunction
            let hasElement = b.findVariable{b.type(of: $0).Is(typeDesc.elementType.unpacked())} != nil
            let isDefaultable = typeDesc.elementType.isWasmDefaultable
            if hasElement && (!isDefaultable || probability(0.5))  {
                let elements = (0..<Int.random(in: 0...10)).map {_ in b.findVariable {b.type(of: $0).Is(typeDesc.elementType.unpacked())}!}
                function.wasmArrayNewFixed(arrayType: arrayType, elements: elements)
            } else if isDefaultable {
                function.wasmArrayNewDefault(arrayType: arrayType, size: function.consti32(Int32(b.randomSize(upTo: 0x1000))))
            }
        }
    },

    // We use false nullability so we do not invoke null traps.
    // TODO(manoskouk): Express that only array types are .required (same with all relevant array and struct generators below).
    CodeGenerator("WasmArrayLengthGenerator", inContext: .wasmFunction, inputs: .required(.anyNonNullableIndexRef)) { b, array in
        guard case .Index(let desc) = b.type(of: array).wasmReferenceType!.kind else {
            fatalError("unreachable: array.len input not an Index")
        }
        if !(desc.get() is WasmArrayTypeDescription) { return }
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmArrayLen(array)
    },

    // We use false nullability so we do not invoke null traps.
    CodeGenerator("WasmArrayGetGenerator", inContext: .wasmFunction, inputs: .required(.anyNonNullableIndexRef)) { b, array in
        guard case .Index(let desc) = b.type(of: array).wasmReferenceType!.kind else {
            fatalError("unreachable: array.get input not an Index")
        }
        if !(desc.get() is WasmArrayTypeDescription) { return }
        let function = b.currentWasmModule.currentWasmFunction
        // TODO(mliedtke): Track array length and use other indices as well.
        let index = function.consti32(0)
        function.wasmArrayGet(array: array, index: index, isSigned: Bool.random())
    },

    // We use false nullability so we do not invoke null traps.
    CodeGenerator("WasmArraySetGenerator", inContext: .wasmFunction, inputs: .required(.anyNonNullableIndexRef)) { b, array in
        guard case .Index(let desc) = b.type(of: array).wasmReferenceType!.kind else {
            fatalError("unreachable: array.set input not an Index")
        }
        guard let arrayType = desc.get()! as? WasmArrayTypeDescription else { return }
        guard arrayType.mutability else { return }
        guard let element = b.randomVariable(ofType: arrayType.elementType.unpacked()) else { return }
        let function = b.currentWasmModule.currentWasmFunction
        // TODO(mliedtke): Track array length and use other indices as well.
        let index = function.consti32(0)
        function.wasmArraySet(array: array, index: index, element: element)
    },

    CodeGenerator("WasmStructNewDefaultGenerator", inContext: .wasmFunction, inputs: .required(.wasmTypeDef())) { b, structType in
        guard let typeDesc = b.type(of: structType).wasmTypeDefinition?.description as? WasmStructTypeDescription else { return }
        let function = b.currentWasmModule.currentWasmFunction
        guard (typeDesc.fields.allSatisfy { $0.type.isWasmDefaultable }) else { return }
        function.wasmStructNewDefault(structType: structType)
    },

    CodeGenerator("WasmStructGetGenerator", inContext: .wasmFunction, inputs: .required(.anyNonNullableIndexRef)) { b, theStruct in
        guard case .Index(let desc) = b.type(of: theStruct).wasmReferenceType!.kind else {
            fatalError("unreachable: struct.get input not an Index")
        }
        guard let structType = desc.get()! as? WasmStructTypeDescription else { return }
        guard let fieldIndex = (0..<structType.fields.count).randomElement() else { return }
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmStructGet(theStruct: theStruct, fieldIndex: fieldIndex, isSigned: Bool.random())
    },

    CodeGenerator("WasmStructSetGenerator", inContext: .wasmFunction, inputs: .required(.anyNonNullableIndexRef)) { b, theStruct in
        guard case .Index(let desc) = b.type(of: theStruct).wasmReferenceType!.kind else {
            fatalError("unreachable: struct.set input not an Index")
        }
        guard let structType = desc.get()! as? WasmStructTypeDescription else { return }
        guard let fieldWithIndex = structType.fields.enumerated().filter({ (offset, field) in
            field.mutability
        }).randomElement() else { return }
        guard let newValue = b.randomVariable(ofType: fieldWithIndex.element.type) else { return }
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmStructSet(theStruct: theStruct, fieldIndex: fieldWithIndex.offset, value: newValue)
    },

    CodeGenerator("WasmRefNullGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        if let typeDef = (b.findVariable{b.type(of: $0).Is(.wasmTypeDef())}), probability(0.5) {
            function.wasmRefNull(typeDef: typeDef)
        } else {
            function.wasmRefNull(type: .wasmRef(.Abstract( chooseUniform(from: WasmAbstractHeapType.allCases)), nullability: true))
        }
    },

    CodeGenerator("WasmRefIsNullGenerator", inContext: .wasmFunction, inputs: .required(.wasmGenericRef)) { b, ref in
        b.currentWasmModule.currentWasmFunction.wasmRefIsNull(ref)
    },

    CodeGenerator("WasmRefI31Generator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, value in
        b.currentWasmModule.currentWasmFunction.wasmRefI31(value)
    },

    CodeGenerator("WasmI31GetGenerator", inContext: .wasmFunction, inputs: .required(.wasmI31Ref)) { b, ref in
        b.currentWasmModule.currentWasmFunction.wasmI31Get(ref, isSigned: Bool.random())
    },

    CodeGenerator("WasmAnyConvertExternGenerator", inContext: .wasmFunction, inputs: .required(.wasmExternRef)) { b, ref in
        b.currentWasmModule.currentWasmFunction.wasmAnyConvertExtern(ref)
    },

    CodeGenerator("WasmExternConvertAnyGenerator", inContext: .wasmFunction, inputs: .required(.wasmAnyRef)) { b, ref in
        b.currentWasmModule.currentWasmFunction.wasmExternConvertAny(ref)
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

    CodeGenerator("WasmDefineMemoryGenerator", inContext: .wasm) { b in
        let module = b.currentWasmModule

        let isShared = probability(0.5)
        let isMemory64 = probability(0.5)

        let minPages = Int.random(in: 1..<10)
        let maxPages: Int?
        // Shared memories always need to specify a maximum size.
        if !isShared && probability(0.5) {
            maxPages = nil
        } else {
            maxPages = Int.random(in: minPages...(isMemory64 ? WasmConstants.specMaxWasmMem64Pages
                                                             : WasmConstants.specMaxWasmMem32Pages))
        }
        module.addMemory(minPages: minPages, maxPages: maxPages, isShared: isShared, isMemory64: isMemory64)
    },

    CodeGenerator("WasmDefineDataSegmentGenerator", inContext: .wasm) { b in
        let dataSegment = b.randomBytes()
        b.currentWasmModule.addDataSegment(segment: dataSegment)
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

    CodeGenerator("WasmAtomicLoadGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        let loadType = chooseUniform(from: WasmAtomicLoadType.allCases)
        let alignment = loadType.naturalAlignment()

        let (address, staticOffset) = b.generateAlignedMemoryIndexes(forMemory: memory, alignment: alignment)

        function.wasmAtomicLoad(memory: memory, address: address, loadType: loadType, offset: staticOffset)
    },

    CodeGenerator("WasmAtomicStoreGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        let storeType = chooseUniform(from: WasmAtomicStoreType.allCases)
        let alignment = storeType.naturalAlignment()

        guard let value = b.randomVariable(ofType: storeType.numberType()) else { return }

        let (address, staticOffset) = b.generateAlignedMemoryIndexes(forMemory: memory, alignment: alignment)

        function.wasmAtomicStore(memory: memory, address: address, value: value, storeType: storeType, offset: staticOffset)
    },

    CodeGenerator("WasmAtomicRMWGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        let op = chooseUniform(from: WasmAtomicRMWType.allCases)
        let valueType = op.type()
        let alignment = op.naturalAlignment()

        let rhs = function.findOrGenerateWasmVar(ofType: valueType)

        let (lhs, staticOffset) = b.generateAlignedMemoryIndexes(forMemory: memory, alignment: alignment)

        function.wasmAtomicRMW(memory: memory, lhs: lhs, rhs: rhs, op: op, offset: staticOffset)
    },

    CodeGenerator("WasmAtomicCmpxchgGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        let op = chooseUniform(from: WasmAtomicCmpxchgType.allCases)
        let valueType = op.type()
        let alignment = op.naturalAlignment()

        let expected = function.findOrGenerateWasmVar(ofType: valueType)
        let replacement = function.findOrGenerateWasmVar(ofType: valueType)

        let (address, staticOffset) = b.generateAlignedMemoryIndexes(forMemory: memory, alignment: alignment)

        function.wasmAtomicCmpxchg(memory: memory, address: address, expected: expected, replacement: replacement, op: op, offset: staticOffset)
    },

    CodeGenerator("WasmMemorySizeGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmMemorySize(memory: memory)
    },

    CodeGenerator("WasmMemoryGrowGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        let function = b.currentWasmModule.currentWasmFunction
        let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
        // Note that each wasm page has a size of 64KB. If we end up with a huge number (e.g. due to
        // input mutation), the memory.grow operation fails silently on allocation and returns -1.
        let growBy = function.memoryArgument(Int64.random(in: 0...10), memoryTypeInfo)
        function.wasmMemoryGrow(memory: memory, growByPages: growBy)
    },

    CodeGenerator("WasmMemoryCopyGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, srcMemory in
        let function = b.currentWasmModule.currentWasmFunction
        let srcMemoryTypeInfo = b.type(of: srcMemory).wasmMemoryType!
        let dstMemory = b.findVariable {v in
          let type = b.type(of: v)
          return type.Is(.object(ofGroup: "WasmMemory"))
              && type.wasmMemoryType!.isMemory64 == srcMemoryTypeInfo.isMemory64
        }!
        let dstMemoryTypeInfo = b.type(of: srcMemory).wasmMemoryType!
        let memArg = {v in function.memoryArgument(v, dstMemoryTypeInfo)}

        let srcMemSize = srcMemoryTypeInfo.limits.min * WasmConstants.specWasmMemPageSize
        let dstMemSize = dstMemoryTypeInfo.limits.min * WasmConstants.specWasmMemPageSize
        let srcOffsetValue = b.randomNonNegativeIndex(upTo: Int64(srcMemSize))
        let srcOffset = memArg(srcOffsetValue)
        let dstOffsetValue = b.randomNonNegativeIndex(upTo: Int64(dstMemSize))
        let dstOffset = memArg(dstOffsetValue)

        let maxCopySize = min(Int64(srcMemSize) - srcOffsetValue, Int64(dstMemSize) - dstOffsetValue)
        let copySizeValue = b.randomSize(upTo:maxCopySize)
        let copySize = memArg(copySizeValue)

        function.wasmMemoryCopy(dstMemory: dstMemory, srcMemory: srcMemory, dstOffset: dstOffset, srcOffset: srcOffset, size: copySize)
    },

    CodeGenerator("WasmMemoryFillGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"))) { b, memory in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
        let memSize = Int64(memoryTypeInfo.limits.min * WasmConstants.specWasmMemPageSize)

        let offsetValue = b.randomNonNegativeIndex(upTo: memSize)
        let offset = function.memoryArgument(offsetValue, memoryTypeInfo)
        let byteToSet = function.consti32(Int32.random(in: 0...255))
        let nrOfBytesToUpdate = function.memoryArgument(Int64.random(in: 0...(memSize - offsetValue)) + 1, memoryTypeInfo)

        function.wasmMemoryFill(memory: memory, offset: offset, byteToSet: byteToSet, nrOfBytesToUpdate: nrOfBytesToUpdate)
    },

    CodeGenerator("WasmMemoryInitGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"), .wasmDataSegment())) { b, memory, dataSegment in
        if (b.hasZeroPages(memory: memory) || b.type(of: dataSegment).wasmDataSegmentType!.isDropped) { return }

        let function = b.currentWasmModule.currentWasmFunction

        let memoryTypeInfo = b.type(of: memory).wasmMemoryType!
        let memSize = Int64(memoryTypeInfo.limits.min * WasmConstants.specWasmMemPageSize)
        let memoryOffsetValue = b.randomNonNegativeIndex(upTo: memSize)
        let memoryOffset = function.memoryArgument(memoryOffsetValue, memoryTypeInfo)

        let dataSegmentTypeInfo = b.type(of: dataSegment).wasmDataSegmentType!
        let dataSegmentOffsetValue = b.randomNonNegativeIndex(upTo: Int64(dataSegmentTypeInfo.segmentLength))
        let dataSegmentOffset = function.consti32(Int32(dataSegmentOffsetValue))

        let maxNrOfBytesToUpdate = min(memSize - memoryOffsetValue, Int64(dataSegmentTypeInfo.segmentLength) - dataSegmentOffsetValue)
        let nrOfBytesToUpdate = function.consti32(Int32(b.randomSize(upTo: maxNrOfBytesToUpdate)))

        function.wasmMemoryInit(dataSegment: dataSegment, memory: memory, memoryOffset: memoryOffset, dataSegmentOffset: dataSegmentOffset, nrOfBytesToUpdate: nrOfBytesToUpdate)
    },

    CodeGenerator("WasmDropDataSegmentGenerator", inContext: .wasmFunction, inputs: .required(.wasmDataSegment())) { b, dataSegment in
        b.currentWasmFunction.wasmDropDataSegment(dataSegment: dataSegment)
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

        let definedEntryIndices: [Int]
        var definedEntries: [WasmTableType.IndexInTableAndWasmSignature] = []
        var definedEntryValues: [Variable] = []

        // For funcref tables, we need to look for functions to populate the entries.
        // These are going to be either wasm function definitions (.wasmFunctionDef()) or JS functions (.function()).
        // TODO(manoskouk): When we have support for constant expressions, consider looking for .wasmFuncRef instead.
        let expectedEntryType = elementType == .wasmFuncRef ? .wasmFunctionDef() | .function() : .object()

        // Currently, only generate entries for funcref tables.
        // TODO(manoskouk): Generalize this.
        if (elementType == .wasmFuncRef) {
            if b.randomVariable(ofType: expectedEntryType) != nil {
                // There is at least one function in scope. Add some initial entries to the table.
                // TODO(manoskouk): Generalize this.
                definedEntryIndices = [0, 1, 2, 3, 4]
                for index in definedEntryIndices {
                    let value = b.randomVariable(ofType: expectedEntryType)!
                    let actualEntryType = b.type(of: value)
                    definedEntries.append(.init(indexInTable: index, signature: actualEntryType == .wasmFunctionDef() ? actualEntryType.wasmFunctionDefSignature! : ProgramBuilder.convertJsSignatureToWasmSignatureDeterministic(actualEntryType.signature ?? Signature.forUnknownFunction)))
                    definedEntryValues.append(value)
                }
            }
        }

        module.addTable(elementType: elementType, minSize: minSize, maxSize: maxSize, definedEntries: definedEntries, definedEntryValues: definedEntryValues, isTable64: probability(0.5))
    },

    CodeGenerator("WasmTableSizeGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTable"))) { b, table in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmTableSize(table: table)
    },

    CodeGenerator("WasmTableGrowGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTable"))) { b, table in
        let function = b.currentWasmModule.currentWasmFunction
        let tableType = b.type(of: table).wasmTableType!
        let delta = tableType.isTable64 ? function.consti64(Int64.random(in: 0...10)) : function.consti32(Int32.random(in: 0...10))
        let initialValue = function.findOrGenerateWasmVar(ofType: tableType.elementType)
        function.wasmTableGrow(table: table, with: initialValue, by: delta)
    },

    CodeGenerator("WasmCallIndirectGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTable"))) { b, table in
        let tableType = b.type(of: table).wasmTableType!
        if !tableType.elementType.Is(.wasmFuncRef) { return }
        guard let indexedSignature = tableType.knownEntries.randomElement() else { return }

        let function = b.currentWasmModule.currentWasmFunction
        let indexVar = tableType.isTable64
            ? function.consti64(Int64(indexedSignature.indexInTable))
            : function.consti32(Int32(indexedSignature.indexInTable))

        guard let functionArgs = b.randomWasmArguments(forWasmSignature: indexedSignature.signature) else { return }

        function.wasmCallIndirect(signature: indexedSignature.signature, table: table, functionArgs: functionArgs, tableIndex: indexVar)
    },

    // TODO(manoskouk): Find a way to generate recursive calls.
    CodeGenerator("WasmCallDirectGenerator", inContext: .wasmFunction, inputs: .required(.wasmFunctionDef())) { b, functionVar in
        let signature = b.type(of: functionVar).wasmFunctionDefSignature!
        let functionArgs = b.randomWasmArguments(forWasmSignature: signature)
        guard let functionArgs else { return }
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmCallDirect(signature: signature, function: functionVar, functionArgs: functionArgs)
    },

    CodeGenerator("WasmReturnCallDirectGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        guard let functionVar = (b.findVariable { v in
            let type = b.type(of: v)
            return type.Is(.wasmFunctionDef()) && type.wasmFunctionDefSignature!.outputTypes == function.signature.outputTypes
        }) else { return }
        let signature = b.type(of: functionVar).wasmFunctionDefSignature!
        let functionArgs = b.randomWasmArguments(forWasmSignature: signature)
        guard let functionArgs else { return }
        function.wasmReturnCallDirect(signature: signature, function: functionVar, functionArgs: functionArgs)
    },

    CodeGenerator("WasmReturnCallIndirectGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTable"))) { b, table in
        let function = b.currentWasmModule.currentWasmFunction
        let tableType = b.type(of: table).wasmTableType!
        if !tableType.elementType.Is(.wasmFuncRef) { return }
        guard let indexedSignature = (tableType.knownEntries.filter { $0.signature.outputTypes == function.signature.outputTypes }.randomElement()) else { return }
        let indexVar = tableType.isTable64
            ? function.consti64(Int64(indexedSignature.indexInTable))
            : function.consti32(Int32(indexedSignature.indexInTable))
        guard let functionArgs = b.randomWasmArguments(forWasmSignature: indexedSignature.signature) else { return }
        function.wasmReturnCallIndirect(signature: indexedSignature.signature, table: table, functionArgs: functionArgs, tableIndex: indexVar)
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
        let functionSignature = b.randomWasmSignature()
        module.addWasmFunction(with: functionSignature) { function, label, args in
            b.buildPrefix()
            b.buildRecursive()
            return functionSignature.outputTypes.map(function.findOrGenerateWasmVar)
        }
    },

    CodeGenerator("WasmReturnGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmReturn(function.signature.outputTypes.map(function.findOrGenerateWasmVar))
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

        let reassignmentVariable = function.findOrGenerateWasmVar(ofType: b.type(of: v))

        assert(b.type(of: reassignmentVariable).Is(.wasmPrimitive))

        function.wasmReassign(variable: v, to: reassignmentVariable)
    },

    RecursiveCodeGenerator("WasmBlockGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildBlock(with: [] => [], args: []) { label, args in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("WasmBlockWithSignatureGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = b.randomWasmBlockArguments(upTo: 5)
        let parameters = args.map {b.type(of: $0)}
        let outputTypes = b.randomWasmBlockOutputTypes(upTo: 5)
        function.wasmBuildBlockWithResults(with: parameters => outputTypes, args: args) { label, args in
            b.buildRecursive()
            return outputTypes.map(function.findOrGenerateWasmVar)
        }
    },

    RecursiveCodeGenerator("WasmLoopGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        let loopCtr = function.consti32(10)

        function.wasmBuildLoop(with: [] => []) { label, args in
            let result = function.wasmi32BinOp(loopCtr, function.consti32(1), binOpKind: .Sub)
            function.wasmReassign(variable: loopCtr, to: result)

            b.buildRecursive()

            // Backedge of loop, we continue if it is not equal to zero.
            let isNotZero = function.wasmi32CompareOp(loopCtr, function.consti32(0), using: .Ne)
            function.wasmBranchIf(isNotZero, to: label, hint: b.randomWasmBranchHint())
        }
    },

    RecursiveCodeGenerator("WasmLoopWithSignatureGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Count upwards here to make it slightly more different from the other loop generator.
        // Also, instead of using reassign, this generator uses the signature to pass and update the loop counter.
        let randomArgs = b.randomWasmBlockArguments(upTo: 5)
        let randomArgTypes = randomArgs.map{b.type(of: $0)}
        let args = [function.consti32(0)] + randomArgs
        let parameters = args.map(b.type)
        let outputTypes = b.randomWasmBlockOutputTypes(upTo: 5)
        // Note that due to the do-while style implementation, the actual iteration count is at least 1.
        let iterationCount = Int32.random(in: 0...16)

        function.wasmBuildLoop(with: parameters => outputTypes, args: args) { label, loopArgs in
            b.buildRecursive()
            let loopCtr = function.wasmi32BinOp(args[0], function.consti32(1), binOpKind: .Add)
            let condition = function.wasmi32CompareOp(loopCtr, function.consti32(iterationCount), using: .Lt_s)
            let backedgeArgs = [loopCtr] + randomArgTypes.map{b.randomVariable(ofType: $0)!}
            function.wasmBranchIf(condition, to: label, args: backedgeArgs, hint: b.randomWasmBranchHint())
            return outputTypes.map(function.findOrGenerateWasmVar)
        }
    },

    RecursiveCodeGenerator("WasmLegacyTryCatchGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = b.randomWasmBlockArguments(upTo: 5)
        let parameters = args.map(b.type)
        let tags = (0..<Int.random(in: 0...5)).map {_ in b.findVariable { b.type(of: $0).isWasmTagType }}.filter {$0 != nil}.map {$0!}
        let recursiveCallCount = 2 + tags.count
        function.wasmBuildLegacyTry(with: parameters => [], args: args) { label, args in
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
        let args = b.randomWasmBlockArguments(upTo: 5)
        let parameters = args.map(b.type)
        let tags = (0..<Int.random(in: 0...5)).map {_ in b.findVariable { b.type(of: $0).isWasmTagType }}.filter {$0 != nil}.map {$0!}
        let outputTypes = b.randomWasmBlockOutputTypes(upTo: 3)
        let signature = parameters => outputTypes
        let recursiveCallCount = 2 + tags.count
        function.wasmBuildLegacyTryWithResult(with: signature, args: args, body: { label, args in
            b.buildRecursive(block: 1, of: recursiveCallCount, n: 4)
            return outputTypes.map(function.findOrGenerateWasmVar)
        }, catchClauses: tags.enumerated().map {i, tag in (tag, {_, _, _ in
            b.buildRecursive(block: 2 + i, of: recursiveCallCount, n: 4)
            return outputTypes.map(function.findOrGenerateWasmVar)
        })}, catchAllBody: { label in
            b.buildRecursive(block: 2 + tags.count, of: recursiveCallCount, n: 4)
            return outputTypes.map(function.findOrGenerateWasmVar)
        })
    },

    RecursiveCodeGenerator("WasmLegacyTryDelegateGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose a few random wasm values as arguments if available.
        let args = b.randomWasmBlockArguments(upTo: 5)
        let outputTypes = b.randomWasmBlockOutputTypes(upTo: 3)
        let parameters = args.map(b.type)
        function.wasmBuildLegacyTryDelegateWithResult(with: parameters => outputTypes, args: args, body: { _, _ in
            b.buildRecursive()
            return outputTypes.map(function.findOrGenerateWasmVar)
        }, delegate: label)
    },

    // The variable we reassign to has to be a numerical primitive, e.g. something that looks like a number (can be a global)
    // We cannot reassign to a .wasmFuncRef or .wasmExternRef though, as they need to be in a local slot.
    RecursiveCodeGenerator("WasmIfElseGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32, .wasmNumericalPrimitive)) { b, conditionVar, outputVar in
        let function = b.currentWasmModule.currentWasmFunction

        let assignProb = probability(0.2)

        function.wasmBuildIfElse(conditionVar, hint: b.randomWasmBranchHint()) {
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
        let args = b.randomWasmBlockArguments(upTo: 5)
        let parameters = args.map(b.type)
        let outputTypes = b.randomWasmBlockOutputTypes(upTo: 5)
        function.wasmBuildIfElseWithResult(conditionVar, hint: b.randomWasmBranchHint(), signature: parameters => outputTypes, args: args) { label, args in
            b.buildRecursive(block: 1, of: 2, n: 4)
            return outputTypes.map(function.findOrGenerateWasmVar)
        } elseBody: { label, args in
            b.buildRecursive(block: 2, of: 2, n: 4)
            return outputTypes.map(function.findOrGenerateWasmVar)
        }
    },

    CodeGenerator("WasmSelectGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, condition in
        let function = b.currentWasmModule.currentWasmFunction
        // The condition is an i32, so we should always find at least that one as a possible input.
        let trueValue = b.randomVariable(ofType: .wasmPrimitive)!
        let falseValue = b.randomVariable(ofType: b.type(of: trueValue))!
        function.wasmSelect(on: condition, trueValue: trueValue, falseValue: falseValue)
    },

    CodeGenerator("WasmThrowGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmTag"))) { b, tag in
        let function = b.currentWasmModule.currentWasmFunction
        let wasmTagType = b.type(of: tag).wasmTagType!
        if wasmTagType.isJSTag {
            // A JSTag cannot be thrown from Wasm.
            return
        }
        var args = wasmTagType.parameters.map(function.findOrGenerateWasmVar)
        function.WasmBuildThrow(tag: tag, inputs: args)
    },

    CodeGenerator("WasmLegacyRethrowGenerator", inContext: .wasmFunction, inputs: .required(.exceptionLabel)) { b, exception in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildLegacyRethrow(exception)
    },

    CodeGenerator("WasmThrowRefGenerator", inContext: .wasmFunction, inputs: .required(.wasmExnRef)) { b, exception in
        let function = b.currentWasmModule.currentWasmFunction
        function.wasmBuildThrowRef(exception: exception)
    },

    CodeGenerator("WasmDefineTagGenerator", inContext: .wasm) {b in
        b.currentWasmModule.addTag(parameterTypes: b.randomTagParameters())
    },

    CodeGenerator("WasmBranchGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel)) { b, label in
        let function = b.currentWasmModule.currentWasmFunction
        let args = b.type(of: label).wasmLabelType!.parameters.map(function.findOrGenerateWasmVar)
        function.wasmBranch(to: label, args: args)
    },

    CodeGenerator("WasmBranchIfGenerator", inContext: .wasmFunction, inputs: .required(.anyLabel, .wasmi32)) { b, label, conditionVar in
        let function = b.currentWasmModule.currentWasmFunction
        let args = b.type(of: label).wasmLabelType!.parameters.map(function.findOrGenerateWasmVar)
        function.wasmBranchIf(conditionVar, to: label, args: args, hint: b.randomWasmBranchHint())
    },

    RecursiveCodeGenerator("WasmBranchTableGenerator", inContext: .wasmFunction, inputs: .required(.wasmi32)) { b, value in
        let function = b.currentWasmModule.currentWasmFunction
        // Choose parameter types for the br_table. If we can find an existing label, just use that
        // label types as it allows use to reuse existing (and therefore more interesting) blocks.
        let parameterTypes = if let label = b.randomVariable(ofType: .anyLabel) {
            b.type(of: label).wasmLabelType!.parameters
        } else {
            b.randomWasmBlockOutputTypes(upTo: 3)
        }
        let extraBlockCount = Int.random(in: 1...5)
        let valueCount = Int.random(in: 0...20)
        let signature = [] => parameterTypes
        (0..<extraBlockCount).forEach { _ in
            function.wasmBeginBlock(with: signature, args: [])
        }
        let labels = (0...valueCount).map {_ in b.randomVariable(ofType: .label(parameterTypes))!}
        let args = parameterTypes.map(function.findOrGenerateWasmVar)
        function.wasmBranchTable(on: value, labels: labels, args: args)
        (0..<extraBlockCount).forEach { n in
            let results = parameterTypes.map(function.findOrGenerateWasmVar)
            function.wasmEndBlock(outputTypes: signature.outputTypes, args: results)
            b.buildRecursive(block: n + 1, of: extraBlockCount, n: 4)
        }
    },

    RecursiveCodeGenerator("WasmTryTableGenerator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        let tags = (0..<Int.random(in: 0...3)).map {_ in
            let tag = b.randomVariable(ofType: .object(ofGroup: "WasmTag"))
            // nil will map to a catch all. Note that this means that we can generate multiple
            // catch all targets.
            b.reportErrorIf(tag != nil && !b.type(of: tag!).isWasmTagType,
                    "Expected tag misses the WasmTagType extension for variable \(String(describing: tag)).")
            return tag == nil || b.type(of: tag!).wasmTagType!.isJSTag || probability(0.1) ? nil : tag
        }
        let withExnRef = tags.map {_ in Bool.random()}

        let outputTypesList = zip(tags, withExnRef).map { tag, withExnRef in
            var outputTypes: [ILType] = if let tag = tag {
                b.type(of: tag).wasmTagType!.parameters
            } else {
                []
            }
            if withExnRef {
                outputTypes.append(.wasmExnRef)
            }
            function.wasmBeginBlock(with: [] => outputTypes, args: [])
            return outputTypes
        }
        // Look up the labels. In most cases these will be exactly the ones produced by the blocks
        // above but also any other matching existing block could be used. (Similar, tags with the
        // same parameter types could also be mapped to the same block.)
        let labels = outputTypesList.map {outputTypes in b.randomVariable(ofType: .label(outputTypes))!}
        let catches = zip(tags, withExnRef).map { tag, withExnRef -> WasmBeginTryTable.CatchKind in
            tag == nil ? (withExnRef ? .AllRef : .AllNoRef) : (withExnRef ? .Ref : .NoRef)
        }

        var tryArgs = b.randomWasmBlockArguments(upTo: 5)
        let tryParameters = tryArgs.map {b.type(of: $0)}
        let tryOutputTypes = b.randomWasmBlockOutputTypes(upTo: 5)
        tryArgs += zip(tags, labels).map {tag, label in tag == nil ? [label] : [tag!, label]}.joined()
        function.wasmBuildTryTable(with: tryParameters => tryOutputTypes, args: tryArgs, catches: catches) { _, _ in
            b.buildRecursive(block: 1, of: tags.count + 1, n: 4)
            return tryOutputTypes.map(function.findOrGenerateWasmVar)
        }
        outputTypesList.reversed().enumerated().forEach { n, outputTypes in
            let results = outputTypes.map(function.findOrGenerateWasmVar)
            function.wasmEndBlock(outputTypes: outputTypes, args: results)
            b.buildRecursive(block: n + 2, of: tags.count + 1, n: 4)
        }
    },

    CodeGenerator("ConstSimd128Generator", inContext: .wasmFunction) { b in
        let function = b.currentWasmModule.currentWasmFunction
        function.constSimd128(value: (0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
    },

    CodeGenerator("WasmSimd128IntegerUnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ !$0.isFloat() })
        let unOpKind = chooseUniform(from: WasmSimd128IntegerUnOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128IntegerUnOp(input, shape, unOpKind)
    },

    CodeGenerator("WasmSimd128IntegerBinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, lhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ !$0.isFloat() })
        let binOpKind = chooseUniform(from: WasmSimd128IntegerBinOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })
        let function = b.currentWasmModule.currentWasmFunction;

        // Shifts take an i32 as an rhs input, the others take a regular .wasmSimd128 input.
        let rhsType = binOpKind.isShift() ? ILType.wasmi32 : .wasmSimd128
        var rhs = function.findOrGenerateWasmVar(ofType: rhsType)
        function.wasmSimd128IntegerBinOp(lhs, rhs, shape, binOpKind)
    },

    CodeGenerator("WasmSimd128IntegerTernaryOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128, .wasmSimd128)) { b, left, mid, right in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ !$0.isFloat() } )
        let ternaryOpKind = chooseUniform(from: WasmSimd128IntegerTernaryOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128IntegerTernaryOp(left, mid, right, shape, ternaryOpKind)
    },

    CodeGenerator("WasmSimd128FloatUnOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ $0.isFloat() })
        let unOpKind = chooseUniform(from: WasmSimd128FloatUnOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128FloatUnOp(input, shape, unOpKind)
    },

    CodeGenerator("WasmSimd128FloatBinOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128)) { b, lhs, rhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ $0.isFloat() })
        let binOpKind = chooseUniform(from: WasmSimd128FloatBinOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128FloatBinOp(lhs, rhs, shape, binOpKind)
    },

    CodeGenerator("WasmSimd128FloatTernaryOpGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128, .wasmSimd128)) { b, left, mid, right in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter{ $0.isFloat() } )
        let ternaryOpKind = chooseUniform(from: WasmSimd128FloatTernaryOpKind.allCases.filter{
            $0.isValidForShape(shape: shape)
        })

        let function = b.currentWasmModule.currentWasmFunction;
        function.wasmSimd128FloatTernaryOp(left, mid, right, shape, ternaryOpKind)
    },

    CodeGenerator("WasmSimd128CompareGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128, .wasmSimd128)) { b, lhs, rhs in
        let shape = chooseUniform(from: WasmSimd128Shape.allCases)
        let compareOpKind = b.randomSimd128CompareOpKind(shape)

        let function = b.currentWasmModule.currentWasmFunction
        function.wasmSimd128Compare(lhs, rhs, shape, compareOpKind)
    },

    CodeGenerator("WasmSimdSplatGenerator", inContext: .wasmFunction) {b in
        let function = b.currentWasmModule.currentWasmFunction;
        let kind = chooseUniform(from: WasmSimdSplat.Kind.allCases)
        function.wasmSimdSplat(kind: kind, function.findOrGenerateWasmVar(ofType: kind.laneType()))
    },

    CodeGenerator("WasmSimdExtractLaneGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        let kind = chooseUniform(from: WasmSimdExtractLane.Kind.allCases)
        function.wasmSimdExtractLane(kind: kind, input, Int.random(in: 0..<kind.laneCount()))
    },

    CodeGenerator("WasmSimdReplaceLaneGenerator", inContext: .wasmFunction, inputs: .required(.wasmSimd128)) { b, input in
        let function = b.currentWasmModule.currentWasmFunction
        let kind = chooseUniform(from: WasmSimdReplaceLane.Kind.allCases)
        let replacement = function.findOrGenerateWasmVar(ofType: kind.laneType())
        function.wasmSimdReplaceLane(kind: kind, input, replacement, Int.random(in: 0..<kind.laneCount()))
    },

    CodeGenerator("WasmSimdStoreLaneGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"), .wasmSimd128)) { b, memory, simdValue in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let (dynamicOffset, staticOffset) = b.generateMemoryIndexes(forMemory: memory)
        let kind = chooseUniform(from: WasmSimdStoreLane.Kind.allCases)
        function.wasmSimdStoreLane(kind: kind, memory: memory, dynamicOffset: dynamicOffset,
            staticOffset: staticOffset, from: simdValue, lane: Int.random(in: 0..<kind.laneCount()))
    },

    CodeGenerator("WasmSimdLoadLaneGenerator", inContext: .wasmFunction, inputs: .required(.object(ofGroup: "WasmMemory"), .wasmSimd128)) { b, memory, simdValue in
        if (b.hasZeroPages(memory: memory)) { return }

        let function = b.currentWasmModule.currentWasmFunction
        let (dynamicOffset, staticOffset) = b.generateMemoryIndexes(forMemory: memory)
        let kind = chooseUniform(from: WasmSimdLoadLane.Kind.allCases)
        function.wasmSimdLoadLane(kind: kind, memory: memory, dynamicOffset: dynamicOffset,
            staticOffset: staticOffset, into: simdValue, lane: Int.random(in: 0..<kind.laneCount()))
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
