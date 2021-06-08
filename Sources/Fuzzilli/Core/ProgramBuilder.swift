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
    public var types = ProgramTypes()

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

    /// Whether to perform splicing as part of the code generation.
    public var performSplicingDuringCodeGeneration = true

    public var context: ProgramContext {
        return contextAnalyzer.context
    }

    /// Counter to quickly determine the next free variable.
    private var numVariables = 0

    /// Property names and integer values previously seen in the current program.
    private var seenPropertyNames = Set<String>()
    private var seenIntegers = Set<Int64>()

    /// Various analyzers for the current program.
    private var scopeAnalyzer = ScopeAnalyzer()
    private var contextAnalyzer = ContextAnalyzer()

    /// Abstract interpreter to computer type information.
    private var interpreter: AbstractInterpreter?

    /// During code generation, contains the minimum number of remaining instructions
    /// that should still be generated.
    private var currentCodegenBudget = 0

    /// Whether there are any variables currently in scope.
    public var hasVisibleVariables: Bool {
        return scopeAnalyzer.visibleVariables.count > 0
    }

    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer, parent: Program?, interpreter: AbstractInterpreter?, mode: Mode) {
        self.fuzzer = fuzzer
        self.interpreter = interpreter
        self.mode = mode
        self.parent = parent
    }

    /// Resets this builder.
    public func reset() {
        numVariables = 0
        seenPropertyNames.removeAll()
        seenIntegers.removeAll()
        code.removeAll()
        types = ProgramTypes()
        scopeAnalyzer = ScopeAnalyzer()
        contextAnalyzer = ContextAnalyzer()
        interpreter?.reset()
        currentCodegenBudget = 0
    }

    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        assert(openFunctions.isEmpty)
        let program = Program(code: code, parent: parent, types: types, comments: comments)
        // TODO set type status to something meaningful?
        reset()
        return program
    }

    /// Prints the current program as FuzzIL code to stdout. Useful for debugging.
    public func dumpCurrentProgram() {
        print(FuzzILLifter().lift(code))
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
        if probability(0.15) && seenIntegers.count >= 2 {
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
        return withEqualProbability({
            chooseUniform(from: self.fuzzer.environment.interestingFloats)
        }, {
            Double.random(in: -1000000...1000000)
        })
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
    public func randVar() -> Variable {
        assert(hasVisibleVariables)
        return randVarInternal()!
    }

    /// Returns a random variable of the given type.
    ///
    /// In conservative mode, this function fails unless it finds a matching variable.
    /// In aggressive mode, this function will also return variables that have unknown type, and may, if no matching variables are available, return variables of any type.
    public func randVar(ofType type: Type) -> Variable? {
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

        if let v = randVarInternal({ self.type(of: $0).Is(wantedType) }) {
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
    public func randVar(ofConservativeType type: Type) -> Variable? {
        let oldMode = mode
        mode = .conservative
        defer { mode = oldMode }
        return randVar(ofType: type)
    }

    /// Returns a random variable satisfying the given constraints or nil if none is found.
    private func randVarInternal(_ selector: ((Variable) -> Bool)? = nil) -> Variable? {
        var candidates = [Variable]()

        // Prefer inner scopes
        withProbability(0.75) {
            candidates = chooseBiased(from: scopeAnalyzer.scopes, factor: 1.25)
            if let sel = selector {
                candidates = candidates.filter(sel)
            }
        }

        if candidates.isEmpty {
            if let sel = selector {
                candidates = scopeAnalyzer.visibleVariables.filter(sel)
            } else {
                candidates = scopeAnalyzer.visibleVariables
            }
        }

        if candidates.isEmpty {
            return nil
        }

        return chooseUniform(from: candidates)
    }


    /// Type information access.
    public func type(of v: Variable) -> Type {
        return types.getType(of: v, after: code.lastInstruction.index)
    }

    public func type(ofProperty property: String) -> Type {
        return interpreter?.type(ofProperty: property) ?? .unknown
    }

    /// Returns the type of the `super` binding at the current position.
    public func currentSuperType() -> Type {
        return interpreter?.currentSuperType() ?? .unknown
    }

    public func methodSignature(of methodName: String, on object: Variable) -> FunctionSignature {
        return interpreter?.inferMethodSignature(of: methodName, on: object) ?? FunctionSignature.forUnknownFunction
    }

    public func methodSignature(of methodName: String, on objType: Type) -> FunctionSignature {
        return interpreter?.inferMethodSignature(of: methodName, on: objType) ?? FunctionSignature.forUnknownFunction
    }

    public func setType(ofProperty propertyName: String, to propertyType: Type) {
        trace("Setting global property type: \(propertyName) => \(propertyType)")
        interpreter?.setType(ofProperty: propertyName, to: propertyType)
    }

    public func setType(ofVariable variable: Variable, to variableType: Type) {
        interpreter?.setType(of: variable, to: variableType)
    }

    public func setSignature(ofMethod methodName: String, to methodSignature: FunctionSignature) {
        trace("Setting global method signature: \(methodName) => \(methodSignature)")
        interpreter?.setSignature(ofMethod: methodName, to: methodSignature)
    }

    // This expands and collects types for arguments in function signatures.
    private func prepareArgumentTypes(forSignature signature: FunctionSignature) -> [Type] {
        var parameterTypes = signature.inputTypes
        var argumentTypes = [Type]()

        // "Expand" varargs parameters first
        if signature.hasVarargsParameter() {
            let varargsParam = parameterTypes.removeLast()
            assert(varargsParam.isList)
            for _ in 0..<Int.random(in: 0...5) {
                parameterTypes.append(varargsParam.removingFlagTypes())
            }
        }

        for var param in parameterTypes {
            if param.isOptional {
                // It's an optional argument, so stop here in some cases
                if probability(0.25) {
                    break
                }

                // Otherwise, "unwrap" the optional
                param = param.removingFlagTypes()
            }

            assert(!param.hasFlags)
            argumentTypes.append(param)
        }

        return argumentTypes
    }

    public func generateCallArguments(for signature: FunctionSignature) -> [Variable] {
        let argumentTypes = prepareArgumentTypes(forSignature: signature)
        var arguments = [Variable]()

        for argumentType in argumentTypes {
            if let v = randVar(ofConservativeType: argumentType) {
                arguments.append(v)
            } else {
                let argument = generateVariable(ofType: argumentType)
                // make sure, that now after generation we actually have a
                // variable of that type available.
                assert(randVar(ofType: argumentType) != nil)
                arguments.append(argument)
            }
        }

        return arguments
    }

    public func randCallArguments(for signature: FunctionSignature) -> [Variable]? {
        let argumentTypes = prepareArgumentTypes(forSignature: signature)
        var arguments = [Variable]()
        for argumentType in argumentTypes {
            guard let v = randVar(ofType: argumentType) else { return nil }
            arguments.append(v)
        }
        return arguments
    }

    public func randCallArguments(for function: Variable) -> [Variable]? {
        let signature = type(of: function).signature ?? FunctionSignature.forUnknownFunction
        return randCallArguments(for: signature)
    }

    public func generateCallArguments(for function: Variable) -> [Variable] {
        let signature = type(of: function).signature ?? FunctionSignature.forUnknownFunction
        return generateCallArguments(for: signature)
    }

    public func randCallArguments(forMethod methodName: String, on object: Variable) -> [Variable]? {
        let signature = methodSignature(of: methodName, on: object)
        return randCallArguments(for: signature)
    }

    public func randCallArguments(forMethod methodName: String, on objType: Type) -> [Variable]? {
        let signature = methodSignature(of: methodName, on: objType)
        return randCallArguments(for: signature)
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
    func generateVariable(ofType type: Type) -> Variable {
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

        assert(type.Is(.object()), "Unexpected type encountered \(type)")

        // The variable that we will return.
        var obj: Variable

        // Fast path for array creation.
        if type.Is(fuzzer.environment.arrayType) && probability(0.9) {
            let value = randVar()
            return createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
        }

        if let group = type.group {
            // We check this during Environment initialization, but let's keep this just in case.
            assert(fuzzer.environment.type(ofBuiltin: group) != .unknown, "We don't know how to construct \(group)")
            let constructionSignature = fuzzer.environment.type(ofBuiltin: group).constructorSignature!
            let arguments = generateCallArguments(for: constructionSignature)
            let constructor = loadBuiltin(group)
            obj = construct(constructor, withArgs: arguments)
        } else {
            // Either generate a literal or use the store property stuff.
            if probability(0.8) { // Do the literal
                var initialProperties: [String: Variable] = [:]
                // gather properties of the correct types
                for prop in type.properties {
                    var value: Variable?
                    let type = self.type(ofProperty: prop)
                    if type != .unknown {
                        value = randVar(ofConservativeType: type)
                        if value == nil {
                            value = generateVariable(ofType: type)
                        }
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
                _ = type.methods.map { initialProperties[$0] = randVar(ofType: .function())! }
                obj = createObject(with: initialProperties)
            } else { // Do it with storeProperty
                obj = construct(loadBuiltin("Object"), withArgs: [])
                for method in type.methods {
                    // TODO: This should take the method type/signature into account!
                    let methodVar = randVar(ofType: .function())
                    storeProperty(methodVar!, as: method, on: obj)
                }
                // These types might have been defined in the interpreter
                for prop in type.properties {
                    var value: Variable?
                    let type = self.type(ofProperty: prop)
                    if type != .unknown {
                        value = randVar(ofConservativeType: type)
                        if value == nil {
                            value = generateVariable(ofType: type)
                        }
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

    /// Formatted ProgramTypes structure for easier adopting of runtimeTypes
    private var runtimeTypesMaps = [[[(Variable, Type)]]]()

    /// Prepare for adoption of variables from the given program.
    ///
    /// This sets up a mapping for variables from the given program to the
    /// currently constructed one to avoid collision of variable names.
    public func beginAdoption(from program: Program) {
        varMaps.append(VariableMap())
        runtimeTypesMaps.append(program.types.onlyRuntimeTypes().indexedByInstruction(for: program))
    }

    /// Finishes the most recently started adoption.
    public func endAdoption() {
        varMaps.removeLast()
        runtimeTypesMaps.removeLast()
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
        assert(!varMaps.last!.contains(sourceVariable))
        varMaps[varMaps.count - 1][sourceVariable] = hostVariable
    }

    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt<Variables: Collection>(_ variables: Variables) -> [Variable] where Variables.Element == Variable {
        return variables.map(adopt)
    }

    private func adoptTypes(at origInstrIndex: Int) {
        for (variable, type) in runtimeTypesMaps.last![origInstrIndex] {
            // No need to keep unknown type nor type of not adopted variable
            if let adoptedVariable = varMaps.last![variable] {
                // Unknown runtime types should not be saved in ProgramTypes
                assert(type != .unknown)

                interpreter?.setType(of: adoptedVariable, to: type)
                // We should save this type even if we do not have interpreter
                // This way we can use runtime types without interpreter
                types.setType(of: adoptedVariable, to: type, after: code.lastInstruction.index, quality: .runtime)
            }
        }
    }

    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instr: Instruction, keepTypes: Bool) {
        internalAppend(Instruction(instr.op, inouts: adopt(instr.inouts)))
        if keepTypes {
            adoptTypes(at: instr.index)
        }
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
                adopt(instr, keepTypes: true)
            }
        }
    }

    /// Append a splice from another program.
    public func splice(from program: Program, at index: Int) {
        trace("Splicing instruction \(index) (\(program.code[index].op.name)) from \(program.id)")
        
        var idx = index

        // The input re-wiring algorithm modifies the code of the source program
        // to implement the manual variable mapping
        var source = program.code

        // The placeholder variable is the next free variable in the victim program.
        var nextFreeVariable = source.nextFreeVariable().number
        func makePlaceholderVariable() -> Variable {
            nextFreeVariable += 1
            return Variable(number: nextFreeVariable - 1)
        }

        // We still adopt from the input program, just with slightly modified code :)
        beginAdoption(from: program)

        // Determine all necessary input instructions for the choosen instruction
        // We need special handling for blocks:
        //   If the choosen instruction is a block instruction then copy the whole block
        //   If we need an inner output of a block instruction then only copy the block instructions, not the content
        //   Otherwise copy the whole block including its content
        var requiredInstructions = Set<Int>()
        var requiredInputs = VariableSet()

        // This maps victim instruction indices to victim : host variable remap
        // Instead of calling adopt and then using nextvar if the variable is
        // not in the varMaps map, we do the adoption manually.
        func rewireOrKeepInputs(of instr: Instruction) {
            var inputs = Array(instr.inputs)
            var neededInputs: [Variable] = []
            for (idx, input) in instr.inputs.enumerated() {
                neededInputs.append(input)
                if probability(0.2) && mode != .conservative {
                    var type = program.type(of: input, before: instr.index)
                    if type == .unknown {
                        type = .anything
                    }
                    if let hostVar = randVar(ofConservativeType: type.generalize()) {
                        let placeholderVariable = makePlaceholderVariable()
                        inputs[idx] = placeholderVariable
                        createVariableMapping(from: placeholderVariable, to: hostVar)
                        neededInputs.removeLast()
                    }
                }
            }
            // Rewrite the instruction with the new inputs only if we have modified it.
            if inputs[...] != instr.inputs {
                source.replace(instr, with: Instruction(instr.op, inouts: inputs + Array(instr.allOutputs)))
            }
            requiredInputs.formUnion(neededInputs)
            requiredInstructions.insert(instr.index)
        }

        func keep(_ instr: Instruction, includeBlockContent: Bool = false) {
            guard !requiredInstructions.contains(instr.index) else { return }
            if instr.isBlock {
                let group = BlockGroup(around: instr, in: source)
                let instructions = includeBlockContent ? group.includingContent() : group.excludingContent()
                for instr in instructions {
                    rewireOrKeepInputs(of: instr)
                }
            } else {
                rewireOrKeepInputs(of: instr)
            }
        }

        // Keep the selected instruction
        keep(program.code[idx], includeBlockContent: true)

        while idx > 0 {
            idx -= 1
            let current = source[idx]

            if !requiredInputs.isDisjoint(with: current.allOutputs) {
                let onlyNeedsInnerOutputs = requiredInputs.isDisjoint(with: current.outputs)
                // If we only need inner outputs (e.g. function parameters), then we don't include
                // the block's content in the slice. Otherwise we do.
                keep(current, includeBlockContent: !onlyNeedsInnerOutputs)
            }

            // If we perform a potentially mutating operation (such as a property store or a method call)
            // on a required variable, then we may decide to keep that instruction as well.
            if mode == .conservative || (mode == .aggressive && probability(0.5)) {
                if current.mayMutate(requiredInputs) {
                    keep(current, includeBlockContent: false)
                }
            }
        }

        for instr in source {
            if requiredInstructions.contains(instr.index) {
                adopt(instr, keepTypes: true)
            }
        }

        endAdoption()
        trace("End of splice")
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
        } while counter < 25 && (program.code[idx].isJump || program.code[idx].isBlockEnd || program.code[idx].isPrimitive || program.code[idx].isLiteral)

        splice(from: program, at: idx)
    }

    private var openFunctions = [Variable]()
    private func callLikelyRecurses(function: Variable) -> Bool {
        return openFunctions.contains(function)
    }

    /// Executes a code generator.
    ///
    /// - Parameter generators: The code generator to run at the current position.
    /// - Returns: the number of instructions added by all generators.
    public func run(_ generator: CodeGenerator, recursiveCodegenBudget: Int? = nil) {
        assert(generator.requiredContext.isSubset(of: context))

        if let budget = recursiveCodegenBudget {
            currentCodegenBudget = budget
        }

        var inputs: [Variable] = []
        for type in generator.inputTypes {
            guard let val = randVar(ofType: type) else { return }
            // In conservative mode, attempt to prevent direct recursion to reduce the number of timeouts
            // This is a very crude mechanism. It might be worth implementing a more sophisticated one.
            if mode == .conservative && type.Is(.function()) && callLikelyRecurses(function: val) { return }

            inputs.append(val)
        }

        self.trace("Executing code generator \(generator.name)")
        generator.run(in: self, with: inputs)
        self.trace("Code generator finished")
    }

    private func generateInternal() {
        assert(!fuzzer.corpus.isEmpty)

        while currentCodegenBudget > 0 {

            // There are two modes of code generation:
            // 1. Splice code from another program in the corpus
            // 2. Pick a CodeGenerator, find or generate matching variables, and execute it

            assert(performSplicingDuringCodeGeneration || hasVisibleVariables)
            withEqualProbability({
                guard self.performSplicingDuringCodeGeneration else { return }
                let program = self.fuzzer.corpus.randomElement(increaseAge: false)
                self.splice(from: program)
            }, {
                // We can't run code generators if we don't have any visible variables.
                guard self.scopeAnalyzer.visibleVariables.count > 0 else { return }
                let generator = self.fuzzer.codeGenerators.randomElement()
                if generator.requiredContext.isSubset(of: self.context) {
                    self.run(generator)
                }
            })

            // This effectively limits the size of recursively generated code fragments.
            if probability(0.25) {
                return
            }
        }
    }

    /// Generates random code at the current position.
    ///
    /// Code generation involves executing the configured code generators as well as splicing code from other
    /// programs in the corpus into the current one.
    public func generate(n: Int = 1) {
        currentCodegenBudget = n

        while currentCodegenBudget > 0 {
            generateInternal()
        }
    }

    /// Called by a code generator to generate more additional code, for example inside a newly created block.
    public func generateRecursive() {
        // Generate at least one instruction, even if already below budget
        if currentCodegenBudget <= 0 {
            currentCodegenBudget = 1
        }
        generateInternal()
    }


    //
    // Low-level instruction constructors.
    //
    // These create an instruction with the provided values and append it to the program at the current position.
    // If the instruction produces a new variable, that variable is returned to the caller.
    // Each class implementing the Operation protocol will have a constructor here.
    //

    @discardableResult
    private func perform(_ op: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        var inouts = inputs
        for _ in 0..<op.numOutputs {
            inouts.append(nextVariable())
        }
        for _ in 0..<op.numInnerOutputs {
            inouts.append(nextVariable())
        }
        let instr = Instruction(op, inouts: inouts)
        internalAppend(instr)
        return instr
    }

    @discardableResult
    public func loadInt(_ value: Int64) -> Variable {
        return perform(LoadInteger(value: value)).output
    }

    @discardableResult
    public func loadBigInt(_ value: Int64) -> Variable {
        return perform(LoadBigInt(value: value)).output
    }

    @discardableResult
    public func loadFloat(_ value: Double) -> Variable {
        return perform(LoadFloat(value: value)).output
    }

    @discardableResult
    public func loadString(_ value: String) -> Variable {
        return perform(LoadString(value: value)).output
    }

    @discardableResult
    public func loadBool(_ value: Bool) -> Variable {
        return perform(LoadBoolean(value: value)).output
    }

    @discardableResult
    public func loadUndefined() -> Variable {
        return perform(LoadUndefined()).output
    }

    @discardableResult
    public func loadNull() -> Variable {
        return perform(LoadNull()).output
    }

    @discardableResult
    public func loadRegExp(_ value: String, _ flags: RegExpFlags) -> Variable {
        return perform(LoadRegExp(value: value, flags: flags)).output
    }

    @discardableResult
    public func createObject(with initialProperties: [String: Variable]) -> Variable {
        // CreateObject expects sorted property names
        var propertyNames = [String](), propertyValues = [Variable]()
        for (k, v) in initialProperties.sorted(by: { $0.key < $1.key }) {
            propertyNames.append(k)
            propertyValues.append(v)
        }
        return perform(CreateObject(propertyNames: propertyNames), withInputs: propertyValues).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable]) -> Variable {
        return perform(CreateArray(numInitialValues: initialValues.count), withInputs: initialValues).output
    }

    @discardableResult
    public func createObject(with initialProperties: [String: Variable], andSpreading spreads: [Variable]) -> Variable {
        // CreateObjectWithgSpread expects sorted property names
        var propertyNames = [String](), propertyValues = [Variable]()
        for (k, v) in initialProperties.sorted(by: { $0.key < $1.key }) {
            propertyNames.append(k)
            propertyValues.append(v)
        }
        return perform(CreateObjectWithSpread(propertyNames: propertyNames, numSpreads: spreads.count), withInputs: propertyValues + spreads).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable], spreading spreads: [Bool]) -> Variable {
        return perform(CreateArrayWithSpread(numInitialValues: initialValues.count, spreads: spreads), withInputs: initialValues).output
    }

    @discardableResult
    public func loadBuiltin(_ name: String) -> Variable {
        return perform(LoadBuiltin(builtinName: name)).output
    }

    @discardableResult
    public func loadProperty(_ name: String, of object: Variable) -> Variable {
        return perform(LoadProperty(propertyName: name), withInputs: [object]).output
    }

    public func storeProperty(_ value: Variable, as name: String, on object: Variable) {
        perform(StoreProperty(propertyName: name), withInputs: [object, value])
    }

    public func deleteProperty(_ name: String, of object: Variable) {
        perform(DeleteProperty(propertyName: name), withInputs: [object])
    }

    @discardableResult
    public func loadElement(_ index: Int64, of array: Variable) -> Variable {
        return perform(LoadElement(index: index), withInputs: [array]).output
    }

    public func storeElement(_ value: Variable, at index: Int64, of array: Variable) {
        perform(StoreElement(index: index), withInputs: [array, value])
    }

    public func deleteElement(_ index: Int64, of array: Variable) {
        perform(DeleteElement(index: index), withInputs: [array])
    }

    @discardableResult
    public func loadComputedProperty(_ name: Variable, of object: Variable) -> Variable {
        return perform(LoadComputedProperty(), withInputs: [object, name]).output
    }

    public func storeComputedProperty(_ value: Variable, as name: Variable, on object: Variable) {
        perform(StoreComputedProperty(), withInputs: [object, name, value])
    }

    public func deleteComputedProperty(_ name: Variable, of object: Variable) {
        perform(DeleteComputedProperty(), withInputs: [object, name])
    }

    @discardableResult
    public func doTypeof(_ v: Variable) -> Variable {
        return perform(TypeOf(), withInputs: [v]).output
    }

    @discardableResult
    public func doInstanceOf(_ v: Variable, _ type: Variable) -> Variable {
        return perform(InstanceOf(), withInputs: [v, type]).output
    }

    @discardableResult
    public func doIn(_ prop: Variable, _ obj: Variable) -> Variable {
        return perform(In(), withInputs: [prop, obj]).output
    }

    @discardableResult
    public func definePlainFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginPlainFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndPlainFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineStrictFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginStrictFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndStrictFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineArrowFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginArrowFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndArrowFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineGeneratorFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginGeneratorFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndGeneratorFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineAsyncFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginAsyncFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndAsyncFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineAsyncArrowFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginAsyncArrowFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndAsyncArrowFunctionDefinition())
        return instr.output
    }

    @discardableResult
    public func defineAsyncGeneratorFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instr = perform(BeginAsyncGeneratorFunctionDefinition(signature: signature))
        body(Array(instr.innerOutputs))
        perform(EndAsyncGeneratorFunctionDefinition())
        return instr.output
    }

    public func doReturn(value: Variable) {
        perform(Return(), withInputs: [value])
    }

    public func yield(value: Variable) {
        perform(Yield(), withInputs: [value])
    }

    public func yieldEach(value: Variable) {
        perform(YieldEach(), withInputs: [value])
    }

    @discardableResult
    public func await(value: Variable) -> Variable {
        return perform(Await(), withInputs: [value]).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable]) -> Variable {
        return perform(CallMethod(methodName: name, numArguments: arguments.count), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable]) -> Variable {
        return perform(CallComputedMethod(numArguments: arguments.count), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable]) -> Variable {
        return perform(CallFunction(numArguments: arguments.count), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable]) -> Variable {
        return perform(Construct(numArguments: arguments.count), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        return perform(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func unary(_ op: UnaryOperator, _ input: Variable) -> Variable {
        return perform(UnaryOperation(op), withInputs: [input]).output
    }

    @discardableResult
    public func binary(_ lhs: Variable, _ rhs: Variable, with op: BinaryOperator) -> Variable {
        return perform(BinaryOperation(op), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func dup(_ v: Variable) -> Variable {
        return perform(Dup(), withInputs: [v]).output
    }

    public func reassign(_ output: Variable, to input: Variable) {
        perform(Reassign(), withInputs: [output, input])
    }

    @discardableResult
    public func compare(_ lhs: Variable, _ rhs: Variable, with comparator: Comparator) -> Variable {
        return perform(Compare(comparator), withInputs: [lhs, rhs]).output
    }

    public func eval(_ string: String, with arguments: [Variable] = []) {
        perform(Eval(string, numArguments: arguments.count), withInputs: arguments)
    }

    public func with(_ scopeObject: Variable, body: () -> Void) {
        perform(BeginWith(), withInputs: [scopeObject])
        body()
        perform(EndWith())
    }

    @discardableResult
    public func loadFromScope(id: String) -> Variable {
        return perform(LoadFromScope(id: id)).output
    }

    public func storeToScope(_ value: Variable, as id: String) {
        perform(StoreToScope(id: id), withInputs: [value])
    }

    public func nop(numOutputs: Int = 0) {
        perform(Nop(numOutputs: numOutputs), withInputs: [])
    }

    public struct ClassBuilder {
        public typealias MethodBodyGenerator = ([Variable]) -> ()
        public typealias ConstructorBodyGenerator = MethodBodyGenerator

        fileprivate var constructor: (parameters: [Type], generator: ConstructorBodyGenerator)? = nil
        fileprivate var methods: [(name: String, signature: FunctionSignature, generator: ConstructorBodyGenerator)] = []
        fileprivate var properties: [String] = []

        // This struct is only created by defineClass below
        fileprivate init() {}

        public mutating func defineConstructor(withParameters parameters: [Type], _ generator: @escaping ConstructorBodyGenerator) {
            constructor = (parameters, generator)
        }

        public mutating func defineProperty(_ name: String) {
            properties.append(name)
        }

        public mutating func defineMethod(_ name: String, withSignature signature: FunctionSignature, _ generator: @escaping MethodBodyGenerator) {
            methods.append((name, signature, generator))
        }
    }

    public typealias ClassBodyGenerator = (inout ClassBuilder) -> ()

    @discardableResult
    public func defineClass(withSuperclass superclass: Variable? = nil,
                            _ body: ClassBodyGenerator) -> Variable {
        // First collect all information about the class and the generators for constructor and method bodies
        var builder = ClassBuilder()
        body(&builder)

        // Now compute the instance type and define the class
        let properties = builder.properties
        let methods = builder.methods.map({ ($0.name, $0.signature )})
        let constructorParameters = builder.constructor?.parameters ?? FunctionSignature.forUnknownFunction.inputTypes
        let hasSuperclass = superclass != nil
        let classDefinition = perform(BeginClassDefinition(hasSuperclass: hasSuperclass,
                                                           constructorParameters: constructorParameters,
                                                           instanceProperties: properties,
                                                           instanceMethods: methods),
                                      withInputs: hasSuperclass ? [superclass!] : [])

        // The code directly following the BeginClassDefinition is the body of the constructor
        builder.constructor?.generator(Array(classDefinition.innerOutputs))

        // Next are the bodies of the methods
        for method in builder.methods {
            let methodDefinition = perform(BeginMethodDefinition(numParameters: method.signature.inputTypes.count), withInputs: [])
            method.generator(Array(methodDefinition.innerOutputs))
        }

        perform(EndClassDefinition())

        return classDefinition.output
    }

    public func callSuperConstructor(withArgs arguments: [Variable]) {
        perform(CallSuperConstructor(numArguments: arguments.count), withInputs: arguments)
    }

    @discardableResult
    public func callSuperMethod(_ name: String, withArgs arguments: [Variable]) -> Variable {
        return perform(CallSuperMethod(methodName: name, numArguments: arguments.count), withInputs: arguments).output
    }

    @discardableResult
    public func loadSuperProperty(_ name: String) -> Variable {
        return perform(LoadSuperProperty(propertyName: name)).output
    }

    public func storeSuperProperty(_ value: Variable, as name: String) {
        perform(StoreSuperProperty(propertyName: name), withInputs: [value])
    }

    public func beginIf(_ conditional: Variable, _ body: () -> Void) {
        perform(BeginIf(), withInputs: [conditional])
        body()
    }

    public func beginElse(_ body: () -> Void) {
        perform(BeginElse())
        body()
    }

    public func endIf() {
        perform(EndIf())
    }

    public func whileLoop(_ lhs: Variable, _ comparator: Comparator, _ rhs: Variable, _ body: () -> Void) {
        perform(BeginWhile(comparator: comparator), withInputs: [lhs, rhs])
        body()
        perform(EndWhile())
    }

    public func doWhileLoop(_ lhs: Variable, _ comparator: Comparator, _ rhs: Variable, _ body: () -> Void) {
        perform(BeginDoWhile(comparator: comparator), withInputs: [lhs, rhs])
        body()
        perform(EndDoWhile())
    }

    public func forLoop(_ start: Variable, _ comparator: Comparator, _ end: Variable, _ op: BinaryOperator, _ rhs: Variable, _ body: (Variable) -> ()) {
        let i = perform(BeginFor(comparator: comparator, op: op), withInputs: [start, end, rhs]).innerOutput
        body(i)
        perform(EndFor())
    }

    public func forInLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = perform(BeginForIn(), withInputs: [obj]).innerOutput
        body(i)
        perform(EndForIn())
    }

    public func forOfLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = perform(BeginForOf(), withInputs: [obj]).innerOutput
        body(i)
        perform(EndForOf())
    }

    public func doBreak() {
        perform(Break(), withInputs: [])
    }

    public func doContinue() {
        perform(Continue(), withInputs: [])
    }

    public func beginTry(_ body: () -> Void) {
        perform(BeginTry())
        body()
    }

    public func beginCatch(_ body: (Variable) -> ()) {
        let exception = perform(BeginCatch()).innerOutput
        body(exception)
    }

    public func beginFinally(_ body: () -> Void) {
        perform(BeginFinally())
        body()
    }

    public func endTryCatch() {
        perform(EndTryCatch())
    }

    public func throwException(_ value: Variable) {
        perform(ThrowException(), withInputs: [value])
    }

    public func codeString(_ body: () -> Variable) -> Variable {
        let instr = perform(BeginCodeString())
        let returnValue = body()
        perform(EndCodeString(), withInputs: [returnValue])
        return instr.output
    }

    public func blockStatement(_ body: () -> Void) {
        perform(BeginBlockStatement())
        body()
        perform(EndBlockStatement())
    }

    public func doPrint(_ value: Variable) {
        perform(Print(), withInputs: [value])
    }


    /// Returns the next free variable.
    func nextVariable() -> Variable {
        assert(numVariables < Code.maxNumberOfVariables, "Too many variables")
        numVariables += 1
        return Variable(number: numVariables - 1)
    }

    private func internalAppend(_ instr: Instruction) {
        // Basic integrity checking
        assert(!instr.inouts.contains(where: { $0.number >= numVariables }))

        code.append(instr)

        currentCodegenBudget -= 1

        // Update our analyses
        scopeAnalyzer.analyze(instr)
        contextAnalyzer.analyze(instr)
        if instr.op is BeginAnyFunctionDefinition {
            openFunctions.append(instr.output)
        } else if instr.op is EndAnyFunctionDefinition {
            openFunctions.removeLast()
        }

        // Update type information
        let typeChanges = interpreter?.execute(instr) ?? []
        for (variable, type) in typeChanges {
            assert(scopeAnalyzer.visibleVariables.contains(variable))
            // We should record only changes when type really changes
            // But we cannot distinguish following changes because .unknown is default type:
            // 1. nil -> .unknown
            // 2. .unknwon -> .unknown
            assert(type != types.getType(of: variable, after: code.lastInstruction.index) || type == .unknown)
            types.setType(of: variable, to: type, after: code.lastInstruction.index, quality: .inferred)
        }

        updateConstantPool(instr.op)
    }

    /// Update the set of previously seen property names and integer values with the provided operation.
    private func updateConstantPool(_ operation: Operation) {
        switch operation {
        case let op as LoadInteger:
            seenIntegers.insert(op.value)
        case let op as LoadBigInt:
            seenIntegers.insert(op.value)
        case let op as LoadProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as StoreProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as DeleteProperty:
            seenPropertyNames.insert(op.propertyName)
        case let op as LoadElement:
            seenIntegers.insert(op.index)
        case let op as StoreElement:
            seenIntegers.insert(op.index)
        case let op as DeleteElement:
            seenIntegers.insert(op.index)
        case let op as CreateObject:
            seenPropertyNames.formUnion(op.propertyNames)
        default:
            break
        }
    }
}
