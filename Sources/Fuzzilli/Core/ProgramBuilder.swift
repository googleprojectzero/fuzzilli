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

/// Builds programs.
///
/// This provides methods for constructing and appending random
/// instances of the different kinds of operations in a program.
public class ProgramBuilder {
    /// The fuzzer instance for which this builder is active.
    public let fuzzer: Fuzzer

    /// The code and type information of the program that is being constructed.
    private var code = Code()

    /// Comments for the program that is being constructed.
    private var comments = ProgramComments()

    /// The parent program for the program being constructed.
    private let parent: Program?

    public enum Mode {
        /// In this mode, the builder will try as hard as possible to generate semantically valid code.
        /// However, the generated code is likely not as diverse as in aggressive mode.
        case conservative
        /// In this mode, the builder tries to generate more diverse code. However, the generated
        /// code likely has a lower probability of being semantically correct.
        case aggressive

    }
    /// The mode of this builder
    public var mode: Mode

    public var context: Context {
        return contextAnalyzer.context
    }

    /// Counter to quickly determine the next free variable.
    private var numVariables = 0

    /// Property names and integer values previously seen in the current program.
    private var seenPropertyNames = Set<String>()
    private var seenIntegers = Set<Int64>()
    private var seenFloats = Set<Double>()

    /// Keep track of existing variables containing known values. For the reuseOrLoadX APIs.
    /// Important: these will contain variables that are no longer in scope. As such, they generally
    /// have to be used in combination with the scope analyzer.
    private var loadedBuiltins = VariableMap<String>()
    private var loadedIntegers = VariableMap<Int64>()
    private var loadedFloats = VariableMap<Double>()

    /// Various analyzers for the current program.
    private var scopeAnalyzer = ScopeAnalyzer()
    private var contextAnalyzer = ContextAnalyzer()

    /// Type inference for JavaScript variables.
    private var jsTyper: JSTyper

    /// During code building, contains the number of instructions that should still be produced.
    /// Code building may overshot this number, but will never produce fewer instructions than this.
    private var currentBuildingBudget = 0

    /// Possible building modes. These are used as argument for build() and determine how the new code is produced.
    public enum BuildingMode {
        // Run random code generators.
        case runningGenerators
        // Splice code from other random programs in the corpus.
        case splicing
        // Do all of the above.
        case runningGeneratorsAndSplicing
    }

    /// The current code building mode.
    private var currentBuildingMode = BuildingMode.runningGeneratorsAndSplicing

    /// How many variables are currently in scope.
    public var numVisibleVariables: Int {
        return scopeAnalyzer.visibleVariables.count
    }

