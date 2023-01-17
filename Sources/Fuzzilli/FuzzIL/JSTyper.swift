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

/// Type inference for JavaScript variables.
public struct JSTyper: Analyzer {
    // The environment model from which to obtain various pieces of type information.
    private let environment: Environment

    // The current state
    private var state = AnalyzerState()

    // Program-wide function and method signatures and property types.
    // Signatures are keyed by the index of the start of the subroutine definition in the program.
    private var signatures = [Int: Signature]()
    // Method signatures and property types are keyed by their method/property name.
    private var methodSignatures = [String: Signature]()
    private var propertyTypes = [String: JSType]()

    // Tracks the active function definitions.
    // This is for example used to determine the type of 'super' at the current position.
    private var activeFunctionDefinitions = [Operation]()

    // Stack of active object literals. Each entry contains the current type of the object created by the literal.
    // This must be a stack as object literals can be nested (e.g. an object literal inside the method of another one).
    private var activeObjectLiterals = Stack<JSType>()

    // Stack of active class definitions. As class definitions can be nested, this has to be a stack.
    private var activeClassDefinitions = Stack<ClassDefinition>()
    struct ClassDefinition {
        let output: Variable
        var constructorParameters: [Signature.Parameter] = []
        let superType: JSType
        var instanceType: JSType
        var classType: JSType
    }

    // The index of the last instruction that was processed. Just used for debug assertions.
    private var indexOfLastInstruction = -1

    init(for environ: Environment) {
        self.environment = environ
    }

    public mutating func reset() {
        indexOfLastInstruction = -1
        state.reset()
        propertyTypes.removeAll()
        methodSignatures.removeAll()
        assert(activeFunctionDefinitions.isEmpty)
        assert(activeObjectLiterals.isEmpty)
        assert(activeClassDefinitions.isEmpty)
    }

    // Array for collecting type changes during instruction execution.
    // Not currently used, by could be used for example to validate the analysis by adding these as comments to programs.
    private var typeChanges = [(Variable, JSType)]()

    /// Analyze the given instruction, thus updating type information.
    public mutating func analyze(_ instr: Instruction) {
        assert(instr.index == indexOfLastInstruction + 1)
        indexOfLastInstruction += 1

        // Reset type changes array before instruction execution.
        typeChanges = []

        processTypeChangesBeforeScopeChanges(instr)

        processScopeChanges(instr)

        processTypeChangesAfterScopeChanges(instr)

        // Sanity checking: every output variable must now have a type.
        assert(instr.allOutputs.allSatisfy(state.hasType))
    }

