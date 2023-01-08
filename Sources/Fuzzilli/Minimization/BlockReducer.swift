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

/// Reducer to remove unecessary block groups.
struct BlockReducer: Reducer {
    func reduce(_ code: inout Code, with helper: MinimizationHelper) {
        for group in Blocks.findAllBlockGroups(in: code) {
            switch group.begin.op.opcode {
            case .beginObjectLiteral:
                assert(group.numBlocks == 1)
                reduceObjectLiteral(group.block(0), in: &code, with: helper)

            case .beginObjectLiteralMethod,
                 .beginObjectLiteralGetter,
                 .beginObjectLiteralSetter:
                assert(group.numBlocks == 1)
                reduceFunctionInObjectLiteral(group.block(0), in: &code, with: helper)

            case .beginWhileLoop,
                 .beginDoWhileLoop,
                 .beginForLoop,
                 .beginForInLoop,
                 .beginForOfLoop,
                 .beginForOfWithDestructLoop,
                 .beginRepeatLoop:
                assert(group.numBlocks == 1)
                reduceLoop(loop: group.block(0), in: &code, with: helper)

            case .beginIf:
                reduceIfElse(group, in: &code, with: helper)

            case .beginTry:
                reduceTryCatchFinally(tryCatch: group, in: &code, with: helper)

            case .beginSwitch:
                reduceBeginSwitch(group, in: &code, with: helper)

            case .beginSwitchCase,
                 .beginSwitchDefaultCase:
                 // These instructions are handled in reduceBeginSwitch.
                 break

            case .beginWith:
                reduceGenericBlockGroup(group, in: &code, with: helper)

            case .beginPlainFunction,
                 .beginArrowFunction,
                 .beginGeneratorFunction,
                 .beginAsyncFunction,
                 .beginAsyncArrowFunction,
                 .beginAsyncGeneratorFunction,
                 .beginConstructor:
                reduceFunctionOrConstructor(group, in: &code, with: helper)

            case .beginCodeString:
                reduceCodeString(group, in: &code, with: helper)

            case .beginBlockStatement:
                reduceGenericBlockGroup(group, in: &code, with: helper)

            case .beginClass:
                // TODO we need a custom reduceClass here that will also attempt to replace the class output variable
                // with some other callable thing (or just an empty class) to remove patterns such as
                //
                //     v0 <- BeginClass
                //        someImportantCode
                //        ...
                //     EndClass
                //     v42 <- Construct v0
                reduceGenericBlockGroup(group, in: &code, with: helper)

            default:
                fatalError("Unknown block group: \(group.begin.op.name)")
            }
        }
    }

    private func reduceObjectLiteral(_ literal: Block, in code: inout Code, with helper: MinimizationHelper) {
        // The instructions in the body of the object literal aren't valid outside of
        // object literals, so either remove the entire literal or nothing.
        helper.tryNopping(literal.instructionIndices, in: &code)
    }

    private func reduceFunctionInObjectLiteral(_ function: Block, in code: inout Code, with helper: MinimizationHelper) {
        // The instruction in the body of these functions aren't valid inside the object literal as
        // they require .javascript context. So either remove the entire function or nothing.
        helper.tryNopping(function.instructionIndices, in: &code)
    }

    private func reduceLoop(loop: Block, in code: inout Code, with helper: MinimizationHelper) {
        assert(loop.begin.isLoop)
        assert(loop.end.isLoop)

        // We reduce loops by removing the loop itself as well as
        // any 'break' or 'continue' instructions in the loop body.
        var candidates = [Int]()
        candidates.append(loop.head)
        candidates.append(loop.tail)

        // Scan the body for break or continue instructions and remove those as well
        var analyzer = ContextAnalyzer()
        for instr in loop.body {
            analyzer.analyze(instr)
            if !analyzer.context.contains(.loop) && instr.op.requiredContext.contains(.loop) {
                candidates.append(instr.index)
            }
        }

        helper.tryNopping(candidates, in: &code)
    }

