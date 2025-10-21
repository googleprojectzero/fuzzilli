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

import Foundation

/// Builds programs.
///
/// This provides methods for constructing and appending random
/// instances of the different kinds of operations in a program.
public class ProgramBuilder {
    /// The fuzzer instance for which this builder is active.
    public let fuzzer: Fuzzer

    private let logger = Logger(withLabel: "ProgramBuilder")

    /// The code and type information of the program that is being constructed.
    private var code = Code()

    /// Comments for the program that is being constructed.
    private var comments = ProgramComments()

    /// Every code generator that contributed to the current program.
    private var contributors = Contributors()

    /// The parent program for the program being constructed.
    private let parent: Program?

    public var context: Context {
        return contextAnalyzer.context
    }

    /// If true, the variables containing a function is hidden inside the function's body.
    ///
    /// For example, in
    ///
    ///     let f = b.buildPlainFunction(with: .parameters(n: 2) { args in
    ///         // ...
    ///     }
    ///     b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    ///
    /// The variable f would *not* be visible inside the body of the plain function during building
    /// when this is enabled. However, the variable will be visible during future mutations, it is only
    /// hidden when the function is initially created.
    ///
    /// The same is done for class definitions, which may also cause trivial recursion in the constructor,
    /// but where usage of the output inside the class definition's body may also cause other problems,
    /// for example since `class C { [C] = 42; }` is invalid.
    ///
    /// This can make sense for a number of reasons. First, it prevents trivial recursion where a
    /// function directly calls itself. Second, it prevents weird code like for example the following:
    ///
    ///     function f1() {
    ///         let o6 = { x: foo + foo, y() { return foo; } };
    ///     }
    ///
    /// From being generated, which can happen quite frequently during prefix generation as
    /// the number of visible variables may be quite small.
    public let enableRecursionGuard = true

    /// Counter to quickly determine the next free variable.
    private var numVariables = 0

    /// Context analyzer to keep track of the currently active IL context.
    private var contextAnalyzer = ContextAnalyzer()

    /// Visible variables management.
    /// The `scopes` stack contains one entry per currently open scope containing all variables created in that scope.
    private(set) var scopes = Stack<[Variable]>([[]])
    /// The `variablesInScope` array simply contains all variables that are currently in scope. It is effectively the `scopes` stack flattened.
    private var variablesInScope = [Variable]()

    /// Keeps track of variables that have explicitly been hidden and so should not be
    /// returned from e.g. `randomJsVariable()`. See `hide()` for more details.
    private var hiddenVariables = VariableSet()
    private var numberOfHiddenVariables = 0

    /// Type inference for JavaScript variables.
    private var jsTyper: JSTyper

    /// Argument generation budget.
    /// This budget is used in `findOrGenerateArguments(forSignature)` and tracks the upper limit of variables that that function should emit.
    /// If that upper limit is reached the function will stop generating new variables and use existing ones instead.
    /// If this value is set to nil, there is no argument generation happening, every argument generation should enter the recursive function (findOrGenerateArgumentsInternal) through the public non-internal one.
    private var argumentGenerationVariableBudget: Stack<Int> = Stack()
    /// This is the top most signature that was requested when `findOrGeneratorArguments(forSignature)` was called, this is helpful for debugging.
    private var argumentGenerationSignature: Stack<Signature> = Stack()

    /// Stack of active object literals.
    ///
    /// This needs to be a stack as object literals can be nested, for example if an object
    /// literals is created inside a method/getter/setter of another object literals.
    private var activeObjectLiterals = Stack<ObjectLiteral>()

    /// If we open a new function, we save its Variable here.
    /// This allows CodeGenerators to refer to their Variable after they emit the
    /// `End*Function` operation. This allows them to call the function after closing it.
    /// Since they cannot refer to the Variable as it usually is created in the head part of the Generator.
    private var lastFunctionVariables = Stack<Variable>()

    /// Just a getter to get the top most, i.e. last function Variable.
    public var lastFunctionVariable: Variable  {
        return lastFunctionVariables.top
    }

    /// When building object literals, the state for the current literal is exposed through this member and
    /// can be used to add fields to the literal or to determine if some field already exists.
    public var currentObjectLiteral: ObjectLiteral {
        return activeObjectLiterals.top
    }

    private var activeWasmModule: WasmModule? = nil

    public var currentWasmModule: WasmModule {
        return activeWasmModule!
    }

    public var currentWasmSignature: WasmSignature {
        return activeWasmModule!.blockSignatures.top
    }

    public var currentWasmFunction: WasmFunction {
        return activeWasmModule!.functions.last!
    }

    /// Stack of active class definitions.
    ///
    /// Similar to object literals, class definitions can be nested so this needs to be a stack.
    private var activeClassDefinitions = Stack<ClassDefinition>()

    /// When building class definitions, the state for the current definition is exposed through this member and
    /// can be used to add fields to the class or to determine if some field already exists.
    public var currentClassDefinition: ClassDefinition {
        return activeClassDefinitions.top
    }

    /// The remaining CodeGenerators to call as part of a building / CodeGen step, these will "clean up" the state and fix the contexts.
    public var scheduled: Stack<GeneratorStub> = Stack()

    /// Stack of active switch blocks.
    private var activeSwitchBlocks = Stack<SwitchBlock>()

    /// When building switch blocks, the state for the current switch block is exposed through this
    /// member and can be used to add cases to the switch.
    public var currentSwitchBlock: SwitchBlock {
        return activeSwitchBlocks.top
    }

    /// How many variables are currently in scope.
    public var numberOfVisibleVariables: Int {
        assert(numberOfHiddenVariables <= variablesInScope.count)
        return variablesInScope.count - numberOfHiddenVariables
    }

    /// Whether there are any variables currently in scope.
    public var hasVisibleVariables: Bool {
        return numberOfVisibleVariables > 0
    }

    public var hasVisibleJsVariables: Bool {
        let jsVarCount = variablesInScope.filter({
            type(of: $0).Is(.jsAnything)
        }).count
        let hiddenJsVarCount = hiddenVariables.filter({
            type(of: $0).Is(.jsAnything)
        }).count

        return jsVarCount > hiddenJsVarCount
    }

