// Copyright 2022 Google LLC
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

/// This mutator explores what can be done with existing variables in a program.
///
/// It's main purpose is to figure out what can be done with variables whose precise type cannot be statically determined and to
/// find any features not included in the environment model (e.g. new builtins or new properties/methods on certain object types).
///
/// This mutator achieves this by doing the following:
/// 1. It instruments the given program by inserting special "Explore" operations for existing variables.
/// 2. It executes the resulting (intermediate) program. The Explore operations will be lifted
///   to a call to a chunk of code that inspects the variable at runtime (using features like 'typeof' and
///   'Object.getOwnPropertyNames' in JavaScript) and selects a "useful" action to perform on it
///   (e.g. load a property, call a method, ...). At the end or program execution, all these "actions"
///   are reported back to Fuzzilli through the special FUZZOUT channel.
/// 3. The mutator processes the output of step 2 and replaces all successful Explore operations with the concrete
///   action that was performed by them at runtime (so for example a GetProperty or CallMethod operation)
///
/// The result is a program that performs useful actions on some of the existing variables even without
/// statically knowing their type. The resulting program is also deterministic and "JIT friendly" as it
/// no longer relies on any kind of runtime object inspection.
///
/// A large bit of the logic of this mutator is located in the lifter code that implements Explore operations
/// in the target language. For JavaScript, that logic can be found in JavaScriptExploreLifting.swift.
public class ExplorationMutator: RuntimeAssistedMutator {
    // If true, this mutator will log detailed statistics like how often each type of operation was performend.
    private static let verbose = true

    // How often each of the possible actions was performed during exploration, used only in verbose mode.
    private var actionUsageCounts = [ActionOperation: Int]()

    // Track the average number of inserted explore operations, for statistical purposes.
    private var averageNumberOfInsertedExploreOps = MovingAverage(n: 1000)

    public init() {
        super.init("ExplorationMutator", verbose: ExplorationMutator.verbose)
        if verbose {
            for op in ActionOperation.allCases {
                actionUsageCounts[op] = 0
            }
        }
    }

    override func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        let b = fuzzer.makeBuilder()

        // Enumerate all variables in the program and put them into one of two buckets, depending on whether static type information is available for them.
        var untypedVariables = [Variable]()
        var typedVariables = [Variable]()
        for instr in program.code {
            b.append(instr)

            // Since we need additional arguments for Explore, only explore when we have a couple of visible variables.
            guard b.numberOfVisibleVariables > 3 else { continue }

            // TODO: we currently don't want to explore anything in the wasm world.
            // We might want to change this to explore the functions that the Wasm module emits.
            guard !(instr.op is WasmOperation) else { continue }

            for v in instr.allOutputs {
                if b.type(of: v) == .anything || b.type(of: v) == .unknownObject {
                    untypedVariables.append(v)
                } else {
                    typedVariables.append(v)
                }
            }
        }

        // Select a number of random variables to explore. Prefer to explore variables whose type is unknown.
        let numUntypedVariablesToExplore = Int((Double(untypedVariables.count) * 0.5).rounded(.up))
        // TODO probably we only rarely want to explore known variables (e.g. only 10% of them or even fewer). But currently, the JSTyper and JavaScriptEnvironment still often set the type to something like .object() or so, which isn't very useful (it's basically a "unknownObject" type). We should maybe stop doing that...
        let numTypedVariablesToExplore = Int((Double(typedVariables.count) * 0.25).rounded(.up))
        let untypedVariablesToExplore = untypedVariables.shuffled().prefix(numUntypedVariablesToExplore)
        let typedVariablesToExplore = typedVariables.shuffled().prefix(numTypedVariablesToExplore)
        let variablesToExplore = VariableSet(untypedVariablesToExplore + typedVariablesToExplore)
        guard !variablesToExplore.isEmpty else {
            return nil
        }

        // Finally construct the instrumented program that contains the Explore operations.
        b.reset()

        // Helper function for inserting the Explore operation.
        func explore(_ v: Variable) {
            let args = b.randomVariables(upTo: 5)
            assert(args.count > 0)
            b.explore(v, id: v.identifier, withArgs: args)
        }
        // When we want to explore the (outer) output of a block (e.g. a function or a class), we only want to perform the
        // explore operation after the block has been closed, and not inside the block (for functions, because that'll quickly
        // lead to unchecked recursion, for classes because we don't have .javascript context in the class body, and in
        // general because it's probably not what makes sense semantically).
        // For that reason, we keep a stack of variables that still need to be explored. A variable in that stack is explored
        // when its entry is popped from the stack, which happens when the block end instruction is emitted.
        var pendingExploreStack = Stack<Variable?>()
        b.adopting(from: program) {
            for instr in program.code {
                b.adopt(instr)

                if instr.isBlockGroupStart {
                    // Will be replaced with a variable if one needs to be explored.
                    pendingExploreStack.push(nil)
                } else if instr.isBlockGroupEnd {
                    // Emit pending explore operation if any.
                    if let v = pendingExploreStack.pop() {
                        explore(v)
                    }
                }

                for v in instr.outputs where variablesToExplore.contains(v) {
                    // When the current instruction starts a new block, we defer exploration until after that block is closed.
                    if instr.isBlockStart {
                        // Currently we assume that inner block instructions don't have (outer) outputs. If they ever do, this logic probably needs to be revisited.
                        assert(instr.isBlockGroupStart)
                        // We currently assume that there can only be one such pending variable. If there are ever multiple ones, the stack simply needs to keep a list of Variables instead of a single one.
                        assert(pendingExploreStack.top == nil)
                        pendingExploreStack.top = v
                    } else {
                        explore(v)
                    }
                }
                for v in instr.innerOutputs where variablesToExplore.contains(v) {
                    // We always immediately explore inner outputs
                    explore(v)
                }
            }
        }

