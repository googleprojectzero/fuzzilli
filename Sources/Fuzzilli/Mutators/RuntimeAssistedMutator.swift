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

/// A mutator that uses runtime feedback to perform smart(er) mutations.
///
/// A runtime assisted-mutator will generally perform the following steps:
/// 1. Instrument the program to mutate in some way, usually by inserting special operations.
/// 2. Execute the instrumented program and collect its output through the fuzzout channel.
/// 3. Process the output from step 2. to perform smarter mutations and generate the final program.
///
/// See the ExplorationMutator or ProbingMutator for examples of runtime-assisted mutators.
public class RuntimeAssistedMutator: Mutator {
    let logger: Logger

    // Whether to enable verbose logging. Mostly useful for development/debugging.
    let verbose: Bool

    // The different outcomes of exploration. Used for statistics in verbose mode.
    enum Outcome: String, CaseIterable {
        case success = "Success"
        case cannotInstrument = "Cannot instrument input"
        case instrumentedProgramFailed = "Instrumented program failed"
        case instrumentedProgramTimedOut = "Instrumented program timed out"
        case noResults = "No results received"
        case unexpectedError = "Unexpected Error"
    }
    private var outcomeCounts = [Outcome: Int]()

    // The number of programs produced so far, mostly used for the verbose mode.
    private var producedSamples = 0

    public init(_ name: String, verbose: Bool = false) {
        self.logger = Logger(withLabel: name)
        self.verbose = verbose

        if verbose {
            for outcome in Outcome.allCases {
                outcomeCounts[outcome] = 0
            }
        }
    }

