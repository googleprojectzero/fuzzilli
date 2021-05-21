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

import Foundation
import JS

/// Supported versions of the ECMA standard.
public enum ECMAScriptVersion {
    case es5
    case es6
}


/// Lifts a FuzzIL program to JavaScript.
public class JavaScriptLifter: Lifter {
    /// Prefix and suffix to surround the emitted code in
    private let prefix: String
    private let suffix: String

    /// The inlining policy to follow. This influences the look of the emitted code.
    let policy: InliningPolicy

    /// The inlining policy used for code emmited for type collection.
    /// It should inline as little expressions as possible to capture as many variable types as possible.
    /// But simple literal types can infer AbstractInterpreter as well.
    let typeCollectionPolicy = InlineOnlyLiterals()

    /// The version of the ECMAScript standard that this lifter generates code for.
    let version: ECMAScriptVersion

    /// Counter to assist the lifter in detecting nested CodeStrings
    private var codeStringNestingLevel = 0

    public init(prefix: String = "",
                suffix: String = "",
                inliningPolicy: InliningPolicy,
                ecmaVersion: ECMAScriptVersion) {
        self.prefix = prefix
        self.suffix = suffix
        self.policy = inliningPolicy
        self.version = ecmaVersion
    }

    public func lift(_ program: Program, withOptions options: LiftingOptions) -> String {
        if options.contains(.collectTypes) {
            return lift(program, withOptions: options, withPolicy: self.typeCollectionPolicy)
        } else {
            return lift(program, withOptions: options, withPolicy: self.policy)
        }
    }

