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
    
    /// The program that contains this block
    let program: Program
    
    var size: Int {
        return tail - head + 1
    }
    
    var begin: Instruction {
        return program[head]
    }
    
    var end: Instruction {
        return program[tail]
    }
    
    init(head: Int, tail: Int, in program: Program) {
        self.program = program
        self.head = head
        self.tail = tail
        assert(begin.isBlockBegin)
        assert(end.isBlockEnd)
    }
    
    /// Returns the list of instruction in the body of this block.
    ///
    /// TODO make iterator instead?
    func body() -> [Instruction] {
        var instrs = [Instruction]()
        var idx = head + 1
        while idx < tail {
            instrs.append(program[idx])
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
    public let program: Program
    
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
        return program[head]
    }
    
    /// The last instruction in this block group.
    public var end: Instruction {
        return program[tail]
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
    init(_ blockInstructions: [Instruction], in program: Program) {
        self.program = program
        self.blockInstructions = blockInstructions.map { $0.index }
        assert(begin.isBlockGroupBegin)
        assert(end.isBlockGroupEnd)
    }
    
    /// Returns the ith block in this block group.
    func block(_ i: Int) -> Block {
        return Block(head: blockInstructions[i], tail: blockInstructions[i + 1], in: program)
    }
    
    /// Returns the ith block instruction in this block group.
    subscript(i: Int) -> Instruction {
        return program[blockInstructions[i]]
    }
    
    /// Returns a list of all block instructions that make up this block group.
    func excludingContent() -> [Instruction] {
        return blockInstructions.map { program[$0] }
    }
    
    /// Returns a list of all instructions, including content instructions, of this block group.
    // TODO should return a custom Sequence.
    func includingContent() -> [Instruction] {
        return Array(program[head...tail])
    }
}

/// Block-related algorithms are generally implemented here, while the Program class provides access to its Blocks and BlockGroups using these algorithms.
public class Blocks {
    // TODO see if it's possible to factor out and reuse the common traversal code.
    
    static func findBlockBegin(end: Instruction, in program: Program) -> Instruction {
        precondition(end.isBlockEnd)
        
        var idx = end.index - 1
        var depth = 1
        repeat {
            let current = program[idx]
            if current.isBlockBegin {
                depth -= 1
            }
            // Note: the placement of this if is the only difference from the following function...
            if depth == 0 {
                assert(current.isBlockBegin)
                return current
            }
            if current.isBlockEnd {
                depth += 1
            }
            idx -= 1
        } while idx >= 0
        
        fatalError("Invalid Program")
    }

    static func findBlockGroupHead(around instr: Instruction, in program: Program) -> Instruction {
        guard !instr.isBlockGroupBegin else {
            return instr
        }
        
        var idx = instr.index - 1
        var depth = 1
        repeat {
            let current = program[idx]
            if current.isBlockBegin {
                depth -= 1
            }
            if current.isBlockEnd {
                depth += 1
            }
            if depth == 0 {
                assert(current.isBlockGroupBegin)
                return current
            }
            idx -= 1
        } while idx >= 0
        
        fatalError("Invalid Program")
    }
    
    static func collectBlockGroupInstructions(head: Instruction, in program: Program) -> [Instruction] {
        var blockInstructions = [head]
        
        var idx = head.index + 1
        var depth = 1
        repeat {
            let current = program[idx]
            
            if current.isBlockEnd {
                depth -= 1
            }
            if current.isBlockBegin {
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
        } while idx < program.size
        assert(idx < program.size)
        
        return blockInstructions
    }
    
    static func findAllBlockGroups(in program: Program) -> [BlockGroup] {
        var groups = [BlockGroup]()
        
        var blockStack = [[Instruction]]()
        for instr in program {
            if instr.isBlockBegin && !instr.isBlockEnd {
                // By definition, this is the start of a block group
                blockStack.append([instr])
            } else if instr.isBlockEnd {
                // Either the end of a block group or a new block in the current block group.
                blockStack[blockStack.count - 1].append(instr)
                if !instr.isBlockBegin {
                    groups.append(BlockGroup(blockStack.removeLast(), in: program))
                }
            }
        }
        
        return groups
    }
}

