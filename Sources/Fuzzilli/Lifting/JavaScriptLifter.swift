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

        // Need to track class definitions to propertly lift class method definitions.
        var classDefinitions = ClassDefinitionStack()

        for instr in program.code {
            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
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
                w.assign(RegExpLiteral.new() + "/" + op.value + "/" + flags, to: instr.output)

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

            case .createObject(let op):
                var properties = [String]()
                for (i, property) in op.propertyNames.enumerated() {
                    let value = w.retrieve(expressionFor: instr.input(i))
                    properties.append("\"\(property)\":\(value)")
                }
                w.assign(ObjectLiteral.new("{\(properties.joined(separator: ","))}"), to: instr.output)

            case .createArray:
                // When creating arrays, treat undefined elements as holes. This also relies on literals always being inlined.
                var elems = instr.inputs.map({ w.retrieve(expressionFor: $0).text }).map({ $0 == "undefined" ? "" : $0 }).joined(separator: ",")
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

            case .createObjectWithSpread(let op):
                var properties = [String]()
                for (i, property) in op.propertyNames.enumerated() {
                    let value = w.retrieve(expressionFor: instr.input(i))
                    properties.append("\"\(property)\":\(value)")
                }
                // Remaining ones are spread.
                for v in instr.inputs.dropFirst(properties.count) {
                    let expr = SpreadExpression.new() + "..." + w.retrieve(expressionFor: v)
                    properties.append(expr.text)
                }
                w.assign(ObjectLiteral.new("{\(properties.joined(separator: ","))}"), to: instr.output)

            case .createArrayWithSpread(let op):
                var elems = [String]()
                for (i, v) in instr.inputs.enumerated() {
                    if op.spreads[i] {
                        let expr = SpreadExpression.new() + "..." + w.retrieve(expressionFor: v)
                        elems.append(expr.text)
                    } else {
                        let text = w.retrieve(expressionFor: v).text
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
                    let VALUE = w.retrieve(expressionFor: instr.input(i - 1))
                    parts.append("${\(VALUE)}\(op.parts[i])")
                }
                // See BeginCodeString case.
                let count = Int(pow(2, Double(codeStringNestingLevel)))-1
                let escapeSequence = String(repeating: "\\", count: count)
                let expr = Literal.new("\(escapeSequence)`" + parts.joined() + "\(escapeSequence)`")
                w.assign(expr, to: instr.output)

            case .loadBuiltin(let op):
                w.assign(Identifier.new(op.builtinName), to: instr.output)

            case .loadProperty(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let expr = MemberExpression.new() + obj + "." + op.propertyName
                w.assign(expr, to: instr.output)

            case .storeProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(PROPERTY) = \(VALUE);")

            case .storePropertyWithBinop(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an property deletion, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let target = MemberExpression.new() + obj + "." + op.propertyName
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureProperty(let op):
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                let PROPERTY = op.propertyName
                let values = instr.inputs.dropFirst().map({ w.retrieve(expressionFor: $0) })
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: values)
                w.emit("Object.defineProperty(\(OBJ), \"\(PROPERTY)\", \(DESCRIPTOR));")

            case .loadElement(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let expr = MemberExpression.new() + obj + "[" + op.index + "]"
                w.assign(expr, to: instr.output)

            case .storeElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(ELEMENT) = \(VALUE);")

            case .storeElementWithBinop(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                w.emit("\(ELEMENT) \(op.op.token)= \(VALUE);")

            case .deleteElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an element deletion, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let target = MemberExpression.new() + obj + "[" + op.index + "]"
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureElement(let op):
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                let INDEX = op.index
                let values = instr.inputs.dropFirst().map({ w.retrieve(expressionFor: $0) })
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: values)
                w.emit("Object.defineProperty(\(OBJ), \(INDEX), \(DESCRIPTOR));")

            case .loadComputedProperty:
                let obj = w.retrieve(expressionFor: instr.input(0))
                let expr = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                w.assign(expr, to: instr.output)

            case .storeComputedProperty:
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let PROPERTY = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                let VALUE = w.retrieve(expressionFor: instr.input(2))
                w.emit("\(PROPERTY) = \(VALUE);")

            case .storeComputedPropertyWithBinop(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let PROPERTY = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                let VALUE = w.retrieve(expressionFor: instr.input(2))
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteComputedProperty:
                // For aesthetic reasons, we don't want to inline the lhs of an property deletion, so force it to be stored in a variable.
                let obj = w.retrieve(identifierFor: instr.input(0))
                let target = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureComputedProperty(let op):
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                let PROPERTY = w.retrieve(expressionFor: instr.input(1))
                let values = instr.inputs.dropFirst(2).map({ w.retrieve(expressionFor: $0) })
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: values)
                w.emit("Object.defineProperty(\(OBJ), \(PROPERTY), \(DESCRIPTOR));")

            case .typeOf:
                let expr = UnaryExpression.new() + "typeof " + w.retrieve(expressionFor: instr.input(0))
                w.assign(expr, to: instr.output)

            case .testInstanceOf:
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
                let expr = BinaryExpression.new() + lhs + " instanceof " + rhs
                w.assign(expr, to: instr.output)

            case .testIn:
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
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

            case .return:
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("return \(VALUE);")

            case .yield:
                let expr = YieldExpression.new() + "yield " + w.retrieve(expressionFor: instr.input(0))
                w.assign(expr, to: instr.output)

            case .yieldEach:
                let VALUES = w.retrieve(expressionFor: instr.input(0))
                w.emit("yield* \(VALUES);")

            case .await:
                let expr = UnaryExpression.new() + "await " + w.retrieve(expressionFor: instr.input(0))
                w.assign(expr, to: instr.output)

            case .callFunction:
                // Avoid inlining of the function expression. This is mostly for aesthetic reasons, but is also required if the expression for
                // the function is a MemberExpression since it would otherwise be interpreted as a method call, not a function call.
                let f = w.retrieve(identifierFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callFunctionWithSpread(let op):
                let f = w.retrieve(expressionFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .construct:
                let f = w.retrieve(expressionFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let EXPR = NewExpression.new() + "new " + f + "(" + liftCallArguments(args) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions and always assign their result to a new variable.
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                w.emit("\(LET) \(V) = \(EXPR);")

            case .constructWithSpread(let op):
                let f = w.retrieve(expressionFor: instr.input(0))
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let EXPR = NewExpression.new() + "new " + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions and always assign their result to a new variable.
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                w.emit("\(LET) \(V) = \(EXPR);")

            case .callMethod(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let method = MemberExpression.new() + obj + "." + op.methodName
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callMethodWithSpread(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let method = MemberExpression.new() + obj + "." + op.methodName
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .callComputedMethod:
                let obj = w.retrieve(expressionFor: instr.input(0))
                let method = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callComputedMethodWithSpread(let op):
                let obj = w.retrieve(expressionFor: instr.input(0))
                let method = MemberExpression.new() + obj + "[" + w.retrieve(expressionFor: instr.input(1)).text + "]"
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + method + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .unaryOperation(let op):
                let input = w.retrieve(expressionFor: instr.input(0))
                let expr: Expression
                if op.op.isPostfix {
                    expr = UnaryExpression.new() + input + op.op.token
                } else {
                    expr = UnaryExpression.new() + op.op.token + input
                }
                w.assign(expr, to: instr.output)

            case .binaryOperation(let op):
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .ternaryOperation:
                let cond = w.retrieve(expressionFor: instr.input(0))
                let value1 = w.retrieve(expressionFor: instr.input(1))
                let value2 = w.retrieve(expressionFor: instr.input(2))
                let expr = TernaryExpression.new() + cond + " ? " + value1 + " : " + value2
                w.assign(expr, to: instr.output)

            case .reassign:
                let DEST = w.retrieve(expressionFor: instr.input(0))
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                assert(DEST.type === Identifier)
                w.emit("\(DEST) = \(VALUE);")

            case .reassignWithBinop(let op):
                let DEST = w.retrieve(expressionFor: instr.input(0))
                let VALUE = w.retrieve(expressionFor: instr.input(1))
                assert(DEST.type === Identifier)
                w.emit("\(DEST) \(op.op.token)= \(VALUE);")

            case .dup:
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output)
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("\(LET) \(V) = \(VALUE);")

            case .destructArray(let op):
                let outputs = w.declareAll(instr.outputs)
                let ARRAY = w.retrieve(expressionFor: instr.input(0))
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement)
                let LET = w.varKeyword
                w.emit("\(LET) [\(PATTERN)] = \(ARRAY);")

            case .destructArrayAndReassign(let op):
                assert(instr.inputs.dropFirst().allSatisfy({ w.retrieve(expressionFor: $0).type === Identifier }))
                let outputs = instr.inputs.dropFirst().map({ w.retrieve(expressionFor: $0).text })
                let ARRAY = w.retrieve(expressionFor: instr.input(0))
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement)
                w.emit("[\(PATTERN)] = \(ARRAY);")

            case .destructObject(let op):
                let outputs = w.declareAll(instr.outputs)
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                let PATTERN = liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement)
                let LET = w.varKeyword
                w.emit("\(LET) {\(PATTERN)} = \(OBJ);")

            case .destructObjectAndReassign(let op):
                assert(instr.inputs.dropFirst().allSatisfy({ w.retrieve(expressionFor: $0).type === Identifier }))
                let outputs = instr.inputs.dropFirst().map({ w.retrieve(expressionFor: $0).text })
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                let PATTERN = liftObjectDestructPattern(properties: op.properties, outputs: outputs, hasRestElement: op.hasRestElement)
                w.emit("({\(PATTERN)} = \(OBJ));")

            case .compare(let op):
                let lhs = w.retrieve(expressionFor: instr.input(0))
                let rhs = w.retrieve(expressionFor: instr.input(1))
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .eval(let op):
                // Woraround until Strings implement the CVarArg protocol in the linux Foundation library...
                // TODO can make this permanent, but then use different placeholder pattern
                var EXPR = op.code
                for v in instr.inputs {
                    let range = EXPR.range(of: "%@")!
                    EXPR.replaceSubrange(range, with: w.retrieve(expressionFor: v).text)
                }
                w.emit("\(EXPR);")

            case .explore(let op):
                let EXPLORE = JavaScriptExploreHelper.exploreFunc
                let ID = op.id
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                let ARGS = instr.inputs.dropFirst().map({ w.retrieve(expressionFor: $0).text }).joined(separator: ",")
                w.emit("\(EXPLORE)(\"\(ID)\", \(VALUE), this, [\(ARGS)]);")

            case .probe(let op):
                let PROBE = JavaScriptProbeHelper.probeFunc
                let ID = op.id
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("\(PROBE)(\"\(ID)\", \(VALUE));")

            case .beginWith:
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                w.emit("with (\(OBJ)) {")
                w.enterNewBlock()

            case .endWith:
                w.leaveCurrentBlock()
                w.emit("}")

            case .loadFromScope(let op):
                w.assign(Identifier.new(op.id), to: instr.output)

            case .storeToScope(let op):
                let NAME = op.id
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("\(NAME) = \(VALUE);")

            case .nop:
                break

            case .beginClass(let op):
                // The name of the class is set to the uppercased variable name. This ensures that the heuristics used by the JavaScriptExploreHelper code to detect constructors works correctly (see shouldTreatAsConstructor).
                let NAME = "C\(instr.output.number)"
                w.declare(instr.output, as: NAME)
                var declaration = "class \(NAME)"
                if op.hasSuperclass {
                    declaration += " extends \(w.retrieve(expressionFor: instr.input(0)))"
                }
                declaration += " {"
                w.emit(declaration)
                w.enterNewBlock()

                classDefinitions.push(ClassDefinition(from: op))

                // The following code is the body of the constructor, so emit the declaration
                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.constructorParameters, as: vars)
                w.emit("constructor(\(PARAMS)) {")
                w.enterNewBlock()

            case .beginMethod:
                // End the previous body (constructor or method)
                w.leaveCurrentBlock()
                w.emit("}")

                // First inner output is explicit |this| parameter
                w.declare(instr.innerOutput(0), as: "this")
                let method = classDefinitions.current.nextMethod()
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(method.parameters, as: vars)
                let METHOD = method.name
                w.emit("\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()

            case .endClass:
                // End the previous body (constructor or method)
                w.leaveCurrentBlock()
                w.emit("}")

                classDefinitions.pop()

                // End the class definition
                w.leaveCurrentBlock()
                w.emit("}")

            case .callSuperConstructor:
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let EXPR = CallExpression.new() + "super(" + liftCallArguments(args) + ")"
                w.emit("\(EXPR);")

            case .callSuperMethod(let op):
                let args = instr.variadicInputs.map({ w.retrieve(expressionFor: $0) })
                let expr = CallExpression.new() + "super.\(op.methodName)(" + liftCallArguments(args)  + ")"
                w.assign(expr, to: instr.output)

            case .loadSuperProperty(let op):
                let expr = MemberExpression.new() + "super.\(op.propertyName)"
                w.assign(expr, to: instr.output)

            case .storeSuperProperty(let op):
                let PROPERTY = op.propertyName
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("super.\(PROPERTY) = \(VALUE);")

            case .storeSuperPropertyWithBinop(let op):
                let PROPERTY = op.propertyName
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("super.\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .beginIf(let op):
                var COND = w.retrieve(expressionFor: instr.input(0))
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
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("switch (\(VALUE)) {")
                w.enterNewBlock()

            case .beginSwitchCase:
                let VALUE = w.retrieve(expressionFor: instr.input(0))
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
                // Instead, we should create a LoopHeader block in which arbitrary expressions can be executed.
                let lhs = w.retrieve(identifierFor: instr.input(0))
                let rhs = w.retrieve(identifierFor: instr.input(1))
                let COND = BinaryExpression.new() + lhs + " " + op.comparator.token + " " + rhs
                w.emit("while (\(COND)) {")
                w.enterNewBlock()

            case .endWhileLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginDoWhileLoop:
                w.emit("do {")
                w.enterNewBlock()

            case .endDoWhileLoop:
                w.leaveCurrentBlock()
                let begin = Block(endedBy: instr, in: program.code).begin
                let comparator = (begin.op as! BeginDoWhileLoop).comparator
                let lhs = w.retrieve(expressionFor: begin.input(0))
                let rhs = w.retrieve(expressionFor: begin.input(1))
                let COND = BinaryExpression.new() + lhs + " " + comparator.token + " " + rhs
                w.emit("} while (\(COND));")

            case .beginForLoop(let op):
                let I = w.declare(instr.innerOutput)
                let INITIAL = w.retrieve(expressionFor: instr.input(0))
                let COND = BinaryExpression.new() + I + " " + op.comparator.token + " " + w.retrieve(expressionFor: instr.input(1))
                let EXPR: Expression
                // This is a bit of a hack. Instead, maybe we should have a way of simplifying expressions through some pattern matching code?
                let step = w.retrieve(expressionFor: instr.input(2))
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
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                w.emit("for (\(LET) \(V) in \(OBJ)) {")
                w.enterNewBlock()

            case .endForInLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginForOfLoop:
                let V = w.declare(instr.innerOutput)
                let LET = w.declarationKeyword(for: instr.innerOutput)
                let OBJ = w.retrieve(expressionFor: instr.input(0))
                w.emit("for (\(LET) \(V) of \(OBJ)) {")
                w.enterNewBlock()

            case .beginForOfWithDestructLoop(let op):
                let outputs = w.declareAll(instr.innerOutputs)
                let PATTERN = liftArrayDestructPattern(indices: op.indices, outputs: outputs, hasRestElement: op.hasRestElement)
                let LET = w.varKeyword
                let OBJ = w.retrieve(expressionFor: instr.input(0))
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
                let VALUE = w.retrieve(expressionFor: instr.input(0))
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
                let VALUE = w.retrieve(expressionFor: instr.input(0))
                w.emit("fuzzilli('FUZZILLI_PRINT', \(VALUE));")
            }
        }

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

    private func liftCallArguments(_ args: [Expression], spreading spreads: [Bool] = []) -> String {
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

    private func liftPropertyDescriptor(flags: PropertyFlags, type: PropertyType, values: [Expression]) -> String {
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
        switch type {
        case .value:
            parts.append("value: \(values[0])")
        case .getter:
            parts.append("get: \(values[0])")
        case .setter:
            parts.append("set: \(values[0])")
        case .getterSetter:
            parts.append("get: \(values[0])")
            parts.append("set: \(values[1])")
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

        /// Retrieve the JavaScript expression for the given FuzzIL variable.
        ///
        /// This is a mutating operation: if the expression is being inlined, this will:
        ///  * emit all pending expressions that need to execute first
        ///  * remove this expression from the expression mapping
        mutating func retrieve(expressionFor v: Variable) -> Expression {
            guard let expression = expressions[v] else {
                fatalError("Don't have an expression for variable \(v)")
            }

            if expression.isEffectful {
                // Inlined, effectful expressions must only be used once. To guarantee that, remove the expression from the dictionary.
                expressions.removeValue(forKey: v)

                // Emit all pending expressions that need to be evaluated prior to this one.
                var i = 0
                while i < pendingExpressions.count {
                    let pending = pendingExpressions[i]
                    i += 1
                    if pending == v { break }
                    emitPendingExpression(forVariable: pending)
                }
                pendingExpressions.removeFirst(i)
            }

            return expression
        }

        /// Retrieve a JavaScript identifier for the given FuzzIL variable.
        ///
        /// This will retrieve the expression for the given variable and, if it is not an identifier (because the expression is being inlined), store it into a local variable.
        /// Useful mostly for aesthetic reasons, when assigning a value to a temporary variable will result in more readable code.
        mutating func retrieve(identifierFor v: Variable) -> Expression {
            var expr = retrieve(expressionFor: v)
            if expr.type !== Identifier {
                expressions.removeValue(forKey: v)
                let LET = declarationKeyword(for: v)
                let V = declare(v)
                emit("\(LET) \(V) = \(expr);")
                expr = Identifier.new(V)
            }
            return expr
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
        private mutating func emitPendingExpressions() {
            for v in pendingExpressions {
                emitPendingExpression(forVariable: v)
            }
            pendingExpressions.removeAll(keepingCapacity: true)
        }

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
                return analyzer.numUses(of: v) > 0
            case .effectful:
                return analyzer.numUses(of: v) == 1
            }
        }
    }
}
