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
    func reduce(_ program: Program, with verifier: ReductionVerifier) -> Program {
        for group in program.blockGroups() {
            switch group.begin.operation {
            case is BeginWhile,
                 is BeginDoWhile,
                 is BeginFor,
                 is BeginForIn,
                 is BeginForOf:
                assert(group.numBlocks == 1)
                reduceLoop(loop: group.block(0), in: program, with: verifier)
                
            case is BeginTry:
                reduceTryCatch(tryCatch: group, in: program, with: verifier)
                
            case is BeginIf:
                // We reduce ifs simply by removing the whole block group.
                // This works OK since minimization is a fixpoint iteration,
                // so if only one branch is required, the other one will
                // eventually be empty.
                reduceGenericBlockGroup(group, in: program, with: verifier)
                
            case is BeginWith:
                reduceGenericBlockGroup(group, in: program, with: verifier)
                
            case is BeginAnyFunctionDefinition:
                // Only remove empty functions here.
                // Function inlining is done by a dedicated reducer.
                reduceGenericBlockGroup(group, in: program, with: verifier)
                break

            case is BeginTemplateLiteral:
                reduceGenericBlockGroup(group, in: program, with: verifier)

            default:
                fatalError("Unknown block group: \(group.begin.operation.name)")
            }
        }
        
        return program
    }
    
    private func reduceLoop(loop: Block, in program: Program, with verifier: ReductionVerifier) {
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
            if !analyzer.context.contains(.loop) && (instr.operation is Break || instr.operation is Continue) {
                candidates.append(instr.index)
            }
        }
        
        verifier.tryNopping(candidates, in: program)
    }
    
    private func reduceGenericBlockGroup(_ group: BlockGroup, in program: Program, with verifier: ReductionVerifier) {
        var candidates = [Int]()
        
        for instr in group.excludingContent() {
            candidates.append(instr.index)
        }
        
        verifier.tryNopping(candidates, in: program)
    }
    
    private func reduceTryCatch(tryCatch: BlockGroup, in program: Program, with verifier: ReductionVerifier) {
        // We first try to remove only the try-catch block instructions.
        // If that doesn't work, then we try to remove the try block including
        // its last instruction but keepp the body of the catch block.
        // If the body isn't required, it will be removed by the
        // other reducers. On the other hand, this successfully
        // reduces code like
        //
        //     try {
        //         do_something_important1();
        //         throw 42;
        //     } catch {
        //         do_something_important2();
        //     }
        //
        // to
        //
        //     do_something_important1();
        //     do_something_important2();
        //
        
        var candidates = [Int]()
        
        candidates.append(tryCatch[0].index)
        candidates.append(tryCatch[1].index)
        candidates.append(tryCatch[2].index)
        
        if verifier.tryNopping(candidates, in: program) {
            return
        }

        // Find the last instruction in try block and try removing that as well.
        for i in stride(from: tryCatch[1].index - 1, to: tryCatch[0].index, by: -1) {
            if !(program[i].operation is Nop) {
                if !program[i].isBlock {
                    candidates.append(i)
                }
                break
            }
        }
        
        if candidates.count == 4 && verifier.tryNopping(candidates, in: program) {
            return
        }

        // If that still didn't work, try removing the entire try-block.
        // Consider the following example why that might be required:
        //
        //     try {
        //         for (let v16 = 0; v16 < 27; v16 = v16 + -2473693327) {
        //             const v17 = Math(v16,v16);
        //         }
        //      } catch {
        //      }
        //
        if candidates.count == 4 {
            candidates.removeLast()
        }
        
        // Find last instruction in try block
        for i in stride(from: tryCatch[1].index - 1, to: tryCatch[0].index, by: -1) {
            if !(tryCatch.program[i].operation is Nop) {
                candidates.append(i)
            }
        }
        
        verifier.tryNopping(candidates, in: program)
    }
}
