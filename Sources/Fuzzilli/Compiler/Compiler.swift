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

    public init() {}

    /// The compiled code.
    private var code = Code()

    /// The environment is used to determine if an identifier identifies a builtin object.
    /// TODO we should probably use the correct target environment, with any additional builtins etc. here. But for now, we just manually add `gc` since that's relatively common.
    private var environment = JavaScriptEnvironment(additionalBuiltins: ["gc": .function()])

    /// Contains the mapping from JavaScript variables to FuzzIL variables in every active scope.
    private var scopes = Stack<[String: Variable]>()

    /// The next free FuzzIL variable.
    private var nextVariable = 0

    /// Context analyzer to track the context of the code being compiled. Used for example to distinguish switch and loop breaks.
    private var contextAnalyzer = ContextAnalyzer()

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
                    // TODO(saelo): consider caching the `undefined` value for future uses
                    initialValue = emit(LoadUndefined()).output
                }

                let declarationMode: NamedVariableDeclarationMode
                switch variableDeclaration.kind {
                case .var:
                    declarationMode = .var
                case .let:
                    declarationMode = .let
                case .const:
                    declarationMode = .const
                case .UNRECOGNIZED(let type):
                    throw CompilerError.invalidNodeError("invalid variable declaration type \(type)")
                }

                let v = emit(CreateNamedVariable(decl.name, declarationMode: declarationMode), withInputs: [initialValue]).output
                // Variables declared with .var are allowed to overwrite each other.
                assert(!currentScope.keys.contains(decl.name) || declarationMode == .var)
                mapOrRemap(decl.name, to: v)
            }

        case .functionDeclaration(let functionDeclaration):
            let parameters = convertParameters(functionDeclaration.parameters)
            let functionBegin, functionEnd: Operation
            switch functionDeclaration.type {
            case .plain:
                functionBegin = BeginPlainFunction(parameters: parameters, functionName: functionDeclaration.name)
                functionEnd = EndPlainFunction()
            case .generator:
                functionBegin = BeginGeneratorFunction(parameters: parameters, functionName: functionDeclaration.name)
                functionEnd = EndGeneratorFunction()
            case .async:
                functionBegin = BeginAsyncFunction(parameters: parameters, functionName: functionDeclaration.name)
                functionEnd = EndAsyncFunction()
            case .asyncGenerator:
                functionBegin = BeginAsyncGeneratorFunction(parameters: parameters, functionName: functionDeclaration.name)
                functionEnd = EndAsyncGeneratorFunction()
            case .UNRECOGNIZED(let type):
                throw CompilerError.invalidNodeError("invalid function declaration type \(type)")
            }

            let instr = emit(functionBegin)
            // The function may have been accessed before it was defined due to function hoisting, so
            // here we may overwrite an existing variable mapping.
            mapOrRemap(functionDeclaration.name, to: instr.output)
            try enterNewScope {
                mapParameters(functionDeclaration.parameters, to: instr.innerOutputs)
                for statement in functionDeclaration.body {
                    try compileStatement(statement)
                }
            }
            emit(functionEnd)

        case .classDeclaration(let classDeclaration):
            // The expressions for property values and computed properties need to be emitted before the class declaration is opened.
            var propertyValues = [Variable]()
            var computedPropertyKeys = [Variable]()
            for field in classDeclaration.fields {
                guard let field = field.field else {
                    throw CompilerError.invalidNodeError("missing concrete field in class declaration")
                }
                if case .property(let property) = field {
                    if property.hasValue {
                        propertyValues.append(try compileExpression(property.value))
                    }
                    if case .expression(let key) = property.key {
                        computedPropertyKeys.append(try compileExpression(key))
                    }
                }
            }

            // Reverse the arrays since we'll remove the elements in FIFO order.
            propertyValues.reverse()
            computedPropertyKeys.reverse()

            let classDecl: Instruction
            if classDeclaration.hasSuperClass {
                let superClass = try compileExpression(classDeclaration.superClass)
                classDecl = emit(BeginClassDefinition(hasSuperclass: true), withInputs: [superClass])
            } else {
                classDecl = emit(BeginClassDefinition(hasSuperclass: false))
            }
            map(classDeclaration.name, to: classDecl.output)

            for field in classDeclaration.fields {
                switch field.field! {
                case .property(let property):
                    guard let key = property.key else {
                        throw CompilerError.invalidNodeError("Missing key in class property")
                    }

                    let op: Operation
                    var inputs = [Variable]()
                    switch key {
                    case .name(let name):
                        if property.isStatic {
                            op = ClassAddStaticProperty(propertyName: name, hasValue: property.hasValue)
                        } else {
                            op = ClassAddInstanceProperty(propertyName: name, hasValue: property.hasValue)
                        }
                    case .index(let index):
                        if property.isStatic {
                            op = ClassAddStaticElement(index: index, hasValue: property.hasValue)
                        } else {
                            op = ClassAddInstanceElement(index: index, hasValue: property.hasValue)
                        }
                    case .expression:
                        inputs.append(computedPropertyKeys.removeLast())
                        if property.isStatic {
                            op = ClassAddStaticComputedProperty(hasValue: property.hasValue)
                        } else {
                            op = ClassAddInstanceComputedProperty(hasValue: property.hasValue)
                        }
                    }
                    if property.hasValue {
                        inputs.append(propertyValues.removeLast())
                    }
                    emit(op, withInputs: inputs)

                case .ctor(let constructor):
                    let parameters = convertParameters(constructor.parameters)
                    let head = emit(BeginClassConstructor(parameters: parameters))

                    try enterNewScope {
                        var parameters = head.innerOutputs
                        map("this", to: parameters.removeFirst())
                        mapParameters(constructor.parameters, to: parameters)
                        for statement in constructor.body {
                            try compileStatement(statement)
                        }
                    }

                    emit(EndClassConstructor())

                case .method(let method):
                    let parameters = convertParameters(method.parameters)
                    let head: Instruction
                    if method.isStatic {
                        head = emit(BeginClassStaticMethod(methodName: method.name, parameters: parameters))
                    } else {
                        head = emit(BeginClassInstanceMethod(methodName: method.name, parameters: parameters))
                    }

                    try enterNewScope {
                        var parameters = head.innerOutputs
                        map("this", to: parameters.removeFirst())
                        mapParameters(method.parameters, to: parameters)
                        for statement in method.body {
                            try compileStatement(statement)
                        }
                    }

                    if method.isStatic {
                        emit(EndClassStaticMethod())
                    } else {
                        emit(EndClassInstanceMethod())
                    }

                case .getter(let getter):
                    let head: Instruction
                    if getter.isStatic {
                        head = emit(BeginClassStaticGetter(propertyName: getter.name))
                    } else {
                        head = emit(BeginClassInstanceGetter(propertyName: getter.name))
                    }

                    try enterNewScope {
                        map("this", to: head.innerOutput)
                        for statement in getter.body {
                            try compileStatement(statement)
                        }
                    }

                    if getter.isStatic {
                        emit(EndClassStaticGetter())
                    } else {
                        emit(EndClassInstanceGetter())
                    }

                case .setter(let setter):
                    let head: Instruction
                    if setter.isStatic {
                        head = emit(BeginClassStaticSetter(propertyName: setter.name))
                    } else {
                        head = emit(BeginClassInstanceSetter(propertyName: setter.name))
                    }

                    try enterNewScope {
                        var parameters = head.innerOutputs
                        map("this", to: parameters.removeFirst())
                        mapParameters([setter.parameter], to: parameters)
                        for statement in setter.body {
                            try compileStatement(statement)
                        }
                    }

                    if setter.isStatic {
                        emit(EndClassStaticSetter())
                    } else {
                        emit(EndClassInstanceSetter())
                    }

                case .staticInitializer(let staticInitializer):
                    let head = emit(BeginClassStaticInitializer())

                    try enterNewScope {
                        map("this", to: head.innerOutput)
                        for statement in staticInitializer.body {
                            try compileStatement(statement)
                        }
                    }

                    emit(EndClassStaticInitializer())
                }
            }

            emit(EndClassDefinition())

        case .returnStatement(let returnStatement):
            if returnStatement.hasArgument {
                let value = try compileExpression(returnStatement.argument)
                emit(Return(hasReturnValue: true), withInputs: [value])
            } else {
                emit(Return(hasReturnValue: false))
            }

        case .directiveStatement(let directiveStatement):
            emit(Directive(directiveStatement.content))

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
            emit(BeginWhileLoopHeader())

            try enterNewScope {
                let cond = try compileExpression(whileLoop.test)
                emit(BeginWhileLoopBody(), withInputs: [cond])
            }

            try enterNewScope {
                try compileBody(whileLoop.body)
            }

            emit(EndWhileLoop())

        case .doWhileLoop(let doWhileLoop):
            emit(BeginDoWhileLoopBody())

            try enterNewScope {
                try compileBody(doWhileLoop.body)
            }

            emit(BeginDoWhileLoopHeader())

            try enterNewScope {
                let cond = try compileExpression(doWhileLoop.test)
                emit(EndDoWhileLoop(), withInputs: [cond])
            }

        case .forLoop(let forLoop):
            var loopVariables = [String]()

            // Process initializer.
            var initialLoopVariableValues = [Variable]()
            emit(BeginForLoopInitializer())
            try enterNewScope {
                if let initializer = forLoop.initializer {
                    switch initializer {
                    case .declaration(let declaration):
                        for declarator in declaration.declarations {
                            loopVariables.append(declarator.name)
                            initialLoopVariableValues.append(try compileExpression(declarator.value))
                        }
                    case .expression(let expression):
                        try compileExpression(expression)
                    }
                }
            }

            // Process condition.
            var outputs = emit(BeginForLoopCondition(numLoopVariables: loopVariables.count), withInputs: initialLoopVariableValues).innerOutputs
            var cond: Variable? = nil
            try enterNewScope {
                zip(loopVariables, outputs).forEach({ map($0, to: $1 )})
                if forLoop.hasCondition {
                    cond = try compileExpression(forLoop.condition)
                } else {
                    cond = emit(LoadBoolean(value: true)).output
                }
            }

            // Process afterthought.
            outputs = emit(BeginForLoopAfterthought(numLoopVariables: loopVariables.count), withInputs: [cond!]).innerOutputs
            try enterNewScope {
                zip(loopVariables, outputs).forEach({ map($0, to: $1 )})
                if forLoop.hasAfterthought {
                    try compileExpression(forLoop.afterthought)
                }
            }

            // Process body
            outputs = emit(BeginForLoopBody(numLoopVariables: loopVariables.count)).innerOutputs
            try enterNewScope {
                zip(loopVariables, outputs).forEach({ map($0, to: $1 )})
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

        case .breakStatement:
            // If we're in both .loop and .switch context, then the loop must be the most recent context 
            // (switch blocks don't propagate an outer .loop context) so we just need to check for .loop here
            if contextAnalyzer.context.contains(.loop){
                emit(LoopBreak())
            } else if contextAnalyzer.context.contains(.switchCase) {
                emit(SwitchBreak())
            } else {
                throw CompilerError.invalidNodeError("break statement outside of loop or switch")
            }

        case .continueStatement:
            emit(LoopContinue())

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

        case .withStatement(let withStatement):
            let object = try compileExpression(withStatement.object)
            emit(BeginWith(), withInputs: [object])
            try enterNewScope {
                try compileBody(withStatement.body)
            }
            emit(EndWith())
        case .switchStatement(let switchStatement):
            // TODO Replace the precomputation of tests with compilation of the test expressions in the cases.
            // To do this, we would need to redesign Switch statements in FuzzIL to (for example) have a BeginSwitchCaseHead, BeginSwitchCaseBody, and EndSwitchCase. 
            // Then the expression would go inside the header.
            var precomputedTests = [Variable]()
            for caseStatement in switchStatement.cases {
                if caseStatement.hasTest {
                    let test = try compileExpression(caseStatement.test)
                    precomputedTests.append(test)
                } 
            }
            let discriminant = try compileExpression(switchStatement.discriminant)
            emit(BeginSwitch(), withInputs: [discriminant])
            for caseStatement in switchStatement.cases {
                if caseStatement.hasTest {
                    emit(BeginSwitchCase(), withInputs: [precomputedTests.removeFirst()])
                } else {
                    emit(BeginSwitchDefaultCase())
                }
                try enterNewScope {
                    for statement in caseStatement.consequent {
                        try compileStatement(statement)
                    }
                }
                // We could also do an optimization here where we check if the last statement in the case is a break, and if so, we drop the last instruction
                // and set the fallsThrough flag to false.
                emit(EndSwitchCase(fallsThrough: true)) 
            }
            emit(EndSwitch())
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

        case .ternaryExpression(let ternaryExpression):
            let condition = try compileExpression(ternaryExpression.condition)
            let consequent = try compileExpression(ternaryExpression.consequent)
            let alternate = try compileExpression(ternaryExpression.alternate)
            return emit(TernaryOperation(), withInputs: [condition, consequent, alternate]).output

        case .identifier(let identifier):
            // Identifiers can generally turn into one of three things:
            //  1. A FuzzIL variable that has previously been associated with the identifier
            //  2. A LoadUndefined or LoadArguments operations if the identifier is "undefined" or "arguments" respectively
            //  3. A CreateNamedVariable operation in all other cases (typically global or hoisted variables, but could also be properties in a with statement)

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
            assert(identifier.name != "this")   // This is handled via ThisExpression
            if identifier.name == "undefined" {
                return emit(LoadUndefined()).output
            } else if identifier.name == "arguments" {
                return emit(LoadArguments()).output
            }

            // Case 3
            let v = emit(CreateNamedVariable(identifier.name, declarationMode: .none)).output
            // Cache the variable in case it is reused again to avoid emitting multiple
            // CreateNamedVariable operations for the same variable.
            map(identifier.name, to: v)
            return v

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
                let BigInt = emit(CreateNamedVariable("BigInt", declarationMode: .none)).output
                return emit(CallFunction(numArguments: 1, isGuarded: false), withInputs: [BigInt, stringValue]).output
            }

        case .stringLiteral(let literal):
            let value = literal.value.replacingOccurrences(of: "\n", with: "\\n")
            return emit(LoadString(value: value)).output

        case .templateLiteral(let templateLiteral):
            let interpolatedValues = try templateLiteral.expressions.map(compileExpression)
            let parts = templateLiteral.parts.map({ $0.replacingOccurrences(of: "\n", with: "\\n") })
            return emit(CreateTemplateString(parts: parts), withInputs: interpolatedValues).output

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
            // Check if `this` is currently mapped to a FuzzIL variable (e.g. if we're inside an object- or class method).
            if let v = lookupIdentifier("this") {
                return v
            }
            // Otherwise, emit a LoadThis.
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

            case .superMemberExpression(let superMemberExpression):
                guard superMemberExpression.isOptional == false else {
                    throw CompilerError.unsupportedFeatureError("Optional chaining is not supported in super member expressions")
                }

                guard let property = superMemberExpression.property else {
                    throw CompilerError.invalidNodeError("Missing property in super member expression")
                }

                switch property {
                case .name(let name):
                    if let op = assignmentOperator {
                        // Example: super.foo += 1
                        emit(UpdateSuperProperty(propertyName: name, operator: op), withInputs: [rhs])
                    } else {
                        // Example: super.foo = 1
                        emit(SetSuperProperty(propertyName: name), withInputs: [rhs])
                    }

                case .expression(let expr):
                    let property = try compileExpression(expr)
                    // Example: super[expr] = 1
                    emit(SetComputedSuperProperty(), withInputs: [property, rhs])
                }

            case .identifier(let identifier):
                // Try to lookup the variable belonging to the identifier. If there is none, we're (probably) dealing with
                // an access to a global variable/builtin or a hoisted variable access. In the case, create a named variable.
                let lhs = lookupIdentifier(identifier.name) ?? emit(CreateNamedVariable(identifier.name, declarationMode: .none)).output

                // Compile to a Reassign or Update operation
                switch assignmentExpression.operator {
                case "=":
                    // TODO(saelo): if we're assigning to a named variable, we could also generate a declaration
                    // of a global variable here instead. Probably it doeesn't matter in practice though.
                    emit(Reassign(), withInputs: [lhs, rhs])
                default:
                    // It's something like "+=", "-=", etc.
                    let binaryOperator = String(assignmentExpression.operator.dropLast())
                    guard let op = BinaryOperator(rawValue: binaryOperator) else {
                        throw CompilerError.invalidNodeError("Unknown assignment operator \(assignmentExpression.operator)")
                    }
                    emit(Update(op), withInputs: [lhs, rhs])
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
                } else if case .method(let method) = field {
                    if case .expression(let expression) = method.key {
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

                    let instr: Instruction
                    if case .name(let name) = method.key {
                        instr = emit(BeginObjectLiteralMethod(methodName: name, parameters: parameters))
                    } else {
                        instr = emit(BeginObjectLiteralComputedMethod(parameters: parameters), withInputs: [computedPropertyKeys.removeLast()])
                    }

                    try enterNewScope {
                        var parameters = instr.innerOutputs
                        map("this", to: parameters.removeFirst())
                        mapParameters(method.parameters, to: parameters)
                        for statement in method.body {
                            try compileStatement(statement)
                        }
                    }

                    if case .name = method.key {
                        emit(EndObjectLiteralMethod())
                    } else {
                        emit(EndObjectLiteralComputedMethod())
                    }
                case .getter(let getter):
                    guard case .name(let name) = getter.key else {
                        fatalError("Computed getters are not yet supported")
                    }
                    let instr = emit(BeginObjectLiteralGetter(propertyName: name))
                    try enterNewScope {
                        map("this", to: instr.innerOutput)
                        for statement in getter.body {
                            try compileStatement(statement)
                        }
                    }
                    emit(EndObjectLiteralGetter())
                case .setter(let setter):
                    guard case .name(let name) = setter.key else {
                        fatalError("Computed setters are not yet supported")
                    }
                    let instr = emit(BeginObjectLiteralSetter(propertyName: name))
                    try enterNewScope {
                        var parameters = instr.innerOutputs
                        map("this", to: parameters.removeFirst())
                        mapParameters([setter.parameter], to: parameters)
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
            var spreads = [Bool]()
            for elem in arrayExpression.elements {
                if elem.expression == nil {
                    if undefined == nil {
                        undefined = emit(LoadUndefined()).output
                    }
                    elements.append(undefined!)
                    spreads.append(false)
                } else {
                    if case .spreadElement(let spreadElement) = elem.expression {
                        elements.append(try compileExpression(spreadElement.argument))
                        spreads.append(true)
                    } else {
                        elements.append(try compileExpression(elem))
                        spreads.append(false)
                    }
                }
            }
            if spreads.contains(true) {
                return emit(CreateArrayWithSpread(spreads: spreads), withInputs: elements).output
            } else {
                return emit(CreateArray(numInitialValues: elements.count), withInputs: elements).output
            }

        case .functionExpression(let functionExpression):
            let parameters = convertParameters(functionExpression.parameters)
            let functionBegin, functionEnd: Operation
            let name = functionExpression.name.isEmpty ? nil : functionExpression.name
            switch functionExpression.type {
            case .plain:
                functionBegin = BeginPlainFunction(parameters: parameters, functionName: name)
                functionEnd = EndPlainFunction()
            case .generator:
                functionBegin = BeginGeneratorFunction(parameters: parameters, functionName: name)
                functionEnd = EndGeneratorFunction()
            case .async:
                functionBegin = BeginAsyncFunction(parameters: parameters, functionName: name)
                functionEnd = EndAsyncFunction()
            case .asyncGenerator:
                functionBegin = BeginAsyncGeneratorFunction(parameters: parameters, functionName: name)
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
                functionBegin = BeginArrowFunction(parameters: parameters)
                functionEnd = EndArrowFunction()
            case .async:
                functionBegin = BeginAsyncArrowFunction(parameters: parameters)
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
                    try compileBody(block)
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
                // obj.foo(...) or obj[expr](...)
                let object = try compileExpression(memberExpression.object)
                guard let property = memberExpression.property else { throw CompilerError.invalidNodeError("missing property in member expression in call expression") }
                switch property {
                case .name(let name):
                    if isSpreading {
                        return emit(CallMethodWithSpread(methodName: name, numArguments: arguments.count, spreads: spreads, isGuarded: callExpression.isOptional), withInputs: [object] + arguments).output
                    } else {
                        return emit(CallMethod(methodName: name, numArguments: arguments.count, isGuarded: callExpression.isOptional), withInputs: [object] + arguments).output
                    }
                case .expression(let expr):
                    let method = try compileExpression(expr)
                    if isSpreading {
                        return emit(CallComputedMethodWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: callExpression.isOptional), withInputs: [object, method] + arguments).output
                    } else {
                        return emit(CallComputedMethod(numArguments: arguments.count, isGuarded: callExpression.isOptional), withInputs: [object, method] + arguments).output
                    }
                }
            } else if case .superMemberExpression(let superMemberExpression) = callExpression.callee.expression {
                // super.foo(...)
                guard !isSpreading else {
                    throw CompilerError.unsupportedFeatureError("Spread calls with super are not supported")
                }
                guard case .name(let methodName) = superMemberExpression.property else {
                    throw CompilerError.invalidNodeError("Super method calls must use a property name")
                }
                guard !callExpression.isOptional else {
                    throw CompilerError.unsupportedFeatureError("Optional chaining with super method calls is not supported")
                }
                return emit(CallSuperMethod(methodName: methodName, numArguments: arguments.count), withInputs: arguments).output
            // Now check if it is a V8 intrinsic function
            } else if case .v8IntrinsicIdentifier(let v8Intrinsic) = callExpression.callee.expression {
                guard !isSpreading else { throw CompilerError.unsupportedFeatureError("Not currently supporting spread calls to V8 intrinsics") }
                let argsString = Array(repeating: "%@", count: arguments.count).joined(separator: ", ")
                return emit(Eval("%\(v8Intrinsic.name)(\(argsString))", numArguments: arguments.count, hasOutput: true), withInputs: arguments).output
            // Otherwise it's a regular function call
            } else {
                guard !callExpression.isOptional else { throw CompilerError.unsupportedFeatureError("Not currently supporting optional chaining with function calls") }
                let callee = try compileExpression(callExpression.callee)
                if isSpreading {
                    return emit(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: false), withInputs: [callee] + arguments).output
                } else {
                    return emit(CallFunction(numArguments: arguments.count, isGuarded: false), withInputs: [callee] + arguments).output
                }
            }

        case .callSuperConstructor(let callSuperConstructor):
            let (arguments, spreads) = try compileCallArguments(callSuperConstructor.arguments)
            let isSpreading = spreads.contains(true)

            if isSpreading {
                throw CompilerError.unsupportedFeatureError("Spread arguments are not supported in super constructor calls")
            }
            guard !callSuperConstructor.isOptional else {
                throw CompilerError.unsupportedFeatureError("Optional chaining is not supported in super constructor calls")
            }
            emit(CallSuperConstructor(numArguments: arguments.count), withInputs: arguments)
            // In JS, the result of calling the super constructor is just |this|, but in FuzzIL the operation doesn't have an output (because |this| is always available anyway)
            return lookupIdentifier("this")! // we can force unwrap because |this| always exists in the context where |super| exists

        case .newExpression(let newExpression):
            let callee = try compileExpression(newExpression.callee)
            let (arguments, spreads) = try compileCallArguments(newExpression.arguments)
            let isSpreading = spreads.contains(true)
            if isSpreading {
                return emit(ConstructWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: false), withInputs: [callee] + arguments).output
            } else {
                return emit(Construct(numArguments: arguments.count, isGuarded: false), withInputs: [callee] + arguments).output
            }

        case .memberExpression(let memberExpression):
            let object = try compileExpression(memberExpression.object)
            guard let property = memberExpression.property else { throw CompilerError.invalidNodeError("missing property in member expression") }
            switch property {
            case .name(let name):
                return emit(GetProperty(propertyName: name, isGuarded: memberExpression.isOptional), withInputs: [object]).output
            case .expression(let expr):
                if case .numberLiteral(let literal) = expr.expression, let index = Int64(exactly: literal.value) {
                    return emit(GetElement(index: index, isGuarded: memberExpression.isOptional), withInputs: [object]).output
                } else {
                    let property = try compileExpression(expr)
                    return emit(GetComputedProperty(isGuarded: memberExpression.isOptional), withInputs: [object, property]).output
                }
            }

        case .superMemberExpression(let superMemberExpression):
            guard superMemberExpression.isOptional == false else {
                throw CompilerError.unsupportedFeatureError("Optional chaining is not supported in super member expressions")
            }
            guard let property = superMemberExpression.property else {
                throw CompilerError.invalidNodeError("Missing property in super member expression")
            }

            switch property {
            case .name(let name):
                return emit(GetSuperProperty(propertyName: name), withInputs: []).output

            case .expression(let expr):
                if case .numberLiteral(let literal) = expr.expression, let _ = Int64(exactly: literal.value) {
                    throw CompilerError.unsupportedFeatureError("GetElement is not supported in super member expressions")
                } else {
                    let compiledProperty = try compileExpression(expr)
                    return emit(GetComputedSuperProperty(), withInputs: [compiledProperty]).output
                }
            }

        case .unaryExpression(let unaryExpression):
            if unaryExpression.operator == "typeof" {
                let argument = try compileExpression(unaryExpression.argument)
                return emit(TypeOf(), withInputs: [argument]).output
            } else if unaryExpression.operator == "void" {
                let argument = try compileExpression(unaryExpression.argument)
                return emit(Void_(), withInputs: [argument]).output
            } else if unaryExpression.operator == "delete" {
                guard case .memberExpression(let memberExpression) = unaryExpression.argument.expression else {
                    throw CompilerError.invalidNodeError("delete operator must be applied to a member expression")
                }

                let obj = try compileExpression(memberExpression.object)
                // isGuarded is true if the member expression is optional (e.g., obj?.prop)
                let isGuarded = memberExpression.isOptional

                if !memberExpression.name.isEmpty {
                    // Deleting a non-computed property (e.g., delete obj.prop)
                    let propertyName = memberExpression.name
                    let instr = emit(
                        DeleteProperty(propertyName: propertyName, isGuarded: isGuarded),
                        withInputs: [obj]
                    )
                    return instr.output
                } else {
                    // Deleting a computed property (e.g., delete obj[expr])
                    let propertyExpression = memberExpression.expression
                    let propertyExpr = propertyExpression.expression
                    let property = try compileExpression(propertyExpression)

                    if case .numberLiteral(let numberLiteral) = propertyExpr {
                        // Delete an element (e.g., delete arr[42])
                        let index = Int64(numberLiteral.value)
                        let instr = emit(
                            DeleteElement(index: index, isGuarded: isGuarded),
                            withInputs: [obj]
                        )
                        return instr.output
                    } else {
                        // Use DeleteComputedProperty for other computed properties (e.g., delete obj["key"])
                        let instr = emit(
                            DeleteComputedProperty(isGuarded: isGuarded),
                            withInputs: [obj, property]
                        )
                        return instr.output
                    }
                }
            } else {
                guard let op = UnaryOperator(rawValue: unaryExpression.operator) else {
                    throw CompilerError.invalidNodeError("invalid unary operator: \(unaryExpression.operator)")
                }
                let argument = try compileExpression(unaryExpression.argument)
                return emit(UnaryOperation(op), withInputs: [argument]).output
            }

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

        case .sequenceExpression(let sequenceExpression):
            assert(!sequenceExpression.expressions.isEmpty)
            return try sequenceExpression.expressions.map({ try compileExpression($0) }).last!

        case .v8IntrinsicIdentifier:
            fatalError("V8IntrinsicIdentifiers must be handled as part of their surrounding CallExpression")

        case .awaitExpression(let awaitExpression):
                // TODO await is also allowed at the top level of a module
                if !contextAnalyzer.context.contains(.asyncFunction) {
                    throw CompilerError.invalidNodeError("`await` is currently only supported in async functions")
                }
                let argument = try compileExpression(awaitExpression.argument)
                return emit(Await(), withInputs: [argument]).output

        }
    }

    @discardableResult
    private func emit(_ op: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        assert(op.numInputs == inputs.count)
        let outputs = (0..<op.numOutputs).map { _ in nextFreeVariable() }
        let innerOutputs = (0..<op.numInnerOutputs).map { _ in nextFreeVariable() }
        let inouts = inputs + outputs + innerOutputs
        let instr = Instruction(op, inouts: inouts, flags: .empty)
        contextAnalyzer.analyze(instr)
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

    private func remap(_ identifier: String, to v: Variable) {
        assert(scopes.top[identifier] != nil)
        scopes.top[identifier] = v
    }

    private func mapOrRemap(_ identifier: String, to v: Variable) {
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

    private func reset() {
        code = Code()
        scopes.removeAll()
        nextVariable = 0
    }
}
