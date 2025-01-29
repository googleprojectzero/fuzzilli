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
        case .loadString(_):
            newOp = LoadString(value: b.randomString())
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
        case .setProperty(_):
            newOp = SetProperty(propertyName: b.randomPropertyName())
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
            switch op.value.toType() {
            case .wasmf32:
                wasmGlobal =  .wasmf32(Float32(b.randomFloat()))
            case .wasmf64:
                wasmGlobal = .wasmf64(b.randomFloat())
            case .wasmi32:
                wasmGlobal = .wasmi32(Int32(truncatingIfNeeded: b.randomInt()))
            case .wasmi64:
                wasmGlobal = .wasmi64(b.randomInt())
            default:
                fatalError("unexpected/unimplemented Value Type!")
            }
            newOp = CreateWasmGlobal(value: wasmGlobal, isMutable: probability(0.5))
        case .createWasmMemory(let op):
            // TODO(evih): Implement shared memories.
            let newMinPages = Int.random(in: 0..<10)
            let newMaxPages = probability(0.5) ? nil : Int.random(in: newMinPages...WasmOperation.WasmConstants.specMaxWasmMem32Pages)
            newOp = CreateWasmMemory(limits: Limits(min: newMinPages, max: newMaxPages), isMemory64: op.memType.isMemory64)
        case .createWasmTable(let op):
            let newMinSize = Int.random(in: 0..<10)
            var newMaxSize: Int? = nil
            if probability(0.5) {
                // TODO: Think about what actually makes sense here.
                newMaxSize = Int.random(in: newMinSize..<(newMinSize + 30))
            }
            newOp = CreateWasmTable(elementType: op.tableType.elementType, limits: Limits(min: newMinSize, max: newMaxSize))
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
            let newMaxPages = probability(0.5) ? nil : Int.random(in: isMemory64 ? newMinPages...WasmOperation.WasmConstants.specMaxWasmMem64Pages
                                                                                 : newMinPages...WasmOperation.WasmConstants.specMaxWasmMem32Pages)
            newOp = WasmDefineMemory(limits: Limits(min: newMinPages, max: newMaxPages), isMemory64: isMemory64)
        case .wasmMemoryLoad(let op):
            let newLoadType = chooseUniform(from: WasmMemoryLoadType.allCases.filter({$0.numberType() == op.loadType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmMemoryLoad(loadType: newLoadType, staticOffset: newStaticOffset, isMemory64: op.isMemory64)
        case .wasmMemoryStore(let op):
            let newStoreType = chooseUniform(from: WasmMemoryStoreType.allCases.filter({$0.numberType() == op.storeType.numberType()}))
            let newStaticOffset = b.randomInt()
            newOp = WasmMemoryStore(storeType: newStoreType, staticOffset: newStaticOffset, isMemory64: op.isMemory64)
        case .wasmThrow(let op):
            // TODO(mliedtke): Allow mutation of the inputs.
            newOp = op
        case .constSimd128(let op):
            // TODO: ?
            newOp = op
        case .wasmSimd128IntegerUnOp(let op):
            // TODO: ?
            newOp = op
        case .wasmSimd128IntegerBinOp(let op):
            // TODO: ?
            newOp = op
        case .wasmSimd128FloatUnOp(let op):
            // TODO: ?
            newOp = op
        case .wasmSimd128FloatBinOp(let op):
            // TODO: ?
            newOp = op
        case .wasmSimd128Compare(let op):
            // TODO: ?
            newOp = op
        case .wasmI64x2Splat(let op):
            // TODO: ?
            newOp = op
        case .wasmI64x2ExtractLane(let op):
            // TODO: ?
            newOp = op
        case .wasmSimdLoad(let op):
            // TODO: ?
            newOp = op
        case .createWasmJSTag(let op):
            newOp = op
        case .createWasmTag(let op):
            // TODO(mliedtke): We could mutate the types / counts of params.
            newOp = op
        case .wasmRethrow(let op):
            // TODO(mliedtke): Pick another input exception to rethrow if available.
            newOp = op
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
             .loadDisposableVariable(_),
             .loadAsyncDisposableVariable(_),
             .void(_),
             .directive(_),
             .wrapPromising(_),
             .wrapSuspending(_),
             .bindMethod(_),
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
             .beginWasmFunction(_),
             .endWasmFunction(_),
             .wasmBeginBlock(_),
             .wasmEndBlock(_),
             .wasmBeginLoop(_),
             .wasmEndLoop(_),
             .wasmBeginTry(_),
             .wasmBeginCatchAll(_),
             .wasmBeginCatch(_),
             .wasmEndTry(_),
             .wasmBeginTryDelegate(_),
             .wasmEndTryDelegate(_),
             .wasmBranch(_),
             .wasmBranchIf(_),
             .wasmBeginIf(_),
             .wasmBeginElse(_),
             .wasmEndIf(_),
             .wasmNop(_),
             .wasmUnreachable(_),
             .wasmSelect(_),
             .wasmDefineTag(_):
             assert(!instr.isOperationMutable)
             fatalError("Unexpected Operation")
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
            inputs.append(b.randomVariable())
        case .createArrayWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomVariable())
            newOp = CreateArrayWithSpread(spreads: spreads)
        case .callFunction(let op):
            inputs.append(b.randomVariable())
            newOp = CallFunction(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callFunctionWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomVariable())
            newOp = CallFunctionWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .construct(let op):
            inputs.append(b.randomVariable())
            newOp = Construct(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .constructWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomVariable())
            newOp = ConstructWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callMethod(let op):
            inputs.append(b.randomVariable())
            newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomVariable())
            newOp = CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callComputedMethod(let op):
            inputs.append(b.randomVariable())
            newOp = CallComputedMethod(numArguments: op.numArguments + 1, isGuarded: op.isGuarded)
        case .callComputedMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randomVariable())
            newOp = CallComputedMethodWithSpread(numArguments: op.numArguments + 1, spreads: spreads, isGuarded: op.isGuarded)
        case .callSuperConstructor(let op):
            inputs.append(b.randomVariable())
            newOp = CallSuperConstructor(numArguments: op.numArguments + 1)
        case .callPrivateMethod(let op):
            inputs.append(b.randomVariable())
            newOp = CallPrivateMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .callSuperMethod(let op):
            inputs.append(b.randomVariable())
            newOp = CallSuperMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .createTemplateString(let op):
            var parts = op.parts
            parts.append(b.randomString())
            inputs.append(b.randomVariable())
            newOp = CreateTemplateString(parts: parts)
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
