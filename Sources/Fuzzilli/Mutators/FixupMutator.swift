// Copyright 2023 Google LLC
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

import Foundation

/// Mutator to fix invalid or "boring" code.
///
/// This attempts to "fix" the following things:
///   * Guarded operations that don't raise an exception are converted to unguarded ones (i.e. it drops try-catch when not needed)
///   * Accesses to non-existent properties/elements (or where the access raises an exception) (TODO)
///   * Invalid function-, method-, or constructor calls (for example if the callee is not a function or if arguments are invalid) (TODO)
///   * Superfluous try-catch statements (when no exception is thrown) (TODO)
///   * Arithmetic operations producing NaN, indicating that no meaningful operation was performed (TODO)
///
/// This mutator works as follows:
/// 1. Convert "fixable" instructions into JavaScript Actions (see RuntimeAssistedMutator) and replace them with Fixup instructions (which contain the respective Action)
/// 2. Execute the instrumented program in the target JavaScript engine
/// 3. On the JavaScript side, when executing a Fixup operation, inspect the associated Action and determine if it can/should be modified (for example by replacing a non-existent property/method with an existing one in a property access/method call), then execute the Action (at which point we can determine if a try-catch is needed for it)
/// 4. Finally, send the modified Actions back to Fuzzilli which will replace the Fixup instructions with the (potentially modified) Actions to generate the final program.
///
public class FixupMutator: RuntimeAssistedMutator {
    // If true, this mutator will log detailed statistics like how often each type of operation was performend.
    private static let verbose = true

    // The FixupMutator will attempt to fix all guarded instructions (to hopefully remove the guards) and this percentage of unguarded (but fixable) instructions.
    private let probabilityOfFixingUnguardedInstruction = 0.5

    // Average success rate: the rate of guarded operations that were turned into unguarded ones, including any try-catch blocks that were removed entirely.
    private var averageSuccesRate = MovingAverage(n: 1000)

    // The ratio of instrumented instructions compared to the total size of the input program.
    private var averageInstrumentationRatio = MovingAverage(n: 1000)

    // For every operation supported by this mutator, the number of times that we've converted such an operation into a Fixup operation.
    // Only used in verbose mode for statistics.
    private var instrumentedOperations = [String: Int]()

    // For every operation supported by this mutator, the number of times that we've converted such an operation with an enabled guard into a Fixup operation.
    // Only used in verbose mode for statistics.
    private var instrumentedGuardedOperations = [String: Int]()

    // For every operation supported by this mutator, the number of times we've modified such an operation during fixup.
    // Only used in verbose mode for statistics
    private var modifiedOperations = [String: Int]()

    public init(name: String? = nil) {
        super.init(name ?? "FixupMutator", verbose: FixupMutator.verbose)
    }

    override func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        let b = fuzzer.makeBuilder()

        // Helper functions to emit the Fixup operations.
        var numInstrumentedInstructions = 0
        let actionEncoder = JSONEncoder()
        func fixup(_ instr: Instruction, performing op: ActionOperation, guarded: Bool, withInputs inputs: [Action.Input], with b: ProgramBuilder) {
            assert(instr.numOutputs == 0 || instr.numOutputs == 1)
            assert(instr.numInnerOutputs == 0)
            assert(inputs.allSatisfy({ if case .argument(let index) = $0 { return index < instr.numInputs } else { return true }}))

            numInstrumentedInstructions += 1

            let id = "instr\(instr.index)"
            let action = Action(id: id, operation: op, inputs: inputs, isGuarded: guarded)
            let encodedData = try! actionEncoder.encode(action)
            let encodedAction = String(data: encodedData, encoding: .utf8)!
            let maybeOutput = b.fixup(id: id, action: encodedAction, originalOperation: instr.op.name, arguments: Array(instr.inputs), hasOutput: instr.hasOneOutput)
            // The fixup instruction must create the same output variable, as that may be used by subsequent code.
            assert(!instr.hasOutputs || instr.output == maybeOutput)

            if verbose {
                instrumentedOperations[instr.op.name] = (instrumentedOperations[instr.op.name] ?? 0) + 1
                if instr.isGuarded {
                    instrumentedGuardedOperations[instr.op.name] = (instrumentedGuardedOperations[instr.op.name] ?? 0) + 1
                }
            }
        }

