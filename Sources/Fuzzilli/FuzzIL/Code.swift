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
            return instructions[i]
        }
        set {
            return instructions[i] = Instruction(newValue.op, inouts: newValue.inouts, index: i)
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
        Assert(contains(instr))
        self[instr.index] = newInstr
    }

    /// Computes the last variable (which will have the highest number) in this code or nil if there are no variables.
    public func lastVariable() -> Variable? {
        Assert(isStaticallyValid())
        for instr in instructions.reversed() {
            if let v = instr.allOutputs.max() {
                return v
            }
        }
        return nil
    }

    /// Computes the next free variable in this code.
    public func nextFreeVariable() -> Variable {
        Assert(isStaticallyValid())
        if let lastVar = lastVariable() {
            return Variable(number: lastVar.number + 1)
        }
        return Variable(number: 0)
    }

    /// Removes nops and renumbers variables so that their numbers are contiguous.
    public mutating func normalize() {
        var writeIndex = 0
        var numVariables = 0
        var varMap = VariableMap<Variable>()

        for instr in self {
            if instr.op is Nop {
                continue
            }

            for output in instr.allOutputs {
                // Must create a new variable
                Assert(!varMap.contains(output))
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

    /// Returns a normalized copy of this code.
    public func normalized() -> Code {
        var copy = self
        copy.normalize()
        return copy
    }

    /// Checks if this code is statically valid, i.e. can be used as a Program.
    public func check() throws {
        var definedVariables = VariableMap<Int>()
        var scopeCounter = 0
        var visibleScopes = [scopeCounter]
        var contextAnalyzer = ContextAnalyzer()
        var blockHeads = [Operation]()
        var defaultSwitchCaseStack: [Bool] = []
        var classDefinitions = ClassDefinitionStack()

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
                guard visibleScopes.contains(definingScope) else {
                    throw FuzzilliError.codeVerificationError("variable \(input) is not visible anymore")
                }
            }

            // Ensure that the instruction exists in the right context
            contextAnalyzer.analyze(instr)
            guard instr.op.requiredContext.isSubset(of: contextAnalyzer.context) else {
                throw FuzzilliError.codeVerificationError("operation \(instr.op.name) inside an invalid context")
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

                // Switch Case semantic verification
                if instr.op is EndSwitch {
                    defaultSwitchCaseStack.removeLast()
                }

                // Class semantic verification
                if instr.op is EndClass {
                    guard !classDefinitions.current.hasPendingMethods else {
                        let pendingMethods = classDefinitions.current.pendingMethods().map({ $0.name })
                        throw FuzzilliError.codeVerificationError("missing method definitions for methods \(pendingMethods) in class \(classDefinitions.current.name)")
                    }
                    classDefinitions.pop()
                }
            }

            // Ensure output variables don't exist yet
            for output in instr.outputs {
                // Nop outputs aren't visible and so should not be used by other instruction
                let scope = instr.op is Nop ? -1 : visibleScopes.last!
                try defineVariable(output, in: scope)
            }

            // Block and scope management (2)
            if instr.isBlockStart {
                scopeCounter += 1
                visibleScopes.append(scopeCounter)
                blockHeads.append(instr.op)

                // Switch Case semantic verification
                if let op = instr.op as? BeginSwitch, op.isDefaultCase {
                    defaultSwitchCaseStack.append(true)
                } else {
                    defaultSwitchCaseStack.append(false)
                }

                // Class semantic verification
                if let op = instr.op as? BeginClass {
                    classDefinitions.push(ClassDefinition(from: op, name: instr.output.identifier))
                } else if instr.op is BeginMethod {
                    guard classDefinitions.current.hasPendingMethods else {
                        throw FuzzilliError.codeVerificationError("too many method definitions for class \(classDefinitions.current.name)")
                    }
                    let _ = classDefinitions.current.nextMethod()
                }
            }

            // Ensure that we have at most one default case in a switch block
            if let op = instr.op as? BeginSwitchCase, op.isDefaultCase {
                let stackTop = defaultSwitchCaseStack.removeLast()

                // Check if the current block already has a default case
                guard !stackTop else {
                    throw FuzzilliError.codeVerificationError("more than one default switch case defined")
                }

                defaultSwitchCaseStack.append(true)
            }

            // Ensure inner output variables don't exist yet
            for output in instr.innerOutputs {
                try defineVariable(output, in: visibleScopes.last!)
            }
        }

        Assert(!definedVariables.hasHoles())
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
