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
private struct InterpreterState {
    // Save variable changes, supports
    // 1. Nested states (function states, loop states)
    // 2. Sibling states (if/else branches)
    // We should start with 2 states, so every used state has parent state
    private var stateChangesStack = [[VariableMap<Type>()], [VariableMap<Type>()]]
    
    // The currently active state.
    private var currentState = VariableMap<Type>()

    private var activeStateChanges: VariableMap<Type> {
        get {
            return stateChangesStack.last!.last!
        }
        set {
            let idx = stateChangesStack[stateChangesStack.count - 1].count - 1
            stateChangesStack[stateChangesStack.count - 1][idx] = newValue
        }
    }

    private var parentStateChanges: VariableMap<Type> {
        get {
            return stateChangesStack[stateChangesStack.count - 2].last!
        }
        set {
            let idx = stateChangesStack[stateChangesStack.count - 2].count - 1
            stateChangesStack[stateChangesStack.count - 2][idx] = newValue
        }
    }

    public mutating func reset() {
        stateChangesStack = [[VariableMap()], [VariableMap()]]
        currentState = VariableMap()
    }

    /// Update current variable types and type changes
    /// Used after block end when some states should be merged to parent
    public mutating func mergeStates(typeChanges: inout [(Variable, Type)]) {
        let states = stateChangesStack.removeLast()
        var numUpdatesPerVariable = VariableMap<Int>()
        var newTypes = VariableMap<Type>()

        for state in states {
            for (v, t) in state {
                // Skip variable types that are out of scope as we do not care about them anymore
                guard t != .nothing else { continue }

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
            // Skip updating local variables, which go out of scope
            if activeStateChanges[v] == .nothing {
                newTypes.remove(v)
                continue
            }

            // Not all paths updates this variable, so it must be unioned with the previous type
            if c != states.count {
                newTypes[v]! |= activeStateChanges[v]!
            }
        }

        // Update currentState and add typeChanges
        for (v, newType) in newTypes {
            if currentState[v] != newType {
                typeChanges.append((v, newType))
            }

            // Propagate activeStateChanges to parentStateChanges if necessary
            // We need to keep invariant -> if there is type in active state then there is type in parent
            if parentStateChanges[v] == nil {
                parentStateChanges[v] = activeStateChanges[v]!
            }
            // Update activeStateChange and currentState
            activeStateChanges[v] = newType
            currentState[v] = newType
        }
    }

    /// Return the type of the given variable.
    /// Return .unknown for variables not available in this state.
    public func type(of variable: Variable) -> Type {
        return currentState[variable] ?? .unknown
    }

    public func hasType(variable: Variable) -> Bool {
        return currentState[variable] != nil
    }

    /// Set the type of the given variable in the current state.
    public mutating func setType(of v: Variable, to t: Type) {
        // Save type in parent state if it is not already
        if parentStateChanges[v] == nil {
            parentStateChanges[v] = currentState[v] ?? .nothing
        }
        activeStateChanges[v] = t
        // Update currentState
        currentState[v] = t
    }

    public mutating func pushChildState() {
        stateChangesStack.append([VariableMap()])
    }

    public mutating func pushSiblingState(typeChanges: inout [(Variable, Type)]) {
        // Reset last sibling state
        for (v, t) in activeStateChanges {
            // Do not save type change if
            // 1. Variable does not exist in sibling scope (t == .nothing)
            // 2. Variable is only local in sibling state (parent == .nothing)
            // 3. No type change happened
            if t != .nothing && parentStateChanges[v] != .nothing && parentStateChanges[v] != currentState[v] {
                typeChanges.append((v, parentStateChanges[v]!))
                currentState[v] = parentStateChanges[v]!
            }
        }
        // Create sibling state
        stateChangesStack[stateChangesStack.count - 1].append(VariableMap())
    }
}

/// Analyzes the types of variables.
public struct AbstractInterpreter {
    // The current state
    private var state = InterpreterState()
    
    // Program-wide property and method types.
    private var propertyTypes = [String: Type]()
    private var methodSignatures = [String: FunctionSignature]()
    
    // The environment model from which to obtain various pieces of type information.
    private let environment: Environment
    
    init(for environ: Environment) {
        self.environment = environ
    }
    
    public mutating func reset() {
        state.reset()
        propertyTypes.removeAll()
        methodSignatures.removeAll()
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
        case is BeginWhile, is BeginDoWhile, is BeginFor, is BeginForIn, is BeginForOf, is BeginAnyFunctionDefinition, is BeginCodeString:
            // Push empty state representing case when loop/function is not executed at all
            state.pushChildState()
            // Push state representing types during loop
            state.pushSiblingState(typeChanges: &typeChanges)
        case is EndWhile, is EndDoWhile, is EndFor, is EndForIn, is EndForOf, is EndAnyFunctionDefinition, is EndCodeString:
            state.mergeStates(typeChanges: &typeChanges)
        case is BeginTry:
            // Ignored for now, TODO
            break
        case is BeginCatch:
            break
        case is EndTryCatch:
            break
        case is BeginWith:
            break
        case is EndWith:
            break
        case is BeginBlockStatement:
            break
        case is EndBlockStatement:
            break
        default:
            assert(instr.isSimple)
        }

        executeInnerEffects(instr)
        return typeChanges
    }

    public func type(ofProperty propertyName: String) -> Type {
        return propertyTypes[propertyName] ?? .unknown
    }
    
    /// Sets a program wide type for the given property.
    public mutating func setType(ofProperty propertyName: String, to type: Type) {
        propertyTypes[propertyName] = type
    }
    
    /// Sets a program wide signature for the given method name.
    public mutating func setSignature(ofMethod methodName: String, to signature: FunctionSignature) {
        methodSignatures[methodName] = signature
    }
    
