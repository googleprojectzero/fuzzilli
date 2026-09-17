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
        simplifyOptionalInstructions(with: helper)
        simplifySingleInstructions(with: helper)
        simplifyMultiInstructions(with: helper)
        simplifyWasmInstructions(with: helper)
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
                newOp = CallFunction(
                    numArguments: op.numArguments, isGuarded: op.isGuarded,
                    isCallOptional: op.isCallOptional)
            case .constructWithSpread(let op):
                newOp = Construct(numArguments: op.numArguments, isGuarded: op.isGuarded)
            case .callMethodWithSpread(let op):
                newOp = CallMethod(
                    methodName: op.methodName, numArguments: op.numArguments,
                    isGuarded: op.isGuarded, isReceiverOptional: op.isReceiverOptional,
                    isCallOptional: op.isCallOptional)
            case .callComputedMethodWithSpread(let op):
                newOp = CallComputedMethod(
                    numArguments: op.numArguments, isGuarded: op.isGuarded,
                    isReceiverOptional: op.isReceiverOptional, isCallOptional: op.isCallOptional)
            case .callPrivateMethodWithSpread(let op):
                newOp = CallPrivateMethod(
                    methodName: op.methodName, numArguments: op.numArguments,
                    isGuarded: op.isGuarded, isReceiverOptional: op.isReceiverOptional,
                    isCallOptional: op.isCallOptional)

            case .construct(let op):
                // Prefer simple function calls over constructor calls if there's no difference
                newOp = CallFunction(
                    numArguments: op.numArguments, isGuarded: op.isGuarded, isCallOptional: false)

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
            guard let op = instr.op as? GuardableOperation, op.isGuarded else { continue }
            let newOp = op.withGuardedState(false)
            helper.tryReplacing(
                instructionAt: instr.index,
                with: Instruction(newOp, inouts: instr.inouts))
        }
    }

    func simplifyOptionalInstructions(with helper: MinimizationHelper) {
        // This will attempt to turn optional operations into non-optional ones.
        // In the lifted JavaScript code, this would turn something like `o?.foo` into `o.foo`
        for instr in helper.code {
            if let op = helper.code[instr.index].op as? ReceiverOptionalOperation,
                op.isReceiverOptional
            {
                let newOp = op.withReceiverOptionalState(false)
                helper.tryReplacing(
                    instructionAt: instr.index,
                    with: Instruction(newOp, inouts: instr.inouts))
            }
            if let op = helper.code[instr.index].op as? CallOptionalOperation, op.isCallOptional {
                let newOp = op.withCallOptionalState(false)
                helper.tryReplacing(
                    instructionAt: instr.index,
                    with: Instruction(newOp, inouts: instr.inouts))
            }
        }
    }

    /// Simplify instructions that can be replaced by a sequence of simpler instructions.
    func simplifyMultiInstructions(with helper: MinimizationHelper) {
        // Lowers destructuring operations into atomic load/store, respecting tc39 evaluation order.
        // This is all-or-nothing: partially lowering a pattern would leave a residual destructuring
        // operation that runs out-of-order.
        var newCode = Code(isBundle: helper.code.isBundle)
        var numCopiedInstructions = 0

        // Temporaries are allocated at the end of the variable space, so the code has to be
        // renumbered afterwards to make the variable numbers continuous again.
        var nextFreeVariable = helper.code.nextFreeVariable()
        var didAllocateVariables = false
        func allocateVariable() -> Variable {
            defer { nextFreeVariable = Variable(number: nextFreeVariable.number + 1) }
            didAllocateVariables = true
            return nextFreeVariable
        }

        var typer = JSTyper(for: helper.fuzzer.environment, isBundle: helper.code.isBundle)
        func isKnownArray(_ v: Variable) -> Bool {
            let type = typer.type(of: v)
            if type.Is(.object(ofGroup: "Array")) { return true }
            return JavaScriptEnvironment.typedArrayConstructors.contains {
                type.Is(.object(ofGroup: $0))
            }
        }

        /// Whether the given pattern can be lowered into an equivalent sequence of loads and
        /// stores. Rejected patterns keep their destructuring operation.
        /// `source` is the variable being destructured, or nil for a nested pattern
        func canBeLowered(_ pattern: DestructuringPattern, source: Variable?) -> Bool {
            func canLowerTarget(_ target: DestructuringPattern.Target?) -> Bool {
                switch target {
                // An elision in an array pattern, which doesn't assign anything.
                case nil:
                    return true
                case .flatBinding, .property, .element, .computedProperty, .privateProperty,
                    .superProperty, .superComputedProperty:
                    return true
                // This would require a "SetSuperElement" operation, which doesn't exist.
                case .superElement:
                    return false
                // Lowered recursively, with the loaded value as the source of the nested
                // pattern. That value has no known type, so nested array patterns are rejected.
                // Note: If an inner pattern cannot be lowered (e.g. `let {foo: {bar: x, ...y}} = o`),
                // we reject the whole pattern rather than partially lowering the outer pattern into
                // a temporary variable (`let tmp = o.foo; let {bar: x, ...y} = tmp;`).
                case .pattern(let pattern):
                    return canBeLowered(pattern, source: nil)
                }
            }

            switch pattern {
            case .object(let obj):
                // TODO(rherouart): "const {} = null" does throw, but lowering it to no instruction won't
                guard !obj.properties.isEmpty else { return false }
                // An object rest element (...rest) copies all remaining own enumerable properties into a
                // fresh object at runtime, which cannot be lowered to static GetProperty loads.
                guard !obj.hasRestElement else { return false }
                // A default value would require branching on `undefined`.
                return obj.properties.allSatisfy {
                    !$0.hasDefaultValue && canLowerTarget($0.target)
                }
            case .array(let arr):
                guard let source, isKnownArray(source) else { return false }
                // TODO(rherouart):
                // An empty pattern still requests an iterator from the source, so it can throw.
                // Lowering it to no instruction won't throw
                guard !arr.elements.isEmpty else { return false }
                // TODO(rherouart): Array.prototype.slice is not equivalent to a rest element: it preserves holes
                guard arr.restTarget == nil else { return false }
                return arr.elements.allSatisfy { !$0.hasDefaultValue && canLowerTarget($0.target) }
            }
        }

        /// Lowers the given pattern into a sequence of loads and stores.
        ///
        /// `nextInput` provides the inputs of the operation (excluding the source) in the order in
        /// which they appear in the pattern, `nextOutput` the outputs of a Destruct operation. For
        /// a DestructAndReassign operation, which declares no new variables, `nextOutput` is nil.
        func lower(
            _ pattern: DestructuringPattern, of source: Variable,
            nextInput: () -> Variable, nextOutput: (() -> Variable)?
        ) {
            /// Loads one value from the source (via `emitLoad`) and assigns it to `target`.
            func assign(_ target: DestructuringPattern.Target?, emitLoad: (Variable) -> Void) {
                // An elision, which only advances the iterator.
                guard let target else { return }

                // When declaring new variables, the loaded value is the new binding, so neither a
                // temporary variable nor a separate store instruction is needed.
                if case .flatBinding = target, let nextOutput {
                    return emitLoad(nextOutput())
                }

                let value = allocateVariable()
                emitLoad(value)

                switch target {
                case .flatBinding:
                    newCode.append(Instruction(Reassign(), inputs: [nextInput(), value]))
                case .property(let propertyName):
                    newCode.append(
                        Instruction(
                            SetProperty(propertyName: propertyName, isGuarded: false),
                            inputs: [nextInput(), value]))
                case .element(let index):
                    newCode.append(
                        Instruction(SetElement(index: index), inputs: [nextInput(), value]))
                case .computedProperty:
                    let object = nextInput()
                    let key = nextInput()
                    newCode.append(
                        Instruction(SetComputedProperty(), inputs: [object, key, value]))
                case .privateProperty(let propertyName):
                    newCode.append(
                        Instruction(
                            SetPrivateProperty(propertyName: propertyName, isGuarded: false),
                            inputs: [nextInput(), value]))
                case .superProperty(let propertyName):
                    newCode.append(
                        Instruction(SetSuperProperty(propertyName: propertyName), inputs: [value]))
                case .superComputedProperty:
                    newCode.append(
                        Instruction(SetComputedSuperProperty(), inputs: [nextInput(), value]))
                case .pattern(let pattern):
                    lower(pattern, of: value, nextInput: nextInput, nextOutput: nextOutput)
                case .superElement:
                    assert(false, "Excluded by canBeLowered")
                    break
                }
            }

            switch pattern {
            case .object(let obj):
                for property in obj.properties {
                    switch property.key {
                    case .string(let propertyName):
                        assign(property.target) { output in
                            newCode.append(
                                Instruction(
                                    GetProperty(propertyName: propertyName), output: output,
                                    inputs: [source]))
                        }
                    case .computed:
                        // The key is evaluated before the load, which is not observable here.
                        let key = nextInput()
                        assign(property.target) { output in
                            newCode.append(
                                Instruction(
                                    GetComputedProperty(), output: output, inputs: [source, key]))
                        }
                    }
                }
            case .array(let arr):
                for (index, element) in arr.elements.enumerated() {
                    assign(element.target) { output in
                        newCode.append(
                            Instruction(
                                GetElement(index: Int64(index)), output: output, inputs: [source]))
                    }
                }
            }
        }

        for instr in helper.code {
            typer.analyze(instr)

            var keepInstruction = true
            switch instr.op.opcode {

            // TODO(rherouart): Add a pass that drops unused rest elements and default values so more patterns can be lowered.
            case .destruct(let op):
                let source = instr.input(0)
                guard canBeLowered(op.pattern, source: source) else { break }

                var inputs = instr.inputs.dropFirst().makeIterator()
                var outputs = instr.outputs.makeIterator()
                lower(
                    op.pattern, of: source, nextInput: { inputs.next()! },
                    nextOutput: { outputs.next()! })
                assert(inputs.next() == nil && outputs.next() == nil)
                keepInstruction = false

            case .destructAndReassign(let op):
                var source = instr.input(0)
                guard canBeLowered(op.pattern, source: source) else { break }

                // The lowering reads the source once per part, so if the source is also a
                // target we need to keep a copy of its original value.
                if instr.inputs.dropFirst().contains(source) {
                    let copy = allocateVariable()
                    newCode.append(Instruction(Dup(), output: copy, inputs: [source]))
                    source = copy
                }

                var inputs = instr.inputs.dropFirst().makeIterator()
                lower(op.pattern, of: source, nextInput: { inputs.next()! }, nextOutput: nil)
                assert(inputs.next() == nil)
                keepInstruction = false

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
            if didAllocateVariables {
                newCode.renumberVariables()
            }
            helper.testAndCommit(newCode)
        }
    }

    func simplifyWasmInstructions(with helper: MinimizationHelper) {
        for instr in helper.code {
            switch instr.op.opcode {
            case .wasmDefineArrayType(let op):
                if op.hasSuperType {
                    let newOp = WasmDefineArrayType(
                        elementType: op.elementType, mutability: op.mutability, hasSuperType: false,
                        isFinal: op.isFinal)
                    let newInouts = instr.inputs.dropFirst() + instr.outputs
                    helper.tryReplacing(
                        instructionAt: instr.index,
                        with: Instruction(newOp, inouts: Array(newInouts)))
                }
            case .endWasmModule(let op):
                if op.hasStartFunction {
                    let newOp = EndWasmModule(hasStartFunction: false)
                    let newInouts = Array(instr.outputs)
                    helper.tryReplacing(
                        instructionAt: instr.index,
                        with: Instruction(newOp, inouts: newInouts))
                }
            default:
                break
            }
        }
    }
}
