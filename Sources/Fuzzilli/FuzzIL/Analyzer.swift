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

protocol Analyzer {
    /// Analyzes the next instruction of a program.
    ///
    /// The caller must guarantee that the instructions are given to this method in the correct order.
    mutating func analyze(_ instr: Instruction)
}

extension Analyzer {
    /// Analyze the provided program.
    mutating func analyze(_ program: Program) {
        for instr in program {
            analyze(instr)
        }
    }
}

/// Determines definitions and uses of variables.
struct DefUseAnalyzer: Analyzer {
    private var definitions = VariableMap<Int>()
    private var uses = VariableMap<[Int]>()
    
    let program: Program
    
    init(for program: Program) {
        self.program = program
        analyze(program)
    }

    mutating func analyze(_ instr: Instruction) {
        for v in instr.allOutputs {
            definitions[v] = instr.index
            uses[v] = []
        }
        for v in instr.inputs {
            assert(uses.contains(v))
            uses[v]?.append(instr.index)
        }
    }
    
    /// Returns the instruction defining the given variable.
    func definition(of variable: Variable) -> Instruction {
        precondition(definitions.contains(variable))
        return program[definitions[variable]!]
    }
    
    /// Returns the instructions using the given variable.
    func uses(of variable: Variable) -> [Instruction] {
        precondition(uses.contains(variable))
        return uses[variable]!.map({ program[$0] })
    }
    
    /// Returns the indices of the instructions using the given variable.
    func usesIndices(of variable: Variable) -> [Int] {
        precondition(uses.contains(variable))
        return uses[variable]!
    }
    
    /// Returns the number of instructions using the given variable.
    func numUses(of variable: Variable) -> Int {
        precondition(uses.contains(variable))
        return uses[variable]!.count
    }
}

/// Keeps track of currently visible variables during program construction.
struct ScopeAnalyzer: Analyzer {
    var scopes = [[Variable]()]
    var visibleVariables = [Variable]()
    
    var outerVisibleVariables: ArraySlice<Variable> {
        let end = visibleVariables.count - scopes.last!.count
        return visibleVariables[0..<end]
    }
    
    mutating func analyze(_ instr: Instruction) {
        // Scope management (1).
        if instr.isBlockEnd {
            assert(scopes.count > 0, "Trying to end a scope that was never started")
            let current = scopes.removeLast()
            visibleVariables.removeLast(current.count)
        }
        
        scopes[scopes.count - 1].append(contentsOf: instr.outputs)
        visibleVariables.append(contentsOf: instr.outputs)
        
        // Scope management (2). Happens here since e.g. function definitions create a variable in the outer scope.
        // This code has to be somewhat careful since e.g. BeginElse both ends and begins a variable scope.
        if instr.isBlockBegin {
            scopes.append([])
        }
        
        scopes[scopes.count - 1].append(contentsOf: instr.innerOutputs)
        visibleVariables.append(contentsOf: instr.innerOutputs)
    }
}

/// Keeps track of the current context during program construction.
struct ContextAnalyzer: Analyzer {
    /// Current context in the program
    struct Context: OptionSet {
        let rawValue: Int
        
        // Outer scope, default context
        static let global     = Context([])
        // Inside a function definition
        static let inFunction = Context(rawValue: 1 << 0)
        // Inside a loop
        static let inLoop     = Context(rawValue: 1 << 1)
        // Inside a with statement
        static let inWith     = Context(rawValue: 1 << 2)
    }
    
    private var contextStack = [Context.global]
    
    var context: Context {
        return contextStack.last!
    }
    
    mutating func analyze(_ instr: Instruction) {
        if instr.isLoopEnd ||
            instr.operation is EndFunctionDefinition ||
            instr.operation is EndWith {
            _ = contextStack.popLast()
        } else if instr.isLoopBegin {
            contextStack.append([context, .inLoop])
        } else if instr.operation is BeginFunctionDefinition {
            // Not in a loop or with statement anymore.
            let newContext = context.subtracting([.inLoop, .inWith]).union(.inFunction)
            contextStack.append(newContext)
        } else if instr.operation is BeginWith {
            contextStack.append([context, .inWith])
        }
    }
    
}

/// Determines whether code after the current instruction is dead code (i.e. can never be executed).
struct DeadCodeAnalyzer: Analyzer {
    private var depth = 0
    
    var currentlyInDeadCode: Bool {
        return depth != 0
    }
    
    mutating func analyze(_ instr: Instruction) {
        if instr.isBlockEnd && currentlyInDeadCode {
            depth -= 1
        }
        if instr.isBlockBegin && currentlyInDeadCode {
            depth += 1
        }
        if instr.isJump && !currentlyInDeadCode {
            depth = 1
        }
        assert(depth >= 0)
    }
}
