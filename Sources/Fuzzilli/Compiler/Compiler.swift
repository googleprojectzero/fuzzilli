// Copyright 2023 Google LLC
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

/// Compiles a JavaScript AST into a FuzzIL program.
public class JavaScriptCompiler {
    public typealias AST = Compiler_Protobuf_AST
    typealias StatementNode = Compiler_Protobuf_Statement
    typealias ExpressionNode = Compiler_Protobuf_Expression

    // Simple error enum for errors that are displayed to the user.
    public enum CompilerError: Error {
        case invalidASTError(String)
        case invalidNodeError(String)
        case unsupportedFeatureError(String)
    }

    public init(deletingCallTo filteredFunctions: [String] = []) {
        self.filteredFunctions = filteredFunctions
    }

    /// The compiled code.
    private var code = Code()

    /// A list of function names or prefixes (e.g. `assert*`) which should be deleted from the output program.
    /// The function calls can in general only be removed if their return value isn't used, and so currently they are only
    /// removed if they make up a full ExpressionStatement, in which case the entire statement is ignored.
    /// This functionality is useful to remove calls to functions such as `assert*` or `print*` from tests
    /// as those are not useful for fuzzing.
    /// The function names may contain the wildcard character `*`, but _only_ as last character, in which case
    /// a prefix match will be performed instead of a string comparison.
    private let filteredFunctions: [String]

    /// The environment is used to determine if an identifier identifies a builtin object.
    /// TODO we should probably use the correct target environment, with any additional builtins etc. here. But for now, we just manually add `gc` since that's relatively common.
    private var environment = JavaScriptEnvironment(additionalBuiltins: ["gc": .function()])

    /// Contains the mapping from JavaScript variables to FuzzIL variables in every active scope.
    private var scopes = Stack<[String: Variable]>()

    /// List of all named variables.
    /// TODO instead of a global list, this should be per (var) scope.
    private var namedVariables = Set<String>()

    /// The next free FuzzIL variable.
    private var nextVariable = 0

    public func compile(_ ast: AST) throws -> Program {
        reset()

        try enterNewScope {
            for statement in ast.statements {
                try compileStatement(statement)
            }
        }

        try code.check()

        return Program(code: code)
    }

    /// Allocates the next free variable.
    private func nextFreeVariable() -> Variable {
        let v = Variable(number: nextVariable)
        nextVariable += 1
        return v
    }

