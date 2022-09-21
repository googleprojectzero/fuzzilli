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

/// Reducer to remove inputs from variadic operations.
struct VariadicInputReducer: Reducer {
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        for instr in code {
            guard instr.isVariadic else { continue }
            let index = instr.index

            var instr = instr
            repeat {
                // Remove the last input (if it exists)
                guard instr.numInputs > instr.firstVariadicInput else { break }

                let newOp: Operation
                switch instr.op {
                case let op as CreateObject:
                    newOp = CreateObject(propertyNames: op.propertyNames.dropLast())
                case let op as CreateArray:
                    newOp = CreateArray(numInitialValues: op.numInitialValues - 1)
                case let op as CreateObjectWithSpread:
                    if op.numSpreads > 0 {
                        newOp = CreateObjectWithSpread(propertyNames: op.propertyNames, numSpreads: op.numSpreads - 1)
                    } else {
                        newOp = CreateObjectWithSpread(propertyNames: op.propertyNames.dropLast(), numSpreads: op.numSpreads)
                    }
                case let op as CreateArrayWithSpread:
                    newOp = CreateArrayWithSpread(spreads: op.spreads.dropLast())
                case let op as CallFunction:
                    newOp = CallFunction(numArguments: op.numArguments - 1)
                case let op as CallFunctionWithSpread:
                    if op.numArguments == 1 {
                        newOp = CallFunction(numArguments: 0)
                    } else {
                        newOp = CallFunctionWithSpread(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                    }
                case let op as Construct:
                    newOp = Construct(numArguments: op.numArguments - 1)
                case let op as ConstructWithSpread:
                    if op.numArguments == 1 {
                        newOp = Construct(numArguments: 0)
                    } else {
                        newOp = ConstructWithSpread(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                    }
                case let op as CallMethod:
                    newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments - 1)
                case let op as CallMethodWithSpread:
                    if op.numArguments == 1 {
                        newOp = CallMethod(methodName: op.methodName, numArguments: 0)
                    } else {
                        newOp = CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                    }
                case let op as CallComputedMethod:
                    newOp = CallComputedMethod(numArguments: op.numArguments - 1)
                case let op as CallComputedMethodWithSpread:
                    if op.numArguments == 1 {
                        newOp = CallComputedMethod(numArguments: 0)
                    } else {
                        newOp = CallComputedMethodWithSpread(numArguments: op.numArguments - 1, spreads: op.spreads.dropLast())
                    }
                case let op as CallSuperConstructor:
                    newOp = CallSuperConstructor(numArguments: op.numArguments - 1)
                case let op as CallSuperMethod:
                    newOp = CallSuperMethod(methodName: op.methodName, numArguments: op.numArguments - 1)
                case let op as CreateTemplateString:
                    newOp = CreateTemplateString(parts: op.parts.dropLast())
                default:
                    fatalError("Unknown variadic operation \(instr.op)")
                }

                let inouts = instr.inputs.dropLast() + instr.outputs + instr.innerOutputs
                instr = Instruction(newOp, inouts: inouts)
            } while verifier.tryReplacing(instructionAt: index, with: instr, in: &code)
        }
    }
}
