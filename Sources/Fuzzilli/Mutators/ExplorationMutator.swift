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
///   action that was performed by them at runtime (so for example a LoadProperty or CallMethod operation)
///
/// The result is a program that performs useful actions on some of the existing variables even without
/// statically knowing their type. The resulting program is also deterministic and "JIT friendly" as it
/// no longer relies on any kind of runtime object inspection.
///
/// A large bit of the logic of this mutator is located in the lifter code that implements Explore operations
/// in the target language. For JavaScript, that logic can be found in JavaScriptExploreLifting.swift.
public class ExplorationMutator: Mutator {
    private let logger = Logger(withLabel: "ExplorationMutator")

    // If true, this mutator will log detailed statistics like how often each type of operation was performend.
    // Enable verbose mode by default while this feature is still under development.
    private let verbose = true

    // How often each of the available handlers was invoked, used only in verbose mode.
    private var invocationCountsPerHandler = [String: Int]()

    // The different outcomes of exploration. Used for statistics in verbose mode.
    private enum ExplorationOutcome: String, CaseIterable {
        case success = "Success"
        case cannotInstrument = "Cannot instrument input"
        case instrumentedProgramFailed = "Instrumented program failed"
        case instrumentedProgramTimedOut = "Instrumented program timed out"
        case noActions = "No actions received"
        case unexpectedError = "Unexpected Error"
    }
    private var explorationOutcomeCounts = [ExplorationOutcome: Int]()

    // The number of programs produced so far, mostly used for the verbose mode.
    private var producedSamples = 0

    public override init() {
        if verbose {
            for op in handlers.keys {
                invocationCountsPerHandler[op] = 0
            }
            for outcome in ExplorationOutcome.allCases {
                explorationOutcomeCounts[outcome] = 0
            }
        }
    }

    override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        guard let (instrumentedProgram, exploreIds) = instrument(program, for: fuzzer) else {
            // This just means that there are not enough available variables for exploration.
            return failure(.cannotInstrument)
        }

        // Execute the instrumented program (with a higher timeout) and collect the output.
        let execution = fuzzer.execute(instrumentedProgram, withTimeout: fuzzer.config.timeout * 2)
        switch execution.outcome {
        case .failed(_):
            // This can happen for various reasons, for example when the performed action detaches an ArrayBufer, or rejects a Promise, or even just modifies an object so
            // that it can no longer be processed in a certain way (for example by something like JSON.stringify, or when changing a method to a property, or when installing
            // a property accessor that throws an exceptions, etc.). In these cases, an exception will potentially be raised later on in the program, but not during the
            // exploration, leading to a failed execution. Failed executions are therefore expected, but if the failure rate appears unreasonably high, one could call
            // maybeLogFailingExecution here and enable verbose mode to investigate.
            return failure(.instrumentedProgramFailed)
        case .timedOut:
            // Similar to the above case, this is expected to some degree.
            return failure(.instrumentedProgramTimedOut)
        case .crashed(let signal):
            // This is also somewhat unexpected, but can happen, generally for one of two reasons:
            // 1. One of the actions performed by an Exploration instruction directly led to a crash (the likely case)
            // 2. Some part of the exploration code caused a crash. For example, if an object is already in an inconsistent state, inspecting it may cause a crash (the less likely case)
            // We will now still try to translate the Explore operations to their concrete action and return the resulting program.
            // This should produce reliable testcase for crashes due to (1). However, to not loose crashes due to (2), we also
            // report the instrumented program as crashing here. We may therefore end up with two crashes from one mutation.
            let stdout = "Exploration log:\n" + execution.fuzzout + "\n" + execution.stdout
            fuzzer.processCrash(instrumentedProgram, withSignal: signal, withStderr: execution.stderr, withStdout: stdout, origin: .local)
        case .succeeded:
            // The expected case.
            break
        }

