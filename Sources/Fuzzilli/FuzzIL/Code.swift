// Copyright 2020 Google LLC
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

/// Code: a sequence of instructions. Forms the basis of Programs.
public struct Code: Collection {
    public typealias Element = Instruction

    /// The maximum number of variables. This restriction arises from the fact that variables and instruction indices are stored internally as UInt16
    public static let maxNumberOfVariables = 0x10000

    /// Code is just a linear sequence of instructions.
    private var instructions = [Instruction]()

    /// Creates an empty code instance.
    public init() {}

    /// Creates a code instance containing the given instructions.
    public init<S: Sequence>(_ instructions: S) where S.Element == Instruction {
        for instr in instructions {
            append(instr)
        }
    }

    /// The number of instructions.
    public var count: Int {
        return instructions.count
    }

    /// The index of the first instruction, always 0.
    public var startIndex: Int {
        return 0
    }

    /// The index of the last instruction plus one.
    public var endIndex: Int {
        return count
    }

    /// Advances the given index by one. Simply returns the argument plus 1.
    public func index(after i: Int) -> Int {
        return i + 1
    }

    /// Access the ith instruction in this code.
    public subscript(i: Int) -> Instruction {
        get {
            assert(instructions[i].index == i)
            return instructions[i]
        }
        set {
            return instructions[i] = Instruction(newValue.op, inouts: newValue.inouts, index: i, flags: newValue.flags)
        }
    }

    /// Returns the instruction after the given one, if it exists.
    public func after(_ instr: Instruction) -> Instruction? {
        let idx = instr.index + 1
        return idx < endIndex ? self[idx] : nil
    }

    /// Returns the instruction before the given one, if it exists.
    public func before(_ instr: Instruction) -> Instruction? {
        let idx = instr.index - 1
        return idx >= 0 ? self[idx] : nil
    }

    /// Returns all instructions that are part of the given block, including the block head and tail instructions.
    public subscript(_ block: Block) -> Slice<Code> {
        assert(isValidBlock(block))
        return self[block.head...block.tail]
    }

    /// Returns all instructions in the body of the given block, i.e. excluding the block head and tail instructions.
    public func body(of block: Block) -> Slice<Code> {
        assert(isValidBlock(block))
        return self[index(after: block.head)..<block.tail]
    }

    /// The last instruction in this code.
    public var lastInstruction: Instruction {
        return instructions.last!
    }

    /// Returns the instructions in this code in reversed order.
    public func reversed() -> ReversedCollection<Array<Instruction>> {
        return instructions.reversed()
    }

    /// Enumerates the instructions in this code.
    public func enumerated() -> EnumeratedSequence<Array<Instruction>> {
        return instructions.enumerated()
    }

    /// Appends the given instruction to this code.
    /// The inserted instruction will now also contain its index in this code.
    @discardableResult
    public mutating func append(_ instr: Instruction) -> Instruction {
        let instr = Instruction(instr.op, inouts: instr.inouts, index: count, flags: instr.flags)
        instructions.append(instr)
        return instr
    }

    /// Removes all instructions in this code.
    public mutating func removeAll() {
        instructions.removeAll()
    }

    /// Removes the last instruction in this code.
    public mutating func removeLast(_ n: Int = 1) {
        instructions.removeLast(n)
    }

    /// Checks whether the given instruction belongs to this code.
    public func contains(_ instr: Instruction) -> Bool {
        let idx = instr.index
        guard idx >= 0 && idx < count else { return false }
        return instr.op === self[idx].op && instr.inouts == self[idx].inouts
    }

    /// Replaces an instruction with a different one.
    ///
    /// - Parameters:
    ///   - instr: The instruction to replace.
    ///   - newInstr: The new instruction.
    public mutating func replace(_ instr: Instruction, with newInstr: Instruction) {
        assert(contains(instr))
        self[instr.index] = newInstr
    }

    /// Computes the last variable (which will have the highest number) in this code or nil if there are no variables.
    public func lastVariable() -> Variable? {
        assert(isStaticallyValid())
        for instr in instructions.reversed() {
            if let v = instr.allOutputs.max() {
                return v
            }
        }
        return nil
    }

    /// Computes the next free variable in this code.
    public func nextFreeVariable() -> Variable {
        assert(isStaticallyValid())
        if let lastVar = lastVariable() {
            return Variable(number: lastVar.number + 1)
        }
        return Variable(number: 0)
    }

    /// Renumbers variables so that their numbers are again continuous.
    /// This can be useful after instructions have been reordered, for example for the purpose of minimization.
    public mutating func renumberVariables() {
        var numVariables = 0
        var varMap = VariableMap<Variable>()
        for (idx, instr) in self.enumerated() {
            for output in instr.allOutputs {
                assert(!varMap.contains(output))
                let mappedVar = Variable(number: numVariables)
                varMap[output] = mappedVar
                numVariables += 1
            }
            let inouts = instr.inouts.map({ varMap[$0]! })
            self[idx] = Instruction(instr.op, inouts: inouts, flags: instr.flags)
        }
    }

