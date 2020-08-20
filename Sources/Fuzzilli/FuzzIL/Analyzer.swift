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
    
    /// Resets the state of the analyzer.
    mutating func reset()
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
    
    mutating func reset() {
        definitions.removeAll()
        uses.removeAll()
    }
}

/// Keeps track of currently visible variables during program construction.
struct ScopeAnalyzer: Analyzer {
    var scopes = [[Variable]()]
    var visibleVariables = [Variable]()
 
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
    
    mutating func reset() {
        scopes = [[]]
        visibleVariables.removeAll()
    }
}

/// Current context in the program
public struct ProgramContext: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // Outer scope, default context
    public static let global            = ProgramContext([])
    // Inside a function definition
    public static let function          = ProgramContext(rawValue: 1 << 0)
    // Inside a generator function definition
    public static let generatorFunction = ProgramContext(rawValue: 1 << 1)
    // Inside an async function definition
    public static let asyncFunction     = ProgramContext(rawValue: 1 << 2)
    // Inside a loop
    public static let loop              = ProgramContext(rawValue: 1 << 3)
    // Inside a with statement
    public static let with              = ProgramContext(rawValue: 1 << 4)
    
    public static let empty             = ProgramContext([])
    public static let any               = ProgramContext([.global, .function, .generatorFunction, .asyncFunction, .loop, .with])
}

/// Keeps track of the current context during program construction.
struct ContextAnalyzer: Analyzer {
    private var contextStack = [ProgramContext.global]
    
    var context: ProgramContext {
        return contextStack.last!
    }
    
    mutating func analyze(_ instr: Instruction) {
        if instr.isLoopEnd ||
            instr.operation is EndAnyFunctionDefinition ||
            instr.operation is EndWith {
            _ = contextStack.popLast()
        } else if instr.isLoopBegin {
            contextStack.append([context, .loop])
        } else if instr.operation is BeginAnyFunctionDefinition {
            // Not in a loop or with statement anymore.
            var newContext = context.subtracting([.loop, .with]).union(.function)
            if instr.operation is BeginGeneratorFunctionDefinition {
                newContext.formUnion(.generatorFunction)
            } else if instr.operation is BeginAsyncFunctionDefinition {
                newContext.formUnion(.asyncFunction)
            }
            contextStack.append(newContext)
        } else if instr.operation is BeginWith {
            contextStack.append([context, .with])
        }
    }
    
    mutating func reset() {
        contextStack = [ProgramContext.global]
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
    
    mutating func reset() {
        depth = 0
    }
}