    /// Attempts to infer the signature of the given method on the given object type.
    public func inferMethodSignature(of methodName: String, on object: Variable) -> FunctionSignature {
        // First check global property types.
        if let signature = methodSignatures[methodName] {
            return signature
        }
        
        // Then check well-known methods of this execution environment.
        return environment.signature(ofMethod: methodName, on: state.type(of: object))
    }
    
    /// Attempts to infer the type of the given property on the given object type.
    private func inferPropertyType(of propertyName: String, on object: Variable) -> Type {
        // First check global property types.
        if let type = propertyTypes[propertyName] {
            return type
        }
        
        // Then check well-known properties of this execution environment.
        return environment.type(ofProperty: propertyName, on: state.type(of: object))
    }
    
    /// Attempts to infer the return value type if the given method on the given object type.
    private func inferMethodReturnType(of methodName: String, on obj: Variable) -> Type {
        return inferMethodSignature(of: methodName, on: obj).outputType
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
        state.setType(of: v, to: t)
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
        default:
            // Only instructions beginning block with output variables should have been handled here
            assert(instr.numOutputs == 0 || !instr.isBlockBegin)
        }
    }

    // Execute effects that should be done after scope change (if there is any)
    private mutating func executeInnerEffects(_ instr: Instruction) {
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
                } else if state.type(of: instr.input(i)).Is(.function()) {
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
                } else if state.type(of: instr.input(i)).Is(.function()) {
                    methods.append(p)
                } else {
                    properties.append(p)
                }
            }
            for i in op.propertyNames.count..<instr.numInputs {
                let v = instr.input(i)
                properties.append(contentsOf: state.type(of: v).properties)
                methods.append(contentsOf: state.type(of: v).methods)
            }
            set(instr.output, environment.objectType + .object(withProperties: properties, withMethods: methods))
            
        case is CreateArray,
             is CreateArrayWithSpread:
            set(instr.output, environment.arrayType)
            
        case let op as StoreProperty:
            if environment.customMethodNames.contains(op.propertyName) {
                set(instr.input(0), state.type(of: instr.input(0)).adding(method: op.propertyName))
            } else {
                set(instr.input(0), state.type(of: instr.input(0)).adding(property: op.propertyName))
            }
            
        case let op as DeleteProperty:
            set(instr.input(0), state.type(of: instr.input(0)).removing(property: op.propertyName))
            
        case let op as LoadProperty:
            set(instr.output, inferPropertyType(of: op.propertyName, on: instr.input(0)))
            
        case is LoadElement,
             is LoadComputedProperty:
            set(instr.output, .unknown)
            
        case is CallFunction,
             is CallFunctionWithSpread:
            set(instr.output, inferCallResultType(of: instr.input(0)))
            
        case let op as CallMethod:
            set(instr.output, inferMethodReturnType(of: op.methodName, on: instr.input(0)))
            
        case is Construct:
            set(instr.output, inferConstructedType(of: instr.input(0)))
            
        case let op as UnaryOperation:
            switch op.op {
            case .PreInc,
                 .PreDec,
                 .PostInc,
                 .PostDec:
                set(instr.input(0), .primitive)
                set(instr.output, .primitive)
            case .Plus:
                set(instr.output, .primitive)
            case .Minus:
                set(instr.output, .primitive)
            case .LogicalNot:
                set(instr.output, .boolean)
            case .BitwiseNot:
                set(instr.output, .integer)
            }
            
        case let op as BinaryOperation:
            switch op.op {
            case .Add:
                set(instr.output, .primitive)
            case .Sub,
                 .Mul,
                 .Exp,
                 .Div,
                 .Mod:
                set(instr.output, .number | .bigint)
            case .BitAnd,
                 .BitOr,
                 .Xor,
                 .LShift,
                 .RShift,
                 .UnRShift:
                set(instr.output, .integer | .bigint)
            case .LogicAnd,
                 .LogicOr:
                set(instr.output, .boolean)
            }
            
        case is TypeOf:
            set(instr.output, .string)
            
        case is InstanceOf:
            set(instr.output, .boolean)
            
        case is In:
            set(instr.output, .boolean)
            
        case is Dup:
            set(instr.output, state.type(of: instr.input(0)))
            
        case is Reassign:
            set(instr.input(0), state.type(of: instr.input(1)))
            
        case is Compare:
            set(instr.output, .boolean)
            
        case is LoadFromScope:
            set(instr.output, .unknown)
            
        case is Await:
            // TODO if input type is known, set to input type and possibly unwrap the Promise
            set(instr.output, .unknown)
            
        case let op as BeginAnyFunctionDefinition:
            // Update only inner variable types
            for (i, param) in instr.innerOutputs.enumerated() {
                let paramType = op.signature.inputTypes[i]
                var varType = paramType
                if paramType == .anything {
                    varType = .unknown
                }
                if paramType.isList {
                    // Could also make it an array? Or fetch the type from the Environment
                    varType = .object()
                }
                set(param, varType)
            }

        case is BeginFor:
            // Primitive type is currently guaranteed due to the structure of for loops
            set(instr.innerOutput, .primitive)
            
        case is BeginForIn:
            set(instr.innerOutput, .string)
            
        case is BeginForOf:
            set(instr.innerOutput, .unknown)
            
        case is BeginCatch:
            set(instr.innerOutput, .unknown)
            
        case is BeginCodeString:
            // Type of output variable was set in outer execution block
            break

        default:
            assert(!instr.hasOutputs)
        }
        
        // Variables must not be .anything or .nothing. For variables that can be anything, .unknown is the correct type.
        assert(instr.allOutputs.allSatisfy({ state.type(of: $0) != .anything && state.type(of: $0) != .nothing }))
    }
}
