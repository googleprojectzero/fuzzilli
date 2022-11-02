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

// Attempts to simplify "complex" instructions into simpler instructions.
struct SimplifyingReducer: Reducer {
    func reduce(_ code: inout Code, with helper: MinimizationHelper) {
        simplifyFunctionDefinitions(&code, with: helper)
        simplifySingleInstructions(&code, with: helper)
        simplifyMultiInstructions(&code, with: helper)
    }

    func simplifyFunctionDefinitions(_ code: inout Code, with helper: MinimizationHelper) {
        // Try to turn "fancy" functions into plain functions
        for group in Blocks.findAllBlockGroups(in: code) {
            guard let begin = group.begin.op as? BeginAnyFunction else { continue }
            assert(group.end.op is EndAnyFunction)
            if begin is BeginPlainFunction { continue }

            let newBegin = Instruction(BeginPlainFunction(parameters: begin.parameters, isStrict: begin.isStrict), inouts: group.begin.inouts)
            let newEnd = Instruction(EndPlainFunction())
            helper.tryReplacements([(group.head, newBegin), (group.tail, newEnd)], in: &code)
        }
    }

    /// Simplify instructions that can be replaced by a single, simple instruction.
    func simplifySingleInstructions(_ code: inout Code, with helper: MinimizationHelper) {
        // Miscellaneous simplifications. This will:
        //   - convert SomeOpWithSpread into SomeOp since spread operations are less "mutation friendly" (somewhat low value, high chance of producing invalid code)
        //   - convert Constructs into Calls
        //   - convert strict functions into non-strict functions
        for instr in code {
            var newOp: Operation? = nil
            switch instr.op {
            case let op as CreateObjectWithSpread:
                if op.numSpreads == 0 {
                    newOp = CreateObject(propertyNames: op.propertyNames)
                }
            case let op as CreateArrayWithSpread:
                newOp = CreateArray(numInitialValues: op.numInputs)
            case let op as CallFunctionWithSpread:
                newOp = CallFunction(numArguments: op.numArguments)
            case let op as ConstructWithSpread:
                newOp = Construct(numArguments: op.numArguments)
            case let op as CallMethodWithSpread:
                newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments)
            case let op as CallComputedMethodWithSpread:
                newOp = CallComputedMethod(numArguments: op.numArguments)

            case let op as Construct:
                // Prefer simple function calls over constructor calls if there's no difference
                newOp = CallFunction(numArguments: op.numArguments)

            // Prefer non strict functions over strict ones
            case let op as BeginPlainFunction:
                if op.isStrict {
                    newOp = BeginPlainFunction(parameters: op.parameters, isStrict: false)
                }
            case let op as BeginArrowFunction:
                if op.isStrict {
                    newOp = BeginArrowFunction(parameters: op.parameters, isStrict: false)
                }
            case let op as BeginGeneratorFunction:
                if op.isStrict {
                    newOp = BeginGeneratorFunction(parameters: op.parameters, isStrict: false)
                }
            case let op as BeginAsyncFunction:
                if op.isStrict {
                    newOp = BeginAsyncFunction(parameters: op.parameters, isStrict: false)
                }
            case let op as BeginAsyncGeneratorFunction:
                if op.isStrict {
                    newOp = BeginAsyncGeneratorFunction(parameters: op.parameters, isStrict: false)
                }

            default:
                break
            }

            if let op = newOp {
                helper.tryReplacing(instructionAt: instr.index, with: Instruction(op, inouts: instr.inouts), in: &code)
            }
        }
    }

    /// Simplify instructions that can be replaced by a sequence of simpler instructions.
    func simplifyMultiInstructions(_ code: inout Code, with helper: MinimizationHelper) {
        // This will:
        //  - convert destructuring operations into simple property or element loads
        //
        // All simplifications are performed at once to keep this logic simple.
        var newCode = Code()
        var numCopiedInstructions = 0
        for instr in code {
            switch instr.op {
            case let op as DestructObject:
                let outputs = Array(instr.outputs)
                for (i, propertyName) in op.properties.enumerated() {
                    newCode.append(Instruction(LoadProperty(propertyName: propertyName), output: outputs[i], inputs: [instr.input(0)]))
                }
            case let op as DestructArray:
                let outputs = Array(instr.outputs)
                for (i, idx) in op.indices.enumerated() {
                    newCode.append(Instruction(LoadElement(index: idx), output: outputs[i], inputs: [instr.input(0)]))
                }
            default:
                numCopiedInstructions += 1
                newCode.append(instr)
            }
        }

        let didMakeChanges = numCopiedInstructions != code.count
        if didMakeChanges && helper.test(newCode) {
            code = newCode
        }
    }
}