        func maybeFixup(_ instr: Instruction, performing op: ActionOperation, guarded: Bool, withInputs inputs: [Action.Input], with b: ProgramBuilder) {
            // Only instrument some percentage of unguarded instructions but do still instrument all guarded instructions (to attempt to remove the guards).
            if !guarded {
                if !probability(probabilityOfFixingUnguardedInstruction) {
                    b.append(instr)
                    return
                }
            }

            fixup(instr, performing: op, guarded: guarded, withInputs: inputs, with: b)
        }

        func fixupIfGuarded(_ instr: Instruction, performing op: ActionOperation, guarded: Bool, withInputs inputs: [Action.Input], with b: ProgramBuilder) {
            guard guarded else {
                b.append(instr)
                return
            }

            fixup(instr, performing: op, guarded: guarded, withInputs: inputs, with: b)
        }

        for instr in program.code {
            switch instr.op.opcode {

            // We only attempt to fix guarded function/constructor calls as we assume that unguarded ones are probably doing something meaningful.
            // For example, for unguarded calls we know that the function/constructor must be callable (or the call must be dead code), since otherwise an
            // exception would be raised.
            case .callFunction(let op):
                let inputs = (0..<instr.numInputs).map({ Action.Input.argument(index: $0) })
                fixupIfGuarded(instr, performing: .CallFunction, guarded: op.isGuarded, withInputs: inputs, with: b)

            case .construct(let op):
                let inputs = (0..<instr.numInputs).map({ Action.Input.argument(index: $0) })
                fixupIfGuarded(instr, performing: .Construct, guarded: op.isGuarded, withInputs: inputs, with: b)

            // For method calls, we also instrument some of the unguarded ones as we may be calling a "boring" method (e.g. one from the Object.prototype)
            // as we lacked knowledge of more interesting methods during static code generation.
            case .callMethod(let op):
                let arguments = (1..<instr.numInputs).map({ Action.Input.argument(index: $0) })
                maybeFixup(instr, performing: .CallMethod, guarded: op.isGuarded, withInputs: [.argument(index: 0), .string(value: op.methodName)] + arguments, with: b)

            case .callComputedMethod(let op):
                let arguments = (2..<instr.numInputs).map({ Action.Input.argument(index: $0) })
                maybeFixup(instr, performing: .CallMethod, guarded: op.isGuarded, withInputs: [.argument(index: 0), .argument(index: 1)] + arguments, with: b)

            // TODO: We cannot currently convert spread calls into Actions.
            case .callFunctionWithSpread,
                 .constructWithSpread,
                 .callMethodWithSpread,
                 .callComputedMethodWithSpread:
                b.append(instr)

            // We attempt to fix all guarded property operations and some percentage of the unguarded since as "meaningless" property accesses (such as
            // loads of non-existent properties) will not raise an exception.
            case .getProperty(let op):
                maybeFixup(instr, performing: .GetProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .string(value: op.propertyName)], with: b)

            case .deleteProperty(let op):
                maybeFixup(instr, performing: .DeleteProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .string(value: op.propertyName)], with: b)

