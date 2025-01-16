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
struct DefUseAnalyzer: Analyzer {
    private var assignments = VariableMap<[Int]>()
    private var uses = VariableMap<[Int]>()
    private let code: Code
    private var analysisDone = false

    init(for program: Program) {
        self.code = program.code
    }

    mutating func finishAnalysis() {
        analysisDone = true
    }

    mutating func analyze() {
        analyze(code)
        finishAnalysis()
    }

    mutating func analyze(_ instr: Instruction) {
        assert(code[instr.index].op === instr.op)    // Must be operating on the program passed in during construction
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
struct VariableAnalyzer: Analyzer {
    private(set) var visibleVariables = [Variable]()
    private(set) var scopes = Stack<Int>([0])

    /// Track the current maximum branch depth. Note that some wasm blocks are not valid branch targets
    // (catch, catch_all) and therefore don't contribute to the branch depth.
    private(set) var wasmBranchDepth = 0

    mutating func analyze(_ instr: Instruction) {
        // Scope management (1).
        if instr.isBlockEnd {
            assert(scopes.count > 0, "Trying to end a scope that was never started")
            let variablesInClosedScope = scopes.pop()
            visibleVariables.removeLast(variablesInClosedScope)

            if instr.op is WasmOperation {
                assert(wasmBranchDepth > 0)
                wasmBranchDepth -= 1
            }
        }

        scopes.top += instr.numOutputs
        visibleVariables.append(contentsOf: instr.outputs)

        // Scope management (2). Happens here since e.g. function definitions create a variable in the outer scope.
        // This code has to be somewhat careful since e.g. BeginElse both ends and begins a variable scope.
        if instr.isBlockStart {
            scopes.push(0)
            if instr.op is WasmOperation {
                wasmBranchDepth += 1
            }
        }

        scopes.top += instr.numInnerOutputs
        visibleVariables.append(contentsOf: instr.innerOutputs)
    }
}

/// Keeps track of the current context during program construction.
struct ContextAnalyzer: Analyzer {
    private var contextStack = Stack([Context.javascript])

    var context: Context {
        return contextStack.top
    }

    mutating func analyze(_ instr: Instruction) {
        if instr.isBlockEnd {
            contextStack.pop()
        }
        if instr.isBlockStart {
            var newContext = instr.op.contextOpened
            if instr.propagatesSurroundingContext {
                newContext.formUnion(context)
            }

            // If we resume the context analysis, we currently take the second to last context.
            // This currently only works if we have a single layer of these instructions.
            if instr.skipsSurroundingContext {
                assert(!instr.propagatesSurroundingContext)
                assert(contextStack.count >= 2)

                // Currently we only support context "skipping" for switch blocks. This logic may need to be refined if it is ever used for other constructs as well.
                assert((contextStack.top.contains(.switchBlock) && contextStack.top.subtracting(.switchBlock) == .empty))

                newContext.formUnion(contextStack.secondToTop)
            }
            
            // If we are in a loop, we don't want to propagate the switch context and vice versa. Otherwise we couldn't determine which break operation to emit.
            // TODO Make this generic for similar logic cases as well. E.g. by using a instr.op.contextClosed list.
            if (instr.op.contextOpened.contains(.switchBlock) || instr.op.contextOpened.contains(.switchCase)) {
                newContext.remove(.loop)
            } else if (instr.op.contextOpened.contains(.loop)) {
                newContext.remove(.switchBlock) 
                newContext.remove(.switchCase)
            }
            contextStack.push(newContext)
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
        if instr.isBlockStart && currentlyInDeadCode {
            depth += 1
        }
        if instr.isJump && !currentlyInDeadCode {
            depth = 1
        }
        assert(depth >= 0)
    }
}
