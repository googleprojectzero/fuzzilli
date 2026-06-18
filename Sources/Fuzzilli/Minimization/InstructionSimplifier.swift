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
struct InstructionSimplifier: Reducer {
    func reduce(with helper: MinimizationHelper) {
        simplifyFunctionDefinitions(with: helper)
        simplifyNamedInstructions(with: helper)
        simplifyGuardedInstructions(with: helper)
        simplifySingleInstructions(with: helper)
        simplifyMultiInstructions(with: helper)
    }

    func simplifyFunctionDefinitions(with helper: MinimizationHelper) {
        // Try to turn "fancy" functions into plain functions
        for group in helper.code.findAllBlockGroups() {
            guard let begin = helper.code[group.head].op as? BeginAnyFunction else { continue }
            assert(helper.code[group.tail].op is EndAnyFunction)
            if begin is BeginPlainFunction { continue }

            let functionName = (begin as? BeginAnyNamedFunction)?.functionName ?? nil
            let newBegin = Instruction(
                BeginPlainFunction(parameters: begin.parameters, functionName: functionName),
                inouts: helper.code[group.head].inouts)
            let newEnd = Instruction(EndPlainFunction())

            // The resulting code may be invalid as we may be changing the context inside the body (e.g. turning an async function into a plain one).
            helper.tryReplacements(
                [(group.head, newBegin), (group.tail, newEnd)], expectCodeToBeValid: false)
        }
    }

    func simplifyNamedInstructions(with helper: MinimizationHelper) {
        // Try to remove the names of values and objects.
        for instr in helper.code {
            var newOp: Operation? = nil
            switch instr.op.opcode {
            case .beginPlainFunction(let op) where op.functionName != nil:
                newOp = BeginPlainFunction(parameters: op.parameters, functionName: nil)
            case .beginWorkerFunction(let op) where op.functionName != nil:
                newOp = BeginWorkerFunction(parameters: op.parameters, functionName: nil)
            case .beginGeneratorFunction(let op) where op.functionName != nil:
                newOp = BeginGeneratorFunction(parameters: op.parameters, functionName: nil)
            case .beginAsyncFunction(let op) where op.functionName != nil:
                newOp = BeginAsyncFunction(parameters: op.parameters, functionName: nil)
            case .beginAsyncGeneratorFunction(let op) where op.functionName != nil:
                newOp = BeginAsyncGeneratorFunction(parameters: op.parameters, functionName: nil)
            default:
                assert((instr.op as? BeginAnyNamedFunction)?.functionName == nil)
            }

            if let op = newOp {
                helper.tryReplacing(
                    instructionAt: instr.index,
                    with: Instruction(op, inouts: instr.inouts))
            }
        }
    }

    /// Simplify instructions that can be replaced by a single, simple instruction.
    func simplifySingleInstructions(with helper: MinimizationHelper) {
        // Miscellaneous simplifications. This will:
        //   - convert SomeOpWithSpread into SomeOp since spread operations are less "mutation friendly" (somewhat low value, high chance of producing invalid code)
        //   - convert Constructs into Calls
        //   - convert strict functions into non-strict functions
        // Since we only change operations in a forward fashion and never change instructions "in front of us" this iterator should stay valid.
        for instr in helper.code {
            var newOp: Operation? = nil
            switch instr.op.opcode {
            case .createArrayWithSpread(let op):
                newOp = CreateArray(numInitialValues: op.numInputs)
            case .callFunctionWithSpread(let op):
                newOp = CallFunction(numArguments: op.numArguments, isGuarded: op.isGuarded)
            case .constructWithSpread(let op):
                newOp = Construct(numArguments: op.numArguments, isGuarded: op.isGuarded)
            case .callMethodWithSpread(let op):
                newOp = CallMethod(
                    methodName: op.methodName, numArguments: op.numArguments,
                    isGuarded: op.isGuarded)
            case .callComputedMethodWithSpread(let op):
                newOp = CallComputedMethod(numArguments: op.numArguments, isGuarded: op.isGuarded)

            case .construct(let op):
                // Prefer simple function calls over constructor calls if there's no difference
                newOp = CallFunction(numArguments: op.numArguments, isGuarded: op.isGuarded)

            default:
                break
            }

            if let op = newOp {
                helper.tryReplacing(
                    instructionAt: instr.index,
                    with: Instruction(op, inouts: instr.inouts))
            }
        }
    }

