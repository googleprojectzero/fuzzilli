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

/// A mutator that randomly mutates parameters of the Operations in the given program.
public class OperationMutator: BaseInstructionMutator {
    public init() {
        super.init(maxSimultaneousMutations: defaultMaxSimultaneousMutations)
    }
    
    public override func canMutate(_ instr: Instruction) -> Bool {
        return instr.isParametric
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        var newOp: Operation
        
        b.trace("Mutating next operation")

        func replaceRandomElement<T>(in set: inout Set<T>, generatingRandomValuesWith generator: () -> T) {
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
        
        switch instr.op {
        case is LoadInteger:
            newOp = LoadInteger(value: b.genInt())
        case is LoadBigInt:
            newOp = LoadBigInt(value: b.genInt())
        case is LoadFloat:
            newOp = LoadFloat(value: b.genFloat())
        case is LoadString:
            newOp = LoadString(value: b.genString())
        case let op as LoadRegExp:
            if probability(0.5) {
                newOp = LoadRegExp(value: b.genRegExp(), flags: op.flags)
            } else {
                newOp = LoadRegExp(value: op.value, flags: b.genRegExpFlags())
            }
        case let op as LoadBoolean:
            newOp = LoadBoolean(value: !op.value)
        case let op as CreateObject:
            var propertyNames = op.propertyNames
            assert(!propertyNames.isEmpty)          // Otherwise operation would not be parametric
            // Replace an existing property with another one
            propertyNames[Int.random(in: 0..<propertyNames.count)] = b.genPropertyNameForWrite()
            newOp = CreateObject(propertyNames: propertyNames)
        case let op as CreateObjectWithSpread:
            var propertyNames = op.propertyNames
            assert(!propertyNames.isEmpty)          // Otherwise operation would not be parametric
            // Replace an existing property with another one
            propertyNames[Int.random(in: 0..<propertyNames.count)] = b.genPropertyNameForWrite()
            newOp = CreateObjectWithSpread(propertyNames: propertyNames, numSpreads: op.numSpreads)
        case let op as CreateArrayWithSpread:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CreateArrayWithSpread(numInitialValues: spreads.count, spreads: spreads)
        case is LoadBuiltin:
            newOp = LoadBuiltin(builtinName: b.genBuiltinName())
        case is LoadProperty:
            newOp = LoadProperty(propertyName: b.genPropertyNameForRead())
        case is StoreProperty:
            newOp = StoreProperty(propertyName: b.genPropertyNameForWrite())
        case is StorePropertyWithBinop:
            newOp = StorePropertyWithBinop(propertyName: b.genPropertyNameForWrite(), operator: chooseUniform(from: allBinaryOperators))
        case is DeleteProperty:
            newOp = DeleteProperty(propertyName: b.genPropertyNameForWrite())
        case is LoadElement:
            newOp = LoadElement(index: b.genIndex())
        case is StoreElement:
            newOp = StoreElement(index: b.genIndex())
        case is StoreElementWithBinop:
            newOp = StoreElementWithBinop(index: b.genIndex(), operator: chooseUniform(from: allBinaryOperators))
        case is StoreComputedPropertyWithBinop:
            newOp = StoreComputedPropertyWithBinop(operator: chooseUniform(from: allBinaryOperators))
        case is DeleteElement:
            newOp = DeleteElement(index: b.genIndex())
        case let op as CallMethod:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CallMethod(methodName: b.genMethodName(), numArguments: op.numArguments, spreads: spreads)
        case let op as CallComputedMethod:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CallComputedMethod(numArguments: op.numArguments, spreads: spreads)
        case let op as CallFunction:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CallFunction(numArguments: op.numArguments, spreads: spreads)
        case let op as Construct:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = Construct(numArguments: op.numArguments, spreads: spreads)
        case is UnaryOperation:
            newOp = UnaryOperation(chooseUniform(from: allUnaryOperators))
        case is BinaryOperation:
            newOp = BinaryOperation(chooseUniform(from: allBinaryOperators))
        case is ReassignWithBinop:
            newOp = ReassignWithBinop(chooseUniform(from: allBinaryOperators))
        case let op as DestructArray:
            var newIndices = Set(op.indices)
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int.random(in: 0..<10) })
            newOp = DestructArray(indices: newIndices.sorted(), hasRestElement: !op.hasRestElement)
        case let op as DestructArrayAndReassign:
            var newIndices = Set(op.indices)
            replaceRandomElement(in: &newIndices, generatingRandomValuesWith: { return Int.random(in: 0..<10) })
            newOp = DestructArrayAndReassign(indices: newIndices.sorted(), hasRestElement: !op.hasRestElement)
        case let op as DestructObject:
            var newProperties = Set(op.properties)
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.genPropertyNameForRead() })
            newOp = DestructObject(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case let op as DestructObjectAndReassign:
            var newProperties = Set(op.properties)
            replaceRandomElement(in: &newProperties, generatingRandomValuesWith: { return b.genPropertyNameForRead() })
            newOp = DestructObjectAndReassign(properties: newProperties.sorted(), hasRestElement: !op.hasRestElement)
        case is Compare:
            newOp = Compare(chooseUniform(from: allComparators))
        case is LoadFromScope:
            newOp = LoadFromScope(id: b.genPropertyNameForRead())
        case is StoreToScope:
            newOp = StoreToScope(id: b.genPropertyNameForWrite())
        /*case let op as BeginClassMethodDefinition: TODO(saelo)
            // TODO also mutate the signature?
            newOp = BeginClassMethodDefinition(name: b.genMethodName(), signature: op.signature)*/
        case let op as CallSuperMethod:
            newOp = CallSuperMethod(methodName: b.genMethodName(), numArguments: op.numArguments)
        case let op as CallSuperConstructor:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CallSuperConstructor(numArguments: op.numArguments, spreads: spreads)
        case is LoadSuperProperty:
            newOp = LoadSuperProperty(propertyName: b.genPropertyNameForRead())
        case is StoreSuperProperty:
            newOp = StoreSuperProperty(propertyName: b.genPropertyNameForWrite())
        case is StoreSuperPropertyWithBinop:
            newOp = StoreSuperPropertyWithBinop(propertyName: b.genPropertyNameForWrite(), operator: chooseUniform(from: allBinaryOperators))    
        case is BeginWhile:
            newOp = BeginWhile(comparator: chooseUniform(from: allComparators))
        case is BeginDoWhile:
            newOp = BeginDoWhile(comparator: chooseUniform(from: allComparators))
        case let op as BeginFor:
            if probability(0.5) {
                newOp = BeginFor(comparator: chooseUniform(from: allComparators), op: op.op)
            } else {
                newOp = BeginFor(comparator: op.comparator, op: chooseUniform(from: allBinaryOperators))
            }
        case let op as BeginPlainFunctionDefinition:
            newOp = BeginPlainFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        case let op as BeginGeneratorFunctionDefinition:
            newOp = BeginGeneratorFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        case let op as BeginAsyncFunctionDefinition:
            newOp = BeginAsyncFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        case let op as BeginAsyncGeneratorFunctionDefinition:
            newOp = BeginAsyncGeneratorFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        case let op as BeginArrowFunctionDefinition:
            newOp = BeginArrowFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        case let op as BeginAsyncArrowFunctionDefinition:
            newOp = BeginAsyncArrowFunctionDefinition(signature: op.signature, isStrict: !op.isStrict)
        default:
            fatalError("Unhandled Operation: \(type(of: instr.op))")
        }

        b.adopt(Instruction(newOp, inouts: instr.inouts), keepTypes: false)
    }
}