    // Instrument the given program.
    func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        fatalError("Must be overwritten by child classes")
    }

    // Process the runtime output of the instrumented program and build the final program from that.
    func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, Outcome) {
        fatalError("Must be overwritten by child classes")
    }

    // Helper function for use by child classes. This detects known types of runtime errors that are expected to some degree (e.g. stack exhaustion or OOM).
    func isKnownRuntimeError(_ message: Substring) -> Bool {
        let ignoredErrors = ["maximum call stack size exceeded", "out of memory", "too much recursion"]
        for error in ignoredErrors {
            if message.lowercased().contains(error) {
                return true
            }
        }
        return false
    }

    // Log any additional statistics about the performance of this mutator. Only used in verbose mode.
    func logAdditionalStatistics() {
        // May be overwritten by child classes
    }

    override final func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Program? {
        // Build the instrumented program.
        guard let instrumentedProgram = instrument(program, for: fuzzer) else {
            return failure(.cannotInstrument)
        }

        // We currently assume that instrumenting will add internal operations to a program.
        assert(instrumentedProgram.code.contains(where: { $0.op is JsInternalOperation }))

        // Execute the instrumented program (with a higher timeout) and collect the output.
        let execution = fuzzer.execute(instrumentedProgram, withTimeout: fuzzer.config.timeout * 4, purpose: .runtimeAssistedMutation)
        switch execution.outcome {
        case .failed(_):
            // We generally do not expect the instrumentation code itself to cause runtime exceptions. Even if it performs new actions those should be guarded with try-catch.
            // However, failures can still happen for various reasons, for example when the instrumented program performs new actions that cause subsequent code to raise an exception.
            // Examples include detaching an ArrayBufer, rejecting a Promise, or even just modifying an object so that it can no longer be processed in a certain way
            // (for example by something like JSON.stringify, or when changing a method to a property, or when installing a property accessor that throws, etc.).
            // In these cases, an exception will potentially be raised later on in the program, leading to a failed execution. Failed executions are therefore expected to some
            // degree, but if the failure rate appears unreasonably high, one could log the failing program here.
            return failure(.instrumentedProgramFailed)
        case .timedOut:
            // Similar to the above case, this is expected to some degree.
            return failure(.instrumentedProgramTimedOut)
        case .crashed(let signal):
            // This is also somewhat unexpected, but can happen, generally for one of two reasons:
            // 1. The instrumented code performs new actions (e.g. in case of the ExplorationMutator) and those cause a crash
            // 2. Some part of the instrumentation logic caused a crash. For example, if an object is already in an inconsistent state, inspecting it may cause a crash
            // In this case we still try to process the instrumentation output (if any) and produce the final, uninstrumented program
            // so that we obtain reliable testcase for crashes due to (1). However, to not loose crashes due to (2), we also
            // report the instrumented program as crashing here. We may therefore end up with two crashes from one mutation.
            let stdout = execution.fuzzout + "\n" + execution.stdout
            fuzzer.processCrash(instrumentedProgram, withSignal: signal, withStderr: execution.stderr, withStdout: stdout, origin: .local, withExectime: execution.execTime)
        case .succeeded:
            // The expected case.
            break
        }

        // Process the output to build the mutated program.
        let (maybeMutatedProgram, outcome) = process(execution.fuzzout, ofInstrumentedProgram: instrumentedProgram, using: b)
        guard let mutatedProgram = maybeMutatedProgram else {
            assert(outcome != .success)
            return failure(outcome)
        }
        assert(outcome == .success)

        // Potentially log verbose statistics.
        producedSamples += 1
        if verbose && (producedSamples % 1000) == 0 {
            let totalOutcomes = outcomeCounts.values.reduce(0, +)
            logger.verbose("Frequencies of outcomes:")
            for outcome in Outcome.allCases {
                let count = outcomeCounts[outcome]!
                let frequency = (Double(count) / Double(totalOutcomes)) * 100.0
                logger.verbose("    \(outcome.rawValue.rightPadded(toLength: 30)): \(String(format: "%.2f%%", frequency))")
            }

            logAdditionalStatistics()
        }

        // All finished!
        return success(mutatedProgram)
    }

    private func failure(_ outcome: Outcome) -> Program? {
        assert(outcome != .success)
        outcomeCounts[outcome]! += 1
        return nil
    }

    private func success(_ program: Program) -> Program {
        outcomeCounts[.success]! += 1
        return program
    }

    //
    // Actions.
    //
    // An Action represents a JavaScript operation together with inputs. They can be used to
    // select and/or perform operations at runtime in an instrumented program. The Exploration-
    // and FixupMutator both make use of these actions.
    //
    // Actions are a bit simpler than FuzzIL instructions since they are only used to perform
    // operation in JavaScript and do not need to support mutations or static type inference.
    //
    // While there is not generally a 1:1 mapping between FuzzIL operations and JavaScript Actions,
    // it is always possible to translate a Action into one or more FuzzIL operations, and it is
    // possible to convert most simple (i.e. not part of a block) FuzzIL operations into a Action.
    //
    enum ActionOperation: String, CaseIterable, Codable {
        case CallFunction = "CALL_FUNCTION"
        case Construct = "CONSTRUCT"
        case CallMethod = "CALL_METHOD"
        case ConstructMethod = "CONSTRUCT_METHOD"
        case GetProperty = "GET_PROPERTY"
        case SetProperty = "SET_PROPERTY"
        case DeleteProperty = "DELETE_PROPERTY"
        case Add = "ADD"
        case Sub = "SUB"
        case Mul = "MUL"
        case Div = "DIV"
        case Mod = "MOD"
        case Inc = "INC"
        case Dec = "DEC"
        case Neg = "NEG"
        case LogicalAnd = "LOGICAL_AND"
        case LogicalOr = "LOGICAL_OR"
        case LogicalNot = "LOGICAL_NOT"
        case NullCoalesce = "NULL_COALESCE"
        case BitwiseAnd = "BITWISE_AND"
        case BitwiseOr = "BITWISE_OR"
        case BitwiseXor = "BITWISE_XOR"
        case LeftShift = "LEFT_SHIFT"
        case SignedRightShift = "SIGNED_RIGHT_SHIFT"
        case UnsignedRightShift = "UNSIGNED_RIGHT_SHIFT"
        case BitwiseNot = "BITWISE_NOT"
        case CompareEqual = "COMPARE_EQUAL"
        case CompareStrictEqual = "COMPARE_STRICT_EQUAL"
        case CompareNotEqual = "COMPARE_NOT_EQUAL"
        case CompareStrictNotEqual = "COMPARE_STRICT_NOT_EQUAL"
        case CompareGreaterThan = "COMPARE_GREATER_THAN"
        case CompareLessThan = "COMPARE_LESS_THAN"
        case CompareGreaterThanOrEqual = "COMPARE_GREATER_THAN_OR_EQUAL"
        case CompareLessThanOrEqual = "COMPARE_LESS_THAN_OR_EQUAL"
        case TestIsNaN = "TEST_IS_NAN"
        case TestIsFinite = "TEST_IS_FINITE"
        case SymbolRegistration = "SYMBOL_REGISTRATION"
    }

    // Data structure representing "actions". Will be transmitted in JSON-encoded form between the target engine and Fuzzilli.
    struct Action: Equatable, Codable {
        enum Input: Equatable, Codable {
            case argument(index: Int)
            case special(name: String)
            case int(value: Int64)
            case float(value: Double)
            case bigint(value: String)
            case string(value: String)
        }

        let id: String
        let operation: ActionOperation
        let inputs: [Input]
        let isGuarded: Bool
    }

    enum ActionError: Error {
        case actionTranslationError(String)
    }
}

