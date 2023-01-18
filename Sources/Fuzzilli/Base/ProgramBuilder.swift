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

    /// Every code generator that contributed to the current program.
    private var contributors = Contributors()

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

    /// Stack of active object literals.
    ///
    /// This needs to be a stack as object literals can be nested, for example if an object
    /// literals is created inside a method/getter/setter of another object literals.
    private var activeObjectLiterals = Stack<ObjectLiteral>()

    /// When building object literals, the state for the current literal is exposed through this member and
    /// can be used to add fields to the literal or to determine if some field already exists.
    public var currentObjectLiteral: ObjectLiteral {
        return activeObjectLiterals.top
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
        code.removeAll()
        comments.removeAll()
        contributors.removeAll()
        numVariables = 0
        loadedBuiltins.removeAll()
        loadedIntegers.removeAll()
        loadedFloats.removeAll()
        scopeAnalyzer = ScopeAnalyzer()
        contextAnalyzer = ContextAnalyzer()
        jsTyper.reset()
        activeObjectLiterals.removeAll()
    }

    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        assert(openFunctions.isEmpty)
        let program = Program(code: code, parent: parent, comments: comments, contributors: contributors)
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
    public func randInt() -> Int64 {
        if probability(0.5) {
            return chooseUniform(from: fuzzer.environment.interestingIntegers)
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

    /// Returns a random integer value suitable as index.
    public func randIndex() -> Int64 {
        // Prefer small, (usually) positive, indices.
        if probability(0.5) {
            return Int64.random(in: -2...10)
        } else {
            return randInt()
        }
    }

    /// Returns a random floating point value.
    public func randFloat() -> Double {
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
    public func randString() -> String {
        return withEqualProbability({
            self.randPropertyForReading()
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingStrings)
        }, {
            String(self.randInt())
        }, {
            String.random(ofLength: Int.random(in: 2...10))
        }, {
            String.random(ofLength: 1)
        })
    }

    /// Returns a random regular expression pattern.
    public func randRegExpPattern() -> String {
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
            regex += randRegExpPattern()
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

    /// Returns the name of a random builtin.
    public func randBuiltin() -> String {
        return chooseUniform(from: fuzzer.environment.builtins)
    }

    /// Returns the name of a random property suitable for read access.
    public func randPropertyForReading() -> String {
        return chooseUniform(from: fuzzer.environment.readableProperties)
    }

    /// Returns the name of a random property suitable for write access.
    public func randPropertyForWriting() -> String {
        return chooseUniform(from: fuzzer.environment.writableProperties)
    }

    /// Returns the name of a random property suitable for defining on new objects.
    public func randPropertyForDefining() -> String {
        if probability(0.5) {
            return randPropertyForWriting()
        } else {
            return chooseUniform(from: fuzzer.environment.customProperties)
        }
    }

    /// Returns the name of a random method.
    public func randMethod() -> String {
        return chooseUniform(from: fuzzer.environment.methods)
    }

    /// Returns the name of a random method suitable for defining on new objects.
    public func randMethodForDefining() -> String {
        if probability(0.10) {
            // TODO should there be a environment.writableMethods that includes the custom method
            // names and things like valueOf, etc. Maybe it's ok since they are in writableProperties...
            return randMethod()
        } else {
            return chooseUniform(from: fuzzer.environment.customMethods)
        }
    }


    ///
    /// Access to variables.
    ///

    /// Returns a random variable.
    public func randVar(excludeInnermostScope: Bool = false) -> Variable {
        assert(hasVisibleVariables)
        return randVarInternal(excludeInnermostScope: excludeInnermostScope)!
    }

    /// Returns up to N (different) random variables.
    /// This method will only return fewer than N variables if the number of currently visible variables is less than N.
    public func randVars(upTo n: Int) -> [Variable] {
        assert(hasVisibleVariables)
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
    public func generateFunctionParameters() -> SubroutineDescriptor {
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
                assert(randVar(ofType: argumentType) != nil)
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
            return loadInt(randInt())
        }
        if type.Is(.float) || type.Is(fuzzer.environment.floatType) {
            return loadFloat(randFloat())
        }
        if type.Is(.string) || type.Is(fuzzer.environment.stringType) {
            return loadString(randString())
        }
        if type.Is(.regexp) || type.Is(fuzzer.environment.regExpType) {
            return loadRegExp(randRegExpPattern(), RegExpFlags.random())
        }
        if type.Is(.boolean) || type.Is(fuzzer.environment.booleanType) {
            return loadBool(Bool.random())
        }
        if type.Is(.bigint) || type.Is(fuzzer.environment.bigIntType) {
            return loadBigInt(randInt())
        }
        if type.Is(.function()) {
            let signature = type.signature ?? Signature(withParameterCount: Int.random(in: 2...5), hasRestParam: probability(0.1))
            return buildPlainFunction(with: .signature(signature), isStrict: probability(0.1)) { _ in
                doReturn(randVar())
            }
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
            // Objects with predefined groups must be constructable through a Builtin exposed by the Environment.
            // Normally, that builtin is a .constructor(), but we also allow just a .function() for constructing object.
            // This is for example necessary for JavaScript Symbols, as the Symbol builtin is not a constructor.
            let constructorType = fuzzer.environment.type(ofBuiltin: group)
            assert(constructorType.Is(.function() | .constructor()), "We don't know how to construct \(group)")
            assert(constructorType.signature != nil, "We don't know how to construct \(group) (missing signature for constructor)")
            assert(constructorType.signature!.outputType.group == group, "We don't know how to construct \(group) (invalid signature for constructor)")

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
                            value = loadInt(randInt())
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

    // Probabilities of remapping variables to host variables during splicing. These are writable so they can be reconfigured for testing.
    // We use different probabilities for outer and for inner outputs: while we rarely want to replace outer outputs, we frequently want to replace inner outputs
    // (e.g. function parameters) to avoid splicing function definitions that may then not be used at all. Instead, we prefer to splice only the body of such functions.
    var probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 0.10
    var probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing = 0.75
    // The probability of including an instruction that may mutate a variable required by the slice (but does not itself produce a required variable).
    var probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 0.5


    /// Splice code from the given program into the current program.
    ///
    /// Splicing computes a set of dependend (through dataflow) instructions in one program (called a "slice") and inserts it at the current position in this program.
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

            let openedContext: Context
            var requiredContext: Context

            var providedInputs = VariableSet()
            var requiredInputs = VariableSet()

            init(startedBy head: Instruction) {
                self.startIndex = head.index
                self.openedContext = head.op.contextOpened
                self.requiredContext = head.op.requiredContext
                self.requiredInputs.formUnion(head.inputs)
                self.providedInputs.formUnion(head.allOutputs)
            }
        }

        //
        // Step (1): compute the context and data-flow dependencies of every block.
        //
        var blocks = [Int: Block]()

        // Helper functions for step (1).
        var activeBlocks = [Block]()
        func updateBlockDependencies(_ requiredContext: Context, _ requiredInputs: VariableSet) {
            guard let current = activeBlocks.last else { return }
            current.requiredContext.formUnion(requiredContext.subtracting(current.openedContext))
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
        func tryRemapVariables(_ variables: ArraySlice<Variable>) {
            guard mergeDataFlow else { return }

            for v in variables {
                let type = typer.type(of: v)
                // Find a compatible (i.e. one of the same type) variable in the host program.
                // If that doesn't work, either because we don't know the type or because there is no matching variable, then take a random variable unless we're in conservative building mode.
                var maybeReplacement: Variable? = nil
                if type != .unknown, let compatibleVariable = randVar(ofConservativeType: type.generalize()) {
                    maybeReplacement = compatibleVariable
                } else if mode != .conservative && hasVisibleVariables {
                    maybeReplacement = randVar()
                }
                if let replacement = maybeReplacement {
                    remappedVariables[v] = replacement
                    availableVariables.insert(v)
                }
            }
        }
        func maybeRemapVariables(_ variables: ArraySlice<Variable>, withProbability remapProbability: Double) {
            assert(remapProbability >= 0.0 && remapProbability <= 1.0)
            if probability(remapProbability) {
                tryRemapVariables(variables)
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
        func canSpliceOperation(of instr: Instruction) -> Bool {
            // Switch default cases cannot be spliced as there must only be one of them in a switch, and there is no
            // way to determine if the switch being spliced into has a default case or not.
            // TODO: consider adding an Operation.Attribute for instructions that must only occur once if there are more such cases in the future.
            var instr = instr
            if let block = blocks[instr.index] {
                instr = program.code[block.startIndex]
            }
            if instr.op is BeginSwitchDefaultCase {
                return false
            }
            return true
        }

        for instr in program.code {
            // Compute variable types to be able to find compatible replacement variables in the host program if necessary.
            typer.analyze(instr)

            // Maybe remap the outputs of this instruction to existing and "compatible" (because of their type) variables in the host program.
            maybeRemapVariables(instr.outputs, withProbability: probabilityOfRemappingAnInstructionsOutputsDuringSplicing)
            maybeRemapVariables(instr.innerOutputs, withProbability: probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing)

            // For the purpose of this step, blocks are treated as a single instruction with all the context and input requirements of the
            // instructions in their body. This is done through the getRequirements function which uses the data computed in step (1).
            let (requiredContext, requiredInputs) = getRequirements(of: instr)

            if requiredContext.isSubset(of: context) && requiredInputs.isSubset(of: availableVariables) && canSpliceOperation(of: instr) {
                candidates.insert(instr.index)
                // This instruction is available, and so are its outputs...
                availableVariables.formUnion(instr.allOutputs)
            } else {
                // While we cannot include this instruction, we may still be able to replace its outputs with existing variables in the host program
                // which will allow other instructions that depend on these outputs to be included.
                tryRemapVariables(instr.allOutputs)
            }
        }

        //
        // Step (3): select the "root" instruction of the slice or use the provided one if any.
        //
        // Simple optimization: avoid splicing data-flow "roots", i.e. simple instructions that don't have any inputs, as this will
        // most of the time result in fairly uninteresting splices that for example just copy a literal from another program.
        // The exception to this are special instructions that exist outside of JavaScript context, for example instructions that add fields to classes.
        let rootCandidates = candidates.filter({ !program.code[$0].isSimple || program.code[$0].numInputs > 0 || !program.code[$0].op.requiredContext.contains(.javascript) })
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
            append(Instruction(instr.op, inouts: inouts))
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

    /// The first "knob": this mainly determines the shape of generated code as it determines how large block bodies are relative to their surrounding code.
    /// This also influences the nesting depth of the generated code, as recursive code generators are only invoked if enough "budget" is still available.
    /// These are writable so they can be reconfigured in tests.
    var minRecursiveBudgetRelativeToParentBudget = 0.05
    var maxRecursiveBudgetRelativeToParentBudget = 0.50

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

    private var openFunctions = [Variable]()
    private func callLikelyRecurses(function: Variable) -> Bool {
        return openFunctions.contains(function)
    }

    // Keeps track of the state of one buildInternal() invocation. These are tracked in a stack, one entry for each recursive call.
    // This is a class so that updating the currently active state is possible without push/pop.
    private class BuildingState {
        let initialBudget: Int
        let mode: BuildingMode
        var recursiveBuildingAllowed = true
        var nextRecursiveBlockOfCurrentGenerator = 1
        var totalRecursiveBlocksOfCurrentGenerator: Int? = nil

        init(initialBudget: Int, mode: BuildingMode) {
            assert(initialBudget > 0)
            self.initialBudget = initialBudget
            self.mode = mode
        }
    }
    private var buildStack = Stack<BuildingState>()

    /// Build random code at the current position in the program.
    ///
    /// The first parameter controls the number of emitted instructions: as soon as more than that number of instructions have been emitted, building stops.
    /// This parameter is only a rough estimate as recursive code generators may lead to significantly more code being generated.
    /// Typically, the actual number of generated instructions will be somewhere between n and 2x n.
    public func build(n: Int = 1, by mode: BuildingMode = .generatingAndSplicing) {
        assert(buildStack.isEmpty)
        buildInternal(initialBuildingBudget: n, mode: mode)
        assert(buildStack.isEmpty)
    }

    /// Recursive code building. Used by CodeGenerators for example to fill the bodies of generated blocks.
    public func buildRecursive(block: Int = 1, of numBlocks: Int = 1, n optionalBudget: Int? = nil) {
        assert(!buildStack.isEmpty)
        let parentState = buildStack.top

        assert(parentState.mode != .splicing)
        assert(parentState.recursiveBuildingAllowed)        // If this fails, a recursive CodeGenerator is probably not marked as recursive.
        assert(numBlocks >= 1)
        assert(block >= 1 && block <= numBlocks)
        assert(parentState.nextRecursiveBlockOfCurrentGenerator == block)
        assert((parentState.totalRecursiveBlocksOfCurrentGenerator ?? numBlocks) == numBlocks)

        parentState.nextRecursiveBlockOfCurrentGenerator = block + 1
        parentState.totalRecursiveBlocksOfCurrentGenerator = numBlocks

        // Determine the budget for this recursive call as a fraction of the parent's initial budget.
        let factor = Double.random(in: minRecursiveBudgetRelativeToParentBudget...maxRecursiveBudgetRelativeToParentBudget)
        assert(factor > 0.0 && factor < 1.0)
        let parentBudget = parentState.initialBudget
        var recursiveBudget = Double(parentBudget) * factor

        // Now split the budget between all sibling blocks.
        recursiveBudget /= Double(numBlocks)
        recursiveBudget.round(.up)
        assert(recursiveBudget >= 1.0)

        // Finally, if a custom budget was requested, choose the smaller of the two values.
        if let requestedBudget = optionalBudget {
            assert(requestedBudget > 0)
            recursiveBudget = min(recursiveBudget, Double(requestedBudget))
        }

        buildInternal(initialBuildingBudget: Int(recursiveBudget), mode: parentState.mode)
    }

    private func buildInternal(initialBuildingBudget: Int, mode: BuildingMode) {
        assert(initialBuildingBudget > 0)

        // Both splicing and code generation can sometimes fail, for example if no other program with the necessary features exists.
        // To avoid infinite loops, we bail out after a certain number of consecutive failures.
        var consecutiveFailures = 0

        let state = BuildingState(initialBudget: initialBuildingBudget, mode: mode)
        buildStack.push(state)
        defer { buildStack.pop() }
        var remainingBudget = initialBuildingBudget

        // Unless we are only splicing, find all generators that have the required context. We must always have at least one suitable code generator.
        let origContext = context
        var availableGenerators = WeightedList<CodeGenerator>()
        if state.mode != .splicing {
            availableGenerators = fuzzer.codeGenerators.filter({ $0.requiredContext.isSubset(of: origContext) })
            assert(!availableGenerators.isEmpty)
        }

        // Code generators assume that there are visible variables that they can use. Futhermore, splicing also benefits
        // from having existing variables to which variables in the slice can be rewired to.
        // So if there are no visible variables, try to generate some first.
        if !hasVisibleVariables {
            guard context.contains(.javascript) else {
                // This can sometimes happen, for example when trying to generate code in an empty object literal at the start of a program.
                // There's not much we can do here, so just give up.
                return
            }
            let valuesToGenerate = Int.random(in: 1...3)
            for _ in 0..<valuesToGenerate {
                remainingBudget -= run(chooseUniform(from: fuzzer.trivialCodeGenerators))
            }
            assert(hasVisibleVariables)
        }

        while remainingBudget > 0 {
            assert(context == origContext, "Code generation or splicing must not change the current context")

            if state.recursiveBuildingAllowed &&
                remainingBudget < ProgramBuilder.minBudgetForRecursiveCodeGeneration &&
                availableGenerators.contains(where: { !$0.isRecursive }) {
                // No more recursion at this point since the remaining budget is too small.
                state.recursiveBuildingAllowed = false
                availableGenerators = availableGenerators.filter({ !$0.isRecursive })
                assert(state.mode == .splicing || !availableGenerators.isEmpty)
            }

            var mode = state.mode
            if mode == .generatingAndSplicing {
                mode = chooseUniform(from: [.generating, .splicing])
            }

            let codeSizeBefore = code.count
            switch mode {
            case .generating:
                assert(hasVisibleVariables)

                // Reset the code generator specific part of the state.
                state.nextRecursiveBlockOfCurrentGenerator = 1
                state.totalRecursiveBlocksOfCurrentGenerator = nil

                // Select a random generator and run it.
                let generator = availableGenerators.randomElement()
                run(generator)

            case .splicing:
                let program = fuzzer.corpus.randomElementForSplicing()
                splice(from: program)

            default:
                fatalError("Unknown ProgramBuildingMode \(mode)")
            }
            let codeSizeAfter = code.count

            let emittedInstructions = codeSizeAfter - codeSizeBefore
            remainingBudget -= emittedInstructions
            if emittedInstructions > 0 {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                guard consecutiveFailures < 10 else {
                    // This should happen very rarely, for example if we're splicing into a restricted context and don't find
                    // another sample with instructions that can be copied over, or if we get very unlucky with the code generators.
                    return
                }
            }
        }
    }

    /// Runs a code generator in the current context and returns the number of generated instructions.
    @discardableResult
    public func run(_ generator: CodeGenerator) -> Int {
        assert(generator.requiredContext.isSubset(of: context))

        var inputs: [Variable] = []
        for type in generator.inputTypes {
            // TODO should this generate variables in conservative mode?
            guard let val = randVar(ofType: type) else { return 0 }
            // In conservative mode, attempt to prevent direct recursion to reduce the number of timeouts
            // This is a very crude mechanism. It might be worth implementing a more sophisticated one.
            if mode == .conservative && type.Is(.function()) && callLikelyRecurses(function: val) { return 0 }

            inputs.append(val)
        }

        trace("Executing code generator \(generator.name)")
        let numGeneratedInstructions = generator.run(in: self, with: inputs)
        trace("Code generator finished")

        if numGeneratedInstructions > 0 {
            contributors.add(generator)
            generator.addedInstructions(numGeneratedInstructions)
        }
        return numGeneratedInstructions
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

    public func reuseOrLoadFloat(_ value: Double) -> Variable {
        for v in scopeAnalyzer.visibleVariables {
            if let val = loadedFloats[v], val == value {
                return v
            }
        }
        return loadFloat(value)
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
    public func loadRegExp(_ pattern: String, _ flags: RegExpFlags) -> Variable {
        return emit(LoadRegExp(pattern: pattern, flags: flags)).output
    }

    /// Represents a currently active object literal. Used to add fields to it and to query which fields already exist.
    public class ObjectLiteral {
        private let b: ProgramBuilder

        fileprivate var existingProperties: [String] = []
        fileprivate var existingElements: [Int64] = []
        fileprivate var existingComputedProperties: [Variable] = []
        fileprivate var existingMethods: [String] = []
        fileprivate var existingGetters: [String] = []
        fileprivate var existingSetters: [String] = []

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.objectLiteral))
            self.b = b
        }

        public func hasProperty(_ name: String) -> Bool {
            return existingProperties.contains(name)
        }

        public func hasElement(_ index: Int64) -> Bool {
            return existingElements.contains(index)
        }

        public func hasComputedProperty(_ name: Variable) -> Bool {
            return existingComputedProperties.contains(name)
        }

        public func hasMethod(_ name: String) -> Bool {
            return existingMethods.contains(name)
        }

        public func hasGetter(for name: String) -> Bool {
            return existingGetters.contains(name)
        }

        public func hasSetter(for name: String) -> Bool {
            return existingSetters.contains(name)
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
        public func addMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setSignatureForNextFunction(descriptor.signature)
            let instr = b.emit(BeginObjectLiteralMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndObjectLiteralMethod())
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

        public fileprivate(set) var hasConstructor = false
        fileprivate var existingInstanceProperties: [String] = []
        fileprivate var existingInstanceElements: [Int64] = []
        fileprivate var existingInstanceComputedProperties: [Variable] = []
        fileprivate var existingInstanceMethods: [String] = []
        fileprivate var existingInstanceGetters: [String] = []
        fileprivate var existingInstanceSetters: [String] = []

        fileprivate var existingStaticProperties: [String] = []
        fileprivate var existingStaticElements: [Int64] = []
        fileprivate var existingStaticComputedProperties: [Variable] = []
        fileprivate var existingStaticMethods: [String] = []
        fileprivate var existingStaticGetters: [String] = []
        fileprivate var existingStaticSetters: [String] = []

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.classDefinition))
            self.b = b
        }

        public func hasInstanceProperty(_ name: String) -> Bool {
            return existingInstanceProperties.contains(name)
        }

        public func hasInstanceElement(_ index: Int64) -> Bool {
            return existingInstanceElements.contains(index)
        }

        public func hasInstanceComputedProperty(_ v: Variable) -> Bool {
            return existingInstanceComputedProperties.contains(v)
        }

        public func hasInstanceMethod(_ name: String) -> Bool {
            return existingInstanceMethods.contains(name)
        }

        public func hasInstanceGetter(for name: String) -> Bool {
            return existingInstanceGetters.contains(name)
        }

        public func hasInstanceSetter(for name: String) -> Bool {
            return existingInstanceSetters.contains(name)
        }

        public func hasStaticProperty(_ name: String) -> Bool {
            return existingStaticProperties.contains(name)
        }

        public func hasStaticElement(_ index: Int64) -> Bool {
            return existingStaticElements.contains(index)
        }

        public func hasStaticComputedProperty(_ v: Variable) -> Bool {
            return existingStaticComputedProperties.contains(v)
        }

        public func hasStaticMethod(_ name: String) -> Bool {
            return existingStaticMethods.contains(name)
        }

        public func hasStaticGetter(for name: String) -> Bool {
            return existingStaticGetters.contains(name)
        }

        public func hasStaticSetter(for name: String) -> Bool {
            return existingStaticSetters.contains(name)
        }

        public func addConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setSignatureForNextFunction(descriptor.signature)
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
            b.setSignatureForNextFunction(descriptor.signature)
            let instr = b.emit(BeginClassInstanceMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassInstanceMethod())
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
            b.setSignatureForNextFunction(descriptor.signature)
            let instr = b.emit(BeginClassStaticMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassStaticMethod())
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
    }

    @discardableResult
    public func buildClassDefinition(withSuperclass superclass: Variable? = nil, _ body: (ClassDefinition) -> ()) -> Variable {
        let inputs = superclass != nil ? [superclass!] : []
        let output = emit(BeginClassDefinition(hasSuperclass: superclass != nil), withInputs: inputs).output
        body(currentClassDefinition)
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

    public func probe(_ v: Variable, id: String) {
        emit(Probe(id: id), withInputs: [v])
    }

    // Helper struct to describe subroutine definitions.
    // This allows defining functions just through the number of parameters or through a Signature, which also contains parameter types.
    // Note however that FunctionSignatures are not associated with the generated operations and will therefore just be valid for the lifetime
    // of this ProgramBuilder. The reason for this behaviour is that it is generally not possible to preserve the type informatio across program
    // mutations (a mutator may change the callsite of a function or modify the uses of a parameter, effectively invalidating the signature).
    public struct SubroutineDescriptor {
        fileprivate let parameters: Parameters
        fileprivate let signature: Signature?

        public static func parameters(n: Int, hasRestParameter: Bool = false) -> SubroutineDescriptor {
            return SubroutineDescriptor(Parameters(count: n, hasRestParameter: hasRestParameter))
        }

        public static func parameters(_ inputTypes: [Signature.Parameter]) -> SubroutineDescriptor {
            let signature = inputTypes => .unknown
            return .signature(signature)
        }

        public static func signature(_ signature: Signature) -> SubroutineDescriptor {
            let parameters = Parameters(count: signature.numParameters, hasRestParameter: signature.hasRestParameter)
            return SubroutineDescriptor(parameters, signature)
        }

        private init(_ parameters: Parameters, _ signature: Signature? = nil) {
            self.parameters = parameters
            self.signature = signature
            assert(signature == nil || signature?.numParameters == parameters.count)
        }
    }

    @discardableResult
    public func buildPlainFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginPlainFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndPlainFunction())
        return instr.output
    }

    @discardableResult
    public func buildArrowFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildGeneratorFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncArrowFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncGeneratorFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginAsyncGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) -> Variable {
        setSignatureForNextFunction(descriptor.signature)
        let instr = emit(BeginConstructor(parameters: descriptor.parameters))
        body(Array(instr.innerOutputs))
        emit(EndConstructor())
        return instr.output
    }

    public func doReturn(_ value: Variable) {
        emit(Return(), withInputs: [value])
    }

    @discardableResult
    public func yield(_ value: Variable) -> Variable {
        return emit(Yield(), withInputs: [value]).output
    }

    public func yieldEach(_ value: Variable) {
        emit(YieldEach(), withInputs: [value])
    }

    @discardableResult
    public func await(_ value: Variable) -> Variable {
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
    public func ternary(_ condition: Variable, _ lhs: Variable, _ rhs: Variable) -> Variable {
        return emit(TernaryOperation(), withInputs: [condition, lhs, rhs]).output
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

    public struct SwitchBuilder {
        public typealias SwitchCaseGenerator = () -> ()
        fileprivate var caseGenerators: [(value: Variable?, fallsthrough: Bool, body: SwitchCaseGenerator)] = []
        var hasDefault: Bool = false

        public mutating func addDefault(fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            assert(!hasDefault, "Cannot add more than one default case")
            hasDefault = true
            caseGenerators.append((nil, fallsThrough, body))
        }

        public mutating func add(_ v: Variable, fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            caseGenerators.append((v, fallsThrough, body))
        }
    }

    public func buildSwitch(on switchVar: Variable, body: (inout SwitchBuilder) -> ()) {
        emit(BeginSwitch(), withInputs: [switchVar])

        var builder = SwitchBuilder()
        body(&builder)

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

    public func buildForOfLoop(_ obj: Variable, selecting indices: [Int64], hasRestElement: Bool = false, _ body: ([Variable]) -> ()) {
        let instr = emit(BeginForOfWithDestructLoop(indices: indices, hasRestElement: hasRestElement), withInputs: [obj])
        body(Array(instr.innerOutputs))
        emit(EndForOfLoop())
    }

    public func buildRepeat(n numIterations: Int, _ body: (Variable) -> ()) {
        let i = emit(BeginRepeatLoop(iterations: numIterations)).innerOutput
        body(i)
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

    /// Set the signature for the next function, method, or constructor, which must be the the start of a function or method definition.
    /// Function/method signatures are only valid for the duration of the program generation, as they cannot be preserved across mutations.
    /// As such, these signatures are linked to their instruction through the index of the instruction in the program.
    private func setSignatureForNextFunction(_ maybeSignature: Signature?) {
        guard let signature = maybeSignature else { return }
        jsTyper.setSignature(forInstructionAt: code.count, to: signature)
    }

    /// Analyze the given instruction. Should be called directly after appending the instruction to the code.
    ///
    /// This will do the following:
    /// * Update the scope analysis to process any scope changes, which is required for correctly tracking the visible variables
    /// * Update the context analysis to process any context changes
    /// * Update the set of seen values and the variables that contain them for variable reuse
    /// * Update object literal state when fields are added to an object literal
    /// * Update the set of open function definitions, used to avoid trivial recursion
    /// * Run type inference to determine output types and any other type changes
    private func analyze(_ instr: Instruction) {
        assert(code.lastInstruction.op === instr.op)

        // Update scope and context analysis.
        scopeAnalyzer.analyze(instr)
        contextAnalyzer.analyze(instr)

        // Update the lists of observed values.
        switch instr.op.opcode {
        case .loadInteger(let op):
            loadedIntegers[instr.output] = op.value
        case .loadFloat(let op):
            loadedFloats[instr.output] = op.value
        case .loadBuiltin(let op):
            loadedBuiltins[instr.output] = op.builtinName
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

        // Update object literal and class definition state.
        switch instr.op.opcode {
        case .beginObjectLiteral:
            activeObjectLiterals.push(ObjectLiteral(in: self))
        case .objectLiteralAddProperty(let op):
            currentObjectLiteral.existingProperties.append(op.propertyName)
        case .objectLiteralAddElement(let op):
            currentObjectLiteral.existingElements.append(op.index)
        case .objectLiteralAddComputedProperty:
            currentObjectLiteral.existingComputedProperties.append(instr.input(0))
        case .objectLiteralCopyProperties:
            // Cannot generally determine what fields this installs.
            break
        case .beginObjectLiteralMethod(let op):
            currentObjectLiteral.existingMethods.append(op.methodName)
        case .beginObjectLiteralGetter(let op):
            currentObjectLiteral.existingGetters.append(op.propertyName)
        case .beginObjectLiteralSetter(let op):
            currentObjectLiteral.existingSetters.append(op.propertyName)
        case .endObjectLiteralMethod,
             .endObjectLiteralGetter,
             .endObjectLiteralSetter:
            break
        case .endObjectLiteral:
            activeObjectLiterals.pop()

        case .beginClassDefinition:
            activeClassDefinitions.push(ClassDefinition(in: self))
        case .beginClassConstructor:
            activeClassDefinitions.top.hasConstructor = true
        case .classAddInstanceProperty(let op):
            activeClassDefinitions.top.existingInstanceProperties.append(op.propertyName)
        case .classAddInstanceElement(let op):
            activeClassDefinitions.top.existingInstanceElements.append(op.index)
        case .classAddInstanceComputedProperty:
            activeClassDefinitions.top.existingInstanceComputedProperties.append(instr.input(0))
        case .beginClassInstanceMethod(let op):
            activeClassDefinitions.top.existingInstanceMethods.append(op.methodName)
        case .beginClassInstanceGetter(let op):
            activeClassDefinitions.top.existingInstanceGetters.append(op.propertyName)
        case .beginClassInstanceSetter(let op):
            activeClassDefinitions.top.existingInstanceSetters.append(op.propertyName)
        case .classAddStaticProperty(let op):
            activeClassDefinitions.top.existingStaticProperties.append(op.propertyName)
        case .classAddStaticElement(let op):
            activeClassDefinitions.top.existingStaticElements.append(op.index)
        case .classAddStaticComputedProperty:
            activeClassDefinitions.top.existingStaticComputedProperties.append(instr.input(0))
        case .beginClassStaticMethod(let op):
            activeClassDefinitions.top.existingStaticMethods.append(op.methodName)
        case .beginClassStaticGetter(let op):
            activeClassDefinitions.top.existingStaticGetters.append(op.propertyName)
        case .beginClassStaticSetter(let op):
            activeClassDefinitions.top.existingStaticSetters.append(op.propertyName)
        case .endClassDefinition:
            activeClassDefinitions.pop()
        default:
            assert(!instr.op.requiredContext.contains(.objectLiteral))
            break
        }

        // Track open functions.
        if instr.op is BeginAnyFunction {
            openFunctions.append(instr.output)
        } else if instr.op is EndAnyFunction {
            openFunctions.removeLast()
        }

        // Update type information.
        jsTyper.analyze(instr)
    }
}
