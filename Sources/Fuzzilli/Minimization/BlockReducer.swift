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
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        for group in Blocks.findAllBlockGroups(in: code) {
            switch group.begin.op {
            case is BeginWhileLoop,
                 is BeginDoWhileLoop,
                 is BeginForLoop,
                 is BeginForInLoop,
                 is BeginForOfLoop,
                 is BeginForOfWithDestructLoop:
                Assert(group.numBlocks == 1)
                reduceLoop(loop: group.block(0), in: &code, with: verifier)

            case is BeginTry:
                reduceTryCatchFinally(tryCatch: group, in: &code, with: verifier)

            case is BeginIf:
                // We reduce ifs simply by removing the whole block group.
                // This works OK since minimization is a fixpoint iteration,
                // so if only one branch is required, the other one will
                // eventually be empty.
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            case is BeginSwitch:
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            case is BeginWith:
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            case is BeginAnyFunction:
                // Only remove empty functions here.
                // Function inlining is done by a dedicated reducer.
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            case is BeginCodeString:
                reduceCodeString(codestring: group, in: &code, with: verifier)

            case is BeginBlockStatement:
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            case is BeginClass:
                reduceGenericBlockGroup(group, in: &code, with: verifier)

            default:
                fatalError("Unknown block group: \(group.begin.op.name)")
            }
        }
    }

    private func reduceLoop(loop: Block, in code: inout Code, with verifier: ReductionVerifier) {
        Assert(loop.begin.isLoop)
        Assert(loop.end.isLoop)

        // We reduce loops by removing the loop itself as well as
        // any 'break' or 'continue' instructions in the loop body.
        var candidates = [Int]()
        candidates.append(loop.head)
        candidates.append(loop.tail)

        // Scan the body for break or continue instructions and remove those as well
        var analyzer = ContextAnalyzer()
        for instr in loop.body() {
            analyzer.analyze(instr)
            // TODO instead have something like '&& instr.onlyValidInLoopBody`
            if !analyzer.context.contains(.loop) && (instr.op is LoopBreak || instr.op is LoopContinue) {
                candidates.append(instr.index)
            }
        }

        verifier.tryNopping(candidates, in: &code)
    }

    private func reduceGenericBlockGroup(_ group: BlockGroup, in code: inout Code, with verifier: ReductionVerifier) {
        var candidates = group.excludingContent().map({ $0.index })
        if verifier.tryNopping(candidates, in: &code) {
            // Success!
            return
        }

        // As a last resort, try removing the entire block group, including its content.
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
        candidates = group.includingContent().map({ $0.index })
        verifier.tryNopping(candidates, in: &code)
    }

    private func reduceCodeString(codestring: BlockGroup, in code: inout Code, with verifier: ReductionVerifier) {
        Assert(codestring.begin.op is BeginCodeString)
        Assert(codestring.end.op is EndCodeString)

        // To remove CodeStrings, we replace the BeginCodeString with a LoadString operation and the EndCodeString with a Nop.
        // This way, the code inside the CodeString will execute directly and any following `eval()` call on that CodeString
        // will effectively become a Nop (and will hopefully be removed afterwards).
        // This avoids the need to find the `eval` call that use the CodeString.
        var replacements = [(Int, Instruction)]()
        replacements.append((codestring.head, Instruction(LoadString(value: ""), output: codestring.begin.output)))
        replacements.append((codestring.tail, Instruction(Nop())))
        if verifier.tryReplacements(replacements, in: &code) {
            // Success!
            return
        }

        // If unsuccessful, default to generic block reduction
        reduceGenericBlockGroup(codestring, in: &code, with: verifier)
    }

    private func reduceTryCatchFinally(tryCatch: BlockGroup, in code: inout Code, with verifier: ReductionVerifier) {
        Assert(tryCatch.begin.op is BeginTry)
        Assert(tryCatch.end.op is EndTryCatchFinally)

        var candidates = [Int]()

        // First we try to remove only the try-catch-finally block instructions.
        for i in 0...tryCatch.numBlocks {
            candidates.append(tryCatch[i].index)
        }

        if verifier.tryNopping(candidates, in: &code) {
            return
        }

        // If that doesn't work, then we try to remove the try block including
        // its last instruction but keep the body of the catch and/or finally block.
        // If the body isn't required, it will be removed by the
        // other reducers. On the other hand, this successfully
        // reduces code like
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
        for i in stride(from: tryCatch[1].index - 1, to: tryCatch[0].index, by: -1) {
            if !(code[i].op is Nop) {
                if !code[i].isBlock {
                    candidates.append(i)
                    removedLastTryBlockInstruction = true
                }
                break
            }
        }

        if removedLastTryBlockInstruction && verifier.tryNopping(candidates, in: &code) {
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
        for i in stride(from: tryCatch[1].index - 1, to: tryCatch[0].index, by: -1) {
            if !(code[i].op is Nop) {
                candidates.append(i)
            }
        }

        verifier.tryNopping(candidates, in: &code)

        // Finally, fall back to generic block group reduction, which will attempt to remove the
        // entire try-catch block including its content
        reduceGenericBlockGroup(tryCatch, in: &code, with: verifier)
    }
}
