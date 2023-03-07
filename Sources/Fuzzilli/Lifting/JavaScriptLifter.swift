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

    /// The version of the ECMAScript standard that this lifter generates code for.
    let version: ECMAScriptVersion

    /// Counter to assist the lifter in detecting nested CodeStrings
    private var codeStringNestingLevel = 0

    // TODO remove once loops are refactored
    private var doWhileLoopStack = Stack<(Expression, Expression)>()

    public init(prefix: String = "",
                suffix: String = "",
                ecmaVersion: ECMAScriptVersion) {
        self.prefix = prefix
        self.suffix = suffix
        self.version = ecmaVersion
    }

    public func lift(_ program: Program, withOptions options: LiftingOptions) -> String {
        // Perform some analysis on the program, for example to determine variable uses
        var needToSupportExploration = false
        var needToSupportProbing = false
        var analyzer = VariableAnalyzer(for: program)
        for instr in program.code {
            analyzer.analyze(instr)
            if instr.op is Explore { needToSupportExploration = true }
            if instr.op is Probe { needToSupportProbing = true }
        }
        analyzer.finishAnalysis()

        var w = JavaScriptWriter(analyzer: analyzer, version: version, stripComments: !options.contains(.includeComments), includeLineNumbers: options.contains(.includeLineNumbers))

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        w.emitBlock(prefix)

        if needToSupportExploration {
            w.emitBlock(JavaScriptExploreHelper.prefixCode)
        }

        if needToSupportProbing {
            w.emitBlock(JavaScriptProbeHelper.prefixCode)
        }

        for instr in program.code {
            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
            }

            // Retrieve all input expressions.
            //
            // Here we assume that the input expressions are evaluated exactly in the order that they appear in the instructions inputs array.
            // If that is not the case, it may change the program's semantics as inlining could reorder operations, see JavaScriptWriter.retrieve
            // for more details.
            // We also have some lightweight checking logic to ensure that the input expressions are retrieved in the correct order.
            // This does not guarantee that they will also _evaluate_ in that order at runtime, but it's probably a decent approximation.
            let inputs = w.retrieve(expressionsFor: instr.inputs)
            var nextExpressionToFetch = 0
            func input(_ i: Int) -> Expression {
                assert(i == nextExpressionToFetch)
                nextExpressionToFetch += 1
                return inputs[i]
            }

            switch instr.op.opcode {
            case .loadInteger(let op):
                w.assign(NumberLiteral.new(String(op.value)), to: instr.output)

            case .loadBigInt(let op):
                w.assign(NumberLiteral.new(String(op.value) + "n"), to: instr.output)

            case .loadFloat(let op):
                let expr: Expression
                if op.value.isNaN {
                    expr = Identifier.new("NaN")
                } else if op.value.isEqual(to: -Double.infinity) {
                    expr = UnaryExpression.new("-Infinity")
                } else if op.value.isEqual(to: Double.infinity) {
                    expr = Identifier.new("Infinity")
                } else {
                    expr = NumberLiteral.new(String(op.value))
                }
                w.assign(expr, to: instr.output)

            case .loadString(let op):
                w.assign(StringLiteral.new("\"\(op.value)\""), to: instr.output)

            case .loadRegExp(let op):
                let flags = op.flags.asString()
                w.assign(RegExpLiteral.new() + "/" + op.pattern + "/" + flags, to: instr.output)

            case .loadBoolean(let op):
                w.assign(Literal.new(op.value ? "true" : "false"), to: instr.output)

            case .loadUndefined:
                w.assign(Identifier.new("undefined"), to: instr.output)

            case .loadNull:
                w.assign(Literal.new("null"), to: instr.output)

            case .loadThis:
                w.assign(Literal.new("this"), to: instr.output)

            case .loadArguments:
                w.assign(Literal.new("arguments"), to: instr.output)

            case .beginObjectLiteral:
                let output = Blocks.findBlockEnd(head: instr, in: program.code).output
                let LET = w.declarationKeyword(for: output)
                let V = w.declare(output, as: "o\(output.number)")
                w.emit("\(LET) \(V) = {")
                w.enterNewBlock()

            case .objectLiteralAddProperty(let op):
                let PROPERTY = op.propertyName
                let VALUE = input(0)
                w.emit("\"\(PROPERTY)\": \(VALUE),")

            case .objectLiteralAddElement(let op):
                let INDEX = op.index
                let VALUE = input(0)
                w.emit("\(INDEX): \(VALUE),")

            case .objectLiteralAddComputedProperty:
                let PROPERTY = input(0)
                let VALUE = input(1)
                w.emit("[\(PROPERTY)]: \(VALUE),")

            case .objectLiteralCopyProperties:
                let EXPR = SpreadExpression.new() + "..." + input(0)
                w.emit("\(EXPR),")

            case .objectLiteralSetPrototype:
                let PROTO = input(0)
                w.emit("__proto__: \(PROTO),")

            case .beginObjectLiteralMethod(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endObjectLiteralMethod:
                w.leaveCurrentBlock()
                w.emit("},")

            case .beginObjectLiteralGetter(let op):
                // inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 1)
                w.declare(instr.innerOutput, as: "this")
                let PROPERTY = op.propertyName
                w.emit("get \(PROPERTY)() {")
                w.enterNewBlock()

            case .beginObjectLiteralSetter(let op):
                // First inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 2)
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                w.emit("set \(PROPERTY)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endObjectLiteralGetter,
                 .endObjectLiteralSetter:
                w.leaveCurrentBlock()
                w.emit("},")

            case .endObjectLiteral:
                w.leaveCurrentBlock()
                w.emit("};")

            case .beginClassDefinition(let op):
                // The name of the class is set to the uppercased variable name. This ensures that the heuristics used by the JavaScriptExploreHelper code to detect constructors works correctly (see shouldTreatAsConstructor).
                let NAME = "C\(instr.output.number)"
                w.declare(instr.output, as: NAME)
                var declaration = "class \(NAME)"
                if op.hasSuperclass {
                    declaration += " extends \(input(0))"
                }
                declaration += " {"
                w.emit(declaration)
                w.enterNewBlock()

            case .beginClassConstructor(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("constructor(\(PARAMS)) {")
                w.enterNewBlock()

            case .endClassConstructor:
                w.leaveCurrentBlock()
                w.emit("}")

            case .classAddInstanceProperty(let op):
                let PROPERTY = op.propertyName
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("\(PROPERTY) = \(VALUE);")
                } else {
                    w.emit("\(PROPERTY);")
                }

            case .classAddInstanceElement(let op):
                let INDEX = op.index
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("\(INDEX) = \(VALUE);")
                } else {
                    w.emit("\(INDEX);")
                }

            case .classAddInstanceComputedProperty(let op):
                let PROPERTY = input(0)
                if op.hasValue {
                    let VALUE = input(1)
                    w.emit("[\(PROPERTY)] = \(VALUE);")
                } else {
                    w.emit("[\(PROPERTY)];")
                }

            case .beginClassInstanceMethod(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .beginClassInstanceGetter(let op):
                // inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 1)
                w.declare(instr.innerOutput, as: "this")
                let PROPERTY = op.propertyName
                w.emit("get \(PROPERTY)() {")
                w.enterNewBlock()

            case .beginClassInstanceSetter(let op):
                // First inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 2)
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                w.emit("set \(PROPERTY)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endClassInstanceMethod,
                 .endClassInstanceGetter,
                 .endClassInstanceSetter:
                w.leaveCurrentBlock()
                w.emit("}")

            case .classAddStaticProperty(let op):
                let PROPERTY = op.propertyName
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("static \(PROPERTY) = \(VALUE);")
                } else {
                    w.emit("static \(PROPERTY);")
                }

            case .classAddStaticElement(let op):
                let INDEX = op.index
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("static \(INDEX) = \(VALUE);")
                } else {
                    w.emit("static \(INDEX);")
                }

            case .classAddStaticComputedProperty(let op):
                let PROPERTY = input(0)
                if op.hasValue {
                    let VALUE = input(1)
                    w.emit("static [\(PROPERTY)] = \(VALUE);")
                } else {
                    w.emit("static [\(PROPERTY)];")
                }

            case .beginClassStaticInitializer:
                // Inner output is explicit |this| parameter
                w.declare(instr.innerOutput, as: "this")
                w.emit("static {")
                w.enterNewBlock()

            case .beginClassStaticMethod(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("static \(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .beginClassStaticGetter(let op):
                // inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 1)
                w.declare(instr.innerOutput, as: "this")
                let PROPERTY = op.propertyName
                w.emit("static get \(PROPERTY)() {")
                w.enterNewBlock()

            case .beginClassStaticSetter(let op):
                // First inner output is explicit |this| parameter
                assert(instr.numInnerOutputs == 2)
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                w.emit("static set \(PROPERTY)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endClassStaticInitializer,
                 .endClassStaticMethod,
                 .endClassStaticGetter,
                 .endClassStaticSetter:
                w.leaveCurrentBlock()
                w.emit("}")

            case .classAddPrivateInstanceProperty(let op):
                let PROPERTY = op.propertyName
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("#\(PROPERTY) = \(VALUE);")
                } else {
                    w.emit("#\(PROPERTY);")
                }

            case .beginClassPrivateInstanceMethod(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("#\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .classAddPrivateStaticProperty(let op):
                let PROPERTY = op.propertyName
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("static #\(PROPERTY) = \(VALUE);")
                } else {
                    w.emit("static #\(PROPERTY);")
                }

            case .beginClassPrivateStaticMethod(let op):
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("static #\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endClassPrivateInstanceMethod,
                 .endClassPrivateStaticMethod:
                w.leaveCurrentBlock()
                w.emit("}")

            case .endClassDefinition:
                w.leaveCurrentBlock()
                w.emit("}")

            case .createArray:
                // When creating arrays, treat undefined elements as holes. This also relies on literals always being inlined.
                var elems = inputs.map({ $0.text }).map({ $0 == "undefined" ? "" : $0 }).joined(separator: ",")
                if elems.last == "," || (instr.inputs.count == 1 && elems == "") {
                    // If the last element is supposed to be a hole, we need one additional comma
                    elems += ","
                }
                w.assign(ArrayLiteral.new("[\(elems)]"), to: instr.output)

            case .createIntArray(let op):
                let values = op.values.map({ String($0) }).joined(separator: ",")
                w.assign(ArrayLiteral.new("[\(values)]"), to: instr.output)

            case .createFloatArray(let op):
                let values = op.values.map({ String($0) }).joined(separator: ",")
                w.assign(ArrayLiteral.new("[\(values)]"), to: instr.output)

            case .createArrayWithSpread(let op):
                var elems = [String]()
                for (i, expr) in inputs.enumerated() {
                    if op.spreads[i] {
                        let expr = SpreadExpression.new() + "..." + expr
                        elems.append(expr.text)
                    } else {
                        let text = expr.text
                        elems.append(text == "undefined" ? "" : text)
                    }
                }
                var elemString = elems.joined(separator: ",");
                if elemString.last == "," || (instr.inputs.count==1 && elemString=="") {
                    // If the last element is supposed to be a hole, we need one additional commas
                    elemString += ","
                }
                w.assign(ArrayLiteral.new("[" + elemString + "]"), to: instr.output)

            case .createTemplateString(let op):
                assert(!op.parts.isEmpty)
                assert(op.parts.count == instr.numInputs + 1)
                var parts = [op.parts[0]]
                for i in 1..<op.parts.count {
                    let VALUE = input(i - 1)
                    parts.append("${\(VALUE)}\(op.parts[i])")
                }
                // See BeginCodeString case.
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let escapeSequence = String(repeating: "\\", count: count)
                let expr = TemplateLiteral.new("\(escapeSequence)`" + parts.joined() + "\(escapeSequence)`")
                w.assign(expr, to: instr.output)

            case .loadBuiltin(let op):
                w.assign(Identifier.new(op.builtinName), to: instr.output)

            case .getProperty(let op):
                let obj = input(0)
                let expr = MemberExpression.new() + obj + "." + op.propertyName
                w.assign(expr, to: instr.output)

            case .setProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updateProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of a property deletion, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let target = MemberExpression.new() + obj + "." + op.propertyName
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureProperty(let op):
                let OBJ = input(0)
                let PROPERTY = op.propertyName
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: inputs.dropFirst())
                w.emit("Object.defineProperty(\(OBJ), \"\(PROPERTY)\", \(DESCRIPTOR));")

            case .getElement(let op):
                let obj = input(0)
                let expr = MemberExpression.new() + obj + "[" + op.index + "]"
                w.assign(expr, to: instr.output)

            case .setElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = input(1)
                w.emit("\(ELEMENT) = \(VALUE);")

            case .updateElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = input(1)
                w.emit("\(ELEMENT) \(op.op.token)= \(VALUE);")

            case .deleteElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an element deletion, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let target = MemberExpression.new() + obj + "[" + op.index + "]"
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureElement(let op):
                let OBJ = input(0)
                let INDEX = op.index
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: inputs.dropFirst())
                w.emit("Object.defineProperty(\(OBJ), \(INDEX), \(DESCRIPTOR));")

            case .getComputedProperty:
                let obj = input(0)
                let expr = MemberExpression.new() + obj + "[" + input(1).text + "]"
                w.assign(expr, to: instr.output)

            case .setComputedProperty:
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let VALUE = input(2)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updateComputedProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let VALUE = input(2)
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteComputedProperty:
                // For aesthetic reasons, we don't want to inline the lhs of a property deletion, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let target = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureComputedProperty(let op):
                let OBJ = input(0)
                let PROPERTY = input(1)
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: inputs.dropFirst(2))
                w.emit("Object.defineProperty(\(OBJ), \(PROPERTY), \(DESCRIPTOR));")

            case .typeOf:
                let expr = UnaryExpression.new() + "typeof " + input(0)
                w.assign(expr, to: instr.output)

            case .testInstanceOf:
                let lhs = input(0)
                let rhs = input(1)
                let expr = BinaryExpression.new() + lhs + " instanceof " + rhs
                w.assign(expr, to: instr.output)

            case .testIn:
                let lhs = input(0)
                let rhs = input(1)
                let expr = BinaryExpression.new() + lhs + " in " + rhs
                w.assign(expr, to: instr.output)

            case .beginPlainFunction:
                liftFunctionDefinitionBegin(instr, keyword: "function", using: &w)

            case .beginArrowFunction(let op):
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                let vars = w.declareAll(instr.innerOutputs, usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("\(LET) \(V) = (\(PARAMS)) => {")
                w.enterNewBlock()
                if op.isStrict {
                    w.emit("'use strict';")
                }

            case .beginGeneratorFunction:
                liftFunctionDefinitionBegin(instr, keyword: "function*", using: &w)

            case .beginAsyncFunction:
                liftFunctionDefinitionBegin(instr, keyword: "async function", using: &w)

            case .beginAsyncArrowFunction(let op):
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                let vars = w.declareAll(instr.innerOutputs, usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("\(LET) \(V) = async (\(PARAMS)) => {")
                w.enterNewBlock()
                if op.isStrict {
                    w.emit("'use strict';")
                }

            case .beginAsyncGeneratorFunction:
                liftFunctionDefinitionBegin(instr, keyword: "async function*", using: &w)

            case .endArrowFunction(_),
                 .endAsyncArrowFunction:
                w.leaveCurrentBlock()
                w.emit("};")

            case .endPlainFunction(_),
                 .endGeneratorFunction(_),
                 .endAsyncFunction(_),
                 .endAsyncGeneratorFunction:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginConstructor(let op):
                // Make the constructor name uppercased so that the difference to a plain function is visible, but also so that the heuristics to determine which functions are constructors in the ExplorationMutator work correctly.
                let NAME = "F\(instr.output.number)"
                w.declare(instr.output, as: NAME)
                // First inner output is the explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("function \(NAME)(\(PARAMS)) {")
                w.enterNewBlock()
                // Disallow invoking constructors without `new` (i.e. Construct in FuzzIL).
                w.emit("if (!new.target) { throw 'must be called with new'; }")

            case .endConstructor:
                w.leaveCurrentBlock()
                w.emit("}")

            case .return(let op):
                if op.hasReturnValue {
                    let VALUE = input(0)
                    w.emit("return \(VALUE);")
                } else {
                    w.emit("return;")
                }

            case .yield(let op):
                let expr: Expression
                if op.hasArgument {
                    expr = YieldExpression.new() + "yield " + input(0)
                } else {
                    expr = YieldExpression.new() + "yield"
                }
                w.assign(expr, to: instr.output)

            case .yieldEach:
                let VALUES = input(0)
                w.emit("yield* \(VALUES);")

            case .await:
                let expr = UnaryExpression.new() + "await " + input(0)
                w.assign(expr, to: instr.output)

            case .callFunction:
                // Avoid inlining of the function expression. This is mostly for aesthetic reasons, but is also required if the expression for
                // the function is a MemberExpression since it would otherwise be interpreted as a method call, not a function call.
                let f = w.maybeStoreInTemporaryVariable(input(0))
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callFunctionWithSpread(let op):
                let f = input(0)
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .construct:
                let f = input(0)
                let args = inputs.dropFirst()
                let EXPR = NewExpression.new() + "new " + f + "(" + liftCallArguments(args) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions and always assign their result to a new variable.
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                w.emit("\(LET) \(V) = \(EXPR);")

            case .constructWithSpread(let op):
                let f = input(0)
                let args = inputs.dropFirst()
                let EXPR = NewExpression.new() + "new " + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions and always assign their result to a new variable.
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                w.emit("\(LET) \(V) = \(EXPR);")

            case .callMethod(let op):
                let obj = input(0)
                let method = MemberExpression.new() + obj + "." + op.methodName
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callMethodWithSpread(let op):
                let obj = input(0)
                let method = MemberExpression.new() + obj + "." + op.methodName
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .callComputedMethod:
                let obj = input(0)
                let method = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let args = inputs.dropFirst(2)
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callComputedMethodWithSpread(let op):
                let obj = input(0)
                let method = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let args = inputs.dropFirst(2)
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .unaryOperation(let op):
                let input = input(0)
                let expr: Expression
                if op.op.isPostfix {
                    expr = UnaryExpression.new() + input + op.op.token
                } else {
                    expr = UnaryExpression.new() + op.op.token + input
                }
                w.assign(expr, to: instr.output)

            case .binaryOperation(let op):
                let lhs = input(0)
                let rhs = input(1)
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .ternaryOperation:
                let cond = input(0)
                let value1 = input(1)
                let value2 = input(2)
                let expr = TernaryExpression.new() + cond + " ? " + value1 + " : " + value2
                w.assign(expr, to: instr.output)

            case .reassign:
                let DEST = input(0)
                let VALUE = input(1)
                assert(DEST.type === Identifier)
                w.emit("\(DEST) = \(VALUE);")

            case .update(let op):
                let DEST = input(0)
                let VALUE = input(1)
                assert(DEST.type === Identifier)
                w.emit("\(DEST) \(op.op.token)= \(VALUE);")

            case .dup:
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                let VALUE = input(0)
                w.emit("\(LET) \(V) = \(VALUE);")

            case .destructArray(let op):
                let outputs = w.declareAll(instr.outputs)
                let ARRAY = input(0)
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.lastIsRest)
                let LET = w.varKeyword
                w.emit("\(LET) [\(PATTERN)] = \(ARRAY);")

            case .destructArrayAndReassign(let op):
                assert(inputs.dropFirst().allSatisfy({ $0.type === Identifier }))
                let ARRAY = input(0)
                let outputs = inputs.dropFirst().map({ $0.text })
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.lastIsRest)
                w.emit("[\(PATTERN)] = \(ARRAY);")

            case .destructObject(let op):
                let outputs = w.declareAll(instr.outputs)
                let OBJ = input(0)
                let PATTERN = liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement)
                let LET = w.varKeyword
                w.emit("\(LET) {\(PATTERN)} = \(OBJ);")

            case .destructObjectAndReassign(let op):
                assert(inputs.dropFirst().allSatisfy({ $0.type === Identifier }))
                let OBJ = input(0)
                let outputs = inputs.dropFirst().map({ $0.text })
                let PATTERN = liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement)
                w.emit("({\(PATTERN)} = \(OBJ));")

            case .compare(let op):
                let lhs = input(0)
                let rhs = input(1)
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .loadNamedVariable(let op):
                w.assign(Identifier.new(op.variableName), to: instr.output)

            case .storeNamedVariable(let op):
                let NAME = op.variableName
                let VALUE = input(0)
                w.emit("\(NAME) = \(VALUE);")

            case .defineNamedVariable(let op):
                let NAME = op.variableName
                let VALUE = input(0)
                w.emit("var \(NAME) = \(VALUE);")

            case .eval(let op):
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var EXPR = op.code
                for expr in inputs {
                    let range = EXPR.range(of: "%@")!
                    EXPR.replaceSubrange(range, with: expr.text)
                }
                if op.hasOutput {
                    let LET = w.declarationKeyword(for: instr.output)
                    let V = w.declare(instr.output)
                    w.emit("\(LET) \(V) = \(EXPR);")
                } else {
                    w.emit("\(EXPR);")
                }

            case .explore(let op):
                let EXPLORE = JavaScriptExploreHelper.exploreFunc
                let ID = op.id
                let VALUE = input(0)
                let ARGS = inputs.dropFirst().map({ $0.text }).joined(separator: ", ")
                w.emit("\(EXPLORE)(\"\(ID)\", \(VALUE), this, [\(ARGS)]);")

            case .probe(let op):
                let PROBE = JavaScriptProbeHelper.probeFunc
                let ID = op.id
                let VALUE = input(0)
                w.emit("\(PROBE)(\"\(ID)\", \(VALUE));")

            case .beginWith:
                let OBJ = input(0)
                w.emit("with (\(OBJ)) {")
                w.enterNewBlock()

            case .endWith:
                w.leaveCurrentBlock()
                w.emit("}")

            case .nop:
                break

            case .callSuperConstructor:
                let EXPR = CallExpression.new() + "super(" + liftCallArguments(inputs) + ")"
                w.emit("\(EXPR);")

            case .callSuperMethod(let op):
                let expr = CallExpression.new() + "super.\(op.methodName)(" + liftCallArguments(inputs)  + ")"
                w.assign(expr, to: instr.output)

            case .getPrivateProperty(let op):
                let obj = input(0)
                let expr = MemberExpression.new() + obj + ".#" + op.propertyName
                w.assign(expr, to: instr.output)

            case .setPrivateProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + ".#" + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updatePrivateProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.maybeStoreInTemporaryVariable(input(0))
                let PROPERTY = MemberExpression.new() + obj + ".#" + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .callPrivateMethod(let op):
                let obj = input(0)
                let method = MemberExpression.new() + obj + ".#" + op.methodName
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .getSuperProperty(let op):
                let expr = MemberExpression.new() + "super.\(op.propertyName)"
                w.assign(expr, to: instr.output)

            case .setSuperProperty(let op):
                let PROPERTY = op.propertyName
                let VALUE = input(0)
                w.emit("super.\(PROPERTY) = \(VALUE);")

            case .updateSuperProperty(let op):
                let PROPERTY = op.propertyName
                let VALUE = input(0)
                w.emit("super.\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .beginIf(let op):
                var COND = input(0)
                if op.inverted {
                    COND = UnaryExpression.new() + "!" + COND
                }
                w.emit("if (\(COND)) {")
                w.enterNewBlock()

            case .beginElse:
                w.leaveCurrentBlock()
                w.emit("} else {")
                w.enterNewBlock()

            case .endIf:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginSwitch:
                let VALUE = input(0)
                w.emit("switch (\(VALUE)) {")
                w.enterNewBlock()

            case .beginSwitchCase:
                let VALUE = input(0)
                w.emit("case \(VALUE):")
                w.enterNewBlock()

            case .beginSwitchDefaultCase:
                w.emit("default:")
                w.enterNewBlock()

            case .endSwitchCase(let op):
                if !op.fallsThrough {
                    w.emit("break;")
                }
                w.leaveCurrentBlock()

            case .endSwitch:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginWhileLoop(let op):
                // We should not inline expressions into the loop header as that would change the behavior of the program.
                // To achieve that, we force all pending expressions to be emitted now.
                // TODO: Instead, we should create a LoopHeader block in which arbitrary expressions can be executed.
                w.emitPendingExpressions()
                var lhs = input(0)
                if lhs.isEffectful {
                    lhs = w.maybeStoreInTemporaryVariable(lhs)
                }
                var rhs = input(1)
                if rhs.isEffectful {
                    rhs = w.maybeStoreInTemporaryVariable(rhs)
                }
                let COND = BinaryExpression.new() + lhs + " " + op.comparator.token + " " + rhs
                w.emit("while (\(COND)) {")
                w.enterNewBlock()

            case .endWhileLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginDoWhileLoop:
                var lhs = input(0)
                if lhs.isEffectful {
                    lhs = w.maybeStoreInTemporaryVariable(lhs)
                }
                var rhs = input(1)
                if rhs.isEffectful {
                    rhs = w.maybeStoreInTemporaryVariable(rhs)
                }
                doWhileLoopStack.push((lhs, rhs))

                w.emit("do {")
                w.enterNewBlock()

            case .endDoWhileLoop:
                w.leaveCurrentBlock()
                let begin = Block(endedBy: instr, in: program.code).begin
                let comparator = (begin.op as! BeginDoWhileLoop).comparator
                let (lhs, rhs) = doWhileLoopStack.pop()
                let COND = BinaryExpression.new() + lhs + " " + comparator.token + " " + rhs
                w.emit("} while (\(COND))")

            case .beginForLoop(let op):
                let I = w.declare(instr.innerOutput)
                let INITIAL = input(0)
                let COND = BinaryExpression.new() + I + " " + op.comparator.token + " " + input(1)
                let EXPR: Expression
                // This is a bit of a hack. Instead, maybe we should have a way of simplifying expressions through some pattern matching code?
                let step = input(2)
                if step.text == "1" && op.op == .Add {
                    EXPR = PostfixExpression.new() + I + "++"
                } else if step.text == "1" && op.op == .Sub {
                    EXPR = PostfixExpression.new() + I + "--"
                } else {
                    let newValue = BinaryExpression.new() + I + " " + op.op.token + " " + step
                    EXPR = AssignmentExpression.new() + I + " = " + newValue
                }
                let LET = w.varKeyword
                w.emit("for (\(LET) \(I) = \(INITIAL); \(COND); \(EXPR)) {")
                w.enterNewBlock()

            case .endForLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginForInLoop:
                let LET = w.declarationKeyword(for: instr.innerOutput)
                let V = w.declare(instr.innerOutput)
                let OBJ = input(0)
                w.emit("for (\(LET) \(V) in \(OBJ)) {")
                w.enterNewBlock()

            case .endForInLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginForOfLoop:
                let V = w.declare(instr.innerOutput)
                let LET = w.declarationKeyword(for: instr.innerOutput)
                let OBJ = input(0)
                w.emit("for (\(LET) \(V) of \(OBJ)) {")
                w.enterNewBlock()

            case .beginForOfWithDestructLoop(let op):
                let outputs = w.declareAll(instr.innerOutputs)
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement)
                let LET = w.varKeyword
                let OBJ = input(0)
                w.emit("for (\(LET) [\(PATTERN)] of \(OBJ)) {")
                w.enterNewBlock()

            case .endForOfLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginRepeatLoop(let op):
                let LET = w.varKeyword
                let I = w.declare(instr.innerOutput)
                let ITERATIONS = op.iterations
                w.emit("for (\(LET) \(I) = 0; \(I) < \(ITERATIONS); \(I)++) {")
                w.enterNewBlock()

            case .endRepeatLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .loopBreak(_),
                 .switchBreak:
                w.emit("break;")

            case .loopContinue:
                w.emit("continue;")

            case .beginTry:
                w.emit("try {")
                w.enterNewBlock()

            case .beginCatch:
                w.leaveCurrentBlock()
                let E = w.declare(instr.innerOutput, as: "e\(instr.innerOutput.number)")
                w.emit("} catch(\(E)) {")
                w.enterNewBlock()

            case .beginFinally:
                w.leaveCurrentBlock()
                w.emit("} finally {")
                w.enterNewBlock()

            case .endTryCatchFinally:
                w.leaveCurrentBlock()
                w.emit("}")

            case .throwException:
                let VALUE = input(0)
                w.emit("throw \(VALUE);")

            case .beginCodeString:
                // This power series (2**n -1) is used to generate a valid escape sequence for nested template literals.
                // Here n represents the nesting level.
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let ESCAPE = String(repeating: "\\", count: count)
                let V = w.declare(instr.output)
                let LET = w.declarationKeyword(for: instr.output)
                w.emit("\(LET) \(V) = \(ESCAPE)`")
                w.enterNewBlock()
                codeStringNestingLevel += 1

            case .endCodeString:
                codeStringNestingLevel -= 1
                w.leaveCurrentBlock()
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let ESCAPE = String(repeating: "\\", count: count)
                w.emit("\(ESCAPE)`;")

            case .beginBlockStatement:
                w.emit("{")
                w.enterNewBlock()

            case .endBlockStatement:
                w.leaveCurrentBlock()
                w.emit("}")

            case .print:
                let VALUE = input(0)
                w.emit("fuzzilli('FUZZILLI_PRINT', \(VALUE));")
            }
        }

        w.emitPendingExpressions()

        if needToSupportProbing {
            w.emitBlock(JavaScriptProbeHelper.suffixCode)
        }

        if options.contains(.includeComments), let footer = program.comments.at(.footer) {
            w.emitComment(footer)
        }

        w.emitBlock(suffix)

        return w.code
    }

    private func liftParameters(_ parameters: Parameters, as variables: [String]) -> String {
        assert(parameters.count == variables.count)
        var paramList = [String]()
        for v in variables {
            if parameters.hasRestParameter && v == variables.last {
                paramList.append("..." + v)
            } else {
                paramList.append(v)
            }
        }
        return paramList.joined(separator: ", ")
    }

    private func liftFunctionDefinitionBegin(_ instr: Instruction, keyword FUNCTION: String, using w: inout JavaScriptWriter) {
        // Function are lifted as `function f3(a4, a5, a6) { ...`.
        // This will produce functions with a recognizable .name property, which the JavaScriptExploreHelper code makes use of (see shouldTreatAsConstructor).
        guard let op = instr.op as? BeginAnyFunction else {
            fatalError("Invalid operation passed to liftFunctionDefinitionBegin")
        }
        let NAME = w.declare(instr.output, as: "f\(instr.output.number)")
        let vars = w.declareAll(instr.innerOutputs, usePrefix: "a")
        let PARAMS = liftParameters(op.parameters, as: vars)
        w.emit("\(FUNCTION) \(NAME)(\(PARAMS)) {")
        w.enterNewBlock()
        if op.isStrict {
            w.emit("'use strict';")
        }
    }

    private func liftCallArguments<Arguments: Sequence>(_ args: Arguments, spreading spreads: [Bool] = []) -> String where Arguments.Element == Expression {
        var arguments = [String]()
        for (i, a) in args.enumerated() {
            if spreads.count > i && spreads[i] {
                let expr = SpreadExpression.new() + "..." + a
                arguments.append(expr.text)
            } else {
                arguments.append(a.text)
            }
        }
        return arguments.joined(separator: ", ")
    }

    private func liftPropertyDescriptor(flags: PropertyFlags, type: PropertyType, values: ArraySlice<Expression>) -> String {
        assert(values.count <= 2)
        var parts = [String]()
        if flags.contains(.writable) {
            parts.append("writable: true")
        }
        if flags.contains(.configurable) {
            parts.append("configurable: true")
        }
        if flags.contains(.enumerable) {
            parts.append("enumerable: true")
        }
        let first = values.startIndex
        let second = values.index(after: first)
        switch type {
        case .value:
            parts.append("value: \(values[first])")
        case .getter:
            parts.append("get: \(values[first])")
        case .setter:
            parts.append("set: \(values[first])")
        case .getterSetter:
            parts.append("get: \(values[first])")
            parts.append("set: \(values[second])")
        }
        return "{ \(parts.joined(separator: ", ")) }"
    }

    private func liftArrayDestructPattern(indices: [Int64], outputs: [String], hasRestElement: Bool) -> String {
        assert(indices.count == outputs.count)

        var arrayPattern = ""
        var lastIndex = 0
        for (index64, output) in zip(indices, outputs) {
            let index = Int(index64)
            let skipped = index - lastIndex
            lastIndex = index
            let dots = index == indices.last! && hasRestElement ? "..." : ""
            arrayPattern += String(repeating: ",", count: skipped) + dots + output
        }

        return arrayPattern
    }

    private func liftObjectDestructPattern(properties: [String], outputs: [String], hasRestElement: Bool) -> String {
        assert(outputs.count == properties.count + (hasRestElement ? 1 : 0))

        var objectPattern = ""
        for (property, output) in zip(properties, outputs) {
            objectPattern += "\"\(property)\":\(output),"
        }
        if hasRestElement {
            objectPattern += "...\(outputs.last!)"
        }

        return objectPattern
    }

    /// A wrapper around a ScriptWriter. It's main responsibility is expression inlining.
    ///
    /// Expression inlining roughly works as follows:
    /// - FuzzIL operations that map to a single JavaScript expressions are lifted to these expressions and associated with the output FuzzIL variable using assign()
    /// - If an expression is pure, e.g. a number literal, it will be inlined into all its uses
    /// - On the other hand, if an expression is effectful, it can only be inlined if there is a single use of the FuzzIL variable (otherwise, the expression would execute multiple times), _and_ if there is no other effectful expression before that use (otherwise, the execution order of instructions would change)
    /// - To achieve that, pending effectful expressions are kept in a list of expressions which must execute in FIFO order at runtime
    /// - To retrieve the expression for an input FuzzIL variable, the retrieve() function is used. If an inlined expression is returned, this function takes care of first emitting pending expressions if necessary (to ensure correct execution order)
    private struct JavaScriptWriter {
        private var writer: ScriptWriter
        private var analyzer: VariableAnalyzer

        /// Variable declaration keywords to use.
        let varKeyword: String
        let constKeyword: String

        var code: String {
            assert(pendingExpressions.isEmpty)
            return writer.code
        }

        // Maps each FuzzIL variable to its JavaScript expression.
        // The expression for a FuzzIL variable can generally either be
        //  * an identifier like "v42" if the FuzzIL variable is mapped to a JavaScript variable OR
        //  * an arbitrary expression if the expression producing the FuzzIL variable is a candidate for inlining
        private var expressions = VariableMap<Expression>()

        // List of effectful expressions that are still waiting to be inlined. In the order that they need to be executed at runtime.
        // The expressions are identified by the FuzzIL output variable that they generate. The actual expression is stored in the expressions dictionary.
        private var pendingExpressions = [Variable]()

        init(analyzer: VariableAnalyzer, version: ECMAScriptVersion, stripComments: Bool = false, includeLineNumbers: Bool = false, indent: Int = 4) {
            self.writer = ScriptWriter(stripComments: stripComments, includeLineNumbers: includeLineNumbers, indent: indent)
            self.analyzer = analyzer
            self.varKeyword = version == .es6 ? "let" : "var"
            self.constKeyword = version == .es6 ? "const" : "var"
        }

        /// Assign a JavaScript expression to a FuzzIL variable.
        ///
        /// If the expression can be inlined, it will be associated with the variable and returned at its use. If the expression cannot be inlined,
        /// the expression will be emitted either as part of a variable definition or as an expression statement (if the value isn't subsequently used).
        mutating func assign(_ expr: Expression, to v: Variable) {
            if shouldTryInlining(expr, producing: v) {
                expressions[v] = expr
                // If this is an effectful expression, it must be the next expression to be evaluated. To ensure that, we
                // keep a list of all "pending" effectful expressions, which must be executed in FIFO order.
                if expr.isEffectful {
                    pendingExpressions.append(v)
                }
            } else {
                // The expression cannot be inlined. Now decide whether to define the output variable or not. The output variable can be omitted if:
                //  * It is not used by any following instructions, and
                //  * It is not an Object literal, as that would not be valid syntax (it would mistakenly be interpreted as a block statement)
                if analyzer.numUses(of: v) == 0 && expr.type !== ObjectLiteral {
                    emit("\(expr);")
                } else {
                    let LET = declarationKeyword(for: v)
                    let V = declare(v)
                    emit("\(LET) \(V) = \(expr);")
                }
            }
        }

        /// Retrieve the JavaScript expressions assigned to the given FuzzIL variables.
        ///
        /// The returned expressions _must_ subsequently execute exactly in the order that they are returned (i.e. in the order of the input variables).
        /// Otherwise, expression inlining will change the semantics of the program.
        ///
        /// This is a mutating operation as it can modify the list of pending expressions or emit pending expression to retain the correct ordering.
        mutating func retrieve(expressionsFor vars: ArraySlice<Variable>) -> [Expression] {
            // If any of the expression for the variables is pending, then one of two things will happen:
            //
            // 1. Iff the pending expressions that are being retrieved are an exact suffix match of the pending expressions list, then these pending expressions
            //    are removed but no code is emitted here.
            //    For example, if pendingExpressions = [v1, v2, v3, v4], and retrievedExpressions = [v3, v0, v4], then v3 and v4 are removed from the pending
            //    expressions list and returned, but no expressions are emitted, and so now pendingExpressions = [v1, v2] (v0 was not a pending expression
            //    and so is ignored). This works because no matter what the lifter now does with the expressions for v3 and v4, they will still executed
            //    _after_ v1 and v2, and so the correct order is maintainted (see also the explanation below).
            //
            // 2. In all other cases, some pending expressions must now be emitted. If there is a suffix match, then only the pending expressions
            //    before the matching suffix are emitted, otherwise, all of them are.
            //    For example, if pendingExpressions = [v1, v2, v3, v4, v5], and retrievedExpressions = [v0, v2, v5], then we would emit the expressions for
            //    v1, v2, v3, and v4 now. Otherwise, something like the following can happen: v0, v2, and v5 are inlined into a new expression, which is
            //    emitted as part of a variable declaraion (or appended to the pending expressions list, the outcome is the same). During the emit() call, all
            //    remaining pending expressions are now emitted, and so v1, v3, and v4 are emitted. However, this has now changed the execution order: v3 and
            //    v4 execute prior to v2. As such, v3 and v4 (in general, all instructions before a matching suffix) must be emitted during the retrieval,
            //    which then requires that all preceeding pending expressions (i.e. v1 in the above example) are emitted as well.
            //
            // This logic works because one of the following two cases must happen with the returned expressions:
            // 1. The handler for the instruction being lifted will emit a single expression for it. In that case, either that expression will be added to the
            //    end of the pending expression list and thereby effectively replace the suffix that is being removed, or it will cause a variable declaration
            //    to be emitted, in which case earlier pending expressions will also be emitted.
            // 2. The handler for the instruction being lifted will emit a statement. In that case, it will call emit() which will take care of emitting all
            //    pending expressions in the correct order.
            //
            // As such, in every possible case the correct ordering of the pending expressions is maintained.
            var results = [Expression]()

            var matchingSuffixLength = 0
            let queriedPendingExpressions = vars.filter(pendingExpressions.contains)
            for v in queriedPendingExpressions.reversed() {
                assert(matchingSuffixLength < pendingExpressions.count)
                let currentSuffixPosition = pendingExpressions.count - 1 - matchingSuffixLength
                if v == pendingExpressions[currentSuffixPosition] {
                    matchingSuffixLength += 1
                }
            }

            if matchingSuffixLength == queriedPendingExpressions.count {
                // This is case 1. from above, so we don't need to emit any pending expressions here \o/
            } else {
                // Case 2, so we need to emit (some) pending expressions.
                let numExpressionsToEmit = pendingExpressions.count - matchingSuffixLength
                for v in pendingExpressions.prefix(upTo: numExpressionsToEmit) {
                    emitPendingExpression(forVariable: v)
                }
                pendingExpressions.removeFirst(numExpressionsToEmit)
            }
            pendingExpressions.removeLast(matchingSuffixLength)

            for v in vars {
                guard let expression = expressions[v] else {
                    fatalError("Don't have an expression for variable \(v)")
                }
                if expression.isEffectful {
                    // Inlined, effectful expressions must only be used once. To guarantee that, remove the expression from the dictionary.
                    expressions.removeValue(forKey: v)
                }
                results.append(expression)
            }

            return results
        }

        /// If the given expression is not an identifier, create a temporary variable and assign the expression to it.
        ///
        /// Mostly used for aesthetical reasons, if an expression is more readable if some subexpression is always
        /// an identifier.
        mutating func maybeStoreInTemporaryVariable(_ expr: Expression) -> Expression {
            if expr.type === Identifier {
                return expr
            } else {
                let LET = constKeyword
                // We use a different naming scheme for these temporary variables since we may end up defining
                // them multiple times (if the same expression is "un-inlined" multiple times).
                // We could instead remember the existing local variable for as long as it is visible, but it's
                // probably not worth the effort.
                let V = "t" + String(writer.currentLineNumber)
                emit("\(LET) \(V) = \(expr);")
                return Identifier.new(V)
            }
        }

        /// Declare the given FuzzIL variable as a JavaScript variable with the given name.
        /// Whenever the variable is used in a FuzzIL instruction, the given identifier will be used in the lifted JavaScript code.
        ///
        /// Note that there is a difference between declaring a FuzzIL variable as a JavaScript identifier and assigning it to the current value of that identifier.
        /// Consider the following FuzzIL code:
        ///
        ///     v0 <- LoadUndefined
        ///     v1 <- LoadInt 42
        ///     Reassign v0 v1
        ///
        /// This code should be lifted to:
        ///
        ///     let v0 = undefined;
        ///     v0 = 42;
        ///
        /// And not:
        ///
        ///     undefined = 42;
        ///
        /// The first (correct) example corresponds to assign()ing v0 the expression 'undefined', while the second (incorrect) example corresponds to declare()ing v0 as 'undefined'.
        @discardableResult
        mutating func declare(_ v: Variable, as maybeName: String? = nil) -> String {
            assert(!expressions.contains(v))
            let name = maybeName ?? "v" + String(v.number)
            expressions[v] = Identifier.new(name)
            return name
        }

        /// Declare all of the given variables. Equivalent to calling declare() for each of them.
        /// The variable names will be constructed as prefix + v.number. By default, the prefix "v" is used.
        @discardableResult
        mutating func declareAll(_ vars: ArraySlice<Variable>, usePrefix prefix: String = "v") -> [String] {
            return vars.map({ declare($0, as: prefix + String($0.number)) })
        }

        /// Determine the correct variable declaration keyword (e.g. 'let' or 'const') for the given variable.
        mutating func declarationKeyword(for v: Variable) -> String {
            if analyzer.numAssignments(of: v) == 1 {
                return constKeyword
            } else {
                assert(analyzer.numAssignments(of: v) > 1)
                return varKeyword
            }
        }

        mutating func enterNewBlock() {
            emitPendingExpressions()
            writer.increaseIndentionLevel()
        }

        mutating func leaveCurrentBlock() {
            emitPendingExpressions()
            writer.decreaseIndentionLevel()
        }

        mutating func emit(_ line: String) {
            emitPendingExpressions()
            writer.emit(line)
        }

        /// Emit a (potentially multi-line) comment.
        mutating func emitComment(_ comment: String) {
            writer.emitComment(comment)
        }

        /// Emit one or more lines of code.
        mutating func emitBlock(_ block: String) {
            emitPendingExpressions()
            writer.emitBlock(block)
        }

        /// Emit all expressions that are still waiting to be inlined.
        /// This is usually used because some other effectful piece of code is about to be emitted, so the pending expression must execute first.
        mutating func emitPendingExpressions() {
            for v in pendingExpressions {
                emitPendingExpression(forVariable: v)
            }
            pendingExpressions.removeAll(keepingCapacity: true)
        }

        /// Emit the pending expression for the given variable.
        /// Note: this does _not_ remove the variable from the pendingExpressions list. It is the caller's responsibility to do so.
        private mutating func emitPendingExpression(forVariable v: Variable) {
            guard let EXPR = expressions[v] else {
                fatalError("Missing expression for variable \(v)")
            }
            expressions.removeValue(forKey: v)
            assert(analyzer.numUses(of: v) > 0)
            let LET = declarationKeyword(for: v)
            let V = declare(v)
            // Need to use writer.emit instead of emit here as the latter will emit all pending expressions.
            writer.emit("\(LET) \(V) = \(EXPR);")
        }

        /// Decide if we should attempt to inline the given expression. We do that if:
        ///  * The output variable is not reassigned later on (otherwise, that reassignment would fail as the variable was never defined)
        ///  * The output variable is pure and has at least one use OR
        ///  * The output variable is effectful and has exactly one use. However, in this case, the expression will only be inlined if it is still the next expression to be evaluated at runtime.
        private func shouldTryInlining(_ expression: Expression, producing v: Variable) -> Bool {
            if analyzer.numAssignments(of: v) > 1 {
                // Can never inline an expression when the output variable is reassigned again later.
                return false
            }

            switch expression.characteristic {
            case .pure:
                // We always inline these, which also means that we may not emit them at all if there is no use of them.
                return true
            case .effectful:
                return analyzer.numUses(of: v) == 1
            }
        }
    }
}
