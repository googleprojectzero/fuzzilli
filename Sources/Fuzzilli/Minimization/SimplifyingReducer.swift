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
        for group in code.findAllBlockGroups() {
            guard let begin = code[group.head].op as? BeginAnyFunction else { continue }
            assert(code[group.tail].op is EndAnyFunction)
            if begin is BeginPlainFunction { continue }

            let newBegin = Instruction(BeginPlainFunction(parameters: begin.parameters, isStrict: begin.isStrict), inouts: code[group.head].inouts)
            let newEnd = Instruction(EndPlainFunction())

            // The resulting code may be invalid as we may be changing the context inside the body (e.g. turning an async function into a plain one).
            helper.tryReplacements([(group.head, newBegin), (group.tail, newEnd)], in: &code, expectCodeToBeValid: false)
        }
    }

    /// Simplify instructions that can be replaced by a single, simple instruction.
    func simplifySingleInstructions(_ code: inout Code, with helper: MinimizationHelper) {
        // Miscellaneous simplifications. This will:
        //   - convert SomeOpWithSpread into SomeOp since spread operations are less "mutation friendly" (somewhat low value, high chance of producing invalid code)
        //   - convert Constructs into Calls
        //   - convert strict functions into non-strict functions
        //   - convert guarded property access into unguarded property access (e.g. `a?.b` into `a.b`)
        for instr in code {
            var newOp: Operation? = nil
            switch instr.op.opcode {
            case .createArrayWithSpread(let op):
                newOp = CreateArray(numInitialValues: op.numInputs)
            case .callFunctionWithSpread(let op):
                newOp = CallFunction(numArguments: op.numArguments)
            case .constructWithSpread(let op):
                newOp = Construct(numArguments: op.numArguments)
            case .callMethodWithSpread(let op):
                newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments, isGuarded: op.isGuarded)
            case .callComputedMethodWithSpread(let op):
                newOp = CallComputedMethod(numArguments: op.numArguments, isGuarded: op.isGuarded)

            case .construct(let op):
                // Prefer simple function calls over constructor calls if there's no difference
                newOp = CallFunction(numArguments: op.numArguments)

            // Prefer non strict functions over strict ones
            case .beginPlainFunction(let op):
                if op.isStrict {
                    newOp = BeginPlainFunction(parameters: op.parameters, isStrict: false)
                }
            case .beginArrowFunction(let op):
                if op.isStrict {
                    newOp = BeginArrowFunction(parameters: op.parameters, isStrict: false)
                }
            case .beginGeneratorFunction(let op):
                if op.isStrict {
                    newOp = BeginGeneratorFunction(parameters: op.parameters, isStrict: false)
                }
            case .beginAsyncFunction(let op):
                if op.isStrict {
                    newOp = BeginAsyncFunction(parameters: op.parameters, isStrict: false)
                }
            case .beginAsyncGeneratorFunction(let op):
                if op.isStrict {
                    newOp = BeginAsyncGeneratorFunction(parameters: op.parameters, isStrict: false)
                }

            // Prefer non-guarded operations over guarded ones (e.g. `a.b` instead of `a?.b`)
            case .getProperty(let op):
                if op.isGuarded {
                    newOp = GetProperty(propertyName: op.propertyName, isGuarded: false)
                }
            case .deleteProperty(let op):
                if op.isGuarded {
                    newOp = DeleteProperty(propertyName: op.propertyName, isGuarded: false)
                }
            case .getElement(let op):
                if op.isGuarded {
                    newOp = GetElement(index: op.index, isGuarded: false)
                }
            case .deleteElement(let op):
                if op.isGuarded {
                    newOp = DeleteElement(index: op.index, isGuarded: false)
                }
            case .getComputedProperty(let op):
                if op.isGuarded {
                    newOp = GetComputedProperty(isGuarded: false)
                }
            case .deleteComputedProperty(let op):
                if op.isGuarded {
                    newOp = DeleteComputedProperty(isGuarded: false)
                }
            case .callMethod(let op):
                if op.isGuarded {
                    newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments, isGuarded: false)
                }
            case .callComputedMethod(let op):
                if op.isGuarded {
                    newOp = CallComputedMethod(numArguments: op.numArguments, isGuarded: false)
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
        // This logic needs to be somewhat careful not to perform no-op replacements as
        // these would cause the fixpoint iteration to not terminate.
        var newCode = Code()
        var numCopiedInstructions = 0
        for instr in code {
            var keepInstruction = true
            switch instr.op.opcode {
            case .destructObject(let op):
                guard op.properties.count > 0 else {
                    // Cannot simplify this as it would be a no-op
                    break
                }

                let outputs = Array(instr.outputs)
                for (i, propertyName) in op.properties.enumerated() {
                    newCode.append(Instruction(GetProperty(propertyName: propertyName, isGuarded: false), output: outputs[i], inputs: [instr.input(0)]))
                }
                if op.hasRestElement {
                    newCode.append(Instruction(DestructObject(properties: [], hasRestElement: true), output: outputs.last!, inputs: [instr.input(0)]))
                }
                keepInstruction = false
            case .destructArray(let op):
                guard op.indices.count > 1 || !op.lastIsRest else {
                    // Cannot simplify this as it would be a no-op
                    break
                }

                let outputs = Array(instr.outputs)
                for (i, idx) in op.indices.enumerated() {
                    if i == op.indices.last! && op.lastIsRest {
                        newCode.append(Instruction(DestructArray(indices: [idx], lastIsRest: true), output: outputs.last!, inputs: [instr.input(0)]))
                    } else {
                        newCode.append(Instruction(GetElement(index: idx, isGuarded: false), output: outputs[i], inputs: [instr.input(0)]))
                    }
                }
                keepInstruction = false
            default:
                break
            }

            if keepInstruction {
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
