// Copyright 2022 Google LLC
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

/// PostProcessing after minimization. This tries to _add_ features back to the minimized program that are typically helpful for future mutations.
///
/// In particular, it does the following:
///  - Insert return statements at the end of every plain function with a random value
///  - Add a random number of arguments for function/method/constructor calls that have no arguments
///  - Add random initial values to array literatls if they don't have any
///
/// Like other reducers, changes are only performed if they do not alter the programs relevant behaviour.
struct MinimizationPostProcessor {
    @discardableResult
    func process(with helper: MinimizationHelper) -> Bool {
        // Step 1: Generate all changes that we'd like to perform and record them.
        var changes = [(index: Int, newInstruction: Instruction)]()
        var codeWithNops = Code()

        // This must happen on the fuzzer's queue as it requires a ProgramBuilder to obtain input variables.
        helper.performOnFuzzerQueue {
            // For every insertion, we also insert a placeholder Nop into the current code. This way, performing the insertions in step 2 becomes very cheap.
            let b = helper.fuzzer.makeBuilder()
            var lastInstr = Instruction(Nop())

            for instr in helper.code {
                var addedInstruction: Instruction? = nil
                var replacementInstruction: Instruction? = nil
                switch instr.op.opcode {
                case .endPlainFunction,
                     .endArrowFunction,
                     .endGeneratorFunction,
                     .endAsyncFunction,
                     .endAsyncArrowFunction,
                     .endAsyncGeneratorFunction,
                     .endObjectLiteralMethod,
                     .endObjectLiteralGetter:
                    // Insert return statements at the end of functions, but only if there is not one already.
                    if lastInstr.op is Return || !b.hasVisibleVariables { break }
                    addedInstruction = Instruction(Return(hasReturnValue: true), inputs: [b.randomVariable()])
                case .callFunction(let op):
                    // (Sometimes) insert random arguments, but only if there are none currently.
                    if instr.hasAnyVariadicInputs || !b.hasVisibleVariables || probability(0.5) { break }
                    let args = b.randomArguments(forCalling: instr.input(0))
                    guard args.count > 0 else { break }
                    replacementInstruction = Instruction(CallFunction(numArguments: args.count, isGuarded: op.isGuarded), output: instr.output, inputs: [instr.input(0)] + args)
                case .callMethod(let op):
                    // (Sometimes) insert random arguments, but only if there are none currently.
                    if instr.hasAnyVariadicInputs || !b.hasVisibleVariables || probability(0.5) { break }
                    let args = b.randomArguments(forCallingMethod: op.methodName, on: instr.input(0))
                    guard args.count > 0 else { break }
                    replacementInstruction = Instruction(CallMethod(methodName: op.methodName, numArguments: args.count, isGuarded: op.isGuarded), output: instr.output, inputs: [instr.input(0)] + args)
                case .construct(let op):
                    // (Sometimes) insert random arguments, but only if there are none currently.
                    if instr.hasAnyVariadicInputs || !b.hasVisibleVariables || probability(0.5) { break }
                    let args = b.randomArguments(forCalling: instr.input(0))
                    guard args.count > 0 else { break }
                    replacementInstruction = Instruction(Construct(numArguments: args.count, isGuarded: op.isGuarded), output: instr.output, inputs: [instr.input(0)] + args)
                case .createArray:
                    // Add initial values, but only if there are none currently.
                    if instr.hasAnyVariadicInputs || !b.hasVisibleVariables { break }
                    let initialValues = Array<Variable>(repeating: b.randomVariable(), count: Int.random(in: 1...5))
                    replacementInstruction = Instruction(CreateArray(numInitialValues: initialValues.count), output: instr.output, inputs: initialValues)
                default:
                    assert(!(instr.op is EndAnyFunction))
                    break
                }

                if let instr = addedInstruction {
                    changes.append((index: codeWithNops.count, newInstruction: instr))
                    codeWithNops.append(Instruction(Nop()))
                }
                if let instr = replacementInstruction {
                    changes.append((index: codeWithNops.count, newInstruction: instr))
                }

                b.append(instr)
                codeWithNops.append(instr)
                lastInstr = instr
            }
            assert(codeWithNops.count >= helper.code.count)
        }

        if !helper.testAndCommit(codeWithNops) {
            return false
        }

        // Step 2: Try to apply each change from step 1 on its own and verify that the change doesn't alter the program's behaviour.
        for change in changes {
            // Either we're adding a new instruction (in which case we're replacing a nop inserted in step 1), or changing the number of inputs of an existing instruction.
            assert((helper.code[change.index].op is Nop && !(change.newInstruction.op is Nop)) ||
                   (helper.code[change.index].op.name == change.newInstruction.op.name && helper.code[change.index].numInputs < change.newInstruction.numInputs))
            helper.tryReplacing(instructionAt: change.index, with: change.newInstruction)
        }

        // Step 3: Remove any remaining nops from step 1.
        helper.removeNops()
        return true
    }
}