    private func compileStatement(_ node: StatementNode) throws {
        let shouldIgnoreStatement = try performStatementFiltering(node)
        guard !shouldIgnoreStatement else {
            return
        }

        guard let stmt = node.statement else {
            throw CompilerError.invalidASTError("missing concrete statement in statement node")
        }

        switch stmt {

        case .emptyStatement:
            break

        case .blockStatement(let blockStatement):
            emit(BeginBlockStatement())
            try enterNewScope {
                for statement in blockStatement.body {
                    try compileStatement(statement)
                }
            }
            emit(EndBlockStatement())

        case .variableDeclaration(let variableDeclaration):
            for decl in variableDeclaration.declarations {
                let initialValue: Variable
                if decl.hasValue {
                    initialValue = try compileExpression(decl.value)
                } else {
                    initialValue = emit(LoadUndefined()).output
                }

                if variableDeclaration.kind == .var && namedVariables.contains(decl.name) {
                    emit(DefineNamedVariable(decl.name), withInputs: [initialValue])
                } else {
                    map(decl.name, to: initialValue)
                }
            }

        case .functionDeclaration(let functionDeclaration):
            let parameters = convertParameters(functionDeclaration.parameters)
            let functionBegin, functionEnd: Operation
            switch functionDeclaration.type {
            case .plain:
                functionBegin = BeginPlainFunction(parameters: parameters, isStrict: false)
                functionEnd = EndPlainFunction()
            case .generator:
                functionBegin = BeginGeneratorFunction(parameters: parameters, isStrict: false)
                functionEnd = EndGeneratorFunction()
            case .async:
                functionBegin = BeginAsyncFunction(parameters: parameters, isStrict: false)
                functionEnd = EndAsyncFunction()
            case .asyncGenerator:
                functionBegin = BeginAsyncGeneratorFunction(parameters: parameters, isStrict: false)
                functionEnd = EndAsyncGeneratorFunction()
            case .UNRECOGNIZED(let type):
                throw CompilerError.invalidNodeError("invalid function declaration type \(type)")
            }

            let instr = emit(functionBegin)
            map(functionDeclaration.name, to: instr.output)
            try enterNewScope {
                mapParameters(functionDeclaration.parameters, to: instr.innerOutputs)
                for statement in functionDeclaration.body {
                    try compileStatement(statement)
                }
            }
            emit(functionEnd)

        case .returnStatement(let returnStatement):
            if returnStatement.hasArgument {
                let value = try compileExpression(returnStatement.argument)
                emit(Return(hasReturnValue: true), withInputs: [value])
            } else {
                emit(Return(hasReturnValue: false))
            }

        case .expressionStatement(let expressionStatement):
            try compileExpression(expressionStatement.expression)

        case .ifStatement(let ifStatement):
            let test = try compileExpression(ifStatement.test)
            emit(BeginIf(inverted: false), withInputs: [test])
            try enterNewScope {
                try compileBody(ifStatement.ifBody)
            }
            if ifStatement.hasElseBody {
                emit(BeginElse())
                try enterNewScope {
                    try compileBody(ifStatement.elseBody)
                }
            }
            emit(EndIf())

        case .whileLoop(let whileLoop):
            // TODO change the IL to avoid this special handling.
            if case .binaryExpression(let test) = whileLoop.test.expression, let op = Comparator(rawValue: test.operator) {
                let lhs = try compileExpression(test.lhs)
                let rhs = try compileExpression(test.rhs)
                emit(BeginWhileLoop(comparator: op), withInputs: [lhs, rhs])
            } else {
                // TODO this is probably often wrong...
                let test = try compileExpression(whileLoop.test)
                let True = emit(LoadBoolean(value: true)).output
                emit(BeginWhileLoop(comparator: .equal), withInputs: [test, True])
            }

            try enterNewScope {
                try compileBody(whileLoop.body)
            }

            emit(EndWhileLoop())

        case .doWhileLoop(let doWhileLoop):
            // TODO change the IL to avoid this special handling.
            if case .binaryExpression(let test) = doWhileLoop.test.expression, let op = Comparator(rawValue: test.operator) {
                let lhs = try compileExpression(test.lhs)
                let rhs = try compileExpression(test.rhs)
                emit(BeginDoWhileLoop(comparator: op), withInputs: [lhs, rhs])
            } else {
                // TODO this is probably often wrong...
                let test = try compileExpression(doWhileLoop.test)
                let True = emit(LoadBoolean(value: true)).output
                emit(BeginDoWhileLoop(comparator: .equal), withInputs: [test, True])
            }

            try enterNewScope {
                try compileBody(doWhileLoop.body)
            }

            emit(EndDoWhileLoop())

        case .forLoop(let forLoop):
            // TODO change the IL to avoid this special handling.

            // Process initializer.
            let initializer = forLoop.init_p;
            guard initializer.hasValue else {
                throw CompilerError.invalidNodeError("Expected an initial value in the for loop initializer")
            }
            let start = try compileExpression(initializer.value)

            // Process test expression.
            guard case .binaryExpression(let test) = forLoop.test.expression, let comparator = Comparator(rawValue: test.operator) else {
                throw CompilerError.invalidNodeError("Expected a comparison as part of the test of a for loop")
            }
            guard case .identifier(let identifier) = test.lhs.expression else {
                throw CompilerError.invalidNodeError("Expected an identifier as lhs of the test expression in a for loop")
            }
            guard identifier.name == initializer.name else {
                throw CompilerError.invalidNodeError("Expected the lhs of the test expression in a for loop to be the loop variable")
            }
            let end = try compileExpression(test.rhs)

            // Process update expression.
            guard case .updateExpression(let update) = forLoop.update.expression else {
                throw CompilerError.invalidNodeError("Expected an update expression as final part of a for loop")
            }
            guard case .identifier(let identifier) = update.argument.expression else {
                throw CompilerError.invalidNodeError("Expected an identifier as argument to the update expression in a for loop")
            }
            guard identifier.name == initializer.name else {
                throw CompilerError.invalidNodeError("Expected the update expression in a for loop to update the loop variable")
            }
            let one = emit(LoadInteger(value: 1)).output
            let op: BinaryOperator
            switch update.operator {
            case "++":
                op = .Add
            case "--":
                op = .Sub
            default:
                throw CompilerError.invalidNodeError("Unexpected operator in for loop update: \(update.operator)")
            }

            let loopVar = emit(BeginForLoop(comparator: comparator, op: op), withInputs: [start, end, one]).innerOutput
            try enterNewScope {
                map(initializer.name, to: loopVar)
                try compileBody(forLoop.body)
            }

            emit(EndForLoop())

        case .forInLoop(let forInLoop):
            let initializer = forInLoop.left;
            guard !initializer.hasValue else {
                throw CompilerError.invalidNodeError("Expected no initial value for the variable declared in a for-in loop")
            }

            let obj = try compileExpression(forInLoop.right)

            let loopVar = emit(BeginForInLoop(), withInputs: [obj]).innerOutput
            try enterNewScope {
                map(initializer.name, to: loopVar)
                try compileBody(forInLoop.body)
            }

            emit(EndForInLoop())

        case .forOfLoop(let forOfLoop):
            let initializer = forOfLoop.left;
            guard !initializer.hasValue else {
                throw CompilerError.invalidNodeError("Expected no initial value for the variable declared in a for-of loop")
            }

            let obj = try compileExpression(forOfLoop.right)

            let loopVar = emit(BeginForOfLoop(), withInputs: [obj]).innerOutput
            try enterNewScope {
                map(initializer.name, to: loopVar)
                try compileBody(forOfLoop.body)
            }

            emit(EndForOfLoop())

        case .tryStatement(let tryStatement):
            emit(BeginTry())
            try enterNewScope {
                for statement in tryStatement.body {
                    try compileStatement(statement)
                }
            }
            if tryStatement.hasCatch {
                try enterNewScope {
                    let beginCatch = emit(BeginCatch())
                    if tryStatement.catch.hasParameter {
                        map(tryStatement.catch.parameter.name, to: beginCatch.innerOutput)
                    }
                    for statement in tryStatement.catch.body {
                        try compileStatement(statement)
                    }
                }
            }
            if tryStatement.hasFinally {
                try enterNewScope {
                    emit(BeginFinally())
                    for statement in tryStatement.finally.body {
                        try compileStatement(statement)
                    }
                }
            }
            emit(EndTryCatchFinally())

        case .throwStatement(let throwStatement):
            let value = try compileExpression(throwStatement.argument)
            emit(ThrowException(), withInputs: [value])

        }
    }

