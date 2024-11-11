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

/// Attempts to inline functions at their callsite. This reducer is necessary to prevent deep nesting of functions.
struct InliningReducer: Reducer {
    func reduce(with helper: MinimizationHelper) {
        var candidates = identifyInlineableFunctions(in: helper.code)
        while !candidates.isEmpty {
            let funcIndex = candidates.removeLast()
            let newCode = inline(functionAt: funcIndex, in: helper.code)
            if helper.testAndCommit(newCode) {
                // Inlining changes the program so we need to redo our analysis.
                // In particular, instruction are reordered and variables are renamed. Further, there may now also be new inlining candidates, for example
                // if another function could previously not be inlined because it was used as argument or return value of a now inlined function).
                candidates = identifyInlineableFunctions(in: helper.code)
            }
        }
    }

    /// Identifies all inlineable functions in the given code.
    /// Returns the indices of the start of the inlineable functions.
    private func identifyInlineableFunctions(in code: Code) -> [Int] {
        var candidates = [Variable: (callCount: Int, index: Int)]()
        func deleteCandidates(_ toRemove: ArraySlice<Variable>) {
            for f in toRemove {
                candidates.removeValue(forKey: f)
            }
        }

        // Contains the output variable of all active subroutine definitions. As some subroutines don't have outputs (e.g. class methods), entries can also be nil.
        var activeSubroutineDefinitions = [Variable?]()

        for instr in code {
            // Identify candidates.
            switch instr.op.opcode {
                // Currently we only inline plain functions as that guarantees that the resulting code is always valid.
                // Otherwise, we might for example attempt to inline an async function containing an 'await', which would not be valid.
                // This works fine because the ReplaceReducer will attempt to turn "special" functions into plain functions.
            case .beginPlainFunction:
                candidates[instr.output] = (callCount: 0, index: instr.index)
                fallthrough
            case .beginArrowFunction,
                 .beginGeneratorFunction,
                 .beginAsyncFunction,
                 .beginAsyncArrowFunction,
                 .beginAsyncGeneratorFunction,
                 .beginConstructor,
                 .beginObjectLiteralMethod,
                 .beginObjectLiteralComputedMethod,
                 .beginObjectLiteralGetter,
                 .beginObjectLiteralSetter,
                 .beginClassConstructor,
                 .beginClassInstanceMethod,
                 .beginClassInstanceGetter,
                 .beginClassInstanceSetter,
                 .beginClassStaticInitializer,
                 .beginClassStaticMethod,
                 .beginClassStaticGetter,
                 .beginClassStaticSetter,
                 .beginClassPrivateInstanceMethod,
                 .beginClassPrivateStaticMethod:
                activeSubroutineDefinitions.append(instr.hasOneOutput ? instr.output : nil)
            case .endPlainFunction,
                 .endArrowFunction,
                 .endGeneratorFunction,
                 .endAsyncFunction,
                 .endAsyncArrowFunction,
                 .endAsyncGeneratorFunction,
                 .endConstructor,
                 .endObjectLiteralMethod,
                 .endObjectLiteralComputedMethod,
                 .endObjectLiteralGetter,
                 .endObjectLiteralSetter,
                 .endClassConstructor,
                 .endClassInstanceMethod,
                 .endClassInstanceGetter,
                 .endClassInstanceSetter,
                 .endClassStaticInitializer,
                 .endClassStaticMethod,
                 .endClassStaticGetter,
                 .endClassStaticSetter,
                 .endClassPrivateInstanceMethod,
                 .endClassPrivateStaticMethod:
                activeSubroutineDefinitions.removeLast()
            default:
                assert(!instr.op.contextOpened.contains(.subroutine))
                break
            }

            // Filter candidates.
            switch instr.op.opcode {
            case .callFunction:
                let f = instr.input(0)

                if let candidate = candidates[f] {
                    candidates[f] = (callCount: candidate.callCount + 1, index: candidate.index)
                }

                // Can't inline recursive calls.
                if activeSubroutineDefinitions.contains(f) {
                    candidates.removeValue(forKey: f)
                }

                // Can't inline functions that are passed as arguments to other functions.
                deleteCandidates(instr.inputs.dropFirst())
            case .loadNewTarget,
                 .loadArguments,
                 .loadDisposableVariable:
                // Can't inline functions if they access their arguments or new.target.
                if let function = activeSubroutineDefinitions.last! {
                    candidates.removeValue(forKey: function)
                }
            default:
                assert(instr.op is Return || !(instr.op.requiredContext.contains(.subroutine)))

                // Can't inline functions that are used as inputs for other instructions.
                deleteCandidates(instr.inputs)
            }
        }

        return candidates.values.filter({ $0.callCount == 1}).map({ $0.index })
    }

