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

    /// Code is just a linear sequence of instructions
    private var instructions = [Instruction]()

    /// Creates an empty code instance.
    public init() {}

    /// Creates a code instance containing the given instructions.
    public init(_ instructions: [Instruction]) {
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
            instructions[i]
        }
        set {
            instructions[i] = Instruction(newValue.op, inouts: newValue.inouts, index: i)
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
    public mutating func append(_ instr: Instruction) {
        instructions.append(Instruction(instr.op, inouts: instr.inouts, index: count))
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
    
    /// Computes the next free variable in this code.
    public func nextFreeVariable() -> Variable {
        assert(isStaticallyValid())
        for instr in instructions.reversed() {
            if let r = instr.allOutputs.max() {
                return Variable(number: r.number + 1)
            }
        }
        return Variable(number: 0)
    }
    
    /// Removes nops and renumbers variables so that their numbers are contiguous.
    public mutating func normalize() {
        assert(isStaticallyValid())
        var writeIndex = 0
        var numVariables = 0
        var varMap = VariableMap<Variable>()

        for instr in self {
            if instr.op is Nop {
                continue
            }

            for output in instr.allOutputs {
                // Must create a new variable
                assert(!varMap.contains(output))
                let mappedVar = Variable(number: numVariables)
                varMap[output] = mappedVar
                numVariables += 1
            }

            let inouts = instr.inouts.map({ varMap[$0]! })

            self[writeIndex] = Instruction(instr.op, inouts: inouts)
            writeIndex += 1
        }

        removeLast(count - writeIndex)
    }
    
    /// Checks if this code is statically valid, i.e. can be used as a Program.
    public func check() throws {
        var definedVariables = VariableMap<Int>()
        var scopeCounter = 0
        var visibleScopes = [scopeCounter]
        var blockHeads = [Operation]()

        for (idx, instr) in instructions.enumerated() {
            guard idx == instr.index else {
                throw FuzzilliError.codeVerificationError("instruction \(idx) has wrong index \(String(describing: instr.index))")
            }

            // Ensure all input variables are valid and have been defined
            for input in instr.inputs {
                guard let definingScope = definedVariables[input] else {
                    throw FuzzilliError.codeVerificationError("variable \(input) was never defined")
                }
                guard visibleScopes.contains(definingScope) else {
                    throw FuzzilliError.codeVerificationError("variable \(input) is not visible anymore")
                }
            }

            // Block and scope management (1)
            if instr.isBlockEnd {
                guard let blockBegin = blockHeads.popLast() else {
                    throw FuzzilliError.codeVerificationError("block was never started")
                }
                guard instr.op.isMatchingEnd(for: blockBegin) else {
                    throw FuzzilliError.codeVerificationError("block end does not match block start")
                }
                visibleScopes.removeLast()
            }

            // Ensure output variables don't exist yet
            for output in instr.outputs {
                guard !definedVariables.contains(output) else {
                    throw FuzzilliError.codeVerificationError("variable \(output) was already defined")
                }
                // Verify that nop outputs are not be used by other instruction
                let scope = instr.op is Nop ? -1 : visibleScopes.last!
                definedVariables[output] = scope
            }

            // Block and scope management (2)
            if instr.isBlockBegin {
                scopeCounter += 1
                visibleScopes.append(scopeCounter)
                blockHeads.append(instr.op)
            }

            // Ensure inner output variables don't exist yet
            for output in instr.innerOutputs {
                guard !definedVariables.contains(output) else {
                    throw FuzzilliError.codeVerificationError("variable \(output) was already defined")
                }
                definedVariables[output] = visibleScopes.last!
            }
        }

        // Ensure that variable numbers are contiguous
        guard !definedVariables.hasHoles() else {
            throw FuzzilliError.codeVerificationError("Variable numbers are not contiguous")
        }
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
    
    // This restriction arises from the fact that variables and instruction indices are stored internally as UInt16
    public static let maxNumberOfVariables = 0x10000
}