    func simplifyGuardedInstructions(with helper: MinimizationHelper) {
        // This will attempt to turn guarded operations into unguarded ones.
        // In the lifted JavaScript code, this would turn something like `try { o.foo(); } catch (e) {}` into `o.foo();`
        for instr in helper.code {
            guard let op = instr.op as? GuardableOperation else { continue }
            let newOp = GuardableOperation.disableGuard(of: op)
            if newOp !== op {
                helper.tryReplacing(
                    instructionAt: instr.index,
                    with: Instruction(newOp, inouts: instr.inouts))
            }
        }
    }

    /// Simplify instructions that can be replaced by a sequence of simpler instructions.
    func simplifyMultiInstructions(with helper: MinimizationHelper) {
        // This will:
        //  - convert destructuring operations into simple property or element loads
        //
        // All simplifications are performed at once to keep this logic simple.
        // This logic needs to be somewhat careful not to perform no-op replacements as
        // these would cause the fixpoint iteration to not terminate.
        var newCode = Code(isBundle: helper.code.isBundle)
        var numCopiedInstructions = 0
        for instr in helper.code {
            var keepInstruction = true
            switch instr.op.opcode {

            // TODO(rherouart): Also simplify DestructAndReassign in a similar way (by converting flat targets into individual assignment operations).
            // TODO(rherouart): Consider a secondary simplification step that tries to drop default values.
            case .destruct(let op):
                guard !op.pattern.hasNestedDestructuring else { break }
                guard
                    instr.outputs.count > 1
                        || (instr.outputs.count == 1 && !op.pattern.hasRestElement)
                else { break }

                var outputs = instr.outputs.makeIterator()

                switch op.pattern {
                case .object(let obj):
                    var leftOverProperties: [DestructuringPattern.ObjectProperty] = []
                    var leftOverOutputs: [Variable] = []
                    var simplifiedAny = false

                    for property in obj.properties {
                        let output = outputs.next()!
                        if case .string(let propertyName) = property.key, !property.hasDefaultValue
                        {
                            newCode.append(
                                Instruction(
                                    GetProperty(propertyName: propertyName, isGuarded: false),
                                    output: output, inputs: [instr.input(0)]))
                            simplifiedAny = true
                        } else {
                            leftOverProperties.append(property)
                            leftOverOutputs.append(output)
                        }
                    }

                    if obj.hasRestElement {
                        leftOverOutputs.append(outputs.next()!)
                    }

                    if simplifiedAny {
                        if !leftOverProperties.isEmpty || obj.hasRestElement {
                            newCode.append(
                                Instruction(
                                    Destruct(
                                        pattern: DestructuringPattern.object(
                                            DestructuringPattern.ObjectPattern(
                                                properties: leftOverProperties,
                                                hasRestElement: obj.hasRestElement)),
                                        numInputs: instr.inputs.count,
                                        numOutputs: leftOverOutputs.count),
                                    inouts: Array(instr.inputs) + leftOverOutputs))
                        }
                        keepInstruction = false
                    }

                case .array(let arr):
                    var leftOverElements: [DestructuringPattern.ArrayElement] = []
                    var leftOverOutputs: [Variable] = []
                    var currentIndex = 0
                    var simplifiedAny = false

                    for element in arr.elements {
                        if case .flatBinding = element.target, !element.hasDefaultValue {
                            let output = outputs.next()!
                            newCode.append(
                                Instruction(
                                    GetElement(index: Int64(currentIndex), isGuarded: false),
                                    output: output, inputs: [instr.input(0)]))
                            leftOverElements.append(
                                DestructuringPattern.ArrayElement(target: .elision))
                            simplifiedAny = true
                        } else {
                            if case .elision = element.target {
                                // No output variable for elisions
                            } else {
                                leftOverOutputs.append(outputs.next()!)
                            }
                            leftOverElements.append(element)
                        }
                        currentIndex += 1
                    }

                    if arr.restTarget != .none {
                        leftOverOutputs.append(outputs.next()!)
                    }

                    if simplifiedAny {
                        if !leftOverOutputs.isEmpty {
                            newCode.append(
                                Instruction(
                                    Destruct(
                                        pattern: DestructuringPattern.array(
                                            DestructuringPattern.ArrayPattern(
                                                elements: leftOverElements,
                                                restTarget: arr.restTarget)),
                                        numInputs: instr.inputs.count,
                                        numOutputs: leftOverOutputs.count),
                                    inouts: Array(instr.inputs) + leftOverOutputs))
                        }
                        keepInstruction = false
                    }
                }
            default:
                break
            }

            if keepInstruction {
                numCopiedInstructions += 1
                newCode.append(instr)
            }
        }

        let didMakeChanges = numCopiedInstructions != helper.code.count
        if didMakeChanges {
            helper.testAndCommit(newCode)
        }
    }
}
