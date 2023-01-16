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
            newOp = LoadInteger(value: b.randInt())
        case .loadBigInt(_):
            newOp = LoadBigInt(value: b.randInt())
        case .loadFloat(_):
            newOp = LoadFloat(value: b.randFloat())
        case .loadString(_):
            newOp = LoadString(value: b.randString())
        case .loadRegExp(let op):
            if probability(0.5) {
                newOp = LoadRegExp(pattern: b.randRegExpPattern(), flags: op.flags)
            } else {
                newOp = LoadRegExp(pattern: op.pattern, flags: RegExpFlags.random())
            }
        case .loadBoolean(let op):
            newOp = LoadBoolean(value: !op.value)
        case .objectLiteralAddProperty:
            newOp = ObjectLiteralAddProperty(propertyName: b.randPropertyForDefining())
        case .objectLiteralAddElement:
            newOp = ObjectLiteralAddElement(index: b.randIndex())
        case .beginObjectLiteralMethod(let op):
            newOp = BeginObjectLiteralMethod(methodName: b.randMethodForDefining(), parameters: op.parameters)
        case .beginObjectLiteralGetter:
            newOp = BeginObjectLiteralGetter(propertyName: b.randPropertyForDefining())
        case .beginObjectLiteralSetter:
            newOp = BeginObjectLiteralSetter(propertyName: b.randPropertyForDefining())
        case .classAddInstanceProperty(let op):
            newOp = ClassAddInstanceProperty(propertyName: b.randPropertyForDefining(), hasValue: op.hasValue)
        case .classAddInstanceElement(let op):
            newOp = ClassAddInstanceElement(index: b.randIndex(), hasValue: op.hasValue)
        case .beginClassInstanceMethod(let op):
            newOp = BeginClassInstanceMethod(methodName: b.randMethodForDefining(), parameters: op.parameters)
        case .createIntArray:
            var values = [Int64]()
            for _ in 0..<Int.random(in: 1...10) {
                values.append(b.randInt())
            }
            newOp = CreateIntArray(values: values)
        case .createFloatArray:
            var values = [Double]()
            for _ in 0..<Int.random(in: 1...10) {
                values.append(b.randFloat())
            }
            newOp = CreateFloatArray(values: values)
        case .createArrayWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CreateArrayWithSpread(spreads: spreads)
        case .loadBuiltin(_):
            newOp = LoadBuiltin(builtinName: b.randBuiltin())
        case .loadProperty(_):
            newOp = LoadProperty(propertyName: b.randPropertyForReading())
        case .storeProperty(_):
            newOp = StoreProperty(propertyName: b.randPropertyForWriting())
        case .storePropertyWithBinop(_):
            newOp = StorePropertyWithBinop(propertyName: b.randPropertyForWriting(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .deleteProperty(_):
            newOp = DeleteProperty(propertyName: b.randPropertyForWriting())
        case .configureProperty(let op):
            // Change the flags or the property name, but don't change the type as that would require changing the inputs as well.
            if probability(0.5) {
                newOp = ConfigureProperty(propertyName: b.randPropertyForWriting(), flags: op.flags, type: op.type)
            } else {
                newOp = ConfigureProperty(propertyName: op.propertyName, flags: PropertyFlags.random(), type: op.type)
            }
        case .loadElement(_):
            newOp = LoadElement(index: b.randIndex())
        case .storeElement(_):
            newOp = StoreElement(index: b.randIndex())
        case .storeElementWithBinop(_):
            newOp = StoreElementWithBinop(index: b.randIndex(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .storeComputedPropertyWithBinop(_):
            newOp = StoreComputedPropertyWithBinop(operator: chooseUniform(from: BinaryOperator.allCases))
        case .deleteElement(_):
            newOp = DeleteElement(index: b.randIndex())
        case .configureElement(let op):
            // Change the flags or the element index, but don't change the type as that would require changing the inputs as well.
            if probability(0.5) {
                newOp = ConfigureElement(index: b.randIndex(), flags: op.flags, type: op.type)
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
            newOp = CallFunctionWithSpread(numArguments: op.numArguments, spreads: spreads)
        case .constructWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = ConstructWithSpread(numArguments: op.numArguments, spreads: spreads)
        case .callMethod(let op):
            newOp = CallMethod(methodName: b.randMethod(), numArguments: op.numArguments)
        case .callMethodWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CallMethodWithSpread(methodName: b.randMethod(), numArguments: op.numArguments, spreads: spreads)
        case .callComputedMethodWithSpread(let op):
            var spreads = op.spreads
            assert(!spreads.isEmpty)
            let idx = Int.random(in: 0..<spreads.count)
            spreads[idx] = !spreads[idx]
            newOp = CallComputedMethodWithSpread(numArguments: op.numArguments, spreads: spreads)
        case .unaryOperation(_):
            newOp = UnaryOperation(chooseUniform(from: UnaryOperator.allCases))
        case .binaryOperation(_):
            newOp = BinaryOperation(chooseUniform(from: BinaryOperator.allCases))
        case .reassignWithBinop(_):
            newOp = ReassignWithBinop(chooseUniform(from: BinaryOperator.allCases))
        case .destructArray(let op):
            var newIndices = Set(op.indices)
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int64.random(in: 0..<10) })
            newOp = DestructArray(indices: newIndices.sorted(), hasRestElement: !op.hasRestElement)
        case .destructArrayAndReassign(let op):
            var newIndices = Set(op.indices)
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int64.random(in: 0..<10) })
            newOp = DestructArrayAndReassign(indices: newIndices.sorted(), hasRestElement: !op.hasRestElement)
        case .destructObject(let op):
            var newProperties = Set(op.properties)
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.randPropertyForReading() })
            newOp = DestructObject(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case .destructObjectAndReassign(let op):
            var newProperties = Set(op.properties)
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.randPropertyForReading() })
            newOp = DestructObjectAndReassign(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case .compare(_):
            newOp = Compare(chooseUniform(from: Comparator.allCases))
        case .loadFromScope(_):
            newOp = LoadFromScope(id: b.randPropertyForReading())
        case .storeToScope(_):
            newOp = StoreToScope(id: b.randPropertyForWriting())
        case .callSuperMethod(let op):
            newOp = CallSuperMethod(methodName: b.randMethod(), numArguments: op.numArguments)
        case .loadSuperProperty(_):
            newOp = LoadSuperProperty(propertyName: b.randPropertyForReading())
        case .storeSuperProperty(_):
            newOp = StoreSuperProperty(propertyName: b.randPropertyForWriting())
        case .storeSuperPropertyWithBinop(_):
            newOp = StoreSuperPropertyWithBinop(propertyName: b.randPropertyForWriting(), operator: chooseUniform(from: BinaryOperator.allCases))
        case .beginIf(let op):
            newOp = BeginIf(inverted: !op.inverted)
        case .beginWhileLoop(_):
            newOp = BeginWhileLoop(comparator: chooseUniform(from: Comparator.allCases))
        case .beginDoWhileLoop(_):
            newOp = BeginDoWhileLoop(comparator: chooseUniform(from: Comparator.allCases))
        case .beginForLoop(let op):
            if probability(0.5) {
                newOp = BeginForLoop(comparator: chooseUniform(from: Comparator.allCases), op: op.op)
            } else {
                newOp = BeginForLoop(comparator: op.comparator, op: chooseUniform(from: BinaryOperator.allCases))
            }
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
            inputs.append(b.randVar())
        case .createArrayWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randVar())
            newOp = CreateArrayWithSpread(spreads: spreads)
        case .callFunction(let op):
            inputs.append(b.randVar())
            newOp = CallFunction(numArguments: op.numArguments + 1)
        case .callFunctionWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randVar())
            newOp = CallFunctionWithSpread(numArguments: op.numArguments + 1, spreads: spreads)
        case .construct(let op):
            inputs.append(b.randVar())
            newOp = Construct(numArguments: op.numArguments + 1)
        case .constructWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randVar())
            newOp = ConstructWithSpread(numArguments: op.numArguments + 1, spreads: spreads)
        case .callMethod(let op):
            inputs.append(b.randVar())
            newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .callMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randVar())
            newOp = CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments + 1, spreads: spreads)
        case .callComputedMethod(let op):
            inputs.append(b.randVar())
            newOp = CallComputedMethod(numArguments: op.numArguments + 1)
        case .callComputedMethodWithSpread(let op):
            let spreads = op.spreads + [Bool.random()]
            inputs.append(b.randVar())
            newOp = CallComputedMethodWithSpread(numArguments: op.numArguments + 1, spreads: spreads)
        case .callSuperConstructor(let op):
            inputs.append(b.randVar())
            newOp = CallSuperConstructor(numArguments: op.numArguments + 1)
        case .callSuperMethod(let op):
            inputs.append(b.randVar())
            newOp = CallSuperMethod(methodName: op.methodName, numArguments: op.numArguments + 1)
        case .createTemplateString(let op):
            var parts = op.parts
            parts.append(b.randString())
            inputs.append(b.randVar())
            newOp = CreateTemplateString(parts: parts)
        default:
            fatalError("Unhandled Operation: \(type(of: instr.op))")
        }

        assert(inputs.count != instr.inputs.count)
        let inouts = inputs + instr.outputs + instr.innerOutputs
        return Instruction(newOp, inouts: inouts)
    }

    private func replaceRandomElement<T>(in set: inout Set<T>, generatingRandomValuesWith generator: () -> T) {
        guard let removedElem = set.randomElement() else { return }
        set.remove(removedElem)

        for _ in 0...5 {
            let newElem = generator()
            // Ensure that we neither add an element that already exists nor add one that we just removed
            if !set.contains(newElem) && newElem != removedElem {
                set.insert(newElem)
                return
            }
        }

        // Failed to insert a new element, so just insert the removed element again as we must not change the size of the set
        set.insert(removedElem)
    }
}
