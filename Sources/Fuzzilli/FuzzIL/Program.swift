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

/// Unit of code that can be executed, scored, and mutated.
///
/// There are a few invariants of programs that are enforced by the engine:
///
/// * The empty program is valid
/// * All input variables must have previously been defined
/// * Variables have increasing numbers starting at zero and there are no holes (TODO check in isValid())
/// * An instruction always produces a new output variable (SSA form)
/// * The first input to a Copy operation must be a variable produced by a Phi operation (SSA form)
///
/// These invariants can be verified at any time by calling check().
///
public class Program: Collection, Codable {
    /// A program is simply a collection of instructions.
    private var instructions: [Instruction] = []
    
    /// The number of instructions in this program.
    var size: Int {
        return instructions.count
    }
    
    /// The index of the first instruction, always 0.
    public let startIndex = 0
    
    /// The index of the last instruction plus one, always equal to the size of the program.
    public var endIndex: Int {
        return size
    }
    
    /// Advances the given index by one. Simply returns the argument plus 1.
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    /// Returns the ith instruction in this program.
    public subscript(i: Int) -> Instruction {
        return instructions[i]
    }
    
    /// The last instruction in this program.
    public var lastInstruction: Instruction {
        return instructions.last!
    }

    /// Creates a (shallow) copy of this program.
    public func copy() -> Program {
        let copy = Program()
        copy.instructions = instructions
        return copy
    }
    
    /// Appends the given instruction to this program.
    public func append(_ instr: Instruction) {
        let instruction = Instruction(operation: instr.operation, inouts: instr.inouts, index: size)
        instructions.append(instruction)
    }
    
    /// Removes the last instruction in this program.
    public func removeLastInstruction() {
        instructions.removeLast()
    }
    
    /// Replaces an instruction with a different one. Returns the replaced instruction.
    ///
    /// - Parameters:
    ///   - index: The index of the instruction to replace.
    ///   - newInstr: The new instruction to replace the old instruction with.
    /// - Returns: The old instruction.
    @discardableResult
    public func replace(instructionAt index: Int, with newInstr: Instruction) -> Instruction {
        let oldInstr = instructions[index]
        instructions[index] = Instruction(operation: newInstr.operation, inouts: newInstr.inouts, index: index)
        return oldInstr
    }
    
    /// Normalizes this program.
    ///
    /// Normalization:
    ///  * Removes NOP instructions
    ///  * Renames variables so their number are contiguous
    public func normalize() {
        var writeIndex = 0
        var numVariables = 0
        var varMap = VariableMap<Variable>()
        
        for instr in self {
            if instr.operation is Nop {
                continue
            }
            
            for output in instr.allOutputs {
                // Must create a new variable
                assert(!varMap.contains(output))
                varMap[output] = Variable(number: numVariables)
                numVariables += 1
            }
            
            let inouts = instr.inouts.map({ varMap[$0]! })
            
            instructions[writeIndex] = Instruction(operation: instr.operation, inouts: inouts, index: writeIndex)
            writeIndex += 1
        }
        
        instructions.removeLast(size - writeIndex)
    }
    
    /// Returns the instructions of this program in reversed order.
    public func reversed() -> ReversedCollection<Array<Instruction>> {
        return instructions.reversed()
    }

    /// Checks if this program is valid.
    public func check() -> CheckResult {
        var definedVariables = VariableMap<Int>()
        var scopeCounter = 0
        var visibleScopes = [scopeCounter]
        var blockHeads = [Operation]()
        var phis = VariableSet()
        
        for (idx, instr) in instructions.enumerated() {
            guard idx == instr.index else {
                return .invalid("instruction \(idx) has wrong index \(String(describing: instr.index))")
            }
            
            // Block and scope management (1)
            if instr.isBlockEnd {
                guard let blockBegin = blockHeads.popLast() else {
                    return .invalid("block was never started")
                }
                guard Matches(blockBegin, instr.operation) else {
                    return .invalid("block end does not match block start")
                }
                visibleScopes.removeLast()
            }
            
            // Ensure all input variables are valid and have been defined
            for input in instr.inputs {
                guard let definingScope = definedVariables[input] else {
                    return .invalid("variable \(input) was never defined")
                }
                guard visibleScopes.contains(definingScope) else {
                    return .invalid("variable \(input) is not visible anymore")
                }
            }
            
            // Ensure output variables don't exist yet
            for output in instr.outputs {
                guard !definedVariables.contains(output) else {
                    return .invalid("variable \(output) was already defined")
                }
                definedVariables[output] = visibleScopes.last!
            }
            
            // Block and scope management (2)
            if instr.isBlockBegin {
                scopeCounter += 1
                visibleScopes.append(scopeCounter)
                blockHeads.append(instr.operation)
            }

            // Ensure inner output variables don't exist yet
            for output in instr.innerOutputs {
                guard !definedVariables.contains(output) else {
                    return .invalid("variable \(output) was already defined")
                }
                definedVariables[output] = visibleScopes.last!
            }
            
            // Special handling for Phi and Copy operations
            if instr.operation is Phi {
                phis.insert(instr.output)
            } else if instr.operation is Copy {
                guard phis.contains(instr.input(0)) else {
                    return .invalid("input to a Copy operation is not the output of a Phi operation")
                }
            }
        }
        return .valid
    }
    
    /// Possible outcomes of the Program.check() method.
    public enum CheckResult {
        case valid
        case invalid(_ reason: String)
    }
}

public func ==(lhs: Program.CheckResult, rhs: Program.CheckResult) -> Bool {
    switch (lhs, rhs) {
    case (.valid, .valid):
        return true
    case let (.invalid(a), .invalid(b)):
        return a == b
    default:
        return false
    }
}