    public func type(ofProperty propertyName: String) -> JSType {
        return propertyTypes[propertyName] ?? .unknown
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperType() -> JSType {
        assert(!activeClassDefinitions.isEmpty)
        return activeClassDefinitions.top.superType
    }

    /// Sets a program wide type for the given property.
    public mutating func setType(ofProperty propertyName: String, to type: JSType) {
        propertyTypes[propertyName] = type
    }

    /// Sets a program wide signature for the given method name.
    public mutating func setSignature(ofMethod methodName: String, to signature: Signature) {
        methodSignatures[methodName] = signature
    }

    /// Sets a program-wide signature for the instruction at the given index, which must be the start of a function or method definition.
    public mutating func setSignature(forInstructionAt index: Int, to signature: Signature) {
        assert(index > indexOfLastInstruction)
        signatures[index] = signature
    }

    public func inferMethodSignature(of methodName: String, on objType: JSType) -> Signature {
        // First check global property types.
        if let signature = methodSignatures[methodName] {
            return signature
        }

        // Then check well-known methods of this execution environment.
        return environment.signature(ofMethod: methodName, on: objType)
    }

    /// Attempts to infer the signature of the given method on the given object type.
    public func inferMethodSignature(of methodName: String, on object: Variable) -> Signature {
        return inferMethodSignature(of: methodName, on: state.type(of: object))
    }

    /// Attempts to infer the signature of the given subroutine definition.
    /// If a signature has been registered for this function, it is returned, otherwise a generic signature with the correct number of parameters is generated.
    private func inferSubroutineSignature(of op: BeginAnySubroutine, at index: Int) -> Signature {
        return signatures[index] ?? Signature(withParameterCount: op.parameters.count, hasRestParam: op.parameters.hasRestParameter)
    }

    /// Attempts to infer the signature of the given class constructor definition.
    /// If a signature has been registered for this constructor, it is returned, otherwise a generic signature with the correct number of parameters is generated.
    private func inferClassConstructorSignature(of op: BeginClassConstructor, at index: Int) -> Signature {
        let signature = signatures[index] ?? Signature(withParameterCount: op.parameters.count, hasRestParam: op.parameters.hasRestParameter)
        // Replace the output type with the current instanceType.
        assert(signature.outputType == .unknown)
        return signature.parameters => activeClassDefinitions.top.instanceType
    }

    /// Attempts to infer the type of the given property on the given object type.
    private func inferPropertyType(of propertyName: String, on objType: JSType) -> JSType {
        // First check global property types.
        if let type = propertyTypes[propertyName] {
            return type
        }

        // Then check well-known properties of this execution environment.
        return environment.type(ofProperty: propertyName, on: objType)
    }

    /// Attempts to infer the type of the given property on the given object type.
    private func inferPropertyType(of propertyName: String, on object: Variable) -> JSType {
        return inferPropertyType(of: propertyName, on: state.type(of: object))
    }

    /// Attempts to infer the constructed type of the given constructor.
    private func inferConstructedType(of constructor: Variable) -> JSType {
        if let signature = state.type(of: constructor).constructorSignature, signature.outputType != .unknown {
            return signature.outputType
        }
        return .object()
    }

    /// Attempts to infer the return value type of the given function.
    private func inferCallResultType(of function: Variable) -> JSType {
        if let signature = state.type(of: function).functionSignature {
            return signature.outputType
        }

        return .unknown
    }

    public mutating func setType(of v: Variable, to t: JSType) {
        // Variables must not be .anything or .nothing. For variables that can be anything, .unknown is the correct type.
        assert(t != .anything && t != .nothing)
        state.updateType(of: v, to: t)
    }

    public func type(of v: Variable) -> JSType {
        return state.type(of: v)
    }

    // Set type to current state and save type change event
    private mutating func set(_ v: Variable, _ t: JSType) {
        // Record type change if:
        // 1. It is first time we set the type of this variable
        // 2. The type is different from the previous type of that variable
        if !state.hasType(for: v) || state.type(of: v) != t {
            typeChanges.append((v, t))
        }
        setType(of: v, to: t)
    }

    private mutating func processTypeChangesBeforeScopeChanges(_ instr: Instruction) {
        switch instr.op.opcode {
        case .beginPlainFunction(let op as BeginAnyFunction):
            // Plain functions can also be used as constructors
            set(instr.output, .functionAndConstructor(inferSubroutineSignature(of: op, at: instr.index)))
        case .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            set(instr.output, .function(inferSubroutineSignature(of: op, at: instr.index)))
        case .beginConstructor(let op):
            set(instr.output, .constructor(inferSubroutineSignature(of: op, at: instr.index)))
        case .beginCodeString:
            set(instr.output, .string)
        case .beginClassDefinition(let op):
            var superType = environment.objectType
            if op.hasSuperclass {
                let superConstructorType = state.type(of: instr.input(0))
                superType = superConstructorType.constructorSignature?.outputType ?? superType
            }
            let classDefiniton = ClassDefinition(output: instr.output, superType: superType, instanceType: superType, classType: environment.objectType)
            activeClassDefinitions.push(classDefiniton)
            set(instr.output, .unknown)         // Treat the class variable as unknown until we have fully analyzed the class definition
        case .endClassDefinition:
            let cls = activeClassDefinitions.pop()
            // Can now compute the full type of the class variable
            set(cls.output, cls.classType + .constructor(cls.constructorParameters => cls.instanceType))
        default:
            // Only instructions starting a block with output variables should be handled here
            assert(instr.numOutputs == 0 || !instr.isBlockStart)
        }
    }

    private mutating func processScopeChanges(_ instr: Instruction) {
        switch instr.op.opcode {
        case .beginObjectLiteral,
             .endObjectLiteral,
             .beginClassDefinition,
             .endClassDefinition:
            // Object literals and class definitions don't create any conditional branches, only methods and accessors inside of them. These are handled further below.
            break
        case .beginIf:
            // Push an empty state to represent the state when no else block exists.
            // If there is an else block, we'll remove this state again, see below.
            state.pushChildState()
            // This state is the state of the if block.
            state.pushSiblingState(typeChanges: &typeChanges)
        case .beginElse:
            state.replaceFirstSiblingStateWithNewState(typeChanges: &typeChanges)
        case .endIf:
            state.mergeStates(typeChanges: &typeChanges)
        case .beginSwitch:
            // Push an empty state to represent the state when no switch-case is executed.
            // If there is a default state, we'll remove this state again, see below.
            state.pushChildState()
        case .beginSwitchDefaultCase:
            // If there is a default case, drop the empty state created by BeginSwitch. That
            // states represents the scenario where no case is executed, which cannot happen
            // with a default state.
            state.replaceFirstSiblingStateWithNewState(typeChanges: &typeChanges)
        case .beginSwitchCase:
            state.pushSiblingState(typeChanges: &typeChanges)
        case .endSwitchCase:
            break
        case .endSwitch:
            state.mergeStates(typeChanges: &typeChanges)
        case .beginWhileLoop,
             .beginDoWhileLoop,
             .beginForLoop,
             .beginForInLoop,
             .beginForOfLoop,
             .beginForOfWithDestructLoop,
             .beginRepeatLoop,
             .beginObjectLiteralMethod,
             .beginObjectLiteralGetter,
             .beginObjectLiteralSetter,
             .beginPlainFunction,
             .beginArrowFunction,
             .beginGeneratorFunction,
             .beginAsyncFunction,
             .beginAsyncArrowFunction,
             .beginAsyncGeneratorFunction,
             .beginConstructor,
             .beginClassConstructor,
             .beginClassInstanceMethod,
             .beginCodeString:
            // Push empty state representing case when loop/function is not executed at all
            state.pushChildState()
            // Push state representing the types in the loop/function
            state.pushSiblingState(typeChanges: &typeChanges)
        case .endWhileLoop,
             .endDoWhileLoop,
             .endForLoop,
             .endForInLoop,
             .endForOfLoop,
             .endRepeatLoop,
             .endObjectLiteralMethod,
             .endObjectLiteralGetter,
             .endObjectLiteralSetter,
             .endPlainFunction,
             .endArrowFunction,
             .endGeneratorFunction,
             .endAsyncFunction,
             .endAsyncArrowFunction,
             .endAsyncGeneratorFunction,
             .endConstructor,
             .endClassConstructor,
             .endClassInstanceMethod,
             .endCodeString:
            // TODO consider adding BeginAnyLoop, EndAnyLoop operations
            state.mergeStates(typeChanges: &typeChanges)
        case .beginTry,
             .beginCatch,
             .beginFinally,
             .endTryCatchFinally:
            break
        case .beginWith,
             .endWith:
            break
        case .beginBlockStatement,
             .endBlockStatement:
            break
        default:
            assert(instr.isSimple)
        }
    }

    private mutating func processTypeChangesAfterScopeChanges(_ instr: Instruction) {
        // Helper function to process parameters
        func processParameterDeclarations(_ params: ArraySlice<Variable>, signature: Signature) {
            let types = computeParameterTypes(from: signature)
            assert(types.count == params.count)
            for (param, type) in zip(params, types) {
                set(param, type)
            }
        }

        func type(ofInput inputIdx: Int) -> JSType {
            return state.type(of: instr.input(inputIdx))
        }

        // When interpreting instructions to determine output types, the general rule is to perform type checks on inputs
        // with the widest, most generic type (e.g. .integer, .bigint, .object), while setting output types to the most
        // specific type possible. In particular, that means that output types should always be fetched from the environment
        // (environment.intType, environment.bigIntType, environment.objectType), to give it a chance to customize the
        // basic types.
        // TODO: fetch all output types from the environment instead of hardcoding them.

        // Helper function to set output type of binary/reassignment operations
        func analyzeBinaryOperation(operator op: BinaryOperator, withInputs inputs: ArraySlice<Variable>) -> JSType {
            switch op {
            case .Add:
                return maybeBigIntOr(.primitive)
            case .Sub,
                 .Mul,
                 .Exp,
                 .Div,
                 .Mod:
                return maybeBigIntOr(.number)
            case .BitAnd,
                 .BitOr,
                 .Xor,
                 .LShift,
                 .RShift,
                 .UnRShift:
                return maybeBigIntOr(.integer)
            case .LogicAnd,
                 .LogicOr:
                return state.type(of: inputs[0]) | state.type(of: inputs[1])
            }
        }

        // Helper function for operations whose results
        // can only be a .bigint if an input to it is
        // a .bigint.
        func maybeBigIntOr(_ t: JSType) -> JSType {
            var outputType = t
            var allInputsAreBigint = true
            for i in 0..<instr.numInputs {
                if type(ofInput: i).MayBe(.bigint) {
                    outputType |= environment.bigIntType
                }
                if !type(ofInput: i).Is(.bigint) {
                    allInputsAreBigint = false
                }
            }
            return allInputsAreBigint ? environment.bigIntType : outputType
        }

        switch instr.op.opcode {
        case .loadBuiltin(let op):
            set(instr.output, environment.type(ofBuiltin: op.builtinName))

        case .loadInteger:
            set(instr.output, environment.intType)

        case .loadBigInt:
            set(instr.output, environment.bigIntType)

        case .loadFloat:
            set(instr.output, environment.floatType)

        case .loadString:
            set(instr.output, environment.stringType)

        case .loadBoolean:
            set(instr.output, environment.booleanType)

        case .loadUndefined:
            set(instr.output, .undefined)

        case .loadNull:
            set(instr.output, .undefined)

        case .loadThis:
            set(instr.output, .object())

        case .loadArguments:
            set(instr.output, .iterable)

        case .loadRegExp:
            set(instr.output, environment.regExpType)

        case .beginObjectLiteral:
            activeObjectLiterals.push(environment.objectType)

        case .objectLiteralAddProperty(let op):
            activeObjectLiterals.top.add(property: op.propertyName)

        case .objectLiteralAddElement,
             .objectLiteralAddComputedProperty,
             .objectLiteralCopyProperties:
            // We cannot currently determine the properties/methods added by these operations.
            break

        case .beginObjectLiteralMethod(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            processParameterDeclarations(instr.innerOutputs(1...), signature: inferSubroutineSignature(of: op, at: instr.index))
            activeObjectLiterals.top.add(method: op.methodName)

        case .beginObjectLiteralGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            assert(instr.numInnerOutputs == 1)
            activeObjectLiterals.top.add(property: op.propertyName)

        case .beginObjectLiteralSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), signature: inferSubroutineSignature(of: op, at: instr.index))
            activeObjectLiterals.top.add(property: op.propertyName)

        case .endObjectLiteral:
            let objectType = activeObjectLiterals.pop()
            set(instr.output, objectType)

        case .createArray,
             .createIntArray,
             .createFloatArray,
             .createArrayWithSpread:
            set(instr.output, environment.arrayType)

        case .createTemplateString:
            set(instr.output, environment.stringType)

        case .storeProperty(let op):
            if environment.customMethods.contains(op.propertyName) {
                set(instr.input(0), type(ofInput: 0).adding(method: op.propertyName))
            } else {
                set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))
            }

