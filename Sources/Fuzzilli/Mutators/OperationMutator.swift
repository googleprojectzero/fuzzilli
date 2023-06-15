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
        case .loadBuiltin(_):
            newOp = LoadBuiltin(builtinName: b.randomBuiltin())
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
        case .loadNamedVariable:
            // We just use property names as variable names here. It's not clear if there's a better alternative and this also works well with `with` statements.
            newOp = LoadNamedVariable(b.randomPropertyName())
        case .storeNamedVariable:
            newOp = StoreNamedVariable(b.randomPropertyName())
        case .defineNamedVariable:
            newOp = DefineNamedVariable(b.randomPropertyName())
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
        default:
            fatalError("Unhandled Operation: \(type(of: instr.op))")
        }

        return Instruction(newOp, inouts: instr.inouts)
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
        return Instruction(newOp, inouts: inouts)
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
