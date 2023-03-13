// Copyright 2023 Google LLC
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

/// This reducer attempts to simplify and speed-up loops:
///  - Complex loops are replaced with simple repeat-loops
///  - Nested loops are replaced with a single loop
///  - Loops with many iterations are replaced with loops with fewer iterations
///
/// This reducer should be scheduled after the BlockReducer which attempts to delete loop entirely (instead of simplifying them).
struct LoopReducer: Reducer {
    // The loop iterations counts that we'll try out when attempting to reduce the number of iterations of a loop.
    private let commonLoopIterationCounts = [5, 10, 25, 50, 100, 250, 500, 1000]

    // When reducing loop interation counts, we want to make sure that the sample still behaves deterministically
    // (if e.g. the loop is necessary to trigger JIT compilation) and so we test each reduction multiple times.
    private let numTestExecutions = 3

    func reduce(_ code: inout Code, with helper: MinimizationHelper) {
        var changed = false
        repeat {
            changed = false
            for group in Blocks.findAllBlockGroups(in: code) {
                switch group.begin.op.opcode {
                case .beginForLoopInitializer:
                    if tryReplaceForLoopWithRepeatLoop(group, in: &code, with: helper) { changed = true }
                case .beginWhileLoopHeader:
                    if tryReplaceWhileLoopWithRepeatLoop(group, in: &code, with: helper) { changed = true }
                case .beginDoWhileLoopBody:
                    if tryReplaceDoWhileLoopWithRepeatLoop(group, in: &code, with: helper) { changed = true }
                case .beginRepeatLoop:
                    if tryReduceRepeatLoopIterationCount(group, in: &code, with: helper) { changed = true }
                case .beginForInLoop,
                        .beginForOfLoop,
                        .beginForOfLoopWithDestruct:
                    // These loops are (usually) guaranteed to terminate, and should probably anyway not be replaced by repeat-loops.
                    break
                default:
                    assert(group.blocks.allSatisfy({ !$0.begin.op.contextOpened.contains(.loop) }))
                }
                if changed { break }
            }
        } while changed

        // Try merging nested loops now, after potentially converting other loop types to simple repeat loops.
        findAndMergeNestedRepeatLoops(in: &code, with: helper)
    }

    private func tryReplaceForLoopWithRepeatLoop(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) -> Bool {
        // Turn
        //
        //      BeginForLoopInitializer
        //          init()
        //      BeginForLoopCondition v4, v6 -> v7, v8
        //          condition()
        //      BeginForLoopAfterthought -> v10, v11
        //          afterthought()
        //      BeginForLoopBody -> v14, v15
        //          body()
        //      EndForLoop
        //
        // Into
        //
        //      init()
        //      BeginRepeatLoop 'n' -> v7
        //          // All inner outputs (v7, v8, v10, v11, v14, and 15) are replaced with v7
        //          condition()
        //          body()
        //          afterthought()
        //      EndRepeatLoop
        //
        var newCode = [Instruction]()

        // Append initializer code
        assert(group.block(0).begin.op is BeginForLoopInitializer)
        for instr in group.block(0).body {
            newCode.append(instr)
        }

        // Append loop header
        let conditionBlock = group.block(1)
        assert(conditionBlock.begin.op is BeginForLoopCondition)
        let headerIndex = newCode.count
        let needLoopVariable = conditionBlock.begin.numInnerOutputs > 0
        let loopVar = needLoopVariable ? conditionBlock.begin.innerOutput(0) : nil
        newCode.append(Instruction(BeginRepeatLoop(iterations: 1, exposesLoopCounter: needLoopVariable), inouts: needLoopVariable ? [loopVar!] : []))

        // Append condition, body, and afterthought code
        var replacements = Dictionary<Variable, Variable>(uniqueKeysWithValues: conditionBlock.begin.innerOutputs.map({ ($0, loopVar!) }))
        for instr in conditionBlock.body {
            let newInouts = instr.inouts.map({ replacements[$0] ?? $0 })
            newCode.append(Instruction(instr.op, inouts: newInouts))
        }

        let bodyBlock = group.block(3)
        assert(bodyBlock.begin.op is BeginForLoopBody)
        replacements = Dictionary<Variable, Variable>(uniqueKeysWithValues: bodyBlock.begin.innerOutputs.map({ ($0, loopVar!) }))
        for instr in bodyBlock.body {
            let newInouts = instr.inouts.map({ replacements[$0] ?? $0 })
            newCode.append(Instruction(instr.op, inouts: newInouts))
        }

        let afterthoughtBlock = group.block(2)
        assert(afterthoughtBlock.begin.op is BeginForLoopAfterthought)
        replacements = Dictionary<Variable, Variable>(uniqueKeysWithValues: afterthoughtBlock.begin.innerOutputs.map({ ($0, loopVar!) }))
        for instr in afterthoughtBlock.body {
            let newInouts = instr.inouts.map({ replacements[$0] ?? $0 })
            newCode.append(Instruction(instr.op, inouts: newInouts))
        }

        // Append loop footer
        newCode.append(Instruction(EndRepeatLoop()))

        return tryReplacingWithShortestPossibleRepeatLoop(range: group.head...group.tail, in: &code, with: &newCode, loopHeaderIndexInNewCode: headerIndex, using: helper)
    }