    // This is essentially the same as compileStatement except that it skips a top-level BlockStatement:
    // For example, the body of a loop is a single statement. If the body consists of multiple statements
    // then the "top-level" statement is a BlockStatement. When compiling such code to FuzzIL, that
    // top-level BlockStatement should be skipped as it would otherwise turn into a separate Begin/EndBlock.
    // This does not modify the current scope, the caller is expected to do that.
    private func compileBody(_ statement: StatementNode) throws {
        if case .blockStatement(let blockStatement) = statement.statement {
            for statement in blockStatement.body {
                try compileStatement(statement)
            }
        } else {
            try compileStatement(statement)
        }
    }

    @discardableResult
    private func compileExpression(_ node: ExpressionNode) throws -> Variable {
        guard let expr = node.expression else {
            throw CompilerError.invalidASTError("missing concrete expression in expression node")
        }

        switch expr {

        case .identifier(let identifier):
            // Identifiers can generally turn into one of three things:
            //  1. A FuzzIL variable that has previously been associated with the identifier
            //  2. A LoadBuiltin operation if the identifier belongs to a builtin object (as defined by the environment)
            //  3. A LoadNamedVariable operation in all other cases (typically global or hoisted variables, but could also be properties in a with statement)

            // We currently fall-back to case 3 if none of the other works. However, this isn't quite correct as it would incorrectly deal with e.g.
            //
            // let v = 42;
            // function foo() {
            //     v = 5;
            //     var v = 3;
            // }
            // foo()
            //
            // As the `v = 5` would end up changing the outer variable.
            // TODO To deal with this correctly, we'd have to walk over the AST twice.

            // Case 1
            if let v = lookupIdentifier(identifier.name) {
                return v
            }

            // Case 2
            if environment.builtins.contains(identifier.name) {
                return emit(LoadBuiltin(builtinName: identifier.name)).output
            }

            // Case 3
            // In this case, we need to remember that this variable was accessed in the current scope.
            // If the variable access is hoisted, and the variable is defined later, then this allows
            // the variable definition to turn into a DefineNamedVariable operation.
            namedVariables.insert(identifier.name)
            return emit(LoadNamedVariable(identifier.name)).output

        case .numberLiteral(let literal):
            if let intValue = Int64(exactly: literal.value) {
                return emit(LoadInteger(value: intValue)).output
            } else {
                return emit(LoadFloat(value: literal.value)).output
            }

        case .bigIntLiteral(let literal):
            if let intValue = Int64(literal.value) {
                return emit(LoadBigInt(value: intValue)).output
            } else {
                // TODO should LoadBigInt support larger integer values (represented as string)?
                let stringValue = emit(LoadString(value: literal.value)).output
                let BigInt = emit(LoadBuiltin(builtinName: "BigInt")).output
                return emit(CallFunction(numArguments: 1), withInputs: [BigInt, stringValue]).output
            }

        case .stringLiteral(let literal):
            let value = literal.value.replacingOccurrences(of: "\n", with: "\\n")
            return emit(LoadString(value: value)).output

        case .regExpLiteral(let literal):
            guard let flags = RegExpFlags.fromString(literal.flags) else {
                throw CompilerError.invalidNodeError("invalid RegExp flags: \(literal.flags)")
            }
            return emit(LoadRegExp(pattern: literal.pattern, flags: flags)).output

        case .booleanLiteral(let literal):
            return emit(LoadBoolean(value: literal.value)).output

        case .nullLiteral:
            return emit(LoadNull()).output

        case .thisExpression:
            return emit(LoadThis()).output

        case .assignmentExpression(let assignmentExpression):
            guard let lhs = assignmentExpression.lhs.expression else {
                throw CompilerError.invalidNodeError("Missing lhs in assignment expression")
            }
            let rhs = try compileExpression(assignmentExpression.rhs)

            let assignmentOperator: BinaryOperator?
            switch assignmentExpression.operator {
            case "=":
                assignmentOperator = nil
            default:
                // It's something like "+=", "-=", etc.
                let binaryOperator = String(assignmentExpression.operator.dropLast())
                guard let op = BinaryOperator(rawValue: binaryOperator) else {
                    throw CompilerError.invalidNodeError("Unknown assignment operator \(assignmentExpression.operator)")
                }
                assignmentOperator = op
            }

            switch lhs {

            case .memberExpression(let memberExpression):
                // Compile to a Set- or Update{Property/Element/ComputedProperty} operation
                let object = try compileExpression(memberExpression.object)
                guard let property = memberExpression.property else { throw CompilerError.invalidNodeError("missing property in member expression") }
                switch property {
                case .name(let name):
                    if let op = assignmentOperator {
                        emit(UpdateProperty(propertyName: name, operator: op), withInputs: [object, rhs])
                    } else {
                        emit(SetProperty(propertyName: name), withInputs: [object, rhs])
                    }
                case .expression(let expr):
                    if case .numberLiteral(let literal) = expr.expression, let index = Int64(exactly: literal.value) {
                        if let op = assignmentOperator {
                            emit(UpdateElement(index: index, operator: op), withInputs: [object, rhs])
                        } else {
                            emit(SetElement(index: index), withInputs: [object, rhs])
                        }
                    } else {
                        let property = try compileExpression(expr)
                        if let op = assignmentOperator {
                            emit(UpdateComputedProperty(operator: op), withInputs: [object, property, rhs])
                        } else {
                            emit(SetComputedProperty(), withInputs: [object, property, rhs])
                        }
                    }
                }


            case .identifier(let identifier):
                if let lhs = lookupIdentifier(identifier.name) {
                    // Compile to a Reassign or Update operation
                    switch assignmentExpression.operator {
                    case "=":
                        emit(Reassign(), withInputs: [lhs, rhs])
                    default:
                        // It's something like "+=", "-=", etc.
                        let binaryOperator = String(assignmentExpression.operator.dropLast())
                        guard let op = BinaryOperator(rawValue: binaryOperator) else {
                            throw CompilerError.invalidNodeError("Unknown assignment operator \(assignmentExpression.operator)")
                        }
                        emit(Update(op), withInputs: [lhs, rhs])
                    }
                } else {
                    // It's (probably) a hoisted or a global variable access. Compile as a named variable.
                    switch assignmentExpression.operator {
                    case "=":
                        emit(StoreNamedVariable(identifier.name), withInputs: [rhs])
                    default:
                        // It's something like "+=", "-=", etc.
                        let binaryOperator = String(assignmentExpression.operator.dropLast())
                        guard let op = BinaryOperator(rawValue: binaryOperator) else {
                            throw CompilerError.invalidNodeError("Unknown assignment operator \(assignmentExpression.operator)")
                        }
                        let oldVal = emit(LoadNamedVariable(identifier.name)).output
                        let newVal = emit(BinaryOperation(op), withInputs: [oldVal, rhs]).output
                        emit(StoreNamedVariable(identifier.name), withInputs: [newVal])
                    }
                }

            default:
                throw CompilerError.unsupportedFeatureError("Compiler only supports assignments to object members or identifiers")
            }

            return rhs

        case .objectExpression(let objectExpression):
            // The expressions for property values and computed properties need to be emitted before the object literal is opened.
            var propertyValues = [Variable]()
            var computedPropertyKeys = [Variable]()
            for field in objectExpression.fields {
                guard let field = field.field else {
                    throw CompilerError.invalidNodeError("missing concrete field in object expression")
                }
                if case .property(let property) = field {
                    propertyValues.append(try compileExpression(property.value))
                    if case .expression(let expression) = property.key {
                        computedPropertyKeys.append(try compileExpression(expression))
                    }
                }
            }

            // Reverse the arrays since we'll remove the elements in FIFO order.
            propertyValues.reverse()
            computedPropertyKeys.reverse()

            // Now build the object literal.
            emit(BeginObjectLiteral())
            for field in objectExpression.fields {
                switch field.field! {
                case .property(let property):
                    guard let key = property.key else {
                        throw CompilerError.invalidNodeError("missing key in object expression field")
                    }
                    let inputs = [propertyValues.removeLast()]
                    switch key {
                    case .name(let name):
                        emit(ObjectLiteralAddProperty(propertyName: name), withInputs: inputs)
                    case .index(let index):
                        emit(ObjectLiteralAddElement(index: index), withInputs: inputs)
                    case .expression:
                        emit(ObjectLiteralAddComputedProperty(), withInputs: [computedPropertyKeys.removeLast()] + inputs)
                    }
                case .method(let method):
                    let parameters = convertParameters(method.parameters)
                    let instr = emit(BeginObjectLiteralMethod(methodName: method.name, parameters: parameters))
                    try enterNewScope {
                        // Ignore the explicit |this| parameter.
                        let parameterVariables = instr.innerOutputs.dropFirst()
                        mapParameters(method.parameters, to: parameterVariables)
                        for statement in method.body {
                            try compileStatement(statement)
                        }
                    }
                    emit(EndObjectLiteralMethod())
                case .getter(let getter):
                    emit(BeginObjectLiteralGetter(propertyName: getter.name))
                    try enterNewScope {
                        for statement in getter.body {
                            try compileStatement(statement)
                        }
                    }
                    emit(EndObjectLiteralGetter())
                case .setter(let setter):
                    let instr = emit(BeginObjectLiteralSetter(propertyName: setter.name))
                    try enterNewScope {
                        // Ignore the explicit |this| parameter.
                        let parameterVariables = instr.innerOutputs.dropFirst()
                        mapParameters([setter.parameter], to: parameterVariables)
                        for statement in setter.body {
                            try compileStatement(statement)
                        }
                    }
                    emit(EndObjectLiteralSetter())
                }
            }
            return emit(EndObjectLiteral()).output

        case .arrayExpression(let arrayExpression):
            var elements = [Variable]()
            var undefined: Variable? = nil
            for elem in arrayExpression.elements {
                if elem.expression == nil {
                    if undefined == nil {
                        undefined = emit(LoadUndefined()).output
                    }
                    elements.append(undefined!)
                } else {
                    elements.append(try compileExpression(elem))
                }
            }
            return emit(CreateArray(numInitialValues: elements.count), withInputs: elements).output

        case .functionExpression(let functionExpression):
            let parameters = convertParameters(functionExpression.parameters)
            let functionBegin, functionEnd: Operation
            switch functionExpression.type {
            case .plain:
                functionBegin = BeginPlainFunction(parameters: parameters, isStrict: false)
                functionEnd = EndPlainFunction()
            case .generator:
                functionBegin = BeginGeneratorFunction(parameters: parameters, isStrict: false)
                functionEnd = EndGeneratorFunction()
            case .async:
                functionBegin = BeginAsyncFunction(parameters: parameters, isStrict: false)
                functionEnd = EndAsyncFunction()
            case .asyncGenerator:
                functionBegin = BeginAsyncGeneratorFunction(parameters: parameters, isStrict: false)
                functionEnd = EndAsyncGeneratorFunction()
            case .UNRECOGNIZED(let type):
                throw CompilerError.invalidNodeError("invalid function declaration type \(type)")
            }

            let instr = emit(functionBegin)
            try enterNewScope {
                mapParameters(functionExpression.parameters, to: instr.innerOutputs)
                for statement in functionExpression.body {
                    try compileStatement(statement)
                }
            }
            emit(functionEnd)

            return instr.output

        case .arrowFunctionExpression(let arrowFunction):
            let parameters = convertParameters(arrowFunction.parameters)
            let functionBegin, functionEnd: Operation
            switch arrowFunction.type {
            case .plain:
                functionBegin = BeginArrowFunction(parameters: parameters, isStrict: false)
                functionEnd = EndArrowFunction()
            case .async:
                functionBegin = BeginAsyncArrowFunction(parameters: parameters, isStrict: false)
                functionEnd = EndAsyncArrowFunction()
            default:
                throw CompilerError.invalidNodeError("invalid arrow function type \(arrowFunction.type)")
            }

            let instr = emit(functionBegin)
            try enterNewScope {
                mapParameters(arrowFunction.parameters, to: instr.innerOutputs)
                guard let body = arrowFunction.body else { throw CompilerError.invalidNodeError("missing body in arrow function") }
                switch body {
                case .block(let block):
                    try compileStatement(block)
                case .expression(let expr):
                    let result = try compileExpression(expr)
                    emit(Return(hasReturnValue: true), withInputs: [result])
                }
            }
            emit(functionEnd)

            return instr.output

        case .callExpression(let callExpression):
            let (arguments, spreads) = try compileCallArguments(callExpression.arguments)
            let isSpreading = spreads.contains(true)

            // See if this is a function or a method call
            if case .memberExpression(let memberExpression) = callExpression.callee.expression {
                let object = try compileExpression(memberExpression.object)
                guard let property = memberExpression.property else { throw CompilerError.invalidNodeError("missing property in member expression in call expression") }
                switch property {
                case .name(let name):
                    if isSpreading {
                        return emit(CallMethodWithSpread(methodName: name, numArguments: arguments.count, spreads: spreads), withInputs: [object] + arguments).output
                    } else {
                        return emit(CallMethod(methodName: name, numArguments: arguments.count), withInputs: [object] + arguments).output
                    }
                case .expression(let expr):
                    let method = try compileExpression(expr)
                    if isSpreading {
                        return emit(CallComputedMethodWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [object, method] + arguments).output
                    } else {
                        return emit(CallComputedMethod(numArguments: arguments.count), withInputs: [object, method] + arguments).output
                    }
                }
            // Now check if it is a V8 intrinsic function
            } else if case .v8IntrinsicIdentifier(let v8Intrinsic) = callExpression.callee.expression {
                guard !isSpreading else { throw CompilerError.unsupportedFeatureError("Not currently supporting spread calls to V8 intrinsics") }
                let argsString = Array(repeating: "%@", count: arguments.count).joined(separator: ", ")
                return emit(Eval("%\(v8Intrinsic.name)(\(argsString))", numArguments: arguments.count, hasOutput: true), withInputs: arguments).output
            // Otherwise it's a regular function call
            } else {
                let callee = try compileExpression(callExpression.callee)
                if isSpreading {
                    return emit(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [callee] + arguments).output
                } else {
                    return emit(CallFunction(numArguments: arguments.count), withInputs: [callee] + arguments).output
                }
            }

        case .newExpression(let newExpression):
            let callee = try compileExpression(newExpression.callee)
            let (arguments, spreads) = try compileCallArguments(newExpression.arguments)
            let isSpreading = spreads.contains(true)
            if isSpreading {
                return emit(ConstructWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [callee] + arguments).output
            } else {
                return emit(Construct(numArguments: arguments.count), withInputs: [callee] + arguments).output
            }

        case .memberExpression(let memberExpression):
            let object = try compileExpression(memberExpression.object)
            guard let property = memberExpression.property else { throw CompilerError.invalidNodeError("missing property in member expression") }
            switch property {
            case .name(let name):
                return emit(GetProperty(propertyName: name), withInputs: [object]).output
            case .expression(let expr):
                if case .numberLiteral(let literal) = expr.expression, let index = Int64(exactly: literal.value) {
                    return emit(GetElement(index: index), withInputs: [object]).output
                } else {
                    let property = try compileExpression(expr)
                    return emit(GetComputedProperty(), withInputs: [object, property]).output
                }
            }

        case .unaryExpression(let unaryExpression):
            let argument = try compileExpression(unaryExpression.argument)

            if unaryExpression.operator == "typeof" {
                return emit(TypeOf(), withInputs: [argument]).output
            }
            guard let op = UnaryOperator(rawValue: unaryExpression.operator) else {
                throw CompilerError.invalidNodeError("invalid unary operator: \(unaryExpression.operator)")
            }
            return emit(UnaryOperation(op), withInputs: [argument]).output

        case .binaryExpression(let binaryExpression):
            let lhs = try compileExpression(binaryExpression.lhs)
            let rhs = try compileExpression(binaryExpression.rhs)
            if let op = Comparator(rawValue: binaryExpression.operator) {
                return emit(Compare(op), withInputs: [lhs, rhs]).output
            } else if let op = BinaryOperator(rawValue: binaryExpression.operator) {
                return emit(BinaryOperation(op), withInputs: [lhs, rhs]).output
            } else if binaryExpression.operator == "in" {
                return emit(TestIn(), withInputs: [lhs, rhs]).output
            } else if binaryExpression.operator == "instanceof" {
                return emit(TestInstanceOf(), withInputs: [lhs, rhs]).output
            } else {
                throw CompilerError.invalidNodeError("invalid binary operator: \(binaryExpression.operator)")
            }

        case .updateExpression(let updateExpression):
            // This is just a unary expression that modifies the argument (e.g. `++`)
            let argument = try compileExpression(updateExpression.argument)
            var stringOp = updateExpression.operator
            if !updateExpression.isPrefix {
                // The rawValue of postfix operators have an additional space at the end, which we make use of here.
                stringOp += " "
            }
            guard let op = UnaryOperator(rawValue: stringOp) else {
                throw CompilerError.invalidNodeError("invalid unary operator: \(updateExpression.operator)")
            }
            return emit(UnaryOperation(op), withInputs: [argument]).output

        case .yieldExpression(let yieldExpression):
            let argument: Variable
            if yieldExpression.hasArgument {
                argument = try compileExpression(yieldExpression.argument)
                return emit(Yield(hasArgument: true), withInputs: [argument]).output
            } else {
                return emit(Yield(hasArgument: false)).output
            }

        case .spreadElement:
            fatalError("SpreadElement must be handled as part of their surrounding expression")

        case .v8IntrinsicIdentifier:
            fatalError("V8IntrinsicIdentifiers must be handled as part of their surrounding CallExpression")

        }
    }