    /// Returns true if the variables in this code are numbered continuously.
    public func variablesAreNumberedContinuously() -> Bool {
        var definedVariables = VariableSet()
        for instr in self {
            for v in instr.allOutputs {
                guard !definedVariables.contains(v) else { return false }
                if v.number > 0 {
                    guard definedVariables.contains(Variable(number: v.number - 1)) else { return false }
                }
                definedVariables.insert(v)
            }
        }
        return true
    }

    /// Remove all nop instructions from this code.
    /// Mainly used at the end of code minimization, as code reducers typically just replace deleted instructions with a nop.
    public mutating func removeNops() {
        instructions = instructions.filter({ !($0.isNop) })
        // Need to renumber the variables now as nops can have outputs, but also because the instruction indices are no longer correct.
        renumberVariables()
    }

    /// Checks if this code is statically valid, i.e. can be used as a Program.
    public func check() throws {
        var definedVariables = VariableMap<Int>()
        var contextAnalyzer = ContextAnalyzer()
        var scopeCounter = 0
        // Per-block information is stored in this struct and kept in a stack of active blocks.
        struct Block {
            let scopeId: Int
            let head: Operation?
        }
        var activeBlocks = Stack<Block>([Block(scopeId: scopeCounter, head: nil)])
        // Contains the number of loop variables, which must be the same for every block in the for-loop's header.
        var forLoopHeaderStack = Stack<Int>()

        func defineVariable(_ v: Variable, in scope: Int) throws {
            guard !definedVariables.contains(v) else {
                throw FuzzilliError.codeVerificationError("variable \(v) was already defined")
            }
            if v.number != 0 {
                let prev = Variable(number: v.number - 1)
                guard definedVariables.contains(prev) else {
                    throw FuzzilliError.codeVerificationError("variable definitions are not contiguous: \(v) is defined before \(prev)")
                }
            }
            definedVariables[v] = scope
        }

        for (idx, instr) in instructions.enumerated() {
            guard idx == instr.index else {
                throw FuzzilliError.codeVerificationError("instruction \(idx) has wrong index \(String(describing: instr.index))")
            }

            // Ensure all input variables are valid and have been defined
            for input in instr.inputs {
                guard let definingScope = definedVariables[input] else {
                    throw FuzzilliError.codeVerificationError("variable \(input) was never defined")
                }
                guard activeBlocks.contains(where: { $0.scopeId == definingScope }) else {
                    throw FuzzilliError.codeVerificationError("variable \(input) is not visible anymore")
                }
            }

            guard instr.op.requiredContext.isSubset(of: contextAnalyzer.context) else {
                throw FuzzilliError.codeVerificationError("operation \(instr.op.name) inside an invalid context")
            }

            // Ensure that the instruction exists in the right context
            contextAnalyzer.analyze(instr)

            // Block and scope management (1)
            if instr.isBlockEnd {
                guard !activeBlocks.isEmpty else {
                    throw FuzzilliError.codeVerificationError("block was never started")
                }
                let block = activeBlocks.pop()
                guard block.head?.isMatchingStart(for: instr.op) ?? false else {
                    throw FuzzilliError.codeVerificationError("block end does not match block start")
                }
            }

            // Ensure output variables don't exist yet
            for output in instr.outputs {
                // Nop outputs aren't visible and so should not be used by other instruction
                let scope = instr.isNop ? -1 : activeBlocks.top.scopeId
                try defineVariable(output, in: scope)
            }

            // Block and scope management (2)
            if instr.isBlockStart {
                scopeCounter += 1
                activeBlocks.push(Block(scopeId: scopeCounter, head: instr.op))

                // Ensure that all blocks in a for-loop's header have the same number of loop variables.
                if instr.op is BeginForLoopCondition {
                    guard instr.numInputs == instr.numInnerOutputs else {
                        throw FuzzilliError.codeVerificationError("for-loop header is inconsistent")
                    }
                    forLoopHeaderStack.push(instr.numInnerOutputs)
                } else if instr.op is BeginForLoopAfterthought {
                    guard instr.numInnerOutputs == forLoopHeaderStack.top else {
                        throw FuzzilliError.codeVerificationError("for-loop header is inconsistent")
                    }
                } else if instr.op is BeginForLoopBody {
                    guard instr.numInnerOutputs == forLoopHeaderStack.pop() else {
                        throw FuzzilliError.codeVerificationError("for-loop header is inconsistent")
                    }
                }
            }

            // Ensure inner output variables don't exist yet
            for output in instr.innerOutputs {
                try defineVariable(output, in: activeBlocks.top.scopeId)
            }
        }

        assert(!definedVariables.hasHoles())
    }