        let instrumentedProgram = b.finalize()
        let numberOfInsertedExploreOps = instrumentedProgram.code.filter({ $0.op is Explore }).count
        averageNumberOfInsertedExploreOps.add(Double(numberOfInsertedExploreOps))
        return instrumentedProgram
    }

    override func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, Outcome) {
        // Initialize the actions dictionary that will contain the processed results.
        // This way, we can detect if something went wrong on the JS side: if we get results for IDs
        // for which there is no Explore operation, then there's probably a bug in the JS code.
        var actions = [String: Action?]()
        for instr in instrumentedProgram.code {
            if let op = instr.op as? Explore {
                assert(!actions.keys.contains(op.id))
                actions.updateValue(nil, forKey: op.id)
            }
        }
        assert(!actions.isEmpty)

        // Parse the output: look for "EXPLORE_ERROR", "EXPLORE_FAILURE", and "EXPLORE_ACTION" and process them.
        // The actions dictionary maps explore operations (identified by their ID) to the concrete actions performed by them. Each operation will have one of three states at the end:
        //  1. The value is nil: we have not seen an action for this operation so it was not executed at runtime and we should ignore it
        //  2. The value is missing: we have seen a "EXPLORE_FAILURE" for this operation, meaning the action raised an exception at runtime and we should ignore it
        //  3. The value is a (non-nil) Action: the selected action executed successfully and we should replace the Explore operation with this action
        for line in output.split(whereSeparator: \.isNewline) where line.starts(with: "EXPLORE") {
            let errorMarker = "EXPLORE_ERROR: "
            let actionMarker = "EXPLORE_ACTION: "
            let failureMarker = "EXPLORE_FAILURE: "

            if line.hasPrefix(errorMarker) {
                if isKnownRuntimeError(line) { return (nil, .instrumentedProgramFailed) }
                // Everything else is unexpected and probably means that there's a bug in the JavaScript implementation, so treat that as an error.
                logger.error("Exploration failed: \(line.dropFirst(errorMarker.count))")
                // We could still continue here, but since this case is unexpected, it may be better to log this as a failure in our statistics.
                return (nil, .unexpectedError)
            } else if line.hasPrefix(failureMarker) {
                let id = line.dropFirst(failureMarker.count).trimmingCharacters(in: .whitespaces)
                guard actions.keys.contains(id) else {
                    logger.error("Invalid or duplicate ID for EXPLORE_FAILURE: \(id)")
                    return (nil, .unexpectedError)
                }
                actions.removeValue(forKey: id)
            } else if line.hasPrefix(actionMarker) {
                let decoder = JSONDecoder()
                let payload = Data(line.dropFirst(actionMarker.count).utf8)
                guard let action = try? decoder.decode(Action.self, from: payload) else {
                    logger.error("Failed to decode JSON payload in \"\(line)\"")
                    return (nil, .unexpectedError)
                }
                guard actions.keys.contains(action.id) && actions[action.id]! == nil else {
                    logger.error("Invalid or duplicate ID for EXPLORE_ACTION: \(action.id)")
                    return (nil, .unexpectedError)
                }
                actions[action.id] = action
            } else {
                logger.error("Invalid exploration result: \(line)")
                return (nil, .unexpectedError)
            }
        }

        guard !actions.isEmpty else {
            // This means that every Explore operation failed, which will happen sometimes.
            return (nil, .noResults)
        }

        // Now build the real program by replacing every Explore operation with the operation(s) that it actually performed at runtime.
        b.adopting(from: instrumentedProgram) {
            for instr in instrumentedProgram.code {
                if let op = instr.op as? Explore {
                    if let entry = actions[op.id], let action = entry {
                        if verbose { actionUsageCounts[action.operation]! += 1 }
                        let exploredValue = b.adopt(instr.input(0))
                        let args = instr.inputs.suffix(from: 1).map(b.adopt)
                        guard case .special(let name) = action.inputs.first, name == "exploredValue" else {
                            logger.error("Unexpected first input, expected the explored value, got \(String(describing: action.inputs.first)) for operation \(action.operation)")
                            continue
                        }
                        b.trace("Exploring value \(exploredValue)")
                        do {
                            let context = (arguments: args, specialValues: ["exploredValue": exploredValue])
                            try action.translateToFuzzIL(withContext: context, using: b)
                        } catch ActionError.actionTranslationError(let msg) {
                            logger.error("Failed to process action: \(msg)")
                        } catch {
                            logger.error("Unexpected error during action processing \(error)")
                        }
                        b.trace("Exploring finished")
                    }
                } else {
                    b.adopt(instr)
                }
            }
        }

        // All finished!
        return (b.finalize(), .success)
    }

    override func logAdditionalStatistics() {
        logger.verbose("Average number of inserted explore operations: \(String(format: "%.2f", averageNumberOfInsertedExploreOps.currentValue))")
        let totalHandlerInvocations = actionUsageCounts.values.reduce(0, +)
        logger.verbose("Frequencies of generated operations:")
        for (op, count) in actionUsageCounts {
            let frequency = (Double(count) / Double(totalHandlerInvocations)) * 100.0
            logger.verbose("    \(op.rawValue.rightPadded(toLength: 30)): \(String(format: "%.2f", frequency))%")
        }
    }
}