    @discardableResult
    private func emit(_ op: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        assert(op.numInputs == inputs.count)
        let outputs = (0..<op.numOutputs).map { _ in nextFreeVariable() }
        let innerOutputs = (0..<op.numInnerOutputs).map { _ in nextFreeVariable() }
        let inouts = inputs + outputs + innerOutputs
        let instr = Instruction(op, inouts: inouts)
        return code.append(instr)
    }

    private func enterNewScope(_ block: () throws -> ()) rethrows {
        scopes.push([:])
        try block()
        scopes.pop()
    }

    private func map(_ identifier: String, to v: Variable) {
        assert(scopes.top[identifier] == nil)
        scopes.top[identifier] = v
    }

    private func mapParameters(_ parameters: [Compiler_Protobuf_Parameter], to variables: ArraySlice<Variable>) {
        assert(parameters.count == variables.count)
        for (param, v) in zip(parameters, variables) {
            map(param.name, to: v)
        }
    }

    private func convertParameters(_ parameters: [Compiler_Protobuf_Parameter]) -> Parameters {
        return Parameters(count: parameters.count)
    }

    /// Convenience accessor for the currently active scope.
    private var currentScope: [String: Variable] {
        return scopes.top
    }

    /// Lookup the FuzzIL variable currently mapped to the given identifier, if any.
    private func lookupIdentifier(_ name: String) -> Variable? {
        for scope in scopes.elementsStartingAtTop() {
            if let v = scope[name] {
                return v
            }
        }
        return nil
    }

