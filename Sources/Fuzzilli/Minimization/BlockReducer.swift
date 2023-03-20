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
        /// Here we iterate over the blocks in the code while also changing the code (by removing blocks). This works
        /// since we are for the most part only nopping out block instructions, not moving them around. In the cases
        /// where code is moved, only code inside the processed block is moved, and the iteration order visits inner
        /// blocks before outer blocks.
        /// As such, the block indices stay valid across these code transformations.
        for group in code.findAllBlockGroups() {
            switch code[group.head].op.opcode {
            case .beginObjectLiteral:
                assert(group.numBlocks == 1)
                reduceObjectLiteral(group.block(0), in: &code, with: helper)

            case .beginObjectLiteralMethod,
                 .beginObjectLiteralComputedMethod,
                 .beginObjectLiteralGetter,
                 .beginObjectLiteralSetter:
                assert(group.numBlocks == 1)
                reduceFunctionInObjectLiteral(group.block(0), in: &code, with: helper)

            case .beginClassDefinition:
                reduceClassDefinition(group.block(0), in: &code, with: helper)

            case .beginClassConstructor,
                 .beginClassInstanceMethod,
                 .beginClassInstanceGetter,
                 .beginClassInstanceSetter,
                 .beginClassStaticInitializer,
                 .beginClassStaticMethod,
                 .beginClassStaticGetter,
                 .beginClassStaticSetter,
                 .beginClassPrivateInstanceMethod,
                 .beginClassPrivateStaticMethod:
                reduceFunctionInClassDefinition(group.block(0), in: &code, with: helper)

            case .beginWhileLoopHeader,
                 .beginDoWhileLoopBody,
                 .beginForLoopInitializer,
                 .beginForInLoop,
                 .beginForOfLoop,
                 .beginForOfLoopWithDestruct,
                 .beginRepeatLoop:
                reduceLoop(group, in: &code, with: helper)

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

            default:
                fatalError("Unknown block group: \(code[group.head].op.name)")
            }
        }
    }

    private func reduceObjectLiteral(_ literal: Block, in code: inout Code, with helper: MinimizationHelper) {
        // The instructions in the body of the object literal aren't valid outside of
        // object literals, so either remove the entire literal or nothing.
        helper.tryNopping(literal.allInstructions, in: &code)
    }

    private func reduceFunctionInObjectLiteral(_ function: Block, in code: inout Code, with helper: MinimizationHelper) {
        // The instruction in the body of these functions aren't valid inside the object literal as
        // they require .javascript context. So either remove the entire function or nothing.
        helper.tryNopping(function.allInstructions, in: &code)
    }

    private func reduceClassDefinition(_ definition: Block, in code: inout Code, with helper: MinimizationHelper) {
        assert(code[definition.head].op is BeginClassDefinition)
        assert(code[definition.tail].op is EndClassDefinition)

        // Similar to the object literal case, the instructions in the body aren't valid outside of it, so remove everything.
        if helper.tryNopping(definition.allInstructions, in: &code) {
            return
        }

        // If that doesn't work, we attempt to turn code such as
        //
        //     v0 <- BeginClassDefinition
        //         BeginClassConstructor
        //             ...
        //         EndClassConstructor
        //         BeginClassInstanceMethod 'm'
        //             <SomeImportantCode>
        //         EndClassInstanceMethod
        //        ...
        //     EndClassDefinition
        //     v42 <- Construct v0
        //     v43 <- CallMethod 'm'
        //
        // Into
        //
        //     v0 <- BeginClassDefinition
        //         BeginClassConstructor
        //         EndClassConstructor
        //         BeginClassInstanceMethod 'm'
        //         EndClassInstanceMethod
        //     EndClassDefinition
        //     <SomeImportantCode>
        //     v42 <- Construct v0
        //     v43 <- CallMethod 'm'
        //
        // For that, first collect all field definition instructions and all body instructions into two separate lists
        var fieldDefinitionInstructions = [code[definition.head]]
        var bodyInstruction = [Instruction]()
        // We have to be careful not to include field definitions of nested class definitions here, so go by the current depth to indentify the correct instructions.
        var depth = 0
        for instr in code.body(of: definition) {
            if instr.isBlockEnd {
                assert(depth > 0)
                depth -= 1
            }
            if depth == 0 {
                fieldDefinitionInstructions.append(instr)
            } else {
                bodyInstruction.append(instr)
            }
            if instr.isBlockStart {
                depth += 1
            }
        }
        fieldDefinitionInstructions.append(code[definition.tail])
        if bodyInstruction.isEmpty {
            // No need to attempt any reordering. This early bail-out is required to ensure minimization terminates.
            // Otherwise, this reordering would be retried every time, and count as a successful modification of the code.
            return
        }
        // Then build the replacement list to reorder these instructions as described above.
        var replacements = [(Int, Instruction)]()
        var index = definition.head
        for instr in fieldDefinitionInstructions + bodyInstruction {
            replacements.append((index, instr))
            index += 1
        }

        // Code reordering can change the numbering of variables, so they need to be renumbered.
        // The resulting code may also not be valid since we're moving code out of a method definition.
        helper.tryReplacements(replacements, in: &code, renumberVariables: true, expectCodeToBeValid: false)
    }

    private func reduceFunctionInClassDefinition(_ function: Block, in code: inout Code, with helper: MinimizationHelper) {
        // Similar to the object literal case, the instructions inside the function body aren't valid inside
        // the surrounding class definition, so we can only try to temove the entire function.
        helper.tryNopping(function.allInstructions, in: &code)
    }

    private func reduceLoop(_ loop: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        // We reduce loops by removing the loop itself as well as
        // any 'break' or 'continue' instructions in the loop body.
        var candidates = loop.blockInstructionIndices
        var inNestedLoop = false
        var nestedBlocks = Stack<Bool>()
        for block in loop.blocks {
            for instr in code.body(of: block) {
                if instr.isBlockEnd {
                   inNestedLoop = nestedBlocks.pop()
                }
                if instr.isBlockStart {
                    let isLoop = instr.op.contextOpened.contains(.loop)
                    nestedBlocks.push(inNestedLoop)
                    inNestedLoop = inNestedLoop || isLoop
                }

                if !inNestedLoop && instr.op.requiredContext.contains(.loop) {
                    candidates.append(instr.index)
                }
            }
            assert(nestedBlocks.isEmpty)
        }

        helper.tryNopping(candidates, in: &code)
    }

    private func reduceIfElse(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(code[group.head].op is BeginIf)
        assert(code[group.tail].op is EndIf)

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
            let beginIf = code[ifBlock.head].op as! BeginIf
            let invertedIf = BeginIf(inverted: !beginIf.inverted)
            var replacements = [(Int, Instruction)]()
            replacements.append((ifBlock.head, Instruction(invertedIf, inouts: code[ifBlock.head].inouts)))
            // The rest of the if body is nopped ...
            for instr in code.body(of: ifBlock) {
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
        //      v7 <- GetProperty v6, '__proto__'
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
        assert(code[group.head].op is BeginSwitch)

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
                let block = code.block(startingAt: instructionIdx)
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
            if code[block.head].op is BeginSwitchDefaultCase { continue }
            // (3) Try to remove the cases here.
            helper.tryNopping(block.allInstructions, in: &code)
        }
    }

    private func reduceFunctionOrConstructor(_ function: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(code[function.head].op is BeginAnySubroutine)
        assert(code[function.tail].op is EndAnySubroutine)

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
        assert(code[codestring.head].op is BeginCodeString)
        assert(code[codestring.tail].op is EndCodeString)

        // To remove CodeStrings, we replace the BeginCodeString with a LoadString operation and the EndCodeString with a Nop.
        // This way, the code inside the CodeString will execute directly and any following `eval()` call on that CodeString
        // will effectively become a Nop (and will hopefully be removed afterwards).
        // This avoids the need to find the `eval` call that use the CodeString.
        var replacements = [(Int, Instruction)]()
        replacements.append((codestring.head, Instruction(LoadString(value: ""), output: code[codestring.head].output)))
        replacements.append((codestring.tail, Instruction(Nop())))
        if helper.tryReplacements(replacements, in: &code) {
            // Success!
            return
        }

        // If unsuccessful, default to generic block reduction
        reduceGenericBlockGroup(codestring, in: &code, with: helper)
    }

    private func reduceTryCatchFinally(tryCatch: BlockGroup, in code: inout Code, with helper: MinimizationHelper) {
        assert(code[tryCatch.head].op is BeginTry)
        assert(code[tryCatch.tail].op is EndTryCatchFinally)

        // First we try to remove only the try-catch-finally block instructions.
        var candidates = tryCatch.blockInstructionIndices

        if helper.tryNopping(candidates, in: &code) {
            return
        }

        let tryBlock = tryCatch.block(0)
        assert(code[tryBlock.head].op is BeginTry)

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