    /// All currently visible variables.
    public var visibleVariables: [Variable] {
        if numberOfHiddenVariables == 0 {
            // Fast path for the common case.
            return variablesInScope
        } else {
            return variablesInScope.filter({ !hiddenVariables.contains($0) })
        }
    }

    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer, parent: Program?) {
        self.fuzzer = fuzzer
        self.jsTyper = JSTyper(for: fuzzer.environment)
        self.parent = parent

        if fuzzer.config.logLevel.isAtLeast(.verbose)  {
            self.buildLog = BuildLog()
        }
    }

    /// Resets this builder.
    public func reset() {
        code.removeAll()
        comments.removeAll()
        contributors.removeAll()
        numVariables = 0
        scopes = Stack([[]])
        variablesInScope.removeAll()
        hiddenVariables.removeAll()
        numberOfHiddenVariables = 0
        contextAnalyzer = ContextAnalyzer()
        jsTyper.reset()
        activeObjectLiterals.removeAll()
        activeClassDefinitions.removeAll()
        buildLog?.reset()
    }

    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        assert(scheduled.isEmpty)
        let program = Program(code: code, parent: parent, comments: comments, contributors: contributors)
        reset()
        return program
    }

    /// Prints the current program as FuzzIL code to stdout. Useful for debugging.
    public func dumpCurrentProgram() {
        print(FuzzILLifter().lift(code))
    }

    // This can be used to crash the fuzzer if we see an unexpected condition.
    // Since some edge cases are hard to trigger, this can be used to surface these conditions
    // during "real" fuzzing runs, i.e. in release builds.
    public func reportErrorIf(_ condition: Bool, _ message: String) {
        if condition {
            let prog = FuzzILLifter().lift(code)
            fatalError("\(message)\nProgram:\n\(prog)")
        }
    }

    /// Returns the current number of instructions of the program we're building.
    public var currentNumberOfInstructions: Int {
        return code.count
    }

    /// Returns the index of the next instruction added to the program. This is equal to the current size of the program.
    public func indexOfNextInstruction() -> Int {
        return currentNumberOfInstructions
    }

    /// Returns the most recently added instruction.
    public func lastInstruction() -> Instruction {
        assert(currentNumberOfInstructions > 0)
        return code.lastInstruction
    }

    /// Add a trace comment to the currently generated program at the current position.
    /// This is only done if inspection is enabled.
    public func trace(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.enableInspection {
            // Use an autoclosure here so that template strings are only evaluated when they are needed.
            comments.add(commentGenerator(), at: .instruction(code.count))
        }
    }

    /// Add a trace comment at the start of the currently generated program.
    /// This is only done if history inspection is enabled.
    public func traceHeader(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.enableInspection {
            comments.add(commentGenerator(), at: .header)
        }
    }

    ///
    /// Methods to obtain random values to use in a FuzzIL program.
    ///

    /// Returns a random integer value.
    public func randomInt() -> Int64 {
        if probability(0.5) {
            return chooseUniform(from: self.fuzzer.environment.interestingIntegers)
        } else {
            return withEqualProbability({
                Int64.random(in: -0x10...0x10)
            }, {
                Int64.random(in: -0x10000...0x10000)
            }, {
                Int64.random(in: Int64(Int32.min)...Int64(Int32.max))
            })
        }
    }

    /// Returns a random integer value suitable as size of for example an array.
    /// The returned value is guaranteed to be positive.
    public func randomSize(upTo maximum: Int64 = 0x100000000) -> Int64 {
        assert(maximum >= 0)
        if maximum < 0x1000 {
            return Int64.random(in: 0...maximum)
        } else if probability(0.5) {
            return chooseUniform(from: fuzzer.environment.interestingIntegers.filter({ $0 >= 0 && $0 <= maximum }))
        } else {
            return withEqualProbability({
                Int64.random(in: 0...0x10)
            }, {
                Int64.random(in: 0...0x100)
            }, {
                Int64.random(in: 0...0x1000)
            }, {
                Int64.random(in: 0...maximum)
            })
        }
    }

    /// Returns a random non-negative integer value suitable as index.
    public func randomNonNegativeIndex(upTo max: Int64 = 0x100000000) -> Int64 {
        // Prefer small indices.
        if max > 10 && probability(0.33) {
            return Int64.random(in: 0...10)
        } else {
            return randomSize(upTo: max)
        }
    }

    /// Returns a random integer value suitable as index.
    public func randomIndex() -> Int64 {
        // Prefer small, (usually) positive, indices.
        if probability(0.33) {
            return Int64.random(in: -2...10)
        } else {
            return randomSize()
        }
    }

    /// Returns a random floating point value.
    public func randomFloat() -> Double {
        if probability(0.5) {
            return chooseUniform(from: fuzzer.environment.interestingFloats)
        } else {
            return withEqualProbability({
                Double.random(in: 0.0...1.0)
            }, {
                Double.random(in: -10.0...10.0)
            }, {
                Double.random(in: -1000.0...1000.0)
            }, {
                Double.random(in: -1000000.0...1000000.0)
            }, {
                // We cannot do Double.random(in: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude) here,
                // presumably because that range is larger than what doubles can represent? So split the range in two.
                if probability(0.5) {
                    return Double.random(in: -Double.greatestFiniteMagnitude...0)
                } else {
                    return Double.random(in: 0...Double.greatestFiniteMagnitude)
                }
            })
        }
    }

    /// Returns a random string value.
    public func randomString() -> String {
        return withEqualProbability({
            self.randomPropertyName()
        }, {
            self.randomMethodName()
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingStrings)
        }, {
            String(self.randomInt())
        }, {
            String.random(ofLength: Int.random(in: 1...5))
        })
    }

    public func randomBytes() -> [UInt8] {
        let size = withProbability(0.9) {
            Int.random(in: 0...127)
        } else: {
            Int.random(in:128...1024)
        }
        return (0..<size).map {_ in UInt8.random(in: UInt8.min ... UInt8.max)}
    }

    func randomRegExpPattern(compatibleWithFlags flags: RegExpFlags) -> String {
        // Generate a "base" regexp
        var regex = ""
        let desiredLength = Int.random(in: 1...4)
        while regex.count < desiredLength {
            regex += withEqualProbability({
                String.random(ofLength: 1)
            }, {
                // Pick from the available RegExp pattern, based on flags.
                let candidates = self.fuzzer.environment.interestingRegExps.filter({ pattern, incompatibleFlags in flags.isDisjoint(with: incompatibleFlags) })
                return chooseUniform(from: candidates).pattern
            })
        }

        // Now optionally concatenate with another regexp
        if probability(0.3) {
            regex += randomRegExpPattern(compatibleWithFlags: flags)
        }

        // Or add a quantifier, if there is not already a quantifier in the last position.
        if probability(0.2) && !self.fuzzer.environment.interestingRegExpQuantifiers.contains(String(regex.last!)) {
            regex += chooseUniform(from: self.fuzzer.environment.interestingRegExpQuantifiers)
        }

        // Or wrap in brackets
        if probability(0.1) {
            withEqualProbability({
                // optionally invert the character set
                if probability(0.2) {
                    regex = "^" + regex
                }
                regex = "[" + regex + "]"
            }, {
                regex = "(" + regex + ")"
            })
        }
        return regex
    }

    /// Returns a random regular expression pattern.
    public func randomRegExpPatternAndFlags() -> (String, RegExpFlags) {
        let flags = RegExpFlags.random()
        return (randomRegExpPattern(compatibleWithFlags: flags), flags)
    }

    /// Returns the name of a random builtin.
    public func randomBuiltin() -> String {
        return chooseUniform(from: fuzzer.environment.builtins)
    }

    /// Returns a random builtin property name.
    ///
    /// This will return a random name from the environment's list of builtin property names,
    /// i.e. a property that exists on (at least) one builtin object type.
    func randomBuiltinPropertyName() -> String {
        return chooseUniform(from: fuzzer.environment.builtinProperties)
    }

    /// Returns a random custom property name.
    ///
    /// This will select a random property from a (usually relatively small) set of custom property names defined by the environment.
    ///
    /// This should generally be used in one of two situations:
    ///   1. If a new property is added to an object.
    ///     In that case, we prefer to add properties with custom names (e.g. ".a", ".b") instead of properties
    ///     with names that exist in the environment (e.g. ".length", ".prototype"). This way, in the resulting code
    ///     it will be fairly clear when a builtin property is accessed vs. a custom one. It also increases the chances
    ///     of selecting an existing property when choosing a random property to access, see the next point.
    ///   2. If we have no static type information about the object we're accessing.
    ///     In that case there is a higher chance of success when using the small set of custom property names
    ///     instead of the much larger set of all property names that exist in the environment (or something else).
    public func randomCustomPropertyName() -> String {
        return chooseUniform(from: fuzzer.environment.customProperties)
    }

    /// Returns either a builtin or a custom property name, with equal probability.
    public func randomPropertyName() -> String {
        return probability(0.5) ? randomBuiltinPropertyName() : randomCustomPropertyName()
    }

    /// Returns a random builtin method name.
    ///
    /// This will return a random name from the environment's list of builtin method names,
    /// i.e. a method that exists on (at least) one builtin object type.
    public func randomBuiltinMethodName() -> String {
        return chooseUniform(from: fuzzer.environment.builtinMethods)
    }

    /// Returns a random custom method name.
    ///
    /// This will select a random method from a (usually relatively small) set of custom method names defined by the environment.
    ///
    /// See the comment for randomCustomPropertyName() for when this should be used.
    public func randomCustomMethodName() -> String {
        return chooseUniform(from: fuzzer.environment.customMethods)
    }

    /// Returns either a builtin or a custom method name, with equal probability.
    public func randomMethodName() -> String {
        return probability(0.5) ? randomBuiltinMethodName() : randomCustomMethodName()
    }

    private static func generateConstrained<T: Equatable>(
            _ generator: () -> T,
            notIn: any Collection<T>,
            fallback: () -> T) -> T {
        var result: T
        var attempts = 0
        repeat {
            if attempts >= 10 {
                return fallback()
            }
            result = generator()
            attempts += 1
        } while notIn.contains(result)
        return result
    }

    // Generate a string not already contained in `notIn` using the provided `generator`. If it fails
    // repeatedly, return a random string instead.
    public func generateString(_ generator: () -> String, notIn: any Collection<String>) -> String {
        Self.generateConstrained(generator, notIn: notIn,
            fallback: {String.random(ofLength: Int.random(in: 1...5))})
    }

    // Find a random variable to use as a string that isn't contained in `notIn`. If it fails
    // repeatedly, create a random string literal instead.
    public func findOrGenerateStringLikeVariable(notIn: any Collection<Variable>) -> Variable {
        return Self.generateConstrained(randomJsVariable, notIn: notIn,
            fallback: {loadString(String.random(ofLength: Int.random(in: 1...5)))})
    }

    // Settings and constants controlling the behavior of randomParameters() below.
    // This determines how many variables of a given type need to be visible before
    // that type is considered a candidate for a parameter type. For example, if this
    // is three, then we need at least three visible .integer variables before creating
    // parameters of type .integer.
    private let thresholdForUseAsParameter = 3

    // The probability of using .jsAnything as parameter type even though we have more specific alternatives.
    // Doing this sometimes is probably beneficial so that completely random values are passed to the function.
    // Future mutations, such as the ExplorationMutator can then figure out what to do with the parameters.
    // Writable so it can be changed for tests.
    var probabilityOfUsingAnythingAsParameterTypeIfAvoidable = 0.20

    // Generate random parameters for a subroutine.
    //
    // This will attempt to find a parameter types for which at least a few variables of a compatible types are
    // currently available to (potentially) later be used as arguments for calling the generated subroutine.
    public func randomParameters(n wantedNumberOfParameters: Int? = nil) -> SubroutineDescriptor {
        assert(probabilityOfUsingAnythingAsParameterTypeIfAvoidable >= 0 && probabilityOfUsingAnythingAsParameterTypeIfAvoidable <= 1)

        // If the caller didn't specify how many parameters to generated, find an appropriate
        // number of parameters based on how many variables are currently visible (and can
        // therefore later be used as arguments for calling the new function).
        let n: Int
        if let requestedN = wantedNumberOfParameters {
            assert(requestedN > 0)
            n = requestedN
        } else {
            switch numberOfVisibleVariables {
            case 0...1:
                n = 0
            case 2...5:
                n = Int.random(in: 1...2)
            default:
                n = Int.random(in: 2...4)
            }
        }

        // Find all types of which we currently have at least a few visible variables that we could later use as arguments.
        // TODO: improve this code by using some kind of cache? That could then also be used for randomVariable(ofType:) etc.
        var availableVariablesByType = [ILType: Int]()
        for v in visibleVariables where type(of: v).Is(.jsAnything) {
            let t = type(of: v)
            // TODO: should we also add this values to the buckets for supertypes (without this becoming O(n^2))?
            // TODO: alternatively just check for some common union types, e.g. .number, .primitive, as long as these can be used meaningfully?
            availableVariablesByType[t] = (availableVariablesByType[t] ?? 0) + 1
        }

        var candidates = Array(availableVariablesByType.filter({ k, v in v >= thresholdForUseAsParameter }).keys)
        if candidates.isEmpty {
            candidates.append(.jsAnything)
        }

        var params = ParameterList()
        for _ in 0..<n {
            if probability(probabilityOfUsingAnythingAsParameterTypeIfAvoidable) {
                params.append(.jsAnything)
            } else {
                params.append(.plain(chooseUniform(from: candidates)))
            }
        }

        // TODO: also generate rest parameters and maybe even optional ones sometimes?

        return .parameters(params)
    }

    public func findOrGenerateArguments(forSignature signature: Signature, maxNumberOfVariablesToGenerate: Int = 100) -> [Variable] {
        assert(context.contains(.javascript))

        argumentGenerationVariableBudget.push(numVariables + maxNumberOfVariablesToGenerate)
        argumentGenerationSignature.push(signature)

        defer {
            argumentGenerationVariableBudget.pop()
            argumentGenerationSignature.pop()
        }

        return findOrGenerateArgumentsInternal(forSignature: signature)
    }

    private func findOrGenerateArgumentsInternal(forSignature: Signature) -> [Variable] {
        var args: [Variable] = []
        outer: for parameter in forSignature.parameters {
            switch parameter {
            case .plain(let t):
                args.append(generateTypeInternal(t))
            case .opt(let t):
                if probability(0.5) {
                    args.append(generateTypeInternal(t))
                } else {
                    // We decided to not provide an optional parameter, so we can stop here.
                    break outer
                }
            case .rest(let t):
                for _ in 0...Int.random(in: 1...3) {
                    args.append(generateTypeInternal(t))
                }
            }
        }

        return args
    }

    // This should be called whenever we have a type that has known information about its properties but we don't have a constructor for it.
    // This can be the case for configuration objects, e.g. objects that can be passed into DOMAPIs.
    private func createObjectWithProperties(_ type: ILType) -> Variable  {
        assert(type.MayBe(.object()))

        // Before we do any generation below, let's take into account that we already create a variable with this invocation, i.e. the createObject at the end.
        // Therefore we need to decrease the budget here temporarily.
        self.argumentGenerationVariableBudget.top -= 1
        // We defer the increase again, because at that point the variable is actually visible, i.e. `numVariables` was increased through the `createObject` call.
        defer { self.argumentGenerationVariableBudget.top += 1 }

        var properties: [String: Variable] = [:]

        for propertyName in type.properties {
            // If we have an object that has a group, we should get a type here, otherwise if we don't have a group, we will get .jsAnything.
            let propType = fuzzer.environment.type(ofProperty: propertyName, on: type)
            properties[propertyName] = generateTypeInternal(propType)
        }

        return createObject(with: properties)
    }

    public func findOrGenerateType(_ type: ILType, maxNumberOfVariablesToGenerate: Int = 100) -> Variable {
        assert(context.contains(.javascript))

        argumentGenerationVariableBudget.push(numVariables + maxNumberOfVariablesToGenerate)

        defer {
            argumentGenerationVariableBudget.pop()
        }

        return generateTypeInternal(type)
    }

    // If the type is a builtin constructor like Promise or Temporal.Instant, generate
    // a path to it from field accesses.
    private func maybeGenerateConstructorAsPath(_ type: ILType) -> Variable? {
        guard let group = type.group else {
            return nil
        }
        guard let path = self.fuzzer.environment.getPathIfConstructor(ofGroup: group) else {
            return nil
        }
        var current = createNamedVariable(forBuiltin: path[0])
        for element in path.dropFirst() {
            current = getProperty(element, of: current)
        }
        assert(self.type(of: current).Is(type), "Registered constructorPath produces incorrect type for ObjectGroup \(group)")
        return current
    }

    private func generateTypeInternal(_ type: ILType) -> Variable {
        if probability(0.9) && !type.isEnumeration {
            if let existingVariable = randomVariable(ofTypeOrSubtype: type) {
                return existingVariable
            }
        }

        // For builtin constructors from the JavaScriptEnvironment, just generate them.
        if let ret = self.maybeGenerateConstructorAsPath(type) {
            return ret
        }

        if numVariables >= argumentGenerationVariableBudget.top {
            if !argumentGenerationSignature.isEmpty {
                logger.warning("Reached variable generation limit in generateType for Signature: \(argumentGenerationSignature.top), returning a random variable for use as type \(type).")
            } else {
              logger.warning("Reached variable generation limit in generateType, returning a random variable for use as type \(type).")
            }
            return randomVariable(forUseAs: type)
        }

        // We only need to check against all base types from TypeSystem.swift, this works because we use .MayBe
        // TODO: Not sure how we should handle merge types, e.g. .string + .object(...).
        let typeGenerators: [(ILType, () -> Variable)] = [
            (.integer, { return self.loadInt(self.randomInt()) }),
            (.string, {
                if type.isEnumeration {
                    return self.loadEnum(type)
                }
                if let typeName = type.group,
                   let customStringGen = self.fuzzer.environment.getNamedStringGenerator(ofName: typeName) {
                    return self.loadString(customStringGen(), customName: typeName)
                }
                return self.loadString(self.randomString()) }),
            (.boolean, { return self.loadBool(probability(0.5)) }),
            (.bigint, { return self.loadBigInt(self.randomInt()) }),
            (.float, { return self.loadFloat(self.randomFloat()) }),
            (.regexp, {
                    let (pattern, flags) = self.randomRegExpPatternAndFlags()
                    return self.loadRegExp(pattern, flags)
                }),
            (.function(), {
                    // TODO: We could technically generate a full function here but then we would enter the full code generation logic which could do anything.
                    // Because we want to avoid this, we will just pick anything that can be a function.
                    //
                    // Note that builtin constructors are handled above in the maybeGenerateConstructorAsPath call.
                    return self.randomVariable(forUseAs: .function())
                }),
            (.unboundFunction(), {
                // TODO: We have the same issue as above for functions.
                // First try to find an existing unbound function. if not present, try to find any
                // function. Using any function as an unbound function is fine, it just misses the
                // information about the receiver type (which for many functions doesn't matter).
                return self.randomVariable(ofType: .unboundFunction()) ?? self.randomVariable(forUseAs: .function())
            }),
            (.undefined, { return self.loadUndefined() }),
            (.constructor(), {
                    // TODO: We have the same issue as above for functions.
                    //
                    // Note that builtin constructors are handled above in the maybeGenerateConstructorAsPath call.
                    return self.randomVariable(forUseAs: .constructor())
                }),
            (.wasmTypeDef(), {
                // Call into the WasmTypeGroup generator (or other that provide a .wasmTypeDef)
                let generators = self.fuzzer.codeGenerators.filter { gen in
                    gen.produces.contains { type in
                        type.Is(.wasmTypeDef())
                    }
                }
                let _ = self.complete(generator: generators.randomElement(), withBudget: 5)
                return self.randomVariable(ofType: .wasmTypeDef())!
            }),
            (.object(), {
                func useMethodToProduce(_ method: (group: String, method: String)) -> Variable {
                    let group = self.fuzzer.environment.type(ofGroup: method.group)
                    let obj = self.generateTypeInternal(group)
                    let sig = chooseUniform(
                    from: self.fuzzer.environment
                        .signatures(ofMethod: method.method, on: group).filter({
                        self.fuzzer.environment.isSubtype($0.outputType, of: type)
                        }))

                    let args = self.findOrGenerateArgumentsInternal(forSignature: sig)
                    return self.callMethod(method.method, on: obj, withArgs: args)
                }

                func usePropertyToProduce(_ property: (group: String, property: String)) -> Variable {
                    // If no ObjectGroup is defined, the property is a builtin.
                    if property.group == "" {
                        let builtinType = self.fuzzer.environment.type(ofBuiltin: property.property)
                        let prop = self.createNamedVariable(forBuiltin: property.property)
                        if builtinType.Is(type) {
                            return prop
                        } else {
                            // This is a constructor, we have to call it.
                            let sig = builtinType.signature
                            if sig == nil {
                                let result = self.randomJsVariable()
                                return result
                            }
                            let args = self.findOrGenerateArgumentsInternal(forSignature: sig!)
                            return self.construct(prop, withArgs: args)
                        }
                    }
                    let group = self.fuzzer.environment.type(ofGroup: property.group)
                    let obj = self.generateTypeInternal(group)
                    let prop = self.getProperty(property.property, of: obj)
                    if self.type(of: prop).Is(type) {
                        return prop
                    } else {
                        // This is a constructor, we have to call it.
                        let sig = self.type(of: prop).signature
                        if sig == nil {
                            let result = self.randomJsVariable()
                            return result
                        }
                        let args = self.findOrGenerateArgumentsInternal(forSignature: sig!)
                        return self.construct(prop, withArgs: args)
                    }
                }

                // If we have a producing generator, we aren't going to get this type from elsewhere
                // so try and generate it using the generator in most cases
                let producingGenerator = self.fuzzer.environment.getProducingGenerator(ofType: type);
                if let producingGenerator {
                    if probability(producingGenerator.probability) {
                        return producingGenerator.generator(self)
                    }
                }

                let producingMethods = self.fuzzer.environment.getProducingMethods(ofType: type)
                let producingProperties = self.fuzzer.environment.getProducingProperties(ofType: type)
                let globalProperties = producingProperties.filter() {(group: String, property: String) in
                    // Global properties are those that don't belong to a group, i.e. where the group is empty.
                    return group == ""
                }
                // If there is a global property or builtin for this type, use it with high probability.
                if !globalProperties.isEmpty && probability(0.9) {
                    return usePropertyToProduce(globalProperties.randomElement()!)
                }
                let maybeMethod = producingMethods.randomElement()
                let maybeProperty = producingProperties.randomElement()
                if let method = maybeMethod ,let property = maybeProperty {
                    if probability(Double(producingMethods.count) / Double(producingMethods.count + producingProperties.count)) {
                        return useMethodToProduce(method)
                    } else {
                        return usePropertyToProduce(property)
                    }
                } else if let method = maybeMethod {
                    return useMethodToProduce(method)
                } else if let property = maybeProperty {
                    return usePropertyToProduce(property)
                }
                let generators = self.fuzzer.codeGenerators.filter({
                    // Right now only use generators that require a single context.
                    $0.parts.last!.requiredContext.isSingle &&
                    $0.parts.last!.requiredContext.satisfied(by: self.context) &&
                    $0.parts.last!.produces.contains(where: { producedType in
                        producedType.Is(type)
                    })
                })
                if generators.count > 0 {
                    let generator = generators.randomElement()
                    let _ = self.complete(generator: generator, withBudget: 10)
                    // The generator we ran above is supposed to generate the
                    // requested type. If no variable of that type exists
                    // now, then either the generator or its annotation is
                    // wrong.
                    return self.randomVariable(ofTypeOrSubtype: type)!
                }
                // Otherwise this is one of the following:
                // 1. an object with more type information, i.e. it has a group, but no associated builtin, e.g. we cannot construct it with new.
                // 2. an object without a group, but it has some required fields.
                // In either case, we try to construct such an object.
                return self.createObjectWithProperties(type)
            })
        ]

        // Make sure that we walk over these tests and their generators randomly.
        // The requested type could be a Union of other types and as such we want to randomly generate one of them,
        // therefore we also use the MayBe test below. However, if we need an object, then we have to produce an
        // object.
        for (t, generate) in typeGenerators.shuffled() {
            if type.Is(t) || (!type.Is(.object()) && type.MayBe(t)) {
                let variable = generate()
                return variable
            }
        }

        logger.warning("Type \(type) was not handled, returning random variable.")
        return randomVariable(forUseAs: type)
    }

    ///
    /// Access to variables.
    ///

    /// Returns a random JavaScript variable.
    public func randomJsVariable() -> Variable {
        assert(hasVisibleVariables)
        return randomVariable(ofType: .jsAnything)!
    }

    /// Returns up to N (different) random JavaScript variables.
    /// This method will only return fewer than N variables if the number of currently visible variables is less than N.
    public func randomJsVariables(upTo n: Int) -> [Variable] {
        guard hasVisibleVariables else { return [] }

        var variables = [Variable]()
        while variables.count < n {
            guard let newVar = findVariable(satisfying: { !variables.contains($0) && type(of: $0).Is(.jsAnything) }) else {
                break
            }
            variables.append(newVar)
        }
        return variables
    }

    /// Returns up to N potentially duplicate random JavaScript variables.
    public func randomJsVariables(n: Int) -> [Variable] {
        assert(hasVisibleVariables)
        return (0..<n).map { _ in randomJsVariable() }
    }

    /// This probability affects the behavior of `randomVariable(forUseAs:)`. In particular, it determines how much variables with
    /// a known-to-be-matching type will be preferred over variables with a more general, or even unknown type. For example, if this is
    /// 0.5, then 50% of the time we'll first try to find an exact match (`type(of: result).Is(requestedType)`) before trying the
    /// more general search (`type(of: result).MayBe(requestedType)`) which also includes variables of unknown type.
    /// This is writable for use in tests, but it could also be used to change how "conservative" variable selection is.
    var probabilityOfVariableSelectionTryingToFindAnExactMatch = 0.5

    /// Returns a random variable to be used as the given type.
    ///
    /// This function may return variables of a different type, or variables that may have the requested type, but could also have a different type.
    /// For example, when requesting a .integer, this function may also return a variable of type .number, .primitive, or even .jsAnything as all of these
    /// types may be an integer (but aren't guaranteed to be). In this way, this function ensures that variables for which no exact type could be statically
    /// determined will also be used as inputs for following code.
    ///
    /// It's the caller's responsibility to check the type of the returned variable to avoid runtime exceptions if necessary. For example, if performing a
    /// property access, the returned variable should be checked if it `MayBe(.nullish)` in which case a property access would result in a
    /// runtime exception and so should be appropriately guarded against that.
    /// This function also returns a boolean, `matches`. If matches is not true, it means that value being returned either `MayBe` the type requested, or
    /// is a random JsVariable.
    ///
    /// If the variable must be of the specified type, use `randomVariable(ofType:)` instead.
    public func randomVariable(forUseAsGuarded type: ILType) -> (variable: Variable, matches: Bool) {
        assert(type != .nothing)

        var result: Variable? = nil
        var matches = true

        // Prefer variables that are known to have the requested type if there's a sufficient number of them.
        if probability(probabilityOfVariableSelectionTryingToFindAnExactMatch) {
            result = findVariable(satisfying: { self.type(of: $0).Is(type) })
        }

        // Otherwise, select variables that may have the desired type, but could also be something else.
        // In particular, this query will include all variable for which we don't know the type as they'll
        // be typed as .jsAnything. We usually expect to have a lot of candidates available for this query,
        // so we don't check the number of them upfront as we do for the above query.
        // If findVariable(satisfying: { self.type(of: $0).Is(type) }) returned nil, we cannot be sure that
        // the result matches the requested type, so we set matches to be false.
        if result == nil {
            matches = false
            result = findVariable(satisfying: { self.type(of: $0).MayBe(type) })
        }

        // Worst case fall back to completely random variables. This should happen rarely, as we'll usually have
        // at least some variables of type .jsAnything.
        return (result ?? randomJsVariable(), matches)
    }

    /// This function is a wrapper around `randomVariable(forUseAsGuarded type:)' which ignores the `matches`
    /// value that it returns.
    /// See the comment above the other function for details.
    public func randomVariable(forUseAs type: ILType) -> Variable {
        assert(type != .nothing)
        return randomVariable(forUseAsGuarded: type).variable
    }

    /// Returns a random variable that is known to have the given type.
    ///
    /// This will return a variable for which `b.type(of: v).Is(type)` is true, i.e. for which our type inference
    /// could prove that it will have the specified type. If no such variable is found, this function returns nil.
    public func randomVariable(ofType type: ILType) -> Variable? {
        assert(type != .nothing)
        return findVariable(satisfying: { self.type(of: $0).Is(type) })
    }

    public func randomVariable(ofTypeOrSubtype type: ILType) -> Variable? {
        assert(type != .nothing)
        return findVariable() { (variable: Variable) in
            fuzzer.environment.isSubtype(self.type(of: variable), of: type)
        }
    }

    /// Returns a random variable that is not known to have the given type.
    ///
    /// This will return a variable for which `b.type(of: v).Is(type)` is false, i.e. for which our type inference
    /// could not prove that it has the given type. Note that this is different from a variable that is known not to have
    /// the given type: this function can return variables for which `b.type(of: v).MayBe(type)` is true.
    /// If no such variable is found, this function returns nil.
    public func randomVariable(preferablyNotOfType type: ILType) -> Variable? {
        return findVariable(satisfying: { !self.type(of: $0).Is(type) })
    }

    /// Returns a random variable satisfying the given constraints or nil if none is found.
    public func findVariable(satisfying filter: ((Variable) -> Bool) = { _ in true }) -> Variable? {
        assert(hasVisibleVariables)

        // TODO: we should implement some kind of fast lookup data structure to speed up the lookup of variables by type.
        // We have to be careful though to correctly take type changes (e.g. from reassignments) into account.

        // Also filter out any hidden variables.
        var isIncluded = filter
        if numberOfHiddenVariables != 0 {
            isIncluded = { !self.hiddenVariables.contains($0) && filter($0) }
        }

        var candidates = [Variable]()

        // Prefer the outputs of the last instruction to build longer data-flow chains.
        if probability(0.15) {
            candidates = Array(code.lastInstruction.allOutputs)
            candidates = candidates.filter(isIncluded)
        }

        // Prefer inner scopes if we're not anyway using one of the newest variables.
        let scopes = scopes
        if candidates.isEmpty && probability(0.75) {
            candidates = chooseBiased(from: scopes.elementsStartingAtBottom(), factor: 1.25)
            candidates = candidates.filter(isIncluded)
        }

        // If we haven't found any candidates yet, take all visible variables into account.
        if candidates.isEmpty {
            candidates = variablesInScope.filter(isIncluded)
        }

        if candidates.isEmpty {
            return nil
        }

        return chooseUniform(from: candidates)
    }

    /// Find random variables to use as arguments for calling the specified function.
    ///
    /// This function will attempt to find variables that are compatible with the functions parameter types (if any). However,
    /// if no matching variables can be found for a parameter, this function will fall back to using a random variable. It is
    /// then the caller's responsibility to determine whether the function call can still be performed without raising a runtime
    /// exception or if it needs to be guarded against that.
    /// In this way, functions/methods for which no matching arguments currently exist can still be called (but potentially
    /// wrapped in a try-catch), which then gives future mutations (in particular Mutators such as the ProbingMutator) the
    /// chance to find appropriate arguments for the function.
    public func randomArguments(forCalling function: Variable) -> [Variable] {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction
        return randomArguments(forCallingFunctionWithSignature: signature)
    }

    /// Find random variables to use as arguments for calling the specified method.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingMethod methodName: String, on object: Variable) -> [Variable] {
        let signature = chooseUniform(from: methodSignatures(of: methodName, on: object))
        return randomArguments(forCallingFunctionWithSignature: signature)
    }

    /// Find random variables to use as arguments for calling the specified method.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingMethod methodName: String, on objType: ILType) -> [Variable] {
        let signature = chooseUniform(from: methodSignatures(of: methodName, on: objType))
        return randomArguments(forCallingFunctionWithSignature: signature)
    }

    /// Find random variables to use as arguments for calling a function with the specified signature.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingFunctionWithSignature signature: Signature) -> [Variable] {
        return randomArguments(forCallingFunctionWithParameters: signature.parameters)
    }

    /// Find random variables to use as arguments for calling a function with the given parameters.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingFunctionWithParameters params: ParameterList) -> [Variable] {
        assert(params.count == 0 || hasVisibleVariables)
        let parameterTypes = ProgramBuilder.prepareArgumentTypes(forParameters: params)
        return parameterTypes.map({ randomVariable(forUseAs: $0) })
    }

    /// Find random variables to use as arguments for calling a function with the given parameters.
    ///
    /// If any of the arguments returned does not match the type of its corresponding parameter,
    /// the boolean this function returns will be true. If everything matches, it will be false.
    public func randomArguments(forCallingGuardableFunction function: Variable) -> (arguments: [Variable], allArgsMatch: Bool) {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction
        let params = signature.parameters
        assert(params.count == 0 || hasVisibleVariables)

        let parameterTypes = ProgramBuilder.prepareArgumentTypes(forParameters: params)

        var variables: [Variable] = []
        var allArgsMatch = true
        for type in parameterTypes {
            let (variable, matches) = randomVariable(forUseAsGuarded: type)
            variables.append(variable)
            allArgsMatch = allArgsMatch && matches
        }

        return (variables, allArgsMatch)
    }


    /// Converts the JS world signature into a Wasm world signature.
    /// In practice this means that we will try to map JS types to corresponding Wasm types.
    /// E.g. .number becomes .wasmf32, .bigint will become .wasmi64, etc.
    /// The result of this conversion is not deterministic if the type does not map directly to a Wasm type.
    /// I.e. .object might be converted to .wasmf32 or .wasmExternRef.
    /// Use this function to generate arguments for a WasmJsCall operation and attach the converted signature to
    /// the WasmJsCall instruction.
    public func randomWasmArguments(forCallingJsFunction function: Variable) -> (WasmSignature, [Variable])? {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction

        var visibleTypes = [ILType: Int]()

        // Find all available wasm types, we assume to be in .wasm Context here.
        assert(context.contains(.wasmFunction))
        for v in visibleVariables {
            // Filter for primitive wasm types here.
            let t = type(of: v)
            // TODO(mliedtke): Support wasm-gc types in wasm-js calls.
            if t.Is(.wasmPrimitive) && !t.Is(.wasmGenericRef) {
                visibleTypes[t] = (visibleTypes[t] ?? 0) + 1
            }
        }

        if visibleTypes.isEmpty {
            return nil
        }

        var weightedTypes = WeightedList<ILType>()
        for (t, w) in visibleTypes {
            weightedTypes.append(t, withWeight: w)
        }

        // This already does an approximation of the JS signature
        let newSignature = ProgramBuilder.convertJsSignatureToWasmSignature(signature, availableTypes: weightedTypes)

        guard let variables = randomWasmArguments(forWasmSignature: newSignature) else {
            return nil
        }

        return (newSignature, variables)
    }

    public func randomWasmArguments(forWasmSignature signature: WasmSignature) -> [Variable]? {
        var variables = [Variable]()
        for parameterType in signature.parameterTypes {
            if let v = randomVariable(ofType: parameterType) {
                variables.append(v)
            } else {
                return nil
            }
        }

        return variables
    }

    // We simplify the signature by first converting it into types, approximating this signature by getting the corresponding Wasm world types.
    // Then we convert that back into a signature with only .plain types and attach that to the WasmJsCall instruction.
    public static func convertJsSignatureToWasmSignature(_ signature: Signature, availableTypes types: WeightedList<ILType>) -> WasmSignature {
        let parameterTypes = prepareArgumentTypes(forParameters: signature.parameters).map { approximateWasmTypeFromJsType($0, availableTypes: types) }
        let outputType = mapJsToWasmType(signature.outputType)
        return WasmSignature(expects: parameterTypes, returns: [outputType])
    }

    public static func convertWasmSignatureToJsSignature(_ signature: WasmSignature) -> Signature {
        let parameterTypes = signature.parameterTypes.map(mapWasmToJsType)
        // If we return multiple values it will just be an Array in JavaScript.
        let returnType = signature.outputTypes.count == 0 ? ILType.undefined
        : signature.outputTypes.count == 1 ? mapWasmToJsType(signature.outputTypes[0])
        : .jsArray
        return Signature(expects: parameterTypes.map(Parameter.plain), returns: returnType)
    }

    public static func convertJsSignatureToWasmSignatureDeterministic(_ signature: Signature) -> WasmSignature {
        let parameterTypes = prepareArgumentTypesDeterministic(forParameters: signature.parameters).map { mapJsToWasmType($0) }
        let outputType = mapJsToWasmType(signature.outputType)
        return WasmSignature(expects: parameterTypes, returns: [outputType])
    }

    /// Find random arguments for a function call and spread some of them.
    public func randomCallArgumentsWithSpreading(n: Int) -> (arguments: [Variable], spreads: [Bool]) {
        var arguments: [Variable] = []
        var spreads: [Bool] = []
        for _ in 0...n {
            let val = randomJsVariable()
            arguments.append(val)
            // Prefer to spread values that we know are iterable, as non-iterable values will lead to exceptions ("TypeError: Found non-callable @@iterator")
            if type(of: val).Is(.iterable) {
                spreads.append(probability(0.9))
            } else {
                spreads.append(probability(0.1))
            }
        }

        return (arguments, spreads)
    }

    /// Hide the specified variable, preventing it from being used as input by subsequent code.
    ///
    /// Hiding a variable prevents it from being returned from `randomJsVariable()` and related functions, which
    /// in turn prevents it from being used as input for later instructions, unless the hidden variable is explicitly specified
    /// as input, which is still allowed.
    ///
    /// This can be useful for example if a CodeGenerator needs to create temporary values that should not be used
    /// by any following code. It is also used to prevent trivial recursion by hiding the function variable inside its body.
    public func hide(_ variable: Variable) {
        assert(!hiddenVariables.contains(variable))
        assert(visibleVariables.contains(variable))

        hiddenVariables.insert(variable)
        numberOfHiddenVariables += 1
    }

    /// Unhide the specified variable so that it can again be used as input by subsequent code.
    ///
    /// The variable must have previously been hidden using `hide(variable:)` above.
    public func unhide(_ variable: Variable) {
        assert(numberOfHiddenVariables > 0)
        assert(hiddenVariables.contains(variable))
        assert(variablesInScope.contains(variable))
        assert(!visibleVariables.contains(variable))

        hiddenVariables.remove(variable)
        numberOfHiddenVariables -= 1
    }

    private static func matchingWasmTypes(jsType: ILType) -> [ILType] {
        if jsType.Is(.integer) {
            return [.wasmi32, .wasmf64, .wasmf32]
        } else if jsType.Is(.number) {
            return [.wasmf32, .wasmf64, .wasmi32, .wasmRefI31, .wasmI31Ref]
        } else if jsType.Is(.bigint) {
            return [.wasmi64]
        } else if jsType.Is(.function()) {
            // TODO(gc): Add support for specific signatures.
            return [.wasmFuncRef]
        } else {
            // TODO(gc): Add support for types of the anyref hierarchy.
            return [.wasmExternRef]
        }
    }

    // Helper that converts a JS type to its deterministic known Wasm counterpart.
    private static func mapJsToWasmType(_ type: ILType) -> ILType {
        return matchingWasmTypes(jsType: type)[0]
    }

    // Helper that converts a Wasm type to its deterministic known JS counterparts.
    private static func mapWasmToJsType(_ type: ILType) -> ILType {
        if type.Is(.wasmi32) {
            return .integer
        } else if type.Is(.wasmf32) {
            return .float
        } else if type.Is(.wasmf64) {
            return .float
        } else if type.Is(.wasmi64) {
            return .bigint
        } else if type.Is(.wasmSimd128) {
            // We should not see these in JS per spec but we might export them, as such type them as .jsAnything for now.
            // Consider passing the .wasmSimd128 through somehow, such that it's unlikely that it gets called?
            // https://github.com/WebAssembly/simd/blob/main/proposals/simd/SIMD.md#javascript-api-and-simd-values
            return .jsAnything
        } else if type.Is(.nothing) {
            return .undefined
        } else if type.Is(.wasmFuncRef) {
            // TODO(cffsmith): refine this type with the signature if we can.
            return .function()
        } else if type.Is(.wasmI31Ref) {
            return .integer
        } else if type.Is(.wasmNullRef) || type.Is(.wasmNullExternRef) || type.Is(.wasmNullFuncRef) {
            // This is slightly imprecise: The null types only accept null, not undefined but
            // Fuzzilli doesn't differentiate between null and undefined in its type system.
            return .nullish
        } else if type.Is(.wasmGenericRef) {
            return .jsAnything
        } else {
            fatalError("Unexpected type encountered: \(type).")
        }
    }

    // Helper function to convert JS Types to an arbitrary matching Wasm type or picks from the other available types-
    private static func approximateWasmTypeFromJsType(_ type: ILType, availableTypes: WeightedList<ILType>) -> ILType {
        let matchingTypes = matchingWasmTypes(jsType: type)
        let intersection = availableTypes.filter({type in matchingTypes.contains(type)})
        return intersection.count != 0 ? intersection.randomElement() : availableTypes.randomElement()
    }

    /// Type information access.
    public func type(of v: Variable) -> ILType {
        return jsTyper.type(of: v)
    }

    /// Returns the type of the `super` binding at the current position.
    public func currentSuperType() -> ILType {
        return jsTyper.currentSuperType()
    }

    /// Returns the type of the super constructor.
    public func currentSuperConstructorType() -> ILType {
        return jsTyper.currentSuperConstructorType()
    }

    public func type(ofProperty property: String, on v: Variable) -> ILType {
        return jsTyper.inferPropertyType(of: property, on: v)
    }

    public func methodSignatures(of methodName: String, on object: Variable) -> [Signature] {
        return jsTyper.inferMethodSignatures(of: methodName, on: object)
    }

    public func methodSignatures(of methodName: String, on objType: ILType) -> [Signature] {
        return jsTyper.inferMethodSignatures(of: methodName, on: objType)
    }

    /// Overwrite the current type of the given variable with a new type.
    /// This can be useful if a certain code construct is guaranteed to produce a value of a specific type,
    /// but where our static type inference cannot determine that.
    public func setType(ofVariable variable: Variable, to variableType: ILType) {
        jsTyper.setType(of: variable, to: variableType)
    }

    /// This helper function converts parameter types into argument types, for example by "unrolling" rest parameters and handling optional parameters.
    private static func prepareArgumentTypes(forParameters params: ParameterList) -> [ILType] {
        var argumentTypes = [ILType]()

        for param in params {
            switch param {
            case .rest(let t):
                // "Unroll" the rest parameter
                for _ in 0..<Int.random(in: 0...5) {
                    argumentTypes.append(t)
                }
            case .opt(let t):
                // It's an optional argument, so stop here in some cases
                if probability(0.25) {
                    return argumentTypes
                }
                fallthrough
            case .plain(let t):
                argumentTypes.append(t)
            }
        }

        return argumentTypes
    }

    private static func prepareArgumentTypesDeterministic(forParameters params: ParameterList) -> [ILType] {
        var argumentTypes = [ILType]()

        for param in params {
            switch param {
            case .rest(let t):
                // One repetition of the rest parameter
                argumentTypes.append(t)
            case .opt(_):
                // It's an optional argument, so stop here.
                return argumentTypes
            case .plain(let t):
                argumentTypes.append(t)
            }
        }

        return argumentTypes
    }

    ///
    /// Adoption of variables from a different program.
    /// Required when copying instructions between program.
    ///
    private var varMaps = [VariableMap<Variable>]()

    /// Prepare for adoption of variables from the given program.
    ///
    /// This sets up a mapping for variables from the given program to the
    /// currently constructed one to avoid collision of variable names.
    public func beginAdoption(from program: Program) {
        varMaps.append(VariableMap())
    }

    /// Finishes the most recently started adoption.
    public func endAdoption() {
        varMaps.removeLast()
    }

    /// Executes the given block after preparing for adoption from the provided program.
    public func adopting(from program: Program, _ block: () -> Void) {
        beginAdoption(from: program)
        block()
        endAdoption()
    }

    /// Maps a variable from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ variable: Variable) -> Variable {
        if !varMaps.last!.contains(variable) {
            varMaps[varMaps.count - 1][variable] = nextVariable()
        }

        return varMaps.last![variable]!
    }

    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt<Variables: Collection>(_ variables: Variables) -> [Variable] where Variables.Element == Variable {
        return variables.map(adopt)
    }

    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instr: Instruction) {
        internalAppend(Instruction(instr.op, inouts: adopt(instr.inouts), flags: instr.flags))
    }

    /// Append an instruction at the current position.
    public func append(_ instr: Instruction) {
        for v in instr.allOutputs {
            numVariables = max(v.number + 1, numVariables)
        }
        internalAppend(instr)
    }

    /// Append a program at the current position.
    ///
    /// This also renames any variable used in the given program so all variables
    /// from the appended program refer to the same values in the current program.
    public func append(_ program: Program) {
        adopting(from: program) {
            for instr in program.code {
                adopt(instr)
            }
        }
    }

    // Probabilities of remapping variables to host variables during splicing. These are writable so they can be reconfigured for testing.
    // We use different probabilities for outer and for inner outputs: while we rarely want to replace outer outputs, we frequently want to replace inner outputs
    // (e.g. function parameters) to avoid splicing function definitions that may then not be used at all. Instead, we prefer to splice only the body of such functions.
    var probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 0.10
    var probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing = 0.75
    // The probability of including an instruction that may mutate a variable required by the slice (but does not itself produce a required variable).
    var probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 0.5


    /// Splice code from the given program into the current program.
    ///
    /// Splicing computes a set of dependent (through dataflow) instructions in one program (called a "slice") and inserts it at the current position in this program.
    ///
    /// If the optional index is specified, the slice starting at that instruction is used. Otherwise, a random slice is computed.
    /// If mergeDataFlow is true, the dataflows of the two programs are potentially integrated by replacing some variables in the slice with "compatible" variables in the host program.
    /// Returns true on success (if at least one instruction has been spliced), false otherwise.
    @discardableResult
    public func splice(from program: Program, at specifiedIndex: Int? = nil, mergeDataFlow: Bool = true) -> Bool {
        // Splicing:
        //
        // Invariants:
        //  - A block is included in a slice in full (including its entire body) or not at all
        //  - An instruction can only be included if its required context is a subset of the current context
        //    OR if one or more of its surrounding blocks are included and all missing contexts are opened by them
        //  - An instruction can only be included if all its data-flow dependencies are included
        //    OR if the required variables have been remapped to existing variables in the host program
        //
        // Algorithm:
        //  1. Iterate over the program from start to end and compute for every block:
        //       - the inputs required by this block. This is the set of variables that are used as input
        //         for one or more instructions in the block's body, but are not created by instructions in the block
        //       - the context required by this block. This is the union of all contexts required by instructions
        //         in the block's body and subracting the context opened by the block itself
        //     In essence, this step allows treating every block start as a single instruction, which simplifies step 2.
        //  2. Iterate over the program from start to end and check which instructions can be inserted at the current
        //     position given the current context and the instruction's required context as well as the set of available
        //     variables and the variables required as inputs for the instruction. When deciding whether a block can be
        //     included, this will use the information computed in step 1 to treat the block as a single instruction
        //     (which it effectively is, as it will always be included in full). If an instruction can be included, its
        //     outputs are available for other instructions to use. If an instruction cannot be included, try to remap its
        //     outputs to existing and "compatible" variables in the host program so other instructions that depend on these
        //     variables can still be included. Also randomly remap some other variables to connect the dataflows of the two
        //     programs if that is enabled.
        //  3. Pick a random instruction from all instructions computed in step (2) or use the provided start index.
        //  4. Iterate over the program in reverse order and compute the slice: every instruction that creates an
        //     output needed as input for another instruction in the slice must be included as well. Step 2 guarantees that
        //     any such instruction can be part of the slice. Optionally, this step can also include instructions that may
        //     mutate variables required by the slice, for example property stores or method calls.
        //  5. Iterate over the program from start to end and add every instruction that is part of the slice into
        //     the current program, while also taking care of remapping the inouts, either to existing variables
        //     (if the variables were remapped in step (2)), or newly allocated variables.

        // Helper class to store various bits of information associated with a block.
        // This is a class so that each instruction belonging to the same block can have a reference to the same object.
        class Block {
            let startIndex: Int
            var endIndex = 0

            // Currently opened context. Updated at each block instruction.
            var currentlyOpenedContext: Context
            var requiredContext: Context

            var providedInputs = VariableSet()
            var requiredInputs = VariableSet()

            init(startedBy head: Instruction) {
                self.startIndex = head.index
                self.currentlyOpenedContext = head.op.contextOpened
                self.requiredContext = head.op.requiredContext
                self.requiredInputs.formUnion(head.inputs)
                self.providedInputs.formUnion(head.allOutputs)
            }
        }

        //
        // Step (1): compute the context- and data-flow dependencies of every block.
        //
        var blocks = [Int: Block]()

        // Helper functions for step (1).
        var activeBlocks = [Block]()
        func updateBlockDependencies(_ requiredContext: Context, _ requiredInputs: VariableSet) {
            guard let current = activeBlocks.last else { return }
            current.requiredContext.formUnion(requiredContext.subtracting(current.currentlyOpenedContext))
            current.requiredInputs.formUnion(requiredInputs.subtracting(current.providedInputs))
        }
        func updateBlockProvidedVariables(_ vars: ArraySlice<Variable>) {
            guard let current = activeBlocks.last else { return }
            current.providedInputs.formUnion(vars)
        }

        for instr in program.code {
            updateBlockDependencies(instr.op.requiredContext, VariableSet(instr.inputs))
            updateBlockProvidedVariables(instr.outputs)

            if instr.isBlockGroupStart {
                let block = Block(startedBy: instr)
                blocks[instr.index] = block
                activeBlocks.append(block)
            } else if instr.isBlockGroupEnd {
                let current = activeBlocks.removeLast()
                current.endIndex = instr.index
                blocks[instr.index] = current
                // Merge requirements into parent block (if any)
                updateBlockDependencies(current.requiredContext, current.requiredInputs)
                // If the block end instruction has any outputs, they need to be added to the surrounding block.
                updateBlockProvidedVariables(instr.outputs)
            } else if instr.isBlock {
                // We currently assume that inner block instructions cannot have outputs.
                // If they ever do, they'll need to be added to the surrounding block.
                assert(instr.numOutputs == 0)
                blocks[instr.index] = activeBlocks.last!

                // Inner block instructions change the execution context. Consider BeginWhileLoopBody as an example.
                activeBlocks.last?.currentlyOpenedContext = instr.op.contextOpened
            }

            updateBlockProvidedVariables(instr.innerOutputs)
        }

        //
        // Step (2): determine which instructions can be part of the slice and attempt to find replacement variables for the outputs of instructions that cannot be included.
        //
        // We need a typer to be able to find compatible replacement variables if we are merging the dataflows of the two programs.
        var typer = JSTyper(for: fuzzer.environment)
        // The set of variables that are available for a slice. A variable is available either because the instruction that outputs
        // it can be part of the slice or because the variable has been remapped to a host variable.
        var availableVariables = VariableSet()
        // Variables in the program that have been remapped to host variables.
        var remappedVariables = VariableMap<Variable>()
        // All instructions that can be included in the slice.
        var candidates = Set<Int>()

        // Helper functions for step (2).
        func tryRemapVariables(_ variables: ArraySlice<Variable>, of instr: Instruction) {
            guard mergeDataFlow else { return }
            guard hasVisibleVariables else { return }

            for v in variables {
                let type = typer.type(of: v)
                // For subroutines, the return type is only available once the subroutine has been fully processed.
                // Prior to that, it is assumed to be .jsAnything. This may lead to incompatible functions being selected
                // as replacements (e.g. if the following code assumes that the return value must be of type X), but
                // is probably fine in practice.
                assert(!instr.hasOneOutput || v != instr.output || !(instr.op is BeginAnySubroutine) || (type.signature?.outputType ?? .jsAnything) == .jsAnything)
                // Try to find a compatible variable in the host program.
                let replacement: Variable
                if let match = randomVariable(ofType: type) {
                    replacement = match
                } else {
                    // No compatible variable found
                    continue
                }
                remappedVariables[v] = replacement
                availableVariables.insert(v)
            }
        }
        func maybeRemapVariables(_ variables: ArraySlice<Variable>, of instr: Instruction, withProbability remapProbability: Double) {
            assert(remapProbability >= 0.0 && remapProbability <= 1.0)
            if probability(remapProbability) {
                tryRemapVariables(variables, of: instr)
            }
        }
        func getRequirements(of instr: Instruction) -> (requiredContext: Context, requiredInputs: VariableSet) {
            if let state = blocks[instr.index] {
                assert(instr.isBlock)
                return (state.requiredContext, state.requiredInputs)
            } else {
                return (instr.op.requiredContext, VariableSet(instr.inputs))
            }
        }

        for instr in program.code {
            // Compute variable types to be able to find compatible replacement variables in the host program if necessary.
            typer.analyze(instr)

            // Maybe remap the outputs of this instruction to existing and "compatible" (because of their type) variables in the host program.
            maybeRemapVariables(instr.outputs, of: instr, withProbability: probabilityOfRemappingAnInstructionsOutputsDuringSplicing)
            maybeRemapVariables(instr.innerOutputs, of: instr, withProbability: probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing)

            // For the purpose of this step, blocks are treated as a single instruction with all the context and input requirements of the
            // instructions in their body. This is done through the getRequirements function which uses the data computed in step (1).
            let (requiredContext, requiredInputs) = getRequirements(of: instr)

            if requiredContext.isSubset(of: context) && requiredInputs.isSubset(of: availableVariables) {
                candidates.insert(instr.index)
                // This instruction is available, and so are its outputs...
                availableVariables.formUnion(instr.allOutputs)
            } else {
                // While we cannot include this instruction, we may still be able to replace its outputs with existing variables in the host program
                // which will allow other instructions that depend on these outputs to be included.
                tryRemapVariables(instr.allOutputs, of: instr)
            }
        }

        //
        // Step (3): select the "root" instruction of the slice or use the provided one if any.
        //
        // Simple optimization: avoid splicing data-flow "roots", i.e. simple instructions that don't have any inputs, as this will
        // most of the time result in fairly uninteresting splices that for example just copy a literal from another program.
        // The exception to this are special instructions that exist outside of JavaScript context, for example instructions that add fields to classes.
        // Also skip the WasmReturn operation as its inputs depend on the result types of the function. Splicing will alomst certainly result in wrongly typed inputs.
        let rootCandidates = candidates.filter {
            (!program.code[$0].isSimple
                || program.code[$0].numInputs > 0
                || !program.code[$0].op.requiredContext.contains(.javascript)
            ) && !(program.code[$0].op is WasmReturn)
        }
        guard !rootCandidates.isEmpty else { return false }
        let rootIndex = specifiedIndex ?? chooseUniform(from: rootCandidates)
        guard rootCandidates.contains(rootIndex) else { return false }
        trace("Splicing instruction \(rootIndex) (\(program.code[rootIndex].op.name)) from \(program.id)")

        //
        // Step (4): compute the slice.
        //
        var slice = Set<Int>()
        var requiredVariables = VariableSet()
        var shouldIncludeCurrentBlock = false
        var startOfCurrentBlock = -1
        var index = rootIndex
        while index >= 0 {
            let instr = program.code[index]

            var includeCurrentInstruction = false
            if index == rootIndex {
                // This is the root of the slice, so include it.
                includeCurrentInstruction = true
                assert(candidates.contains(index))
            } else if shouldIncludeCurrentBlock {
                // This instruction is part of the slice because one of its surrounding blocks is included.
                includeCurrentInstruction = true
                // In this case, the instruction isn't necessarily a candidate (but at least one of its surrounding blocks is).
            } else if !requiredVariables.isDisjoint(with: instr.allOutputs) {
                // This instruction is part of the slice because at least one of its outputs is required.
                includeCurrentInstruction = true
                assert(candidates.contains(index))
            } else {
                // Also (potentially) include instructions that can modify one of the required variables if they can be included in the slice.
                if probability(probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable) {
                    if candidates.contains(index) && instr.mayMutate(anyOf: requiredVariables) {
                        includeCurrentInstruction = true
                    }
                }
            }

            if includeCurrentInstruction {
                slice.insert(instr.index)

                // Only those inputs that we haven't picked replacements for are now also required.
                let newlyRequiredVariables = instr.inputs.filter({ !remappedVariables.contains($0) })
                requiredVariables.formUnion(newlyRequiredVariables)

                if !shouldIncludeCurrentBlock && instr.isBlock {
                    // We're including a block instruction due to its outputs. We now need to ensure that we include the full block with it.
                    shouldIncludeCurrentBlock = true
                    let block = blocks[index]!
                    startOfCurrentBlock = block.startIndex
                    index = block.endIndex + 1
                }
            }

            if index == startOfCurrentBlock {
                assert(instr.isBlockGroupStart)
                shouldIncludeCurrentBlock = false
                startOfCurrentBlock = -1
            }

            index -= 1
        }

        //
        // Step (5): insert the final slice into the current program while also remapping any missing variables to their replacements selected in step (2).
        //
        var variableMap = remappedVariables
        for instr in program.code where slice.contains(instr.index) {
            for output in instr.allOutputs {
                variableMap[output] = nextVariable()
            }
            let inouts = instr.inouts.map({ variableMap[$0]! })
            append(Instruction(instr.op, inouts: inouts, flags: instr.flags))
        }

        trace("Splicing done")
        return true
    }

    // Code Building Algorithm:
    //
    // In theory, the basic building algorithm is simply:
    //
    //   var remainingBudget = initialBudget
    //   while remainingBudget > 0 {
    //       if probability(0.5) {
    //           remainingBudget -= runRandomCodeGenerator()
    //       } else {
    //           remainingBudget -= performSplicing()
    //       }
    //   }
    //
    // In practice, things become a little more complicated because code generators can be recursive: a function
    // generator will emit the function start and end and recursively call into the code building machinery to fill the
    // body of the function. The size of the recursively generated blocks is determined as a fraction of the parent's
    // *initial budget*. This ensures that the sizes of recursively generated blocks roughly follow the same
    // distribution. However, it also means that the initial budget can be overshot by quite a bit: we may end up
    // invoking a recursive generator near the end of our budget, which may then for example generate another 0.5x
    // initialBudget instructions. However, the benefit of this approach is that there are really only two "knobs" that
    // determine the "shape" of the generated code: the factor that determines the recursive budget relative to the
    // parent budget and the (absolute) threshold for recursive code generation.
    //

    /// The second "knob": the minimum budget required to be able to invoke recursive code generators.
    public static let minBudgetForRecursiveCodeGeneration = 5

    /// Possible building modes. These are used as argument for build() and determine how the new code is produced.
    public enum BuildingMode {
        // Generate code by running CodeGenerators.
        case generating
        // Splice code from other random programs in the corpus.
        case splicing
        // Do all of the above.
        case generatingAndSplicing
    }

    struct BuildLog {
        enum ActionOutcome: CustomStringConvertible {
            case success
            case failed(String?)
            case started

            var description: String {
                switch self {
                    case .success:
                        return "✅"
                    case .failed(let reason):
                        if let reason {
                            return "❌: \(reason)"
                        } else {
                            return "❌"
                        }
                    case .started:
                        return "started"
                }
            }
        }

        struct BuildAction {
            var name: String
            var outcome = ActionOutcome.started
            var produces: [ILType]
        }

        var pendingActions: Stack<BuildAction> = Stack()
        var actions = [(BuildAction, Int)]()
        var indent = 0

        mutating func startAction(_ actionName: String, produces: [ILType]) {
            let action = BuildAction(name: actionName, produces: produces)
            // Mark this action as `.started`.
            actions.append((action, indent))
            // Push the action onto the pending stack, we will need to complete or fail it later.
            pendingActions.push(action)
            indent += 1
        }

        mutating func succeedAction(_ newlyCreatedVariableTypes: [ILType]) {
            indent -= 1
            var finishedAction = pendingActions.pop()
            finishedAction.outcome = .success
            actions.append((finishedAction, indent))
            #if DEBUG
            // Now Check that we've seen these new types.
            for t in finishedAction.produces {
                if !newlyCreatedVariableTypes.contains(where: {
                    $0.Is(t)
                }) {
                    var fatalErrorString = ""
                    fatalErrorString += "Action: \(finishedAction.name)\n"
                    fatalErrorString += "Action guaranteed it would produce: \(finishedAction.produces)\n"
                    fatalErrorString += "\(getLogString())\n"
                    fatalErrorString += "newlyCreatedVariableTypes: \(newlyCreatedVariableTypes) does not contain expected type \(t)"
                    fatalError(fatalErrorString)
                }
            }
            #endif
        }

        mutating func reportFailure(reason: String? = nil) {
            indent -= 1
            var failedAction = pendingActions.pop()
            failedAction.outcome = .failed(reason)
            actions.append((failedAction, indent))
        }

        func getLogString() -> String {
            var logString = "Build log:\n"
            for (action, indent) in actions {
                let tab = String(repeating: " ", count: indent)
                logString.append("\(tab)\(action.name): \(action.outcome)\n")
            }
            return logString
        }

        mutating func reset() {
            assert(pendingActions.isEmpty, "We should have completed all pending build actions, either failed or succeeded.")
            // This is basically equivalent with the statement above.
            assert(indent == 0)
            actions.removeAll()
        }
    }


    // The BuildLog records all `run` and `complete` calls on this ProgramBuilder, be it through mutation or generation.
    #if DEBUG
    // We definitely want to have the BuildLog in DEBUG builds.
    var buildLog: BuildLog? = BuildLog()
    #else
    // We initialize this depending on the LogLevel in the initializer.
    var buildLog: BuildLog? = nil
    #endif

    /// Build random code at the current position in the program.
    ///
    /// The first parameter controls the number of emitted instructions: as soon as more than that number of instructions have been emitted, building stops.
    /// This parameter is only a rough estimate as recursive code generators may lead to significantly more code being generated.
    /// Typically, the actual number of generated instructions will be somewhere between n and 2x n.
    ///
    /// Building code requires that there are visible variables available as inputs for CodeGenerators or as replacement variables for splicing.
    /// When building new programs, `buildPrefix()` can be used to generate some initial variables. `build()` purposely does not call
    /// `buildPrefix()` itself so that the budget isn't accidentally spent just on prefix code (which is probably less interesting).
    public func build(n budget: Int, by buildingMode: BuildingMode = .generatingAndSplicing) {

        /// The number of CodeGenerators we want to call per level.
        let splitFactor = 2

        // If the corpus is empty, we have to pick generating here, this is only relevant for the first sample.
        let mode: BuildingMode = if fuzzer.corpus.isEmpty {
            .generating
        } else {
            if buildingMode == .generatingAndSplicing {
                chooseUniform(from: [.generating, .splicing])
            } else {
                buildingMode
            }
        }

        // Now depending on the budget we will do one of these things:
        // 1. Large budget is still here. Pick a scheduled CodeGenerator, or a random CodeGenerator.
        //   a. See if we can execute it immediately and call into build if it yields. (and split budgets).
        //   b. if not, schedule it, pick a generator that get's us closer to the target context.
        //   c. see if we need to solve input constraints of scheduled generators.
        // 2. budget is low
        //   a. Call scheduled GeneratorStubs or return.

        // Both splicing and code generation can sometimes fail, for example if no other program with the necessary features exists.
        // To avoid infinite loops, we bail out after a certain number of consecutive failures.
        var consecutiveFailures = 0

        var remainingBudget = budget

        // Unless we are only splicing, find all generators that have the required context. We must always have at least one suitable code generator.
        let origContext = context

        while remainingBudget > 0 {
            assert(context == origContext, "Code generation or splicing must not change the current context")

            let codeSizeBefore = code.count
            switch mode {
            case .generating:
                // This requirement might seem somewhat arbitrary but our JavaScript code generators make use of `b.randomVariable` and as such rely on the availability of
                // visible Variables. Therefore we should always have some Variables visible if we want to use them.
                assert(hasVisibleVariables, "CodeGenerators assume that there are visible variables to use. Use buildPrefix() to generate some initial variables in a new program")

                var generator: CodeGenerator? = nil

                // If the budget is low, we will pick a CodeGenerator that is directly usable from the current context.
                // If we still have budget left, we will instead pick any CodeGenerator that is reachable from the current context, which means that we might go from .javascript to .wasmFunction.
                if remainingBudget < ProgramBuilder.minBudgetForRecursiveCodeGeneration {
                    generator = fuzzer.codeGenerators.filter({
                        $0.requiredContext.isSubset(of: context)
                    }).randomElement()

                    guard generator != nil else {
                        fatalError("need a callable generator from every context!")
                    }
                } else {
                    var counter = 0
                    // We now try to assemble a Generator that we want to use.
                    while generator == nil {
                        // If we haven't managed to find a suitable CodeGenerator, we will try again but only consider CodeGenerators that are reachable from the current context. This should always work.
                        if counter == 10 {
                            generator = fuzzer.codeGenerators.filter({
                                $0.requiredContext.isSubset(of: context)
                            }).randomElement()!
                            break
                        }
                        // Select a random CodeGenerator that is reachable from the current context and run it.
                        let reachableContexts = fuzzer.contextGraph.getReachableContexts(from: context)
                        let possibleGenerators = fuzzer.codeGenerators.filter({ generator in
                            reachableContexts.reduce(false) { res, reachable in
                                return res || generator.requiredContext.isSubset(of: reachable)
                            }
                        })

                        assert(!possibleGenerators.isEmpty)
                        let randomGenerator = possibleGenerators.randomElement()
                        // After having picked a generator, we might need to nest it in other generators that provide the necessary contexts.
                        generator = assembleSyntheticGenerator(for: randomGenerator)
                        counter += 1
                    }
                }

                // TODO: think about this and if we want to split this so that we get more CodeGenerators on the same level?
                let _ = complete(generator: generator!, withBudget: remainingBudget / splitFactor)

            case .splicing:
                let program = fuzzer.corpus.randomElementForSplicing()
                buildLog?.startAction("splicing", produces: [])
                splice(from: program)

            default:
                fatalError("Unknown ProgramBuildingMode \(mode)")
            }
            let codeSizeAfter = code.count

            let emittedInstructions = codeSizeAfter - codeSizeBefore
            remainingBudget -= emittedInstructions
            if emittedInstructions > 0 {
                if mode == .splicing {
                    buildLog?.succeedAction([])
                }
            } else {
                if mode == .splicing {
                    buildLog?.reportFailure()
                }
                consecutiveFailures += 1
                guard consecutiveFailures < 10 else {
                    // When splicing, this is somewhat expected as we may not find code to splice if we're in a restricted
                    // context (e.g. we're inside a switch, but can't find another program with switch-cases).
                    // However, when generating code this should happen very rarely since we should always be able to
                    // generate code, not matter what context we are currently in.
                    if mode != .splicing {
                        if let log = buildLog {
                            logger.verbose(log.getLogString())
                        }
                    }
                    // If we have requested generatingAndSplicing initially and
                    // then decided to splice and fail here, we generate as a
                    // fallback.
                    if buildingMode == .generatingAndSplicing && mode == .splicing {
                        build(n: budget, by: .generating)
                    }
                    return
                }
            }
        }
    }

    // Like build(n:by) but forcing BuildingMode to generating. Splicing is an operation that
    // affects the whole program, so we shouldn't roll a die on every buildRecursive() call in a
    // code generator whether we'd want to splice an operation into the current block (which happens
    // with the default mode .generatingAndSplicing).
    public func buildRecursive(n budget: Int) {
        build(n: budget, by: .generating)
    }

    /// Run ValueGenerators until we have created at least N new variables.
    /// Returns both the number of generated instructions and of newly created variables.
    @discardableResult
    public func buildValues(_ n: Int) -> (generatedInstructions: Int, generatedVariables: Int) {
        var valueGenerators = fuzzer.codeGenerators.filter({ $0.isValueGenerator })
        // Filter for the current context
        valueGenerators = valueGenerators.filter { context.contains($0.requiredContext) }

        assert(!valueGenerators.isEmpty)
        let previousNumberOfVisibleVariables = numberOfVisibleVariables
        var totalNumberOfGeneratedInstructions = 0

        // ValueGenerators can be recursive.
        // Here we create a builder stack entry for that case which gives each generator a fixed recursive
        // budget and allows us to run code generators when building recursively. We probably don't want to run
        // splicing here since splicing isn't as careful as code generation and may lead to invalid code more quickly.
        // The `initialBudget` isn't really used (since we specify a `recursiveBudget`), so can be an arbitrary value.

        let currentBudget = 2 * n

        while numberOfVisibleVariables - previousNumberOfVisibleVariables < n {

            let generator = valueGenerators.randomElement()

            // Just fully run the generator without yielding back.
            // Think about changing this and calling into the higher level build logic?
            // TODO arbitrary budget here right now, change this to some split factor?
            let numberOfGeneratedInstructions =  self.complete(generator: generator, withBudget: currentBudget / 5)

            assert(numberOfGeneratedInstructions > 0, "ValueGenerators must always succeed")
            totalNumberOfGeneratedInstructions += numberOfGeneratedInstructions
        }
        return (totalNumberOfGeneratedInstructions, numberOfVisibleVariables - previousNumberOfVisibleVariables)
    }

    /// Bootstrap program building by creating some variables with statically known types.
    ///
    /// The `build()` method for generating new code or splicing from existing code can
    /// only be used once there are visible variables. This method can be used to generate some.
    ///
    /// Internally, this uses the ValueGenerators to generate some code. As such, the "shape"
    /// of prefix code is controlled in the same way as other generated code through the
    /// generator's respective weights.
    public func buildPrefix() {
        // Each value generators should generate at least 3 variables, and we probably want to run at least a
        // few of them (maybe roughly >= 3), so the number of variables to build shouldn't be set too low.
        assert(GeneratorStub.numberOfValuesToGenerateByValueGenerators == 3)
        let numValuesToBuild = Int.random(in: 10...15)

        trace("Start of prefix code")
        buildValues(numValuesToBuild)
        assert(numberOfVisibleVariables >= numValuesToBuild)
        trace("End of prefix code. \(numberOfVisibleVariables) variables are now visible")
    }

    /// Builds into a `Context.wasmTypeGroup`.
    /// This is called by the SpliceMutator and the CodeGenMutator to fix up the EndTypeGroup Instruction after building.
    /// Needs to run from an adopting block.
    public func buildIntoTypeGroup(endTypeGroupInstr instr: Instruction, by mode: BuildingMode) {
        assert(instr.op is WasmEndTypeGroup)
        assert(context.contains(.wasmTypeGroup))

        // We need to update the inputs later, so take note of the visible variables here.
        let oldVisibleVariables = visibleVariables

        build(n: defaultCodeGenerationAmount, by: mode)

        let newVisibleVariables = visibleVariables.filter { v in
            let t = type(of: v)
            return !oldVisibleVariables.contains(v) && t.wasmTypeDefinition?.description != .selfReference && t.Is(.wasmTypeDef())
        }

        let newOp = WasmEndTypeGroup(typesCount: instr.inputs.count + newVisibleVariables.count)
        // We need to keep and adopt the inputs that are still there.
        let newInputs = adopt(instr.inputs) + newVisibleVariables
        // Adopt the old outputs and allocate new output variables for the new outputs
        let newOutputs = adopt(instr.outputs) + newVisibleVariables.map { _ in
            nextVariable()
        }

        append(Instruction(newOp, inouts: Array(newInputs) + newOutputs, flags: instr.flags))
    }

    // This function knows its own budget, and splits it to its yield points.
    public func complete(generator: CodeGenerator, withBudget budget: Int) -> Int {
        trace("Executing Generator \(generator.expandedName)")
        let actionName = "Generator: " + generator.expandedName
        buildLog?.startAction(actionName, produces: generator.produces)
        let visibleVariablesBefore = visibleVariables

        let depth = scheduled.count

        // Split budget evenly at yield points.
        let budgetPerYieldPoint = budget / generator.parts.count

        var numberOfGeneratedInstructions = 0

        // calculate all input requirements of this CodeGenerator.
        let inputTypes = Set(generator.parts.reduce([]) { res, gen in
            return res + gen.inputs.types
        })

        var availableTypes = inputTypes.filter {
            randomVariable(ofType: $0) != nil
        }

        // Add the current context to the seen Contexts as well.
        var seenContexts: [Context] = [context]

        let contextsAndTypes = generator.parts.map { ($0.providedContext, $0.inputs.types) }

        // Check if the can be produced along this generator, otherwise we need to bail.
        for (contexts, types) in contextsAndTypes {
            // We've seen the current context.
            for context in contexts {
                seenContexts.append(context)
            }

            for type in types {
                // If we don't have the type available, check if we can produce it in the current context or a seen context.
                if !availableTypes.contains(where: {
                    type.Is($0)
                }) {
                    // Check if we have generators that can produce the type reachable from this context.
                    let reachableContexts: Context = seenContexts.reduce(Context.empty) { res, ctx in [res, fuzzer.contextGraph.getReachableContexts(from: ctx).reduce(Context.empty) { res, ctx in [res, ctx]}]
                    }

                    // Right now this checks if the generator is a subset of the full reachable context (a single bitfield with all reachable contexts).
                    // TODO: We need to also do some graph thingies here and add our requested types to the queue to see if we can fulfill the requested types. if we see that a generator produces a type, we need to put its input requirements onto the queue and start over?
                    // Maybe overkill, but also cool.
                    let callableGenerators = fuzzer.codeGenerators.filter {
                        $0.requiredContext.isSubset(of: reachableContexts)
                    }

                    // Filter to see if they produce this type. Crucially to avoid dependency cycles, these also need to be valuegenerators.
                    let canProduceThisType = callableGenerators.contains(where: { generator in
                        generator.produces.contains(where: { $0.Is(type) })
                    })

                    // We cannot run if this is false.
                    if !canProduceThisType {
                        // TODO(cffsmith): track some statistics on how often this happens.
                        buildLog?.reportFailure(reason: "Cannot produce type \(type) starting in original context \(context).")
                        return 0
                    } else {
                        // Mark the type as available.
                        availableTypes.insert(type)
                    }
                }
            }
        }

        // Try to create the types that we need for this generator.
        // At this point we've guaranteed that we can produce the types somewhere along the yield points of this generator.
        createRequiredInputVariables(forTypes: inputTypes)

        // Push the remaining stubs, we need to call them to close all Contexts properly.
        for part in generator.tail.reversed() {
            scheduled.push(part)
        }

        // This runs the first part of the generator.
        numberOfGeneratedInstructions += self.run(generator.head)

        // If this generator says it provides a context, it must do so, it cannot fail because we would not be able to continue with the rest of the generator.
        // TODO(cffsmith): implement some forking / merging mode for the Code Object? that way we could "roll back" some changes.
        let subsetContext = generator.head.providedContext.reduce(Context.empty) { res, context in
            return [res, context]
        }

        assert(subsetContext.isSubset(of: context), "Generators that claim to provide contexts cannot fail to provide those contexts \(generator.head.name).")

        // While our local stack is not removed, we need to call into build and call the scheduled stubs.
        while scheduled.count > depth {
            let codeSizePre = code.count
            // Check if we need to or can create types here.
            createRequiredInputVariables(forTypes: inputTypes)
            // Build into the block.
            buildRecursive(n: budgetPerYieldPoint)
            // Call the next scheduled stub.
            let _  = callNext()
            numberOfGeneratedInstructions += code.count - codeSizePre
        }

        if numberOfGeneratedInstructions > 0 {
            buildLog?.succeedAction(
                Set(visibleVariables)
                .subtracting(Set(visibleVariablesBefore))
                .map(self.type)
                )
        } else {
            buildLog?.reportFailure()
        }

        // I guess this is kind of implied by the logic above, yet if someone calls an extra closer in build somehow this would catch it.
        assert(depth == scheduled.count, "Build stack is not balanced")
        return numberOfGeneratedInstructions
    }

    // Todo, the context graph could also find ideal paths that allow type creation.
    private func createRequiredInputVariables(forTypes types: Set<ILType>) {
        for type in types {
            if type.Is(.jsAnything) && context.contains(.javascript) {
                let _ = findOrGenerateType(type)
            } else {
                if type.Is(.wasmAnything) && context.contains(.wasmFunction) {
                    // Check if we can produce it with findOrGenerateWasmVar
                    let _ = currentWasmFunction.generateRandomWasmVar(ofType: type)
                }
                if randomVariable(ofType: type) == nil {
                    // Check for other CodeGenerators that can produce the given type in this context.
                    let usableGenerators = fuzzer.codeGenerators.filter {
                        $0.requiredContext.isSubset(of: context) &&
                        $0.produces.contains {
                            $0.Is(type)
                        }
                    }

                    // Cannot build type here.
                    if usableGenerators.isEmpty {
                        // Continue here though, as we might be able to create Variables for other types.
                        continue
                    }

                    let generator = usableGenerators.randomElement()

                    let _ = complete(generator: generator, withBudget: 5)
                }
            }
        }
    }

    // The `mainGenerator` is the actual generator that we want to run, we now might need to schedule other generators first to reach a necessary context.
    public func assembleSyntheticGenerator(for mainGenerator: CodeGenerator) -> CodeGenerator? {
        // We can directly run this CodeGenerator here.
        if context.contains(mainGenerator.requiredContext) {
            return mainGenerator
        }

        // Get all the generators for each edge and pick one of them.

        // We might be in a context that is a union, e.g. .javascript | .subroutine. We then need to get all Paths from both possible single contexts.
        let paths: [ContextGraph.Path] = Context.allCases.reduce([]) { pathArray, possibleContext in

            if context.contains(possibleContext) {
                // Walk through generated Graph and find a path.
                let paths = fuzzer.contextGraph.getCodeGeneratorPaths(from: possibleContext, to: mainGenerator.requiredContext) ?? []
                return pathArray + paths
            }

            return pathArray
        }

        if paths.isEmpty {
            logger.warning("Found no paths in context \(context) for requested generator \(mainGenerator.name)")
            return nil
        }

        // Pick a random path.
        let path = chooseUniform(from: paths)

        // For each edge in the path, pick a random generator.
        // This is now a list of CodeGenerators, i.e. pairs of logical units.
        let generators: [CodeGenerator] = path.randomConcretePath()

        // So we can now assemble a synthetic generator that invokes our picked generator.
        // We start by taking our first CodeGenerator, that will open the next context that is necessary.
        // This is an incomplete CodeGenerator right now, as it only contains one part that opens a new context.
        var syntheticGenerator = generators[0].parts

        // For all other Stubs we will now successively insert the next CodeGenerator stubs into the right "spots".
        //  <head_generator 1>
        // We now try to insert the next part of the first CodeGenerator into our synthetic generator.
        //  <head_generator 1> [some context] <tail_generator 1>
        // We now go to the next Edge of our path and try to insert that head in the correct spot.
        // <head_generator 1> [some context] <head_generator 2> [another context] <tail_generator 1>
        // Since every part of the CodeGenerator requires its previous context, we can insert them in the right spot.
        // At the very end, we will insert the actual CodeGenerator that we want to call.
        // This essentially amounts to an insertion sort.
        // (Because we might have CodeGenerators with multiple parts and different contexts, we cannot do this without sorting)
        for subGenerator in generators[1...] + [mainGenerator] {
            for (idx, part) in syntheticGenerator.enumerated() {
                if part.providedContext.contains(where: { ctx in
                    subGenerator.head.requiredContext.satisfied(by: ctx)
                }) {
                    // Insert this codegenerator here after this stub.
                    syntheticGenerator.insert(contentsOf: subGenerator.parts, at: idx + 1)
                    break
                }
            }
        }

        // This is our synthetic CodeGenerator.
        return CodeGenerator("Synthetic", syntheticGenerator)
    }

    // Calls the next scheduled generator.
    private func callNext() -> Int {
        // Check if we should pass variables to this closer somehow?
        if !scheduled.isEmpty {
            let generator = scheduled.pop()
            let generatedInstructions = self.run(generator)

            let subsetContext = generator.providedContext.reduce(Context.empty) { res, context in
                return [res, context]
            }

            assert(subsetContext.isSubset(of: context), "Generators that claim to provide contexts cannot fail to provide those contexts \(generator.name).")


            return generatedInstructions
        } else {
            return 0
        }
    }

    /// Runs a code generator in the current context and returns the number of generated instructions.
    @discardableResult
    private func run(_ generator: GeneratorStub) -> Int {
        // Any of the required Context constraints need to be satisfied.
        assert(generator.requiredContext.satisfied(by: context))
        let visibleVariablesBefore = visibleVariables

        trace("Executing code generator \(generator.name)")
        buildLog?.startAction(generator.name, produces: generator.produces)
        var inputs = [Variable]()
        switch generator.inputs.mode {
        case .loose:
            // Find inputs that are probably compatible with the desired input types using randomVariable(forUseAs:)
            inputs = generator.inputs.types.map(randomVariable(forUseAs:))

        case .strict:
            // Find inputs of the required type using randomVariable(ofType:)
            for inputType in generator.inputs.types {
                guard let input = randomVariable(ofType: inputType) else {
                    // Cannot run this generator
                    if generator.providedContext != [] {
                        fatalError("This generator is supposed to provide a context but cannot as we've failed to find the necessary inputs.")
                    }
                    // This early return also needs to report a failure.
                    buildLog?.reportFailure(reason: "Cannot find variable that satifies input constraints \(inputType).")
                    return 0
                }
                inputs.append(input)
            }
        }
        let numGeneratedInstructions = generator.run(in: self, with: inputs)
        trace("Code generator finished")

        if numGeneratedInstructions > 0 {
            contributors.insert(generator)
            buildLog?.succeedAction(
                Set(visibleVariables)
                .subtracting(Set(visibleVariablesBefore))
                .map(self.type)
                )
        } else {
            buildLog?.reportFailure(reason: "Generator itself failed to produce any instructions.")
        }

        return numGeneratedInstructions
    }

    //
    // Low-level instruction constructors.
    //
    // These create an instruction with the provided values and append it to the program at the current position.
    // If the instruction produces a new variable, that variable is returned to the caller.
    // Each class implementing the Operation protocol will have a constructor here.
    //

    private func handleInputTypeFailure(_ message: String) {
        logger.warning(message)
        if fuzzer.config.enableDiagnostics {
            do {
                let program = Program(with: self.code)
                let pb = try program.asProtobuf().serializedData()
                fuzzer.dispatchEvent(fuzzer.events.DiagnosticsEvent, data: (name: "WasmProgramBuildingEmissionFail", content: pb))
            } catch {
                logger.warning("Could not dump program to disk!")
            }
        }
        // Fail on debug builds.
        assert(false, message)
    }

    @discardableResult
    public func emit(_ op: Operation, withInputs inputs: [Variable] = [], types: [ILType]? = nil) -> Instruction {
        var inouts = inputs
        for _ in 0..<op.numOutputs {
            inouts.append(nextVariable())
        }
        for _ in 0..<op.numInnerOutputs {
            inouts.append(nextVariable())
        }

        // For WasmOperations, we can assert here that the input types are correct.
        if let expectedTypes = types {
            // TODO: try to make sure that mutations don't change the assumptions while ProgramBuilding.
            if inputs.count != expectedTypes.count {
                handleInputTypeFailure("expected \(expectedTypes.count) inputs, actual \(inputs.count)")
            }
            zip(inputs, expectedTypes).enumerated().forEach { n, pair in
                let (input, type) = pair
                let actualType = self.type(of: input)
                if !actualType.Is(type) {
                    handleInputTypeFailure("Invalid input \(n + 1) \(input) with type \(actualType), expected \(type)")
                }
            }
        }

        return internalAppend(Instruction(op, inouts: inouts, flags: .empty))
    }

    @discardableResult
    public func loadInt(_ value: Int64) -> Variable {
        return emit(LoadInteger(value: value)).output
    }

    @discardableResult
    public func loadBigInt(_ value: Int64) -> Variable {
        return emit(LoadBigInt(value: value)).output
    }

    @discardableResult
    public func loadFloat(_ value: Double) -> Variable {
        return emit(LoadFloat(value: value)).output
    }

    @discardableResult
    public func loadString(_ value: String, customName: String? = nil) -> Variable {
        return emit(LoadString(value: value, customName: customName)).output
    }

    @discardableResult
    public func loadEnum(_ type: ILType) -> Variable {
        assert(type.isEnumeration)
        return loadString(chooseUniform(from: type.enumValues), customName: type.group)
    }

    @discardableResult
    public func loadBool(_ value: Bool) -> Variable {
        return emit(LoadBoolean(value: value)).output
    }

    @discardableResult
    public func loadUndefined() -> Variable {
        return emit(LoadUndefined()).output
    }

    @discardableResult
    public func loadNull() -> Variable {
        return emit(LoadNull()).output
    }

    @discardableResult
    public func loadThis() -> Variable {
        return emit(LoadThis()).output
    }

    @discardableResult
    public func loadArguments() -> Variable {
        return emit(LoadArguments()).output
    }

    @discardableResult
    public func loadDisposableVariable(_ value: Variable) -> Variable {
        return emit(LoadDisposableVariable(), withInputs: [value]).output
    }

    @discardableResult
    public func loadAsyncDisposableVariable(_ value: Variable) -> Variable {
        return emit(LoadAsyncDisposableVariable(), withInputs: [value]).output
    }

    @discardableResult
    public func loadNewTarget() -> Variable {
        return emit(LoadNewTarget()).output
    }

    @discardableResult
    public func loadRegExp(_ pattern: String, _ flags: RegExpFlags) -> Variable {
        return emit(LoadRegExp(pattern: pattern, flags: flags)).output
    }

    /// Represents a currently active object literal. Used to add fields to it and to query which fields already exist.
    public class ObjectLiteral {
        private let b: ProgramBuilder

        public fileprivate(set) var properties: [String] = []
        public fileprivate(set) var elements: [Int64] = []
        public fileprivate(set) var computedProperties: [Variable] = []
        public fileprivate(set) var methods: [String] = []
        public fileprivate(set) var computedMethods: [Variable] = []
        public fileprivate(set) var getters: [String] = []
        public fileprivate(set) var setters: [String] = []
        public fileprivate(set) var hasPrototype = false

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.objectLiteral))
            self.b = b
        }

        public func addProperty(_ name: String, as value: Variable) {
            b.emit(ObjectLiteralAddProperty(propertyName: name), withInputs: [value])
        }

        public func addElement(_ index: Int64, as value: Variable) {
            b.emit(ObjectLiteralAddElement(index: index), withInputs: [value])
        }

        public func addComputedProperty(_ name: Variable, as value: Variable) {
            b.emit(ObjectLiteralAddComputedProperty(), withInputs: [name, value])
        }

        public func copyProperties(from obj: Variable) {
            b.emit(ObjectLiteralCopyProperties(), withInputs: [obj])
        }

        public func setPrototype(to proto: Variable) {
            b.emit(ObjectLiteralSetPrototype(), withInputs: [proto])
        }

        public func addMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginObjectLiteralMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndObjectLiteralMethod())
        }

        public func addComputedMethod(_ name: Variable, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginObjectLiteralComputedMethod(parameters: descriptor.parameters), withInputs: [name])
            body(Array(instr.innerOutputs))
            b.emit(EndObjectLiteralComputedMethod())
        }

        public func addGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginObjectLiteralGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndObjectLiteralGetter())
        }

        public func addSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginObjectLiteralSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndObjectLiteralSetter())
        }
    }

    @discardableResult
    public func buildObjectLiteral(_ body: (ObjectLiteral) -> ()) -> Variable {
        emit(BeginObjectLiteral())
        body(currentObjectLiteral)
        return emit(EndObjectLiteral()).output
    }

    @discardableResult
    // Convenience method to create simple object literals.
    public func createObject(with initialProperties: [String: Variable]) -> Variable {
        return buildObjectLiteral { obj in
            // Sort the property names so that the emitted code is deterministic.
            for (propertyName, value) in initialProperties.sorted(by: { $0.key < $1.key }) {
                obj.addProperty(propertyName, as: value)
            }
        }
    }

    /// Represents a currently active class definition. Used to add fields to it and to query which fields already exist.
    public class ClassDefinition {
        private let b: ProgramBuilder

        public let isDerivedClass: Bool

        public fileprivate(set) var hasConstructor = false

        public fileprivate(set) var instanceProperties: [String] = []
        public fileprivate(set) var instanceElements: [Int64] = []
        public fileprivate(set) var instanceComputedProperties: [Variable] = []
        public fileprivate(set) var instanceMethods: [String] = []
        public fileprivate(set) var instanceComputedMethods: [Variable] = []
        public fileprivate(set) var instanceGetters: [String] = []
        public fileprivate(set) var instanceSetters: [String] = []

        public fileprivate(set) var staticProperties: [String] = []
        public fileprivate(set) var staticElements: [Int64] = []
        public fileprivate(set) var staticComputedProperties: [Variable] = []
        public fileprivate(set) var staticMethods: [String] = []
        public fileprivate(set) var staticComputedMethods: [Variable] = []
        public fileprivate(set) var staticGetters: [String] = []
        public fileprivate(set) var staticSetters: [String] = []

        // These sets are required to ensure syntactic correctness, not just as an optimization to
        // avoid adding duplicate fields:
        // In JavaScript, it is a syntax error to access a private property/method that has not
        // been declared by the surrounding class. Further, each private field must only be declared
        // once, regardless of whether it is a method or a property and whether it's per-instance or
        // static. However, we still track properties and methods separately to facilitate selecting
        // property and method names for private property accesses and private method calls.
        public fileprivate(set) var privateProperties: [String] = []
        public fileprivate(set) var privateMethods: [String] = []
        public var privateFields: [String] {
            return privateProperties + privateMethods
        }

        fileprivate init(in b: ProgramBuilder, isDerived: Bool) {
            assert(b.context.contains(.classDefinition))
            self.b = b
            self.isDerivedClass = isDerived
        }

        public func addConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassConstructor(parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassConstructor())
        }

        public func addInstanceProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddInstanceProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceElement(_ index: Int64, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddInstanceElement(index: index, hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceComputedProperty(_ name: Variable, value: Variable? = nil) {
            let inputs = value != nil ? [name, value!] : [name]
            b.emit(ClassAddInstanceComputedProperty(hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassInstanceMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassInstanceMethod())
        }

        public func addInstanceComputedMethod(_ name: Variable, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassInstanceComputedMethod(parameters: descriptor.parameters), withInputs: [name])
            body(Array(instr.innerOutputs))
            b.emit(EndClassInstanceComputedMethod())
        }

        public func addInstanceGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginClassInstanceGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndClassInstanceGetter())
        }

        public func addInstanceSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginClassInstanceSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndClassInstanceSetter())
        }

        public func addStaticProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddStaticProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticElement(_ index: Int64, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddStaticElement(index: index, hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticComputedProperty(_ name: Variable, value: Variable? = nil) {
            let inputs = value != nil ? [name, value!] : [name]
            b.emit(ClassAddStaticComputedProperty(hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticInitializer(_ body: (Variable) -> ()) {
            let instr = b.emit(BeginClassStaticInitializer())
            body(instr.innerOutput)
            b.emit(EndClassStaticInitializer())
        }

        public func addStaticMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassStaticMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassStaticMethod())
        }

        public func addStaticComputedMethod(_ name: Variable, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassStaticComputedMethod(parameters: descriptor.parameters), withInputs: [name])
            body(Array(instr.innerOutputs))
            b.emit(EndClassStaticComputedMethod())
        }

        public func addStaticGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginClassStaticGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndClassStaticGetter())
        }

        public func addStaticSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginClassStaticSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndClassStaticSetter())
        }

        public func addPrivateInstanceProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddPrivateInstanceProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addPrivateInstanceMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassPrivateInstanceMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassPrivateInstanceMethod())
        }

        public func addPrivateStaticProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddPrivateStaticProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addPrivateStaticMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassPrivateStaticMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassPrivateStaticMethod())
        }
    }

    @discardableResult
    public func buildClassDefinition(withSuperclass superclass: Variable? = nil, isExpression: Bool = false, _ body: (ClassDefinition) -> ()) -> Variable {
        let inputs = superclass != nil ? [superclass!] : []
        let output = emit(BeginClassDefinition(hasSuperclass: superclass != nil, isExpression: isExpression), withInputs: inputs).output
        if enableRecursionGuard { hide(output) }
        body(currentClassDefinition)
        if enableRecursionGuard { unhide(output) }
        emit(EndClassDefinition())
        return output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable]) -> Variable {
        return emit(CreateArray(numInitialValues: initialValues.count), withInputs: initialValues).output
    }

    @discardableResult
    public func createIntArray(with initialValues: [Int64]) -> Variable {
        return emit(CreateIntArray(values: initialValues)).output
    }

    @discardableResult
    public func createFloatArray(with initialValues: [Double]) -> Variable {
        return emit(CreateFloatArray(values: initialValues)).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable], spreading spreads: [Bool]) -> Variable {
        assert(initialValues.count == spreads.count)
        return emit(CreateArrayWithSpread(spreads: spreads), withInputs: initialValues).output
    }

    @discardableResult
    public func createTemplateString(from parts: [String], interpolating interpolatedValues: [Variable]) -> Variable {
        return emit(CreateTemplateString(parts: parts), withInputs: interpolatedValues).output
    }

    @discardableResult
    public func getProperty(_ name: String, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetProperty(propertyName: name, isGuarded: isGuarded), withInputs: [object]).output
    }

    public func setProperty(_ name: String, of object: Variable, to value: Variable, guard isGuarded: Bool = false) {
        emit(SetProperty(propertyName: name, isGuarded: isGuarded), withInputs: [object, value])
    }

    public func updateProperty(_ name: String, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateProperty(propertyName: name, operator: op), withInputs: [object, value])
    }

    @discardableResult
    public func deleteProperty(_ name: String, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteProperty(propertyName: name, isGuarded: isGuarded), withInputs: [object]).output
    }

    public enum PropertyConfiguration {
        case value(Variable)
        case getter(Variable)
        case setter(Variable)
        case getterSetter(Variable, Variable)
    }

    public func configureProperty(_ name: String, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .value), withInputs: [object, value])
        case .getter(let getter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .getter), withInputs: [object, getter])
        case .setter(let setter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .setter), withInputs: [object, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .getterSetter), withInputs: [object, getter, setter])
        }
    }

    @discardableResult
    public func getElement(_ index: Int64, of array: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetElement(index: index, isGuarded: isGuarded), withInputs: [array]).output
    }

    public func setElement(_ index: Int64, of array: Variable, to value: Variable) {
        emit(SetElement(index: index), withInputs: [array, value])
    }

    public func updateElement(_ index: Int64, of array: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateElement(index: index, operator: op), withInputs: [array, value])
    }

    @discardableResult
    public func deleteElement(_ index: Int64, of array: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteElement(index: index, isGuarded: isGuarded), withInputs: [array]).output
    }

    public func configureElement(_ index: Int64, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureElement(index: index, flags: flags, type: .value), withInputs: [object, value])
        case .getter(let getter):
            emit(ConfigureElement(index: index, flags: flags, type: .getter), withInputs: [object, getter])
        case .setter(let setter):
            emit(ConfigureElement(index: index, flags: flags, type: .setter), withInputs: [object, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureElement(index: index, flags: flags, type: .getterSetter), withInputs: [object, getter, setter])
        }
    }

    @discardableResult
    public func getComputedProperty(_ name: Variable, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetComputedProperty(isGuarded: isGuarded), withInputs: [object, name]).output
    }

    public func setComputedProperty(_ name: Variable, of object: Variable, to value: Variable) {
        emit(SetComputedProperty(), withInputs: [object, name, value])
    }

    public func updateComputedProperty(_ name: Variable, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateComputedProperty(operator: op), withInputs: [object, name, value])
    }

    @discardableResult
    public func deleteComputedProperty(_ name: Variable, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteComputedProperty(isGuarded: isGuarded), withInputs: [object, name]).output
    }

    public func configureComputedProperty(_ name: Variable, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureComputedProperty(flags: flags, type: .value), withInputs: [object, name, value])
        case .getter(let getter):
            emit(ConfigureComputedProperty(flags: flags, type: .getter), withInputs: [object, name, getter])
        case .setter(let setter):
            emit(ConfigureComputedProperty(flags: flags, type: .setter), withInputs: [object, name, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureComputedProperty(flags: flags, type: .getterSetter), withInputs: [object, name, getter, setter])
        }
    }

    @discardableResult
    public func typeof(_ v: Variable) -> Variable {
        return emit(TypeOf(), withInputs: [v]).output
    }

    @discardableResult
    public func void(_ v: Variable) -> Variable {
        return emit(Void_(), withInputs: [v]).output
    }

    @discardableResult
    public func testInstanceOf(_ v: Variable, _ type: Variable) -> Variable {
        return emit(TestInstanceOf(), withInputs: [v, type]).output
    }

    @discardableResult
    public func testIn(_ prop: Variable, _ obj: Variable) -> Variable {
        return emit(TestIn(), withInputs: [prop, obj]).output
    }

    public func explore(_ v: Variable, id: String, withArgs arguments: [Variable]) {
        let rngSeed = UInt32(truncatingIfNeeded: randomInt())
        emit(Explore(id: id, numArguments: arguments.count, rngSeed: rngSeed), withInputs: [v] + arguments)
    }

    public func probe(_ v: Variable, id: String) {
        emit(Probe(id: id), withInputs: [v])
    }

    @discardableResult
    public func fixup(id: String, action: String, originalOperation: String, arguments: [Variable], hasOutput: Bool) -> Variable? {
        let instr = emit(Fixup(id: id, action: action, originalOperation: originalOperation, numArguments: arguments.count, hasOutput: hasOutput), withInputs: arguments)
        return hasOutput ? instr.output : nil
    }

    // Helper struct to describe subroutine definitions.
    // This allows defining functions by just specifying the number of parameters or by specifying the types of the individual parameters.
    // Note however that parameter types are not associated with the generated operations and will therefore just be valid for the lifetime
    // of this ProgramBuilder. The reason for this behaviour is that it is generally not possible to preserve the type information across program
    // mutations: a mutator may change the callsite of a function or modify the uses of a parameter, effectively invalidating the parameter types.
    // Parameter types are therefore only valid when a function is first created.
    public struct SubroutineDescriptor {
        // The parameter "structure", i.e. the number of parameters and whether there is a rest parameter, etc.
        // Currently, this information is also fully contained in the parameterTypes member. However, if we ever
        // add support for features such as parameter destructuring, this would no longer be the case.
        public let parameters: Parameters
        // Type information for every parameter. If no type information is specified, the parameters will all use .jsAnything as type.
        public let parameterTypes: ParameterList

        public var count: Int {
            return parameters.count
        }

        public static func parameters(n: Int, hasRestParameter: Bool = false) -> SubroutineDescriptor {
            return SubroutineDescriptor(withParameters: Parameters(count: n, hasRestParameter: hasRestParameter))
        }

        public static func parameters(_ params: Parameter...) -> SubroutineDescriptor {
            return parameters(ParameterList(params))
        }

        public static func parameters(_ parameterTypes: ParameterList) -> SubroutineDescriptor {
            let parameters = Parameters(count: parameterTypes.count, hasRestParameter: parameterTypes.hasRestParameter)
            return SubroutineDescriptor(withParameters: parameters, ofTypes: parameterTypes)
        }

        private init(withParameters parameters: Parameters, ofTypes parameterTypes: ParameterList? = nil) {
            if let types = parameterTypes {
                assert(types.areValid())
                assert(types.count == parameters.count)
                assert(types.hasRestParameter == parameters.hasRestParameter)
                self.parameterTypes = types
            } else {
                self.parameterTypes = ParameterList(numParameters: parameters.count, hasRestParam: parameters.hasRestParameter)
                assert(self.parameterTypes.allSatisfy({ $0 == .plain(.jsAnything) || $0 == .rest(.jsAnything) }))
            }
            self.parameters = parameters
        }
    }

    @discardableResult
    public func buildPlainFunction(with descriptor: SubroutineDescriptor, named functionName: String? = nil,_ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginPlainFunction(parameters: descriptor.parameters, functionName: functionName))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndPlainFunction())
        return instr.output
    }

    @discardableResult
    public func buildArrowFunction(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginArrowFunction(parameters: descriptor.parameters))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildGeneratorFunction(with descriptor: SubroutineDescriptor, named functionName: String? = nil, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginGeneratorFunction(parameters: descriptor.parameters, functionName: functionName))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncFunction(with descriptor: SubroutineDescriptor, named functionName: String? = nil, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncFunction(parameters: descriptor.parameters, functionName: functionName))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndAsyncFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncArrowFunction(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncArrowFunction(parameters: descriptor.parameters))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndAsyncArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncGeneratorFunction(with descriptor: SubroutineDescriptor, named functionName: String? = nil, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncGeneratorFunction(parameters: descriptor.parameters, functionName: functionName))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndAsyncGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginConstructor(parameters: descriptor.parameters))
        if enableRecursionGuard { hide(instr.output) }
        body(Array(instr.innerOutputs))
        if enableRecursionGuard { unhide(instr.output) }
        emit(EndConstructor())
        return instr.output
    }

    public func directive(_ content: String) {
        emit(Directive(content))
    }

    public func doReturn(_ value: Variable? = nil) {
        if let returnValue = value {
            emit(Return(hasReturnValue: true), withInputs: [returnValue])
        } else {
            emit(Return(hasReturnValue: false))
        }
    }

    public func maybeReturnRandomJsVariable(_ prob: Double) {
        if probability(prob) {
            doReturn(randomJsVariable())
        }
    }

    @discardableResult
    public func yield(_ value: Variable? = nil) -> Variable {
        if let argument = value {
            return emit(Yield(hasArgument: true), withInputs: [argument]).output
        } else {
            return emit(Yield(hasArgument: false)).output
        }
    }

    public func yieldEach(_ value: Variable) {
        emit(YieldEach(), withInputs: [value])
    }

    @discardableResult
    public func await(_ value: Variable) -> Variable {
        return emit(Await(), withInputs: [value]).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(CallFunction(numArguments: arguments.count, isGuarded: isGuarded), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return callFunction(function, withArgs: arguments) }
        return emit(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(Construct(numArguments: arguments.count, isGuarded: isGuarded), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return construct(constructor, withArgs: arguments) }
        return emit(ConstructWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(CallMethod(methodName: name, numArguments: arguments.count, isGuarded: isGuarded), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return callMethod(name, on: object, withArgs: arguments) }
        return emit(CallMethodWithSpread(methodName: name, numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func bindMethod(_ name: String, on object: Variable) -> Variable {
        return emit(BindMethod(methodName: name), withInputs: [object]).output
    }

    @discardableResult
    public func bindFunction(_ fct: Variable, boundArgs arguments: [Variable]) -> Variable {
        return emit(BindFunction(numInputs: arguments.count + 1), withInputs: [fct] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(CallComputedMethod(numArguments: arguments.count, isGuarded: isGuarded), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return callComputedMethod(name, on: object, withArgs: arguments) }
        return emit(CallComputedMethodWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func unary(_ op: UnaryOperator, _ input: Variable) -> Variable {
        return emit(UnaryOperation(op), withInputs: [input]).output
    }

    @discardableResult
    public func binary(_ lhs: Variable, _ rhs: Variable, with op: BinaryOperator) -> Variable {
        return emit(BinaryOperation(op), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func ternary(_ condition: Variable, _ lhs: Variable, _ rhs: Variable) -> Variable {
        return emit(TernaryOperation(), withInputs: [condition, lhs, rhs]).output
    }

    public func reassign(_ output: Variable, to input: Variable, with op: BinaryOperator) {
        emit(Update(op), withInputs: [output, input])
    }

    @discardableResult
    public func dup(_ v: Variable) -> Variable {
        return emit(Dup(), withInputs: [v]).output
    }

    public func reassign(_ output: Variable, to input: Variable) {
        emit(Reassign(), withInputs: [output, input])
    }

    @discardableResult
    public func destruct(_ input: Variable, selecting indices: [Int64], lastIsRest: Bool = false) -> [Variable] {
        let outputs = emit(DestructArray(indices: indices, lastIsRest: lastIsRest), withInputs: [input]).outputs
        return Array(outputs)
    }

    public func destruct(_ input: Variable, selecting indices: [Int64], into outputs: [Variable], lastIsRest: Bool = false) {
        emit(DestructArrayAndReassign(indices: indices, lastIsRest: lastIsRest), withInputs: [input] + outputs)
    }

    @discardableResult
    public func destruct(_ input: Variable, selecting properties: [String], hasRestElement: Bool = false) -> [Variable] {
        let outputs = emit(DestructObject(properties: properties, hasRestElement: hasRestElement), withInputs: [input]).outputs
        return Array(outputs)
    }

    public func destruct(_ input: Variable, selecting properties: [String], into outputs: [Variable], hasRestElement: Bool = false) {
        emit(DestructObjectAndReassign(properties: properties, hasRestElement: hasRestElement), withInputs: [input] + outputs)
    }

    @discardableResult
    public func compare(_ lhs: Variable, with rhs: Variable, using comparator: Comparator) -> Variable {
        return emit(Compare(comparator), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func createNamedVariable(_ name: String, declarationMode: NamedVariableDeclarationMode, initialValue: Variable? = nil) -> Variable {
        assert((declarationMode == .none) == (initialValue == nil))
        let inputs = initialValue != nil ? [initialValue!] : []
        return emit(CreateNamedVariable(name, declarationMode: declarationMode), withInputs: inputs).output
    }

    @discardableResult
    public func createNamedVariable(forBuiltin builtinName: String) -> Variable {
        return createNamedVariable(builtinName, declarationMode: .none)
    }

    @discardableResult
    public func createNamedDisposableVariable(_ name: String, _ initialValue: Variable) -> Variable {
        return emit(CreateNamedDisposableVariable(name), withInputs: [initialValue]).output
    }

    @discardableResult
    public func createNamedAsyncDisposableVariable(_ name: String, _ initialValue: Variable) -> Variable {
        return emit(CreateNamedAsyncDisposableVariable(name), withInputs: [initialValue]).output
    }

    @discardableResult
    public func createSymbolProperty(_ name: String) -> Variable {
        let Symbol = createNamedVariable(forBuiltin: "Symbol")
        // The Symbol constructor is just a "side effect" and probably
        // shouldn't be used by following generators.
        hide(Symbol)
        return getProperty(name, of: Symbol)
    }

    @discardableResult
    public func eval(_ string: String, with arguments: [Variable] = [], hasOutput: Bool = false) -> Variable? {
        let instr = emit(Eval(string, numArguments: arguments.count, hasOutput: hasOutput), withInputs: arguments)
        return hasOutput ? instr.output : nil
    }

    public func buildWith(_ scopeObject: Variable, body: () -> Void) {
        emit(BeginWith(), withInputs: [scopeObject])
        body()
        emit(EndWith())
    }

    public func nop(numOutputs: Int = 0) {
        emit(Nop(numOutputs: numOutputs), withInputs: [])
    }

    public func callSuperConstructor(withArgs arguments: [Variable]) {
        emit(CallSuperConstructor(numArguments: arguments.count), withInputs: arguments)
    }

    @discardableResult
    public func callSuperMethod(_ name: String, withArgs arguments: [Variable] = []) -> Variable {
        return emit(CallSuperMethod(methodName: name, numArguments: arguments.count), withInputs: arguments).output
    }

    @discardableResult
    public func getPrivateProperty(_ name: String, of object: Variable) -> Variable {
        return emit(GetPrivateProperty(propertyName: name), withInputs: [object]).output
    }

    public func setPrivateProperty(_ name: String, of object: Variable, to value: Variable) {
        emit(SetPrivateProperty(propertyName: name), withInputs: [object, value])
    }

    public func updatePrivateProperty(_ name: String, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdatePrivateProperty(propertyName: name, operator: op), withInputs: [object, value])
    }

    @discardableResult
    public func callPrivateMethod(_ name: String, on object: Variable, withArgs arguments: [Variable] = []) -> Variable {
        return emit(CallPrivateMethod(methodName: name, numArguments: arguments.count), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func getSuperProperty(_ name: String) -> Variable {
        return emit(GetSuperProperty(propertyName: name)).output
    }

    public func setSuperProperty(_ name: String, to value: Variable) {
        emit(SetSuperProperty(propertyName: name), withInputs: [value])
    }

    @discardableResult
    public func getComputedSuperProperty(_ property: Variable) -> Variable {
        return emit(GetComputedSuperProperty(), withInputs: [property]).output
    }

    public func setComputedSuperProperty(_ property: Variable, to value: Variable) {
        emit(SetComputedSuperProperty(), withInputs: [property, value])
    }

    public func updateSuperProperty(_ name: String, with value: Variable, using op: BinaryOperator) {
        emit(UpdateSuperProperty(propertyName: name, operator: op), withInputs: [value])
    }

    public func buildIf(_ condition: Variable, ifBody: () -> Void) {
        emit(BeginIf(inverted: false), withInputs: [condition])
        ifBody()
        emit(EndIf())
    }

    public func buildIfElse(_ condition: Variable, ifBody: () -> Void, elseBody: () -> Void) {
        emit(BeginIf(inverted: false), withInputs: [condition])
        ifBody()
        emit(BeginElse())
        elseBody()
        emit(EndIf())
    }

    public class SwitchBlock {
        private let b: ProgramBuilder
        public fileprivate(set) var hasDefaultCase: Bool = false

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.switchBlock))
            self.b = b
        }

        public func addDefaultCase(fallsThrough: Bool = false, body: @escaping () -> ()) {
            b.emit(BeginSwitchDefaultCase(), withInputs: [])
            body()
            b.emit(EndSwitchCase(fallsThrough: fallsThrough))
        }

        public func addCase(_ v: Variable, fallsThrough: Bool = false, body: @escaping () -> ()) {
            b.emit(BeginSwitchCase(), withInputs: [v])
            body()
            b.emit(EndSwitchCase(fallsThrough: fallsThrough))
        }
    }

    public func buildSwitch(on switchVar: Variable, body: (SwitchBlock) -> ()) {
        emit(BeginSwitch(), withInputs: [switchVar])
        body(currentSwitchBlock)
        emit(EndSwitch())
    }

    public func switchBreak() {
        emit(SwitchBreak())
    }

    public func buildWhileLoop(_ header: () -> Variable, _ body: () -> Void) {
        emit(BeginWhileLoopHeader())
        let cond = header()
        emit(BeginWhileLoopBody(), withInputs: [cond])
        body()
        emit(EndWhileLoop())
    }

    public func buildDoWhileLoop(do body: () -> Void, while header: () -> Variable) {
        emit(BeginDoWhileLoopBody())
        body()
        emit(BeginDoWhileLoopHeader())
        let cond = header()
        emit(EndDoWhileLoop(), withInputs: [cond])
    }

    // Build a simple for loop that declares one loop variable.
    public func buildForLoop(i initializer: () -> Variable, _ cond: (Variable) -> Variable, _ afterthought: (Variable) -> (), _ body: (Variable) -> ()) {
        emit(BeginForLoopInitializer())
        let initialValue = initializer()
        var loopVar = emit(BeginForLoopCondition(numLoopVariables: 1), withInputs: [initialValue]).innerOutput
        let cond = cond(loopVar)
        loopVar = emit(BeginForLoopAfterthought(numLoopVariables: 1), withInputs: [cond]).innerOutput
        afterthought(loopVar)
        loopVar = emit(BeginForLoopBody(numLoopVariables: 1)).innerOutput
        body(loopVar)
        emit(EndForLoop())
    }

    // Build arbitrarily complex for loops without any loop variables.
    public func buildForLoop(_ initializer: (() -> ())? = nil, _ cond: (() -> Variable)? = nil, _ afterthought: (() -> ())? = nil, _ body: () -> ()) {
        emit(BeginForLoopInitializer())
        initializer?()
        emit(BeginForLoopCondition(numLoopVariables: 0))
        let cond = cond?() ?? loadBool(true)
        emit(BeginForLoopAfterthought(numLoopVariables: 0), withInputs: [cond])
        afterthought?()
        emit(BeginForLoopBody(numLoopVariables: 0))
        body()
        emit(EndForLoop())
    }

    // Build arbitrarily complex for loops with one or more loop variables.
    public func buildForLoop(_ initializer: () -> [Variable], _ cond: (([Variable]) -> Variable)? = nil, _ afterthought: (([Variable]) -> ())? = nil, _ body: ([Variable]) -> ()) {
        emit(BeginForLoopInitializer())
        let initialValues = initializer()
        var loopVars = emit(BeginForLoopCondition(numLoopVariables: initialValues.count), withInputs: initialValues).innerOutputs
        let cond = cond?(Array(loopVars)) ?? loadBool(true)
        loopVars = emit(BeginForLoopAfterthought(numLoopVariables: initialValues.count), withInputs: [cond]).innerOutputs
        afterthought?(Array(loopVars))
        loopVars = emit(BeginForLoopBody(numLoopVariables: initialValues.count)).innerOutputs
        body(Array(loopVars))
        emit(EndForLoop())
    }

    public func buildForInLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = emit(BeginForInLoop(), withInputs: [obj]).innerOutput
        body(i)
        emit(EndForInLoop())
    }

    public func buildForOfLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = emit(BeginForOfLoop(), withInputs: [obj]).innerOutput
        body(i)
        emit(EndForOfLoop())
    }

    public func buildForOfLoop(_ obj: Variable, selecting indices: [Int64], hasRestElement: Bool = false, _ body: ([Variable]) -> ()) {
        let instr = emit(BeginForOfLoopWithDestruct(indices: indices, hasRestElement: hasRestElement), withInputs: [obj])
        body(Array(instr.innerOutputs))
        emit(EndForOfLoop())
    }

    public func buildRepeatLoop(n numIterations: Int, _ body: (Variable) -> ()) {
        let i = emit(BeginRepeatLoop(iterations: numIterations)).innerOutput
        body(i)
        emit(EndRepeatLoop())
    }

    public func buildRepeatLoop(n numIterations: Int, _ body: () -> ()) {
        emit(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: false))
        body()
        emit(EndRepeatLoop())
    }

    public func loopBreak() {
        emit(LoopBreak())
    }

    public func loopContinue() {
        emit(LoopContinue(), withInputs: [])
    }

    public func buildTryCatchFinally(tryBody: () -> (), catchBody: ((Variable) -> ())? = nil, finallyBody: (() -> ())? = nil) {
        assert(catchBody != nil || finallyBody != nil, "Must have either a Catch or a Finally block (or both)")
        emit(BeginTry())
        tryBody()
        if let catchBody = catchBody {
            let exception = emit(BeginCatch()).innerOutput
            catchBody(exception)
        }
        if let finallyBody = finallyBody {
            emit(BeginFinally())
            finallyBody()
        }
        emit(EndTryCatchFinally())
    }

    public func throwException(_ value: Variable) {
        emit(ThrowException(), withInputs: [value])
    }

    public func buildCodeString(_ body: () -> ()) -> Variable {
        let instr = emit(BeginCodeString())
        body()
        emit(EndCodeString())
        return instr.output
    }

    public func blockStatement(_ body: () -> Void) {
        emit(BeginBlockStatement())
        body()
        emit(EndBlockStatement())
    }

    public func doPrint(_ value: Variable) {
        emit(Print(), withInputs: [value])
    }


    @discardableResult
    public func createWasmGlobal(value: WasmGlobal, isMutable: Bool) -> Variable {
        let variable = emit(CreateWasmGlobal(value: value, isMutable: isMutable)).output
        return variable
    }

    @discardableResult
    public func createWasmMemory(minPages: Int, maxPages: Int? = nil, isShared: Bool = false, isMemory64: Bool = false) -> Variable {
        assert(!isShared || maxPages != nil, "Shared memories must have a maximum size")
        return emit(CreateWasmMemory(limits: Limits(min: minPages, max: maxPages), isShared: isShared, isMemory64: isMemory64)).output
    }

    public func createWasmTable(elementType: ILType, limits: Limits, isTable64: Bool) -> Variable {
        return emit(CreateWasmTable(elementType: elementType, limits: limits, isTable64: isTable64)).output
    }

    @discardableResult
    public func createWasmJSTag() -> Variable {
        return emit(CreateWasmJSTag()).output
    }

    @discardableResult
    public func createWasmTag(parameterTypes: [ILType]) -> Variable {
        return emit(CreateWasmTag(parameterTypes: parameterTypes)).output
    }

    @discardableResult
    public func wrapSuspending(function: Variable) -> Variable {
        return emit(WrapSuspending(), withInputs: [function]).output
    }

    @discardableResult
    public func wrapPromising(function: Variable) -> Variable {
        return emit(WrapPromising(), withInputs: [function]).output
    }

    public class WasmFunction {
        private let b: ProgramBuilder
        let signature: WasmSignature
        let jsSignature: Signature

        public init(forBuilder b: ProgramBuilder, withSignature signature: WasmSignature) {
            self.b = b
            self.signature = signature
            self.jsSignature = convertWasmSignatureToJsSignature(signature)
        }

        // Wasm Instructions
        @discardableResult
        public func consti32(_ value: Int32) -> Variable {
            return b.emit(Consti32(value: value)).output
        }

        @discardableResult
        public func consti64(_ value: Int64) -> Variable {
            return b.emit(Consti64(value: value)).output
        }

        @discardableResult
        public func memoryArgument(_ value: Int64, _ memoryTypeInfo: WasmMemoryType) -> Variable {
            if (memoryTypeInfo.isMemory64) {
                return self.consti64(value)
            } else {
                return self.consti32(Int32(value))
            }
        }

        @discardableResult
        public func constf32(_ value: Float32) -> Variable {
            return b.emit(Constf32(value: value)).output
        }

        @discardableResult
        public func constf64(_ value: Float64) -> Variable {
            return b.emit(Constf64(value: value)).output
        }

        @discardableResult
        public func wasmi64BinOp(_ lhs: Variable, _ rhs: Variable, binOpKind: WasmIntegerBinaryOpKind) -> Variable {
            return b.emit(Wasmi64BinOp(binOpKind: binOpKind), withInputs: [lhs, rhs], types: [.wasmi64, .wasmi64]).output
        }

        @discardableResult
        public func wasmi32BinOp(_ lhs: Variable, _ rhs: Variable, binOpKind: WasmIntegerBinaryOpKind) -> Variable {
            return b.emit(Wasmi32BinOp(binOpKind: binOpKind), withInputs: [lhs, rhs], types: [.wasmi32, .wasmi32]).output
        }

        @discardableResult
        public func wasmf32BinOp(_ lhs: Variable, _ rhs: Variable, binOpKind: WasmFloatBinaryOpKind) -> Variable {
            return b.emit(Wasmf32BinOp(binOpKind: binOpKind), withInputs: [lhs, rhs], types: [.wasmf32, .wasmf32]).output
        }

        @discardableResult
        public func wasmf64BinOp(_ lhs: Variable, _ rhs: Variable, binOpKind: WasmFloatBinaryOpKind) -> Variable {
            return b.emit(Wasmf64BinOp(binOpKind: binOpKind), withInputs: [lhs, rhs], types: [.wasmf64, .wasmf64]).output
        }

        @discardableResult
        public func wasmi32UnOp(_ input: Variable, unOpKind: WasmIntegerUnaryOpKind) -> Variable {
            return b.emit(Wasmi32UnOp(unOpKind: unOpKind), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func wasmi64UnOp(_ input: Variable, unOpKind: WasmIntegerUnaryOpKind) -> Variable {
            return b.emit(Wasmi64UnOp(unOpKind: unOpKind), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func wasmf32UnOp(_ input: Variable, unOpKind: WasmFloatUnaryOpKind) -> Variable {
            return b.emit(Wasmf32UnOp(unOpKind: unOpKind), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func wasmf64UnOp(_ input: Variable, unOpKind: WasmFloatUnaryOpKind) -> Variable {
            return b.emit(Wasmf64UnOp(unOpKind: unOpKind), withInputs: [input],types: [.wasmf64]).output
        }

        @discardableResult
        public func wasmi32EqualZero(_ input: Variable) -> Variable {
            return b.emit(Wasmi32EqualZero(), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func wasmi64EqualZero(_ input: Variable) -> Variable {
            return b.emit(Wasmi64EqualZero(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func wasmi32CompareOp(_ lhs: Variable, _ rhs: Variable, using compareOperator: WasmIntegerCompareOpKind) -> Variable {
            return b.emit(Wasmi32CompareOp(compareOpKind: compareOperator), withInputs: [lhs, rhs], types: [.wasmi32, .wasmi32]).output
        }

        @discardableResult
        public func wasmi64CompareOp(_ lhs: Variable, _ rhs: Variable, using compareOperator: WasmIntegerCompareOpKind) -> Variable {
            return b.emit(Wasmi64CompareOp(compareOpKind: compareOperator), withInputs: [lhs, rhs], types: [.wasmi64, .wasmi64]).output
        }

        @discardableResult
        public func wasmf64CompareOp(_ lhs: Variable, _ rhs: Variable, using compareOperator: WasmFloatCompareOpKind) -> Variable {
            return b.emit(Wasmf64CompareOp(compareOpKind: compareOperator), withInputs: [lhs, rhs], types: [.wasmf64, .wasmf64]).output
        }

        @discardableResult
        public func wasmf32CompareOp(_ lhs: Variable, _ rhs: Variable, using compareOperator: WasmFloatCompareOpKind) -> Variable {
            return b.emit(Wasmf32CompareOp(compareOpKind: compareOperator), withInputs: [lhs, rhs], types: [.wasmf32, .wasmf32]).output
        }

        @discardableResult
        public func wrapi64Toi32(_ input: Variable) -> Variable {
            return b.emit(WasmWrapi64Toi32(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func truncatef32Toi32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncatef32Toi32(isSigned: isSigned), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func truncatef64Toi32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncatef64Toi32(isSigned: isSigned), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func extendi32Toi64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmExtendi32Toi64(isSigned: isSigned), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func truncatef32Toi64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncatef32Toi64(isSigned: isSigned), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func truncatef64Toi64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncatef64Toi64(isSigned: isSigned), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func converti32Tof32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmConverti32Tof32(isSigned: isSigned), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func converti64Tof32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmConverti64Tof32(isSigned: isSigned), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func demotef64Tof32(_ input: Variable) -> Variable {
            return b.emit(WasmDemotef64Tof32(), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func converti32Tof64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmConverti32Tof64(isSigned: isSigned), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func converti64Tof64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmConverti64Tof64(isSigned: isSigned), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func promotef32Tof64(_ input: Variable) -> Variable {
            return b.emit(WasmPromotef32Tof64(), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func reinterpretf32Asi32(_ input: Variable) -> Variable {
            return b.emit(WasmReinterpretf32Asi32(), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func reinterpretf64Asi64(_ input: Variable) -> Variable {
            return b.emit(WasmReinterpretf64Asi64(), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func reinterpreti32Asf32(_ input: Variable) -> Variable {
            return b.emit(WasmReinterpreti32Asf32(), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func reinterpreti64Asf64(_ input: Variable) -> Variable {
            return b.emit(WasmReinterpreti64Asf64(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func signExtend8Intoi32(_ input: Variable) -> Variable {
            return b.emit(WasmSignExtend8Intoi32(), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func signExtend16Intoi32(_ input: Variable) -> Variable {
            return b.emit(WasmSignExtend16Intoi32(), withInputs: [input], types: [.wasmi32]).output
        }

        @discardableResult
        public func signExtend8Intoi64(_ input: Variable) -> Variable {
            return b.emit(WasmSignExtend8Intoi64(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func signExtend16Intoi64(_ input: Variable) -> Variable {
            return b.emit(WasmSignExtend16Intoi64(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func signExtend32Intoi64(_ input: Variable) -> Variable {
            return b.emit(WasmSignExtend32Intoi64(), withInputs: [input], types: [.wasmi64]).output
        }

        @discardableResult
        public func truncateSatf32Toi32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncateSatf32Toi32(isSigned: isSigned), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func truncateSatf64Toi32(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncateSatf64Toi32(isSigned: isSigned), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func truncateSatf32Toi64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncateSatf32Toi64(isSigned: isSigned), withInputs: [input], types: [.wasmf32]).output
        }

        @discardableResult
        public func truncateSatf64Toi64(_ input: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmTruncateSatf64Toi64(isSigned: isSigned), withInputs: [input], types: [.wasmf64]).output
        }

        @discardableResult
        public func wasmLoadGlobal(globalVariable: Variable) -> Variable {
            let type = b.type(of: globalVariable).wasmGlobalType!.valueType
            return b.emit(WasmLoadGlobal(globalType: type), withInputs:[globalVariable], types: [ILType.object(ofGroup: "WasmGlobal")]).output
        }

        public func wasmStoreGlobal(globalVariable: Variable, to value: Variable) {
            let type = b.type(of: globalVariable).wasmGlobalType!.valueType
            let inputTypes = [ILType.object(ofGroup: "WasmGlobal", withWasmType: WasmGlobalType(valueType: type, isMutable: true)), type]
            b.emit(WasmStoreGlobal(globalType: type), withInputs: [globalVariable, value], types: inputTypes)
        }

        @discardableResult
        public func wasmTableGet(tableRef: Variable, idx: Variable) -> Variable {
            let tableType = b.type(of: tableRef)
            let offsetType = tableType.wasmTableType!.isTable64 ? ILType.wasmi64 : ILType.wasmi32
            return b.emit(WasmTableGet(tableType: tableType), withInputs: [tableRef, idx], types: [tableType, offsetType]).output
        }

        public func wasmTableSet(tableRef: Variable, idx: Variable, to value: Variable) {
            let tableType = b.type(of: tableRef)
            let elementType = tableType.wasmTableType!.elementType
            let offsetType = tableType.wasmTableType!.isTable64 ? ILType.wasmi64 : ILType.wasmi32
            b.emit(WasmTableSet(tableType: tableType), withInputs: [tableRef, idx, value], types: [tableType, offsetType, elementType])
        }

        @discardableResult
        public func wasmTableSize(table: Variable) -> Variable {
            return b.emit(WasmTableSize(), withInputs: [table],
                types: [.object(ofGroup: "WasmTable")]).output
        }

        @discardableResult
        public func wasmTableGrow(table: Variable, with initialValue: Variable, by delta: Variable) -> Variable {
            let tableType = b.type(of: table)
            let elementType = tableType.wasmTableType!.elementType
            let offsetType = tableType.wasmTableType!.isTable64 ? ILType.wasmi64 : ILType.wasmi32
            return b.emit(WasmTableGrow(), withInputs: [table, initialValue, delta],
                types: [.object(ofGroup: "WasmTable"), elementType, offsetType]).output
        }

        @discardableResult
        public func wasmCallIndirect(signature: WasmSignature, table: Variable, functionArgs: [Variable], tableIndex: Variable) -> [Variable] {
            let isTable64 = b.type(of: table).wasmTableType!.isTable64
            return Array(b.emit(WasmCallIndirect(signature: signature),
                withInputs: [table] + functionArgs + [tableIndex],
                types: [.wasmTable] + signature.parameterTypes + [isTable64 ? .wasmi64 : .wasmi32]
            ).outputs)
        }

        @discardableResult
        public func wasmCallDirect(signature: WasmSignature, function: Variable, functionArgs: [Variable]) -> [Variable] {
            return Array(b.emit(WasmCallDirect(signature: signature),
                withInputs: [function] + functionArgs,
                types: [.wasmFunctionDef(signature)] + signature.parameterTypes
            ).outputs)
        }

        public func wasmReturnCallDirect(signature: WasmSignature, function: Variable, functionArgs: [Variable]) {
            assert(self.signature.outputTypes == signature.outputTypes)
            b.emit(WasmReturnCallDirect(signature: signature),
                withInputs: [function] + functionArgs,
                types: [.wasmFunctionDef(signature)] + signature.parameterTypes)
        }

        public func wasmReturnCallIndirect(signature: WasmSignature, table: Variable, functionArgs: [Variable], tableIndex: Variable) {
            let isTable64 = b.type(of: table).wasmTableType!.isTable64
            assert(self.signature.outputTypes == signature.outputTypes)
            b.emit(WasmReturnCallIndirect(signature: signature),
                withInputs: [table] + functionArgs + [tableIndex],
                types: [.wasmTable] + signature.parameterTypes + [isTable64 ? .wasmi64 : .wasmi32])
        }

        @discardableResult
        public func wasmJsCall(function: Variable, withArgs args: [Variable], withWasmSignature signature: WasmSignature) -> Variable? {
            let instr = b.emit(WasmJsCall(signature: signature), withInputs: [function] + args,
                types: [.function() | .object(ofGroup: "WasmSuspendingObject")] + signature.parameterTypes)
            if signature.outputTypes.isEmpty {
                assert(!instr.hasOutputs)
                return nil
            } else {
                assert(instr.hasOutputs)
                return instr.output
            }
        }

        @discardableResult
        public func wasmMemoryLoad(memory: Variable, dynamicOffset: Variable, loadType: WasmMemoryLoadType, staticOffset: Int64) -> Variable {
            let addrType = b.type(of: memory).wasmMemoryType!.addrType
            return b.emit(WasmMemoryLoad(loadType: loadType, staticOffset: staticOffset), withInputs: [memory, dynamicOffset], types: [.object(ofGroup: "WasmMemory"), addrType]).output
        }

        public func wasmMemoryStore(memory: Variable, dynamicOffset: Variable, value: Variable, storeType: WasmMemoryStoreType, staticOffset: Int64) {
            assert(b.type(of: value) == storeType.numberType())
            let addrType = b.type(of: memory).wasmMemoryType!.addrType
            let inputTypes = [ILType.object(ofGroup: "WasmMemory"), addrType, storeType.numberType()]
            b.emit(WasmMemoryStore(storeType: storeType, staticOffset: staticOffset), withInputs: [memory, dynamicOffset, value], types: inputTypes)
        }

        @discardableResult
        func wasmAtomicLoad(memory: Variable, address: Variable, loadType: WasmAtomicLoadType, offset: Int64) -> Variable {
            let op = WasmAtomicLoad(loadType: loadType, offset: offset)
            return b.emit(op, withInputs: [memory, address]).output
        }

        func wasmAtomicStore(memory: Variable, address: Variable, value: Variable, storeType: WasmAtomicStoreType, offset: Int64) {
            let op = WasmAtomicStore(storeType: storeType, offset: offset)
            b.emit(op, withInputs: [memory, address, value])
        }

        @discardableResult
        func wasmAtomicRMW(memory: Variable, lhs: Variable, rhs: Variable, op: WasmAtomicRMWType, offset: Int64) -> Variable {
            let op = WasmAtomicRMW(op: op, offset: offset)
            let anyInt: ILType = .wasmi32 | .wasmi64
            let valueType = op.op.type()
            return b.emit(op, withInputs: [memory, lhs, rhs], types: [.object(ofGroup: "WasmMemory"), anyInt, valueType]).output
        }

        @discardableResult
        func wasmAtomicCmpxchg(memory: Variable, address: Variable, expected: Variable, replacement: Variable, op: WasmAtomicCmpxchgType, offset: Int64) -> Variable {
            let op = WasmAtomicCmpxchg(op: op, offset: offset)
            let anyInt: ILType = .wasmi32 | .wasmi64
            let valueType = op.op.type()
            return b.emit(op, withInputs: [memory, address, expected, replacement], types: [.object(ofGroup: "WasmMemory"), anyInt, valueType, valueType]).output
        }

        @discardableResult
        public func wasmMemorySize(memory: Variable) -> Variable {
            return b.emit(WasmMemorySize(), withInputs: [memory],
                types: [.object(ofGroup: "WasmMemory")]).output
        }

        @discardableResult
        public func wasmMemoryGrow(memory: Variable, growByPages: Variable) -> Variable {
            let addrType = b.type(of: memory).wasmMemoryType!.addrType
            return b.emit(WasmMemoryGrow(), withInputs: [memory, growByPages],
                types: [.object(ofGroup: "WasmMemory"), addrType]).output
        }

        public func wasmMemoryCopy(dstMemory: Variable, srcMemory: Variable,  dstOffset: Variable, srcOffset: Variable, size: Variable) {
            let dstMemoryType = b.type(of: dstMemory).wasmMemoryType!
            let srcMemoryType = b.type(of: srcMemory).wasmMemoryType!
            assert(dstMemoryType.isMemory64 == srcMemoryType.isMemory64)

            let addrType = dstMemoryType.addrType
            b.emit(WasmMemoryCopy(), withInputs: [dstMemory, srcMemory, dstOffset, srcOffset, size],
                types: [.object(ofGroup: "WasmMemory"), .object(ofGroup: "WasmMemory"), addrType, addrType, addrType])
        }

        public func wasmMemoryFill(memory: Variable, offset: Variable, byteToSet: Variable, nrOfBytesToUpdate: Variable) {
            let addrType = b.type(of: memory).wasmMemoryType!.addrType
            b.emit(WasmMemoryFill(), withInputs: [memory, offset, byteToSet, nrOfBytesToUpdate],
                types: [.object(ofGroup: "WasmMemory"), addrType, .wasmi32, addrType])
        }

        public func wasmMemoryInit(dataSegment: Variable, memory: Variable, memoryOffset: Variable, dataSegmentOffset: Variable, nrOfBytesToUpdate: Variable) {
            let addrType = b.type(of: memory).wasmMemoryType!.addrType
            b.emit(WasmMemoryInit(), withInputs: [dataSegment, memory, memoryOffset, dataSegmentOffset, nrOfBytesToUpdate],
                types: [.wasmDataSegment(), .object(ofGroup: "WasmMemory"), addrType, .wasmi32, .wasmi32])
        }

        public func wasmDropDataSegment(dataSegment: Variable) {
            b.emit(WasmDropDataSegment(), withInputs: [dataSegment], types: [.wasmDataSegment()])
        }

        public func wasmDropElementSegment(elementSegment: Variable) {
            b.emit(WasmDropElementSegment(), withInputs: [elementSegment], types: [.wasmElementSegment()])
        }

        public func wasmTableInit(elementSegment: Variable, table: Variable, tableOffset: Variable, elementSegmentOffset: Variable, nrOfElementsToUpdate: Variable) {
            let elementSegmentType = ILType.wasmFuncRef
            let tableElemType = b.type(of: table).wasmTableType!.elementType
            assert(elementSegmentType.Is(tableElemType))

            let addrType = b.type(of: table).wasmTableType!.isTable64 ? ILType.wasmi64 : ILType.wasmi32
            b.emit(WasmTableInit(), withInputs: [elementSegment, table, tableOffset, elementSegmentOffset, nrOfElementsToUpdate],
                types: [.wasmElementSegment(), .object(ofGroup: "WasmTable"), addrType, .wasmi32, .wasmi32])
        }

        public func wasmTableCopy(dstTable: Variable, srcTable: Variable, dstOffset: Variable, srcOffset: Variable, count: Variable) {
            let dstTableType = b.type(of: dstTable).wasmTableType!
            let srcTableType = b.type(of: srcTable).wasmTableType!
            assert(dstTableType.isTable64 == srcTableType.isTable64)
            assert(srcTableType.elementType.Is(dstTableType.elementType))

            let addrType = dstTableType.isTable64 ? ILType.wasmi64 : ILType.wasmi32
            b.emit(WasmTableCopy(), withInputs: [dstTable, srcTable, dstOffset, srcOffset, count],
                types: [.object(ofGroup: "WasmTable"), .object(ofGroup: "WasmTable"), addrType, addrType, addrType])
        }

        public func wasmReassign(variable: Variable, to: Variable) {
            assert(b.type(of: variable) == b.type(of: to))
            b.emit(WasmReassign(variableType: b.type(of: variable)), withInputs: [variable, to])
        }

        public enum wasmBlockType {
            case typeIdx(Int)
            case valueType(ILType)
        }

        // The first innerOutput of this block is a label variable, which is just there to explicitly mark control-flow and allow branches.
        public func wasmBuildBlock(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> ()) {
            assert(signature.outputTypes.count == 0)
            let instr = b.emit(WasmBeginBlock(with: signature), withInputs: args, types: signature.parameterTypes)
            body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            b.emit(WasmEndBlock(outputTypes: []))
        }

        @discardableResult
        public func wasmBuildBlockWithResults(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> [Variable]) -> [Variable] {
            let instr = b.emit(WasmBeginBlock(with: signature), withInputs: args, types: signature.parameterTypes)
            let results = body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            return Array(b.emit(WasmEndBlock(outputTypes: signature.outputTypes), withInputs: results, types: signature.outputTypes).outputs)
        }

        // Convenience function to begin a wasm block. Note that this does not emit an end block.
        func wasmBeginBlock(with signature: WasmSignature, args: [Variable]) {
            b.emit(WasmBeginBlock(with: signature), withInputs: args, types: signature.parameterTypes)
        }
        // Convenience function to end a wasm block.
        func wasmEndBlock(outputTypes: [ILType], args: [Variable]) {
            b.emit(WasmEndBlock(outputTypes: outputTypes), withInputs: args, types: outputTypes)
        }

        private func checkArgumentsMatchLabelType(label: ILType, args: [Variable]) {
            let parameterTypes = label.wasmLabelType!.parameters
            let errorMsg = "label type \(label) doesn't match argument types \(args.map({b.type(of: $0)}))"
            assert(parameterTypes.count == args.count, errorMsg)
            // Each argument type must be a subtype of the corresponding label's parameter type.
            assert(zip(parameterTypes, args).allSatisfy {b.type(of: $0.1).Is($0.0)}, errorMsg)
        }

        // This can branch to label variables only, has a variable input for dataflow purposes.
        public func wasmBranch(to label: Variable, args: [Variable] = []) {
            let labelType = b.type(of: label)
            checkArgumentsMatchLabelType(label: labelType, args: args)
            b.emit(WasmBranch(labelTypes: labelType.wasmLabelType!.parameters), withInputs: [label] + args)
        }

        public func wasmBranchIf(_ condition: Variable, to label: Variable, args: [Variable] = [], hint: WasmBranchHint = .None) {
            let labelType = b.type(of: label)
            checkArgumentsMatchLabelType(label: labelType, args: args)
            assert(b.type(of: condition).Is(.wasmi32))
            b.emit(WasmBranchIf(labelTypes: labelType.wasmLabelType!.parameters, hint: hint), withInputs: [label] + args + [condition])
        }

        public func wasmBranchTable(on: Variable, labels: [Variable], args: [Variable]) {
            let argumentTypes = args.map({b.type(of: $0)})
            labels.forEach {
                checkArgumentsMatchLabelType(label: b.type(of: $0), args: args)
            }
            b.emit(WasmBranchTable(labelTypes: argumentTypes, valueCount: labels.count - 1),
                withInputs: labels + args + [on])
        }

        public func wasmBuildIfElse(_ condition: Variable, hint: WasmBranchHint = .None, ifBody: () -> Void, elseBody: (() -> Void)? = nil) {
            b.emit(WasmBeginIf(hint: hint), withInputs: [condition])
            ifBody()
            if let elseBody {
                b.emit(WasmBeginElse())
                elseBody()
            }
            b.emit(WasmEndIf())
        }

        public func wasmBuildIfElse(_ condition: Variable, signature: WasmSignature, args: [Variable], inverted: Bool, ifBody: (Variable, [Variable]) -> Void, elseBody: ((Variable, [Variable]) -> Void)? = nil) {
            let beginBlock = b.emit(WasmBeginIf(with: signature, inverted: inverted),
                withInputs: args + [condition],
                types: signature.parameterTypes + [.wasmi32])
            ifBody(beginBlock.innerOutput(0), Array(beginBlock.innerOutputs(1...)))
            if let elseBody {
                let elseBlock = b.emit(WasmBeginElse(with: signature))
                elseBody(elseBlock.innerOutput(0), Array(elseBlock.innerOutputs(1...)))
            }
            b.emit(WasmEndIf())
        }

        @discardableResult
        public func wasmBuildIfElseWithResult(_ condition: Variable, hint: WasmBranchHint = .None, signature: WasmSignature, args: [Variable], ifBody: (Variable, [Variable]) -> [Variable], elseBody: (Variable, [Variable]) -> [Variable]) -> [Variable] {
            let beginBlock = b.emit(WasmBeginIf(with: signature, hint: hint), withInputs: args + [condition], types: signature.parameterTypes + [.wasmi32])
            let trueResults = ifBody(beginBlock.innerOutput(0), Array(beginBlock.innerOutputs(1...)))
            let elseBlock = b.emit(WasmBeginElse(with: signature), withInputs: trueResults, types: signature.outputTypes)
            let falseResults = elseBody(elseBlock.innerOutput(0), Array(elseBlock.innerOutputs(1...)))
            return Array(b.emit(WasmEndIf(outputTypes: signature.outputTypes), withInputs: falseResults, types: signature.outputTypes).outputs)
        }

        // The first output of this block is a label variable, which is just there to explicitly mark control-flow and allow branches.
        public func wasmBuildLoop(with signature: WasmSignature, body: (Variable, [Variable]) -> Void) {
            let instr = b.emit(WasmBeginLoop(with: signature))
            body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            b.emit(WasmEndLoop())
        }

        @discardableResult
        public func wasmBuildLoop(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> [Variable]) -> [Variable] {
            let instr = b.emit(WasmBeginLoop(with: signature), withInputs: args, types: signature.parameterTypes)
            let fallthroughResults = body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            return Array(b.emit(WasmEndLoop(outputTypes: signature.outputTypes), withInputs: fallthroughResults, types: signature.outputTypes).outputs)
        }

        @discardableResult
        func wasmBuildTryTable(with signature: WasmSignature, args: [Variable], catches: [WasmBeginTryTable.CatchKind], body: (Variable, [Variable]) -> [Variable]) -> [Variable] {
            assert(zip(signature.parameterTypes, args).allSatisfy {b.type(of: $1).Is($0)})
            #if DEBUG
                var argIndex = signature.parameterTypes.count
                for catchKind in catches {
                    switch catchKind {
                    case .Ref:
                        assert(b.type(of: args[argIndex]).Is(.object(ofGroup: "WasmTag")))
                        let labelType = b.type(of: args[argIndex + 1])
                        assert(labelType.Is(.anyLabel))
                        assert(labelType.wasmLabelType!.parameters.last!.Is(.wasmExnRef))
                        argIndex += 2
                    case .NoRef:
                        assert(b.type(of: args[argIndex]).Is(.object(ofGroup: "WasmTag")))
                        assert(b.type(of: args[argIndex + 1]).Is(.anyLabel))
                        argIndex += 2
                    case .AllRef:
                        let labelType = b.type(of: args[argIndex])
                        assert(labelType.Is(.anyLabel))
                        assert(labelType.wasmLabelType!.parameters.last!.Is(.wasmExnRef))
                        argIndex += 1
                    case .AllNoRef:
                        assert(b.type(of: args[argIndex]).Is(.anyLabel))
                        argIndex += 1
                    }
                }
            #endif
            let instr = b.emit(WasmBeginTryTable(with: signature, catches: catches), withInputs: args)
            let results = body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            return Array(b.emit(WasmEndTryTable(outputTypes: signature.outputTypes), withInputs: results).outputs)
        }

        public func wasmBuildLegacyTry(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> Void, catchAllBody: ((Variable) -> Void)? = nil) {
            let instr = b.emit(WasmBeginTry(with: signature), withInputs: args, types: signature.parameterTypes)
            body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            if let catchAllBody = catchAllBody {
                let instr = b.emit(WasmBeginCatchAll(inputTypes: signature.outputTypes))
                catchAllBody(instr.innerOutput(0))
            }
            b.emit(WasmEndTry())
        }

        // The catchClauses expect a list of (tag, block-generator lambda).
        // The lambda's inputs are the block label, the exception label (for rethrowing) and the
        // tag arguments.
        @discardableResult
        public func wasmBuildLegacyTryWithResult(with signature: WasmSignature, args: [Variable],
                body: (Variable, [Variable]) -> [Variable],
                catchClauses: [(tag: Variable, body: (Variable, Variable, [Variable]) -> [Variable])],
                catchAllBody: ((Variable) -> [Variable])? = nil) -> [Variable] {
            let instr = b.emit(WasmBeginTry(with: signature), withInputs: args, types: signature.parameterTypes)
            var result = body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            for (tag, generator) in catchClauses {
                b.reportErrorIf(!b.type(of: tag).isWasmTagType,
                    "Expected tag misses the WasmTagType extension for variable \(tag), typed \(b.type(of: tag)).")
                let instr = b.emit(WasmBeginCatch(with: b.type(of: tag).wasmTagType!.parameters => signature.outputTypes),
                    withInputs: [tag] + result,
                    types: [.object(ofGroup: "WasmTag")] + signature.outputTypes)
                result = generator(instr.innerOutput(0), instr.innerOutput(1), Array(instr.innerOutputs(2...)))
            }
            if let catchAllBody = catchAllBody {
                let instr = b.emit(WasmBeginCatchAll(inputTypes: signature.outputTypes), withInputs: result, types: signature.outputTypes)
                result = catchAllBody(instr.innerOutput(0))
            }
            return Array(b.emit(WasmEndTry(outputTypes: signature.outputTypes), withInputs: result, types: signature.outputTypes).outputs)
        }

        // Build a legacy catch block without a result type. Note that this may only be placed into
        // try blocks that also don't have a result type. (Use wasmBuildLegacyTryWithResult to
        // create a catch block with a result value.)
        public func WasmBuildLegacyCatch(tag: Variable, body: ((Variable, Variable, [Variable]) -> Void)) {
            b.reportErrorIf(!b.type(of: tag).isWasmTagType,
                "Expected tag misses the WasmTagType extension for variable \(tag), typed \(b.type(of: tag)).")
            let instr = b.emit(WasmBeginCatch(with: b.type(of: tag).wasmTagType!.parameters => []), withInputs: [tag], types: [.object(ofGroup: "WasmTag")])
            body(instr.innerOutput(0), instr.innerOutput(1), Array(instr.innerOutputs(2...)))
        }

        public func WasmBuildThrow(tag: Variable, inputs: [Variable]) {
            let tagType = b.type(of: tag).wasmType as! WasmTagType
            b.emit(WasmThrow(parameterTypes: tagType.parameters), withInputs: [tag] + inputs, types: [.object(ofGroup: "WasmTag")] + tagType.parameters)
        }

        public func wasmBuildThrowRef(exception: Variable) {
            b.emit(WasmThrowRef(), withInputs: [exception], types: [.wasmExnRef])
        }

        public func wasmBuildLegacyRethrow(_ exceptionLabel: Variable) {
            b.emit(WasmRethrow(), withInputs: [exceptionLabel], types: [.exceptionLabel])
        }

        public func wasmBuildLegacyTryDelegate(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> Void, delegate: Variable) {
            assert(signature.outputTypes.isEmpty)
            let instr = b.emit(WasmBeginTryDelegate(with: signature), withInputs: args, types: signature.parameterTypes)
            body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            b.emit(WasmEndTryDelegate(), withInputs: [delegate])
        }

        @discardableResult
        public func wasmBuildLegacyTryDelegateWithResult(with signature: WasmSignature, args: [Variable], body: (Variable, [Variable]) -> [Variable], delegate: Variable) -> [Variable] {
            let instr = b.emit(WasmBeginTryDelegate(with: signature), withInputs: args, types: signature.parameterTypes)
            let results = body(instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            return Array(b.emit(WasmEndTryDelegate(outputTypes: signature.outputTypes),
                withInputs: [delegate] + results,
                types: [.anyLabel] + signature.outputTypes
            ).outputs)
        }

        public func generateRandomWasmVar(ofType type: ILType) -> Variable? {
            switch type {
            case .wasmi32:
                return self.consti32(Int32(truncatingIfNeeded: b.randomInt()))
            case .wasmi64:
                return self.consti64(b.randomInt())
            case .wasmf32:
                return self.constf32(Float32(b.randomFloat()))
            case .wasmf64:
                return self.constf64(b.randomFloat())
            case .wasmSimd128:
                return self.constSimd128(value: (0 ..< 16).map{ _ in UInt8.random(in: UInt8.min ... UInt8.max) })
            default:
                if type.Is(.wasmGenericRef) {
                    // TODO(cffsmith): Can we improve this once we have better support for ad hoc
                    // code generation in other contexts?
                    switch type.wasmReferenceType?.kind {
                    case .Abstract(let heapType):
                        if heapType == .WasmI31 {
                            // Prefer generating a non-null value.
                            return probability(0.2) && type.wasmReferenceType!.nullability
                                ? self.wasmRefNull(type: type)
                                : self.wasmRefI31(self.consti32(Int32(truncatingIfNeeded: b.randomInt())))
                        }
                        assert(type.wasmReferenceType!.nullability)
                        return self.wasmRefNull(type: type)
                    case .Index(_),
                         .none:
                        break // Unimplemented
                    }
                } else {
                    return nil
                }
                return nil
            }
        }

        public func findOrGenerateWasmVar(ofType type: ILType) -> Variable {
            b.randomVariable(ofType: type) ?? generateRandomWasmVar(ofType: type)!
        }

        public func wasmUnreachable() {
            b.emit(WasmUnreachable())
        }

        @discardableResult
        public func wasmSelect(on condition: Variable, trueValue: Variable, falseValue: Variable) -> Variable {
            let lhsType = b.type(of: trueValue)
            return b.emit(WasmSelect(), withInputs: [trueValue, falseValue, condition], types: [lhsType, lhsType, .wasmi32]).output
        }

        public func wasmReturn(_ values: [Variable]) {
            b.emit(WasmReturn(returnTypes: values.map(b.type)), withInputs: values, types: signature.outputTypes)
        }

        public func wasmReturn(_ returnVariable: Variable) {
            let returnType = b.type(of: returnVariable)
            b.emit(WasmReturn(returnTypes: [returnType]), withInputs: [returnVariable], types: signature.outputTypes)
        }

        public func wasmReturn() {
            assert(signature.outputTypes.isEmpty)
            b.emit(WasmReturn(returnTypes: []), withInputs: [])
        }

        @discardableResult
        public func constSimd128(value: [UInt8]) -> Variable {
            return b.emit(ConstSimd128(value: value)).output
        }

        @discardableResult
        public func wasmSimd128IntegerUnOp(_ input: Variable, _ shape: WasmSimd128Shape, _ integerUnOpKind: WasmSimd128IntegerUnOpKind) -> Variable {
            return b.emit(WasmSimd128IntegerUnOp(shape: shape, unOpKind: integerUnOpKind), withInputs: [input], types: [.wasmSimd128]).output
        }

        @discardableResult
        public func wasmSimd128IntegerBinOp(_ left: Variable, _ right: Variable, _ shape: WasmSimd128Shape, _ integerBinOpKind: WasmSimd128IntegerBinOpKind) -> Variable {
            // Shifts take an i32 as an rhs input, the others take a regular .wasmSimd128 input.
            let rhsInputType: ILType = switch integerBinOpKind {
            case .shl, .shr_s, .shr_u:
                .wasmi32
            default:
                .wasmSimd128
            }
            return b.emit(WasmSimd128IntegerBinOp(shape: shape, binOpKind: integerBinOpKind), withInputs: [left, right], types: [.wasmSimd128, rhsInputType]).output
        }

        @discardableResult
        public func wasmSimd128IntegerTernaryOp(_ left: Variable, _ mid: Variable, _ right: Variable, _ shape: WasmSimd128Shape, _ integerTernaryOpKind: WasmSimd128IntegerTernaryOpKind) -> Variable {
            return b.emit(WasmSimd128IntegerTernaryOp(shape: shape, ternaryOpKind: integerTernaryOpKind), withInputs: [left, mid, right], types: [.wasmSimd128, .wasmSimd128, .wasmSimd128]).output
        }

        @discardableResult
        public func wasmSimd128FloatUnOp(_ input: Variable, _ shape: WasmSimd128Shape, _ floatUnOpKind: WasmSimd128FloatUnOpKind) -> Variable {
            return b.emit(WasmSimd128FloatUnOp(shape: shape, unOpKind: floatUnOpKind), withInputs: [input], types: [.wasmSimd128]).output
        }

        @discardableResult
        public func wasmSimd128FloatBinOp(_ left: Variable, _ right: Variable, _ shape: WasmSimd128Shape, _ floatBinOpKind: WasmSimd128FloatBinOpKind) -> Variable {
            return b.emit(WasmSimd128FloatBinOp(shape: shape, binOpKind: floatBinOpKind), withInputs: [left, right], types: [.wasmSimd128, .wasmSimd128]).output
        }

        @discardableResult
        public func wasmSimd128FloatTernaryOp(_ left: Variable, _ mid: Variable, _ right: Variable, _ shape: WasmSimd128Shape, _ floatTernaryOpKind: WasmSimd128FloatTernaryOpKind) -> Variable {
            return b.emit(WasmSimd128FloatTernaryOp(shape: shape, ternaryOpKind: floatTernaryOpKind), withInputs: [left, mid, right], types: [.wasmSimd128, .wasmSimd128, .wasmSimd128]).output
        }

        @discardableResult
        public func wasmSimd128Compare(_ lhs: Variable, _ rhs: Variable, _ shape: WasmSimd128Shape, _ compareOpKind: WasmSimd128CompareOpKind) -> Variable {
            return b.emit(WasmSimd128Compare(shape: shape, compareOpKind: compareOpKind), withInputs: [lhs, rhs], types: [.wasmSimd128, .wasmSimd128]).output
        }

        @discardableResult
        func wasmSimdSplat(kind: WasmSimdSplat.Kind, _ input: Variable) -> Variable {
            return b.emit(WasmSimdSplat(kind), withInputs: [input], types: [kind.laneType()]).output
        }

        @discardableResult
        func wasmSimdExtractLane(kind: WasmSimdExtractLane.Kind, _ input: Variable, _ lane: Int) -> Variable {
            return b.emit(WasmSimdExtractLane(kind: kind, lane: lane), withInputs: [input], types: [.wasmSimd128]).output
        }

        @discardableResult
        func wasmSimdReplaceLane(kind: WasmSimdReplaceLane.Kind, _ input: Variable, _ laneValue: Variable, _ lane: Int) -> Variable {
            return b.emit(WasmSimdReplaceLane(kind: kind, lane: lane),
                withInputs: [input, laneValue], types: [.wasmSimd128, kind.laneType()]).output
        }

        func wasmSimdStoreLane(kind: WasmSimdStoreLane.Kind, memory: Variable, dynamicOffset: Variable, staticOffset: Int64, from: Variable, lane: Int) {
            let isMemory64 = b.type(of: memory).wasmMemoryType!.isMemory64
            let dynamicOffsetType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
            b.emit(WasmSimdStoreLane(kind: kind, staticOffset: staticOffset, lane: lane),
                withInputs: [memory, dynamicOffset, from],
                types: [.object(ofGroup: "WasmMemory"), dynamicOffsetType, .wasmSimd128])
        }

        @discardableResult
        func wasmSimdLoadLane(kind: WasmSimdLoadLane.Kind, memory: Variable, dynamicOffset: Variable, staticOffset: Int64, into: Variable, lane: Int) -> Variable {
            let isMemory64 = b.type(of: memory).wasmMemoryType!.isMemory64
            let dynamicOffsetType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
            return b.emit(WasmSimdLoadLane(kind: kind, staticOffset: staticOffset, lane: lane),
                withInputs: [memory, dynamicOffset, into],
                types: [.object(ofGroup: "WasmMemory"), dynamicOffsetType, .wasmSimd128]).output
        }

        @discardableResult
        func wasmSimdLoad(kind: WasmSimdLoad.Kind, memory: Variable, dynamicOffset: Variable, staticOffset: Int64) -> Variable {
            let isMemory64 = b.type(of: memory).wasmMemoryType!.isMemory64
            let dynamicOffsetType = isMemory64 ? ILType.wasmi64 : ILType.wasmi32
            return b.emit(WasmSimdLoad(kind: kind, staticOffset: staticOffset),
                withInputs: [memory, dynamicOffset],
                types: [.object(ofGroup: "WasmMemory"), dynamicOffsetType]).output
        }

        @discardableResult
        public func wasmArrayNewFixed(arrayType: Variable, elements: [Variable]) -> Variable {
            let arrayDesc = b.jsTyper.getTypeDescription(of: arrayType) as! WasmArrayTypeDescription
            assert(elements.allSatisfy {b.jsTyper.type(of: $0).Is(arrayDesc.elementType.unpacked())})
            return b.emit(WasmArrayNewFixed(size: elements.count), withInputs: [arrayType] + elements).output
        }

        @discardableResult
        public func wasmArrayNewDefault(arrayType: Variable, size: Variable) -> Variable {
            return b.emit(WasmArrayNewDefault(), withInputs: [arrayType, size]).output
        }

        @discardableResult
        public func wasmArrayLen(_ array: Variable) -> Variable {
            return b.emit(WasmArrayLen(), withInputs: [array]).output
        }

        @discardableResult
        public func wasmArrayGet(array: Variable, index: Variable, isSigned: Bool = false) -> Variable {
            return b.emit(WasmArrayGet(isSigned: isSigned), withInputs: [array, index],
                          types: [.wasmGenericRef, .wasmi32]).output
        }

        public func wasmArraySet(array: Variable, index: Variable, element: Variable) {
            let arrayDesc = b.jsTyper.getTypeDescription(of: array) as! WasmArrayTypeDescription
            assert(arrayDesc.mutability)
            b.emit(WasmArraySet(), withInputs: [array, index, element],
                   types: [.wasmGenericRef, .wasmi32, arrayDesc.elementType.unpacked()])
        }

        @discardableResult
        public func wasmStructNewDefault(structType: Variable) -> Variable {
            return b.emit(WasmStructNewDefault(), withInputs: [structType]).output
        }

        @discardableResult
        public func wasmStructGet(theStruct: Variable, fieldIndex: Int, isSigned: Bool = false) -> Variable {
            return b.emit(WasmStructGet(fieldIndex: fieldIndex, isSigned: isSigned), withInputs: [theStruct]).output
        }

        public func wasmStructSet(theStruct: Variable, fieldIndex: Int, value: Variable) {
            let structDesc = b.jsTyper.getTypeDescription(of: theStruct) as! WasmStructTypeDescription
            assert(structDesc.fields[fieldIndex].mutability)
            b.emit(WasmStructSet(fieldIndex: fieldIndex), withInputs: [theStruct, value])
        }

        @discardableResult
        public func wasmRefNull(type: ILType) -> Variable {
            assert(type.isWasmReferenceType)
            assert(type.wasmReferenceType!.isAbstract(), "index types must use .wasmRefNull(Variable)")
            return b.emit(WasmRefNull(type: type)).output
        }

        @discardableResult
        public func wasmRefNull(typeDef: Variable) -> Variable {
            return b.emit(WasmRefNull(type: nil), withInputs: [typeDef]).output
        }

        @discardableResult
        public func wasmRefIsNull(_ ref: Variable) -> Variable {
            return b.emit(WasmRefIsNull(), withInputs: [ref], types: [.wasmGenericRef]).output
        }

        @discardableResult
        public func wasmRefI31(_ number: Variable) -> Variable {
            return b.emit(WasmRefI31(), withInputs: [number], types: [.wasmi32]).output
        }

        @discardableResult
        public func wasmI31Get(_ refI31: Variable, isSigned: Bool) -> Variable {
            return b.emit(WasmI31Get(isSigned: isSigned), withInputs: [refI31], types: [.wasmI31Ref]).output
        }

        @discardableResult
        public func wasmAnyConvertExtern(_ ref: Variable) -> Variable {
            b.emit(WasmAnyConvertExtern(), withInputs: [ref], types: [.wasmExternRef]).output
        }

        @discardableResult
        public func wasmExternConvertAny(_ ref: Variable) -> Variable {
            b.emit(WasmExternConvertAny(), withInputs: [ref], types: [.wasmAnyRef]).output
        }
    }

    public class WasmModule {
        private let b: ProgramBuilder
        public var methods: [String]
        public var functions: [WasmFunction]
        // This is the stack of current active block signatures.
        public var blockSignatures: Stack<WasmSignature>
        public var currentWasmFunction: WasmFunction {
            return functions.last!
        }

        private var moduleVariable: Variable?

        public func getExportedMethod(at index: Int) -> String {
            return methods[index]
        }

        public func getExportedMethods() -> [(String, Signature)] {
            assert(methods.count == functions.count)
            return (0..<methods.count).map { (methods[$0], functions[$0].jsSignature) }
        }

        public func setModuleVariable(variable: Variable) {
            guard moduleVariable == nil else {
                fatalError("Cannot re-set the WasmModule variable!")
            }
            moduleVariable = variable
        }

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.wasm))
            self.b = b
            self.methods = [String]()
            self.moduleVariable = nil
            self.functions = []
            self.blockSignatures = Stack()
        }

        @discardableResult
        public func loadExports() -> Variable {
            let exports = self.b.getProperty("exports", of: self.getModuleVariable())
            return exports
        }

        // TODO: distinguish between exported and non-exported functions
        @discardableResult
        public func addWasmFunction(with signature: WasmSignature, _ body: (WasmFunction, Variable, [Variable]) -> [Variable]) -> Variable {
            let instr = b.emit(BeginWasmFunction(signature: signature))
            let results = body(currentWasmFunction, instr.innerOutput(0), Array(instr.innerOutputs(1...)))
            return b.emit(EndWasmFunction(signature: signature), withInputs: results).output
        }

        @discardableResult
        public func addGlobal(wasmGlobal: WasmGlobal, isMutable: Bool) -> Variable {
            return b.emit(WasmDefineGlobal(wasmGlobal: wasmGlobal, isMutable: isMutable)).output
        }

        @discardableResult
        public func addTable(elementType: ILType, minSize: Int, maxSize: Int? = nil, definedEntries: [WasmTableType.IndexInTableAndWasmSignature] = [], definedEntryValues: [Variable] = [], isTable64: Bool) -> Variable {
            let inputTypes = Array(repeating: getEntryTypeForTable(elementType: elementType), count: definedEntries.count)
            return b.emit(WasmDefineTable(elementType: elementType, limits: Limits(min: minSize, max: maxSize), definedEntries: definedEntries, isTable64: isTable64),
                withInputs: definedEntryValues, types: inputTypes).output
        }

        @discardableResult
        public func addElementSegment(elements: [Variable]) -> Variable {
            let inputTypes = Array(repeating: getEntryTypeForTable(elementType: ILType.wasmFuncRef), count: elements.count)
            return b.emit(WasmDefineElementSegment(size: UInt32(elements.count)), withInputs: elements, types: inputTypes).output
        }

        public func getEntryTypeForTable(elementType: ILType) -> ILType {
            switch elementType {
                case .wasmFuncRef:
                    return .wasmFunctionDef() | .function()
                default:
                    return .object()
            }
        }


        // This result can be ignored right now, as we can only define one memory per module
        // Also this should be tracked like a global / table.
        @discardableResult
        public func addMemory(minPages: Int, maxPages: Int? = nil, isShared: Bool = false, isMemory64: Bool = false) -> Variable {
            return b.emit(WasmDefineMemory(limits: Limits(min: minPages, max: maxPages), isShared: isShared, isMemory64: isMemory64)).output
        }

        @discardableResult
        public func addDataSegment(segment: [UInt8]) -> Variable {
            return b.emit(WasmDefineDataSegment(segment: segment)).output
        }

        @discardableResult
        public func addTag(parameterTypes: [ILType]) -> Variable {
            return b.emit(WasmDefineTag(parameterTypes: parameterTypes)).output
        }

        private func getModuleVariable() -> Variable {
            guard moduleVariable != nil else {
                fatalError("WasmModule variable was not set yet!")
            }
            return moduleVariable!
        }
    }

    func hasZeroPages(memory: Variable) -> Bool {
        let memoryTypeInfo = self.type(of: memory).wasmMemoryType!
        return memoryTypeInfo.limits.min == 0
    }

    // Returns 'dynamicOffset' and 'staticOffset' such that:
    // 0 <= dynamicOffset + staticOffset <= memSize
    //
    // Note: In rare cases, the returned values may lead to an out-of-bounds memory access.
    func generateMemoryIndexes(forMemory memory: Variable) -> (Variable, Int64) {
        return generateAlignedMemoryIndexes(forMemory: memory, alignment: 1)
    }

    // Returns 'dynamicOffset' and 'alignedStaticOffset' such that:
    // 0 <= dynamicOffset + alignedStaticOffset <= memSize
    // (dynamicOffset + alignedStaticOffset) % alignment == 0
    //
    // Note: In rare cases, the returned values may lead to an out-of-bounds memory access.
    func generateAlignedMemoryIndexes(forMemory memory: Variable, alignment: Int64) -> (address: Variable, offset: Int64) {
        assert(alignment > 0, "Alignment must be positive")
        let memoryTypeInfo = self.type(of: memory).wasmMemoryType!
        let memSize = Int64(memoryTypeInfo.limits.min * WasmConstants.specWasmMemPageSize)
        let function = self.currentWasmModule.currentWasmFunction
        if memSize < alignment {
            // We can't generate in-bounds accesses here, so simply return address 0.
            return (function.memoryArgument(0, memoryTypeInfo), 0)
        }

        // Generate an in-bounds offset (dynamicOffset + alignedStaticOffset) into the memory.
        // The '+1' allows out-of-bounds access (dynamicOffset + alignedStaticOffset == memSize)
        let dynamicOffsetValue = self.randomNonNegativeIndex(upTo: memSize - alignment + 1)
        let dynamicOffset = function.memoryArgument(dynamicOffsetValue, memoryTypeInfo)
        let staticOffset = self.randomNonNegativeIndex(upTo: memSize - alignment + 1 - dynamicOffsetValue)

        let currentAddress = dynamicOffsetValue + staticOffset
        // Calculate the minimal value needed to make the total address aligned.
        let adjustment = (alignment - (currentAddress % alignment)) % alignment
        let alignedStaticOffset = staticOffset + adjustment
        return (dynamicOffset, alignedStaticOffset)
    }

    /// Produces a WasmGlobal that is valid to create in the given Context.
    public func randomWasmGlobal(forContext context: Context) -> WasmGlobal {
        switch context {
        case .javascript:
            // These are valid in JS according to: https://webassembly.github.io/spec/js-api/#globals.
            // TODO: add simd128 and anyfunc.
            return withEqualProbability(
                {.wasmf32(Float32(self.randomFloat()))},
                {.wasmf64(self.randomFloat())},
                {.wasmi32(Int32(truncatingIfNeeded: self.randomInt()))},
                {.wasmi64(self.randomInt())},
                {.externref})
        case .wasm:
            // TODO: Add simd128 and nullrefs.
            return withEqualProbability(
                {.wasmf32(Float32(self.randomFloat()))},
                {.wasmf64(self.randomFloat())},
                {.wasmi32(Int32(truncatingIfNeeded: self.randomInt()))},
                {.wasmi64(self.randomInt())},
                {.externref},
                {.exnref},
                {.i31ref})
        default:
            fatalError("Unsupported context \(context) for a WasmGlobal.")
        }
    }

    public func randomTagParameters() -> [ILType] {
        // TODO(mliedtke): The list of types should be shared with function signature generation
        // etc. We should also support non-nullable references but that requires being able
        // to generate valid ones which currently isn't the case for most of them.
        return (0..<Int.random(in: 0...10)).map {_ in chooseUniform(from: [
            // Value types:
            .wasmi32, .wasmi64, .wasmf32, .wasmf64, .wasmSimd128,
            // Subset of abstract heap types (the null (bottom) types are not allowed in the JS API):
            .wasmExternRef, .wasmFuncRef, .wasmAnyRef, .wasmEqRef, .wasmI31Ref, .wasmStructRef,
            .wasmArrayRef, .wasmExnRef
        ])}
    }

    public func randomWasmSignature() -> WasmSignature {
        // TODO: generalize this to support more types. Also add support for simd128 and
        // (null)exnref, note however that these types raise exceptions when used from JS.
        let valueTypes: [ILType] = [.wasmi32, .wasmi64, .wasmf32, .wasmf64]
        let abstractRefTypes: [ILType] = [.wasmExternRef, .wasmAnyRef, .wasmI31Ref]
        let nullTypes: [ILType] = [.wasmNullRef, .wasmNullExternRef, .wasmNullFuncRef]
        let randomType = {
            chooseUniform(
                from: chooseBiased(from: [nullTypes, abstractRefTypes, valueTypes], factor: 1.5))
        }
        let returnTypes: [ILType] = (0..<Int.random(in: 0...3)).map {_ in randomType()}
        let params: [ILType] = (0..<Int.random(in: 0...10)).map {_ in randomType()}
        return params => returnTypes
    }

    public func randomWasmBlockOutputTypes(upTo n: Int) -> [ILType] {
        // TODO(mliedtke): This should allow more types as well as non-nullable references for all
        // abstract heap types. To be able to emit them, generateRandomWasmVar() needs to be able
        // to generate a sequence that produces such a non-nullable value which might be difficult
        // for some types as of now.
        (0..<Int.random(in: 0...n)).map {_ in chooseUniform(from:
            [.wasmi32, .wasmi64, .wasmf32, .wasmf64, .wasmSimd128, .wasmRefI31]
                + WasmAbstractHeapType.allCases.map {.wasmRef(.Abstract($0), nullability: true)})}
    }

    public func randomWasmBlockArguments(upTo n: Int) -> [Variable] {
        (0..<Int.random(in: 0...n)).map {_ in findVariable {
            // TODO(mliedtke): Also support wasm-gc types in wasm blocks.
            // This requires updating the inner output types based on the input types.
            type(of: $0).Is(.wasmPrimitive) && !type(of: $0).Is(.wasmGenericRef)
        }}.filter {$0 != nil}.map {$0!}
    }

    public func randomWasmBranchHint() -> WasmBranchHint {
        probability(0.8) ? .None : Bool.random() ? .Likely : .Unlikely
    }

    public func randomSimd128CompareOpKind(_ shape: WasmSimd128Shape) -> WasmSimd128CompareOpKind {
        if shape.isFloat() {
            return .fKind(value: chooseUniform(from: WasmFloatCompareOpKind.allCases))
        } else {
            if shape == .i64x2 {
                // i64x2 does not provide unsigned comparison.
                return .iKind(value:
                    chooseUniform(from: WasmIntegerCompareOpKind.allCases.filter{
                        return $0 != .Lt_u && $0 != .Le_u && $0 != .Gt_u && $0 != .Ge_u
                    }))
            } else {
                return .iKind(value: chooseUniform(from: WasmIntegerCompareOpKind.allCases))
            }
        }
    }

    @discardableResult
    public func buildWasmModule(_ body: (WasmModule) -> ()) -> WasmModule {
        emit(BeginWasmModule())
        let module = self.currentWasmModule
        body(module)
        emit(EndWasmModule())

        return module
    }

    @discardableResult
    public func wasmDefineTypeGroup(typeGenerator: () -> [Variable]) -> [Variable] {
        emit(WasmBeginTypeGroup())
        let types = typeGenerator()
        return Array(emit(WasmEndTypeGroup(typesCount: types.count), withInputs: types).outputs)
    }

    @discardableResult
    public func wasmDefineTypeGroup(recursiveGenerator: () -> ()) -> [Variable] {
        emit(WasmBeginTypeGroup())
        recursiveGenerator()
        // Make all type definitions visible.
        let types = scopes.top.filter {
            let t = type(of: $0)
            return t.Is(.wasmTypeDef()) && t.wasmTypeDefinition?.description != .selfReference
        }
        return Array(emit(WasmEndTypeGroup(typesCount: types.count), withInputs: types).outputs)
    }

    @discardableResult
    func wasmDefineSignatureType(signature: WasmSignature, indexTypes: [Variable]) -> Variable {
        return emit(WasmDefineSignatureType(signature: signature), withInputs: indexTypes).output
    }

    @discardableResult
    func wasmDefineArrayType(elementType: ILType, mutability: Bool, indexType: Variable? = nil) -> Variable {
        let inputs = indexType != nil ? [indexType!] : []
        return emit(WasmDefineArrayType(elementType: elementType, mutability: mutability), withInputs: inputs).output
    }

    @discardableResult
    func wasmDefineStructType(fields: [WasmStructTypeDescription.Field], indexTypes: [Variable]) -> Variable {
        return emit(WasmDefineStructType(fields: fields), withInputs: indexTypes).output
    }

    @discardableResult
    func wasmDefineForwardOrSelfReference() -> Variable {
        return emit(WasmDefineForwardOrSelfReference()).output
    }

    func wasmResolveForwardReference(_ forwardReference: Variable, to: Variable) {
        assert(type(of: forwardReference).wasmTypeDefinition?.description == .selfReference)
        emit(WasmResolveForwardReference(), withInputs: [forwardReference, to])
    }
    // Converts an array to a string separating elements by comma. This is used for testing only.
    func arrayToStringForTesting(_ array: Variable) -> Variable {
        let stringified = callMethod("map", on: array,
                withArgs: [buildArrowFunction(with: .parameters(n: 1)) { args in
            doReturn(callMethod("toString", on: args[0]))
        }])
        return callMethod("join", on: stringified, withArgs: [loadString(",")])
    }

    func wasmDefineAndResolveForwardReference(recursiveGenerator: () -> ()) {
        let previousTypes = Set(scopes.elementsStartingAtTop().joined().filter {type(of: $0).Is(.wasmTypeDef())})
        let ref = wasmDefineForwardOrSelfReference()
        recursiveGenerator()
        let newTypes = scopes.elementsStartingAtTop().joined().filter {
            let t = type(of: $0)
            return !previousTypes.contains($0) && t.Is(.wasmTypeDef()) && t.wasmTypeDefinition?.description != .selfReference
        }
        if !newTypes.isEmpty {
            wasmResolveForwardReference(ref, to: chooseUniform(from: newTypes))
        }
    }

    /// Returns the next free variable.
    func nextVariable() -> Variable {
        assert(numVariables < Code.maxNumberOfVariables, "Too many variables")
        numVariables += 1
        return Variable(number: numVariables - 1)
    }

    @discardableResult
    private func internalAppend(_ instr: Instruction) -> Instruction {
        // Basic integrity checking
        assert(!instr.inouts.contains(where: { $0.number >= numVariables }))
        assert(instr.op.requiredContext.isSubset(of: contextAnalyzer.context))

        // The returned instruction will also contain its index in the program. Use that so the analyzers have access to the index.
        let instr = code.append(instr)
        analyze(instr)

        return instr
    }

    /// Set the parameter types for the next function, method, or constructor, which must be the the start of a function or method definition.
    /// Parameter types (and signatures in general) are only valid for the duration of the program generation, as they cannot be preserved across mutations.
    /// As such, the parameter types are linked to their instruction through the index of the instruction in the program.
    public func setParameterTypesForNextSubroutine(_ parameterTypes: ParameterList) {
        jsTyper.setParameters(forSubroutineStartingAt: code.count, to: parameterTypes)
    }

    /// Analyze the given instruction. Should be called directly after appending the instruction to the code.
    private func analyze(_ instr: Instruction) {
        assert(code.lastInstruction.op === instr.op)
        updateVariableAnalysis(instr)
        contextAnalyzer.analyze(instr)
        updateBuilderState(instr)
        jsTyper.analyze(instr)
    }

    private func updateVariableAnalysis(_ instr: Instruction) {
        // Scope management (1).
        if instr.isBlockEnd {
            assert(scopes.count > 0, "Trying to close a scope that was never opened")
            let current = scopes.pop()
            // Hidden variables that go out of scope need to be unhidden.
            for v in current where hiddenVariables.contains(v) {
                unhide(v)
            }
            variablesInScope.removeLast(current.count)
        }

        scopes.top.append(contentsOf: instr.outputs)
        variablesInScope.append(contentsOf: instr.outputs)

        // Scope management (2). Happens here since e.g. function definitions create a variable in the outer scope.
        if instr.isBlockStart {
            scopes.push([])
        }

        scopes.top.append(contentsOf: instr.innerOutputs)
        variablesInScope.append(contentsOf: instr.innerOutputs)
    }

    private func updateBuilderState(_ instr: Instruction) {
        switch instr.op.opcode {
        case .beginObjectLiteral:
            activeObjectLiterals.push(ObjectLiteral(in: self))
        case .objectLiteralAddProperty(let op):
            currentObjectLiteral.properties.append(op.propertyName)
        case .objectLiteralAddElement(let op):
            currentObjectLiteral.elements.append(op.index)
        case .objectLiteralAddComputedProperty:
            currentObjectLiteral.computedProperties.append(instr.input(0))
        case .objectLiteralCopyProperties:
            // Cannot generally determine what fields this installs.
            break
        case .objectLiteralSetPrototype:
            currentObjectLiteral.hasPrototype = true
        case .beginObjectLiteralMethod(let op):
            currentObjectLiteral.methods.append(op.methodName)
        case .beginObjectLiteralComputedMethod:
            currentObjectLiteral.computedMethods.append(instr.input(0))
        case .beginObjectLiteralGetter(let op):
            currentObjectLiteral.getters.append(op.propertyName)
        case .beginObjectLiteralSetter(let op):
            currentObjectLiteral.setters.append(op.propertyName)
        case .endObjectLiteralMethod,
                .endObjectLiteralComputedMethod,
                .endObjectLiteralGetter,
                .endObjectLiteralSetter:
            break
        case .endObjectLiteral:
            activeObjectLiterals.pop()

        case .beginClassDefinition(let op):
            activeClassDefinitions.push(ClassDefinition(in: self, isDerived: op.hasSuperclass))
        case .beginClassConstructor:
            activeClassDefinitions.top.hasConstructor = true
        case .classAddInstanceProperty(let op):
            activeClassDefinitions.top.instanceProperties.append(op.propertyName)
        case .classAddInstanceElement(let op):
            activeClassDefinitions.top.instanceElements.append(op.index)
        case .classAddInstanceComputedProperty:
            activeClassDefinitions.top.instanceComputedProperties.append(instr.input(0))
        case .beginClassInstanceMethod(let op):
            activeClassDefinitions.top.instanceMethods.append(op.methodName)
        case .beginClassInstanceComputedMethod:
            activeClassDefinitions.top.instanceComputedMethods.append(instr.input(0))
        case .beginClassInstanceGetter(let op):
            activeClassDefinitions.top.instanceGetters.append(op.propertyName)
        case .beginClassInstanceSetter(let op):
            activeClassDefinitions.top.instanceSetters.append(op.propertyName)
        case .classAddStaticProperty(let op):
            activeClassDefinitions.top.staticProperties.append(op.propertyName)
        case .classAddStaticElement(let op):
            activeClassDefinitions.top.staticElements.append(op.index)
        case .classAddStaticComputedProperty:
            activeClassDefinitions.top.staticComputedProperties.append(instr.input(0))
        case .beginClassStaticMethod(let op):
            activeClassDefinitions.top.staticMethods.append(op.methodName)
        case .beginClassStaticComputedMethod:
            activeClassDefinitions.top.staticComputedMethods.append(instr.input(0))
        case .beginClassStaticGetter(let op):
            activeClassDefinitions.top.staticGetters.append(op.propertyName)
        case .beginClassStaticSetter(let op):
            activeClassDefinitions.top.staticSetters.append(op.propertyName)
        case .classAddPrivateInstanceProperty(let op):
            activeClassDefinitions.top.privateProperties.append(op.propertyName)
        case .beginClassPrivateInstanceMethod(let op):
            activeClassDefinitions.top.privateMethods.append(op.methodName)
        case .classAddPrivateStaticProperty(let op):
            activeClassDefinitions.top.privateProperties.append(op.propertyName)
        case .beginClassPrivateStaticMethod(let op):
            activeClassDefinitions.top.privateMethods.append(op.methodName)
        case .beginClassStaticInitializer:
            break
        case .endClassDefinition:
            activeClassDefinitions.pop()

        case .beginSwitch:
            activeSwitchBlocks.push(SwitchBlock(in: self))
        case .beginSwitchDefaultCase:
            activeSwitchBlocks.top.hasDefaultCase = true
        case .beginSwitchCase:
            break
        case .endSwitch:
            activeSwitchBlocks.pop()
        case .createWasmGlobal(_):
            break
        case .reassign(_):
            break
        // Wasm cases
        case .beginWasmModule:
            activeWasmModule = WasmModule(in: self)
        case .endWasmModule:
            activeWasmModule!.setModuleVariable(variable: instr.output)
            activeWasmModule = nil
        case .endWasmFunction:
            activeWasmModule!.methods.append("w\(activeWasmModule!.methods.count)")
        case .wasmDefineGlobal(_),
             .wasmDefineTable(_),
             .wasmDefineMemory(_),
             .wasmDefineDataSegment(_),
             .wasmDefineElementSegment(_):
            break
        case .wasmDefineTag(_):
            break
        case .beginWasmFunction(let op):
            activeWasmModule!.functions.append(WasmFunction(forBuilder: self, withSignature: op.signature))
        case .wasmBeginIf(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmBeginBlock(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmBeginLoop(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmBeginTry(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmBeginTryDelegate(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmBeginTryTable(let op):
            activeWasmModule!.blockSignatures.push(op.signature)
        case .wasmEndIf(_),
             .wasmEndLoop(_),
             .wasmEndTry(_),
             .wasmEndTryDelegate(_),
             .wasmEndTryTable(_),
             .wasmEndBlock(_):
            activeWasmModule!.blockSignatures.pop()
        case .beginPlainFunction(_),
             .beginArrowFunction(_),
             .beginAsyncArrowFunction(_),
             .beginAsyncFunction(_),
             .beginAsyncGeneratorFunction(_),
             .beginCodeString(_),
             .beginGeneratorFunction(_):
            assert(instr.numOutputs == 1)
            lastFunctionVariables.push(instr.output)
        case .endPlainFunction(_),
             .endArrowFunction(_),
             .endAsyncArrowFunction(_),
             .endAsyncFunction(_),
             .endAsyncGeneratorFunction(_),
             .endCodeString(_),
             .endGeneratorFunction(_):
            lastFunctionVariables.pop()

        default:
            assert(!instr.op.requiredContext.contains(.objectLiteral))
            assert(!instr.op.requiredContext.contains(.classDefinition))
            assert(!instr.op.requiredContext.contains(.switchBlock))
            assert(!instr.op.requiredContext.contains(.wasm))
            break
        }
    }

    // Some APIs accept ObjectGroups that are not produced by other APIs,
    // so we instead register a generator that allows the fuzzer a greater chance of generating
    // one when needed.
    //
    // These can be registered on the JavaScriptEnvironment with addProducingGenerator()
    @discardableResult
    func createOptionsBag(_ bag: OptionsBag) -> Variable {
        // We run .filter() to pick a subset of fields, but we generally want to set as many as possible
        // and let the mutator prune things
        let dict: [String : Variable] = bag.properties.filter {_ in probability(0.8)}.mapValues {
            if $0.isEnumeration {
                return loadEnum($0)
            // relativeTo doesn't have an ObjectGroup so we cannot just register a producingGenerator for it
            } else if $0.Is(OptionsBag.jsTemporalRelativeTo) {
                return findOrGenerateType(chooseUniform(from: [.jsTemporalZonedDateTime, .jsTemporalPlainDateTime,
                                          .jsTemporalPlainDate, .string]))
            } else {
                return findOrGenerateType($0)
            }
        }
        return createObject(with: dict)
    }

    // Generate a Temporal.Duration object
    @discardableResult
    func createTemporalDurationFieldsObject() -> Variable {
        var properties: [String : Variable] = [:]
        // Durations are simple, they accept an object with optional integer fields for each duration field.
        for field in ["years", "months", "weeks", "days", "hours", "minutes", "seconds", "milliseconds", "microseconds", "nanoseconds"] {
            if Bool.random() {
                properties[field] = randomVariable(forUseAs: .number)
            }
        }
        return createObject(with: properties)
    }

    // Generate a random time zone identifier
    @discardableResult
    func randomTimeZone() -> Variable {
        return loadString(ProgramBuilder.randomTimeZoneString(), customName: "TemporalTimeZoneString")
    }

    @discardableResult
    static func randomTimeZoneString() -> String {
        // Bias towards knownTimeZoneIdentifiers since it's a larger array
        if probability(0.7) {
            return chooseUniform(from: TimeZone.knownTimeZoneIdentifiers)
        } else {
            return chooseUniform(from: TimeZone.abbreviationDictionary.keys)
        }
    }

    @discardableResult
    func randomUTCOffset(mayHaveSeconds: Bool) -> Variable {
        return loadString(ProgramBuilder.randomUTCOffsetString(mayHaveSeconds: mayHaveSeconds), customName: "TemporalTimeZoneString")
    }

    @discardableResult
    static func randomUTCOffsetString(mayHaveSeconds: Bool) -> String {
        let hours = Int.random(in: 0..<24)
        // Bias towards zero minutes since that's what most time zones do.
        let zeroMinutes = probability(0.8)
        let minutes = zeroMinutes ? 0 : Int.random(in: 0..<60)
        let plusminus = Bool.random() ? "+" : "-";
        var offset = String(format: "%@%02d:%02d", plusminus, hours, minutes)
        if !zeroMinutes && mayHaveSeconds && probability(0.3) {
            let seconds = Int.random(in: 0..<60)
            offset = String(format: "%@:%02d", offset, seconds)
            if  probability(0.3) {
                offset = String(format: "%@:.%09d", offset, Int.random(in: 0...999999999))
            }
        }
        return offset
    }

    // Generate an object with fields from
    // https://tc39.es/proposal-temporal/#table-temporal-calendar-fields-record-fields
    //
    // with() will error when given a calendar; so we allow control over omitting
    // a `calendar` field.
    @discardableResult
    func createTemporalFieldsObject(forWith: Bool, dateFields: Bool, timeFields: Bool, zonedFields: Bool) -> Variable {
        var properties: [String : Variable] = [:]

        if dateFields {
            var chosenCalendar: String? = nil

            // The "calendar" field is forbidden for `with`
            // and will produce an early error
            if !forWith && Bool.random() {
                // TODO(Manishearth) share code with PlainDate once https://chrome-internal-review.googlesource.com/c/v8/fuzzilli/+/8534116/
                // lands
                chosenCalendar = chooseUniform(from: [
                    "buddhist", "chinese", "coptic", "dangi", "ethioaa", "ethiopic",
                    "ethiopic-amete-alem", "gregory", "hebrew", "indian", "islamic-civil",
                    "islamic-tbla", "islamic-umalqura", "islamicc", "iso8601", "japanese",
                    "persian", "roc"])
                properties["calendar"] = loadString(chosenCalendar!)
            }

            if probability(0.8) {
                properties["year"] = randomVariable(forUseAs: .integer)
            }

            // If the "year" is set, reduce the chance of emitting an "eraYear" which in most cases
            // would contradict.
            let eraProbability = properties["year"] == nil ? 0.8 : 0.2;
            if probability(eraProbability) {
                properties["eraYear"] = randomVariable(forUseAs: .integer)
                // https://tc39.es/proposal-intl-era-monthcode/#table-eras
                let gregoryEras = ["ce", "bce", "ad", "bc"]
                let japaneseEras = ["reiwa", "heisei", "showa", "taisho", "meiji"]
                let rocEras = ["roc", "broc", "minguo", "before-roc", "minguo-qian"]
                // If we know the calendar, we should choose from the list of valid eras.
                let eras = switch chosenCalendar {
                    case "buddhist":
                        ["be"]
                    case "coptic":
                        ["am"]
                    case "ethioaa", "ethiopic":
                        ["aa", "am", "mundi", "incar"]
                    case "gregory":
                        gregoryEras
                    case "indian":
                        ["shaka"]
                    case "islamic-civil", "islamicc", "islamic-umalqura", "islamic-tbla":
                        ["ah", "bh"]
                    case "japanese":
                        gregoryEras + japaneseEras
                    case "persian":
                        ["ap"]
                    case "roc":
                        rocEras
                    default:
                        ["be", "am", "aa", "mundi", "incar", "shaka", "ah", "bh", "ap"] + gregoryEras + japaneseEras + rocEras
                }
                properties["era"] = loadString(chooseUniform(from: eras))
            }


            if probability(0.8) {
                // Sometimes generates out of range values to test "constrain"
                // behavior.
                properties["month"] = loadInt(Int64.random(in: 0...14))
            }

            // We don't wish to have clashing month/monthCode
            // *most* of the time, but we still wish to also test those codepaths.
            let monthCodeProbability = properties["month"] == nil ? 0.8 : 0.2;
            if probability(monthCodeProbability) {
                // Month codes go from M00 to M13.
                var code = String(format: "M%02d", Int.random(in: 0...13))
                if probability(0.3) || code == "M00" {
                    // leap months have an L
                    code += "L"
                }
                properties["monthCode"] = loadString(code)
            }

            if probability(0.8) {
                properties["day"] = loadInt(Int64.random(in: 0...35))
            }
        }

        // These are occasionally generated to be out of range to test "constrain"
        // behavior.
        if timeFields {
            if probability(0.8) {
                properties["hour"] = loadInt(Int64.random(in: 0..<26))
            }
            if probability(0.8) {
                properties["minute"] = loadInt(Int64.random(in: 0..<65))
            }
            if probability(0.8) {
                properties["second"] = loadInt(Int64.random(in: 0..<65))
            }
            if probability(0.8) {
                properties["millisecond"] = loadInt(Int64.random(in: 0..<1010))
            }
            if probability(0.8) {
                properties["microsecond"] = loadInt(Int64.random(in: 0..<1010))
            }
            if probability(0.8) {
                properties["nanosecond"] = loadInt(Int64.random(in: 0..<1010))
            }

        }
        // timeZone
        if zonedFields {
            var generatedOffset: Variable? = nil
            // ZonedDateTime must be constructed with a timeZone property.
            // but ZonedDateTime.with will always reject a timeZone.
            //
            // This is because ZonedDateTime.with is about partially replacing
            // calendar fields: and operations like "change the day and also the
            // time zone" are ambiguous based on whether you change the day first
            // or the time zone first (and it's not a *useful* ambiguity).
            // Instead, you are expected to use `.with()` and `.withTimeZone()`
            // in whatever order you need.
            if (!forWith) {
                if Bool.random() {
                    // Time zones can be offsets, but cannot have seconds
                    generatedOffset = randomUTCOffset(mayHaveSeconds: false)
                    properties["timeZone"] = generatedOffset
                } else {
                    properties["timeZone"] = randomTimeZone()
                }
            }

            // Most of the time mixing a random offset and timezone
            // will cause uninteresting errors since they need to match.
            // If our timezone was a UTC offset, then there's not much harm
            // in setting the field (it matches!), but otherwise we should generate offsets
            // with a low probability.
            if generatedOffset != nil && Bool.random() {
                // Half the time when we've generated an offset, set the offset field too, it won't clash.
                properties["offset"] = generatedOffset!
            } else if probability(0.3) {
                // Otherwise, with a low probability, generate a random offset.
                properties["offset"] = randomUTCOffset(mayHaveSeconds: true)
            }
        }
        return createObject(with: properties)
    }

    @discardableResult
    func constructTemporalInstant() -> Variable {
        let temporal = createNamedVariable(forBuiltin: "Temporal")
        let useConstructor = Bool.random()
        let constructor = getProperty("Instant", of: temporal)
        if useConstructor {
            let nanoseconds = randomVariable(forUseAs: .bigint)
            return construct(constructor, withArgs: [nanoseconds])
        } else {
            // TODO(manishearth, 439921647) Generate Temporal-like strings
            let string = randomVariable(forUseAs: .string)
            return callMethod("from", on: constructor, withArgs: [string])
        }
    }

    @discardableResult
    func constructTemporalDuration() -> Variable {
        let temporal = createNamedVariable(forBuiltin: "Temporal")
        let useConstructor = Bool.random()
        let constructor = getProperty("Duration", of: temporal)
        if useConstructor {
            // Constructor takes between 0 and 10 integer args
            let numArgs = Int.random(in: 0...10)
            let args = (0..<numArgs).map { _ in randomVariable(forUseAs: .number) }
            return construct(constructor, withArgs: args)
        } else {
            // Whether to pass a Temporal-like object or a string
            if Bool.random() {
                let fields = createTemporalDurationFieldsObject()
                return callMethod("", on: constructor, withArgs: [ fields ] )
            } else {
                // TODO(manishearth, 439921647) Generate Temporal-like strings
                let string = randomVariable(forUseAs: .string)
                return callMethod("from", on: constructor, withArgs: [string])
             }
         }
    }

    // Generic generators for Temporal date/time types.
    // Pass in a closure that knows how to construct the type with `new()`.
    private func constructTemporalType(type: String,
                            dateFields: Bool, timeFields: Bool, zonedFields: Bool, optionsBag: OptionsBag,
                            generateWithConstructor: (Variable) -> Variable) -> Variable {
        let temporal = createNamedVariable(forBuiltin: "Temporal")
        let useConstructor = Bool.random()
        let constructor = getProperty(type, of: temporal)
        if useConstructor {
            return generateWithConstructor(constructor)
        } else {
            // Whether to pass a Temporal-like object or a string
            if Bool.random() {
                let fields = createTemporalFieldsObject(forWith: false, dateFields: dateFields, timeFields: timeFields, zonedFields: zonedFields)
                var args = [fields]
                if Bool.random() {
                    args.append(createOptionsBag(optionsBag))
                }
                return callMethod("from", on: constructor, withArgs: args )
            } else {
                // TODO(manishearth, 439921647) Generate Temporal-like strings
                let string = randomVariable(forUseAs: .string)
                return callMethod("from", on: constructor, withArgs: [string])
            }
        }
    }

    @discardableResult
    func constructTemporalTime() -> Variable {
        return constructTemporalType(type: "PlainTime", dateFields: false, timeFields: true, zonedFields: false, optionsBag: .jsTemporalOverflowSettings) { constructor in
            // The constructor takes between 0 and 6 integer args.
            let numArgs = Int.random(in: 0...6)
            // Should we be constraining these to valid range?
            let args = (0..<numArgs).map { _ in randomVariable(forUseAs: .number) }
            return construct(constructor, withArgs: args)
        }
    }

    @discardableResult
    func constructTemporalYearMonth() -> Variable {
        return constructTemporalType(type: "PlainYearMonth", dateFields: true, timeFields: false, zonedFields: false, optionsBag: .jsTemporalOverflowSettings) { constructor in
            // The constructor takes 3 int args, an optional calendar, and an optional reference day.
            var args = (0..<3).map {_ in randomVariable(forUseAs: .integer) }
            if Bool.random() {
                args.append(randomVariable(forUseAs: .jsTemporalCalendarEnum))
                if Bool.random() {
                    args.append(randomVariable(forUseAs: .integer))
                }
            }
            return construct(constructor, withArgs: args)
        }
    }
    @discardableResult
    func constructTemporalMonthDay() -> Variable {
        return constructTemporalType(type: "PlainMonthDay", dateFields: true, timeFields: false, zonedFields: false, optionsBag: .jsTemporalOverflowSettings) { constructor in
            // The constructor takes 3 int args, an optional calendar, and an optional reference day.
            var args = (0..<3).map {_ in randomVariable(forUseAs: .integer) }
            if Bool.random() {
                args.append(randomVariable(forUseAs: .jsTemporalCalendarEnum))
                if Bool.random() {
                    args.append(randomVariable(forUseAs: .integer))
                }
            }
            return construct(constructor, withArgs: args)
        }
    }

    @discardableResult
    func constructTemporalDate() -> Variable {
        return constructTemporalType(type: "PlainDate", dateFields: true, timeFields: false, zonedFields: false, optionsBag: .jsTemporalOverflowSettings) { constructor in
            // The constructor takes 3 int args and an optional calendar.
            var args = (0..<3).map {_ in randomVariable(forUseAs: .integer) }
            if Bool.random() {
                args.append(randomVariable(forUseAs: .jsTemporalCalendarEnum))
            }
            return construct(constructor, withArgs: args)
        }
    }
    @discardableResult
    func constructTemporalDateTime() -> Variable {
        return constructTemporalType(type: "PlainDateTime", dateFields: true, timeFields: true, zonedFields: false, optionsBag: .jsTemporalOverflowSettings) { constructor in
            // The constructor takes 3 mandatory integer args and between 0 and 6 additional integer args.
            let timeArgs = Int.random(in: 0...6)
            let totalIntArgs = 3 + timeArgs
            var args = (0..<totalIntArgs).map { _ in randomVariable(forUseAs: .number) }
            if timeArgs == 6 && Bool.random() {
                args.append(randomVariable(forUseAs: .jsTemporalCalendarEnum))
            }
            return construct(constructor, withArgs: args)
        }
    }

    @discardableResult
    func constructTemporalZonedDateTime() -> Variable {
        return constructTemporalType(type: "ZonedDateTime", dateFields: true, timeFields: true, zonedFields: true, optionsBag: .jsTemporalZonedInterpretationSettings) { constructor in
            // The constructor takes one integer arg, one timezone arg, one optional calendar arg.
            // TODO(manishearth, 439921647) Generate timezone strings
            var args = [randomVariable(forUseAs: .bigint), randomVariable(forUseAs: .string)]
            if Bool.random() {
                args.append(randomVariable(forUseAs: .jsTemporalCalendarEnum))
            }
            return construct(constructor, withArgs: args)
        }
    }

    @discardableResult
    static func constructIntlLocaleString() -> String {
        // TODO(Manishearth) Generate more interesting locales than just the builtins
        return chooseUniform(from: Locale.availableIdentifiers)
    }

    // Obtained by calling Intl.supportedValuesOf("unit") in a browser
    fileprivate static let allUnits = ["acre", "bit", "byte", "celsius", "centimeter", "day", "degree", "fahrenheit", "fluid-ounce", "foot", "gallon", "gigabit", "gigabyte", "gram", "hectare", "hour", "inch", "kilobit", "kilobyte", "kilogram", "kilometer", "liter", "megabit", "megabyte", "meter", "microsecond", "mile", "mile-scandinavian", "milliliter", "millimeter", "millisecond", "minute", "month", "nanosecond", "ounce", "percent", "petabyte", "pound", "second", "stone", "terabit", "terabyte", "week", "yard", "year"]

    @discardableResult
    static func constructIntlUnit() -> String {
        let firstUnit = chooseUniform(from: allUnits)
        // Intl is able to format combinations of units too, like hectares-per-gallon
        if probability(0.7) {
            return firstUnit
        } else {
            return "\(firstUnit)-per-\(chooseUniform(from: allUnits))"
        }
    }

    // Generic generators for Intl types.
    private func constructIntlType(type: String, optionsBag: OptionsBag) -> Variable {
        let intl = createNamedVariable(forBuiltin: "Intl")
        let constructor = getProperty(type, of: intl)

        var args: [Variable] = []
        if probability(0.7) {
            args.append(findOrGenerateType(.jsIntlLocaleLike))

            if probability(0.7) {
                args.append(createOptionsBag(optionsBag))
            }
        }
        return construct(constructor, withArgs: args)
    }

    @discardableResult
    func constructIntlDateTimeFormat() -> Variable {
        return constructIntlType(type: "DateTimeFormat", optionsBag: .jsIntlDateTimeFormatSettings)
    }

    @discardableResult
    func constructIntlCollator() -> Variable {
        return constructIntlType(type: "Collator", optionsBag: .jsIntlCollatorSettings)
    }

    @discardableResult
    func constructIntlListFormat() -> Variable {
        return constructIntlType(type: "ListFormat", optionsBag: .jsIntlListFormatSettings)
    }

    @discardableResult
    func constructIntlNumberFormat() -> Variable {
        return constructIntlType(type: "NumberFormat", optionsBag: .jsIntlNumberFormatSettings)
    }

    @discardableResult
    func constructIntlPluralRules() -> Variable {
        return constructIntlType(type: "PluralRules", optionsBag: .jsIntlPluralRulesSettings)
    }

    @discardableResult
    func constructIntlRelativeTimeFormat() -> Variable {
        return constructIntlType(type: "RelativeTimeFormat", optionsBag: .jsIntlRelativeTimeFormatSettings)
    }

    @discardableResult
    func constructIntlSegmenter() -> Variable {
        return constructIntlType(type: "Segmenter", optionsBag: .jsIntlSegmenterSettings)
    }
}

