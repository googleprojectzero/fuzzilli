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

/// The MinimizationHelper provides functions for testing whether a code change alters the programs interesting behaviour. It also provides access to the fuzzer instance for executing programs or other tasks.
class MinimizationHelper {
    var totalReductions = 0
    var failedReductions = 0
    var didReduce = false

    /// Fuzzer instance to schedule execution of programs on.
    let fuzzer: Fuzzer

    /// The aspects of the program to preserve during minimization.
    private let aspects: ProgramAspects

    /// Whether we are running on the fuzzer queue (synchronous minimization) or not (asynchronous minimization).
    private let runningOnFuzzerQueue: Bool

    /// The minimizer can select instructions that should be kept regardless of whether they are important or not. This set tracks those instructions.
    private var instructionsToKeep: Set<Int>

    /// How many times we execute the modified code by default to determine whether its (relevant) behaviour has changed due to a modification.
    private static let defaultNumExecutions = 1

    init(for aspects: ProgramAspects, of fuzzer: Fuzzer, keeping instructionsToKeep: Set<Int>, runningOnFuzzerQueue: Bool) {
        self.aspects = aspects
        self.fuzzer = fuzzer
        self.instructionsToKeep = instructionsToKeep
        self.runningOnFuzzerQueue = runningOnFuzzerQueue
    }

    func performOnFuzzerQueue(_ task: () -> Void) {
        if runningOnFuzzerQueue {
            return task()
        } else {
            return fuzzer.sync(do: task)
        }
    }

    func clearInstructionsToKeep() {
        instructionsToKeep.removeAll()
    }

    /// Test a reduction and return true if the reduction was Ok, false otherwise.
    func test(_ code: Code, expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions) -> Bool {
        assert(numExecutions > 0)
        assert(!expectCodeToBeValid || code.isStaticallyValid())

        // Reducers are allowed to nop instructions without verifying whether their outputs are used.
        // They are also allowed to remove blocks without verifying whether their opened contexts are required.
        // Therefore, we need to check if the code is valid here before executing it. This approach is much
        // simpler than forcing reducers to always generate valid code.
        // However, we expect the variables to be numbered continuously. If a reducer reorders variables,
        // it needs to renumber the variables afterwards as the code will otherwise always be rejected.
        assert(code.variablesAreNumberedContinuously())
        guard code.isStaticallyValid() else { return false }

        totalReductions += 1

        // Run the modified program and see if the patch changed its behaviour
        var stillHasAspects = false
        performOnFuzzerQueue {
            for _ in 0..<numExecutions {
                let execution = fuzzer.execute(Program(with: code), withTimeout: fuzzer.config.timeout * 2)
                stillHasAspects = fuzzer.evaluator.hasAspects(execution, aspects)
                guard stillHasAspects else { break }
            }
        }

        if stillHasAspects {
            didReduce = true
        } else {
            failedReductions += 1
        }

        return stillHasAspects
    }

    /// Replace the instruction at the given index with the provided replacement if it does not negatively influence the programs previous behaviour.
    /// The replacement instruction must produce the same output variables as the original instruction.
    @discardableResult
    func tryReplacing(instructionAt index: Int, with newInstr: Instruction, in code: inout Code, expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions) -> Bool {
        assert(code[index].allOutputs == newInstr.allOutputs)

        guard !instructionsToKeep.contains(index) else {
            return false
        }

        let origInstr = code[index]
        code[index] = newInstr

        let result = test(code, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)

        if !result {
            // Revert change
            code[index] = origInstr
        }

        return result
    }

    @discardableResult
    func tryInserting(_ newInstr: Instruction, at index: Int, in code: inout Code, expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions) -> Bool {
        // Inserting instructions will invalidate the instructionsToKeep list, so that list must be empty here.
        assert(instructionsToKeep.isEmpty)

        // For simplicity, just build a copy of the input code here. This logic is not particularly performance sensitive.
        var newCode = Code()
        for instr in code {
            if instr.index == index {
                newCode.append(newInstr)
            }
            newCode.append(instr)
        }

        let result = test(newCode, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)

        if result {
            code = newCode
        }

        return result
    }

    /// Remove the instruction at the given index if it does not negatively influence the programs previous behaviour.
    @discardableResult
    func tryNopping(instructionAt index: Int, in code: inout Code, numExecutions: Int = defaultNumExecutions) -> Bool {
        return tryReplacing(instructionAt: index, with: nop(for: code[index]), in: &code, expectCodeToBeValid: false, numExecutions: numExecutions)
    }

    /// Attempt multiple replacements at once.
    @discardableResult
    func tryReplacements(_ replacements: [(Int, Instruction)], in code: inout Code, renumberVariables: Bool = false, expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions) -> Bool {
        let originalCode = code

        for (index, newInstr) in replacements {
            if instructionsToKeep.contains(index) {
                code = originalCode
                return false
            }
            code[index] = newInstr
        }

        if renumberVariables {
            code.renumberVariables()
        }
        assert(code.variablesAreNumberedContinuously())

        let result = test(code, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
        if !result {
            code = originalCode
        }

        assert(code.isStaticallyValid())
        return result
    }

    @discardableResult
    func tryReplacing(range: ClosedRange<Int>, in code: inout Code, with newCode: [Instruction], renumberVariables: Bool = false, expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions) -> Bool {
        assert(range.count >= newCode.count)

        var replacements = [(Int, Instruction)]()
        for indexOfInstructionToReplace in range {
            let indexOfReplacementInstruction = indexOfInstructionToReplace - range.lowerBound
            let replacement: Instruction
            if newCode.indices.contains(indexOfReplacementInstruction) {
                replacement = newCode[indexOfReplacementInstruction]
            } else {
                // Pad with Nops if necessary
                replacement = Instruction(Nop())
            }
            replacements.append((indexOfInstructionToReplace, replacement))
        }

        return tryReplacements(replacements, in: &code, renumberVariables: renumberVariables, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
    }

    /// Attempt the removal of multiple instructions at once.
    @discardableResult
    func tryNopping(_ indices: [Int], in code: inout Code, expectCodeToBeValid: Bool = false) -> Bool {
        var replacements = [(Int, Instruction)]()
        for index in indices {
            replacements.append((index, nop(for: code[index])))
        }
        return tryReplacements(replacements, in: &code, expectCodeToBeValid: false)
    }

    /// Create a Nop instruction for replacing the given instruction with.
    func nop(for instr: Instruction) -> Instruction {
        // We must preserve outputs here to keep variable number contiguous.
        return Instruction(Nop(numOutputs: instr.numOutputs + instr.numInnerOutputs), inouts: instr.allOutputs)
    }
}

protocol Reducer {
    /// Attempt to reduce the given program in some way and return the result.
    ///
    /// The returned program can have non-contiguous variable names but must otherwise be valid.
    func reduce(_ code: inout Code, with tester: MinimizationHelper)
}