            case .getElement(let op):
                maybeFixup(instr, performing: .GetProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .int(value: op.index)], with: b)

            case .deleteElement(let op):
                maybeFixup(instr, performing: .DeleteProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .int(value: op.index)], with: b)

            case .getComputedProperty(let op):
                maybeFixup(instr, performing: .GetProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .argument(index: 1)], with: b)

            case .deleteComputedProperty(let op):
                maybeFixup(instr, performing: .DeleteProperty, guarded: op.isGuarded, withInputs: [.argument(index: 0), .argument(index: 1)], with: b)

            default:
                // At least all guardable operations should be handled by this mutator.
                assert(!(instr.op is GuardableOperation), "FixupMutator should handle guardable operation \(instr.op)")

                b.append(instr)
            }
        }

        guard numInstrumentedInstructions > 0 else {
            return nil
        }

        averageInstrumentationRatio.add(Double(numInstrumentedInstructions) / Double(program.size))

        let instrumentedProgram = b.finalize()
        // We assume that the number of instructions doesn't change during instrumentation since
        // we use instruction indices as IDs for the fixup operations.
        assert(instrumentedProgram.size == program.size)
        return instrumentedProgram
    }

    override func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, RuntimeAssistedMutator.Outcome) {
        // For each Fixup operation (identified by its Id), this dict contains the (potentially modified) action that was performed by it.
        var actions = [String: Action]()

        let actionDecoder = JSONDecoder()
        // Populate the actions map with the original actions. This way, we can verify that the received (updated) actions all belong to a Fixup operation.
        for instr in instrumentedProgram.code {
            if let op = instr.op as? Fixup {
                guard let originalAction = try? actionDecoder.decode(Action.self, from: op.action.data(using: .utf8)!) else {
                    logger.error("Failed to decode original action \"\(op.action)\"")
                    return (nil, .unexpectedError)
                }
                actions[op.id] = originalAction
            }
        }

        // Remember the number of guarded instructions before fixup, used to compute the "success rate" below.
        let originalNumberOfGuardedInstructions = actions.values.filter({ $0.isGuarded }).count
        // Also remember which actions were modified for statistical purposes.
        var modifiedActions = Set<String>()

        // Parse the output: look for "FIXUP_ACTION", "FIXUP_FAILURE", and "FIXUP_ERROR":
        // * a FIXUP_ACTIONS contains the actual action that was executed at runtime, which may be different from the original action as the fixup code may have modified it
        // * a FIXUP_FAILURE indicates that an unguarded (likely because the guard was removed when the action was executed the first time) action has raised an exception at least once.
        // * a FIXUP_ERROR indicates that a runtime exception was raised by the fixup logic, which may indicate a bug in the JavaScript implementation.
        var seenActions = Set<String>()
        var seenFailures = Set<String>()
        for line in output.split(whereSeparator: \.isNewline) where line.starts(with: "FIXUP") {
            let actionMarker = "FIXUP_ACTION: "
            let failureMarker = "FIXUP_FAILURE: "
            let errorMarker = "FIXUP_ERROR: "

            if line.hasPrefix(errorMarker) {
                if isKnownRuntimeError(line) { return (nil, .instrumentedProgramFailed) }
                // Everything else is unexpected and probably means that there's a bug in the JavaScript implementation, so treat that as an error.
                logger.error("Fixup failed: \(line.dropFirst(errorMarker.count))")
                // We could still continue here, but since this case is unexpected, it may be better to log this as a failure in our statistics.
                return (nil, .unexpectedError)
            } else if line.hasPrefix(failureMarker) {
                let id = line.dropFirst(failureMarker.count).trimmingCharacters(in: .whitespaces)
                guard let action = actions[id] else {
                    logger.error("Unknown id for FIXUP_FAILURE: \(id)")
                    return (nil, .unexpectedError)
                }
                guard !seenFailures.contains(id) else {
                    logger.error("Observed duplicate FIXUP_FAILURE for operation at \(id)")
                    return (nil, .unexpectedError)
                }
                seenFailures.insert(id)
                // We could also drop this action or replace it with a different one, but for now, simply add the guard back if we observe a failure.
                actions[id] = Action(id: action.id, operation: action.operation, inputs: action.inputs, isGuarded: true)
            } else if line.hasPrefix(actionMarker) {
                let payload = Data(line.dropFirst(actionMarker.count).utf8)
                guard let action = try? actionDecoder.decode(Action.self, from: payload) else {
                    logger.error("Failed to decode JSON payload in \"\(line)\"")
                    return (nil, .unexpectedError)
                }
                guard actions.keys.contains(action.id) else {
                    logger.error("Invalid ID for FIXUP_ACTION: \(action.id)")
                    return (nil, .unexpectedError)
                }
                guard !seenActions.contains(action.id) else {
                    logger.error("Duplicate action for \(action.id)")
                    return (nil, .unexpectedError)
                }
                if verbose && actions[action.id] != action {
                    // We must've modified this operation in some way.
                    modifiedActions.insert(action.id)
                }
                seenActions.insert(action.id)
                actions[action.id] = action
            } else {
                logger.error("Invalid fixup result: \(line)")
                return (nil, .unexpectedError)
            }
        }

        // If we didn't get any (modified) actions back, then we'd just re-create the original program. So fail the mutation instead.
        guard !seenActions.isEmpty else {
            return (nil, .noResults)
        }

        // The success rate is simply the percentage of removed guards (i.e. if we had 100 guarded instructions and now only have 25, then our success rate is 75%).
        // Note that this could theoretically be negative if guards are _added_, e.g. if previously unguarded instructions now fail, maybe due to changes to preceeding instructions.
        // If we didn't have any guarded operations to start with, then there is no success rate, so skip it in that case.
        if originalNumberOfGuardedInstructions != 0 {
            let newNumberOfGuardedInstructions = actions.values.filter({ $0.isGuarded }).count
            let difference = originalNumberOfGuardedInstructions - newNumberOfGuardedInstructions
            let successRate = Double(difference) / Double(originalNumberOfGuardedInstructions)
            averageSuccesRate.add(successRate)
        }

        // Now build the real program by replacing every Fixup operation with either the new (if we got one) or original Action.
        for instr in instrumentedProgram.code {
            if let op = instr.op as? Fixup {
                assert(actions.keys.contains(op.id))
                let action = actions[op.id]!
                let args = Array(instr.inputs)
                b.trace("Fixing next instruction")
                do {
                    try action.translateToFuzzIL(withContext: (arguments: args, specialValues: [:]), using: b)
                    assert(!op.hasOutput || b.visibleVariables.last == instr.output)
                    assert(op.originalOperation == b.lastInstruction().op.name)         // We expect the old and new operations to be the same (but potentially performed on different inputs)
                } catch ActionError.actionTranslationError(let msg) {
                    logger.error("Failed to process action: \(msg)")
                } catch {
                    logger.error("Unexpected error during action processing \(error)")
                }
                b.trace("Fixup done")
                if verbose && modifiedActions.contains(action.id) {
                    modifiedOperations[op.originalOperation] = (modifiedOperations[op.originalOperation] ?? 0) + 1
                }
            } else {
                b.append(instr)
            }
        }

        // All finished!
        return (b.finalize(), .success)
    }

    override func logAdditionalStatistics() {
        logger.verbose("Average success rate (percentage of removed guards) during recent mutations: \(String(format: "%.2f", averageSuccesRate.currentValue * 100))%")
        logger.verbose("Average percentage of instrumented instructions: \(String(format: "%.2f", averageInstrumentationRatio.currentValue * 100))%")
        logger.verbose("Per-operation statistics:")
        for (opName, count) in instrumentedOperations {
            let guardedRatio = Double(instrumentedGuardedOperations[opName] ?? 0) / Double(count)
            let modificationRate = Double(modifiedOperations[opName] ?? 0) / Double(count)
            logger.verbose("    \(opName.rightPadded(toLength: 30)): instrumented \(count) times (of which \(String(format: "%.2f", guardedRatio * 100))% were guarded), modification rate: \(String(format: "%.2f", modificationRate * 100))%")
        }
    }
}