    /// Whether there are any variables currently in scope.
    public var hasVisibleVariables: Bool {
        return numVisibleVariables > 0
    }

    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer, parent: Program?, mode: Mode) {
        self.fuzzer = fuzzer
        self.jsTyper = JSTyper(for: fuzzer.environment)
        self.mode = mode
        self.parent = parent
    }

    /// Resets this builder.
    public func reset() {
        numVariables = 0
        seenPropertyNames.removeAll()
        seenIntegers.removeAll()
        seenFloats.removeAll()
        loadedBuiltins.removeAll()
        loadedIntegers.removeAll()
        loadedFloats.removeAll()
        code.removeAll()
        scopeAnalyzer = ScopeAnalyzer()
        contextAnalyzer = ContextAnalyzer()
        jsTyper.reset()
        currentBuildingBudget = 0
        currentBuildingMode = .runningGeneratorsAndSplicing
    }

    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        Assert(openFunctions.isEmpty)
        let program = Program(code: code, parent: parent, comments: comments)
        reset()
        return program
    }

    /// Prints the current program as FuzzIL code to stdout. Useful for debugging.
    public func dumpCurrentProgram() {
        print(FuzzILLifter().lift(code))
    }

    /// Returns the index of the next instruction added to the program. This is equal to the current size of the program.
    public func indexOfNextInstruction() -> Int {
        return code.count
    }

    /// Add a trace comment to the currently generated program at the current position.
    /// This is only done if history inspection is enabled.
    public func trace(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.inspection.contains(.history) {
            // Use an autoclosure here so that template strings are only evaluated when they are needed.
            comments.add(commentGenerator(), at: .instruction(code.count))
        }
    }

    /// Add a trace comment at the start of the currently generated program.
    /// This is only done if history inspection is enabled.
    public func traceHeader(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.inspection.contains(.history) {
            comments.add(commentGenerator(), at: .header)
        }
    }

    /// Generates a random integer for the current program context.
    public func genInt() -> Int64 {
        // Either pick a previously seen integer or generate a random one
        if probability(0.2) && seenIntegers.count >= 2 {
            return chooseUniform(from: seenIntegers)
        } else {
            return withEqualProbability({
                chooseUniform(from: self.fuzzer.environment.interestingIntegers)
            }, {
                Int64.random(in: -0x100000000...0x100000000)
            })
        }
    }

    /// Generates a random regex pattern.
    public func genRegExp() -> String {
        // Generate a "base" regexp
        var regex = ""
        let desiredLength = Int.random(in: 1...4)
        while regex.count < desiredLength {
            regex += withEqualProbability({
                String.random(ofLength: 1)
            }, {
                chooseUniform(from: self.fuzzer.environment.interestingRegExps)
            })
        }

        // Now optionally concatenate with another regexp
        if probability(0.3) {
            regex += genRegExp()
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

    /// Generates a random set of RegExpFlags
    public func genRegExpFlags() -> RegExpFlags {
        return RegExpFlags.random()
    }

    /// Generates a random index value for the current program context.
    public func genIndex() -> Int64 {
        return genInt()
    }

    /// Generates a random integer for the current program context.
    public func genFloat() -> Double {
        // TODO improve this
        if probability(0.2) && seenFloats.count >= 2 {
            return chooseUniform(from: seenFloats)
        } else {
            return withEqualProbability({
                chooseUniform(from: self.fuzzer.environment.interestingFloats)
            }, {
                Double.random(in: -1000000...1000000)
            })
        }
    }

    /// Generates a random string value for the current program context.
    public func genString() -> String {
        return withEqualProbability({
            self.genPropertyNameForRead()
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingStrings)
        }, {
            String.random(ofLength: 10)
        }, {
            String(chooseUniform(from: self.fuzzer.environment.interestingIntegers))
        })
    }

    /// Generates a random builtin name for the current program context.
    public func genBuiltinName() -> String {
        return chooseUniform(from: fuzzer.environment.builtins)
    }

    /// Generates a random property name for the current program context.
    public func genPropertyNameForRead() -> String {
        if probability(0.15) && seenPropertyNames.count >= 2 {
            return chooseUniform(from: seenPropertyNames)
        } else {
            return chooseUniform(from: fuzzer.environment.readPropertyNames)
        }
    }

    /// Generates a random property name for the current program context.
    public func genPropertyNameForWrite() -> String {
        if probability(0.15) && seenPropertyNames.count >= 2 {
            return chooseUniform(from: seenPropertyNames)
        } else {
            return chooseUniform(from: fuzzer.environment.writePropertyNames)
        }
    }

    /// Generates a random method name for the current program context.
    public func genMethodName() -> String {
        return chooseUniform(from: fuzzer.environment.methodNames)
    }

    ///
    /// Access to variables.
    ///

    /// Returns a random variable.
    public func randVar(excludeInnermostScope: Bool = false) -> Variable {
        Assert(hasVisibleVariables)
        return randVarInternal(excludeInnermostScope: excludeInnermostScope)!
    }

    /// Returns up to N (different) random variables.
    /// This method will only return fewer than N variables if the number of currently visible variables is less than N.
    public func randVars(upTo n: Int) -> [Variable] {
        Assert(hasVisibleVariables)
        var variables = [Variable]()
        while variables.count < n {
            guard let newVar = randVarInternal(filter: { !variables.contains($0) }) else {
                break
            }
            variables.append(newVar)
        }
        return variables
    }

    /// Returns a random variable of the given type.
    ///
    /// In conservative mode, this function fails unless it finds a matching variable.
    /// In aggressive mode, this function will also return variables that have unknown type, and may, if no matching variables are available, return variables of any type.
    ///
    /// In certain cases, for example in the InputMutator, it might be required to exclude variables from the innermost scopes, which can be achieved by passing excludeInnermostScope: true.
    public func randVar(ofType type: JSType, excludeInnermostScope: Bool = false) -> Variable? {
        var wantedType = type

        // As query/input type, .unknown is treated as .anything.
        // This for example simplifies code that is attempting to replace a given variable with another one with a "compatible" type.
        // If the real type of the replaced variable is unknown, it doesn't make sense to search for another variable of unknown type, so just use .anything.
        if wantedType.Is(.unknown) {
            wantedType = .anything
        }

        if mode == .aggressive {
            wantedType |= .unknown
        }

        if let v = randVarInternal(filter: { self.type(of: $0).Is(wantedType) }, excludeInnermostScope: excludeInnermostScope) {
            return v
        }

        // Didn't find a matching variable. If we are in aggressive mode, we now simply return a random variable.
        if mode == .aggressive {
            return randVar()
        }

        // Otherwise, we give up
        return nil
    }

    /// Returns a random variable of the given type. This is the same as calling randVar in conservative building mode.
    public func randVar(ofConservativeType type: JSType) -> Variable? {
        let oldMode = mode
        mode = .conservative
        defer { mode = oldMode }
        return randVar(ofType: type)
    }

    /// Returns a random variable satisfying the given constraints or nil if none is found.
    func randVarInternal(filter: ((Variable) -> Bool)? = nil, excludeInnermostScope: Bool = false) -> Variable? {
        var candidates = [Variable]()
        let scopes = excludeInnermostScope ? scopeAnalyzer.scopes.dropLast() : scopeAnalyzer.scopes

        // Prefer inner scopes
        withProbability(0.75) {
            candidates = chooseBiased(from: scopes, factor: 1.25)
            if let f = filter {
                candidates = candidates.filter(f)
            }
        }

        if candidates.isEmpty {
            let visibleVariables = excludeInnermostScope ? scopes.reduce([], +) : scopeAnalyzer.visibleVariables
            if let f = filter {
                candidates = visibleVariables.filter(f)
            } else {
                candidates = visibleVariables
            }
        }

        if candidates.isEmpty {
            return nil
        }

        return chooseUniform(from: candidates)
    }


    /// Type information access.
    public func type(of v: Variable) -> JSType {
        return jsTyper.type(of: v)
    }

    public func type(ofProperty property: String) -> JSType {
        return jsTyper.type(ofProperty: property)
    }

    /// Returns the type of the `super` binding at the current position.
    public func currentSuperType() -> JSType {
        return jsTyper.currentSuperType()
    }

    public func methodSignature(of methodName: String, on object: Variable) -> Signature {
        return jsTyper.inferMethodSignature(of: methodName, on: object)
    }

    public func methodSignature(of methodName: String, on objType: JSType) -> Signature {
        return jsTyper.inferMethodSignature(of: methodName, on: objType)
    }

    public func setType(ofProperty propertyName: String, to propertyType: JSType) {
        trace("Setting global property type: \(propertyName) => \(propertyType)")
        jsTyper.setType(ofProperty: propertyName, to: propertyType)
    }

    public func setType(ofVariable variable: Variable, to variableType: JSType) {
        jsTyper.setType(of: variable, to: variableType)
    }

    public func setSignature(ofMethod methodName: String, to methodSignature: Signature) {
        trace("Setting global method signature: \(methodName) => \(methodSignature)")
        jsTyper.setSignature(ofMethod: methodName, to: methodSignature)
    }

    // Generate random parameters for a function, method, or constructor.
    public func generateFunctionParameters() -> FunctionDescriptor {
        return .parameters(n: Int.random(in: 2...4), hasRestParameter: probability(0.1))
    }

    // This expands and collects types for arguments in function signatures.
    private func prepareArgumentTypes(forSignature signature: Signature) -> [JSType] {
        var argumentTypes = [JSType]()

        for param in signature.parameters {
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

    public func generateCallArguments(for signature: Signature) -> [Variable] {
        let argumentTypes = prepareArgumentTypes(forSignature: signature)
        var arguments = [Variable]()

        for argumentType in argumentTypes {
            if let v = randVar(ofConservativeType: argumentType) {
                arguments.append(v)
            } else {
                let argument = generateVariable(ofType: argumentType)
                // make sure, that now after generation we actually have a
                // variable of that type available.
                Assert(randVar(ofType: argumentType) != nil)
                arguments.append(argument)
            }
        }

        return arguments
    }

    public func randCallArguments(for signature: Signature) -> [Variable]? {
        let argumentTypes = prepareArgumentTypes(forSignature: signature)
        var arguments = [Variable]()
        for argumentType in argumentTypes {
            guard let v = randVar(ofType: argumentType) else { return nil }
            arguments.append(v)
        }
        return arguments
    }

    public func randCallArguments(for function: Variable) -> [Variable]? {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction
        return randCallArguments(for: signature)
    }

    public func generateCallArguments(for function: Variable) -> [Variable] {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction
        return generateCallArguments(for: signature)
    }

    public func randCallArguments(forMethod methodName: String, on object: Variable) -> [Variable]? {
        let signature = methodSignature(of: methodName, on: object)
        return randCallArguments(for: signature)
    }

    public func randCallArguments(forMethod methodName: String, on objType: JSType) -> [Variable]? {
        let signature = methodSignature(of: methodName, on: objType)
        return randCallArguments(for: signature)
    }

    public func randCallArgumentsWithSpreading(n: Int) -> (arguments: [Variable], spreads: [Bool]) {
        var arguments: [Variable] = []
        var spreads: [Bool] = []
        for _ in 0...n {
            let val = randVar()
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

    public func generateCallArguments(forMethod methodName: String, on object: Variable) -> [Variable] {
        let signature = methodSignature(of: methodName, on: object)
        return generateCallArguments(for: signature)
    }

    /// Generates a sequence of instructions that generate the desired type.
    /// This function can currently generate:
    ///  - primitive types
    ///  - arrays
    ///  - objects of certain types
    ///  - plain objects with properties that are either generated or selected
    ///    and methods that are selected from the environment.
    /// It currently cannot generate:
    ///  - methods for objects
    func generateVariable(ofType type: JSType) -> Variable {
        trace("Generating variable of type \(type)")

        // Check primitive types
        if type.Is(.integer) || type.Is(fuzzer.environment.intType) {
            return loadInt(genInt())
        }
        if type.Is(.float) || type.Is(fuzzer.environment.floatType) {
            return loadFloat(genFloat())
        }
        if type.Is(.string) || type.Is(fuzzer.environment.stringType) {
            return loadString(genString())
        }
        if type.Is(.boolean) || type.Is(fuzzer.environment.booleanType) {
            return loadBool(Bool.random())
        }
        if type.Is(.bigint) || type.Is(fuzzer.environment.bigIntType) {
            return loadBigInt(genInt())
        }
        if type.Is(.function()) {
            let signature = type.signature ?? Signature(withParameterCount: Int.random(in: 2...5), hasRestParam: probability(0.1))
            return buildPlainFunction(with: .signature(signature), isStrict: probability(0.1)) { _ in
                buildRecursive()
                doReturn(value: randVar())
            }
        }
        if type.Is(.regexp) || type.Is(fuzzer.environment.regExpType) {
            return loadRegExp(genRegExp(), genRegExpFlags())
        }

        Assert(type.Is(.object()), "Unexpected type encountered \(type)")

        // The variable that we will return.
        var obj: Variable

        // Fast path for array creation.
        if type.Is(fuzzer.environment.arrayType) && probability(0.9) {
            let value = randVar()
            return createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
        }

        if let group = type.group {
            // Objects with predefined groups must be constructable through a Builtin exposed by the Environment.
            // Normally, that builtin is a .constructor(), but we also allow just a .function() for constructing object.
            // This is for example necessary for JavaScript Symbols, as the Symbol builtin is not a constructor.
            let constructorType = fuzzer.environment.type(ofBuiltin: group)
            Assert(constructorType.Is(.function() | .constructor()), "We don't know how to construct \(group)")
            Assert(constructorType.signature != nil, "We don't know how to construct \(group) (missing signature for constructor)")
            Assert(constructorType.signature!.outputType.group == group, "We don't know how to construct \(group) (invalid signature for constructor)")

            let constructorSignature = constructorType.signature!
            let arguments = generateCallArguments(for: constructorSignature)
            let constructor = loadBuiltin(group)
            if !constructorType.Is(.constructor()) {
                obj = callFunction(constructor, withArgs: arguments)
            } else {
                obj = construct(constructor, withArgs: arguments)
            }
        } else {
            // Either generate a literal or use the store property stuff.
            if probability(0.8) { // Do the literal
                var initialProperties: [String: Variable] = [:]
                // gather properties of the correct types
                for prop in type.properties {
                    var value: Variable?
                    let type = self.type(ofProperty: prop)
                    if type != .unknown {
                        // TODO Here and elsewhere in this function: turn this pattern into a new helper function,
                        // e.g. reuseOrGenerateVariable(ofType: ...). See also the discussions in
                        // https://github.com/googleprojectzero/fuzzilli/blob/main/Docs/HowFuzzilliWorks.md#when-to-instantiate
                        // TODO I don't think we need to use the ofConservativeType version. The regular ofType version should
                        // be fine since the ProgramTemplates/HybridEngine do the code generation in conservative mode anyway.
                        value = randVar(ofConservativeType: type) ?? generateVariable(ofType: type)
                    } else {
                        if !hasVisibleVariables {
                            value = loadInt(genInt())
                        } else {
                            value = randVar()
                        }
                    }
                    initialProperties[prop] = value
                }
                // TODO: This should take the method type/signature into account!
                _ = type.methods.map { initialProperties[$0] = randVar(ofType: .function()) ?? generateVariable(ofType: .function()) }
                obj = createObject(with: initialProperties)
            } else { // Do it with storeProperty
                obj = construct(loadBuiltin("Object"), withArgs: [])
                for method in type.methods {
                    // TODO: This should take the method type/signature into account!
                    let methodVar = randVar(ofType: .function()) ?? generateVariable(ofType: .function())
                    storeProperty(methodVar, as: method, on: obj)
                }
                for prop in type.properties {
                    var value: Variable?
                    let type = self.type(ofProperty: prop)
                    if type != .unknown {
                        value = randVar(ofConservativeType: type) ?? generateVariable(ofType: type)
                    } else {
                        value = randVar()
                    }
                    storeProperty(value!, as: prop, on: obj)
                }
            }
        }

        return obj
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

    private func createVariableMapping(from sourceVariable: Variable, to hostVariable: Variable) {
        Assert(!varMaps.last!.contains(sourceVariable))
        varMaps[varMaps.count - 1][sourceVariable] = hostVariable
    }

    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt<Variables: Collection>(_ variables: Variables) -> [Variable] where Variables.Element == Variable {
        return variables.map(adopt)
    }

    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instr: Instruction) {
        internalAppend(Instruction(instr.op, inouts: adopt(instr.inouts)))
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

    /// Append a splice from another program.
    public func splice(from program: Program, at index: Int) {
        // Early exit if we are currently within a Switch statement.
        guard !contextAnalyzer.context.contains(.switchBlock) else {
            return
        }

        trace("Splicing instruction \(index) (\(program.code[index].op.name)) from \(program.id)")

        beginAdoption(from: program)

        let source = program.code

        // The slice of the given program that will be inserted into the current program.
        var slice = Set<Int>()

        // Determine all necessary input instructions for the choosen instruction
        // We need special handling for blocks:
        //   If the choosen instruction is a block instruction then copy the whole block
        //   If we need an inner output of a block instruction then only copy the block instructions, not the content
        //   Otherwise copy the whole block including its content
        var requiredInputs = VariableSet()

        // A Set of variables that have yet to be included in the slice
        var remainingInputs = VariableSet()

        // A stack of contexts that are required by the instruction in the slice
        var requiredContextStack = [Context.empty]

        // Helper function to handle context updates when handling block instructions
        func handleBlockInstruction(instruction instr: Instruction, shouldAdd: Bool = false){
            // When we encounter a block begin:
            // 1. We ensure that the context being opened removes at least one required context
            // 2. The default context (.script) isn't the only context being removed
            // 3. The required context is not empty
            if instr.isBlockStart {
                var requiredContext = requiredContextStack.removeLast()
                if requiredContext.subtracting(instr.op.contextOpened) != requiredContext && requiredContext.intersection(instr.op.contextOpened) != .javascript && requiredContext != .empty {
                    requiredContextStack.append(requiredContext)
                    if shouldAdd {
                        add(instr)
                    }
                    requiredContext = requiredContextStack.removeLast()
                }
                requiredContext = requiredContext.subtracting(instr.op.contextOpened)

                // If the required context is not a subset of the current stack top, then we have contexts that should be propagated to the current stack top
                // We must have at least one context on the stack
                if requiredContextStack.count >= 1 {
                    var currentTop = requiredContextStack.removeLast()
                    requiredContext = requiredContext.subtracting(currentTop)
                    if requiredContext != .empty {
                        currentTop.formUnion(requiredContext)
                    }
                    requiredContextStack.append(currentTop)
                } else {
                    requiredContextStack.append(requiredContext)
                }
            }
            if instr.isBlockEnd {
                requiredContextStack.append([])
            }
        }

        // Helper function to add a context to the context stack
        func addContextRequired(requiredContext: Context) {
            var currentContext = requiredContextStack.removeLast()
            currentContext.formUnion(requiredContext)
            requiredContextStack.append(currentContext)
        }

        // Helper function to add an instruction, or possibly multiple instruction in the case of blocks, to the slice.
        func add(_ instr: Instruction, includeBlockContent: Bool = false) {
            guard !slice.contains(instr.index) else { return }

            func internalAdd(_ instr: Instruction) {
                remainingInputs.subtract(instr.allOutputs)

                requiredInputs.formUnion(instr.inputs)
                remainingInputs.formUnion(instr.inputs)
                addContextRequired(requiredContext: instr.op.requiredContext)
                handleBlockInstruction(instruction: instr)
                slice.insert(instr.index)
            }

            if instr.isBlock {
                let group = BlockGroup(around: instr, in: source)
                let instructions = includeBlockContent ? group.includingContent() : group.excludingContent()
                // Instructions within blocks are evaluated in reverse order so that the evaluation is consistent with the caller loop
                for instr in instructions.reversed() {
                    internalAdd(instr)
                }
            } else {
                internalAdd(instr)
            }
        }

        // Compute the slice...
        var idx = index

        // We also early exit if we encounter a switch during adoption.
        var needsSwitch = false

        // First, add the selected instruction.
        add(source[idx], includeBlockContent: true)
        // Then add all instructions that the slice has data dependencies on.
        while idx > 0 {

            // This is the exit condition from the loop
            // We have no remaining inputs to account for and
            // There's only one context on the stack which must be a subset of self.context (i.e. context of the host program)
            if remainingInputs.isEmpty && requiredContextStack.count == 1 {
                let requiredContext = requiredContextStack.last!
                if requiredContext.isSubset(of: self.context) {
                    break
                }
            }

            idx -= 1
            let instr = source[idx]

            // Check if we need a BeginSwitch or BeginSwitchCase, if so early exit.
            if instr.op.requiredContext.contains(.switchBlock) || instr.op.requiredContext.contains(.switchCase) {
                needsSwitch = true
                break
            }

            if !requiredInputs.isDisjoint(with: instr.allOutputs) {
                let onlyNeedsInnerOutputs = requiredInputs.isDisjoint(with: instr.outputs)
                // If we only need inner outputs (e.g. function parameters), then we don't include
                // the block's content in the slice. Otherwise we do.
                add(instr, includeBlockContent: !onlyNeedsInnerOutputs)
            }

            // If we perform a potentially mutating operation (such as a property store or a method call)
            // on a required variable, then we may decide to keep that instruction as well.
            if mode == .conservative || (mode == .aggressive && probability(0.5)) {
                if instr.mayMutate(requiredInputs) {
                    add(instr)
                }
            }

            handleBlockInstruction(instruction: instr, shouldAdd: true)
        }

        // don't splice if we want to splice from a switch context.
        if needsSwitch {
            endAdoption()
            return
        }

        // If, after the loop, the current context does not contain the required context (e.g. because we are just after a BeginSwitch), abort the splicing
        let stillRequired = requiredContextStack.removeLast()
        guard stillRequired.isSubset(of: self.context) else {
            endAdoption()
            return
        }

        // Finally, insert the slice into the current program.
        for instr in source {
            if slice.contains(instr.index) {
                adopt(instr)
            }
        }
        endAdoption()
        trace("Splicing done")
    }

    func splice(from program: Program) {
        // Pick a starting instruction from the selected program.
        // For that, prefer dataflow "sinks" whose outputs are not used for anything else,
        // as these are probably the most interesting instructions.
        var idx = 0
        var counter = 0
        repeat {
            counter += 1
            idx = Int.random(in: 0..<program.size)
            // Some instructions are less suited to be the start of a splice. Skip them.
        } while counter < 25 && (program.code[idx].isJump || program.code[idx].isBlockEnd || !program.code[idx].hasInputs)

        splice(from: program, at: idx)
    }

    private var openFunctions = [Variable]()
    private func callLikelyRecurses(function: Variable) -> Bool {
        return openFunctions.contains(function)
    }

    /// Build random code at the current position in the program.
    public func build(n: Int = 1, by mode: BuildingMode = .runningGeneratorsAndSplicing) {
        currentBuildingBudget = n
        currentBuildingMode = mode
        buildInternal()
    }

    /// Recursive code building. Used by CodeGenerators for example to fill the bodies of generated blocks.
    public func buildRecursive() {
        Assert(currentBuildingMode != .splicing)

        // Generate at least one instruction, even if already below budget.
        if currentBuildingBudget <= 0 {
            currentBuildingBudget = 1
        }

        // Limit recursive building (i.e. bodies of generated blocks) to 25% - 50% of the original budget.
        let remainingOuterBuildingBudget = Int(Double(currentBuildingBudget) * Double.random(in: 0.50...0.75))
        currentBuildingBudget -= remainingOuterBuildingBudget

        buildInternal()

        // Restore the original budget.
        currentBuildingBudget = remainingOuterBuildingBudget
    }

    private func buildInternal() {
        Assert(currentBuildingBudget > 0)

        // Splicing or code generation may fail. This counts consecutive failures to avoid infinite looping below.
        var consecutiveFailures = 0

        // Unless we are only splicing, find all generators that have the required context. We must always have at least one suitable code generator.
        let origContext = context
        var availableGenerators = WeightedList<CodeGenerator>()
        if currentBuildingMode != .splicing {
            availableGenerators = fuzzer.codeGenerators.filter({ $0.requiredContext.isSubset(of: origContext) })
            Assert(!availableGenerators.isEmpty)
        }

        while currentBuildingBudget > 0 && consecutiveFailures < 10 {
            Assert(context == origContext, "Code generation or splicing must not change the current context")

            var mode = currentBuildingMode
            if mode == .runningGeneratorsAndSplicing {
                mode = chooseUniform(from: [.runningGenerators, .splicing])
            }

            let previousBudget = currentBuildingBudget

            switch mode {
            case .runningGenerators:
                if !hasVisibleVariables {
                    // Can't run code generators if there are no visible variables, so generate some.
                    run(chooseUniform(from: fuzzer.trivialCodeGenerators))
                    Assert(hasVisibleVariables)
                }

                // Select a random generator and run it.
                let generator = availableGenerators.randomElement()
                run(generator)

            case .splicing:
                let program = fuzzer.corpus.randomElementForSplicing()
                splice(from: program)

            default:
                fatalError("Unknown ProgramBuildingMode \(mode)")
            }

            // Both splicing and code generation can sometimes fail, for example if no other program with the necessary features exists.
            // To avoid infinite loops, we bail out after a certain number of failures.
            if currentBuildingBudget == previousBudget {
                consecutiveFailures += 1
            } else {
                consecutiveFailures = 0
            }
        }
    }

    /// Runs a code generator in the current context.
    private func run(_ generator: CodeGenerator) {
        Assert(generator.requiredContext.isSubset(of: context))

        var inputs: [Variable] = []
        for type in generator.inputTypes {
            // TODO should this generate variables in conervative mode
            guard let val = randVar(ofType: type) else { return }
            // In conservative mode, attempt to prevent direct recursion to reduce the number of timeouts
            // This is a very crude mechanism. It might be worth implementing a more sophisticated one.
            if mode == .conservative && type.Is(.function()) && callLikelyRecurses(function: val) { return }

            inputs.append(val)
        }

        trace("Executing code generator \(generator.name)")
        generator.run(in: self, with: inputs)
        trace("Code generator finished")
    }

    //
    // Variable reuse APIs.
    //
    // These attempt to find an existing variable containing the desired value.
    // If none exist, a new instruction is emitted to create it.
    //
    // This is generally an O(n) operation in the number of currently visible
    // varialbes (~= current size of program). This should be fine since it is
    // not too frequently used. Also, this way of implementing it keeps the
    // overhead in internalAppend to a minimum, which is probably more important.
    public func reuseOrLoadBuiltin(_ name: String) -> Variable {
        for v in scopeAnalyzer.visibleVariables {
            if let builtin = loadedBuiltins[v], builtin == name {
                return v
            }
        }
        return loadBuiltin(name)
    }

    public func reuseOrLoadInt(_ value: Int64) -> Variable {
        for v in scopeAnalyzer.visibleVariables {
            if let val = loadedIntegers[v], val == value {
                return v
            }
        }
        return loadInt(value)
    }

    public func reuseOrLoadAnyInt() -> Variable {
        // This isn't guaranteed to succeed, but that's probably fine.
        let val = seenIntegers.randomElement() ?? genInt()
        return reuseOrLoadInt(val)
    }

    public func reuseOrLoadFloat(_ value: Double) -> Variable {
        for v in scopeAnalyzer.visibleVariables {
            if let val = loadedFloats[v], val == value {
                return v
            }
        }
        return loadFloat(value)
    }

    public func reuseOrLoadAnyFloat() -> Variable {
        let val = seenFloats.randomElement() ?? genFloat()
        return reuseOrLoadFloat(val)
    }


    //
    // Low-level instruction constructors.
    //
    // These create an instruction with the provided values and append it to the program at the current position.
    // If the instruction produces a new variable, that variable is returned to the caller.
    // Each class implementing the Operation protocol will have a constructor here.
    //

    @discardableResult
    private func emit(_ op: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        var inouts = inputs
        for _ in 0..<op.numOutputs {
            inouts.append(nextVariable())
        }
        for _ in 0..<op.numInnerOutputs {
            inouts.append(nextVariable())
        }

        return internalAppend(Instruction(op, inouts: inouts))
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
    public func loadString(_ value: String) -> Variable {
        return emit(LoadString(value: value)).output
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
    public func loadRegExp(_ value: String, _ flags: RegExpFlags) -> Variable {
        return emit(LoadRegExp(value: value, flags: flags)).output
    }

    @discardableResult
    public func createObject(with initialProperties: [String: Variable]) -> Variable {
        // CreateObject expects sorted property names
        var propertyNames = [String](), propertyValues = [Variable]()
        for (k, v) in initialProperties.sorted(by: { $0.key < $1.key }) {
            propertyNames.append(k)
            propertyValues.append(v)
        }
        return emit(CreateObject(propertyNames: propertyNames), withInputs: propertyValues).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable]) -> Variable {
        return emit(CreateArray(numInitialValues: initialValues.count), withInputs: initialValues).output
    }

    @discardableResult
    public func createObject(with initialProperties: [String: Variable], andSpreading spreads: [Variable]) -> Variable {
        // CreateObjectWithgSpread expects sorted property names
        var propertyNames = [String](), propertyValues = [Variable]()
        for (k, v) in initialProperties.sorted(by: { $0.key < $1.key }) {
            propertyNames.append(k)
            propertyValues.append(v)
        }
        return emit(CreateObjectWithSpread(propertyNames: propertyNames, numSpreads: spreads.count), withInputs: propertyValues + spreads).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable], spreading spreads: [Bool]) -> Variable {
        Assert(initialValues.count == spreads.count)
        return emit(CreateArrayWithSpread(spreads: spreads), withInputs: initialValues).output
    }

    @discardableResult
    public func createTemplateString(from parts: [String], interpolating interpolatedValues: [Variable]) -> Variable {
        return emit(CreateTemplateString(parts: parts), withInputs: interpolatedValues).output
    }

    @discardableResult
    public func loadBuiltin(_ name: String) -> Variable {
        return emit(LoadBuiltin(builtinName: name)).output
    }

    @discardableResult
    public func loadProperty(_ name: String, of object: Variable) -> Variable {
        return emit(LoadProperty(propertyName: name), withInputs: [object]).output
    }

    public func storeProperty(_ value: Variable, as name: String, on object: Variable) {
        emit(StoreProperty(propertyName: name), withInputs: [object, value])
    }

    public func storeProperty(_ value: Variable, as name: String, with op: BinaryOperator, on object: Variable) {
        emit(StorePropertyWithBinop(propertyName: name, operator: op), withInputs: [object, value])
    }

    @discardableResult
    public func deleteProperty(_ name: String, of object: Variable) -> Variable {
        emit(DeleteProperty(propertyName: name), withInputs: [object]).output
    }

    @discardableResult
    public func loadElement(_ index: Int64, of array: Variable) -> Variable {
        return emit(LoadElement(index: index), withInputs: [array]).output
    }

    public func storeElement(_ value: Variable, at index: Int64, of array: Variable) {
        emit(StoreElement(index: index), withInputs: [array, value])
    }

    public func storeElement(_ value: Variable, at index: Int64, with op: BinaryOperator, of array: Variable) {
        emit(StoreElementWithBinop(index: index, operator: op), withInputs: [array, value])
    }

    @discardableResult
    public func deleteElement(_ index: Int64, of array: Variable) -> Variable {
        emit(DeleteElement(index: index), withInputs: [array]).output
    }

    @discardableResult
    public func loadComputedProperty(_ name: Variable, of object: Variable) -> Variable {
        return emit(LoadComputedProperty(), withInputs: [object, name]).output
    }

    public func storeComputedProperty(_ value: Variable, as name: Variable, on object: Variable) {
        emit(StoreComputedProperty(), withInputs: [object, name, value])
    }

    public func storeComputedProperty(_ value: Variable, as name: Variable, with op: BinaryOperator, on object: Variable) {
        emit(StoreComputedPropertyWithBinop(operator: op), withInputs: [object, name, value])
    }

    @discardableResult
    public func deleteComputedProperty(_ name: Variable, of object: Variable) -> Variable {
        emit(DeleteComputedProperty(), withInputs: [object, name]).output
    }

    @discardableResult
    public func typeof(_ v: Variable) -> Variable {
        return emit(TypeOf(), withInputs: [v]).output
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
        emit(Explore(id: id, numArguments: arguments.count), withInputs: [v] + arguments)
    }

    // Helper struct to describe function definitions.
    // This allows defining functions just through the number of parameters or through a Signature, which also contains parameter types.
    // Note however that FunctionSignatures are not associated with the generated operations and will therefore just be valid for the lifetime
    // of this ProgramBuilder. The reason for this behaviour is that it is generally not possible to preserve the type informatio across program
    // mutations (a mutator may change the callsite of a function or modify the uses of a parameter, effectively invalidating the signature).
    public struct FunctionDescriptor {
        fileprivate let parameters: Parameters
        fileprivate let signature: Signature?

        public static func parameters(n: Int, hasRestParameter: Bool = false) -> FunctionDescriptor {
            return FunctionDescriptor(Parameters(count: n, hasRestParameter: hasRestParameter))
        }

        public static func parameters(_ inputTypes: [Signature.Parameter]) -> FunctionDescriptor {
            let signature = inputTypes => .unknown
            return .signature(signature)
        }

        public static func signature(_ signature: Signature) -> FunctionDescriptor {
            let parameters = Parameters(count: signature.numParameters, hasRestParameter: signature.hasRestParameter)
            return FunctionDescriptor(parameters, signature)
        }

        private init(_ parameters: Parameters, _ signature: Signature? = nil) {
            self.parameters = parameters
            self.signature = signature
            Assert(signature == nil || signature?.numParameters == parameters.count)
        }
    }

    @discardableResult
    public func buildPlainFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginPlainFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndPlainFunction())
        return instr.output
    }

    @discardableResult
    public func buildArrowFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildGeneratorFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncArrowFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncGeneratorFunction(with descriptor: FunctionDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncGeneratorFunction())
        return instr.output
    }

    public func doReturn(value: Variable) {
        emit(Return(), withInputs: [value])
    }

    @discardableResult
    public func yield(value: Variable) -> Variable {
        return emit(Yield(), withInputs: [value]).output
    }

    public func yieldEach(value: Variable) {
        emit(YieldEach(), withInputs: [value])
    }

    @discardableResult
    public func await(value: Variable) -> Variable {
        return emit(Await(), withInputs: [value]).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable]) -> Variable {
        return emit(CallFunction(numArguments: arguments.count), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return callFunction(function, withArgs: arguments) }
        return emit(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable]) -> Variable {
        return emit(Construct(numArguments: arguments.count), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return construct(constructor, withArgs: arguments) }
        return emit(ConstructWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable]) -> Variable {
        return emit(CallMethod(methodName: name, numArguments: arguments.count), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return callMethod(name, on: object, withArgs: arguments) }
        return emit(CallMethodWithSpread(methodName: name, numArguments: arguments.count, spreads: spreads), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable]) -> Variable {
        return emit(CallComputedMethod(numArguments: arguments.count), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return callComputedMethod(name, on: object, withArgs: arguments) }
        return emit(CallComputedMethodWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func unary(_ op: UnaryOperator, _ input: Variable) -> Variable {
        return emit(UnaryOperation(op), withInputs: [input]).output
    }

    @discardableResult
    public func binary(_ lhs: Variable, _ rhs: Variable, with op: BinaryOperator) -> Variable {
        return emit(BinaryOperation(op), withInputs: [lhs, rhs]).output
    }

    public func reassign(_ output: Variable, to input: Variable, with op: BinaryOperator) {
        emit(ReassignWithBinop(op), withInputs: [output, input])
    }

    @discardableResult
    public func dup(_ v: Variable) -> Variable {
        return emit(Dup(), withInputs: [v]).output
    }

    public func reassign(_ output: Variable, to input: Variable) {
        emit(Reassign(), withInputs: [output, input])
    }

    @discardableResult
    public func destruct(_ input: Variable, selecting indices: [Int], hasRestElement: Bool = false) -> [Variable] {
        let outputs = emit(DestructArray(indices: indices, hasRestElement: hasRestElement), withInputs: [input]).outputs
        return Array(outputs)
    }

    public func destruct(_ input: Variable, selecting indices: [Int], into outputs: [Variable], hasRestElement: Bool = false) {
        emit(DestructArrayAndReassign(indices: indices, hasRestElement: hasRestElement), withInputs: [input] + outputs)
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
    public func compare(_ lhs: Variable, _ rhs: Variable, with comparator: Comparator) -> Variable {
        return emit(Compare(comparator), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func conditional(_ condition: Variable, _ lhs: Variable, _ rhs: Variable) -> Variable {
        return emit(ConditionalOperation(), withInputs: [condition, lhs, rhs]).output
    }

    public func eval(_ string: String, with arguments: [Variable] = []) {
        emit(Eval(string, numArguments: arguments.count), withInputs: arguments)
    }

    public func buildWith(_ scopeObject: Variable, body: () -> Void) {
        emit(BeginWith(), withInputs: [scopeObject])
        body()
        emit(EndWith())
    }

    @discardableResult
    public func loadFromScope(id: String) -> Variable {
        return emit(LoadFromScope(id: id)).output
    }

    public func storeToScope(_ value: Variable, as id: String) {
        emit(StoreToScope(id: id), withInputs: [value])
    }

    public func nop(numOutputs: Int = 0) {
        emit(Nop(numOutputs: numOutputs), withInputs: [])
    }

    public struct ClassBuilder {
        public typealias MethodBodyGenerator = ([Variable]) -> ()
        public typealias ConstructorBodyGenerator = MethodBodyGenerator

        fileprivate var constructor: (descriptor: FunctionDescriptor, generator: ConstructorBodyGenerator)? = nil
        fileprivate var methods: [(name: String, descriptor: FunctionDescriptor, generator: ConstructorBodyGenerator)] = []
        fileprivate var properties: [String] = []

        // This struct is only created by defineClass below
        fileprivate init() {}

        public mutating func defineConstructor(with descriptor: FunctionDescriptor, _ generator: @escaping ConstructorBodyGenerator) {
            constructor = (descriptor, generator)
        }

        public mutating func defineProperty(_ name: String) {
            properties.append(name)
        }

        public mutating func defineMethod(_ name: String, with descriptor: FunctionDescriptor, _ generator: @escaping MethodBodyGenerator) {
            methods.append((name, descriptor, generator))
        }
    }

    public typealias ClassBodyGenerator = (inout ClassBuilder) -> ()

    @discardableResult
    public func buildClass(withSuperclass superclass: Variable? = nil,
                            _ body: ClassBodyGenerator) -> Variable {
        // First collect all information about the class and the generators for constructor and method bodies
        var builder = ClassBuilder()
        body(&builder)

        // Now compute the instance type and define the class
        let properties = builder.properties
        let methods = builder.methods.map({ ($0.name, $0.descriptor.parameters )})
        let constructorDescriptor = builder.constructor?.descriptor ?? .parameters(n: 0)
        let hasSuperclass = superclass != nil
        setSignatureForNextFunction(builder.constructor?.descriptor.signature)
        let classDefinition = emit(BeginClass(hasSuperclass: hasSuperclass,
                                              constructorParameters: constructorDescriptor.parameters,
                                              instanceProperties: properties,
                                              instanceMethods: methods),
                                   withInputs: hasSuperclass ? [superclass!] : [])

        // The code directly following the BeginClass is the body of the constructor
        builder.constructor?.generator(Array(classDefinition.innerOutputs))

        // Next are the bodies of the methods
        for method in builder.methods {
            setSignatureForNextFunction(method.descriptor.signature)
            let methodDefinition = emit(BeginMethod(numParameters: method.descriptor.parameters.count), withInputs: [])
            method.generator(Array(methodDefinition.innerOutputs))
        }

        emit(EndClass())

        return classDefinition.output
    }

    public func callSuperConstructor(withArgs arguments: [Variable]) {
        emit(CallSuperConstructor(numArguments: arguments.count), withInputs: arguments)
    }

    @discardableResult
    public func callSuperMethod(_ name: String, withArgs arguments: [Variable]) -> Variable {
        return emit(CallSuperMethod(methodName: name, numArguments: arguments.count), withInputs: arguments).output
    }

    @discardableResult
    public func loadSuperProperty(_ name: String) -> Variable {
        return emit(LoadSuperProperty(propertyName: name)).output
    }

    public func storeSuperProperty(_ value: Variable, as name: String) {
        emit(StoreSuperProperty(propertyName: name), withInputs: [value])
    }

    public func storeSuperProperty(_ value: Variable, as name: String, with op: BinaryOperator) {
        emit(StoreSuperPropertyWithBinop(propertyName: name, operator: op), withInputs: [value])
    }

    public func buildIfElse(_ condition: Variable, ifBody: () -> Void, elseBody: () -> Void) {
        emit(BeginIf(), withInputs: [condition])
        ifBody()
        emit(BeginElse())
        elseBody()
        emit(EndIf())
    }

    public struct SwitchBuilder {
        public typealias SwitchCaseGenerator = () -> ()
        fileprivate var caseGenerators: [(value: Variable?, fallsthrough: Bool, body: SwitchCaseGenerator)] = []
        var hasDefault: Bool = false

        public mutating func addDefault(fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            Assert(!hasDefault, "Cannot add more than one default case")
            hasDefault = true
            caseGenerators.append((nil, fallsThrough, body))
        }

        public mutating func add(_ v: Variable, fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            caseGenerators.append((v, fallsThrough, body))
        }
    }

    public func buildSwitch(on switchVar: Variable, body: (inout SwitchBuilder) -> ()) {
        var builder = SwitchBuilder()
        body(&builder)

        emit(BeginSwitch(), withInputs: [switchVar])

        for (val, fallsThrough, bodyGenerator) in builder.caseGenerators {
            let inputs = val == nil ? [] : [val!]
            if inputs.count == 0 {
                emit(BeginSwitchDefaultCase(), withInputs: inputs)
            } else {
                emit(BeginSwitchCase(), withInputs: inputs)
            }
            bodyGenerator()
            emit(EndSwitchCase(fallsThrough: fallsThrough))
        }
        emit(EndSwitch())
    }

    public func buildSwitchCase(forCase caseVar: Variable, fallsThrough: Bool, body: () -> ()) {
        emit(BeginSwitchCase(), withInputs: [caseVar])
        body()
        emit(EndSwitchCase(fallsThrough: fallsThrough))
    }

    public func switchBreak() {
        emit(SwitchBreak())
    }

    public func buildWhileLoop(_ lhs: Variable, _ comparator: Comparator, _ rhs: Variable, _ body: () -> Void) {
        emit(BeginWhileLoop(comparator: comparator), withInputs: [lhs, rhs])
        body()
        emit(EndWhileLoop())
    }

    public func buildDoWhileLoop(_ lhs: Variable, _ comparator: Comparator, _ rhs: Variable, _ body: () -> Void) {
        emit(BeginDoWhileLoop(comparator: comparator), withInputs: [lhs, rhs])
        body()
        emit(EndDoWhileLoop())
    }

    public func buildForLoop(_ start: Variable, _ comparator: Comparator, _ end: Variable, _ op: BinaryOperator, _ rhs: Variable, _ body: (Variable) -> ()) {
        let i = emit(BeginForLoop(comparator: comparator, op: op), withInputs: [start, end, rhs]).innerOutput
        body(i)
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

    public func buildForOfLoop(_ obj: Variable, selecting indices: [Int], hasRestElement: Bool = false, _ body: ([Variable]) -> ()) {
        let instr = emit(BeginForOfWithDestructLoop(indices: indices, hasRestElement: hasRestElement), withInputs: [obj])
        body(Array(instr.innerOutputs))
        emit(EndForOfLoop())
    }

    public func loopBreak() {
        emit(LoopBreak())
    }

    public func loopContinue() {
        emit(LoopContinue(), withInputs: [])
    }

    public func buildTryCatchFinally(tryBody: () -> (), catchBody: ((Variable) -> ())? = nil, finallyBody: (() -> ())? = nil) {
        Assert(catchBody != nil || finallyBody != nil, "Must have either a Catch or a Finally block (or both)")
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


    /// Returns the next free variable.
    func nextVariable() -> Variable {
        Assert(numVariables < Code.maxNumberOfVariables, "Too many variables")
        numVariables += 1
        return Variable(number: numVariables - 1)
    }

    @discardableResult
    private func internalAppend(_ instr: Instruction) -> Instruction {
        // Basic integrity checking
        Assert(!instr.inouts.contains(where: { $0.number >= numVariables }))
        Assert(instr.op.requiredContext.isSubset(of: contextAnalyzer.context))

        // The returned instruction will also contain its index in the program. Use that so the analyzers have access to the index.
        let instr = code.append(instr)

        currentBuildingBudget -= 1

        // Update our analyses
        scopeAnalyzer.analyze(instr)
        contextAnalyzer.analyze(instr)
        // TODO could this become an Analyzer?
        updateValueAnalysis(instr)
        if instr.op is BeginAnyFunction {
            openFunctions.append(instr.output)
        } else if instr.op is EndAnyFunction {
            openFunctions.removeLast()
        }

        // Update type information
        jsTyper.analyze(instr)

        return instr
    }

    /// Set the signature for the next function, method, or constructor, which must be the the start of a function or method definition.
    /// Function/method signatures are only valid for the duration of the program generation, as they cannot be preserved across mutations.
    /// As such, these signatures are linked to their instruction through the index of the instruction in the program.
    private func setSignatureForNextFunction(_ maybeSignature: Signature?) {
        guard let signature = maybeSignature else { return }
        jsTyper.setSignature(forInstructionAt: code.count, to: signature)
    }

    /// Update value analysis. In particular the set of seen values and the variables that contain them for variable reuse.
    private func updateValueAnalysis(_ instr: Instruction) {
        switch instr.op {
        case let op as LoadInteger:
            seenIntegers.insert(op.value)
            loadedIntegers[instr.output] = op.value
        case let op as LoadBigInt:
            seenIntegers.insert(op.value)
        case let op as LoadFloat:
            seenFloats.insert(op.value)
            loadedFloats[instr.output] = op.value
        case let op as LoadBuiltin:
            loadedBuiltins[instr.output] = op.builtinName
        case let op as LoadProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as StoreProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as StorePropertyWithBinop:
            seenPropertyNames.insert(op.propertyName)
        case let op as DeleteProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as LoadElement:
            seenIntegers.insert(op.index)
        case let op as StoreElement:
            seenIntegers.insert(op.index)
        case let op as StoreElementWithBinop:
            seenIntegers.insert(op.index)
        case let op as DeleteElement:
            seenIntegers.insert(op.index)
        case let op as CreateObject:
            seenPropertyNames.formUnion(op.propertyNames)
        default:
            break
        }

        for v in instr.inputs {
            if instr.reassigns(v) {
                // Remove input from loaded variable sets
                loadedBuiltins.removeValue(forKey: v)
                loadedIntegers.removeValue(forKey: v)
                loadedFloats.removeValue(forKey: v)
            }
        }
    }
}