    /// Returns a new Code object with the specified function inlined into its callsite.
    /// The specified function must be called exactly once in the provided code.
    private func inline(functionAt index: Int, in code: Code) -> Code {
        assert(index < code.count)
        assert(code[index].op is BeginAnyFunction)

        var c = Code()
        var i = 0

        // Append all code prior to the function that we're inlining.
        while i < index {
            c.append(code[i])
            i += 1
        }

        let funcDefinition = code[i]
        let function = funcDefinition.output
        let parameters = Array(funcDefinition.innerOutputs)

        i += 1

        // Fast-forward to end of function definition
        var functionBody = [Instruction]()
        var depth = 0
        while i < code.count {
            let instr = code[i]

            if instr.op is BeginAnyFunction {
                depth += 1
            }
            if instr.op is EndAnyFunction {
                if depth == 0 {
                    i += 1
                    break
                } else {
                    depth -= 1
                }
            }

            functionBody.append(instr)

            i += 1
        }
        assert(i < code.count)

        // Search for the call of the function
        while i < code.count {
            let instr = code[i]

            if instr.op is CallFunction && instr.input(0) == function {
                break
            }

            assert(!instr.inputs.contains(function))

            c.append(instr)
            i += 1
        }
        assert(i < code.count)

        // Found it. Inline the function now
        let call = code[i]
        assert(call.op is CallFunction)

        // Reuse the function variable to store 'undefined' and use that for any missing arguments.
        let undefined = funcDefinition.output
        c.append(Instruction(LoadUndefined(), output: undefined))

        var arguments = VariableMap<Variable>()
        for (i, v) in parameters.enumerated() {
            if call.numInputs - 1 > i {
                arguments[v] = call.input(i + 1)
            } else {
                arguments[v] = undefined
            }
        }

        // Initialize the return value to undefined.
        let rval = call.output
        c.append(Instruction(LoadUndefined(), output: rval, inputs: []))

        var functionDefinitionDepth = 0
        for instr in functionBody {
            let newInouts = instr.inouts.map { arguments[$0] ?? $0 }
            let newInstr = Instruction(instr.op, inouts: newInouts, flags: instr.flags)

            // Returns (from the function being inlined) are converted to assignments to the return value.
            if instr.op is Return && functionDefinitionDepth == 0 {
                // Returns may not have a return value, in which case we'll use undefined.
                let value = newInstr.hasInputs ? newInstr.input(0) : undefined
                c.append(Instruction(Reassign(), inputs: [rval, value]))
            } else {
                c.append(newInstr)

                if instr.op is BeginAnyFunction {
                    functionDefinitionDepth += 1
                } else if instr.op is EndAnyFunction {
                    functionDefinitionDepth -= 1
                }
            }
        }

        // Insert a Nop to keep the code size the same across inlining, which is required by the minimizer tests.
        // Inlining removes the Begin + End operations and the call operation. The first two were already replaced by LoadUndefined.
        c.append(Instruction(Nop()))

        i += 1

        // Copy remaining instructions
        while i < code.count {
            assert(!code[i].inputs.contains(function))
            c.append(code[i])
            i += 1
        }

        // Need to renumber the variables now as they are no longer in ascending order.
        c.renumberVariables()

        // The code must now be valid.
        assert(c.isStaticallyValid())
        return c
    }
}