extension RuntimeAssistedMutator.Action.Input {
    func translateToFuzzIL(withContext context: (arguments: [Variable], specialValues: [String: Variable]), using b: ProgramBuilder) throws -> Variable {
        switch self {
        case .argument(let index):
            guard context.arguments.indices.contains(index) else {
                throw RuntimeAssistedMutator.ActionError.actionTranslationError("Invalid argument index: \(index), have \(context.arguments.count) arguments")
            }
            return context.arguments[index]
        case .int(let value):
            return b.loadInt(value)
        case .float(let value):
            return b.loadFloat(value)
        case .bigint(let value):
            guard value.allSatisfy({ $0.isNumber || $0 == "-" }) else {
                throw RuntimeAssistedMutator.ActionError.actionTranslationError("Malformed bigint value: \(value)")
            }
            if let intValue = Int64(value) {
                return b.loadBigInt(intValue)
            } else {
                // TODO consider changing loadBigInt to use a string instead
                let s = b.loadString(value)
                let BigInt = b.createNamedVariable(forBuiltin: "BigInt")
                return b.callFunction(BigInt, withArgs: [s])
            }
        case .string(let value):
            return b.loadString(value)
        case .special(let name):
            guard let v = context.specialValues[name] else { throw RuntimeAssistedMutator.ActionError.actionTranslationError("Unknown special input value \(name)") }
            return v
        }
    }
}

