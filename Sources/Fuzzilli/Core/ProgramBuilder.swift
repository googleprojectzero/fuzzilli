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
    let fuzzer: Fuzzer
    
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
    
    public var context: ProgramContext {
        return contextAnalyzer.context
    }
    
    /// Counter to quickly determine the next free variable.
    private var numVariables = 0
    
    /// Property names and integer values previously seen in the current program.
    private var seenPropertyNames = Set<String>()
    private var seenIntegers = Set<Int64>()
    
    /// The program currently being constructed.
    private var program = Program()
    
    /// Various analyzers for the current program.
    private var scopeAnalyzer = ScopeAnalyzer()
    private var contextAnalyzer = ContextAnalyzer()
    
    /// Abstract interpreter to computer type information.
    private var interpreter: AbstractInterpreter?
    
    /// During code generation, contains the minimum number of remaining instructions
    /// that should still be generated.
    private var currentCodegenBudget = 0
    
    /// Set of phis, needed for the randPhi() method.
    private var phis = VariableSet()
    
    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer, interpreter: AbstractInterpreter?, mode: Mode) {
        self.fuzzer = fuzzer
        self.interpreter = interpreter
        self.mode = mode
    }
    
    /// Resets this builder.
    public func reset() {
        numVariables = 0
        seenPropertyNames.removeAll()
        seenIntegers.removeAll()
        program = Program()
        scopeAnalyzer.reset()
        contextAnalyzer.reset()
        interpreter?.reset()
        currentCodegenBudget = 0
        phis.removeAll()
    }
    
    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        assert(program.check() == .valid)
        let result = program
        reset()
        return result
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
        // TODO: add genRegExpPatterns with groups etc.
        let regexp = withEqualProbability({
            String.random(ofLength: 2)
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingRegExps)
        }, {
            self.genRegExp() + self.genRegExp()
        })

        return regexp.replacingOccurrences(of: "/", with: "\\/")
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
    
    public func randPhi() -> Variable? {
        return randVarInternal({ self.phis.contains($0) })
    }
    
    /// Returns a random variable.
    public func randVar() -> Variable {
        precondition(scopeAnalyzer.visibleVariables.count > 0)
        return randVarInternal()!
    }
    
    /// Returns a random variable of the given type.
    ///
    /// In conservative mode, this function fails unless it finds a matching variable.
    /// In aggressive mode, this function will also return variables that have unknown type, and may, if no matching variables are available, return variables of any type.
    public func randVar(ofType type: Type) -> Variable? {
        var wantedType = type
        
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
        let runtimeType = program.runtimeType(of: v)
        if runtimeType == .unknown {
            return interpreter?.type(of: v) ?? .unknown
        } else {
            return runtimeType
        }
    }
    
    public func isPhi(_ v: Variable) -> Bool {
        return phis.contains(v)
    }
    
    public func methodSignature(of methodName: String, on object: Variable) -> FunctionSignature {
        return interpreter?.inferMethodSignature(of: methodName, on: object) ?? FunctionSignature.forUnknownFunction
    }
    
    public func setType(ofProperty propertyName: String, to propertyType: Type) {
        interpreter?.setType(ofProperty: propertyName, to: propertyType)
    }
    
    public func setSignature(ofMethod methodName: String, to methodSignature: FunctionSignature) {
        interpreter?.setSignature(ofMethod: methodName, to: methodSignature)
    }
    
    public func generateCallArguments(for signature: FunctionSignature) -> [Variable]? {
        var parameterTypes = signature.inputTypes
        var arguments = [Variable]()
        
        // "Expand" varargs parameters first
        if signature.hasVarargsParameter() {
            let varargsParam = parameterTypes.removeLast()
            assert(varargsParam.isList)
            for _ in 0..<Int.random(in: 0...5) {
                parameterTypes.append(varargsParam.removingFlagTypes())
            }
        }
            
        for param in parameterTypes {
            if param.isOptional {
                // It's an optional argument, so stop here in some cases
                if probability(0.25) {
                    break
                }
            }
            
            assert(!param.isList)
            guard let v = randVar(ofType: param) else { return nil }
            arguments.append(v)
        }
            
        return arguments
    }
    
    public func generateCallArguments(for function: Variable) -> [Variable]? {
        let signature = type(of: function).signature ?? FunctionSignature.forUnknownFunction
        return generateCallArguments(for: signature)
    }
    
    public func generateCallArguments(forMethod methodName: String, on object: Variable) -> [Variable]? {
        let signature = methodSignature(of: methodName, on: object)
        return generateCallArguments(for: signature)
    }
    
    
    ///
    /// Adoption of variables from a different program.
    /// Required when copying instructions between program.
    ///
    private var varMaps = [VariableMap<Variable>]()
    private var typeMaps = [VariableMap<Type>]()
    
    /// Prepare for adoption of variables from the given program.
    ///
    /// This sets up a mapping for variables from the given program to the
    /// currently constructed one to avoid collision of variable names.
    public func beginAdoption(from program: Program) {
        varMaps.append(VariableMap())
        typeMaps.append(program.runtimeTypes)
    }
    
    /// Finishes the most recently started adoption.
    public func endAdoption() {
        varMaps.removeLast()
        typeMaps.removeLast()
    }
    
    /// Executes the given block after preparing for adoption from the provided program.
    public func adopting(from program: Program, _ block: () -> Void) {
        beginAdoption(from: program)
        block()
        endAdoption()
    }
    
    /// Maps a variable from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ variable: Variable, keepType: Bool) -> Variable {
        if !varMaps.last!.contains(variable) {
            varMaps[varMaps.count - 1][variable] = nextVariable()
        }
        let currentVariable = varMaps.last![variable]!

        if keepType, let currentType = typeMaps.last![variable] {
            program.setRuntimeType(of: currentVariable, to: currentType)
        }
        return currentVariable
    }
    
    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ variables: [Variable], keepTypes: Bool) -> [Variable] {
        return variables.map{ adopt($0, keepType: keepTypes) }
    }
    
    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instruction: Instruction, keepTypes: Bool) {
        let newInouts = adopt(Array(instruction.inputs), keepTypes: false) + adopt(Array(instruction.allOutputs), keepTypes: keepTypes)
        internalAppend(Instruction(operation: instruction.operation, inouts: newInouts))
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
            for instr in program {
                adopt(instr, keepTypes: true)
            }
        }
    }
    
    /// Append a splice from another program.
    public func splice(from program: Program, at index: Int) {
        var idx = index
        
        // Determine all necessary input instructions for the choosen instruction
        // We need special handling for blocks:
        //   If the choosen instruction is a block instruction then copy the whole block
        //   If we need an inner output of a block instruction then only copy the block instructions, not the content
        //   Otherwise copy the whole block including its content
        var needs = Set<Int>()
        var requiredInputs = VariableSet()
        
        func keep(_ instr: Instruction, includeBlockContent: Bool = false) {
            guard !needs.contains(instr.index) else { return }
            if instr.isBlock {
                let group = program.blockGroup(around: instr)
                let instructions = includeBlockContent ? group.includingContent() : group.excludingContent()
                for instr in instructions {
                    requiredInputs.formUnion(instr.inputs)
                    needs.insert(instr.index)
                }
            } else {
                requiredInputs.formUnion(instr.inputs)
                needs.insert(instr.index)
            }
        }
        
        // Keep the selected instruction
        keep(program[idx], includeBlockContent: true)
        
        while idx > 0 {
            idx -= 1
            let current = program[idx]
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
        
        // Insert the slice into the currently mutated program
        adopting(from: program) {
            for instr in program {
                if needs.contains(instr.index) {
                    adopt(instr, keepTypes: true)
                }
            }
        }
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
        } while counter < 25 && (program[idx].isJump || program[idx].isBlockEnd || program[idx].isPrimitive || program[idx].isLiteral)
        
        splice(from: program, at: idx)
    }
    
    /// Executes a code generator.
    ///
    /// - Parameter generators: The code generator to run at the current position.
    /// - Returns: the number of instructions added by all generators.
    func run(_ generator: CodeGenerator) {
        precondition(generator.requiredContext.isSubset(of: context))
                
        var inputs: [Variable] = []
        for type in generator.inputTypes {
            guard let val = randVar(ofType: type) else { return }
            inputs.append(val)
        }

        generator.run(in: self, with: inputs)
    }
    
    private func generateInternal() {
        precondition(!fuzzer.corpus.isEmpty)
        
        while currentCodegenBudget > 0 {
            
            // There are two modes of code generation:
            // 1. Splice code from another program in the corpus
            // 2. Pick a CodeGenerator, find or generate matching variables, and execute it
                        
            withEqualProbability({
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
    private func perform(_ operation: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        var inouts = inputs
        for _ in 0..<operation.numOutputs {
            inouts.append(nextVariable())
        }
        for _ in 0..<operation.numInnerOutputs {
            inouts.append(nextVariable())
        }
        let instruction = Instruction(operation: operation, inouts: inouts)
        internalAppend(instruction)
        return instruction
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
        perform(DeleteComputedProperty(), withInputs: [name, object])
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
        let instruction = perform(BeginPlainFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndPlainFunctionDefinition())
        return instruction.output
    }

    @discardableResult
    public func defineStrictFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instruction = perform(BeginStrictFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndStrictFunctionDefinition())
        return instruction.output
    }
    
    @discardableResult
    public func defineArrowFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instruction = perform(BeginArrowFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndArrowFunctionDefinition())
        return instruction.output
    }
    
    @discardableResult
    public func defineGeneratorFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instruction = perform(BeginGeneratorFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndGeneratorFunctionDefinition())
        return instruction.output
    }
    
    @discardableResult
    public func defineAsyncFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instruction = perform(BeginAsyncFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndAsyncFunctionDefinition())
        return instruction.output
    }

    @discardableResult
    public func defineAsyncArrowFunction(withSignature signature: FunctionSignature, _ body: ([Variable]) -> ()) -> Variable {
        let instruction = perform(BeginAsyncArrowFunctionDefinition(signature: signature))
        body(Array(instruction.innerOutputs))
        perform(EndAsyncArrowFunctionDefinition())
        return instruction.output
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
    public func phi(_ input: Variable) -> Variable {
        return perform(Phi(), withInputs: [input]).output
    }
    
    public func copy(_ input: Variable, to output: Variable) {
        perform(Copy(), withInputs: [output, input])
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
    
    public func endTryCatch() {
        perform(EndTryCatch())
    }
    
    public func throwException(_ value: Variable) {
        perform(ThrowException(), withInputs: [value])
    }
    
    public func codeString(_ body: () -> ()) -> Variable{
        let instruction = perform(BeginCodeString())
        body()
        perform(EndCodeString())
        return instruction.output
    }

    public func doPrint(_ value: Variable) {
        perform(Print(), withInputs: [value])
    }
    
    public func inspectType(of value: Variable) {
        perform(InspectType(), withInputs: [value])
    }
    
    public func inspectValue(_ value: Variable) {
        perform(InspectValue(), withInputs: [value])
    }
    
    public func inspectGlobals() {
        perform(EnumerateBuiltins())
    }
    
    
    /// Returns the next free variable.
    func nextVariable() -> Variable {
        assert(numVariables < maxNumberOfVariables, "Too many variables")
        numVariables += 1
        return Variable(number: numVariables - 1)
    }
    
    private func internalAppend(_ instruction: Instruction) {
        // Basic integrity checking
        assert(!instruction.inouts.contains(where: { $0.number >= numVariables }))
        
        program.append(instruction)
        
        currentCodegenBudget -= 1
        
        // Update our analyses
        interpreter?.execute(program.lastInstruction)
        scopeAnalyzer.analyze(program.lastInstruction)
        contextAnalyzer.analyze(program.lastInstruction)
        updateConstantPool(instruction.operation)
        if instruction.operation is Phi {
            // We need to track Phi variables separately to be able to produce valid programs.
            phis.insert(instruction.output)
        }
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