    private func compileCallArguments(_ args: [ExpressionNode]) throws -> ([Variable], [Bool]) {
        var variables = [Variable]()
        var spreads = [Bool]()

        for expr in args {
            if case .spreadElement(let spreadElement) = expr.expression {
                variables.append(try compileExpression(spreadElement.argument))
                spreads.append(true)
            } else {
                variables.append(try compileExpression(expr))
                spreads.append(false)
            }
        }

        assert(variables.count == spreads.count)
        return (variables, spreads)
    }

    /// Determine whether the given statement should be filtered out.
    ///
    /// Currently this function only performs function call filtering based on the `filteredFunctions` array.
    private func performStatementFiltering(_ statement: StatementNode) throws -> Bool {
        guard case .expressionStatement(let expressionStatement) = statement.statement else { return false }
        guard case .callExpression(let callExpression) = expressionStatement.expression.expression else { return false }
        guard case .identifier(let identifier) = callExpression.callee.expression else { return false }

        let functionName = identifier.name
        var shouldIgnore = false
        for filteredFunction in filteredFunctions {
            if filteredFunction.last == "*" {
                if functionName.starts(with: filteredFunction.dropLast()) {
                    shouldIgnore = true
                }
            } else {
                assert(!filteredFunction.contains("*"))
                if functionName == filteredFunction {
                    shouldIgnore = true
                }
            }
        }

        if shouldIgnore {
            // Still generate code for the arguments.
            // For example, we may still want to emit the function call for something like `assertEq(f(), 42);`
            for arg in callExpression.arguments {
                try compileExpression(arg)
            }
        }

        return shouldIgnore
    }

    private func reset() {
        code = Code()
        scopes.removeAll()
        nextVariable = 0
    }
}
