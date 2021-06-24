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

/// Analyzes the types of variables.
public struct AbstractInterpreter {
    // The current state
    private var state = InterpreterState()

    // Program-wide property and method types.
    private var propertyTypes = [String: Type]()
    private var methodSignatures = [String: FunctionSignature]()

    // Stack of currently active class definitions.
    private(set) var classDefinitions = ClassDefinitionStack()

    // Tracks the active function definitions.
    // This is for example used to determine the type of 'super' at the current position.
    private var activeFunctionDefinitions = [Operation]()

    // The environment model from which to obtain various pieces of type information.
    private let environment: Environment

    init(for environ: Environment) {
        self.environment = environ
    }

    public mutating func reset() {
        state.reset()
        propertyTypes.removeAll()
        methodSignatures.removeAll()
        assert(activeFunctionDefinitions.isEmpty)
        assert(classDefinitions.isEmpty)
    }

    // Array for collecting type changes during instruction execution
    private var typeChanges = [(Variable, Type)]()

    /// Abstractly execute the given instruction, thus updating type information.
    /// Return type changes.
    public mutating func execute(_ instr: Instruction) -> [(Variable, Type)] {
        // Reset type changes array before instruction execution
        typeChanges = []

        executeOuterEffects(instr)

        switch instr.op {
        case is BeginIf:
            state.pushChildState()
        case is BeginElse:
            state.pushSiblingState(typeChanges: &typeChanges)
        case is EndIf:
            state.mergeStates(typeChanges: &typeChanges)
        case is BeginSwitch:
            state.pushChildState()
        case is BeginSwitchCase:
            state.pushSiblingState(typeChanges: &typeChanges)
        case is EndSwitch:
            state.mergeStates(typeChanges: &typeChanges)
        case is BeginWhile, is BeginDoWhile, is BeginFor, is BeginForIn, is BeginForOf, is BeginAnyFunctionDefinition, is BeginCodeString:
            // Push empty state representing case when loop/function is not executed at all
            state.pushChildState()
            // Push state representing types during loop
            state.pushSiblingState(typeChanges: &typeChanges)
        case is EndWhile, is EndDoWhile, is EndFor, is EndForIn, is EndForOf, is EndAnyFunctionDefinition, is EndCodeString:
            state.mergeStates(typeChanges: &typeChanges)
        case is BeginTry,
             is BeginCatch,
             is BeginFinally,
             is EndTryCatch:
            break
        case is BeginWith,
             is EndWith:
            break
        case is BeginBlockStatement,
             is EndBlockStatement:
            break
        case is BeginClassDefinition:
            // Push an empty state for the case that the constructor is never executed
            state.pushChildState()
            // Push the new state for the constructor
            state.pushSiblingState(typeChanges: &typeChanges)
        case is BeginMethodDefinition:
            // Remove the state of the previous method or constructor
            state.mergeStates(typeChanges: &typeChanges)

            // and push two new states for this method
            state.pushChildState()
            state.pushSiblingState(typeChanges: &typeChanges)
        case is EndClassDefinition:
            state.mergeStates(typeChanges: &typeChanges)
        default:
            assert(instr.isSimple)
        }

        // Track active function definitions
        switch instr.op {
        case is EndAnyFunctionDefinition,
             is EndClassDefinition:
            activeFunctionDefinitions.removeLast()
        case is BeginMethodDefinition:
            // Finishes the previous method or constructor definition
            activeFunctionDefinitions.removeLast()
            // Then creates a new one
            fallthrough
        case is BeginAnyFunctionDefinition,
             is BeginClassDefinition:
            activeFunctionDefinitions.append(instr.op)
        default:
            // Could assert here that the operation is not related to functions with a new operation flag
            break
        }

        executeInnerEffects(instr)
        return typeChanges
    }

    private func currentlyDefinedFunctionisMethod() -> Bool {
        guard let activeFunctionDefinition = activeFunctionDefinitions.last else { return false }
        return activeFunctionDefinition is BeginClassDefinition || activeFunctionDefinition is BeginMethodDefinition
    }

