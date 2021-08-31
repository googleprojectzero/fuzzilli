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
        analyze(program.code)
    }
    
    mutating func analyze(_ code: Code) {
        assert(code.isStaticallyValid())
        for instr in code {
            analyze(instr)
        }
    }
}

/// Determines definitions, assignments, and uses of variables.
struct VariableAnalyzer: Analyzer {
    private var assignments = VariableMap<[Int]>()
    private var uses = VariableMap<[Int]>()
    private let code: Code
    private var analysisDone = false
    
    init(for program: Program) {
        self.code = program.code
        analyze(program)
        analysisDone = true
    }
    
    mutating func analyze(_ instr: Instruction) {
        assert(!analysisDone)
        for v in instr.allOutputs {
            assignments[v] = [instr.index]
            uses[v] = []
        }
        for v in instr.inputs {
            assert(uses.contains(v))
            uses[v]?.append(instr.index)
            if instr.reassigns(v) {
                assignments[v]?.append(instr.index)
            }
        }
    }
    
    /// Returns the instruction that defines the given variable.
    func definition(of variable: Variable) -> Instruction {
        assert(assignments.contains(variable))
        return code[assignments[variable]![0]]
    }
    
    /// Returns all instructions that assign the given variable, including its initial definition.
    func assignments(of variable: Variable) -> [Instruction] {
        assert(assignments.contains(variable))
        return assignments[variable]!.map({ code[$0] })
    }
    
    /// Returns the instructions using the given variable.
    func uses(of variable: Variable) -> [Instruction] {
        assert(uses.contains(variable))
        return uses[variable]!.map({ code[$0] })
    }
    
    /// Returns the indices of the instructions using the given variable.
    func assignmentIndices(of variable: Variable) -> [Int] {
        assert(uses.contains(variable))
        return assignments[variable]!
    }
    
    /// Returns the indices of the instructions using the given variable.
    func usesIndices(of variable: Variable) -> [Int] {
        assert(uses.contains(variable))
        return uses[variable]!
    }
    
    /// Returns the number of instructions using the given variable.
    func numAssignments(of variable: Variable) -> Int {
        assert(assignments.contains(variable))
        return assignments[variable]!.count
    }
    
    /// Returns the number of instructions using the given variable.
    func numUses(of variable: Variable) -> Int {
        assert(uses.contains(variable))
        return uses[variable]!.count
    }
}

/// Keeps track of currently visible variables during program construction.
struct ScopeAnalyzer: Analyzer {
    private(set) var scopes = [[Variable]()]
    private(set) var visibleVariables = [Variable]()

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

/// Current context in the program
public struct ProgramContext: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // Default script context
    public static let script            = ProgramContext([])
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
    // Inside a class definition
    public static let classDefinition   = ProgramContext(rawValue: 1 << 5)
    
    public static let empty             = ProgramContext([])
    public static let any               = ProgramContext([.script, .function, .generatorFunction, .asyncFunction, .loop, .with, .classDefinition])
}

/// Keeps track of the current context during program construction.
struct ContextAnalyzer: Analyzer {
    private var contextStack = [ProgramContext.script]
    
    var context: ProgramContext {
        return contextStack.last!
    }
    
    mutating func analyze(_ instr: Instruction) {
        if instr.isLoopEnd ||
            instr.op is EndAnyFunctionDefinition ||
            instr.op is EndWith ||
            instr.op is EndClassDefinition {
            _ = contextStack.popLast()
        } else if instr.isLoopBegin {
            contextStack.append([context, .loop])
        } else if instr.op is BeginAnyFunctionDefinition {
            // We are no longer in the previous context
            var newContext = ProgramContext([.function])
            if instr.op is BeginGeneratorFunctionDefinition {
                newContext.formUnion(.generatorFunction)
            } else if instr.op is BeginAsyncFunctionDefinition ||
                instr.op is BeginAsyncArrowFunctionDefinition {
                newContext.formUnion(.asyncFunction)
            } else if instr.op is BeginAsyncGeneratorFunctionDefinition {
                newContext.formUnion([.asyncFunction, .generatorFunction])
            }
            contextStack.append(newContext)
        } else if instr.op is BeginWith {
            contextStack.append([context, .with])
        } else if instr.op is BeginClassDefinition {
            // We are no longer in the previous context
            contextStack.append([.classDefinition, .function])
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
