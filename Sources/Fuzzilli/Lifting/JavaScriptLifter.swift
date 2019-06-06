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

/// Lifts a FuzzIL program to JavaScript.
public class JavaScriptLifter: ComponentBase, Lifter {
    /// Prefix and suffix to surround the emitted code in
    private let prefix: String
    private let suffix: String
    
    /// The inlining policy to follow. This influences to look of the emitted code.
    let policy: InliningPolicy
    
    /// The identifier to refer to the global object.
    ///
    /// For node.js this is "global", otherwise probably just "this".
    let globalObjectIdentifier: String
    
    /// Supported versions of the ECMA standard.
    enum ECMAScriptVersion {
        case es5
        case es6
    }
    
    /// The version of the ECMAScript standard that this lifter generates code for.
    let version: ECMAScriptVersion

    public init(prefix: String = "", suffix: String = "", inliningPolicy: InliningPolicy, globalObjectIdentifier: String = "this") {
        self.prefix = prefix
        self.suffix = suffix
        self.policy = inliningPolicy
        self.globalObjectIdentifier = globalObjectIdentifier
        self.version = .es6
        
        super.init(name: "JavaScriptLifter")
    }
 
    public func lift(_ program: Program) -> String {
        var w = ScriptWriter()
        
        // Analyze the program to determine the uses of a variable
        var analyzer = DefUseAnalyzer(for: program)
        
        // Associates variables with the expressions that produce them
        // TODO use VariableMap here?
        var expressions = [Variable: Expression]()
        func expr(for v: Variable) -> Expression {
            return expressions[v] ?? Identifier.new(v.identifier)
        }
        
        w.emitBlock(prefix)
        
        let varDecl = version == .es6 ? "let" : "var"
        let constDecl = version == .es6 ? "const" : "var"
        
        for instr in program {
            // Conveniece access to inputs
            func input(_ idx: Int) -> Expression {
                return expr(for: instr.input(idx))
            }
            func value(_ idx: Int) -> Any? {
                switch analyzer.definition(of: instr.input(idx)).operation {
                case let op as LoadInteger:
                    return op.value
                case let op as LoadFloat:
                    return op.value
                case let op as LoadString:
                    return op.value
                default:
                    return nil
                }
            }
            
            var output: Expression? = nil
            
            switch instr.operation {
            case is Nop:
                break
                
            case let op as LoadInteger:
                output = NumberLiteral.new(String(op.value))
                
            case let op as LoadFloat:
                if op.value.isNaN {
                    output = Identifier.new("NaN")
                } else if op.value.isEqual(to: -Double.infinity) {
                    output = UnaryExpression.new("-Infinity")
                } else if op.value.isEqual(to: Double.infinity) {
                    output = Identifier.new("Infinity")
                } else {
                    output = NumberLiteral.new(String(op.value))
                }
                
            case let op as LoadString:
                output = Literal.new() <> "\"" <> op.value <> "\""
                
            case let op as LoadBoolean:
                output = Literal.new(op.value ? "true" : "false")
                
            case is LoadUndefined:
                output = Identifier.new("undefined")
                
            case is LoadNull:
                output = Literal.new("null")
                
            case let op as CreateObject:
                var properties = [String]()
                for (index, propertyName) in op.propertyNames.enumerated() {
                    properties.append(propertyName + ":" + input(index))
                }
                output = ObjectLiteral.new("{" + properties.joined(separator: ",") + "}")
                
            case is CreateArray:
                let elems = instr.inputs.map({ expr(for: $0).text }).joined(separator: ",")
                output = ArrayLiteral.new("[" + elems + "]")
                
            case let op as CreateObjectWithSpread:
                var properties = [String]()
                for (index, propertyName) in op.propertyNames.enumerated() {
                    properties.append(propertyName + ":" + input(index))
                }
                // Remaining ones are spread.
                for v in instr.inputs.dropFirst(properties.count) {
                    properties.append("..." + expr(for: v).text)
                }
                output = ObjectLiteral.new("{" + properties.joined(separator: ",") + "}")
                
            case let op as CreateArrayWithSpread:
                var elems = [String]()
                for (i, v) in instr.inputs.enumerated() {
                    if op.spreads[i] {
                        elems.append("..." + expr(for: v).text)
                    } else {
                        elems.append(expr(for: v).text)
                    }
                }
                output = ArrayLiteral.new("[" + elems.joined(separator: ",") + "]")
                
            case let op as LoadBuiltin:
                output = Identifier.new(op.builtinName)
                
            case let op as LoadProperty:
                output = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                
            case let op as StoreProperty:
                let dest = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(1)
                w.emit(expr)
                
            case let op as DeleteProperty:
                let target = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                let expr = UnaryExpression.new() <> "delete " <> target
                w.emit(expr)
                
            case let op as LoadElement:
                output = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                
            case let op as StoreElement:
                let dest = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(1)
                w.emit(expr)
                
            case let op as DeleteElement:
                let target = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                let expr = UnaryExpression.new() <> "delete " <> target
                w.emit(expr)
                
            case is LoadComputedProperty:
                output = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                
            case is StoreComputedProperty:
                let dest = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(2)
                w.emit(expr)
                
            case is DeleteComputedProperty:
                let target = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                let expr = UnaryExpression.new() <> "delete " <> target
                w.emit(expr)
                
            case is TypeOf:
                output = UnaryExpression.new() <> "typeof " <> input(0)
                
            case is InstanceOf:
                output = BinaryExpression.new() <> input(0) <> " instanceof " <> input(1)
                
            case is In:
                output = BinaryExpression.new() <> input(0) <> " in " <> input(1)
                
            case let op as BeginFunctionDefinition:
                var identifiers = instr.innerOutputs.map({ $0.identifier })
                if op.hasRestParam, let last = instr.innerOutputs.last {
                    identifiers[identifiers.endIndex - 1] = "..." + last.identifier
                }

                let params = identifiers.joined(separator: ",")
                w.emit("function \(instr.output)(\(params)) {")
                w.increaseIndentionLevel()
                if (op.isJSStrictMode) {
                    w.emit("'use strict'")
                }
                
            case is Return:
                w.emit("return \(input(0));")
                
            case is EndFunctionDefinition:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is CallFunction:
                let arguments = instr.inputs.dropFirst().map({ expr(for: $0).text })
                output = CallExpression.new() <> input(0) <> "(" <> arguments.joined(separator: ",") <> ")"
                
            case let op as CallMethod:
                let arguments = instr.inputs.dropFirst().map({ expr(for: $0).text })
                let method = MemberExpression.new() <> input(0) <> "." <> op.methodName
                output = CallExpression.new() <> method <> "(" <> arguments.joined(separator: ",") <> ")"
                
            case is Construct:
                let arguments = instr.inputs.dropFirst().map({ expr(for: $0).text })
                output = NewExpression.new() <> "new " <> input(0) <> "(" <> arguments.joined(separator: ",") <> ")"
                
            case let op as CallFunctionWithSpread:
                var arguments = [String]()
                for (i, v) in instr.inputs.dropFirst().enumerated() {
                    if op.spreads[i] {
                        arguments.append("..." + expr(for: v).text)
                    } else {
                        arguments.append(expr(for: v).text)
                    }
                }
                output = CallExpression.new() <> input(0) <> "(" <> arguments.joined(separator: ",") <> ")"
                
            case let op as UnaryOperation:
                if op.op == .Inc {
                    output = BinaryExpression.new() <> input(0) <> " + 1"
                } else if op.op == .Dec {
                    output = BinaryExpression.new() <> input(0) <> " - 1"
                } else {
                    output = UnaryExpression.new() <> op.op.token <> input(0)
                }
                
            case let op as BinaryOperation:
                output = BinaryExpression.new() <> input(0) <> " " <> op.op.token <> " " <> input(1)
                
            case is Phi:
                w.emit("\(varDecl) \(instr.output) = \(input(0));")
                
            case is Copy:
                w.emit("\(instr.input(0)) = \(input(1));")
                
            case let op as Compare:
                output = BinaryExpression.new() <> input(0) <> " " <> op.comparator.token <> " " <> input(1)
                
            case let op as Eval:
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var string = op.string
                for v in instr.inputs {
                    let range = string.range(of: "%@")!
                    string.replaceSubrange(range, with: expr(for: v).text)
                }
                w.emit(string)
                
            case is BeginWith:
                w.emit("with (\(input(0))) {")
                w.increaseIndentionLevel()
                
            case is EndWith:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case let op as LoadFromScope:
                output = Identifier.new(op.id)
                
            case let op as StoreToScope:
                w.emit("\(op.id) = \(input(0));")
                
            case is BeginIf:
                w.emit("if (\(input(0))) {")
                w.increaseIndentionLevel()
                
            case is BeginElse:
                w.decreaseIndentionLevel()
                w.emit("} else {")
                w.increaseIndentionLevel()
                
            case is EndIf:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case let op as BeginWhile:
                let cond = BinaryExpression.new() <> input(0) <> " " <> op.comparator.token <> " " <> input(1)
                w.emit("while (\(cond)) {")
                w.increaseIndentionLevel()
                
            case is EndWhile:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is BeginDoWhile:
                w.emit("do {")
                w.increaseIndentionLevel()
                
            case let op as EndDoWhile:
                w.decreaseIndentionLevel()
                let cond = BinaryExpression.new() <> input(0) <> " " <> op.comparator.token <> " " <> input(1)
                w.emit("} while (\(cond));")
                
            case let op as BeginFor:
                let loopVar = Identifier.new(instr.innerOutput.identifier)
                let cond = BinaryExpression.new() <> loopVar <> " " <> op.comparator.token <> " " <> input(1)
                var expr: Expression
                if let i = value(2) as? Int, i == 1 && op.op == .Add {
                    expr = PostfixExpression.new() <> loopVar <> "++"
                } else if let i = value(2) as? Int, i == 1 && op.op == .Sub {
                    expr = PostfixExpression.new() <> loopVar <> "--"
                } else {
                    let newValue = BinaryExpression.new() <> loopVar <> " " <> op.op.token <> " " <> input(2)
                    expr = AssignmentExpression.new() <> loopVar <> " = " <> newValue
                }
                w.emit("for (\(varDecl) \(loopVar) = \(input(0)); \(cond); \(expr)) {")
                w.increaseIndentionLevel()
                
            case is EndFor:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is BeginForIn:
                w.emit("for (\(constDecl) \(instr.innerOutput) in \(input(0))) {")
                w.increaseIndentionLevel()
                
            case is EndForIn:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is BeginForOf:
                w.emit("for (\(constDecl) \(instr.innerOutput) of \(input(0))) {")
                w.increaseIndentionLevel()
                
            case is EndForOf:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is Break:
                w.emit("break;")
                
            case is Continue:
                w.emit("continue;")
                
            case is BeginTry:
                w.emit("try {")
                w.increaseIndentionLevel()
                
            case is BeginCatch:
                w.decreaseIndentionLevel()
                w.emit("} catch(\(instr.innerOutput)) {")
                w.increaseIndentionLevel()
                
            case is EndTryCatch:
                w.decreaseIndentionLevel()
                w.emit("}")
                
            case is ThrowException:
                w.emit("throw \(input(0));")
                
            case is Print:
                w.emit("\(fuzzilOutputFuncName)(\(input(0)));")
                
            case is InspectType:
                w.emitBlock(
                    """
                    {
                        try {
                            var proto = (\(input(0))).__proto__;
                            var typename = proto == null ? "Object" : proto.constructor.name;
                            \(fuzzilOutputFuncName)(typename);
                        } catch (e) {
                            \(fuzzilOutputFuncName)("");
                        }
                    }
                    """)
                
            case is InspectValue:
                w.emitBlock(
                    """
                    {
                        var properties = [];
                        var methods = [];
                        var obj = \(input(0));
                        while (obj != null) {
                            for (p of Object.getOwnPropertyNames(obj)) {
                                var prop;
                                try { prop = obj[p]; } catch (e) { continue; }
                                if (typeof(prop) === 'function') {
                                    methods.push(p);
                                }
                                // Every method is also a property!
                                properties.push(p);
                            }
                            obj = obj.__proto__;
                        }
                        \(fuzzilOutputFuncName)(JSON.stringify({properties: properties, methods: methods}));
                    }
                    """)
                
            case is EnumerateBuiltins:
                w.emitBlock("""
                    {
                        var globals = Object.getOwnPropertyNames(\(globalObjectIdentifier));
                        \(fuzzilOutputFuncName)(JSON.stringify({globals: globals}));
                    }
                    """)
                
            default:
                logger.fatal("Unhandled Operation: \(type(of: instr.operation))")
            }
            
            if let expression = output {
                let v = instr.output
                if policy.shouldInline(expression) && expression.canInline(instr, analyzer.usesIndices(of: v)) {
                    expressions[v] = expression
                } else {
                    w.emit("\(constDecl) \(v) = \(expression);")
                }
            }
        }
        
        w.emitBlock(suffix)

        return w.code
    }
}