    public func type(ofProperty propertyName: String) -> Type {
        return propertyTypes[propertyName] ?? .unknown
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperType() -> Type {
        if currentlyDefinedFunctionisMethod() {
            return classDefinitions.current.superType
        } else {
            return .unknown
        }
    }

    /// Sets a program wide type for the given property.
    public mutating func setType(ofProperty propertyName: String, to type: Type) {
        propertyTypes[propertyName] = type
    }

    /// Sets a program wide signature for the given method name.
    public mutating func setSignature(ofMethod methodName: String, to signature: FunctionSignature) {
        methodSignatures[methodName] = signature
    }

    public func inferMethodSignature(of methodName: String, on objType: Type) -> FunctionSignature {
        // First check global property types.
        if let signature = methodSignatures[methodName] {
            return signature
        }

        // Then check well-known methods of this execution environment.
        return environment.signature(ofMethod: methodName, on: objType)
    }

    /// Attempts to infer the signature of the given method on the given object type.
    public func inferMethodSignature(of methodName: String, on object: Variable) -> FunctionSignature {
        return inferMethodSignature(of: methodName, on: state.type(of: object))
    }

    /// Attempts to infer the type of the given property on the given object type.
    private func inferPropertyType(of propertyName: String, on objType: Type) -> Type {
        // First check global property types.
        if let type = propertyTypes[propertyName] {
            return type
        }

        // Then check well-known properties of this execution environment.
        return environment.type(ofProperty: propertyName, on: objType)
    }

    /// Attempts to infer the type of the given property on the given object type.
    private func inferPropertyType(of propertyName: String, on object: Variable) -> Type {
        return inferPropertyType(of: propertyName, on: state.type(of: object))
    }

    /// Attempts to infer the constructed type of the given constructor.
    private func inferConstructedType(of constructor: Variable) -> Type {
        if let signature = state.type(of: constructor).constructorSignature {
            return signature.outputType
        }

        return .object()
    }

    /// Attempts to infer the return value type of the given function.
    private func inferCallResultType(of function: Variable) -> Type {
        if let signature = state.type(of: function).functionSignature {
            return signature.outputType
        }

        return .unknown
    }

    public mutating func setType(of v: Variable, to t: Type) {
        // Variables must not be .anything or .nothing. For variables that can be anything, .unknown is the correct type.
        assert(t != .anything && t != .nothing)
        state.updateType(of: v, to: t)
    }

    // Set type to current state and save type change event
    private mutating func set(_ v: Variable, _ t: Type) {
        // Record type change if:
        // 1. It is first time we infered variable type
        // 2. Variable type changed
        if !state.hasType(variable: v) || state.type(of: v) != t {
            typeChanges.append((v, t))
        }
        setType(of: v, to: t)
    }

    // Execute effects that should be done before scope change
    private mutating func executeOuterEffects(_ instr: Instruction) {
        switch instr.op {

        case let op as BeginAnyFunctionDefinition:
            if op is BeginPlainFunctionDefinition {
                set(instr.output, .functionAndConstructor(op.signature))
            } else {
                set(instr.output, .function(op.signature))
            }
        case is BeginCodeString:
            set(instr.output, .string)
        case let op as BeginClassDefinition:
            var superType = Type.nothing
            if op.hasSuperclass {
                let superConstructorType = state.type(of: instr.input(0))
                superType = superConstructorType.constructorSignature?.outputType ?? .nothing
            }
            let classDefiniton = ClassDefinition(from: op, withSuperType: superType)
            classDefinitions.push(classDefiniton)
            set(instr.output, .constructor(classDefiniton.constructorSignature))
        case is EndClassDefinition:
            classDefinitions.pop()
        default:
            // Only instructions beginning block with output variables should have been handled here
            assert(instr.numOutputs == 0 || !instr.isBlockBegin)
        }
    }

    // Execute effects that should be done after scope change (if there is any)
    private mutating func executeInnerEffects(_ instr: Instruction) {
        // Helper function to process parameters
        func processParameterDeclarations(_ params: ArraySlice<Variable>, signature: FunctionSignature) {
            for (i, param) in params.enumerated() {
                let paramType = signature.inputTypes[i]
                var varType = paramType
                if paramType == .anything {
                    varType = .unknown
                }
                if paramType.isList {
                    varType = environment.arrayType
                }
                set(param, varType)
            }
        }

        func type(ofInput inputIdx: Int) -> Type {
            return state.type(of: instr.input(inputIdx))
        }

        // When interpreting instructions to determine output types, the general rule is to perform type checks on inputs
        // with the widest, most generic type (e.g. .integer, .bigint, .object), while setting output types to the most
        // specific type possible. In particular, that means that output types should always be fetched from the environment
        // (environment.intType, environment.bigIntType, environment.objectType), to give it a chance to customize the
        // basic types.
        // TODO: fetch all output types from the environment instead of hardcoding them.

        // Helper function for operations whose results
        // can only be a .bigint if an input to it is
        // a .bigint.
        func maybeBigIntOr(_ t: Type) -> Type {
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

        switch instr.op {

        case let op as LoadBuiltin:
            set(instr.output, environment.type(ofBuiltin: op.builtinName))

        case is LoadInteger:
            set(instr.output, environment.intType)

        case is LoadBigInt:
            set(instr.output, environment.bigIntType)

        case is LoadFloat:
            set(instr.output, environment.floatType)

        case is LoadString:
            set(instr.output, environment.stringType)

        case is LoadBoolean:
            set(instr.output, environment.booleanType)

        case is LoadUndefined:
            set(instr.output, .undefined)

        case is LoadNull:
            set(instr.output, .undefined)

        case is LoadRegExp:
            set(instr.output, environment.regExpType)

        case let op as CreateObject:
            var properties: [String] = []
            var methods: [String] = []
            for (i, p) in op.propertyNames.enumerated() {
                if environment.customMethodNames.contains(p) {
                    methods.append(p)
                } else if environment.customPropertyNames.contains(p) {
                    properties.append(p)
                } else if type(ofInput: i).Is(.function()) {
                    methods.append(p)
                } else {
                    properties.append(p)
                }
            }
            set(instr.output, environment.objectType + .object(withProperties: properties, withMethods: methods))

        case let op as CreateObjectWithSpread:
            var properties: [String] = []
            var methods: [String] = []
            for (i, p) in op.propertyNames.enumerated() {
                if environment.customMethodNames.contains(p) {
                    methods.append(p)
                } else if environment.customPropertyNames.contains(p) {
                    properties.append(p)
                } else if type(ofInput: i).Is(.function()) {
                    methods.append(p)
                } else {
                    properties.append(p)
                }
            }
            for i in op.propertyNames.count..<instr.numInputs {
                properties.append(contentsOf: type(ofInput: i).properties)
                methods.append(contentsOf: type(ofInput: i).methods)
            }
            set(instr.output, environment.objectType + .object(withProperties: properties, withMethods: methods))

        case is CreateArray,
             is CreateArrayWithSpread:
            set(instr.output, environment.arrayType)

        case is CreateTemplateString:
            set(instr.output, environment.stringType)

        case let op as StoreProperty:
            if environment.customMethodNames.contains(op.propertyName) {
                set(instr.input(0), type(ofInput: 0).adding(method: op.propertyName))
            } else {
                set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))
            }

        case let op as DeleteProperty:
            set(instr.input(0), type(ofInput: 0).removing(property: op.propertyName))

        case let op as LoadProperty:
            set(instr.output, inferPropertyType(of: op.propertyName, on: instr.input(0)))

        // TODO: An additional analyzer is required to determine the runtime value of the output variable generated from the following operations
        // For now we treat this as .unknown
        case is LoadElement,
             is LoadComputedProperty,
             is CallComputedMethod:
            set(instr.output, .unknown)

        case is ConditionalOperation:
            let outputType = type(ofInput: 1) | type(ofInput: 2)
            set(instr.output, outputType)

        case is CallFunction,
             is CallFunctionWithSpread:
            set(instr.output, inferCallResultType(of: instr.input(0)))

        case let op as CallMethod:
            set(instr.output, inferMethodSignature(of: op.methodName, on: instr.input(0)).outputType)

        case is Construct:
            set(instr.output, inferConstructedType(of: instr.input(0)))

        case let op as UnaryOperation:
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

        case let op as BinaryOperation:
            switch op.op {
            case .Add:
                set(instr.output, maybeBigIntOr(.primitive))
            case .Sub,
                 .Mul,
                 .Exp,
                 .Div,
                 .Mod:
                set(instr.output, maybeBigIntOr(.number))
            case .BitAnd,
                 .BitOr,
                 .Xor,
                 .LShift,
                 .RShift,
                 .UnRShift:
                set(instr.output, maybeBigIntOr(.integer))
            case .LogicAnd,
                 .LogicOr:
                set(instr.output, .boolean)
            }

        case let op as BinaryOperationAndReassign:
            switch op.op {
            case .Add:
                set(instr.input(0), maybeBigIntOr(.primitive))
            case .Sub,
                 .Mul,
                 .Exp,
                 .Div,
                 .Mod:
                set(instr.input(0), maybeBigIntOr(.number))
            case .BitAnd,
                 .BitOr,
                 .Xor,
                 .LShift,
                 .RShift,
                 .UnRShift:
                set(instr.input(0), maybeBigIntOr(.integer))
            case .LogicAnd,
                 .LogicOr:
                set(instr.input(0), .boolean)
            }

        case is TypeOf:
            set(instr.output, .string)

        case is InstanceOf:
            set(instr.output, .boolean)

        case is In:
            set(instr.output, .boolean)

        case is Dup:
            set(instr.output, type(ofInput: 0))

        case is Reassign:
            set(instr.input(0), type(ofInput: 1))

        case is Compare:
            set(instr.output, .boolean)

        case is LoadFromScope:
            set(instr.output, .unknown)

        case is Await:
            // TODO if input type is known, set to input type and possibly unwrap the Promise
            set(instr.output, .unknown)

        case let op as BeginAnyFunctionDefinition:
            processParameterDeclarations(instr.innerOutputs, signature: op.signature)

        case is BeginClassDefinition:
            // The first inner output is the implicit |this| for the constructor
            set(instr.innerOutput(0), classDefinitions.current.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), signature: classDefinitions.current.constructorSignature)

        case is BeginMethodDefinition:
            // The first inner output is the implicit |this|
            set(instr.innerOutput(0), classDefinitions.current.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), signature: classDefinitions.current.nextMethod().signature)