        case .configureProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .storePropertyWithBinop(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .deleteProperty(let op):
            set(instr.input(0), type(ofInput: 0).removing(property: op.propertyName))
            set(instr.output, .boolean)

            // TODO: An additional analyzer is required to determine the runtime value of the input variable
        case .deleteComputedProperty,
             .deleteElement:
            set(instr.output, .boolean)

        case .loadProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: instr.input(0)))

            // TODO: An additional analyzer is required to determine the runtime value of the output variable generated from the following operations
            // For now we treat this as .unknown
        case .loadElement,
             .loadComputedProperty,
             .callComputedMethod,
             .callComputedMethodWithSpread:
            set(instr.output, .unknown)

        case .ternaryOperation:
            let outputType = type(ofInput: 1) | type(ofInput: 2)
            set(instr.output, outputType)

        case .callFunction,
             .callFunctionWithSpread:
            set(instr.output, inferCallResultType(of: instr.input(0)))

        case .construct,
             .constructWithSpread:
            set(instr.output, inferConstructedType(of: instr.input(0)))

        case .callMethod(let op):
            set(instr.output, inferMethodSignature(of: op.methodName, on: instr.input(0)).outputType)
        case .callMethodWithSpread(let op):
            set(instr.output, inferMethodSignature(of: op.methodName, on: instr.input(0)).outputType)

        case .unaryOperation(let op):
            switch op.op {
            case .PreInc,
                 .PreDec,
                 .PostInc,
                 .PostDec:
                set(instr.input(0), maybeBigIntOr(.primitive))
                set(instr.output, maybeBigIntOr(.primitive))
            case .Plus:
                set(instr.output, maybeBigIntOr(.primitive))
            case .Minus:
                set(instr.output, maybeBigIntOr(.primitive))
            case .LogicalNot:
                set(instr.output, .boolean)
            case .BitwiseNot:
                set(instr.output, maybeBigIntOr(.integer))
            }

        case .binaryOperation(let op):
            set(instr.output, analyzeBinaryOperation(operator: op.op, withInputs: instr.inputs))

        case .reassignWithBinop(let op):
            set(instr.input(0), analyzeBinaryOperation(operator: op.op, withInputs: instr.inputs))

        case .typeOf:
            set(instr.output, .string)

        case .testInstanceOf:
            set(instr.output, .boolean)

        case .testIn:
            set(instr.output, .boolean)

        case .dup:
            set(instr.output, type(ofInput: 0))

        case .reassign:
            set(instr.input(0), type(ofInput: 1))

        case .destructArray:
            instr.outputs.forEach{set($0, .unknown)}

        case .destructArrayAndReassign:
            instr.inputs.dropFirst().forEach{set($0, .unknown)}

        case .destructObject(let op):
            for (property, output) in zip(op.properties, instr.outputs) {
                set(output, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.outputs.last!, environment.objectType)
            }

        case .destructObjectAndReassign(let op):
            for (property, input) in zip(op.properties, instr.inputs.dropFirst()) {
                set(input, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.inputs.last!, environment.objectType)
            }

        case .compare:
            set(instr.output, .boolean)

        case .loadFromScope:
            set(instr.output, .unknown)

        case .await:
            // TODO if input type is known, set to input type and possibly unwrap the Promise
            set(instr.output, .unknown)

        case .yield:
            set(instr.output, .unknown)

        case .beginPlainFunction(let op as BeginAnyFunction),
             .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            processParameterDeclarations(instr.innerOutputs, signature: inferSubroutineSignature(of: op, at: instr.index))

        case .beginConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), .object())
            processParameterDeclarations(instr.innerOutputs(1...), signature: inferSubroutineSignature(of: op, at: instr.index))

        case .beginClassConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            let signature = inferClassConstructorSignature(of: op, at: instr.index)
            processParameterDeclarations(instr.innerOutputs(1...), signature: signature)
            activeClassDefinitions.top.constructorParameters = signature.parameters

        case .classAddInstanceProperty(let op):
            activeClassDefinitions.top.instanceType.add(property: op.propertyName)

        case .beginClassInstanceMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), signature: inferSubroutineSignature(of: op, at: instr.index))
            activeClassDefinitions.top.instanceType.add(method: op.methodName)

        case .classAddStaticProperty(let op):
            activeClassDefinitions.top.classType.add(property: op.propertyName)

        case .callSuperMethod(let op):
            set(instr.output, inferMethodSignature(of: op.methodName, on: currentSuperType()).outputType)

        case .loadSuperProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: currentSuperType()))

            // TODO: support superclass property assignment

        case .beginForLoop:
            // Primitive type is currently guaranteed due to the structure of for loops
            set(instr.innerOutput, .primitive)

        case .beginForInLoop:
            set(instr.innerOutput, .string)

        case .beginForOfLoop:
            set(instr.innerOutput, .unknown)

        case .beginForOfWithDestructLoop:
            instr.innerOutputs.forEach {
                set($0, .unknown)
            }

        case .beginRepeatLoop:
            set(instr.innerOutput, .integer)

        case .beginCatch:
            set(instr.innerOutput, .unknown)

        default:
            // Only simple instructions and block instruction with inner outputs are handled here
            assert(instr.numOutputs == 0 || (instr.isBlock && instr.numInnerOutputs == 0))
        }
    }

    private func computeParameterTypes(from signature: Signature) -> [JSType] {
        func processType(_ type: JSType) -> JSType {
            if type == .anything {
                // .anything in the caller maps to .unknown in the callee
                return .unknown
            }
            return type
        }

        var types: [JSType] = []
        signature.parameters.forEach { param in
            switch param {
            case .plain(let t):
                types.append(processType(t))
            case .opt(let t):
                // When processing .opt(.anything) just turns into .unknown and not .unknown | .undefined
                // .unknown already means that we don't know what it is, so adding in .undefined doesn't really make sense and might screw other code that checks for .unknown
                // See https://github.com/googleprojectzero/fuzzilli/issues/326
                types.append(processType(t | .undefined))
            case .rest:
                // A rest parameter will just be an array. Currently, we don't support nested array types (i.e. .iterable(of: .integer)) or so, but once we do, we'd need to update this logic.
                types.append(environment.arrayType)
            }
        }
        return types
    }

    private struct AnalyzerState {
        // Represents an execution state.
        // This type must be a reference type as it is referred to from
        // member variables as well as being part of the state stack.
        private class State {
            public var types = VariableMap<JSType>()
        }

        // The current execution state. There is a new level (= array of states)
        // pushed onto this stack for every CFG structure with conditional execution
        // (if-else, loops, ...). Each level then has as many states as there are
        // conditional branches, e.g. if-else has two states, if-elseif-elseif-else
        // would have four and so on.
        //
        // Each state in the stack only stores information that was updated in the
        // corresponding block. As such, there may be a type for a variable in a
        // parent state but not a child state (if the variable's type doesn't change
        // inside the child block). However, there's an invariant that if the active
        // state contains a type (that's not .nothing, see below) for V, then its
        // parent state must also contain a type for V: if the variable is only defined
        // in the child state, it's type in the parent state will be set to .nothing.
        // If the variable is changed in a child state but not its parent state, then
        // the type in the parent state will be the most recent type for V in its parent
        // states. This invariant is necessary to be able to correctly update types when
        // leaving scopes as that requires knowing the type in the surrounding scope.
        //
        // It would be simpler to have the types of all visible variables in all active
        // states, but this way of implementing state tracking is significantly faster.
        private var stack: [[State]]

        // Always points to the active state: the newest state in the top most level of the stack
        private var activeState: State
        // Always points to the parent state: the newest state in the second-to-top level of the stack
        private var parentState: State

        // The full state at the current position. In essence, this is just a cache.
        // The same information could be retrieved by walking the state stack starting
        // from the activeState until there is a value for the queried variable.
        private var overallState: State

        init() {
            activeState = State()
            parentState = State()
            stack = [[parentState], [activeState]]
            overallState = State()
        }

        mutating func reset() {
            self = AnalyzerState()
        }

        /// Update current variable types and type changes
        /// Used after block end when some states should be merged to parent
        mutating func mergeStates(typeChanges: inout [(Variable, JSType)]) {
            let statesToMerge = stack.removeLast()
            var numUpdatesPerVariable = VariableMap<Int>()
            var newTypes = VariableMap<JSType>()

            for state in statesToMerge {
                for (v, t) in state.types {
                    // Skip variable types that are already out of scope (local to a child of the child state)
                    guard t != .nothing else { continue }

                    // Invariant checking: activeState[v] != nil => parentState[v] != nil
                    assert(parentState.types[v] != nil)

                    // Skip variables that are local to the child state
                    guard parentState.types[v] != .nothing else { continue }

                    if newTypes[v] == nil {
                        newTypes[v] = t
                        numUpdatesPerVariable[v] = 1
                    } else {
                        newTypes[v]! |= t
                        numUpdatesPerVariable[v]! += 1
                    }
                }
            }

            for (v, c) in numUpdatesPerVariable {
                assert(parentState.types[v] != .nothing)

                // Not all paths updates this variable, so it must be unioned with the type in the parent state.
                // The parent state will always have an entry for v due to the invariant "activeState[v] != nil => parentState[v] != nil".
                if c != statesToMerge.count {
                    newTypes[v]! |= parentState.types[v]!
                }
            }

            // The previous parent state is now the active state
            let oldParentState = parentState
            activeState = parentState
            parentState = stack[stack.count - 2].last!

            // Update the overallState and compute typeChanges
            for (v, newType) in newTypes {
                if overallState.types[v] != newType {
                    typeChanges.append((v, newType))
                }

                // overallState now doesn't contain the older type but actually a newer type,
                // therefore we have to manually specify the old type here.
                updateType(of: v, to: newType, from: oldParentState.types[v])
            }
        }

        /// Return the current type of the given variable.
        /// Return .unknown for variables not available in this state.
        func type(of variable: Variable) -> JSType {
            return overallState.types[variable] ?? .unknown
        }

        func hasType(for v: Variable) -> Bool {
            return overallState.types[v] != nil
        }

        /// Set the type of the given variable in the current state.
        mutating func updateType(of v: Variable, to newType: JSType, from oldType: JSType? = nil) {
            // Basic consistency checking. This seems like a decent
            // place to do this since it executes frequently.
            assert(activeState === stack.last!.last!)
            assert(parentState === stack[stack.count-2].last!)
            // If an oldType is specified, it must match the type in the next most recent state
            // (but here we just check that one of the parent states contains it).
            assert(oldType == nil || stack.contains(where: { $0.last!.types[v] == oldType! }))

            // Set the old type in the parent state if itss not already there to satisfy "activeState[v] != nil => parentState[v] != nil".
            // Use .nothing to express that the variable is only defined in the child state.
            let oldType = oldType ?? overallState.types[v] ?? .nothing
            if parentState.types[v] == nil {
                parentState.types[v] = oldType
            }

            // Integrity checking: if the type of v hasn't previously been updated in the active
            // state, then the old type must be equal to the type in the parent state.
            assert(activeState.types[v] != nil || parentState.types[v] == oldType)

            activeState.types[v] = newType
            overallState.types[v] = newType
        }

        mutating func pushChildState() {
            parentState = activeState
            activeState = State()
            stack.append([activeState])
        }

        // Required for switch-case handling, see handling of BeginSwitchDefaultCase.
        // Replaces the first sibling state with a newly created one.
        mutating func replaceFirstSiblingStateWithNewState(typeChanges: inout [(Variable, JSType)]) {
            stack[stack.count - 1].removeFirst()
            pushSiblingState(typeChanges: &typeChanges)
        }

        mutating func pushSiblingState(typeChanges: inout [(Variable, JSType)]) {
            // Reset current state to parent state
            for (v, t) in activeState.types {
                // Do not save type change if
                // 1. Variable does not exist in sibling scope (t == .nothing)
                // 2. Variable is only local in sibling state (parent == .nothing)
                // 3. No type change happened
                if t != .nothing && parentState.types[v] != .nothing && parentState.types[v] != overallState.types[v] {
                    typeChanges.append((v, parentState.types[v]!))
                    overallState.types[v] = parentState.types[v]!
                }
            }

            // Create sibling state
            activeState = State()
            stack[stack.count - 1].append(activeState)
        }
    }
}
