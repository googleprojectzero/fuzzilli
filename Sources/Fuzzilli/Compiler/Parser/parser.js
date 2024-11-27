const Parser = require("@babel/parser");
const protobuf = require("protobufjs");
const fs = require('fs');

if (process.argv.length < 5) {
    console.error(`Usage: node ${process.argv[1]} path/to/ast.proto path/to/code.js path/to/output.ast.proto`);
    process.exit(0);
}

let astProtobufDefinitionPath = process.argv[2];
let inputFilePath = process.argv[3];
let outputFilePath = process.argv[4];

function assert(cond, msg) {
    if (!cond) {
        if (typeof msg !== 'undefined') {
            throw "Assertion failed: " + msg;
        } else {
            throw "Assertion failed";
        }
    }
}

function tryReadFile(path) {
    let content;
    try {
        content = fs.readFileSync(path, 'utf8').toString();
    } catch(err) {
        console.error(`Couldn't read ${path}: ${err}`);
        process.exit(-1);
    }
    return content;
}

// Parse the given JavaScript script and return an AST compatible with Fuzzilli's protobuf-based AST format.
function parse(script, proto) {
    let ast = Parser.parse(script, { plugins: ["v8intrinsic"] }); 
    
    function assertNoError(err) {
        if (err) throw err;
    }

    function dump(node) {
        console.log(JSON.stringify(node, null, 2));
    }

    function visitProgram(node) {
        const AST = proto.lookupType('compiler.protobuf.AST');
        let program = {statements: []};
        for (let child of node.body) {
            program.statements.push(visitStatement(child));
        }
        assertNoError(AST.verify(program));
        return AST.create(program);
    }

    // Helper function to turn misc. object into their corresponding protobuf message.
    function make(name, obj) {
            let Proto = proto.lookupType('compiler.protobuf.' + name);
            assertNoError(Proto.verify(obj));
            return Proto.create(obj);
        }

    // Helper function to turn object nodes into their corresponding protobuf message.
    const Statement = proto.lookupType('compiler.protobuf.Statement');
    function makeStatement(name, node) {
        let Proto = proto.lookupType('compiler.protobuf.' + name);
        let fieldName = name.charAt(0).toLowerCase() + name.slice(1);
        assertNoError(Proto.verify(node));
        let statement = {[fieldName]: Proto.create(node)};
        assertNoError(Statement.verify(statement));
        return Statement.create(statement);
    }

    function visitParameter(param) {
        assert(param.type == 'Identifier');
        return make('Parameter', { name: param.name });
    }

    function visitVariableDeclaration(node) {
        let kind;
        if (node.kind === "var") {
            kind = 0;
        } else if (node.kind === "let") {
            kind = 1;
        } else if (node.kind === "const") {
            kind = 2;
        } else {
            throw "Unknown variable declaration kind: " + node.kind;
        }

        let declarations = [];
        for (let decl of node.declarations) {
            assert(decl.type === 'VariableDeclarator', "Expected variable declarator nodes inside variable declaration, found " + decl.type);
            let outDecl = {name: decl.id.name};
            if (decl.init !== null) {
                outDecl.value = visitExpression(decl.init);
            }
            declarations.push(make('VariableDeclarator', outDecl));
        }

        return { kind, declarations };
    }


    function visitStatement(node) {
        switch (node.type) {
            case 'EmptyStatement': {
                return makeStatement('EmptyStatement', {});
            }
            case 'BlockStatement': {
                let body = [];
                for (let stmt of node.body) {
                    body.push(visitStatement(stmt));
                }
                return makeStatement('BlockStatement', {body});
            }
            case 'ExpressionStatement': {
                let expr = visitExpression(node.expression);
                return makeStatement('ExpressionStatement', {expression: expr});
            }
            case 'VariableDeclaration': {
                return makeStatement('VariableDeclaration', visitVariableDeclaration(node));
            }
            case 'FunctionDeclaration': {
                assert(node.id.type === 'Identifier', "Expected an identifier as function declaration name");
                let name = node.id.name;
                let type = 0; //"PLAIN";
                if (node.generator && node.async) {
                    type = 3; //"ASYNC_GENERATOR";
                } else if (node.generator) {
                    type = 1; //"GENERATOR";
                } else if (node.async) {
                    type = 2; //"ASYNC";
                }
                let parameters = node.params.map(visitParameter);
                assert(node.body.type === 'BlockStatement', "Expected block statement as function declaration body, found " + node.body.type);
                let body = node.body.body.map(visitStatement);
                return makeStatement('FunctionDeclaration', { name, type, parameters, body });
            }
            case 'ClassDeclaration': {
                let cls = {};
                cls.name = node.id.name;
                if (node.superClass !== null) {
                    cls.superClass = visitExpression(node.superClass);
                }
                cls.fields = [];
                for (let field of node.body.body) {
                    if (field.type === 'ClassProperty') {
                        let property = {};
                        property.isStatic = field.static;
                        if (field.value !== null) {
                          property.value = visitExpression(field.value);
                        }
                        if (field.computed) {
                            property.expression = visitExpression(field.key);
                        } else {
                            if (field.key.type === 'Identifier') {
                                property.name = field.key.name;
                            } else if (field.key.type === 'NumericLiteral') {
                                property.index = field.key.value;
                            } else {
                                throw "Unknown property key type: " + field.key.type + " in class declaration";
                            }
                        }
                        cls.fields.push(make('ClassField', { property: make('ClassProperty', property) }));
                    } else if (field.type === 'ClassMethod') {
                        assert(!field.shorthand);
                        assert(!field.computed);
                        assert(!field.generator);
                        assert(!field.async);
                        assert(field.key.type === 'Identifier');

                        let method = field;
                        field = {};
                        let name = method.key.name;
                        let isStatic = method.static;
                        if (method.kind === 'constructor') {
                            assert(method.body.type === 'BlockStatement');
                            assert(name === 'constructor');
                            assert(!isStatic);

                            let parameters = method.params.map(visitParameter);
                            let body = method.body.body.map(visitStatement);
                            field.ctor = make('ClassConstructor', { parameters, body });
                        } else if (method.kind === 'method') {
                            assert(method.body.type === 'BlockStatement');

                            let parameters = method.params.map(visitParameter);
                            let body = method.body.body.map(visitStatement);
                            field.method = make('ClassMethod', { name, isStatic, parameters, body });
                        } else if (method.kind === 'get') {
                            assert(method.params.length === 0);
                            assert(!method.generator && !method.async);
                            assert(method.body.type === 'BlockStatement');

                            let body = method.body.body.map(visitStatement);
                            field.getter = make('ClassGetter', { name, isStatic, body });
                        } else if (method.kind === 'set') {
                            assert(method.params.length === 1);
                            assert(!method.generator && !method.async);
                            assert(method.body.type === 'BlockStatement');

                            let parameter = visitParameter(method.params[0]);
                            let body = method.body.body.map(visitStatement);
                            field.setter = make('ClassSetter', { name, isStatic, parameter, body });
                        } else {
                            throw "Unknown method kind: " + method.kind;
                        }
                        cls.fields.push(make('ClassField', field));
                    } else if (field.type === 'StaticBlock') {
                        let body = field.body.map(visitStatement);
                        let staticInitializer = make('ClassStaticInitializer', { body });
                        cls.fields.push(make('ClassField', { staticInitializer }));
                    } else {
                        throw "Unsupported class declaration field: " + field.type;
                    }
                }
                return makeStatement('ClassDeclaration', cls);
            }
            case 'ReturnStatement': {
                if (node.argument !== null) {
                    return makeStatement('ReturnStatement', { argument: visitExpression(node.argument) });
                } else {
                    return makeStatement('ReturnStatement', {});
                }
            }
            case 'IfStatement': {
                let ifStmt = {};
                ifStmt.test = visitExpression(node.test);
                ifStmt.ifBody = visitStatement(node.consequent);
                if (node.alternate !== null) {
                    ifStmt.elseBody = visitStatement(node.alternate);
                }
                return makeStatement('IfStatement', ifStmt);
            }
            case 'WhileStatement': {
                let whileLoop = {};
                whileLoop.test = visitExpression(node.test);
                whileLoop.body = visitStatement(node.body);
                return makeStatement('WhileLoop', whileLoop);
            }
            case 'DoWhileStatement': {
                let doWhileLoop = {};
                doWhileLoop.test = visitExpression(node.test);
                doWhileLoop.body = visitStatement(node.body);
                return makeStatement('DoWhileLoop', doWhileLoop);
            }
            case 'ForStatement': {
                let forLoop = {};
                if (node.init !== null) {
                    if (node.init.type === 'VariableDeclaration') {
                        forLoop.declaration = make('VariableDeclaration', visitVariableDeclaration(node.init));
                    } else {
                        forLoop.expression = visitExpression(node.init);
                    }
                }
                if (node.test !== null) {
                    forLoop.condition = visitExpression(node.test);
                }
                if (node.update !== null) {
                    forLoop.afterthought = visitExpression(node.update);
                }
                forLoop.body = visitStatement(node.body);
                return makeStatement('ForLoop', forLoop);
            }
            case 'ForInStatement': {
                assert(node.left.type === 'VariableDeclaration', "Expected variable declaration as init part of a for-in loop, found " + node.left.type);
                assert(node.left.declarations.length === 1, "Expected exactly one variable declaration in the init part of a for-in loop");
                let decl = node.left.declarations[0];
                let forInLoop = {};
                let initDecl = { name: decl.id.name };
                assert(decl.init == null, "Expected no initial value for the variable declared as part of a for-in loop")
                forInLoop.left = make('VariableDeclarator', initDecl);
                forInLoop.right = visitExpression(node.right);
                forInLoop.body = visitStatement(node.body);
                return makeStatement('ForInLoop', forInLoop);
            }
            case 'ForOfStatement': {
                assert(node.left.type === 'VariableDeclaration', "Expected variable declaration as init part of a for-in loop, found " + node.left.type);
                assert(node.left.declarations.length === 1, "Expected exactly one variable declaration in the init part of a for-in loop");
                let decl = node.left.declarations[0];
                let forOfLoop = {};
                let initDecl = { name: decl.id.name };
                assert(decl.init == null, "Expected no initial value for the variable declared as part of a for-in loop")
                forOfLoop.left = make('VariableDeclarator', initDecl);
                forOfLoop.right = visitExpression(node.right);
                forOfLoop.body = visitStatement(node.body);
                return makeStatement('ForOfLoop', forOfLoop);
            }
            case 'BreakStatement': {
                let breakStatementProto = {};
                
                if (node.label) {
                    breakStatementProto.label = node.label.name;  // Extract the label if present
                }
                return makeStatement('BreakStatement', breakStatementProto);
            }
            case 'ContinueStatement': {
                let continueStatementProto = {};
                if (node.label) {
                    continueStatementProto.label = node.label.name;  // Extract the label if present
                }
                return makeStatement('ContinueStatement', continueStatementProto);
            }
            case 'TryStatement': {
                assert(node.block.type === 'BlockStatement', "Expected block statement as body of a try block");
                let tryStatement = {}
                tryStatement.body = node.block.body.map(visitStatement);
                assert(node.handler !== null || node.finalizer !== null, "TryStatements require either a handler or a finalizer (or both)")
                if (node.handler !== null) {
                    assert(node.handler.type === 'CatchClause', "Expected catch clause as try handler");
                    assert(node.handler.body.type === 'BlockStatement', "Expected block statement as body of a catch block");
                    let catchClause = {};
                    if (node.handler.param !== null) {
                        catchClause.parameter = visitParameter(node.handler.param);
                    }
                    catchClause.body = node.handler.body.body.map(visitStatement);
                    tryStatement.catch = make('CatchClause', catchClause);
                }
                if (node.finalizer !== null) {
                    assert(node.finalizer.type === 'BlockStatement', "Expected block statement as body of finally block");
                    let finallyClause = {};
                    finallyClause.body = node.finalizer.body.map(visitStatement);
                    tryStatement.finally = make('FinallyClause', finallyClause);
                }
                return makeStatement('TryStatement', tryStatement);
            }
            case 'ThrowStatement': {
                return makeStatement('ThrowStatement', { argument: visitExpression(node.argument) });
            }
            case 'WithStatement': {
                let withStatement = {};
                withStatement.object = visitExpression(node.object);
                withStatement.body = visitStatement(node.body);
                return makeStatement('WithStatement', withStatement);
            }
            case 'SwitchStatement': {
                let switchStatement = {};
                switchStatement.discriminant = visitExpression(node.discriminant);
                switchStatement.cases = node.cases.map(visitStatement);
                return makeStatement('SwitchStatement', switchStatement);
            }
            case "LabeledStatement": {
                let labeledStatementProto = {
                    label: node.label.name, // Store the label
                    statement: visitStatement(node.body)
                };
                return { labeledStatement: labeledStatementProto };
            }
            case 'SwitchCase': {
                let switchCase = {};
                if (node.test) {switchCase.test = visitExpression(node.test)}
                switchCase.consequent = node.consequent.map(visitStatement);
                return switchCase;
            }
            default: {
                throw "Unhandled node type " + node.type;
            }
        }
    }

    // Helper function to turn object nodes into their corresponding protobuf message.
    const Expression = proto.lookupType('compiler.protobuf.Expression');
    function makeExpression(name, node) {
        let Proto = proto.lookupType('compiler.protobuf.' + name);
        let fieldName = name.charAt(0).toLowerCase() + name.slice(1);
        assertNoError(Proto.verify(node));
        let expression = { [fieldName]: Proto.create(node) };
        assertNoError(Expression.verify(expression));
        return Expression.create(expression);
    }

    function visitExpression(node) {
        const Expression = proto.lookupType('compiler.protobuf.Expression');
        switch (node.type) {
            case 'Identifier': {
                return makeExpression('Identifier', { name: node.name });
            }
            case 'NumericLiteral': {
                return makeExpression('NumberLiteral', { value: node.value });
            }
            case 'BigIntLiteral': {
                return makeExpression('BigIntLiteral', { value: node.value });
            }
            case 'StringLiteral': {
                return makeExpression('StringLiteral', { value: node.value });
            }
            case 'TemplateLiteral': {
                let expressions = node.expressions.map(visitExpression);
                let parts = node.quasis.map((part) => part.value.raw);
                return makeExpression('TemplateLiteral', { parts, expressions });
            }
            case 'RegExpLiteral': {
                return makeExpression('RegExpLiteral', { pattern: node.pattern, flags: node.flags });
            }
            case 'BooleanLiteral': {
                return makeExpression('BooleanLiteral', { value: node.value });
            }
            case 'NullLiteral': {
                return makeExpression('NullLiteral', {});
            }
            case 'ThisExpression': {
                return makeExpression('ThisExpression', {});
            }
            case 'AssignmentExpression': {
                let operator = node.operator;
                let lhs = visitExpression(node.left);
                let rhs = visitExpression(node.right);
                return makeExpression('AssignmentExpression', { operator, lhs, rhs });
            }
            case 'ObjectExpression': {
                let fields = [];
                for (let field of node.properties) {
                    if (field.type === 'ObjectProperty') {
                        assert(!field.method);
                        let property = {};
                        property.value = visitExpression(field.value);
                        if (field.computed) {
                            property.expression = visitExpression(field.key);
                        } else {
                            if (field.key.type === 'Identifier') {
                                property.name = field.key.name;
                            } else if (field.key.type === 'NumericLiteral') {
                                property.index = field.key.value;
                            } else {
                                throw "Unknown property key type: " + field.key.type;
                            }
                        }
                        fields.push(make('ObjectField', { property: make('ObjectProperty', property) }));
                    } else {
                        assert(field.type === 'ObjectMethod');
                        assert(!field.shorthand);

                        let method = field;

                        let out = {};
                        if (method.computed) {
                            out.expression = visitExpression(method.key);
                        } else {
                            assert(method.key.type === 'Identifier')
                            out.name = method.key.name;
                        }

                        field = {};
                        if (method.kind === 'method') {
                            assert(method.body.type === 'BlockStatement');

                            let type = 0; //"PLAIN";
                            if (method.generator && method.async) {
                                out.type = 3; //"ASYNC_GENERATOR";
                            } else if (method.generator) {
                                out.type = 1; //"GENERATOR";
                            } else if (method.async) {
                                out.type = 2; //"ASYNC";
                            }
                            out.parameters = method.params.map(visitParameter);
                            out.body = method.body.body.map(visitStatement);
                            field.method = make('ObjectMethod', out);
                        } else if (method.kind === 'get') {
                            assert(method.params.length === 0);
                            assert(!method.generator && !method.async);
                            assert(method.body.type === 'BlockStatement');

                            out.body = method.body.body.map(visitStatement);
                            field.getter = make('ObjectGetter', out);
                        } else if (method.kind === 'set') {
                            assert(method.params.length === 1);
                            assert(!method.generator && !method.async);
                            assert(method.body.type === 'BlockStatement');

                            out.parameter = visitParameter(method.params[0]);
                            out.body = method.body.body.map(visitStatement);
                            field.setter = make('ObjectSetter', out);
                        } else {
                            throw "Unknown method kind: " + method.kind;
                        }
                        fields.push(make('ObjectField', field));
                    }
                }
                return makeExpression('ObjectExpression', { fields });
            }
            case 'ArrayExpression': {
                let elements = [];
                for (let elem of node.elements) {
                    if (elem == null) {
                        // Empty expressions indicate holes.
                        elements.push(Expression.create({}));
                    } else {
                        elements.push(visitExpression(elem));
                    }
                }
                return makeExpression('ArrayExpression', { elements });
            }
            case 'FunctionExpression': {
                let type = 0; //"PLAIN";
                if (node.generator && node.async) {
                    type = 3; //"ASYNC_GENERATOR";
                } else if (node.generator) {
                    type = 1; //"GENERATOR";
                } else if (node.async) {
                    type = 2; //"ASYNC";
                }
                let parameters = node.params.map(visitParameter);
                assert(node.body.type === 'BlockStatement', "Expected block statement as function expression body, found " + node.body.type);
                let body = node.body.body.map(visitStatement);
                return makeExpression('FunctionExpression', { type, parameters, body });
            }
            case 'ArrowFunctionExpression': {
                assert(node.id == null);
                assert(node.generator == false);
                let type = 0; //"PLAIN";
                if (node.async) {
                    type = 2; //"ASYNC";
                }
                let parameters = node.params.map(visitParameter);
                let out = { type, parameters };
                if (node.body.type === 'BlockStatement') {
                    out.block = visitStatement(node.body);
                } else {
                    out.expression = visitExpression(node.body);
                }
                return makeExpression('ArrowFunctionExpression', out);
            }
            case 'CallExpression':
            case 'OptionalCallExpression': {
                let callee = visitExpression(node.callee);
                let arguments = node.arguments.map(visitExpression);
                let isOptional = node.type === 'OptionalCallExpression';
                return makeExpression('CallExpression', { callee, arguments, isOptional });
            }
            case 'NewExpression': {
                let callee = visitExpression(node.callee);
                let arguments = node.arguments.map(visitExpression);
                return makeExpression('NewExpression', { callee, arguments });
            }
            case 'MemberExpression':
            case 'OptionalMemberExpression': {
                let object = visitExpression(node.object);
                let out = { object };
                if (node.computed) {
                    out.expression = visitExpression(node.property);
                } else {
                    assert(node.property.type === 'Identifier');
                    out.name = node.property.name;
                }
                out.isOptional = node.type === 'OptionalMemberExpression';
                return makeExpression('MemberExpression', out);
            }
            case 'UnaryExpression': {
                assert(node.prefix);
                let operator = node.operator;
                let argument = visitExpression(node.argument);
                return makeExpression('UnaryExpression', { operator, argument });
            }
            case 'ConditionalExpression': {
                let condition = visitExpression(node.test);
                let consequent = visitExpression(node.consequent);
                let alternate = visitExpression(node.alternate);
                return makeExpression('TernaryExpression', { condition, consequent, alternate });
            }
            case 'BinaryExpression':
            case 'LogicalExpression': {
                let operator = node.operator;
                let lhs = visitExpression(node.left);
                let rhs = visitExpression(node.right);
                return makeExpression('BinaryExpression', { operator, lhs, rhs });
            }
            case 'UpdateExpression': {
                let operator = node.operator;
                let isPrefix = node.prefix;
                let argument = visitExpression(node.argument);
                return makeExpression('UpdateExpression', { operator, isPrefix, argument });
            }
            case 'YieldExpression': {
                assert(node.delegate == false);
                if (node.argument !== null) {
                    let argument = visitExpression(node.argument);
                    return makeExpression('YieldExpression', { argument });
                } else {
                    return makeExpression('YieldExpression', {});
                }
            }
            case 'SpreadElement': {
                let argument = visitExpression(node.argument);
                return makeExpression('SpreadElement', { argument });
            }
            case 'SequenceExpression': {
                let expressions = node.expressions.map(visitExpression);
                return makeExpression('SequenceExpression', { expressions });
            }
            case 'V8IntrinsicIdentifier': {
                return makeExpression('V8IntrinsicIdentifier', { name: node.name });
            }
            default: {
                throw "Unhandled node type " + node.type;
            }
        }
    }

    return visitProgram(ast.program);
}

let script = tryReadFile(inputFilePath);

protobuf.load(astProtobufDefinitionPath, function(err, root) {
    if (err)
        throw err;

    let ast = parse(script, root);

    // Uncomment this to print the AST to stdout (will be very verbose).
    //console.log(JSON.stringify(ast, null, 2));
    
    const AST = root.lookupType('compiler.protobuf.AST');
    let buffer = AST.encode(ast).finish();

    fs.writeFileSync(outputFilePath, buffer);
    console.log("All done, output file @ " + outputFilePath);
});

