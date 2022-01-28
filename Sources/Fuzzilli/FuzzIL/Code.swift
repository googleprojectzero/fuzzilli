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
        // Stack of tuples (hasConstructor: Bool, hasSuperClass: Bool, superConstructorCalled: Bool) that track constructor definition and super() calls
        // TODO: Maybe hide this in ClassUtils.swift?
        var classConstructorStack:[(Bool, Bool, Bool)] = []

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
            guard instr.op.requiredContext.isSubset(of: contextAnalyzer.context) else {
                throw FuzzilliError.codeVerificationError("operation \(instr.op.name) inside an invalid context")
            }
            contextAnalyzer.analyze(instr)

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

                // Class Constructor semantic verification
                if instr.op is EndClassConstructor {
                    let (hasConstructor, hasSuperClass, superConstructorCalled) = classConstructorStack.removeLast()

                    // TODO:
                    // When a derived class that extends a base class is generated, the derived class constructor must call super() before any class instance properties are defined (i.e. `this.some_prop = variable`)
                    // The class generators ensure this requirement however the splicing algorithm does not take this requirement into consideration when generating a splice.
                    // As a result the programs generated from the splicing operation may not contain semantically valid class definitions.
                    // For now we disable this check until we have a better splicing algorithm that is aware of class defintion semantics.
                    // if hasSuperClass {
                    //     guard superConstructorCalled else {
                    //         throw FuzzilliError.codeVerificationError("super() must be called in derived constructor before accessing |this| or returning non-object.")
                    //     }
                    // }
                    //

                    classConstructorStack.append((hasConstructor, hasSuperClass, superConstructorCalled))
                }

                if instr.op is EndClassDefinition {
                    classConstructorStack.removeLast()
                }
            }

            // Ensure output variables don't exist yet
            for output in instr.outputs {
                // Nop outputs aren't visible and so should not be used by other instruction
                let scope = instr.op is Nop ? -1 : visibleScopes.last!
                try defineVariable(output, in: scope)
            }

            // Block and scope management (2)
            if instr.isBlockBegin {
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
                if let op = instr.op as? BeginClassDefinition {
                    // We haven't processed a constructor and we haven't invoked the super constructor
                    classConstructorStack.append((false, op.hasSuperclass, false))
                }

                if instr.op is BeginClassConstructor {
                    let (hasConstructor, hasSuperClass, superConstructorCalled) = classConstructorStack.removeLast()

                    // hasConstructor must be false or we have multiple constructor definitions
                    guard !hasConstructor else { 
                        throw FuzzilliError.codeVerificationError("Cannot declare multiple constructors in a single class.")
                    }

                    // superConstructorCalled must be false or it has been called in an invalid context (e.g. class methods)
                    guard !superConstructorCalled else {
                        throw FuzzilliError.codeVerificationError("super() was called in an invalid context.")
                    }

                    classConstructorStack.append((true, hasSuperClass, superConstructorCalled))
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

            if instr.op is CallSuperConstructor {
                let (hasConstructor, hasSuperClass, superConstructorCalled) = classConstructorStack.removeLast()

                // hasConstructor must be true or super() has been called in an invalid context (e.g. class methods)
                guard hasConstructor else {
                    throw FuzzilliError.codeVerificationError("super() was called in an invalid context.")
                }

                // superConstructorCalled must be false or it has been called more than once
                guard !superConstructorCalled else {
                    throw FuzzilliError.codeVerificationError("super() was called more than once")
                }

                classConstructorStack.append((hasConstructor, hasSuperClass, true))
            }

            // Ensure inner output variables don't exist yet
            for output in instr.innerOutputs {
                try defineVariable(output, in: visibleScopes.last!)
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
    
    // This restriction arises from the fact that variables and instruction indices are stored internally as UInt16
    public static let maxNumberOfVariables = 0x10000
}