        // Parse the output: look for "EXPLORE_ERROR", "EXPLORE_FAILURE", and "EXPLORE_ACTION" and process them.
        // The actions dictionary maps explore operations (identified by their ID) to the concrete actions performed by them. Each operation will have one of three states at the end:
        //  1. The value in the dictionary is nil: we have not seen an action for this operation so it was not executed at runtime and we should ignore it
        //  2. The value is missing: we have seen a "EXPLORE_FAILURE" for this operation, meaning the action raised an exception at runtime and we should ignore it
        //  3. The value is a (non-nil) Action: the selected action executed successfully and we should replace the Explore operation with this action
        var actions = [String: Action?](uniqueKeysWithValues: zip(exploreIds, [Action?](repeating: nil, count: exploreIds.count)))
        for line in execution.fuzzout.split(whereSeparator: \.isNewline) {
            guard line.starts(with: "EXPLORE") else { continue }
            let errorMarker = "EXPLORE_ERROR: "
            let actionMarker = "EXPLORE_ACTION: "
            let failureMarker = "EXPLORE_FAILURE: "

            if line.hasPrefix(errorMarker) {
                let ignoredErrors = ["maximum call stack size exceeded", "out of memory", "too much recursion"]
                for error in ignoredErrors {
                    if line.lowercased().contains(error) {
                        return failure(.instrumentedProgramFailed)
                    }
                }

                // Everything else is unexpected and probably means there's a bug in the JavaScript implementation, so treat that as an error.
                logger.error("Exploration failed: \(line.dropFirst(errorMarker.count))")
                maybeLogFailingExecution(execution, of: instrumentedProgram, usingLifter: fuzzer.lifter, usingLogLevel: .error)
                // We could still continue here, but since this case is unexpected, it may be better to log this as a failure in our statistics.
                return failure(.unexpectedError)
            } else if line.hasPrefix(failureMarker) {
                let id = line.dropFirst(failureMarker.count).trimmingCharacters(in: .whitespaces)
                guard actions.keys.contains(id) else {
                    logger.error("Invalid or duplicate ID for EXPLORE_FAILURE: \(id)")
                    return failure(.unexpectedError)
                }
                actions.removeValue(forKey: id)
            } else if line.hasPrefix(actionMarker) {
                let decoder = JSONDecoder()
                let payload = Data(line.dropFirst(actionMarker.count).utf8)
                guard let action = try? decoder.decode(Action.self, from: payload) else {
                    logger.error("Failed to decode JSON payload in \"\(line)\"")
                    return failure(.unexpectedError)
                }
                guard actions.keys.contains(action.id) && actions[action.id]! == nil else {
                    logger.error("Invalid or duplicate ID for EXPLORE_ACTION: \(action.id)")
                    return failure(.unexpectedError)
                }
                actions[action.id] = action
            } else {
                logger.error("Invalid exploration result: \(line)")
                return failure(.unexpectedError)
            }
        }

        guard !actions.isEmpty else {
            // This means that every Explore operation failed, which will sometimes happen.
            return failure(.noActions)
        }

        // Now build the real program by replacing every Explore operation with the operation(s) that it actually performed at runtime.
        b.adopting(from: instrumentedProgram) {
            for instr in instrumentedProgram.code {
                if let op = instr.op as? Explore {
                    if let entry = actions[op.id], let action = entry {
                        let exploredValue = b.adopt(instr.input(0))
                        let adoptedArgs = instr.inputs.suffix(from: 1).map({ b.adopt($0) })
                        b.trace("Exploring value \(exploredValue)")
                        translateActionToFuzzIL(action, on: exploredValue, withArgs: adoptedArgs, using: b)
                        b.trace("Exploring finished")
                    }
                } else {
                    b.adopt(instr)
                }
            }
        }

        producedSamples += 1
        if verbose && (producedSamples % 1000) == 0 {
            let totalHandlerInvocations = invocationCountsPerHandler.values.reduce(0, +)
            logger.info("Frequencies of generated operations:")
            for (op, count) in invocationCountsPerHandler {
                let frequency = (Double(count) / Double(totalHandlerInvocations)) * 100.0
                logger.info("    \(op.padding(toLength: 30, withPad: " ", startingAt: 0)): \(String(format: "%.2f%%", frequency))")
            }

            let totalOutcomes = explorationOutcomeCounts.values.reduce(0, +)
            logger.info("Frequencies of exploration outcomes:")
            for outcome in ExplorationOutcome.allCases {
                let count = explorationOutcomeCounts[outcome]!
                let frequency = (Double(count) / Double(totalOutcomes)) * 100.0
                logger.info("    \(outcome.rawValue.padding(toLength: 30, withPad: " ", startingAt: 0)): \(String(format: "%.2f%%", frequency))")
            }
        }