        case let op as CallSuperMethod:
            set(instr.output, inferMethodSignature(of: op.methodName, on: currentSuperType()).outputType)

        case let op as LoadSuperProperty:
            set(instr.output, inferPropertyType(of: op.propertyName, on: currentSuperType()))

        case is BeginFor:
            // Primitive type is currently guaranteed due to the structure of for loops
            set(instr.innerOutput, .primitive)

        case is BeginForIn:
            set(instr.innerOutput, .string)

        case is BeginForOf:
            set(instr.innerOutput, .unknown)

        case is BeginCatch:
            set(instr.innerOutput, .unknown)

        default:
            // Only simple instructions and block instruction with inner outputs are handled here
            assert(instr.numOutputs == 0 || (instr.isBlock && instr.numInnerOutputs == 0))
        }
    }
}

fileprivate struct InterpreterState {
    // Represents an execution state during abstract interpretation.
    // This type must be a reference type as it is referred to from
    // member variables as well as being part of the state stack.
    private class State {
        // Currently, the AbstractInterpreter only computes type information.
        // In the future, we could track other pieces of data here, for example
        // integer range values so we can approximate the iteration counts of
        // nested loops.
        public var types = VariableMap<Type>()
    }

    // The current execution state. There is a new level (= array of states)
    // pushed onto this stack for every CFG structure with conditional execution
    // (if-else, loops, ...). Each level then has as many states as there are
    // conditional branches, e.g. if-else has two states, if-elseif-elseif-else
    // would have four and so on.
    // Each state in the stack only stores information that was updated in the
    // corresponding block. As such, there may be a value for variable V in the
    // activeState but not it's parent (if the variable is defined only in the
    // activeState) or vice versa (if the variable was defined in the parentState
    // and not updated since).
    private var stack: [[State]]

    // Always points to the active state: the newest state in the top most level of the stack
    private var activeState: State
    // Always points to the parent state: the newest state in the second-to-top level of the stack
    private var parentState: State

    // The state at the current position. In essence, this is just a cache.
    // The same information could be retrieved by walking the state stack starting
    // from the activeState until there is a value for the queried variable.
    private var currentState: State

    init() {
        activeState = State()
        parentState = State()
        stack = [[parentState], [activeState]]
        currentState = State()
    }

    mutating func reset() {
        self = InterpreterState()
    }

    /// Update current variable types and type changes
    /// Used after block end when some states should be merged to parent
    mutating func mergeStates(typeChanges: inout [(Variable, Type)]) {
        let statesToMerge = stack.removeLast()
        var numUpdatesPerVariable = VariableMap<Int>()
        var newTypes = VariableMap<Type>()

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

            // Not all paths updates this variable, so it must be unioned with the previous type
            if c != statesToMerge.count {
                newTypes[v]! |= parentState.types[v]!
            }
        }

        // The previous parent state is now the active state
        let oldParentState = parentState
        activeState = parentState
        parentState = stack[stack.count - 2].last!

        // Update currentState and compute typeChanges
        for (v, newType) in newTypes {
            if currentState.types[v] != newType {
                typeChanges.append((v, newType))
            }

            // currentState doesn't contain the older type but actually a newer type,
            // thus we have to manually specify the old type here
            updateType(of: v, to: newType, from: oldParentState.types[v])
        }
    }

    /// Return the type of the given variable.
    /// Return .unknown for variables not available in this state.
    func type(of variable: Variable) -> Type {
        return currentState.types[variable] ?? .unknown
    }

    func hasType(variable: Variable) -> Bool {
        return currentState.types[variable] != nil
    }

    /// Set the type of the given variable in the current state.
    mutating func updateType(of v: Variable, to newType: Type, from oldType: Type? = nil) {
        // Basic consistency checking. This seems like a decent
        // place to do this since it executes frequently.
        assert(activeState === stack.last!.last!)
        assert(parentState === stack[stack.count-2].last!)

        // Save old type in parent state if it is not already there
        let oldType = oldType ?? currentState.types[v] ?? .nothing      // .nothing expresses that the variable was undefined in the parent state
        if parentState.types[v] == nil {
            parentState.types[v] = oldType
        }

        // Integrity checking: if the type of v hasn't been updated in the active
        // state yet, then the old type must be equal to the type in the parent state.
        assert(activeState.types[v] != nil || parentState.types[v] == oldType)

        activeState.types[v] = newType
        currentState.types[v] = newType
    }

    mutating func pushChildState() {
        parentState = activeState
        activeState = State()
        stack.append([activeState])
    }

    mutating func pushSiblingState(typeChanges: inout [(Variable, Type)]) {
        // Reset current state to parent state
        for (v, t) in activeState.types {
            // Do not save type change if
            // 1. Variable does not exist in sibling scope (t == .nothing)
            // 2. Variable is only local in sibling state (parent == .nothing)
            // 3. No type change happened
            if t != .nothing && parentState.types[v] != .nothing && parentState.types[v] != currentState.types[v] {
                typeChanges.append((v, parentState.types[v]!))
                currentState.types[v] = parentState.types[v]!
            }
        }

        // Create sibling state
        activeState = State()
        stack[stack.count - 1].append(activeState)
    }
}