    private func tryReplaceWhileLoopWithRepeatLoop(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) -> Bool {
        // Turn
        //
        //      BeginWhileLoopHeader
        //          header()
        //      BeginWhileLoopBody v3
        //          body()
        //      EndWhileLoop
        //
        // Into
        //
        //      BeginRepeatLoop 'n'
        //          header()
        //          body()
        //      EndRepeatLoop
        //
        var newCode = [Instruction]()

        // Append loop header
        newCode.append(Instruction(BeginRepeatLoop(iterations: 1, exposesLoopCounter: false)))

        // Append loop header and body code
        let headerBlock = group.block(0)
        assert(headerBlock.begin.op is BeginWhileLoopHeader)
        for instr in headerBlock.body {
            newCode.append(instr)
        }

        let bodyBlock = group.block(1)
        assert(bodyBlock.begin.op is BeginWhileLoopBody)
        for instr in bodyBlock.body {
            newCode.append(instr)
        }

        // Append loop footer
        newCode.append(Instruction(EndRepeatLoop()))

        return tryReplacingWithShortestPossibleRepeatLoop(range: group.head...group.tail, in: &code, with: &newCode, loopHeaderIndexInNewCode: 0, using: helper)
    }

    private func tryReplaceDoWhileLoopWithRepeatLoop(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) -> Bool {
        // Turn
        //
        //      BeginDoWhileLoopBody
        //          body()
        //      BeginDoWhileLoopHeader
        //          header()
        //      EndDoWhileLoop v7
        //
        // Into
        //
        //      BeginRepeatLoop 'n'
        //          body()
        //          header()
        //      EndRepeatLoop
        //
        var newCode = [Instruction]()

        // Append loop header
        newCode.append(Instruction(BeginRepeatLoop(iterations: 1, exposesLoopCounter: false)))

        // Append loop body and header code
        let bodyBlock = group.block(0)
        assert(bodyBlock.begin.op is BeginDoWhileLoopBody)
        for instr in bodyBlock.body {
            newCode.append(instr)
        }

        let headerBlock = group.block(1)
        assert(headerBlock.begin.op is BeginDoWhileLoopHeader)
        for instr in headerBlock.body {
            newCode.append(instr)
        }

        // Append loop footer
        newCode.append(Instruction(EndRepeatLoop()))

        return tryReplacingWithShortestPossibleRepeatLoop(range: group.head...group.tail, in: &code, with: &newCode, loopHeaderIndexInNewCode: 0, using: helper)
    }