    private func reduceIfElse(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(group.begin.op is BeginIf)
        assert(group.end.op is EndIf)

        // First try to remove the entire if-else block but keep its content.
        if helper.tryNopping(group.blockInstructionIndices, in: &code) {
            return
        }

        // Now try to turn if-else into just if.
        if group.numBlocks == 2 {
            // First try to remove the else block.
            let elseBlock = group.block(1)
            let rangeToNop = Array(elseBlock.head ..< elseBlock.tail)
            if helper.tryNopping(rangeToNop, in: &code) {
                return
            }

            // Then try to remove the if block. This requires inverting the condition of the if.
            let ifBlock = group.block(0)
            let beginIf = ifBlock.begin.op as! BeginIf
            let invertedIf = BeginIf(inverted: !beginIf.inverted)
            var replacements = [(Int, Instruction)]()
            replacements.append((ifBlock.head, Instruction(invertedIf, inputs: Array(ifBlock.begin.inputs))))
            // The rest of the if body is nopped ...
            for instr in ifBlock.body {
                replacements.append((instr.index, helper.nop(for: instr)))
            }
            // ... as well as the BeginElse.
            replacements.append((elseBlock.head, Instruction(Nop())))
            helper.tryReplacements(replacements, in: &code)
        }
    }

    private func reduceGenericBlockGroup(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        var candidates = group.blockInstructionIndices
        if helper.tryNopping(candidates, in: &code) {
            // Success!
            return
        }

        // Also try removing the entire block group, including its content.
        // This is sometimes necessary. Consider the following FuzzIL code:
        //
        //  v6 <- BeginCodeString
        //      v7 <- LoadProperty v6, '__proto__'
        //  EndCodeString v7
        //
        // Or, lifted to JavaScript:
        //
        //   const v6 = `
        //       const v7 = v6.__proto__;
        //       v7;
        //   `;
        //
        // Here, neither the single instruction inside the block, nor the two block instruction
        // can be removed independently, since they have data dependencies on each other. As such,
        // the only option is to remove the entire block, including its content.
        candidates = group.instructionIndices
        helper.tryNopping(candidates, in: &code)
    }

    // Try to reduce a BeginSwitch/EndSwitch Block.
    // (1) reduce it by aggressively trying to remove the whole thing.
    // (2) reduce it by removing the BeginSwitch(Default)Case/EndSwitchCase instructions but keeping the content.
    // (3) reduce it by removing individual BeginSwitchCase/EndSwitchCase blocks.
    private func reduceBeginSwitch(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(group.begin.op is BeginSwitch)

        var candidates = group.instructionIndices

        if helper.tryNopping(candidates, in: &code) {
            // (1)
            // We successfully removed the whole switch statement.
            return
        }

        // Add the head and tail of the block. These are the
        // BeginSwitch/EndSwitch instructions.
        candidates = [group.head, group.tail]

        var blocks: [Block] = []

        // Start iterating over the switch case statements.
        var instructionIdx = group.head+1
        while instructionIdx < group.tail {
            if code[instructionIdx].op is BeginSwitchCase || code[instructionIdx].op is BeginSwitchDefaultCase {
                let block = Block(startedBy: code[instructionIdx], in: code)
                blocks.append(block)
                candidates.append(block.head)
                candidates.append(block.tail)
                // Set the idx to the corresponding EndSwitchCase instruction.
                instructionIdx = block.tail
            }
            instructionIdx += 1
        }

        if helper.tryNopping(candidates, in: &code) {
            // (2)
            // We successfully removed the switch case while keeping the
            // content inside.
            return
        }

        for block in blocks {
            // We do not want to remove BeginSwitchDefaultCase blocks, as we
            // currently do not have a way of generating them.
            if block.begin.op is BeginSwitchDefaultCase { continue }
            // (3) Try to remove the cases here.
            helper.tryNopping(block.instructionIndices, in: &code)
        }
    }

