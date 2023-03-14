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

    /// The number of instructions in this block, including the two block instructions themselves.
    public var size: Int {
        return tail - head + 1
    }

    /// Returns the indices of all instructions in this block.
    public var allInstructions: [Int] {
        return Array(head...tail)
    }

    public init(head: Int, tail: Int, in code: Code) {
        self.head = head
        self.tail = tail

        assert(head < tail)
        assert(code[head].isBlockStart)
        assert(code[tail].isBlockEnd)
        assert(code.findBlockBegin(end: tail) == head)
        assert(code.findBlockEnd(head: head) == tail)
    }

    fileprivate init(head: Int, tail: Int) {
        assert(head < tail)

        self.head = head
        self.tail = tail
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
    /// The indices of the block instructions belonging to this block group in the code.
    private let blockInstructions: [Int]

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

    /// The number of blocks that are part of this block group.
    public var numBlocks: Int {
        return blockInstructions.count - 1
    }

    /// The indices of all block instructions belonging to this block group.
    public var blockInstructionIndices: [Int] {
        return blockInstructions
    }

    /// The indices of all instructions in this block group.
    public var instructionIndices: [Int] {
        return Array(head...tail)
    }

    /// All blocks of this block group.
    public var blocks: [Block] {
        return (0..<numBlocks).map(block)
    }

    /// Returns the i-th block in this block group.
    public func block(_ i: Int) -> Block {
        return Block(head: blockInstructions[i], tail: blockInstructions[i + 1])
    }

    /// Constructs a block group from the a list of block instructions.
    public init(_ blockInstructions: [Int], in code: Code) {
        assert(blockInstructions.count >= 2)
        self.blockInstructions = blockInstructions
        assert(code[head].isBlockGroupStart)
        assert(code[tail].isBlockGroupEnd)
        for intermediate in blockInstructions.dropFirst().dropLast() {
            assert(code[intermediate].isBlockStart && code[intermediate].isBlockEnd)
        }
    }
}