    private func tryReduceRepeatLoopIterationCount(_ group: BlockGroup, in code: inout Code, with helper: MinimizationHelper) -> Bool {
        let originalLoopHeader = group.begin.op as! BeginRepeatLoop
        guard originalLoopHeader.iterations > commonLoopIterationCounts[0] else {
            // Loop already has the minimum number of iterations.
            return false
        }
        for numIterations in commonLoopIterationCounts {
            guard numIterations < originalLoopHeader.iterations else {
                // We should never increase the number of iterations
                return false
            }
            let replacement: Instruction
            if originalLoopHeader.exposesLoopCounter {
                replacement = Instruction(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: true), inouts: group.begin.inouts)
            } else {
                replacement = Instruction(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: false))
            }
            if helper.tryReplacing(instructionAt: group.head, with: replacement, in: &code, numExecutions: numTestExecutions) {
                return true
            }
        }
        return false
    }

    private func tryReplacingWithShortestPossibleRepeatLoop(range: ClosedRange<Int>, in code: inout Code, with newCode: inout [Instruction], loopHeaderIndexInNewCode headerIndex: Int, using helper: MinimizationHelper) -> Bool {
        assert(newCode[headerIndex].op is BeginRepeatLoop)
        for numIterations in commonLoopIterationCounts {
            if newCode[headerIndex].numInnerOutputs > 0 {
                newCode[headerIndex] = Instruction(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: true), inouts: newCode[headerIndex].inouts)
            } else {
                newCode[headerIndex] = Instruction(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: false))
            }
            // After this change, the variable numbers may no longer be sequential as we may have removed instructions with inner outputs. So we need to also renumber the variables.
            if helper.tryReplacing(range: range, in: &code, with: newCode, renumberVariables: true, numExecutions: numTestExecutions) {
                return true
            }
        }
        return false
    }

    private func findAndMergeNestedRepeatLoops(in code: inout Code, with helper: MinimizationHelper) {
        // We consider a loop a nested loop if it is directly inside another loop, with only nops in between.
        // For example:
        //
        //      loop1 {
        //          foo();
        //          loop2 {
        //              bar();
        //          }
        //      }
        //
        // Would not be considered a nested loop, but
        //
        //      loop1 {
        //          nop;
        //          loop2 {
        //              foo();
        //          }
        //          nop;
        //          nop;
        //      }
        //
        // Would.
        var loops = [Block]()
        for group in Blocks.findAllBlockGroups(in: code) where group.begin.op is BeginRepeatLoop {
            assert(group.numBlocks == 1)
            loops.append(group.block(0))
        }
        loops.sort(by: { $0.head < $1.head })
        var nestedLoops = [(outerHead: Int, innerHead: Int, innerTail: Int, outerTail: Int)]()
        for (i, outerLoop) in loops.dropLast().enumerated() {
            let innerLoop = loops[i + 1]
            let instructionsBeforeInnerLoop = code[code.index(after: outerLoop.head)..<innerLoop.head]
            guard !instructionsBeforeInnerLoop.contains(where: { !($0.op is Nop) }) else { break }
            let instructionsAfterInnerLoop = code[code.index(after: innerLoop.tail)..<outerLoop.tail]
            guard !instructionsAfterInnerLoop.contains(where: { !($0.op is Nop) }) else { break }
            nestedLoops.append((outerLoop.head, innerLoop.head, innerLoop.tail, outerLoop.tail))
        }

        for nestedLoop in nestedLoops {
            guard code[nestedLoop.outerHead].op is BeginRepeatLoop else {
                // This means the outer loop has itself been merged with another loop
                continue
            }
            tryMergeNestedRepeatLoops(outerHead: nestedLoop.outerHead, innerHead: nestedLoop.innerHead, innerTail: nestedLoop.innerTail, outerTail: nestedLoop.outerTail, in: &code, with: helper)
        }
    }

    private func tryMergeNestedRepeatLoops(outerHead: Int, innerHead: Int, innerTail: Int, outerTail: Int, in code: inout Code, with helper: MinimizationHelper) {
        assert(outerHead < innerHead && innerHead < innerTail && innerTail < outerTail)
        let outer = code[outerHead].op as! BeginRepeatLoop
        let inner = code[innerHead].op as! BeginRepeatLoop
        let newHead = BeginRepeatLoop(iterations: outer.iterations * inner.iterations, exposesLoopCounter: outer.exposesLoopCounter || inner.exposesLoopCounter)

        var replacements = [(Int, Instruction)]()
        replacements.append((innerHead, Instruction(Nop())))
        replacements.append((innerTail, Instruction(Nop())))
        if !outer.exposesLoopCounter && !inner.exposesLoopCounter {
            // The simplest case: only need to replace the loop instructions and not deal with loop counters at all
            assert(!newHead.exposesLoopCounter)
            replacements.append((outerHead, Instruction(newHead)))
        } else if !outer.exposesLoopCounter || !inner.exposesLoopCounter {
            // Another simple case: only need to replace the loop instructions and reuse the one existing loop counter variable
            assert(newHead.exposesLoopCounter)
            let loopVar = outer.exposesLoopCounter ? code[outerHead].innerOutput : code[innerHead].innerOutput
            replacements.append((outerHead, Instruction(newHead, innerOutput: loopVar)))
        } else {
            // The more complicated case: we also need to rebind references to the inner loop's counter variable to the new counter variable
            let loopVar = code[outerHead].innerOutput
            replacements.append((outerHead, Instruction(newHead, innerOutput: loopVar)))

            let innerLoopVar = code[innerHead].innerOutput
            for instr in code[innerHead..<innerTail] {
                if instr.inputs.contains(innerLoopVar) {
                    let newInouts = instr.inouts.map({ $0 == innerLoopVar ? loopVar : $0 })
                    let replacement = Instruction(instr.op, inouts: newInouts)
                    replacements.append((instr.index, replacement))
                }
            }
        }

        // We may have changed the order of variable declarations, so we need to renumber the variables.
        helper.tryReplacements(replacements, in: &code, renumberVariables: true, numExecutions: numTestExecutions)
    }
}