    private func reduceFunctionOrConstructor(_ function: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(function.begin.op is BeginAnySubroutine)
        assert(function.end.op is EndAnySubroutine)

        // Only attempt generic block group reduction and rely on the InliningReducer to handle more complex scenarios.
        // Alternatively, we could also attempt to turn
        //
        //     v0 <- BeginPlainFunction
        //         someImportantCode
        //     EndPlainFunction
        //
        // Into
        //
        //     v0 <- BeginPlainFunction
        //     EndPlainFunction
        //     someImportantCode
        //
        // So that the calls to the function can be removed by a subsequent reducer if only the body is important.
        // But its likely not worth the effort as the InliningReducer will do a better job at solving this.
        reduceGenericBlockGroup(function, in: &code, with: helper)
    }

    private func reduceCodeString(_ codestring: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(codestring.begin.op is BeginCodeString)
        assert(codestring.end.op is EndCodeString)

        // To remove CodeStrings, we replace the BeginCodeString with a LoadString operation and the EndCodeString with a Nop.
        // This way, the code inside the CodeString will execute directly and any following `eval()` call on that CodeString
        // will effectively become a Nop (and will hopefully be removed afterwards).
        // This avoids the need to find the `eval` call that use the CodeString.
        var replacements = [(Int, Instruction)]()
        replacements.append((codestring.head, Instruction(LoadString(value: ""), output: codestring.begin.output)))
        replacements.append((codestring.tail, Instruction(Nop())))
        if helper.tryReplacements(replacements, in: &code) {
            // Success!
            return
        }

        // If unsuccessful, default to generic block reduction
        reduceGenericBlockGroup(codestring, in: &code, with: helper)
    }

    private func reduceTryCatchFinally(tryCatch: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(tryCatch.begin.op is BeginTry)
        assert(tryCatch.end.op is EndTryCatchFinally)

        // First we try to remove only the try-catch-finally block instructions.
        var candidates = tryCatch.blockInstructionIndices

        if helper.tryNopping(candidates, in: &code) {
            return
        }

        let tryBlock = tryCatch.block(0)
        assert(tryBlock.begin.op is BeginTry)

        // If that doesn't work, then we try to remove the block instructions
        // and the last instruction of the try block but keep everything else.
        // If instructions in the bodies aren't required, they will be removed
        // by the other reducers. On the other hand, this successfully minimizes
        // something like:
        //
        //     try {
        //         do_something_important1();
        //         throw 42;
        //         // dead code, so should've been removed already
        //     } catch {
        //         do_something_important2();
        //     } finally {
        //         do_something_important3();
        //     }
        //
        // to
        //
        //     do_something_important1();
        //     do_something_important2();
        //     do_something_important3();
        //
        var removedLastTryBlockInstruction = false
        // Find the last instruction in try block and try removing that as well.
        for i in stride(from: tryBlock.tail - 1, to: tryBlock.head, by: -1) {
            if !(code[i].op is Nop) {
                if !code[i].isBlock {
                    candidates.append(i)
                    removedLastTryBlockInstruction = true
                }
                break
            }
        }

        if removedLastTryBlockInstruction && helper.tryNopping(candidates, in: &code) {
            return
        }

        // If that still didn't work, try removing the entire try-block.
        // Consider the following example why that might be required:
        //
        //     try {
        //         for (let v16 = 0; v16 < 27; v16 = v16 + -2473693327) {
        //             const v17 = Math(v16,v16); // Raises an exception
        //         }
        //     } catch {
        //         do_something_important();
        //     } finally {
        //     }
        //
        if removedLastTryBlockInstruction {
            candidates.removeLast()
        }

        // Remove all instructions in the body of the try block
        for i in stride(from: tryBlock.tail - 1, to: tryBlock.head, by: -1) {
            if !(code[i].op is Nop) {
                candidates.append(i)
            }
        }

        helper.tryNopping(candidates, in: &code)

        // Finally, fall back to generic block group reduction, which will attempt to remove the
        // entire try-catch block including its content
        reduceGenericBlockGroup(tryCatch, in: &code, with: helper)
    }
}
