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

/// Inlines functions at their callsite if possible to prevent deep nesting of functions.
///
/// This attempts to inline all types of functions, including generators and async functions. Often,
/// this won't result in semantically valid JavaScript, but since we check the program for validity
/// after every inlining attempt, that should be fine.
struct InliningReducer: Reducer {
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        var functions = [Variable]()
        var candidates = VariableMap<Int>()
        var stack = [Variable]()
        for instr in code {
            switch instr.op {
            case is BeginAnyFunction:
                functions.append(instr.output)
                candidates[instr.output] = 0
                stack.append(instr.output)
            case is EndAnyFunction:
                stack.removeLast()
            case is CallFunction:
                let f = instr.input(0)

                // Can't inline recursive calls
                if stack.contains(f) {
                    candidates.removeValue(forKey: f)
                }

                if let callCount = candidates[f] {
                    candidates[f] = callCount + 1
                }

                for v in instr.inputs.dropFirst() {
                    candidates.removeValue(forKey: v)
                }
            default:
                for v in instr.inputs {
                    candidates.removeValue(forKey: v)
                }
            }
        }

        for f in functions {
            if candidates.contains(f) && candidates[f] == 1 {
                // Try inlining the function
                let newCode = inline(f, in: code)
                // Must normalize (a copy of) the code before attempting to execute it.
                if verifier.test(newCode.normalized()) {
                    code = newCode
                }
            }
        }

        // Must normalize the code now as variable numbers are no longer in ascending order.
        // We can only do this now, after performing all inline() calls, as otherwise the variables
        // might get renamed in between calls to inline(), which would invalidate the |functions|
        // list as the variables stored in it would suddenly refer to different values.
        code.normalize()
        Assert(code.isStaticallyValid())
    }

    /// Inlines the given function into its callsite. The given function variable must be the output of a function definition instruction and it
    /// must be called exactly once in the provided code. Returns a new code object with the function inlined. Important: the returned code
    /// is not normalized. In particular, variables will not be defined in sequential order and some variables may not be defined at all.
    /// The caller is responsible for normalizing the code after inlining.
    func inline(_ function: Variable, in code: Code) -> Code {
        var c = Code()
        var i = 0

        while i < code.count {
            let instr = code[i]

            if instr.numOutputs == 1 && instr.output == function {
                Assert(instr.op is BeginAnyFunction)
                break
            }

            c.append(instr)

            i += 1
        }

        Assert(i < code.count)

        let funcDefinition = code[i]
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

        Assert(i < code.count)

        // Search for the call of the function
        while i < code.count {
            let instr = code[i]

            if instr.op is CallFunction && instr.input(0) == function {
                break
            }

            Assert(!instr.inputs.contains(function))

            c.append(instr)
            i += 1
        }

        // Found it. Inline the function now
        let call = code[i]

        // Reuse the function variable to store 'undefined' and use that as
        // initial value of the return variable and for missing arguments.
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

        let rval = call.output
        c.append(Instruction(LoadUndefined(), output: rval, inputs: []))

        for instr in functionBody {
            let newInouts = instr.inouts.map { arguments[$0] ?? $0 }
            let newInstr = Instruction(instr.op, inouts: newInouts)

            // Return is converted to an assignment to the return value
            if instr.op is Return {
                c.append(Instruction(Reassign(), inputs: [rval, newInstr.input(0)]))
            } else {
                c.append(newInstr)
            }
        }

        i += 1

        // Copy remaining instructions
        while i < code.count {
            Assert(!code[i].inputs.contains(function))
            c.append(code[i])
            i += 1
        }

        return c
    }
}
