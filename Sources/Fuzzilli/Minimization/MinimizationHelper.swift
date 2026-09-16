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

    let logger = Logger(withLabel: "MinimizationHelper")

    /// The aspects of the program to preserve during minimization.
    private let aspects: ProgramAspects

    /// The code that is being reduced.
    /// All methods essentially modify this code.
    /// The Minimizer then takes this out of helper with `.finalize()`
    private(set) var code: Code

    /// This signals that the code is not expected to be changed anymore.
    private var finalized = false

    /// Whether we are running on the fuzzer queue (synchronous minimization) or not (asynchronous minimization).
    private let runningOnFuzzerQueue: Bool

    /// How many times we execute the modified code by default to determine whether its (relevant) behaviour has changed due to a modification.
    private static let defaultNumExecutions = 1

    init(
        for aspects: ProgramAspects, forCode code: Code, of fuzzer: Fuzzer,
        runningOnFuzzerQueue: Bool
    ) {
        assert(code.filter({ $0.isNop }).count == 0)
        self.aspects = aspects
        self.fuzzer = fuzzer
        self.runningOnFuzzerQueue = runningOnFuzzerQueue
        self.code = code
    }

    func performOnFuzzerQueue(_ task: () -> Void) {
        if runningOnFuzzerQueue {
            return task()
        } else {
            return fuzzer.sync(do: task)
        }
    }

    func removeNops() {
        assert(!self.finalized)
        code.removeNops()
    }

    /// Returns the final reduced code.
    /// after this, we don't expect the code to change anymore.
    func finalize() -> Code {
        assert(!self.finalized)
        self.finalized = true
        return self.code
    }

    /// Test a reduction and returns true if the reduction was Ok, false otherwise.
    @discardableResult
    func testAndCommit(
        _ newCode: Code, expectCodeToBeValid: Bool = true,
        numExecutions: Int = defaultNumExecutions
    ) -> Bool {
        assert(!self.finalized)
        assert(numExecutions > 0)
        #if DEBUG
            if expectCodeToBeValid {
                newCode.assertIsStaticallyValid()
            }
        #endif

        // Reducers are allowed to nop instructions without verifying whether their outputs are used.
        // They are also allowed to remove blocks without verifying whether their opened contexts are required.
        // Therefore, we need to check if the code is valid here before executing it. This approach is much
        // simpler than forcing reducers to always generate valid code.
        // However, we expect the variables to be numbered continuously. If a reducer reorders variables,
        // it needs to renumber the variables afterwards as the code will otherwise always be rejected.
        totalReductions += 1
        assert(newCode.variablesAreNumberedContinuously())
        guard newCode.isStaticallyValid() else {
            failedReductions += 1
            return false
        }

        // Run the modified program and see if the reduction altered its behaviour
        var stillHasAspects = false
        performOnFuzzerQueue {
            for _ in 0..<numExecutions {
                let execution = fuzzer.execute(
                    Program(with: newCode), withTimeout: fuzzer.config.timeout * 2,
                    purpose: .minimization)
                stillHasAspects = fuzzer.evaluator.hasAspects(execution, aspects)
                guard stillHasAspects else { break }
            }
        }

        if stillHasAspects {
            // Commit this new code to this instance.
            // This will later be the minimized sample.
            self.code = newCode
            didReduce = true
            return true
        } else {
            failedReductions += 1
            return false
        }
    }

    /// Replace the instruction at the given index with the provided replacement if it does not negatively influence the programs previous behaviour.
    /// The replacement instruction must produce the same output variables as the original instruction.
    @discardableResult
    func tryReplacing(
        instructionAt index: Int, with newInstr: Instruction, expectCodeToBeValid: Bool = true,
        numExecutions: Int = defaultNumExecutions
    ) -> Bool {
        var newCode = self.code
        assert(newCode[index].allOutputs == newInstr.allOutputs)
        newCode[index] = newInstr

        return testAndCommit(
            newCode, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
    }

    @discardableResult
    func tryInserting(
        _ newInstr: Instruction, at index: Int, expectCodeToBeValid: Bool = true,
        numExecutions: Int = defaultNumExecutions
    ) -> Bool {
        // For simplicity, just build a copy of the input code here. This logic is not particularly performance sensitive.
        var newCode = Code(isBundle: code.isBundle)
        for instr in code {
            if instr.index == index {
                newCode.append(newInstr)
            }
            newCode.append(instr)
        }

        return testAndCommit(
            newCode, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
    }

    /// Remove the instruction at the given index if it does not negatively influence the programs previous behaviour.
    @discardableResult
    func tryNopping(
        instructionAt index: Int, numExecutions: Int = defaultNumExecutions
    ) -> Bool {
        return tryReplacing(
            instructionAt: index, with: nop(for: code[index]), expectCodeToBeValid: false,
            numExecutions: numExecutions)
    }

    /// Attempt multiple replacements at once.
    @discardableResult
    func tryReplacements(
        _ replacements: [(Int, Instruction)], renumberVariables: Bool = false,
        expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions
    ) -> Bool {
        var newCode = self.code

        for (index, newInstr) in replacements {
            newCode[index] = newInstr
        }

        if renumberVariables {
            newCode.renumberVariables()
        }
        assert(newCode.variablesAreNumberedContinuously())

        return testAndCommit(
            newCode, expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
    }

    @discardableResult
    func tryReplacing(
        range: ClosedRange<Int>, with newCode: [Instruction], renumberVariables: Bool = false,
        expectCodeToBeValid: Bool = true, numExecutions: Int = defaultNumExecutions
    ) -> Bool {
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

        return tryReplacements(
            replacements, renumberVariables: renumberVariables,
            expectCodeToBeValid: expectCodeToBeValid, numExecutions: numExecutions)
    }

    /// Attempt the removal of multiple instructions at once.
    @discardableResult
    func tryNopping(
        _ indices: [Int], expectCodeToBeValid: Bool = false
    ) -> Bool {
        var replacements = [(Int, Instruction)]()
        for index in indices {
            replacements.append((index, nop(for: code[index])))
        }
        return tryReplacements(
            replacements, expectCodeToBeValid: expectCodeToBeValid)
    }

    /// Create a Nop instruction for replacing the given instruction with.
    func nop(for instr: Instruction) -> Instruction {
        // We must preserve outputs here to keep variable number contiguous.
        return Instruction(
            Nop(numOutputs: instr.numOutputs + instr.numInnerOutputs), inouts: instr.allOutputs)
    }
}

protocol Reducer {
    /// Attempt to reduce the given program in some way and return the result.
    ///
    /// The returned program can have non-contiguous variable names but must otherwise be valid.
    func reduce(with tester: MinimizationHelper)
}
