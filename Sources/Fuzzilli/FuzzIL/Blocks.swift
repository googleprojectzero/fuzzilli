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

/// A block is a sequence of instruction which starts at an opening instruction (isBlockBegin is true)
/// and ends at the next closing instruction (isBlockEnd is true) of the same nesting depth.
/// An example for a block is a loop:
///
///     BeginWhileLoop
///         ...
///     EndWhileLoop
///
/// A block contains the starting and ending instructions which are also referred to as "head" and "tail".
public struct Block {
    /// Index of the head of the block
    let head: Int

    /// Index of the tail of the block group
    let tail: Int

    /// The code that contains this block
    let code: Code

    public var size: Int {
        return tail - head + 1
    }

    public var begin: Instruction {
        return code[head]
    }

    public var end: Instruction {
        return code[tail]
    }

    public init(head: Int, tail: Int, in code: Code) {
        self.code = code
        self.head = head
        self.tail = tail

        assert(begin.isBlockStart)
        assert(end.isBlockEnd)
        assert(Blocks.findBlockBegin(end: end, in: code).index == head)
        assert(Blocks.findBlockEnd(head: begin, in: code).index == tail)
    }

    public init(startedBy head: Instruction, in code: Code) {
        assert(code.contains(head))
        assert(head.isBlockStart)
        let end = Blocks.findBlockEnd(head: head, in: code)
        self.init(head: head.index, tail: end.index, in: code)
    }

    public init(endedBy end: Instruction, in code: Code) {
        assert(code.contains(end))
        assert(end.isBlockEnd)
        let begin = Blocks.findBlockBegin(end: end, in: code)
        self.init(head: begin.index, tail: end.index, in: code)
    }

    /// Returns the list of instruction in the body of this block.
    ///
    /// TODO make iterator instead?
    public func body() -> [Instruction] {
        var instrs = [Instruction]()
        var idx = head + 1
        while idx < tail {
            instrs.append(code[idx])
            idx += 1
        }
        return instrs
    }
}

/// A block group is a sequence of blocks (and thus instructions) that is started by an opening instruction
/// that is not closing an existing block (isBlockBegin is true and isBlockEnd is false) and ends at a closing
/// instruction that doesn't open a new block (isBlockEnd is true and isBlockBegin is false).
/// An example for a block group is an if-else statement:
///
///     BeginIf
///        ; block 1
///        ...
///     BeginElse
///        ; block 2
///        ...
///     EndIf
///
public struct BlockGroup {
    /// The program that this block group is part of.
    public let code: Code

    /// Index of the first instruction in this block group (the opening instruction).
    public var head: Int {
        return blockInstructions.first!
    }

    /// Index of the last instruction in this block group (the closing instruction).
    public var tail: Int {
        return blockInstructions.last!
    }

    /// The number of instructions in this block group.
    public var size: Int {
        return tail - head + 1
    }

    /// The first instruction in this block group.
    public var begin: Instruction {
        return code[head]
    }

    /// The last instruction in this block group.
    public var end: Instruction {
        return code[tail]
    }

    /// The number of blocks that are part of this block group.
    public var numBlocks: Int {
        return blockInstructions.count - 1
    }

    /// Indices of the block instructions belonging to this block group
    private let blockInstructions: [Int]

    /// Constructs a block group from the a list of block instructions.
    ///
    /// - Parameters:
    ///   - blockInstructions: The block instructions that make up the block group.
    ///   - program: The program that the instructions are part of.
    fileprivate init(_ blockInstructions: [Instruction], in code: Code) {
        self.code = code
        self.blockInstructions = blockInstructions.map { $0.index }
        assert(begin.isBlockGroupStart)
        assert(end.isBlockGroupEnd)
    }

    public init(startedBy head: Instruction, in code: Code) {
        assert(code.contains(head))
        assert(head.isBlockGroupStart)
        let blockInstructions = Blocks.collectBlockGroupInstructions(head: head, in: code)
        self.init(blockInstructions, in: code)
    }

    public init(around instr: Instruction, in code: Code) {
        assert(code.contains(instr))
        let head = Blocks.findBlockGroupHead(around: instr, in: code)
        self.init(startedBy: head, in: code)
    }

    /// Returns the ith block in this block group.
    func block(_ i: Int) -> Block {
        return Block(head: blockInstructions[i], tail: blockInstructions[i + 1], in: code)
    }

    /// Returns the ith block instruction in this block group.
    subscript(i: Int) -> Instruction {
        return code[blockInstructions[i]]
    }

    /// Returns a list of all block instructions that make up this block group.
    func excludingContent() -> [Instruction] {
        return blockInstructions.map { code[$0] }
    }

    /// Returns a list of all instructions, including content instructions, of this block group.
    // TODO should return a custom Sequence.
    func includingContent() -> [Instruction] {
        return Array(code[head...tail])
    }
}

/// Block-related utility algorithms are  implemented here, and used by the Block/BlockGroup constructors.
public class Blocks {
    // TODO see if it's possible to factor out and reuse the common traversal code.

    // TODO merge with findBlockBegin
    static func findBlockEnd(head: Instruction, in code: Code) -> Instruction {
        assert(head.isBlockStart)

        var idx = head.index + 1
        var depth = 1
        while idx < code.count {
            let current = code[idx]
            if current.isBlockEnd {
                depth -= 1
            }
            if depth == 0 {
                assert(current.isBlockEnd)
                return current
            }
            if current.isBlockStart {
                depth += 1
            }
            idx += 1
        }

        fatalError("Invalid code")
    }

    static func findBlockBegin(end: Instruction, in code: Code) -> Instruction {
        assert(end.isBlockEnd)

        var idx = end.index - 1
        var depth = 1
        while idx >= 0 {
            let current = code[idx]
            if current.isBlockStart {
                depth -= 1
            }
            // Note: the placement of this if is the only difference from the following function...
            if depth == 0 {
                assert(current.isBlockStart)
                return current
            }
            if current.isBlockEnd {
                depth += 1
            }
            idx -= 1
        }

        fatalError("Invalid code")
    }

    static func findBlockGroupHead(around instr: Instruction, in code: Code) -> Instruction {
        guard !instr.isBlockGroupStart else {
            return instr
        }

        var idx = instr.index - 1
        var depth = 1
        repeat {
            let current = code[idx]
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

    static func collectBlockGroupInstructions(head: Instruction, in code: Code) -> [Instruction] {
        var blockInstructions = [head]

        var idx = head.index + 1
        var depth = 1
        repeat {
            let current = code[idx]

            if current.isBlockEnd {
                depth -= 1
            }
            if current.isBlockStart {
                if depth == 0 {
                    blockInstructions.append(current)
                }
                depth += 1
            }
            if depth == 0 {
                assert(current.isBlockGroupEnd)
                blockInstructions.append(current)
                break
            }
            idx += 1
        } while idx < code.count
        assert(idx < code.count)

        return blockInstructions
    }

    static func findAllBlockGroups(in code: Code) -> [BlockGroup] {
        var groups = [BlockGroup]()

        var blockStack = [[Instruction]]()
        for instr in code {
            if instr.isBlockStart && !instr.isBlockEnd {
                // By definition, this is the start of a block group
                blockStack.append([instr])
            } else if instr.isBlockEnd {
                // Either the end of a block group or a new block in the current block group.
                blockStack[blockStack.count - 1].append(instr)
                if !instr.isBlockStart {
                    groups.append(BlockGroup(blockStack.removeLast(), in: code))
                }
            }
        }

        return groups
    }
}
