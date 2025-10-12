// Copyright 2019 Google LLC
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

/// A mutator that mutates the Operations in the given program.
public class OperationMutator: BaseInstructionMutator {
    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousMutations)
    }

    public override func canMutate(_ instr: Instruction) -> Bool {
        // The OperationMutator handles both mutable and variadic operations since both require
        // modifying the operation and both types of mutations are approximately equally "useful",
        // so there's no need for a dedicated "VariadicOperationMutator".
        return instr.isOperationMutable || instr.isVariadic
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        b.trace("Mutating next operation")

        let newInstr: Instruction
        if instr.isOperationMutable && instr.isVariadic {
            newInstr = probability(0.5) ? mutateOperation(instr, b) : extendVariadicOperation(instr, b)
        } else if instr.isOperationMutable {
            newInstr = mutateOperation(instr, b)
        } else {
            assert(instr.isVariadic)
            newInstr = extendVariadicOperation(instr, b)
        }

        b.adopt(newInstr)
    }

    private func mutateOperation(_ instr: Instruction, _ b: ProgramBuilder) -> Instruction {
        let newOp: Operation
        switch instr.op.opcode {
        case .loadInteger(_):
            newOp = LoadInteger(value: b.randomInt())
        case .loadBigInt(_):
            newOp = LoadBigInt(value: b.randomInt())
        case .loadFloat(_):
            newOp = LoadFloat(value: b.randomFloat())
        case .loadString(let op):
            if let customName = op.customName {
                // Half the time we want to just hit the regular path
                if Bool.random() {
                    if let type = b.fuzzer.environment.getEnum(ofName: customName) {
                        newOp = LoadString(value: chooseUniform(from: type.enumValues), customName: customName)
                        break
                    } else if let gen = b.fuzzer.environment.getNamedStringGenerator(ofName: customName) {
                        newOp = LoadString(value: gen(), customName: customName)
                        break
                    }
                }
            }
            let charSetAlNum = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            // TODO(mliedtke): Should we also use some more esoteric characters in initial string
            // creation, e.g. ProgramBuilder.randomString?
            let charSetExtended = charSetAlNum + Array("-_.,!?<>()[]{}`´^\\/|+#*=;:'~^²\t°ß¿ 🤯🙌🏿\u{202D}")
            let randomIndex = {(s: String) in
                s.index(s.startIndex, offsetBy: Int.random(in: 0..<s.count))
            }
            let randomCharacter = {
                // Add an overweight to the alpha-numeric characters.
                (Bool.random() ? charSetAlNum : charSetExtended).randomElement()!
            }
            // With a 50% chance create a new string, otherwise perform a modification on the
            // existing string. Modifying the string can be especially interesting for
            // decoders for RegEx, base64, hex, ...
            let newString = op.value.isEmpty || Bool.random() ? b.randomString() : withEqualProbability(
                {
                    // Replace a single character.
                    var result = op.value
                    let index = randomIndex(result)
                    result.replaceSubrange(index..<result.index(index, offsetBy: 1), with: String(randomCharacter()))
                    return result
                }, {
                    // Insert a single character.
                    var result = op.value
                    result.insert(randomCharacter(), at: randomIndex(result))
                    return result
                }, {
                    // Remove a single character.
                    var result = op.value
                    result.remove(at: randomIndex(result))
                    return result
                }
            )
            // Note: This explicitly discards customName since we may have created a string that no longer
            // matches the original schema.
            newOp = LoadString(value: newString)
        case .loadRegExp(let op):
            newOp = withEqualProbability({
                let (pattern, flags) = b.randomRegExpPatternAndFlags()
                return LoadRegExp(pattern: pattern, flags: flags)
            }, {
                return LoadRegExp(pattern: b.randomRegExpPattern(compatibleWithFlags: op.flags), flags: op.flags)
            }, {
                return LoadRegExp(pattern: op.pattern, flags: RegExpFlags.random())
            })
        case .loadBoolean(let op):
            newOp = LoadBoolean(value: !op.value)
        case .createTemplateString(let op):
            var newParts = op.parts
            replaceRandomElement(in: &newParts, generatingRandomValuesWith: { return b.randomString() })
            newOp = CreateTemplateString(parts: newParts)
        case .objectLiteralAddProperty:
            newOp = ObjectLiteralAddProperty(propertyName: b.randomPropertyName())
        case .objectLiteralAddElement:
            newOp = ObjectLiteralAddElement(index: b.randomIndex())
        case .beginObjectLiteralMethod(let op):
            newOp = BeginObjectLiteralMethod(methodName: b.randomMethodName(), parameters: op.parameters)
        case .beginObjectLiteralGetter:
            newOp = BeginObjectLiteralGetter(propertyName: b.randomPropertyName())
        case .beginObjectLiteralSetter:
            newOp = BeginObjectLiteralSetter(propertyName: b.randomPropertyName())
        case .classAddInstanceProperty(let op):
            newOp = ClassAddInstanceProperty(propertyName: b.randomPropertyName(), hasValue: op.hasValue)
        case .classAddInstanceElement(let op):
            newOp = ClassAddInstanceElement(index: b.randomIndex(), hasValue: op.hasValue)
        case .beginClassInstanceMethod(let op):
            newOp = BeginClassInstanceMethod(methodName: b.randomMethodName(), parameters: op.parameters)
        case .beginClassInstanceGetter:
            newOp = BeginClassInstanceGetter(propertyName: b.randomPropertyName())
        case .beginClassInstanceSetter:
            newOp = BeginClassInstanceSetter(propertyName: b.randomPropertyName())
        case .classAddStaticProperty(let op):
            newOp = ClassAddStaticProperty(propertyName: b.randomPropertyName(), hasValue: op.hasValue)
        case .classAddStaticElement(let op):
            newOp = ClassAddStaticElement(index: b.randomIndex(), hasValue: op.hasValue)
        case .beginClassStaticMethod(let op):
            newOp = BeginClassStaticMethod(methodName: b.randomMethodName(), parameters: op.parameters)
        case .beginClassStaticGetter:
            newOp = BeginClassStaticGetter(propertyName: b.randomPropertyName())
        case .beginClassStaticSetter:
            newOp = BeginClassStaticSetter(propertyName: b.randomPropertyName())
        case .createIntArray:
            var values = [Int64]()
            for _ in 0..<Int.random(in: 1...10) {
                values.append(b.randomInt())
            }
            newOp = CreateIntArray(values: values)
        case .createFloatArray:
            var values = [Double]()
            for _ in 0..<Int.random(in: 1...10) {
                values.append(b.randomFloat())
            }
            newOp = CreateFloatArray(values: values)
        case .createArrayWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CreateArrayWithSpread(spreads: spreads)
        case .getProperty(let op):
            newOp = GetProperty(propertyName: b.randomPropertyName(), isGuarded: op.isGuarded)
        case .setProperty(let op):
            newOp = SetProperty(propertyName: b.randomPropertyName(), isGuarded: op.isGuarded)
        case .updateProperty(_):
            newOp = UpdateProperty(propertyName: b.randomPropertyName(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .deleteProperty(let op):
            newOp = DeleteProperty(propertyName: b.randomPropertyName(), isGuarded: op.isGuarded)
        case .configureProperty(let op):
            // Change the flags or the property name, but don't change the type as that would require changing the inputs as well.
            if probability(0.5) {
                newOp = ConfigureProperty(propertyName: b.randomPropertyName(), flags: op.flags, type: op.type)
            } else {
                newOp = ConfigureProperty(propertyName: op.propertyName, flags: PropertyFlags.random(), type: op.type)
            }
        case .getElement(let op):
            newOp = GetElement(index: b.randomIndex(), isGuarded: op.isGuarded)
        case .setElement(_):
            newOp = SetElement(index: b.randomIndex())
        case .updateElement(_):
            newOp = UpdateElement(index: b.randomIndex(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .updateComputedProperty(_):
            newOp = UpdateComputedProperty(operator: chooseUniform(from: BinaryOperator.allCases))
        case .deleteElement(let op):
            newOp = DeleteElement(index: b.randomIndex(), isGuarded: op.isGuarded)
        case .configureElement(let op):
            // Change the flags or the element index, but don't change the type as that would require changing the inputs as well.
            if probability(0.5) {
                newOp = ConfigureElement(index: b.randomIndex(), flags: op.flags, type: op.type)
            } else {
                newOp = ConfigureElement(index: op.index, flags: PropertyFlags.random(), type: op.type)
            }
        case .configureComputedProperty(let op):
            newOp = ConfigureComputedProperty(flags: PropertyFlags.random(), type: op.type)
        case .callFunctionWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CallFunctionWithSpread(numArguments: op.numArguments, spreads: spreads, isGuarded: op.isGuarded)
        case .constructWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = ConstructWithSpread(numArguments: op.numArguments, spreads: spreads, isGuarded: op.isGuarded)
        case .callMethod(let op):
            // Selecting a random method has a high chance of causing a runtime exception, so try to select an existing one.
            let methodName = b.type(of: instr.input(0)).randomMethod() ?? b.randomMethodName()
            newOp = CallMethod(methodName: methodName, numArguments: op.numArguments, isGuarded: op.isGuarded)
        case .callMethodWithSpread(let op):
            // Selecting a random method has a high chance of causing a runtime exception, so try to select an existing one.
            let methodName = b.type(of: instr.input(0)).randomMethod() ?? b.randomMethodName()
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CallMethodWithSpread(methodName: methodName, numArguments: op.numArguments, spreads: spreads, isGuarded: op.isGuarded)
        case .callComputedMethodWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CallComputedMethodWithSpread(numArguments: op.numArguments, spreads: spreads, isGuarded: op.isGuarded)
        case .unaryOperation(_):
            newOp = UnaryOperation(chooseUniform(from: UnaryOperator.allCases))
        case .binaryOperation(_):
            newOp = BinaryOperation(chooseUniform(from: BinaryOperator.allCases))
        case .update(_):
            newOp = Update(chooseUniform(from: BinaryOperator.allCases))
        case .destructArray(let op):
            var newIndices = op.indices
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int64.random(in: 0..<10) })
            assert(newIndices.count == Set(newIndices).count)
            newOp = DestructArray(indices: newIndices.sorted(), lastIsRest: !op.lastIsRest)
        case .destructArrayAndReassign(let op):
            var newIndices = op.indices
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int64.random(in: 0..<10) })
            assert(newIndices.count == Set(newIndices).count)
            newOp = DestructArrayAndReassign(indices: newIndices.sorted(), lastIsRest: !op.lastIsRest)
        case .destructObject(let op):
            var newProperties = op.properties
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.randomPropertyName() })
            assert(newProperties.count == Set(newProperties).count)
            newOp = DestructObject(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case .destructObjectAndReassign(let op):
            var newProperties = op.properties
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.randomPropertyName() })
            assert(newProperties.count == Set(newProperties).count)
            newOp = DestructObjectAndReassign(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case .compare(_):
            newOp = Compare(chooseUniform(from: Comparator.allCases))
        case .createNamedVariable(let op):
            // We just use property names as variable names here. It's not clear if there's a better alternative and this also works well with `with` statements.
            newOp = CreateNamedVariable(b.randomPropertyName(), declarationMode: op.declarationMode)
        case .callSuperMethod(let op):
            let methodName = b.currentSuperType().randomMethod() ?? b.randomMethodName()
            newOp = CallSuperMethod(methodName: methodName, numArguments: op.numArguments)
        case .getSuperProperty(_):
            newOp = GetSuperProperty(propertyName: b.randomPropertyName())
        case .setSuperProperty(_):
            newOp = SetSuperProperty(propertyName: b.randomPropertyName())
        case .updateSuperProperty(_):
            newOp = UpdateSuperProperty(propertyName: b.randomPropertyName(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .beginIf(let op):
            newOp = BeginIf(inverted: !op.inverted)
        case .createWasmGlobal(let op):
            // The type has to match for wasm, we cannot just switch types here as the rest of the wasm code will become invalid.
            // TODO: add nullref and funcref as types here.
            let wasmGlobal: WasmGlobal
            switch op.value {
            case .wasmf32:
                wasmGlobal = .wasmf32(Float32(b.randomFloat()))
            case .wasmf64:
                wasmGlobal = .wasmf64(b.randomFloat())
            case .wasmi32:
                wasmGlobal = .wasmi32(Int32(truncatingIfNeeded: b.randomInt()))
            case .wasmi64:
                wasmGlobal = .wasmi64(b.randomInt())
            case .externref,
                 .exnref,
                 .i31ref:
                return instr
            case .refFunc,
                 .imported:
                // TODO(cffsmith): Support these enum values or drop them from the WasmGlobal.
                fatalError("unimplemented")
            }
            newOp = CreateWasmGlobal(value: wasmGlobal, isMutable: probability(0.5))
        case .createWasmMemory(let op):
            // TODO(evih): Implement shared memories.
            let newMinPages = Int.random(in: 0..<10)
            let newMaxPages = probability(0.5) ? nil : Int.random(in: newMinPages...WasmConstants.specMaxWasmMem32Pages)
            newOp = CreateWasmMemory(limits: Limits(min: newMinPages, max: newMaxPages), isMemory64: op.memType.isMemory64)
        case .createWasmTable(let op):
            let newMinSize = Int.random(in: 0..<10)
            var newMaxSize: Int? = nil
            if probability(0.5) {
                // TODO: Think about what actually makes sense here.
                newMaxSize = Int.random(in: newMinSize..<(newMinSize + 30))
            }
            newOp = CreateWasmTable(elementType: op.tableType.elementType, limits: Limits(min: newMinSize, max: newMaxSize), isTable64: op.tableType.isTable64)
        // Wasm Operations
        case .consti32(_):
            newOp = Consti32(value: Int32(truncatingIfNeeded: b.randomInt()))
        case .consti64(_):
            newOp = Consti64(value: b.randomInt())
        case .constf32(_):
            newOp = Constf32(value: Float32(b.randomFloat()))
        case .constf64(_):
            newOp = Constf64(value: b.randomFloat())

        // Wasm Numerical Operations
        case .wasmi32CompareOp(_):
            newOp = Wasmi32CompareOp(compareOpKind: chooseUniform(from: WasmIntegerCompareOpKind.allCases))
        case .wasmi64CompareOp(_):
            newOp = Wasmi64CompareOp(compareOpKind: chooseUniform(from: WasmIntegerCompareOpKind.allCases))
        case .wasmf32CompareOp(_):
            newOp = Wasmf32CompareOp(compareOpKind: chooseUniform(from: WasmFloatCompareOpKind.allCases))
        case .wasmf64CompareOp(_):
            newOp = Wasmf64CompareOp(compareOpKind: chooseUniform(from: WasmFloatCompareOpKind.allCases))
        case .wasmi32BinOp(_):
            newOp = Wasmi32BinOp(binOpKind: chooseUniform(from: WasmIntegerBinaryOpKind.allCases))
        case .wasmi64BinOp(_):
            newOp = Wasmi64BinOp(binOpKind: chooseUniform(from: WasmIntegerBinaryOpKind.allCases))
        case .wasmi32UnOp(_):
            newOp = Wasmi32UnOp(unOpKind: chooseUniform(from: WasmIntegerUnaryOpKind.allCases))
        case .wasmi64UnOp(_):
            newOp = Wasmi64UnOp(unOpKind: chooseUniform(from: WasmIntegerUnaryOpKind.allCases))
        case .wasmf32BinOp(_):
            newOp = Wasmf32BinOp(binOpKind: chooseUniform(from: WasmFloatBinaryOpKind.allCases))
        case .wasmf64BinOp(_):
            newOp = Wasmf64BinOp(binOpKind: chooseUniform(from: WasmFloatBinaryOpKind.allCases))
        case .wasmf32UnOp(_):
            newOp = Wasmf32UnOp(unOpKind: chooseUniform(from: WasmFloatUnaryOpKind.allCases))
        case .wasmf64UnOp(_):
            newOp = Wasmf64UnOp(unOpKind: chooseUniform(from: WasmFloatUnaryOpKind.allCases))

        case .wasmTruncatef32Toi32(_):
            newOp = WasmTruncatef32Toi32(isSigned: probability(0.5))
        case .wasmTruncatef64Toi32(_):
            newOp = WasmTruncatef64Toi32(isSigned: probability(0.5))
        case .wasmExtendi32Toi64(_):
            newOp = WasmExtendi32Toi64(isSigned: probability(0.5))
        case .wasmTruncatef32Toi64(_):
            newOp = WasmTruncatef32Toi64(isSigned: probability(0.5))
        case .wasmTruncatef64Toi64(_):
            newOp = WasmTruncatef64Toi64(isSigned: probability(0.5))
        case .wasmConverti32Tof32(_):
            newOp = WasmConverti32Tof32(isSigned: probability(0.5))
        case .wasmConverti64Tof32(_):
            newOp = WasmConverti64Tof32(isSigned: probability(0.5))
        case .wasmConverti32Tof64(_):
            newOp = WasmConverti32Tof64(isSigned: probability(0.5))
        case .wasmConverti64Tof64(_):
            newOp = WasmConverti64Tof64(isSigned: probability(0.5))
        case .wasmTruncateSatf32Toi32(_):
            newOp = WasmTruncateSatf32Toi32(isSigned: probability(0.5))
        case .wasmTruncateSatf64Toi32(_):
            newOp = WasmTruncateSatf64Toi32(isSigned: probability(0.5))
        case .wasmTruncateSatf32Toi64(_):
            newOp = WasmTruncateSatf32Toi64(isSigned: probability(0.5))
        case .wasmTruncateSatf64Toi64(_):
            newOp = WasmTruncateSatf64Toi64(isSigned: probability(0.5))

        case .wasmDefineGlobal(let op):
            // We never change the type of the global, only the value as changing the type will break the following code pretty much instantly.
            let wasmGlobal: WasmGlobal
            switch op.wasmGlobal.toType() {
            case .wasmf32:
                wasmGlobal = .wasmf32(Float32(b.randomFloat()))
            case .wasmf64:
                wasmGlobal = .wasmf64(b.randomFloat())
            case .wasmi32:
                wasmGlobal = .wasmi32(Int32(truncatingIfNeeded: b.randomInt()))
            case .wasmi64:
                wasmGlobal = .wasmi64(b.randomInt())
            case .wasmExternRef,
                 .wasmExnRef,
                 .wasmI31Ref:
                wasmGlobal = op.wasmGlobal
            default:
                fatalError("unexpected/unimplemented Value Type!")
            }
            newOp = WasmDefineGlobal(wasmGlobal: wasmGlobal, isMutable: probability(0.5))
        case .wasmDefineTable(let op):
            // TODO: change table size?
            newOp = op
        case .wasmDefineMemory(let op):
            // TODO(evih): Implement shared memories.
            let isMemory64 = op.wasmMemory.wasmMemoryType!.isMemory64
            // Making the memory empty will make all loads and stores OOB, so do it rarely.
            let newMinPages = probability(0.005) ? 0 : Int.random(in: 1..<10)
            let newMaxPages = probability(0.5) ? nil : Int.random(in: isMemory64 ? newMinPages...WasmConstants.specMaxWasmMem64Pages
                                                                                 : newMinPages...WasmConstants.specMaxWasmMem32Pages)
            newOp = WasmDefineMemory(limits: Limits(min: newMinPages, max: newMaxPages), isMemory64: isMemory64)
        case.wasmDefineDataSegment(_):
            newOp = WasmDefineDataSegment(segment: b.randomBytes())
        case .wasmMemoryLoad(let op):
            let newLoadType = chooseUniform(from: WasmMemoryLoadType.allCases.filter({$0.numberType() == op.loadType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmMemoryLoad(loadType: newLoadType, staticOffset: newStaticOffset)
        case .wasmMemoryStore(let op):
            let newStoreType = chooseUniform(from: WasmMemoryStoreType.allCases.filter({$0.numberType() == op.storeType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmMemoryStore(storeType: newStoreType, staticOffset: newStaticOffset)
        case .wasmAtomicLoad(let op):
            let newLoadType = chooseUniform(from: WasmAtomicLoadType.allCases.filter({$0.numberType() == op.loadType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmAtomicLoad(
                loadType: newLoadType,
                offset: newStaticOffset
            )
        case .wasmAtomicStore(let op):
            let newStoreType = chooseUniform(from: WasmAtomicStoreType.allCases.filter({$0.numberType() == op.storeType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmAtomicStore(
                storeType: newStoreType,
                offset: newStaticOffset
            )
        case .wasmAtomicRMW(let op):
            let newOpType = chooseUniform(from: WasmAtomicRMWType.allCases.filter({ $0.type() == op.op.type() }))
            let newOffset = b.randomInt()
            newOp = WasmAtomicRMW(op: newOpType, offset: newOffset)
        case .wasmAtomicCmpxchg(let op):
            let newOpType = chooseUniform(from: WasmAtomicCmpxchgType.allCases.filter({ $0.type() == op.op.type() }))
            let newOffset = b.randomInt()
            newOp = WasmAtomicCmpxchg(op: newOpType, offset: newOffset)
        case .constSimd128(_):
            newOp = ConstSimd128(value: (0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
        case .wasmSimd128IntegerUnOp(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter {!$0.isFloat()})
            let unOpKind = chooseUniform(from: WasmSimd128IntegerUnOpKind.allCases.filter {
                $0.isValidForShape(shape: shape)
            })
            newOp = WasmSimd128IntegerUnOp(shape: shape, unOpKind: unOpKind)
        case .wasmSimd128IntegerBinOp(let op):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter {!$0.isFloat()})
            // We can't convert between shift operations and other operations as they require
            // different input types.
            let isShift = op.binOpKind.isShift()
            let binOpKind = chooseUniform(from: WasmSimd128IntegerBinOpKind.allCases.filter{
                $0.isValidForShape(shape: shape) && $0.isShift() == isShift
            })
            newOp = WasmSimd128IntegerBinOp(shape: shape, binOpKind: binOpKind)
        case .wasmSimd128IntegerTernaryOp(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter { !$0.isFloat() })
            let ternaryOpKind = chooseUniform(from: WasmSimd128IntegerTernaryOpKind.allCases.filter {
                $0.isValidForShape(shape: shape)
            })
            newOp = WasmSimd128IntegerTernaryOp(shape: shape, ternaryOpKind: ternaryOpKind)
        case .wasmSimd128FloatUnOp(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter {$0.isFloat()})
            let unOpKind = chooseUniform(from: WasmSimd128FloatUnOpKind.allCases.filter {
                $0.isValidForShape(shape: shape)
            })
            newOp = WasmSimd128FloatUnOp(shape: shape, unOpKind: unOpKind)
        case .wasmSimd128FloatBinOp(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter {$0.isFloat()})
            let binOpKind = chooseUniform(from: WasmSimd128FloatBinOpKind.allCases.filter {
                $0.isValidForShape(shape: shape)
            })
            newOp = WasmSimd128FloatBinOp(shape: shape, binOpKind: binOpKind)
        case .wasmSimd128FloatTernaryOp(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases.filter { $0.isFloat() })
            let ternaryOpKind = chooseUniform(from: WasmSimd128FloatTernaryOpKind.allCases.filter {
                $0.isValidForShape(shape: shape)
            })
            newOp = WasmSimd128FloatTernaryOp(shape: shape, ternaryOpKind: ternaryOpKind)
        case .wasmSimd128Compare(_):
            let shape = chooseUniform(from: WasmSimd128Shape.allCases)
            newOp = WasmSimd128Compare(shape: shape, compareOpKind: b.randomSimd128CompareOpKind(shape))
        case .wasmSimdExtractLane(let op):
            newOp = WasmSimdExtractLane(kind: op.kind, lane: Int.random(in: 0..<op.kind.laneCount()))
        case .wasmSimdReplaceLane(let op):
            newOp = WasmSimdReplaceLane(kind: op.kind, lane: Int.random(in: 0..<op.kind.laneCount()))
        case .wasmSimdStoreLane(let op):
            let kind = chooseUniform(from: WasmSimdStoreLane.Kind.allCases)
            let staticOffset = probability(0.8)
                ? Int64.random(in: -256...256)
                : Int64.random(in: Int64.min...Int64.max) // most likely out of bounds
            newOp = WasmSimdStoreLane(kind: kind, staticOffset: staticOffset,
                lane: Int.random(in: 0..<op.kind.laneCount()))
        case .wasmSimdLoadLane(let op):
            let kind = chooseUniform(from: WasmSimdLoadLane.Kind.allCases)
            let staticOffset = probability(0.8)
                ? Int64.random(in: -256...256)
                : Int64.random(in: Int64.min...Int64.max) // most likely out of bounds
            newOp = WasmSimdLoadLane(kind: kind, staticOffset: staticOffset,
                lane: Int.random(in: 0..<op.kind.laneCount()))
        case .wasmSimdLoad(_):
            let kind = chooseUniform(from: WasmSimdLoad.Kind.allCases)
            let staticOffset = probability(0.8)
                ? Int64.random(in: -256...256)
                : Int64.random(in: Int64.min...Int64.max) // most likely out of bounds
            newOp = WasmSimdLoad(kind: kind, staticOffset: staticOffset)
        case .wasmBranchIf(let op):
            newOp = WasmBranchIf(labelTypes: op.labelTypes, hint: chooseUniform(from: WasmBranchHint.allCases))
        case .wasmBeginIf(let op):
            newOp = WasmBeginIf(with: op.signature, hint: chooseUniform(from: WasmBranchHint.allCases), inverted: Bool.random())
        case .wasmArrayGet(let op):
            // Switch signedness. (This only matters for packed types i8 and i16.)
            newOp = WasmArrayGet(isSigned: !op.isSigned)
        case .wasmStructGet(let op):
            // Switch signedness. (This only matters for packed types i8 and i16.)
            newOp = WasmStructGet(fieldIndex: op.fieldIndex, isSigned: !op.isSigned)
        case .wasmI31Get(let op):
            newOp = WasmI31Get(isSigned: !op.isSigned)
        // Unexpected operations to make the switch fully exhaustive.
        case .nop(_),
             .loadUndefined(_),
             .loadNull(_),
             .loadThis(_),
             .loadArguments(_),
             .beginObjectLiteral(_),
             .objectLiteralAddComputedProperty(_),
             .objectLiteralCopyProperties(_),
             .objectLiteralSetPrototype(_),
             .endObjectLiteralMethod(_),
             .beginObjectLiteralComputedMethod(_),
             .endObjectLiteralComputedMethod(_),
             .endObjectLiteralGetter(_),
             .endObjectLiteralSetter(_),
             .endObjectLiteral(_),
             .beginClassDefinition(_),
             .beginClassConstructor(_),
             .endClassConstructor(_),
             .classAddInstanceComputedProperty(_),
             .beginClassInstanceComputedMethod(_),
             .endClassInstanceComputedMethod(_),
             .beginClassStaticComputedMethod(_),
             .endClassStaticComputedMethod(_),
             .endClassInstanceMethod(_),
             .endClassInstanceGetter(_),
             .endClassInstanceSetter(_),
             .classAddStaticComputedProperty(_),
             .beginClassStaticInitializer(_),
             .endClassStaticInitializer(_),
             .endClassStaticMethod(_),
             .endClassStaticGetter(_),
             .endClassStaticSetter(_),
             .classAddPrivateInstanceProperty(_),
             .beginClassPrivateInstanceMethod(_),
             .endClassPrivateInstanceMethod(_),
             .classAddPrivateStaticProperty(_),
             .beginClassPrivateStaticMethod(_),
             .endClassPrivateStaticMethod(_),
             .endClassDefinition(_),
             .createArray(_),
             .getComputedProperty(_),
             .setComputedProperty(_),
             .getComputedSuperProperty(_),
             .setComputedSuperProperty(_),
             .deleteComputedProperty(_),
             .typeOf(_),
             .testInstanceOf(_),
             .testIn(_),
             .beginPlainFunction(_),
             .endPlainFunction(_),
             .beginArrowFunction(_),
             .endArrowFunction(_),
             .beginGeneratorFunction(_),
             .endGeneratorFunction(_),
             .beginAsyncFunction(_),
             .endAsyncFunction(_),
             .beginAsyncArrowFunction(_),
             .endAsyncArrowFunction(_),
             .beginAsyncGeneratorFunction(_),
             .endAsyncGeneratorFunction(_),
             .beginConstructor(_),
             .endConstructor(_),
             .return(_),
             .yield(_),
             .yieldEach(_),
             .await(_),
             .callFunction(_),
             .construct(_),
             .callComputedMethod(_),
             .ternaryOperation(_),
             .dup(_),
             .reassign(_),
             .eval(_),
             .beginWith(_),
             .endWith(_),
             .callSuperConstructor(_),
             .getPrivateProperty(_),
             .setPrivateProperty(_),
             .updatePrivateProperty(_),
             .callPrivateMethod(_),
             .beginElse(_),
             .endIf(_),
             .beginWhileLoopHeader(_),
             .beginWhileLoopBody(_),
             .endWhileLoop(_),
             .beginDoWhileLoopBody(_),
             .beginDoWhileLoopHeader(_),
             .endDoWhileLoop(_),
             .beginForLoopInitializer(_),
             .beginForLoopCondition(_),
             .beginForLoopAfterthought(_),
             .beginForLoopBody(_),
             .endForLoop(_),
             .beginForInLoop(_),
             .endForInLoop(_),
             .beginForOfLoop(_),
             .beginForOfLoopWithDestruct(_),
             .endForOfLoop(_),
             .beginRepeatLoop(_),
             .endRepeatLoop(_),
             .loopBreak(_),
             .loopContinue(_),
             .beginTry(_),
             .beginCatch(_),
             .beginFinally(_),
             .endTryCatchFinally(_),
             .throwException(_),
             .beginCodeString(_),
             .endCodeString(_),
             .beginBlockStatement(_),
             .endBlockStatement(_),
             .beginSwitch(_),
             .beginSwitchCase(_),
             .beginSwitchDefaultCase(_),
             .endSwitchCase(_),
             .endSwitch(_),
             .switchBreak(_),
             .loadNewTarget(_),
             .print(_),
             .explore(_),
             .probe(_),
             .fixup(_),
             .createNamedDisposableVariable(_),
             .createNamedAsyncDisposableVariable(_),
             .loadDisposableVariable(_),
             .loadAsyncDisposableVariable(_),
             .void(_),
             .directive(_),
             .wrapPromising(_),
             .wrapSuspending(_),
             .bindMethod(_),
             .bindFunction(_),
             // Wasm instructions
             .beginWasmModule(_),
             .endWasmModule(_),
             .wasmReturn(_),
             .wasmJsCall(_),
             .wasmReassign(_),
             .wasmLoadGlobal(_),
             .wasmStoreGlobal(_),
             .wasmTableGet(_),
             .wasmTableSet(_),
             .wasmCallIndirect(_),
             .wasmCallDirect(_),
             .wasmReturnCallDirect(_),
             .wasmReturnCallIndirect(_),
             .wasmi32EqualZero(_),
             .wasmi64EqualZero(_),
             .wasmWrapi64Toi32(_),
             .wasmDemotef64Tof32(_),
             .wasmPromotef32Tof64(_),
             .wasmReinterpretf32Asi32(_),
             .wasmReinterpretf64Asi64(_),
             .wasmReinterpreti32Asf32(_),
             .wasmReinterpreti64Asf64(_),
             .wasmSignExtend8Intoi32(_),
             .wasmSignExtend16Intoi32(_),
             .wasmSignExtend8Intoi64(_),
             .wasmSignExtend16Intoi64(_),
             .wasmSignExtend32Intoi64(_),
             .wasmMemorySize(_),
             .wasmMemoryGrow(_),
             .wasmMemoryCopy(_),
             .wasmMemoryFill(_),
             .wasmTableSize(_),
             .wasmTableGrow(_),
             .wasmMemoryInit(_),
             .wasmDropDataSegment(_),
             .beginWasmFunction(_),
             .endWasmFunction(_),
             .wasmBeginBlock(_),
             .wasmEndBlock(_),
             .wasmBeginLoop(_),
             .wasmEndLoop(_),
             .wasmBeginTryTable(_),
             .wasmEndTryTable(_),
             .wasmBeginTry(_),
             .wasmBeginCatchAll(_),
             .wasmBeginCatch(_),
             .wasmEndTry(_),
             .wasmBeginTryDelegate(_),
             .wasmEndTryDelegate(_),
             .wasmBranch(_),
             .wasmBranchTable(_),
             .wasmBeginElse(_),
             .wasmEndIf(_),
             .wasmNop(_),
             .wasmUnreachable(_),
             .wasmSelect(_),
             .wasmDefineTag(_),
             .createWasmTag(_),
             .createWasmJSTag(_),
             .wasmThrow(_),
             .wasmThrowRef(_),
             .wasmRethrow(_),
             .wasmSimdSplat(_),
             .wasmBeginTypeGroup(_),
             .wasmEndTypeGroup(_),
             .wasmDefineArrayType(_),
             .wasmDefineStructType(_),
             .wasmDefineSignatureType(_),
             .wasmDefineForwardOrSelfReference(_),
             .wasmResolveForwardReference(_),
             .wasmArrayNewFixed(_),
             .wasmArrayNewDefault(_),
             .wasmArrayLen(_),
             .wasmArraySet(_),
             .wasmStructNewDefault(_),
             .wasmStructSet(_),
             .wasmRefNull(_),
             .wasmRefIsNull(_),
             .wasmRefI31(_),
             .wasmAnyConvertExtern(_),
             .wasmExternConvertAny(_),
             .wasmDefineElementSegment(_),
             .wasmDropElementSegment(_),
             .wasmTableInit(_),
             .wasmTableCopy(_):
             let mutability = instr.isOperationMutable ? "mutable" : "immutable"
             fatalError("Unexpected operation \(instr.op.opcode), marked as \(mutability)")
        }

        // This assert is here to prevent subtle bugs if we ever decide to add flags that are "alive" during program building / mutation.
        // If we add flags, remove this assert and change the code below.
        assert(instr.flags == .empty)
        return Instruction(newOp, inouts: instr.inouts, flags: .empty)
    }

    private func extendVariadicOperation(_ instr: Instruction, _ b: ProgramBuilder) -> Instruction {
        var instr = instr
        let numInputsToAdd = Int.random(in: 1...3)
        for _ in 0..<numInputsToAdd {
            instr = extendVariadicOperationByOneInput(instr, b)
        }
        return instr
    }

    private func extendVariadicOperationByOneInput(_ instr: Instruction, _ b: ProgramBuilder) -> Instruction {
        // Without visible variables, we can't add a new input to this instruction.
        // This should happen rarely, so just skip this mutation.
        guard b.hasVisibleVariables else { return instr }

        let newOp: Operation
        var inputs = instr.inputs

        switch instr.op.opcode {
        case .createArray(let op):
            newOp = CreateArray(numInitialValues: op.numInitialValues + 1)
            inputs.append(b.randomJsVariable())
        case .createArrayWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomJsVariable())
            newOp = CreateArrayWithSpread(spreads: spreads)
        case .callFunction(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallFunction(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callFunctionWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomJsVariable())
            newOp = CallFunctionWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .construct(let op):
            inputs.append(b.randomJsVariable())
            newOp = Construct(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .constructWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomJsVariable())
            newOp = ConstructWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callMethod(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomJsVariable())
            newOp = CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callComputedMethod(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallComputedMethod(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callComputedMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomJsVariable())
            newOp = CallComputedMethodWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callSuperConstructor(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallSuperConstructor(numArguments: op.numArguments + 1)
        case .callPrivateMethod(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallPrivateMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .callSuperMethod(let op):
            inputs.append(b.randomJsVariable())
            newOp = CallSuperMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .bindFunction(_):
            inputs.append(b.randomJsVariable())
            newOp = BindFunction(numInputs: inputs.count)
        case .createTemplateString(let op):
            var parts = op.parts
            parts.append(b.randomString())
            inputs.append(b.randomJsVariable())
            newOp = CreateTemplateString(parts: parts)
        case .wasmEndTypeGroup(_):
            // Typegroups are mutated by the CodeGenMutator by calling
            // `ProgramBuilder.buildIntoTypeGroup` which handles "exporting" of defined types via
            // the WasmEndTypeGroup instruction.
            return instr
        default:
            fatalError("Unhandled Operation: \(type(of: instr.op))")
        }

        assert(inputs.count != instr.inputs.count)
        let inouts = inputs + instr.outputs + instr.innerOutputs

        // This assert is here to prevent subtle bugs if we ever decide to add flags that are "alive" during program building / mutation.
        // If we add flags, remove this assert and change the code below.
        assert(instr.flags == .empty)
        return Instruction(newOp, inouts: inouts, flags: .empty)
    }

    private func replaceRandomElement<T: Comparable>(in elements: inout Array<T>, generatingRandomValuesWith generator: () -> T) {
        // Pick a random index to replace.
        guard let index = elements.indices.randomElement() else { return }

        // Try to find a replacement value that does not already exist.
        for _ in 0...5 {
            let newElem = generator()
            // Ensure that we neither add an element that already exists nor add one that we just removed
            if !elements.contains(newElem) {
                elements[index] = newElem
                return
            }
        }

        // Failed to find a replacement value, so just leave the array unmodified.
    }
}