    /// Returns true if this code is valid, false otherwise.
    public func isStaticallyValid() -> Bool {
        do {
            try check()
            return true
        } catch {
            return false
        }
    }

    public func countIntructionsWith(flags: Instruction.Flags) -> Int {
        self.filter { instr in
            instr.flags.contains(flags)
        }.count
    }

    /// This is used in the minimizer to clear flags that have been set during minimization.
    public mutating func clearFlags() {
        for idx in 0..<self.count {
            self[idx].flags = .empty
        }
    }

    //
    // Routines for accessing the blocks of a Code object.
    //
    public func block(startingAt head: Int) -> Block {
        assert(self[head].isBlockStart)
        let end = findBlockEnd(head: head)
        return Block(head: head, tail: end, in: self)
    }

    public func block(startedBy head: Instruction) -> Block {
        assert(contains(head))
        return block(startingAt: head.index)
    }

    public func block(endingAt end: Int) -> Block {
        assert(self[end].isBlockEnd)
        let begin = findBlockBegin(end: end)
        return Block(head: begin, tail: end, in: self)
    }

    public func block(endedBy end: Instruction) -> Block {
        assert(contains(end))
        return block(endingAt: end.index)
    }

    public func blockgroup(startedBy head: Instruction) -> BlockGroup {
        assert(contains(head))
        assert(head.isBlockGroupStart)
        let blockInstructions = collectBlockGroupInstructions(head: head)
        return BlockGroup(blockInstructions, in: self)
    }

    public func blockgroup(around instr: Instruction) -> BlockGroup {
        assert(contains(instr))
        let head = findBlockGroupHead(around: instr)
        return blockgroup(startedBy: head)
    }

    public func findBlockEnd(head: Int) -> Int {
        assert(self[head].isBlockStart)

        var idx = head + 1
        var depth = 1
        while idx < count {
            let current = self[idx]
            if current.isBlockEnd {
                depth -= 1
            }
            if depth == 0 {
                assert(current.isBlockEnd)
                return current.index
            }
            if current.isBlockStart {
                depth += 1
            }
            idx += 1
        }

        fatalError("Invalid code")
    }

    public func findBlockBegin(end: Int) -> Int {
        assert(self[end].isBlockEnd)

        var idx = end - 1
        var depth = 1
        while idx >= 0 {
            let current = self[idx]
            if current.isBlockStart {
                depth -= 1
            }
            // Note: the placement of this if is the only difference from the following function...
            if depth == 0 {
                assert(current.isBlockStart)
                return current.index
            }
            if current.isBlockEnd {
                depth += 1
            }
            idx -= 1
        }

        fatalError("Invalid code")
    }

    public func findBlockGroupHead(around instr: Instruction) -> Instruction {
        guard !instr.isBlockGroupStart else {
            return instr
        }

        var idx = instr.index - 1
        var depth = 1
        repeat {
            let current = self[idx]
            if current.isBlockStart {
                depth -= 1
            }
            if current.isBlockEnd {
                depth += 1
            }
            if depth == 0 {
                assert(current.isBlockGroupStart)
                return current
            }
            idx -= 1
        } while idx >= 0

        fatalError("Invalid code")
    }

    public func collectBlockGroupInstructions(head: Instruction) -> [Int] {
        var blockInstructions = [head.index]

        var idx = head.index + 1
        var depth = 1
        repeat {
            let current = self[idx]

            if current.isBlockEnd {
                depth -= 1
            }
            if current.isBlockStart {
                if depth == 0 {
                    blockInstructions.append(current.index)
                }
                depth += 1
            }
            if depth == 0 {
                assert(current.isBlockGroupEnd)
                blockInstructions.append(current.index)
                break
            }
            idx += 1
        } while idx < count
        assert(idx < count)

        return blockInstructions
    }

    /// Finds and returns all block groups in this code.
    ///
    /// The returned list will be ordered:
    ///  - an inner block will come before its surrounding block
    ///  - a block ending before another block starts will come before that block
    public func findAllBlockGroups() -> [BlockGroup] {
        var groups = [BlockGroup]()

        var blockStack = Stack<[Int]>()
        for instr in self {
            if instr.isBlockStart && !instr.isBlockEnd {
                // By definition, this is the start of a block group
                blockStack.push([instr.index])
            } else if instr.isBlockEnd {
                // Either the end of a block group or a new block in the current block group.
                blockStack.top.append(instr.index)
                if !instr.isBlockStart {
                    groups.append(BlockGroup(blockStack.pop(), in: self))
                }
            }
        }

        return groups
    }

    /// Check that the given block object describes a block in this code.
    private func isValidBlock(_ block: Block) -> Bool {
        return block.tail <= endIndex && self[block.head].isBlockStart && self[block.tail].isBlockEnd && self[block.tail].op.isMatchingEnd(for: self[block.head].op)
    }
}
