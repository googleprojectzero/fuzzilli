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
    private var interpreter: AbstractInterpreter
    
    
    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer) {
        self.fuzzer = fuzzer
        self.interpreter = AbstractInterpreter(for: fuzzer)
    }
    
    /// Finalizes and returns the constructed program.
    ///
    /// The builder instance can not be used further after calling this function.
    public func finish() -> Program {
        assert(program.check() == .valid)
        let result = program
        program = Program()
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
        return withEqualProbability({
            String.random(ofLength: 2)
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingRegExps)
        }, {
            self.genRegExp() + self.genRegExp()
        })
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


    /// Returns true if the current position is inside the body of a function, false otherwise.
    public var isInFunction: Bool {
        return contextAnalyzer.context.contains(.inFunction)
    }
    
    /// Returns true if the current position is inside the body of a generator function, false otherwise.
    public var isInGeneratorFunction: Bool {
        return contextAnalyzer.context.contains(.inGeneratorFunction)
    }
    
    /// Returns true if the current position is inside the body of an async  function, false otherwise.
    public var isInAsyncFunction: Bool {
        return contextAnalyzer.context.contains(.inAsyncFunction)
    }

    /// Returns true if the current position is inside the body of a loop, false otherwise.
    public var isInLoop: Bool {
        return contextAnalyzer.context.contains(.inLoop)
    }
    
    /// Returns true if the current position is inside the body of a with statement, false otherwise.
    public var isInWithStatement: Bool {
        return contextAnalyzer.context.contains(.inWith)
    }
    
    /// Returns a random variable.
    public func randVar() -> Variable {
        return randVarInternal()!
    }
    
    /// Returns a random variable of the given type or of another type if none is available.
    public func randVar(ofType wantedType: Type) -> Variable {
        // For now, we always mix in .unknown into the requested type.
        // Probably in the future we want to have a "conservative" mode where we
        // don't to that.
        if let v = randVarInternal({ self.type(of: $0).Is(wantedType | .unknown) }) {
            return v
        } else {
            // Must use variable of a different type
            return randVar()
        }
    }
    
    /// Returns a random variable of the given type or nil if none is found.
    public func randVar(ofGuaranteedType wantedType: Type) -> Variable? {
        return randVarInternal({ self.type(of: $0).Is(wantedType) })
    }
    
    /// Returns a random variable from the outer scope.
    public func randVarFromOuterScope() -> Variable {
        return chooseUniform(from: scopeAnalyzer.outerVisibleVariables)
    }
    
    
    /// Type information access.
    public func type(of v: Variable) -> Type {
        return interpreter.type(of: v)
    }
    
    public func methodSignature(of methodName: String, on object: Variable) -> FunctionSignature {
        return interpreter.inferMethodSignature(of: methodName, on: object)
    }
    
    public func setType(ofProperty propertyName: String, to propertyType: Type) {
        interpreter.setType(ofProperty: propertyName, to: propertyType)
    }
    
    public func setSignature(ofMethod methodName: String, to methodSignature: FunctionSignature) {
        interpreter.setSignature(ofMethod: methodName, to: methodSignature)
    }
    
    public func generateCallArguments(for signature: FunctionSignature) -> [Variable] {
        var arguments = [Variable]()
        for (i, param) in signature.inputTypes.enumerated() {
            if signature.isOptional(i) {
                // It's an optional argument, so stop here in some cases
                if probability(0.25) {
                    break
                }
            }
            
            if param.isList {
                // It's a varargs function
                for _ in 0..<Int.random(in: 1...5) {
                    arguments.append(randVar(ofType: param.removingFlagTypes))
                }
            } else {
                // "Normal" parameter
                arguments.append(randVar(ofType: param))
            }
        }
        return arguments
    }
    
    public func generateCallArguments(for function: Variable) -> [Variable] {
        let signature = type(of: function).signature ?? FunctionSignature.forUnknownFunction
        return generateCallArguments(for: signature)
    }
    
    public func generateCallArguments(forMethod methodName: String, on object: Variable) -> [Variable] {
        let signature = interpreter.inferMethodSignature(of: methodName, on: object)
        return generateCallArguments(for: signature)
    }
    
    
    
    ///
    /// Adoption of variables from a different program.
    /// Required when copying instructions between program.
    ///
    private var varMaps = [[Variable: Variable]]()
    
    /// Prepare for adoption of variables from the given program.
    ///
    /// This sets up a mapping for variables from the given program to the
    /// currently constructed one to avoid collision of variable names.
    public func beginAdoption(from program: Program) {
        varMaps.append([Variable: Variable]())
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
        if !varMaps.last!.keys.contains(variable) {
            varMaps[varMaps.count - 1][variable] = nextVariable()
        }
        return varMaps.last![variable]!
    }
    
    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ variables: [Variable]) -> [Variable] {
        return variables.map(adopt)
    }
    
    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instruction: Instruction) {
        internalAppend(Instruction(operation: instruction.operation, inouts: adopt(instruction.inouts)))
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
                adopt(instr)
            }
        }
    }
    

    
    /// Executes a code generator.
    ///
    /// - Parameter generators: The code generator to run at the current position.
    /// - Returns: the number of instructions added by all generators.
    @discardableResult
    func run(_ generators: CodeGenerator...) -> Int {
        let previousProgramSize = program.size
        for generator in generators {
            generator(self)
        }
        return program.size - previousProgramSize
    }
    
    // Code generators that can be used even if no variables exist yet.
    private let primitiveGenerators = [
        IntegerLiteralGenerator,
        FloatLiteralGenerator,
        StringLiteralGenerator,
        BooleanLiteralGenerator
    ]
    
    /// Generates random code at the current position.
    @discardableResult
    public func generate(n: Int = 1) -> Int {
        let previousProgramSize = program.size
        for _ in 0..<n {
            if scopeAnalyzer.visibleVariables.count == 0 {
                let generator = chooseUniform(from: primitiveGenerators)
                run(generator)
                continue
            }
            
            var success = false
            repeat {
                let generator = fuzzer.codeGenerators.any()
                success = run(generator) > 0
            } while !success
        }
        return program.size - previousProgramSize
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
        return perform(CreateObject(propertyNames: Array(initialProperties.keys)), withInputs: Array(initialProperties.values)).output
    }
    
    @discardableResult
    public func createArray(with initialValues: [Variable]) -> Variable {
        return perform(CreateArray(numInitialValues: initialValues.count), withInputs: initialValues).output
    }
    
    @discardableResult
    public func createObject(with initialProperties: [String: Variable], andSpreading spreads: [Variable]) -> Variable {
        return perform(CreateObjectWithSpread(propertyNames: Array(initialProperties.keys), numSpreads: spreads.count),
                       withInputs: Array(initialProperties.values) + spreads).output
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
        perform(BeginDoWhile())
        body()
        perform(EndDoWhile(comparator: comparator), withInputs: [lhs, rhs])
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
    
    public func print(_ value: Variable) {
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
                if candidates.isEmpty {
                    // Failed to find a variable that satisfies the requirements
                    return nil
                }
            } else {
                candidates = scopeAnalyzer.visibleVariables
            }
        }
        
        return chooseUniform(from: candidates)
    }
    
    private func internalAppend(_ instruction: Instruction) {
        // Basic integrity checking
        assert(!instruction.inouts.contains(where: { $0.number >= numVariables }))
        
        program.append(instruction)
        
        // Update our analysis
        if fuzzer.config.useAbstractInterpretation {
            interpreter.execute(program.lastInstruction)
        } else if instruction.operation is Phi {
            // Even though we don't track types when useAbstractInterpretation is disabled,
            // we still need to track Phi variables to be able to produce valid programs.
            interpreter.setType(of: instruction.output, to: .phi(of: .anything))
        }
        scopeAnalyzer.analyze(program.lastInstruction)
        contextAnalyzer.analyze(program.lastInstruction)
        updateConstantPool(instruction.operation)
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