        // All finished!
        return success(b.finalize())
    }

    private func instrument(_ program: Program, for fuzzer: Fuzzer) -> (instrumentedProgram: Program, exploreIds: [String])? {
        let b = fuzzer.makeBuilder()

        // Enumerate all variables in the program in put them into one of two buckets, depending on whether static type information is available for them.
        var untypedVariables = [Variable]()
        var typedVariables = [Variable]()
        for instr in program.code {
            b.append(instr)
            // Since we need additional arguments for Explore, only explore when we have a couple of visible variables.
            guard b.numVisibleVariables > 3 else { continue }
            for v in instr.allOutputs {
                if b.type(of: v) == .unknown {
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
        var ids = [String]()
        b.adopting(from: program) {
            for instr in program.code {
                b.adopt(instr)
                for v in instr.allOutputs {
                    if variablesToExplore.contains(v) {
                        let args = b.randVars(upTo: 5)
                        assert(args.count > 0)
                        let id = v.identifier
                        assert(!ids.contains(id))
                        b.explore(v, id: id, withArgs: args)
                        ids.append(id)
                    }
                }
            }
        }

        return (b.finalize(), ids)
    }

    private func translateActionToFuzzIL(_ action: Action, on exploredValue: Variable, withArgs arguments: [Variable], using b: ProgramBuilder) {
        guard let handler = handlers[action.operation] else {
            return logger.error("Unknown operation \(action.operation)")
        }

        if verbose { invocationCountsPerHandler[action.operation]! += 1 }
        handler.invoke(for: action, on: exploredValue, withArgs: arguments, using: b, loggingWith: logger)
    }

    // Data structure used for communication with the target. Will be transmitted in JSON-encoded form.
    private struct Action: Decodable {
        struct Input: Decodable {
            let argumentIndex: Int?
            let methodName: String?
            let elementIndex: Int64?
            let propertyName: String?
            let intValue: Int64?
            let floatValue: Double?
            let bigintValue: String?
            let stringValue: String?

            func isValid() -> Bool {
                // Must have exactly one non-nil value.
                return [argumentIndex != nil,
                        methodName != nil,
                        elementIndex != nil,
                        propertyName != nil,
                        intValue != nil,
                        floatValue != nil,
                        bigintValue != nil,
                        stringValue != nil]
                    .filter({ $0 }).count == 1
            }
        }

        let id: String
        let operation: String
        let inputs: [Input]
    }

    // Handlers to interpret the actions and translate them into FuzzIL instructions.
    private struct Handler {
        typealias DefaultHandlerImpl = (ProgramBuilder, Variable, [Variable]) -> Void
        typealias HandlerWithMethodNameImpl = (ProgramBuilder, Variable, String, [Variable]) -> Void
        typealias HandlerWithPropertyNameImpl = (ProgramBuilder, Variable, String, [Variable]) -> Void
        typealias HandlerWithElementIndexImpl = (ProgramBuilder, Variable, Int64, [Variable]) -> Void

        private var expectedInputs: Int? = nil
        private var defaultImpl: DefaultHandlerImpl? = nil
        private var withMethodNameImpl: HandlerWithMethodNameImpl? = nil
        private var withPropertyNameImpl: HandlerWithPropertyNameImpl? = nil
        private var withElementIndexImpl: HandlerWithElementIndexImpl? = nil

        init(expectedInputs: Int? = nil, defaultImpl: DefaultHandlerImpl? = nil) {
            self.expectedInputs = expectedInputs
            self.defaultImpl = defaultImpl
        }

        static func withMethodName(expectedInputs: Int? = nil, _ impl: @escaping HandlerWithMethodNameImpl) -> Handler {
            var handler = Handler(expectedInputs: expectedInputs)
            handler.withMethodNameImpl = impl
            return handler
        }

        static func withPropertyName(expectedInputs: Int? = nil, _ impl: @escaping HandlerWithPropertyNameImpl) -> Handler {
            var handler = Handler(expectedInputs: expectedInputs)
            handler.withPropertyNameImpl = impl
            return handler
        }

        static func withElementIndex(expectedInputs: Int? = nil, _ impl: @escaping HandlerWithElementIndexImpl) -> Handler {
            var handler = Handler(expectedInputs: expectedInputs)
            handler.withElementIndexImpl = impl
            return handler
        }

        func invoke(for action: Action, on exploredValue: Variable, withArgs arguments: [Variable], using b: ProgramBuilder, loggingWith logger: Logger) {
            // Translate inputs to FuzzIL variables.
            var fuzzILInputs = [Variable]()
            for input in action.inputs {
                guard input.isValid() else {
                    return logger.error("Invalid input for action \(action.operation)")
                }

                if let argumentIndex = input.argumentIndex {
                    guard arguments.indices.contains(argumentIndex) else {
                        return logger.error("Invalid argument index: \(argumentIndex), have \(arguments.count) arguments")
                    }
                    fuzzILInputs.append(arguments[argumentIndex])
                } else if let intValue = input.intValue {
                    fuzzILInputs.append(b.loadInt(intValue))
                } else if let floatValue = input.floatValue {
                    fuzzILInputs.append(b.loadFloat(floatValue))
                } else if let bigintValue = input.bigintValue {
                    guard bigintValue.allSatisfy({ $0.isNumber || $0 == "-" }) else {
                        return logger.error("Malformed bigint value: \(bigintValue)")
                    }
                    if let intValue = Int64(bigintValue) {
                        fuzzILInputs.append(b.loadBigInt(intValue))
                    } else {
                        // TODO consider changing loadBigInt to use a string instead
                        let s = b.loadString(bigintValue)
                        let BigInt = b.reuseOrLoadBuiltin("BigInt")
                        fuzzILInputs.append(b.callFunction(BigInt, withArgs: [s]))
                    }
                } else if let stringValue = input.stringValue {
                    fuzzILInputs.append(b.loadString(stringValue))
                }
            }

            guard expectedInputs == nil || fuzzILInputs.count == expectedInputs else {
                return logger.error("Incorrect number of inputs for \(action.operation). Expected \(expectedInputs!), got \(fuzzILInputs.count)")
            }

            // Call handler implementation.
            if let impl = defaultImpl {
                impl(b, exploredValue, fuzzILInputs)
            } else if let impl = withMethodNameImpl {
                guard let methodName = action.inputs.first?.methodName else {
                    return logger.error("Missing method name for \(action.operation) operation")
                }
                impl(b, exploredValue, methodName, fuzzILInputs)
            } else if let impl = withPropertyNameImpl {
                guard let propertyName = action.inputs.first?.propertyName else {
                    return logger.error("Missing property name for \(action.operation) operation")
                }
                impl(b, exploredValue, propertyName, fuzzILInputs)
            } else if let impl = withElementIndexImpl {
                guard let elementIndex = action.inputs.first?.elementIndex else {
                    return logger.error("Missing element index for \(action.operation) operation")
                }
                impl(b, exploredValue, elementIndex, fuzzILInputs)
            } else {
                fatalError("Invalid handler")
            }
        }
    }

    // All supported handlers.
    private let handlers: [String: Handler] = [
        "CALL_FUNCTION": Handler { b, v, inputs in b.callFunction(v, withArgs: inputs) },
        "CONSTRUCT": Handler { b, v, inputs in b.construct(v, withArgs: inputs) },
        "CALL_METHOD": Handler.withMethodName { b, v, methodName, inputs in b.callMethod(methodName, on: v, withArgs: inputs) },
        "CONSTRUCT_MEMBER": Handler.withMethodName { b, v, constructorName, inputs in
            let constructor = b.loadProperty(constructorName, of: v)
            b.construct(constructor, withArgs: inputs)
        },
        "GET_PROPERTY": Handler.withPropertyName(expectedInputs: 0) { b, v, propertyName, inputs in b.loadProperty(propertyName, of: v) },
        "SET_PROPERTY": Handler.withPropertyName(expectedInputs: 1) { b, v, propertyName, inputs in b.storeProperty(inputs[0], as: propertyName, on: v) },
        "DEFINE_PROPERTY": Handler.withPropertyName(expectedInputs: 1) { b, v, propertyName, inputs in b.storeProperty(inputs[0], as: propertyName, on: v) },
        "GET_ELEMENT": Handler.withElementIndex(expectedInputs: 0) { b, v, idx, inputs in b.loadElement(idx, of: v) },
        "SET_ELEMENT": Handler.withElementIndex(expectedInputs: 1) { b, v, idx, inputs in b.storeElement(inputs[0], at: idx, of: v) },
        "ADD": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Add) },
        "SUB": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Sub) },
        "MUL": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Mul) },
        "DIV": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Div) },
        "MOD": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Mod) },
        "INC": Handler(expectedInputs: 0) { b, v, inputs in b.unary(.PostInc, v) },
        "DEC": Handler(expectedInputs: 0) { b, v, inputs in b.unary(.PostDec, v) },
        "NEG": Handler(expectedInputs: 0) { b, v, inputs in b.unary(.Minus, v) },
        "LOGICAL_AND": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .LogicAnd) },
        "LOGICAL_OR": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .LogicAnd) },
        "LOGICAL_NOT": Handler(expectedInputs: 0) { b, v, inputs in b.unary(.LogicalNot, v) },
        "BITWISE_AND": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .BitAnd) },
        "BITWISE_OR": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .BitOr) },
        "BITWISE_XOR": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .Xor) },
        "LEFT_SHIFT": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .LShift) },
        "SIGNED_RIGHT_SHIFT": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .RShift) },
        "UNSIGNED_RIGHT_SHIFT": Handler(expectedInputs: 1) { b, v, inputs in b.binary(v, inputs[0], with: .UnRShift) },
        "BITWISE_NOT": Handler(expectedInputs: 0) { b, v, inputs in b.unary(.BitwiseNot, v) },
        "COMPARE_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .equal) },
        "COMPARE_STRICT_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .strictEqual) },
        "COMPARE_NOT_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .notEqual) },
        "COMPARE_STRICT_NOT_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .strictNotEqual) },
        "COMPARE_GREATER_THAN": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .greaterThan) },
        "COMPARE_LESS_THAN": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .greaterThanOrEqual) },
        "COMPARE_GREATER_THAN_OR_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .lessThan) },
        "COMPARE_LESS_THAN_OR_EQUAL": Handler(expectedInputs: 1) { b, v, inputs in b.compare(v, with: inputs[0], using: .lessThanOrEqual) },
        "TEST_IS_NAN": Handler(expectedInputs: 0) { b, v, inputs in
            let Number = b.reuseOrLoadBuiltin("Number")
            b.callMethod("isNaN", on: v, withArgs: [])
        },
        "TEST_IS_FINITE": Handler(expectedInputs: 0) { b, v, inputs in
            let Number = b.reuseOrLoadBuiltin("Number")
            b.callMethod("isFinite", on: v, withArgs: [])
        },
        "SYMBOL_REGISTRATION": Handler(expectedInputs: 0) { b, v, inputs in
            let Symbol = b.reuseOrLoadBuiltin("Symbol")
            let description = b.loadProperty("description", of: v)
            b.callMethod("for", on: Symbol, withArgs: [description])
        },
    ]

    private func failure(_ outcome: ExplorationOutcome) -> Program? {
        assert(outcome != .success)
        explorationOutcomeCounts[outcome]! += 1
        return nil
    }

    private func success(_ program: Program) -> Program {
        explorationOutcomeCounts[.success]! += 1
        return program
    }

    private func maybeLogFailingExecution(_ execution: Execution, of program: Program, usingLifter lifter: Lifter, usingLogLevel logLevel: LogLevel) {
        guard verbose else { return }
        let script = lifter.lift(program, withOptions: [.includeLineNumbers])
        logger.log("Instrumented program:\n\(script)\nSTDOUT:\n\(execution.stdout)\nSTDERR:\n\(execution.stderr)", atLevel: logLevel)
    }
}
