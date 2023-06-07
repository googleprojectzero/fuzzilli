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
    // TODO: possible improvements:
    //  - Add awareness of dead code, such as code after a return or singular operations if
    //    there is already another singular operation in the surrounding block (in which case
    //    only the first singular operation is executed at runtime)

    // The environment model from which to obtain various pieces of type information.
    private let environment: Environment

    // The current state
    private var state = AnalyzerState()

    // Parameter types for subroutines defined in the analyzed program.
    // These are keyed by the index of the start of the subroutine definition.
    private var signatures = [Int: ParameterList]()

    // Tracks the active function definitions and contains the instruction that started the function.
    private var activeFunctionDefinitions = Stack<Instruction>()

    // Stack of active object literals. Each entry contains the current type of the object created by the literal.
    // This must be a stack as object literals can be nested (e.g. an object literal inside the method of another one).
    private var activeObjectLiterals = Stack<JSType>()

    // Stack of active class definitions. As class definitions can be nested, this has to be a stack.
    private var activeClassDefinitions = Stack<ClassDefinition>()
    struct ClassDefinition {
        let output: Variable
        var constructorParameters: ParameterList = []
        let superType: JSType
        let superConstructorType: JSType
        var instanceType: JSType
        var classType: JSType
    }

    // A stack for active for loops containing the types of the loop variables.
    private var activeForLoopVariableTypes = Stack<[JSType]>()

    // The index of the last instruction that was processed. Just used for debug assertions.
    private var indexOfLastInstruction = -1

    init(for environ: Environment) {
        self.environment = environ
    }

    public mutating func reset() {
        indexOfLastInstruction = -1
        state.reset()
        signatures.removeAll()
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

        // More sanity checking: the outputs of guarded operation should be typed as .anything.
        if let op = instr.op as? GuardableOperation, op.isGuarded {
            assert(instr.allOutputs.allSatisfy({ type(of: $0).Is(.anything) }))
        }
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperType() -> JSType {
        // Access to |super| is also allowed in e.g. object methods, but there we can't know the super type.
        if activeClassDefinitions.count > 0 {
            return activeClassDefinitions.top.superType
        } else {
            return .anything
        }
    }

    /// Returns the type of the 'super' binding at the current position
    public func currentSuperConstructorType() -> JSType {
        // Access to |super| is also allowed in e.g. object methods, but there we can't know the super type.
        if activeClassDefinitions.count > 0 {
            // If the superConstructorType is .nothing it means that the current class does not extend anything.
            // In that case, accessing the super constructor type is considered a bug.
            assert(activeClassDefinitions.top.superConstructorType != .nothing)
            return activeClassDefinitions.top.superConstructorType
        } else {
            return .anything
        }
    }

    /// Sets a program-wide signature for the instruction at the given index, which must be the start of a function or method definition.
    public mutating func setParameters(forSubroutineStartingAt index: Int, to parameterTypes: ParameterList) {
        // Currently we expect this to only be used for the next instruction.
        assert(index == indexOfLastInstruction + 1)
        signatures[index] = parameterTypes
    }

    public func inferMethodSignature(of methodName: String, on objType: JSType) -> Signature {
        return environment.signature(ofMethod: methodName, on: objType)
    }

    /// Attempts to infer the signature of the given method on the given object type.
    public func inferMethodSignature(of methodName: String, on object: Variable) -> Signature {
        return inferMethodSignature(of: methodName, on: state.type(of: object))
    }

    /// Attempts to infer the type of the given property on the given object type.
    public func inferPropertyType(of propertyName: String, on objType: JSType) -> JSType {
        return environment.type(ofProperty: propertyName, on: objType)
    }

    /// Attempts to infer the type of the given property on the given object type.
    public func inferPropertyType(of propertyName: String, on object: Variable) -> JSType {
        return inferPropertyType(of: propertyName, on: state.type(of: object))
    }

    /// Attempts to infer the constructed type of the given constructor.
    public func inferConstructedType(of constructor: Variable) -> JSType {
        if let signature = state.type(of: constructor).constructorSignature, signature.outputType != .anything {
            return signature.outputType
        }
        return .object()
    }

    /// Attempts to infer the return value type of the given function.
    private func inferCallResultType(of function: Variable) -> JSType {
        if let signature = state.type(of: function).functionSignature {
            return signature.outputType
        }
        return .anything
    }

    public mutating func setType(of v: Variable, to t: JSType) {
        assert(t != .nothing)
        state.updateType(of: v, to: t)
    }

    public func type(of v: Variable) -> JSType {
        return state.type(of: v)
    }

    /// Attempts to infer the parameter types of the given subroutine definition.
    /// If parameter types have been added for this function, they are returned, otherwise generic parameter types (i.e. .anything parameters) for the parameters specified in the operation are generated.
    private func inferSubroutineParameterList(of op: BeginAnySubroutine, at index: Int) -> ParameterList {
        return signatures[index] ?? ParameterList(numParameters: op.parameters.count, hasRestParam: op.parameters.hasRestParameter)
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
        case .beginPlainFunction(let op):
            // Plain functions can also be used as constructors.
            // The return value type will only be known after fully processing the function definitions.
            set(instr.output, .functionAndConstructor(inferSubroutineParameterList(of: op, at: instr.index) => .anything))
        case .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            set(instr.output, .function(inferSubroutineParameterList(of: op, at: instr.index) => .anything))
        case .beginConstructor(let op):
            set(instr.output, .constructor(inferSubroutineParameterList(of: op, at: instr.index) => .anything))
        case .beginCodeString:
            set(instr.output, .string)
        case .beginClassDefinition(let op):
            var superType = environment.emptyObjectType
            var superConstructorType: JSType = .nothing
            if op.hasSuperclass {
                superConstructorType = state.type(of: instr.input(0))
                // If the super constructor returns anything other than .object(), then the return type will be
                // the |this| value inside the constructor. However, we don't currently support multiple signatures
                // for the same callable (the call signature and the construct signature), so here in that case
                // we just ignore the super type.
                if let constructorReturnType = superConstructorType.constructorSignature?.outputType, constructorReturnType.Is(.object()) {
                    superType = constructorReturnType
                }
            }
            let classDefiniton = ClassDefinition(output: instr.output, superType: superType, superConstructorType: superConstructorType, instanceType: superType, classType: environment.emptyObjectType)
            activeClassDefinitions.push(classDefiniton)
            set(instr.output, .anything)         // Treat the class variable as unknown until we have fully analyzed the class definition
        case .endClassDefinition:
            let cls = activeClassDefinitions.pop()
            // Can now compute the full type of the class variable
            set(cls.output, cls.classType + .constructor(cls.constructorParameters => cls.instanceType))
        default:
            // Only instructions starting a block with output variables should be handled here.
            assert(instr.numOutputs == 0 || !instr.isBlockStart)
        }
    }

    private mutating func processScopeChanges(_ instr: Instruction) {
        switch instr.op.opcode {
        case .beginObjectLiteral,
             .endObjectLiteral,
             .beginClassDefinition,
             .endClassDefinition,
             .beginClassStaticInitializer,
             .endClassStaticInitializer:
            // Object literals and class definitions don't create any conditional branches, only methods and accessors inside of them. These are handled further below.
            break
        case .beginIf:
            state.startGroupOfConditionallyExecutingBlocks()
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .beginElse:
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .endIf:
            if !state.currentBlockHasAlternativeBlock {
                // This If doesn't have an Else block, so append an empty block representing the state if the If-body is not executed.
                state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            }
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginSwitch:
            state.startSwitch()
        case .beginSwitchCase:
            state.enterSwitchCase(typeChanges: &typeChanges)
        case .beginSwitchDefaultCase:
            state.enterSwitchDefaultCase(typeChanges: &typeChanges)
        case .endSwitchCase:
            break
        case .endSwitch:
            state.endSwitch(typeChanges: &typeChanges)
        case .beginWhileLoopHeader:
            // Loop headers execute unconditionally (at least once).
            break
        case .beginDoWhileLoopBody,
             .beginDoWhileLoopHeader,
             .endDoWhileLoop:
            // Do-While loop headers _and_ bodies execute unconditionally (at least once).
            break
        case .beginForLoopInitializer,
             .beginForLoopCondition:
            // The initializer and the condition of a for-loop's header execute unconditionally.
            break
        case .beginForLoopAfterthought:
            // A for-loop's afterthought and body block execute conditionally.
            state.startGroupOfConditionallyExecutingBlocks()
            // We add an empty block to represent the state when the body and afterthought are never executed.
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            // Then we add a block to represent the state when they are executed.
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .beginForLoopBody:
            // We keep using the state for the loop afterthought here.
            // TODO, technically we should execute the body before the afterthought block...
            break
        case .endForLoop:
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginWhileLoopBody,
             .beginForInLoop,
             .beginForOfLoop,
             .beginForOfLoopWithDestruct,
             .beginRepeatLoop,
             .beginCodeString:
            state.startGroupOfConditionallyExecutingBlocks()
            // Push an empty state representing the case when the loop body (or code string) is not executed at all
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            // Push a new state tracking the types inside the loop
            state.enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        case .endWhileLoop,
             .endForInLoop,
             .endForOfLoop,
             .endRepeatLoop,
             .endCodeString:
            state.endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        case .beginObjectLiteralMethod,
             .beginObjectLiteralComputedMethod,
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
             .beginClassInstanceGetter,
             .beginClassInstanceSetter,
             .beginClassStaticMethod,
             .beginClassStaticGetter,
             .beginClassStaticSetter,
             .beginClassPrivateInstanceMethod,
             .beginClassPrivateStaticMethod:
            activeFunctionDefinitions.push(instr)
            state.startSubroutine()
        case .endObjectLiteralMethod,
             .endObjectLiteralComputedMethod,
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
             .endClassInstanceGetter,
             .endClassInstanceSetter,
             .endClassStaticMethod,
             .endClassStaticGetter,
             .endClassStaticSetter,
             .endClassPrivateInstanceMethod,
             .endClassPrivateStaticMethod:
            //
            // Infer the return type of the subroutine (if necessary for the signature).
            //
            let begin = activeFunctionDefinitions.pop()
            var defaultReturnValueType = JSType.undefined
            if begin.op is BeginConstructor {
                // For a constructor, the default return value is `this`, so use the current type of the
                // `this` object, which is the first inner output of the BeginConstructor operation.
                defaultReturnValueType = type(of: begin.innerOutput(0))
            }

            let returnValueType = state.endSubroutine(typeChanges: &typeChanges, defaultReturnValueType: defaultReturnValueType)

            // Check if the signature is needed, otherwise, we don't need the return value type.
            if begin.numOutputs == 1 {
                let funcType = state.type(of: begin.output)
                // The function variable may have been reassigned to a different function, in which case we may not have a signature anymore.
                if let signature = funcType.signature {
                    switch begin.op.opcode {
                    case .beginGeneratorFunction,
                         .beginAsyncGeneratorFunction:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => environment.generatorType))
                    case .beginAsyncFunction,
                         .beginAsyncArrowFunction:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => environment.promiseType))
                    default:
                        setType(of: begin.output, to: funcType.settingSignature(to: signature.parameters => returnValueType))
                    }
                }
            }
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
        func processParameterDeclarations(_ parameterVariables: ArraySlice<Variable>, parameters: ParameterList) {
            let types = computeParameterTypes(from: parameters)
            assert(types.count == parameterVariables.count)
            for (param, type) in zip(parameterVariables, types) {
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
            set(instr.output, environment.argumentsType)

        case .loadRegExp:
            set(instr.output, environment.regExpType)

        case .beginObjectLiteral:
            activeObjectLiterals.push(environment.emptyObjectType)

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
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeObjectLiterals.top.add(method: op.methodName)

        case .beginObjectLiteralComputedMethod(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginObjectLiteralGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            assert(instr.numInnerOutputs == 1)
            activeObjectLiterals.top.add(property: op.propertyName)

        case .beginObjectLiteralSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeObjectLiterals.top)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeObjectLiterals.top.add(property: op.propertyName)

        case .endObjectLiteral:
            let objectType = activeObjectLiterals.pop()
            set(instr.output, objectType)

        case .beginClassConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            let parameters = inferSubroutineParameterList(of: op, at: instr.index)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: parameters)
            activeClassDefinitions.top.constructorParameters = parameters

        case .classAddInstanceProperty(let op):
            activeClassDefinitions.top.instanceType.add(property: op.propertyName)

        case .beginClassInstanceMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeClassDefinitions.top.instanceType.add(method: op.methodName)

        case .beginClassInstanceGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            assert(instr.numInnerOutputs == 1)
            activeClassDefinitions.top.instanceType.add(property: op.propertyName)

        case .beginClassInstanceSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeClassDefinitions.top.instanceType.add(property: op.propertyName)

        case .classAddStaticProperty(let op):
            activeClassDefinitions.top.classType.add(property: op.propertyName)

        case .beginClassStaticInitializer:
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.classType)
            assert(instr.numInnerOutputs == 1)

        case .beginClassStaticMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.classType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeClassDefinitions.top.classType.add(method: op.methodName)

        case .beginClassStaticGetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.classType)
            assert(instr.numInnerOutputs == 1)
            activeClassDefinitions.top.classType.add(property: op.propertyName)

        case .beginClassStaticSetter(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), activeClassDefinitions.top.classType)
            assert(instr.numInnerOutputs == 2)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))
            activeClassDefinitions.top.classType.add(property: op.propertyName)

        case .beginClassPrivateInstanceMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.instanceType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginClassPrivateStaticMethod(let op):
            // The first inner output is the explicit |this|
            set(instr.innerOutput(0), activeClassDefinitions.top.classType)
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .createArray,
             .createIntArray,
             .createFloatArray,
             .createArrayWithSpread:
            set(instr.output, environment.arrayType)

        case .createTemplateString:
            set(instr.output, environment.stringType)

        case .getProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: instr.input(0)))

        case .setProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .updateProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .configureProperty(let op):
            set(instr.input(0), type(ofInput: 0).adding(property: op.propertyName))

        case .deleteProperty(let op):
            set(instr.input(0), type(ofInput: 0).removing(property: op.propertyName))
            set(instr.output, .boolean)

            // TODO: An additional analyzer is required to determine the runtime value of the input variable
        case .deleteComputedProperty,
             .deleteElement:
            set(instr.output, .boolean)

            // TODO: An additional analyzer is required to determine the runtime value of the output variable generated from the following operations
            // For now we treat this as .anything
        case .getElement,
             .getComputedProperty,
             .callComputedMethod,
             .callComputedMethodWithSpread:
            set(instr.output, .anything)

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

        case .update(let op):
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

        case .return(let op):
            if op.hasReturnValue {
                state.updateReturnValueType(to: type(ofInput: 0))
            } else {
                // TODO this isn't correct e.g. for constructors (where the return value would be `this`).
                // To fix that, we could for example add a "placeholder" return value that is replaced by
                // the default return value at the end of the subroutine.
                state.updateReturnValueType(to: .undefined)
            }

        case .destructArray:
            instr.outputs.forEach{set($0, .anything)}

        case .destructArrayAndReassign:
            instr.inputs.dropFirst().forEach{set($0, .anything)}

        case .destructObject(let op):
            for (property, output) in zip(op.properties, instr.outputs) {
                set(output, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.outputs.last!, environment.emptyObjectType)
            }

        case .destructObjectAndReassign(let op):
            for (property, input) in zip(op.properties, instr.inputs.dropFirst()) {
                set(input, inferPropertyType(of: property, on: instr.input(0)))
            }
            if op.hasRestElement {
                // TODO: Add the subset of object properties and methods captured by the rest element
                set(instr.inputs.last!, environment.emptyObjectType)
            }

        case .compare:
            set(instr.output, .boolean)

        case .loadNamedVariable:
            // We don't currently track these.
            set(instr.output, .anything)

        case .await:
            // TODO if input type is known, set to input type and possibly unwrap the Promise
            set(instr.output, .anything)

        case .yield:
            set(instr.output, .anything)

        case .eval:
            if instr.hasOneOutput {
                set(instr.output, .anything)
            }

        case .fixup:
            // As Fixup operations may change the action that they perform at runtime, we cannot statically know the output type.
            if instr.hasOneOutput {
                set(instr.output, .anything)
            }

        case .beginPlainFunction(let op as BeginAnyFunction),
             .beginArrowFunction(let op as BeginAnyFunction),
             .beginGeneratorFunction(let op as BeginAnyFunction),
             .beginAsyncFunction(let op as BeginAnyFunction),
             .beginAsyncArrowFunction(let op as BeginAnyFunction),
             .beginAsyncGeneratorFunction(let op as BeginAnyFunction):
            processParameterDeclarations(instr.innerOutputs, parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .beginConstructor(let op):
            // The first inner output is the explicit |this| parameter for the constructor
            set(instr.innerOutput(0), .object())
            processParameterDeclarations(instr.innerOutputs(1...), parameters: inferSubroutineParameterList(of: op, at: instr.index))

        case .callSuperMethod(let op):
            set(instr.output, inferMethodSignature(of: op.methodName, on: currentSuperType()).outputType)

        case .getPrivateProperty:
            // We currently don't track the types of private properties
            set(instr.output, .anything)

        case .callPrivateMethod:
            // We currently don't track the signatures of private methods
            set(instr.output, .anything)

        case .getSuperProperty(let op):
            set(instr.output, inferPropertyType(of: op.propertyName, on: currentSuperType()))

            // TODO: support superclass property assignment

        case .beginForLoopCondition:
            // For now, we use only the initial type of the loop variables (at the point of the for-loop's initializer block)
            // without tracking any type changes in the other parts of the for loop.
            let inputTypes = instr.inputs.map({ state.type(of: $0) })
            activeForLoopVariableTypes.push(inputTypes)
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForLoopAfterthought:
            let inputTypes = activeForLoopVariableTypes.top
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForLoopBody:
            let inputTypes = activeForLoopVariableTypes.pop()
            assert(inputTypes.count == instr.numInnerOutputs)
            zip(instr.innerOutputs, inputTypes).forEach({ set($0, $1) })

        case .beginForInLoop:
            set(instr.innerOutput, .string)

        case .beginForOfLoop:
            set(instr.innerOutput, .anything)

        case .beginForOfLoopWithDestruct:
            for v in instr.innerOutputs {
                set(v, .anything)
            }

        case .beginRepeatLoop(let op):
            if op.exposesLoopCounter {
                set(instr.innerOutput, .integer)
            }

        case .beginCatch:
            set(instr.innerOutput, .anything)

        default:
            // Only simple instructions and block instruction with inner outputs are handled here
            assert(instr.numOutputs == 0 || (instr.isBlock && instr.numInnerOutputs == 0))
        }

        // We explicitly type the outputs of guarded operations as .anything for two reasons:
        // (1) if the operation raises an exception, then the output will probably be `undefined`
        //     but that's not clearly specified
        // (2) typing to .anything allows us try and fix the operation at runtime (e.g. by looking
        //     at the existing methods for a method call or by selecting different inputs), in
        //     which case the return value may change. See FixupMutator.swift for more details.
        if instr.hasOutputs && instr.isGuarded {
            assert(instr.numInnerOutputs == 0)
            instr.allOutputs.forEach({ set($0, .anything) })
        }

        // We should only have parameter types for operations that start a subroutine, otherwise, something is inconsistent.
        // We could put this assert elsewhere as well, but here seems fine.
        assert(instr.op is BeginAnySubroutine || signatures[instr.index] == nil)
    }

    private func computeParameterTypes(from parameters: ParameterList) -> [JSType] {
        var types: [JSType] = []
        parameters.forEach { param in
            switch param {
            case .plain(let t):
                types.append(t)
            case .opt(let t):
                types.append(t | .undefined)
            case .rest:
                // A rest parameter will just be an array. Currently, we don't support nested array types (i.e. .iterable(of: .integer)) or so, but once we do, we'd need to update this logic.
                types.append(environment.arrayType)
            }
        }
        return types
    }

    private struct AnalyzerState {
        // Represents the execution state at one point in a CFG.
        //
        // This must be a reference type as it is referred to from
        // member variables as well as being part of the state stack.
        private class State {
            var types = VariableMap<JSType>()

            // Whether this state represents a subroutine, in which case it also
            // tracks its return value type.
            let isSubroutineState: Bool
            // Holds the current type of the return value. This is also tracked in
            // states that are not subroutines, as one of their parent states may
            // be a subroutine.
            var returnValueType = JSType.nothing
            // Whether all execution paths leading to this state have already returned,
            // in which case the return value type will not be updated again.
            var hasReturned = false

            // Whether this state represents a switch default case, which requires
            // special handling: if there is a default case in a switch, then one
            // of the cases is guaranteed to execute, otherwise not.
            let isDefaultSwitchCaseState: Bool

            init(isSubroutineState: Bool = false, isDefaultSwitchCaseState: Bool = false) {
                assert(!isSubroutineState || !isDefaultSwitchCaseState)
                self.isSubroutineState = isSubroutineState
                self.isDefaultSwitchCaseState = isDefaultSwitchCaseState
            }
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
        private var states: Stack<[State]>

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
            states = Stack([[parentState], [activeState]])
            overallState = State()
        }

        mutating func reset() {
            self = AnalyzerState()
        }

        /// Return the current type of the given variable.
        /// Return .anything for variables not available in this state.
        func type(of variable: Variable) -> JSType {
            return overallState.types[variable] ?? .anything
        }

        func hasType(for v: Variable) -> Bool {
            return overallState.types[v] != nil
        }

        /// Set the type of the given variable in the current state.
        mutating func updateType(of v: Variable, to newType: JSType, from oldType: JSType? = nil) {
            // Basic consistency checking. This seems like a decent
            // place to do this since it executes frequently.
            assert(activeState === states.top.last!)
            assert(parentState === states.secondToTop.last!)
            // If an oldType is specified, it must match the type in the next most recent state
            // (but here we just check that one of the parent states contains it).
            assert(oldType == nil || states.elementsStartingAtTop().contains(where: { $0.last!.types[v] == oldType! }))

            // Set the old type in the parent state if it doesn't yet exist to satisfy "activeState[v] != nil => parentState[v] != nil".
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

        mutating func updateReturnValueType(to t: JSType) {
            assert(states.elementsStartingAtTop().contains(where: { $0.last!.isSubroutineState }), "Handling a `return` but neither the active state nor any of its parent states represents a subroutine")
            guard !activeState.hasReturned else {
                // In this case, we have already set the return value in this branch of (conditional)
                // execution and so are executing inside dead code, so don't update the return value.
                return
            }
            activeState.returnValueType |= t
            activeState.hasReturned = true
        }

        /// Start a new group of conditionally executing blocks.
        ///
        /// At runtime, exactly one of the blocks in this group (added via `enterConditionallyExecutingBlock`) will be
        /// executed. A group of conditionally executing blocks should consist of at least two blocks, otherwise
        /// the single block will be treated as executing unconditionally.
        /// For example, an if-else would be represented by a group of two blocks, while a group representing
        /// a switch-case may contain many blocks. However, a switch-case consisting only of a default case is a
        /// a legitimate example of a group of blocks consisting of a single block (which then executes unconditionally).
        mutating func startGroupOfConditionallyExecutingBlocks() {
            parentState = activeState
            states.push([])
        }

        /// Enter a new conditionally executing block and append it to the currently active group of such blocks.
        /// As such, either this block or one of its "sibling" blocks in the current group may execute at runtime.
        mutating func enterConditionallyExecutingBlock(typeChanges: inout [(Variable, JSType)], isDefaultSwitchCaseState: Bool = false) {
            assert(states.top.isEmpty || !states.top.last!.isSubroutineState)

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

            activeState = State(isDefaultSwitchCaseState: isDefaultSwitchCaseState)
            states.top.append(activeState)
        }

        /// Finalize the current group of conditionally executing blocks.
        ///
        /// This will compute the new variable types assuming that exactly one of the blocks in the group will be executed
        /// at runtime and will then return to the previously active state.
        mutating func endGroupOfConditionallyExecutingBlocks(typeChanges: inout [(Variable, JSType)]) {
            let returnValueType = mergeNewestConditionalBlocks(typeChanges: &typeChanges, defaultReturnValueType: .nothing)
            assert(returnValueType == nil)
        }

        /// Start a new group of conditionally executing blocks representing a switch construct.
        ///
        /// We have special handling for switch blocks since they are a bit special: if there is a default
        /// case in a switch, then it's guaranteed that exactly one of the cases will execute at runtime.
        /// Otherwise, this is not guaranteed.
        mutating func startSwitch() {
            startGroupOfConditionallyExecutingBlocks()
        }

        /// Enter a new conditionally executing block representing a (regular) switch case.
        mutating func enterSwitchCase(typeChanges: inout [(Variable, JSType)]) {
            enterConditionallyExecutingBlock(typeChanges: &typeChanges)
        }

        /// Enter a new conditionally executing block representing a default switch case.
        mutating func enterSwitchDefaultCase(typeChanges: inout [(Variable, JSType)]) {
            enterConditionallyExecutingBlock(typeChanges: &typeChanges, isDefaultSwitchCaseState: true)
        }

        /// Finalizes the current group of conditionally executing blocks representing a switch construct.
        mutating func endSwitch(typeChanges: inout [(Variable, JSType)]) {
            // First check if we have a default case. If not, we need to add an empty state
            // that represents the scenario in which none of the cases is executed.
            // TODO: in case of multiple switch default cases, we should ignore all but the first one.
            let hasDefaultCase = states.top.contains(where: { $0.isDefaultSwitchCaseState })
            if !hasDefaultCase {
                // No default case, so add an empty state for the case that no case block is executed.
                enterConditionallyExecutingBlock(typeChanges: &typeChanges)
            }
            endGroupOfConditionallyExecutingBlocks(typeChanges: &typeChanges)
        }

        /// Whether the currently active block has at least one alternative block.
        var currentBlockHasAlternativeBlock: Bool {
            return states.top.count > 1
        }

        /// Start a new subroutine.
        ///
        /// Subroutines are treated as conditionally executing code, in essence similar to
        ///
        ///     if (functionIsCalled) {
        ///         function_body();
        ///     }
        ///
        /// In addition to updating variable types, subroutines also track their return value
        /// type which is returned by `leaveSubroutine()`.
        mutating func startSubroutine() {
            parentState = activeState
            // The empty state represents the execution path where the function is not executed.
            let emptyState = State()
            activeState = State(isSubroutineState: true)
            states.push([emptyState, activeState])
        }

        /// End the current subroutine.
        ///
        /// This behaves similar to `endGroupOfConditionallyExecutingBlocks()` and computes variable type changes assuming that the\
        /// function body may or may not have been executed, but it additionally computes and returns the inferred type for the subroutine's return value.
        mutating func endSubroutine(typeChanges: inout [(Variable, JSType)], defaultReturnValueType: JSType) -> JSType {
            guard let returnValueType = mergeNewestConditionalBlocks(typeChanges: &typeChanges, defaultReturnValueType: defaultReturnValueType) else {
                fatalError("Leaving a subroutine that was never entered")
            }
            return returnValueType
        }

        /// Merge the current conditional block and all its alternative blocks and compute both variable- and return value type changes.
        ///
        /// This computes the new types assuming that exactly one of the conditional blocks will execute at runtime. If the currently
        /// active state is a subroutine state, this will return the final return value type, otherwise it will return nil.
        private mutating func mergeNewestConditionalBlocks(typeChanges: inout [(Variable, JSType)], defaultReturnValueType: JSType) -> JSType? {
            let statesToMerge = states.pop()

            let maybeReturnValueType = computeReturnValueType(whenMerging: statesToMerge, defaultReturnValueType: defaultReturnValueType)
            let newTypes = computeVariableTypes(whenMerging: statesToMerge)
            makeParentStateTheActiveStateAndUpdateVariableTypes(to: newTypes, &typeChanges)

            return maybeReturnValueType
        }

        private func computeReturnValueType(whenMerging states: [State], defaultReturnValueType: JSType) -> JSType? {
            assert(states.last === activeState)

            // Need to compute how many sibling states have returned and what their overall return value type is.
            var returnedStates = 0
            var returnValueType = JSType.nothing

            for state in states {
                returnValueType |= state.returnValueType
                if state.hasReturned {
                    assert(state.returnValueType != .nothing)
                    returnedStates += 1
                }
            }

            // If the active state represents a subroutine, then we can now compute
            // the final return value type.
            // Otherwise, we may need to merge our return value type with that
            // of our parent state.
            var maybeReturnValue: JSType? = nil
            if activeState.isSubroutineState {
                assert(returnValueType == activeState.returnValueType)
                if !activeState.hasReturned {
                    returnValueType |= defaultReturnValueType
                }
                maybeReturnValue = returnValueType
            } else if !parentState.hasReturned {
                parentState.returnValueType |= returnValueType
                if returnedStates == states.count {
                    // All conditional branches have returned, so the parent state
                    // must also have returned now.
                    parentState.hasReturned = true
                }
            }
            // None of our sibling states can be a subroutine state as that wouldn't make sense semantically.
            assert(states.dropLast().allSatisfy({ !$0.isSubroutineState }))

            return maybeReturnValue
        }

        private func computeVariableTypes(whenMerging states: [State]) -> VariableMap<JSType> {
            var numUpdatesPerVariable = VariableMap<Int>()
            var newTypes = VariableMap<JSType>()

            for state in states {
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
                if c != states.count {
                    newTypes[v]! |= parentState.types[v]!
                }
            }

            return newTypes
        }

        private mutating func makeParentStateTheActiveStateAndUpdateVariableTypes(to newTypes: VariableMap<JSType>, _ typeChanges: inout [(Variable, JSType)]) {
            // The previous parent state is now the active state
            let oldParentState = parentState
            activeState = parentState
            parentState = states.secondToTop.last!
            assert(activeState === states.top.last)

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
    }
}