extension RuntimeAssistedMutator.Action {
    func translateToFuzzIL(withContext context: (arguments: [Variable], specialValues: [String: Variable]), using b: ProgramBuilder) throws {
        // Helper function to fetch an input of this Action.
        func getInput(_ i: Int) throws -> Input {
            guard inputs.indices.contains(i) else { throw RuntimeAssistedMutator.ActionError.actionTranslationError("Missing input \(i) for operation \(operation)") }
            return inputs[i]
        }
        // Helper function to fetch an input of this Action and translate it to a FuzzIL variable.
        func translateInput(_ i: Int) throws -> Variable {
            return try getInput(0).translateToFuzzIL(withContext: context, using: b)
        }
        // Helper function to translate a range of inputs of this Action into FuzzIL variables.
        func translateInputs(_ r: PartialRangeFrom<Int>) throws -> [Variable] {
            guard inputs.indices.upperBound >= r.lowerBound else { throw RuntimeAssistedMutator.ActionError.actionTranslationError("Missing inputs in range \(r) for operation \(operation)") }
            return try inputs[r].map({ try $0.translateToFuzzIL(withContext: context, using: b) })
        }
        // Helper functions to translate actions to binary/unary operations or comparisons.
        func translateBinaryOperation(_ op: BinaryOperator) throws {
            assert(!isGuarded)
            b.binary(try translateInput(0), try translateInput(1), with: op)
        }
        func translateUnaryOperation(_ op: UnaryOperator) throws {
            assert(!isGuarded)
            b.unary(op, try translateInput(0))
        }
        func translateComparison(_ op: Comparator) throws {
            assert(!isGuarded)
            b.compare(try translateInput(0), with: try translateInput(1), using: op)
        }

        switch operation {
        case .CallFunction:
            let f = try translateInput(0)
            let args = try translateInputs(1...)
            b.callFunction(f, withArgs: args, guard: isGuarded)
        case .Construct:
            let c = try translateInput(0)
            let args = try translateInputs(1...)
            b.construct(c, withArgs: args, guard: isGuarded)
        case .CallMethod:
            let o = try translateInput(0)
            let args = try translateInputs(2...)
            switch try getInput(1) {
            case .string(let methodName):
                b.callMethod(methodName, on: o, withArgs: args, guard: isGuarded)
            default:
                let method = try translateInput(1)
                b.callComputedMethod(method, on: o, withArgs: args, guard: isGuarded)
            }
        case .ConstructMethod:
            let o = try translateInput(0)
            let c: Variable
            switch try getInput(1) {
            case .string(let member):
                c = b.getProperty(member, of: o, guard: isGuarded)
            default:
                let member = try translateInput(1)
                c = b.getComputedProperty(member, of: o, guard: isGuarded)
            }
            let args = try translateInputs(2...)
            b.construct(c, withArgs: args, guard: isGuarded)
        case .GetProperty:
            let o = try translateInput(0)
            switch try getInput(1) {
            case .string(let propertyName):
                b.getProperty(propertyName, of: o, guard: isGuarded)
            case .int(let index):
                b.getElement(index, of: o, guard: isGuarded)
            default:
                let property = try translateInput(1)
                b.getComputedProperty(property, of: o, guard: isGuarded)
            }
        case .SetProperty:
            assert(!isGuarded)
            let o = try translateInput(0)
            let v = try translateInput(2)
            switch try getInput(1) {
            case .string(let propertyName):
                b.setProperty(propertyName, of: o, to: v)
            case .int(let index):
                b.setElement(index, of: o, to: v)
            default:
                let property = try translateInput(1)
                b.setComputedProperty(property, of: o, to: v)
            }
        case .DeleteProperty:
            let o = try translateInput(0)
            switch try getInput(1) {
            case .string(let propertyName):
                b.deleteProperty(propertyName, of: o, guard: isGuarded)
            case .int(let index):
                b.deleteElement(index, of: o, guard: isGuarded)
            default:
                let property = try translateInput(1)
                b.deleteComputedProperty(property, of: o, guard: isGuarded)
            }
        case .Add:
            try translateBinaryOperation(.Add)
        case .Sub:
            try translateBinaryOperation(.Sub)
        case .Mul:
            try translateBinaryOperation(.Mul)
        case .Div:
            try translateBinaryOperation(.Div)
        case .Mod:
            try translateBinaryOperation(.Mod)
        case .Inc:
            try translateUnaryOperation(.PostInc)
        case .Dec:
            try translateUnaryOperation(.PostDec)
        case .Neg:
            try translateUnaryOperation(.Minus)
        case .LogicalAnd:
            try translateBinaryOperation(.LogicAnd)
        case .LogicalOr:
            try translateBinaryOperation(.LogicOr)
        case .LogicalNot:
            try translateUnaryOperation(.LogicalNot)
        case .BitwiseAnd:
            try translateBinaryOperation(.BitAnd)
        case .BitwiseOr:
            try translateBinaryOperation(.BitOr)
        case .BitwiseXor:
            try translateBinaryOperation(.Xor)
        case .NullCoalesce:
            try translateBinaryOperation(.NullCoalesce)    
        case .LeftShift:
            try translateBinaryOperation(.LShift)
        case .SignedRightShift:
            try translateBinaryOperation(.RShift)
        case .UnsignedRightShift:
            try translateBinaryOperation(.UnRShift)
        case .BitwiseNot:
            try translateUnaryOperation(.BitwiseNot)
        case .CompareEqual:
            try translateComparison(.equal)
        case .CompareStrictEqual:
            try translateComparison(.strictEqual)
        case .CompareNotEqual:
            try translateComparison(.notEqual)
        case .CompareStrictNotEqual:
            try translateComparison(.strictNotEqual)
        case .CompareGreaterThan:
            try translateComparison(.greaterThan)
        case .CompareLessThan:
            try translateComparison(.lessThan)
        case .CompareGreaterThanOrEqual:
            try translateComparison(.greaterThanOrEqual)
        case .CompareLessThanOrEqual:
            try translateComparison(.lessThanOrEqual)
        case .TestIsNaN:
            assert(!isGuarded)
            let v = try translateInput(0)
            let Number = b.createNamedVariable(forBuiltin: "Number")
            b.callMethod("isNaN", on: Number, withArgs: [v])
        case .TestIsFinite:
            assert(!isGuarded)
            let v = try translateInput(0)
            let Number = b.createNamedVariable(forBuiltin: "Number")
            b.callMethod("isFinite", on: Number, withArgs: [v])
        case .SymbolRegistration:
            assert(!isGuarded)
            let s = try translateInput(0)
            let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
            let description = b.getProperty("description", of: s)
            b.callMethod("for", on: Symbol, withArgs: [description])
        }
    }
}