    private func lift(_ program: Program, withOptions options: LiftingOptions, withPolicy policy: InliningPolicy) -> String {
        var w = ScriptWriter(minifyOutput: options.contains(.minify))

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        var typeUpdates: [[(Variable, Type)]] = []
        if options.contains(.dumpTypes) {
            typeUpdates = program.types.indexedByInstruction(for: program)
        }

        // Keeps track of which variables have been inlined
        var inlinedVars = VariableSet()

        // Analyze the program to determine the uses of a variable
        let analyzer = VariableAnalyzer(for: program)

        let typeCollectionAnalyzer = TypeCollectionAnalyzer()

        // Associates variables with the expressions that produce them
        var expressions = VariableMap<Expression>()
        func expr(for v: Variable) -> Expression {
            return expressions[v] ?? Identifier.new(v.identifier)
        }

        if options.contains(.collectTypes) {
            // Wrap type collection to its own main function to avoid using global variables
            w.emit("function typeCollectionMain() {")
            w.increaseIndentionLevel()
            w.emitBlock(helpersScript)
            w.emitBlock(initTypeCollectionScript)
        }

        w.emitBlock(prefix)

        let varDecl = version == .es6 ? "let" : "var"
        let constDecl = version == .es6 ? "const" : "var"
        func decl(_ v: Variable) -> String {
            if analyzer.numAssignments(of: v) == 1 {
                return "\(constDecl) \(v)"
            } else {
                return "\(varDecl) \(v)"
            }
        }

        // Need to track class definitions to propertly lift class method definitions.
        var classDefinitions = ClassDefinitionStack()

        for instr in program.code {
            // Convenience access to inputs
            func input(_ idx: Int) -> Expression {
                return expr(for: instr.input(idx))
            }

            // Helper functions to lift a function definition
            func liftFunctionDefinitionParameters(_ op: BeginAnyFunctionDefinition) -> String {
                assert(instr.op === op)
                var identifiers = instr.innerOutputs.map({ $0.identifier })
                if op.hasRestParam, let last = instr.innerOutputs.last {
                    identifiers[identifiers.endIndex - 1] = "..." + last.identifier
                }
                return identifiers.joined(separator: ",")
            }
            // TODO remove copy+paste
            func liftMethodDefinitionParameters(_ signature: FunctionSignature) -> String {
                var identifiers = instr.innerOutputs(1...).map({ $0.identifier })
                if signature.hasVarargsParameter(), let last = instr.innerOutputs.last {
                    identifiers[identifiers.endIndex - 1] = "..." + last.identifier
                }
                return identifiers.joined(separator: ",")
            }
            func liftFunctionDefinitionBegin(_ op: BeginAnyFunctionDefinition, _ keyword: String) {
                assert(instr.op === op)
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(keyword) \(instr.output)(\(params)) {")
                w.increaseIndentionLevel()
            }

            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
            }

            var output: Expression? = nil

            switch instr.op {
            case let op as LoadInteger:
                output = NumberLiteral.new(String(op.value))

            case let op as LoadBigInt:
                output = NumberLiteral.new(String(op.value) + "n")

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

            case let op as LoadRegExp:
                let flags = op.flags.asString()
                output = Literal.new() <> "/" <> op.value <> "/" <> flags

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
                let elems = instr.inputs.map({ expr(for: $0).text == "undefined" ? "" : expr(for: $0).text }).joined(separator: ",")
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

            case let op as BeginPlainFunctionDefinition:
                liftFunctionDefinitionBegin(op, "function")

            case let op as BeginStrictFunctionDefinition:
                liftFunctionDefinitionBegin(op, "function")
                w.emit("'use strict';")

            case let op as BeginArrowFunctionDefinition:
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(decl(instr.output)) = (\(params)) => {")
                w.increaseIndentionLevel()

            case let op as BeginGeneratorFunctionDefinition:
                liftFunctionDefinitionBegin(op, "function*")

            case let op as BeginAsyncFunctionDefinition:
                liftFunctionDefinitionBegin(op, "async function")

            case let op as BeginAsyncArrowFunctionDefinition:
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(decl(instr.output)) = async (\(params)) => {")
                w.increaseIndentionLevel()

            case let op as BeginAsyncGeneratorFunctionDefinition:
                liftFunctionDefinitionBegin(op, "async function*")

            case is EndArrowFunctionDefinition, is EndAsyncArrowFunctionDefinition:
                w.decreaseIndentionLevel()
                w.emit("};")

            case is EndAnyFunctionDefinition:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is Return:
                w.emit("return \(input(0));")

            case is Yield:
                w.emit("yield \(input(0));")

            case is YieldEach:
                w.emit("yield* \(input(0));")

            case is Await:
                output = UnaryExpression.new() <> "await " <> input(0)

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
                if op.op.isPostfix {
                    output = UnaryExpression.new() <> input(0) <> op.op.token
                } else {
                    output = UnaryExpression.new() <> op.op.token <> input(0)
                }

            case let op as BinaryOperation:
                output = BinaryExpression.new() <> input(0) <> " " <> op.op.token <> " " <> input(1)

            case is Dup:
                w.emit("\(decl(instr.output)) = \(input(0));")

            case is Reassign:
                w.emit("\(instr.input(0)) = \(input(1));")

            case let op as Compare:
                output = BinaryExpression.new() <> input(0) <> " " <> op.op.token <> " " <> input(1)

            case let op as Eval:
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var string = op.code
                for v in instr.inputs {
                    let range = string.range(of: "%@")!
                    string.replaceSubrange(range, with: expr(for: v).text)
                }
                w.emit(string + ";")

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

            case is Nop:
                break

            case let op as BeginClassDefinition:
                var declaration = "\(decl(instr.output)) = class \(instr.output.identifier.uppercased())"
                if op.hasSuperclass {
                    declaration += " extends \(input(0))"
                }
                declaration += " {"
                w.emit(declaration)
                w.increaseIndentionLevel()

                classDefinitions.push(ClassDefinition(from: op))

                // The following code is the body of the constructor, so emit the declaration
                // First inner output is implicit |this| parameter
                expressions[instr.innerOutput(0)] = Identifier.new("this")
                let params = liftMethodDefinitionParameters(classDefinitions.current.constructorSignature)
                w.emit("constructor(\(params)) {")
                w.increaseIndentionLevel()

            case is BeginMethodDefinition:
                // End the previous body (constructor or method)
                w.decreaseIndentionLevel()
                w.emit("}")

                // First inner output is implicit |this| parameter
                expressions[instr.innerOutput(0)] = Identifier.new("this")
                let method = classDefinitions.current.nextMethod()
                let params = liftMethodDefinitionParameters(method.signature)
                w.emit("\(method.name)(\(params)) {")
                w.increaseIndentionLevel()

            case is EndClassDefinition:
                // End the previous body (constructor or method)
                w.decreaseIndentionLevel()
                w.emit("}")

                classDefinitions.pop()

                // End the class definition
                w.decreaseIndentionLevel()
                w.emit("};")

            case is CallSuperConstructor:
                let arguments = instr.inputs.map({ expr(for: $0).text })
                w.emit(CallExpression.new() <> "super(" <> arguments.joined(separator: ",") <> ")")

            case let op as CallSuperMethod:
                let arguments = instr.inputs.map({ expr(for: $0).text })
                output = CallExpression.new() <> "super.\(op.methodName)(" <> arguments.joined(separator: ",") <> ")"

            case let op as LoadSuperProperty:
                output = MemberExpression.new() <> "super.\(op.propertyName)"

            case let op as StoreSuperProperty:
                let expr = AssignmentExpression.new() <> "super.\(op.propertyName) = " <> input(0)
                w.emit(expr)

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

            case is EndDoWhile:
                w.decreaseIndentionLevel()
                let begin = Block(endedBy: instr, in: program.code).begin
                let comparator = (begin.op as! BeginDoWhile).comparator
                let cond = BinaryExpression.new() <> expr(for: begin.input(0)) <> " " <> comparator.token <> " " <> expr(for: begin.input(1))
                w.emit("} while (\(cond));")

            case let op as BeginFor:
                let loopVar = Identifier.new(instr.innerOutput.identifier)
                let cond = BinaryExpression.new() <> loopVar <> " " <> op.comparator.token <> " " <> input(1)
                var expr: Expression
                // This is a bit of a hack. Instead, maybe we should have a way of simplifying expressions through some pattern matching code?
                if input(2).text == "1" && op.op == .Add {
                    expr = PostfixExpression.new() <> loopVar <> "++"
                } else if input(2).text == "1" && op.op == .Sub {
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
                w.emit("for (\(decl(instr.innerOutput)) in \(input(0))) {")
                w.increaseIndentionLevel()

            case is EndForIn:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is BeginForOf:
                w.emit("for (\(decl(instr.innerOutput)) of \(input(0))) {")
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

            case is BeginCodeString:
                // This power series (2**n -1) is used to generate a valid escape sequence for nested template literals.
                // Here n represents the nesting level.
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let escapeSequence = String(repeating: "\\", count: count)
                w.emit("\(decl(instr.output)) = \(escapeSequence)`")
                w.increaseIndentionLevel()
                codeStringNestingLevel += 1

            case is EndCodeString:
                w.emit("\(input(0));")
                codeStringNestingLevel -= 1
                w.decreaseIndentionLevel()
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let escapeSequence = String(repeating: "\\", count: count)
                w.emit("\(escapeSequence)`;")

            case is BeginBlockStatement:
                w.emit("{")
                w.increaseIndentionLevel()

            case is EndBlockStatement:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is Print:
                w.emit("fuzzilli('FUZZILLI_PRINT', \(input(0)));")

            default:
                fatalError("Unhandled Operation: \(type(of: instr.op))")
            }

            if let expression = output {
                let v = instr.output

                if policy.shouldInline(expression) && analyzer.numAssignments(of: v) == 1 && expression.canInline(instr, analyzer.usesIndices(of: v)) {
                    expressions[v] = expression
                    inlinedVars.insert(v)
                } else {
                    w.emit("\(decl(v)) = \(expression);")
                }
            }

            if options.contains(.dumpTypes) {
                for (v, t) in typeUpdates[instr.index] where !inlinedVars.contains(v) {
                    w.emitComment("\(v) = \(t.abbreviated)")
                }
            }

            if options.contains(.collectTypes) {
                // Update type of every variable returned by analyzer
                for v in typeCollectionAnalyzer.analyze(instr) where !inlinedVars.contains(v) {
                    w.emit("updateType(\(v.number), \(instr.index), \(expr(for: v)));")
                }
            }
        }

        w.emitBlock(suffix)

        if options.contains(.collectTypes) {
            w.emitBlock(printTypesScript)
            w.decreaseIndentionLevel()
            w.emit("}")
            w.emit("typeCollectionMain()")
        }

        if options.contains(.includeComments), let footer = program.comments.at(.footer) {
            w.emitComment(footer)
        }

        return w.code
    }
}
