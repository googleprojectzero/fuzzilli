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

    // How often each of the available handlers was invoked, used only in verbose mode.
    private var invocationCountsPerHandler = [String: Int]()

    public init() {
        super.init("ExplorationMutator", verbose: ExplorationMutator.verbose)
        if verbose {
            for op in handlers.keys {
                invocationCountsPerHandler[op] = 0
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

        return b.finalize()
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
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.starts(with: "EXPLORE") else { continue }
            let errorMarker = "EXPLORE_ERROR: "
            let actionMarker = "EXPLORE_ACTION: "
            let failureMarker = "EXPLORE_FAILURE: "

            if line.hasPrefix(errorMarker) {
                let ignoredErrors = ["maximum call stack size exceeded", "out of memory", "too much recursion"]
                for error in ignoredErrors {
                    if line.lowercased().contains(error) {
                        return (nil, .instrumentedProgramFailed)
                    }
                }

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

        // All finished!
        return (b.finalize(), .success)
    }

    override func logAdditionalStatistics() {
        let totalHandlerInvocations = invocationCountsPerHandler.values.reduce(0, +)
        logger.verbose("Frequencies of generated operations:")
        for (op, count) in invocationCountsPerHandler {
            let frequency = (Double(count) / Double(totalHandlerInvocations)) * 100.0
            logger.verbose("    \(op.rightPadded(toLength: 30)): \(String(format: "%.2f%%", frequency))")
        }
    }

    private func translateActionToFuzzIL(_ action: Action, on exploredValue: Variable, withArgs arguments: [Variable], using b: ProgramBuilder) {
        guard let handler = handlers[action.operation] else {
            return logger.error("Unknown operation \(action.operation)")
        }

        if verbose { invocationCountsPerHandler[action.operation]! += 1 }
        if action.isFallible {
            b.buildTryCatchFinally(tryBody: {
                handler.invoke(for: action, on: exploredValue, withArgs: arguments, using: b, loggingWith: logger)
            }, catchBody: { _ in })
        } else {
            handler.invoke(for: action, on: exploredValue, withArgs: arguments, using: b, loggingWith: logger)
        }
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
        let isFallible: Bool
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
                        let BigInt = b.loadBuiltin("BigInt")
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
            let constructor = b.getProperty(constructorName, of: v)
            b.construct(constructor, withArgs: inputs)
        },
        "GET_PROPERTY": Handler.withPropertyName(expectedInputs: 0) { b, v, propertyName, inputs in b.getProperty(propertyName, of: v) },
        "SET_PROPERTY": Handler.withPropertyName(expectedInputs: 1) { b, v, propertyName, inputs in b.setProperty(propertyName, of: v, to: inputs[0]) },
        "DEFINE_PROPERTY": Handler.withPropertyName(expectedInputs: 1) { b, v, propertyName, inputs in b.setProperty(propertyName, of: v, to: inputs[0]) },
        "GET_ELEMENT": Handler.withElementIndex(expectedInputs: 0) { b, v, idx, inputs in b.getElement(idx, of: v) },
        "SET_ELEMENT": Handler.withElementIndex(expectedInputs: 1) { b, v, idx, inputs in b.setElement(idx, of: v, to: inputs[0]) },
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
            let Number = b.loadBuiltin("Number")
            b.callMethod("isNaN", on: v)
        },
        "TEST_IS_FINITE": Handler(expectedInputs: 0) { b, v, inputs in
            let Number = b.loadBuiltin("Number")
            b.callMethod("isFinite", on: v)
        },
        "SYMBOL_REGISTRATION": Handler(expectedInputs: 0) { b, v, inputs in
            let Symbol = b.loadBuiltin("Symbol")
            let description = b.getProperty("description", of: v)
            b.callMethod("for", on: Symbol, withArgs: [description])
        },
    ]
}
