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
        super.init(maxSimultaneousMutations: 3)
    }
    
    override public func canMutate(_ instr: Instruction) -> Bool {
        return instr.isParametric && instr.isMutable
    }

    override public func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        var newOp: Operation
        
        switch instr.operation {
        case is LoadInteger:
            newOp = LoadInteger(value: b.genInt())
        case is LoadBigInt:
            newOp = LoadBigInt(value: b.genInt())
        case is LoadFloat:
            newOp = LoadFloat(value: b.genFloat())
        case is LoadString:
            newOp = LoadString(value: b.genString())
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
        case is DeleteProperty:
            newOp = DeleteProperty(propertyName: b.genPropertyNameForWrite())
        case is LoadElement:
            newOp = LoadElement(index: b.genIndex())
        case is StoreElement:
            newOp = StoreElement(index: b.genIndex())
        case is DeleteElement:
            newOp = DeleteElement(index: b.genIndex())
        case let op as CallMethod:
            newOp = CallMethod(methodName: b.genMethodName(), numArguments: op.numArguments)
        case let op as CallFunctionWithSpread:
            var spreads = op.spreads
            if spreads.count > 0 {
                let idx = Int.random(in: 0..<spreads.count)
                spreads[idx] = !spreads[idx]
            }
            newOp = CallFunctionWithSpread(numArguments: op.numArguments, spreads: spreads)
        case is UnaryOperation:
            newOp = UnaryOperation(chooseUniform(from: allUnaryOperators))
        case is BinaryOperation:
            newOp = BinaryOperation(chooseUniform(from: allBinaryOperators))
        case is Compare:
            newOp = Compare(chooseUniform(from: allComparators))
        case is LoadFromScope:
            newOp = LoadFromScope(id: b.genPropertyNameForRead())
        case is StoreToScope:
            newOp = StoreToScope(id: b.genPropertyNameForWrite())
        case is BeginWhile:
            newOp = BeginWhile(comparator: chooseUniform(from: allComparators))
        case is EndDoWhile:
            newOp = EndDoWhile(comparator: chooseUniform(from: allComparators))
        case let op as BeginFor:
            if probability(0.5) {
                newOp = BeginFor(comparator: chooseUniform(from: allComparators), op: op.op)
            } else {
                newOp = BeginFor(comparator: op.comparator, op: chooseUniform(from: allBinaryOperators))
            }
        default:
            fatalError("[OperationMutator] Unhandled Operation: \(type(of: instr.operation))")
        }
                
        b.adopt(Instruction(operation: newOp, inouts: instr.inouts))
    }
}
