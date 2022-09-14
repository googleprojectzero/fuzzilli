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
        var w = ScriptWriter(stripComments: !options.contains(.includeComments), includeLineNumbers: options.contains(.includeLineNumbers))

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        var typeUpdates: [[(Variable, Type)]] = []
        if options.contains(.dumpTypes) {
            typeUpdates = program.types.indexedByInstruction(for: program)
        }

        // Keeps track of which variables have been inlined
        var inlinedVars = VariableSet()

        // Perform some analysis on the program, for example to determine variable uses
        var needToSupportExploration = false
        var analyzer = VariableAnalyzer(for: program)
        for instr in program.code {
            analyzer.analyze(instr)
            if instr.op is Explore { needToSupportExploration = true }
        }
        analyzer.finishAnalysis()

        let typeCollectionAnalyzer = TypeCollectionAnalyzer()

        // Associates variables with the expressions that produce them
        var expressions = VariableMap<Expression>()
        func expr(for v: Variable) -> Expression {
            return expressions[v] ?? Identifier.new(v.identifier)
        }

        if needToSupportExploration {
            w.emitBlock(JavaScriptExploreHelper.prefixCode)
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

            // Helper function to lift call arguments
            func liftCallArguments(_ args: ArraySlice<Variable>, spreading spreads: [Bool] = []) -> String {
                var arguments = [String]()
                for (i, v) in args.enumerated() {
                    if spreads.count > i && spreads[i] {
                        arguments.append("...\(expr(for: v).text)")
                    } else {
                        arguments.append(expr(for: v).text)
                    }
                }
                return arguments.joined(separator: ",")
            }

            // Helper function to lift destruct array operations
            func liftArrayPattern(indices: [Int], outputs: [String], hasRestElement: Bool) -> String {
                Assert(indices.count == outputs.count)

                var arrayPattern = ""
                var lastIndex = 0
                for (index, output) in zip(indices, outputs) {
                    let skipped = index - lastIndex
                    lastIndex = index
                    let dots = index == indices.last! && hasRestElement ? "..." : ""
                    arrayPattern += String(repeating: ",", count: skipped) + dots + output
                }

                return arrayPattern
            }

            func liftObjectDestructPattern(properties: [String], outputs: [String], hasRestElement: Bool) -> String {
                Assert(outputs.count == properties.count + (hasRestElement ? 1 : 0))

                var objectPattern = ""
                for (property, output) in zip(properties, outputs) {
                    objectPattern += "\"\(property)\":\(output),"
                }
                if hasRestElement {
                    objectPattern += "...\(outputs.last!)"
                }

                return objectPattern
            }

            // Helper functions to lift a function definition
            func liftFunctionDefinitionParameters(_ op: BeginAnyFunction) -> String {
                Assert(instr.op === op)
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
            func liftFunctionDefinitionBegin(_ op: BeginAnyFunction, _ keyword: String) {
                // Function are lifted as `function v3(v4, v5, v6) { ...`.
                // This will set the .name of the function to the name of the variable, which is a property that the JavaScriptExploreHelper code relies on (see shouldTreatAsConstructor).
                Assert(instr.op === op)
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(keyword) \(instr.output)(\(params)) {")
                w.increaseIndentionLevel()
                if op.isStrict {
                    w.emit("'use strict';")
                }
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
                output = RegExpLiteral.new() <> "/" <> op.value <> "/" <> flags

            case let op as LoadBoolean:
                output = Literal.new(op.value ? "true" : "false")

            case is LoadUndefined:
                output = Identifier.new("undefined")

            case is LoadNull:
                output = Literal.new("null")

            case is LoadThis:
                output = Literal.new("this")

            case is LoadArguments:
                output = Literal.new("arguments")

            case let op as CreateObject:
                var properties = [String]()
                for (index, propertyName) in op.propertyNames.enumerated() {
                    properties.append("\"" + propertyName + "\"" + ":" + input(index))
                }
                output = ObjectLiteral.new("{" + properties.joined(separator: ",") + "}")

            case is CreateArray:
                // When creating arrays, treat undefined elements as holes. This also relies on literals always being inlined.
                var elems = instr.inputs.map({ let text = expr(for: $0).text; return text == "undefined" ? "" : text }).joined(separator: ",")
                if elems.last == "," || (instr.inputs.count==1 && elems=="") {
                    // If the last element is supposed to be a hole, we need one additional comma
                    elems += ","
                }
                output = ArrayLiteral.new("[" + elems + "]")

            case let op as CreateObjectWithSpread:
                var properties = [String]()
                for (index, propertyName) in op.propertyNames.enumerated() {
                    properties.append("\"" + propertyName + "\"" + ":" + input(index))
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
                        let text = expr(for: v).text
                        elems.append(text == "undefined" ? "" : text)
                    }
                }
                var elemString = elems.joined(separator: ",");
                if elemString.last == "," || (instr.inputs.count==1 && elemString=="") {
                    // If the last element is supposed to be a hole, we need one additional commas
                    elemString += ","
                }
                output = ArrayLiteral.new("[" + elemString + "]")

            case let op as CreateTemplateString:
                Assert(!op.parts.isEmpty)
                Assert(op.parts.count == instr.numInputs + 1)
                var parts = [op.parts[0]]
                for i in 1..<op.parts.count {
                    parts.append("${\(input(i - 1))}\(op.parts[i])")
                }
                // See BeginCodeString case.
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let escapeSequence = String(repeating: "\\", count: count)
                output = Literal.new("\(escapeSequence)`" + parts.joined() + "\(escapeSequence)`")

            case let op as LoadBuiltin:
                output = Identifier.new(op.builtinName)

            case let op as LoadProperty:
                output = MemberExpression.new() <> input(0) <> "." <> op.propertyName

            case let op as StoreProperty:
                let dest = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(1)
                w.emit(expr)

            case let op as StorePropertyWithBinop:
                let dest = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                let expr = AssignmentExpression.new() <> dest <> " \(op.op.token)= " <> input(1)
                w.emit(expr)

            case let op as DeleteProperty:
                let target = MemberExpression.new() <> input(0) <> "." <> op.propertyName
                output = UnaryExpression.new() <> "delete " <> target

            case let op as LoadElement:
                output = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"

            case let op as StoreElement:
                let dest = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(1)
                w.emit(expr)

            case let op as StoreElementWithBinop:
                let dest = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                let expr = AssignmentExpression.new() <> dest <> " \(op.op.token)= " <> input(1)
                w.emit(expr)

            case let op as DeleteElement:
                let target = MemberExpression.new() <> input(0) <> "[" <> op.index <> "]"
                output = UnaryExpression.new() <> "delete " <> target

            case is LoadComputedProperty:
                output = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"

            case is StoreComputedProperty:
                let dest = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                let expr = AssignmentExpression.new() <> dest <> " = " <> input(2)
                w.emit(expr)

            case let op as StoreComputedPropertyWithBinop:
                let dest = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                let expr = AssignmentExpression.new() <> dest <> " \(op.op.token)= " <> input(2)
                w.emit(expr)

            case is DeleteComputedProperty:
                let target = MemberExpression.new() <> input(0) <> "[" <> input(1).text <> "]"
                output = UnaryExpression.new() <> "delete " <> target

            case is TypeOf:
                output = UnaryExpression.new() <> "typeof " <> input(0)

            case is TestInstanceOf:
                output = BinaryExpression.new() <> input(0) <> " instanceof " <> input(1)

            case is TestIn:
                output = BinaryExpression.new() <> input(0) <> " in " <> input(1)

            case let op as BeginPlainFunction:
                liftFunctionDefinitionBegin(op, "function")

            case let op as BeginArrowFunction:
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(decl(instr.output)) = (\(params)) => {")
                w.increaseIndentionLevel()
                if op.isStrict {
                    w.emit("'use strict';")
                }

            case let op as BeginGeneratorFunction:
                liftFunctionDefinitionBegin(op, "function*")

            case let op as BeginAsyncFunction:
                liftFunctionDefinitionBegin(op, "async function")

            case let op as BeginAsyncArrowFunction:
                let params = liftFunctionDefinitionParameters(op)
                w.emit("\(decl(instr.output)) = async (\(params)) => {")
                w.increaseIndentionLevel()
                if op.isStrict {
                    w.emit("'use strict';")
                }

            case let op as BeginAsyncGeneratorFunction:
                liftFunctionDefinitionBegin(op, "async function*")

            case is EndArrowFunction, is EndAsyncArrowFunction:
                w.decreaseIndentionLevel()
                w.emit("};")

            case is EndAnyFunction:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is Return:
                w.emit("return \(input(0));")

            case is Yield:
                output = YieldExpression.new() <> "yield " <> input(0)

            case is YieldEach:
                w.emit("yield* \(input(0));")

            case is Await:
                output = UnaryExpression.new() <> "await " <> input(0)

            case is CallFunction:
                output = CallExpression.new() <> input(0) <> "(" <> liftCallArguments(instr.variadicInputs) <> ")"

            case let op as CallFunctionWithSpread:
                output = CallExpression.new() <> input(0) <> "(" <> liftCallArguments(instr.variadicInputs, spreading: op.spreads) <> ")"

            case is Construct:
                output = NewExpression.new() <> "new " <> input(0) <> "(" <> liftCallArguments(instr.variadicInputs) <> ")"

            case let op as ConstructWithSpread:
                output = NewExpression.new() <> "new " <> input(0) <> "(" <> liftCallArguments(instr.variadicInputs, spreading: op.spreads) <> ")"

            case let op as CallMethod:
                let method = MemberExpression.new() <> input(0) <> "." <> op.methodName
                output = CallExpression.new() <> method <> "(" <> liftCallArguments(instr.variadicInputs) <> ")"

            case let op as CallMethodWithSpread:
                let method = MemberExpression.new() <> input(0) <> "." <> op.methodName
                output = CallExpression.new() <> method <> "(" <> liftCallArguments(instr.variadicInputs, spreading: op.spreads) <> ")"

            case is CallComputedMethod:
                let method = MemberExpression.new() <> input(0) <> "[" <> input(1) <> "]"
                output = CallExpression.new() <> method <> "(" <> liftCallArguments(instr.variadicInputs) <> ")"

            case let op as CallComputedMethodWithSpread:
                let method = MemberExpression.new() <> input(0) <> "[" <> input(1) <> "]"
                output = CallExpression.new() <> method <> "(" <> liftCallArguments(instr.variadicInputs, spreading: op.spreads) <> ")"

            case let op as UnaryOperation:
                if op.op.isPostfix {
                    output = UnaryExpression.new() <> input(0) <> op.op.token
                } else {
                    output = UnaryExpression.new() <> op.op.token <> input(0)
                }

            case let op as BinaryOperation:
                output = BinaryExpression.new() <> input(0) <> " " <> op.op.token <> " " <> input(1)

            case let op as ReassignWithBinop:
                let expr = AssignmentExpression.new() <> input(0) <> " \(op.op.token)= " <> input(1)
                w.emit(expr)

            case is Dup:
                w.emit("\(decl(instr.output)) = \(input(0));")

            case is Reassign:
                let expr = AssignmentExpression.new() <> input(0) <> " = " <> input(1)
                w.emit(expr)

            case let op as DestructArray:
                let outputs = instr.outputs.map({ $0.identifier })
                w.emit("\(varDecl) [\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] = \(input(0));")

            case let op as DestructArrayAndReassign:
                let outputs = instr.inputs.dropFirst().map({ $0.identifier })
                w.emit("[\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] = \(input(0));")

            case let op as DestructObject:
                let outputs = instr.outputs.map({ $0.identifier })
                w.emit("\(varDecl) {\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} = \(input(0));")

            case let op as DestructObjectAndReassign:
                let outputs = instr.inputs.dropFirst().map({ $0.identifier })
                w.emit("({\(liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement))} = \(input(0)));")

            case let op as Compare:
                output = BinaryExpression.new() <> input(0) <> " " <> op.op.token <> " " <> input(1)

            case is ConditionalOperation:
                output = TernaryExpression.new() <> input(0) <> " ? " <> input(1) <> " : " <> input(2)

            case let op as Eval:
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var string = op.code
                for v in instr.inputs {
                    let range = string.range(of: "%@")!
                    string.replaceSubrange(range, with: expr(for: v).text)
                }
                w.emit(string + ";")

            case let op as Explore:
                let arguments = instr.inputs.suffix(from: 1).map({ expr(for: $0).text }).joined(separator: ",")
                w.emit("\(JavaScriptExploreHelper.exploreFunc)(\"\(op.id)\", \(input(0)), this, [\(arguments)]);")

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

            case let op as BeginClass:
                // The name of the class is set to the uppercased variable name. This ensures that the heuristics used by the JavaScriptExploreHelper code to detect constructors works correctly (see shouldTreatAsConstructor).
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

            case is BeginMethod:
                // End the previous body (constructor or method)
                w.decreaseIndentionLevel()
                w.emit("}")

                // First inner output is implicit |this| parameter
                expressions[instr.innerOutput(0)] = Identifier.new("this")
                let method = classDefinitions.current.nextMethod()
                let params = liftMethodDefinitionParameters(method.signature)
                w.emit("\(method.name)(\(params)) {")
                w.increaseIndentionLevel()

            case is EndClass:
                // End the previous body (constructor or method)
                w.decreaseIndentionLevel()
                w.emit("}")

                classDefinitions.pop()

                // End the class definition
                w.decreaseIndentionLevel()
                w.emit("};")

            case is CallSuperConstructor:
                w.emit(CallExpression.new() <> "super(" <> liftCallArguments(instr.variadicInputs) <> ")")

            case let op as CallSuperMethod:
                output = CallExpression.new() <> "super.\(op.methodName)(" <> liftCallArguments(instr.variadicInputs)  <> ")"

            case let op as LoadSuperProperty:
                output = MemberExpression.new() <> "super.\(op.propertyName)"

            case let op as StoreSuperProperty:
                let expr = AssignmentExpression.new() <> "super.\(op.propertyName) = " <> input(0)
                w.emit(expr)

            case let op as StoreSuperPropertyWithBinop:
                let expr = AssignmentExpression.new() <> "super.\(op.propertyName) \(op.op.token)= " <> input(0)
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

            case let op as BeginSwitch:
                w.emit("switch (\(input(0))) {")
                if op.isDefaultCase {
                    w.emit("default:")
                } else {
                    w.emit("case \(input(1)):")
                }
                w.increaseIndentionLevel()

            case let op as BeginSwitchCase:
                if !op.previousCaseFallsThrough {
                    w.emit("break;")
                }
                w.decreaseIndentionLevel()
                if op.isDefaultCase {
                    w.emit("default:")
                } else {
                    w.emit("case \(input(0)):")
                }
                w.increaseIndentionLevel()

            case is EndSwitch:
                w.decreaseIndentionLevel()
                w.emit("}")

            case let op as BeginWhileLoop:
                let cond = BinaryExpression.new() <> input(0) <> " " <> op.comparator.token <> " " <> input(1)
                w.emit("while (\(cond)) {")
                w.increaseIndentionLevel()

            case is EndWhileLoop:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is BeginDoWhileLoop:
                w.emit("do {")
                w.increaseIndentionLevel()

            case is EndDoWhileLoop:
                w.decreaseIndentionLevel()
                let begin = Block(endedBy: instr, in: program.code).begin
                let comparator = (begin.op as! BeginDoWhileLoop).comparator
                let cond = BinaryExpression.new() <> expr(for: begin.input(0)) <> " " <> comparator.token <> " " <> expr(for: begin.input(1))
                w.emit("} while (\(cond));")

            case let op as BeginForLoop:
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

            case is EndForLoop:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is BeginForInLoop:
                w.emit("for (\(decl(instr.innerOutput)) in \(input(0))) {")
                w.increaseIndentionLevel()

            case is EndForInLoop:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is BeginForOfLoop:
                w.emit("for (\(decl(instr.innerOutput)) of \(input(0))) {")
                w.increaseIndentionLevel()

            case let op as BeginForOfWithDestructLoop:
                let outputs = instr.innerOutputs.map({ $0.identifier })
                w.emit("for (\(varDecl) [\(liftArrayPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement))] of \(input(0))) {")
                w.increaseIndentionLevel()

            case is EndForOfLoop:
                w.decreaseIndentionLevel()
                w.emit("}")

            case is LoopBreak,
                is SwitchBreak:
                w.emit("break;")

            case is LoopContinue:
                w.emit("continue;")

            case is BeginTry:
                w.emit("try {")
                w.increaseIndentionLevel()

            case is BeginCatch:
                w.decreaseIndentionLevel()
                w.emit("} catch(\(instr.innerOutput)) {")
                w.increaseIndentionLevel()

            case is BeginFinally:
                w.decreaseIndentionLevel()
                w.emit("} finally {")
                w.increaseIndentionLevel()

            case is EndTryCatchFinally:
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

        if needToSupportExploration {
            w.emitBlock(JavaScriptExploreHelper.suffixCode)
        }

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
