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

    private let logger: Logger
    private var wasmLiftingFailures = 0
    private var liftedSamples = 0

    /// The version of the ECMAScript standard that this lifter generates code for.
    let version: ECMAScriptVersion

    /// This environment is used if we need to re-type a program before we compile Wasm code.
    private var environment: Environment?

    /// Counter to assist the lifter in detecting nested CodeStrings
    private var codeStringNestingLevel = 0

    /// Stack of for-loop header parts. A for-loop's header consists of three different blocks (initializer, condition, afterthought), which
    /// are lifted independently but should then typically be combined into a single line. This helper stack makes that possible.
    struct ForLoopHeader {
        var initializer = ""
        var condition = ""
        // No need for the afterthought string since this struct will be consumed
        // by the handler for the afterthought block.
        var loopVariables = [String]()
    }
    private var forLoopHeaderStack = Stack<ForLoopHeader>()

    // Stack for object literals.
    private var objectLiteralStack = Stack<ObjectLiteralWriter>()
    private var currentObjectLiteral: ObjectLiteralWriter {
        get {
            return objectLiteralStack.top
        }
        set(newValue) {
            objectLiteralStack.top = newValue
        }
    }

    public init(prefix: String = "",
                suffix: String = "",
                ecmaVersion: ECMAScriptVersion,
                environment: Environment? = nil) {
        self.prefix = prefix
        self.suffix = suffix
        self.version = ecmaVersion
        self.environment = environment
        self.logger = Logger(withLabel: "JavaScriptLifter")
    }

    public func lift(_ program: Program, withOptions options: LiftingOptions) -> String {
        liftedSamples += 1
        // Perform some analysis on the program, for example to determine variable uses
        var needToSupportExploration = false
        var needToSupportProbing = false
        var needToSupportFixup = false
        var needToSupportWasm = false
        var analyzer = DefUseAnalyzer(for: program)
        // If this program has a WasmModule, i.e. has a BeginWasmModule / EndWasmModule instruction, we need a typer to collect type information for lifting of that module.
        // This typer is shared across WasmLifters and a WasmLifter is only valid for a single WasmModule.
        var typer: JSTyper? = nil
        // The currently active WasmLifter, we can only have one of them.
        var wasmLifter: WasmLifter? = nil
        for instr in program.code {
            analyzer.analyze(instr)
            if instr.op is Explore { needToSupportExploration = true }
            if instr.op is Probe { needToSupportProbing = true }
            if instr.op is Fixup { needToSupportFixup = true }
            if instr.op is BeginWasmModule { needToSupportWasm = true }
        }
        analyzer.finishAnalysis()

        if needToSupportWasm {
            // If we need to support Wasm we need to type all instructions outside of Wasm such that the WasmLifter can access extra type information during lifting.
            typer = JSTyper(for: environment!)
        }

        var w = JavaScriptWriter(analyzer: analyzer, version: version, stripComments: !options.contains(.includeComments), includeLineNumbers: options.contains(.includeLineNumbers))

        var wasmCodeStarts: Int? = nil

        if options.contains(.includeComments), let header = program.comments.at(.header) {
            w.emitComment(header)
        }

        w.emitBlock(prefix)

        if needToSupportExploration {
            w.emitBlock(JavaScriptExploreLifting.prefixCode)
        }

        if needToSupportProbing {
            w.emitBlock(JavaScriptProbeLifting.prefixCode)
        }

        if needToSupportFixup {
            w.emitBlock(JavaScriptFixupLifting.prefixCode)
        }

        // Singular operation handling.
        // Singular operations (e.g. class constructors or switch default cases) should only occur once inside their surrounding blocks. If there are
        // multiple singular operations, then all but the first one are ignored. We implement this here simply by commenting them out, for which we
        // need some additional state tracking.
        struct Block {
            var seenSingularOperation = false
            var singularOperationName = ""
            var previouslyIgnoringCode: Bool
        }
        var activeBlocks = Stack([Block(previouslyIgnoringCode: false)])
        var currentlyIgnoringCode = false

        // Helper function to bind a variable to |this|. This requires special handling because |this| must never be reassigned (`this = 42;`) as that is a syntax error.
        func bindVariableToThis(_ v: Variable) {
            // Assignments to |this| are syntax errors, so we use assign() here (instead of declare()) which will make sure to emit a local variable if the FuzzIL variable is ever reassigned.
            w.assign(Identifier.new("this"), to: v)
        }

        for instr in program.code {
            if options.contains(.includeComments), let comment = program.comments.at(.instruction(instr.index)) {
                w.emitComment(comment)
            }

            // Collect type information that we might pass to the WasmLifter.
            typer?.analyze(instr)

            // Singular operation handling:
            // All but the first singular operation in the same block are removed.
            // TODO(saelo): instead consider enforcing this in FuzzIL already.
            if currentlyIgnoringCode && !activeBlocks.top.previouslyIgnoringCode {
                currentlyIgnoringCode = false
            }
            if instr.isSingular {
                if activeBlocks.top.seenSingularOperation {
                    currentlyIgnoringCode = true
                    assert(activeBlocks.top.singularOperationName == instr.op.name)
                }
                activeBlocks.top.seenSingularOperation = true
                activeBlocks.top.singularOperationName = instr.op.name
            }
            if instr.isBlockEnd {
                currentlyIgnoringCode = activeBlocks.pop().previouslyIgnoringCode
            }
            if instr.isBlockStart {
                activeBlocks.push(Block(previouslyIgnoringCode: currentlyIgnoringCode))
            }
            if currentlyIgnoringCode {
                continue
            }

            // Pass Wasm instructions to the WasmLifter
            if (instr.op as? WasmOperation) != nil {
                // Forward all the Wasm related instructions to the WasmLifter,
                // they will be emitted once we see the end of the module.
                wasmLifter!.addInstruction(instr)
                continue;
            }

            // Handling of guarded operations, part 1: unless we have special handling (e.g. for guarded property loads we use `o?.foo`),
            // we emit a try-catch around guarded operations so prepare for that.
            var guarding = false
            if instr.isGuarded && !haveSpecialHandlingForGuardedOp(instr.op) {
                assert(!instr.isBlock, "Cannot wrap block headers/footers in try-catch")
                guarding = true

                // Emit all pending expressions so that the guarded operation is guaranteed to lift to a single line.
                w.emitPendingExpressions()

                // We need to declare all outputs of the guarded operation before the try-catch so that they are
                // visible to subsequent code.
                assert(instr.numInnerOutputs == 0, "Inner outputs are not currently supported in guarded operations")
                let neededOutputs = instr.allOutputs.filter({ analyzer.numUses(of: $0) > 0 })
                if !neededOutputs.isEmpty {
                    let VARS = w.declareAll(neededOutputs).joined(separator: ", ")
                    let LET = w.varKeyword
                    w.emit("\(LET) \(VARS);")
                }

                // Lift the operation into a temporary buffer, then wrap the resulting code into try-catch afterwards.
                w.pushTemporaryOutputBuffer(initialIndentionLevel: 0)
            }

            // Retrieve all input expressions.
            //
            // Here we assume that the input expressions are evaluated exactly in the order that they appear in the instructions inputs array.
            // If that is not the case, it may change the program's semantics as inlining could reorder operations, see JavaScriptWriter.retrieve
            // for more details.
            // We also have some lightweight checking logic to ensure that the input expressions are retrieved in the correct order.
            // This does not guarantee that they will also _evaluate_ in that order at runtime, but it's probably a decent approximation.
            let inputs = w.retrieve(expressionsFor: instr.inputs)!
            var nextExpressionToFetch = 0
            func input(_ i: Int) -> Expression {
                assert(i == nextExpressionToFetch)
                nextExpressionToFetch += 1
                return inputs[i]
            }
            // Retrieves the expression for the given input and makes sure that it is an identifier. If necessary, this will create a temporary variable.
            func inputAsIdentifier(_ i: Int) -> Expression {
                let expr = input(i)
                let identifier = w.ensureIsIdentifier(expr, for: instr.input(i))
                assert(identifier.type === Identifier)
                return identifier
            }

            switch instr.op.opcode {
            case .loadInteger(let op):
                let expr: Expression
                if op.value < 0 {
                    expr = NegativeNumberLiteral.new(String(op.value))
                } else {
                    expr = NumberLiteral.new(String(op.value))
                }
                w.assign(expr, to: instr.output)

            case .loadBigInt(let op):
                let expr: Expression
                if op.value < 0 {
                    expr = NegativeNumberLiteral.new(String(op.value) + "n")
                } else {
                    expr = NumberLiteral.new(String(op.value) + "n")
                }
                w.assign(expr, to: instr.output)

            case .loadFloat(let op):
                let expr = liftFloatValue(op.value)
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
                bindVariableToThis(instr.output)

            case .loadArguments:
                w.assign(Identifier.new("arguments"), to: instr.output)

            case .createNamedVariable(let op):
                assert(op.declarationMode == .none || op.hasInitialValue)
                if op.hasInitialValue {
                    switch op.declarationMode {
                    case .none:
                        fatalError("This declaration mode doesn't have an initial value")
                    case .global:
                        w.emit("\(op.variableName) = \(input(0));")
                    case .var:
                        // Small optimization: turn `var x = undefined;` into just `var x;`
                        let initialValue = input(0).text
                        if initialValue == "undefined" {
                            w.emit("var \(op.variableName);")
                        } else {
                            w.emit("var \(op.variableName) = \(initialValue);")
                        }
                    case .let:
                        // Small optimization: turn `let x = undefined;` into just `let x;`
                        let initialValue = input(0).text
                        if initialValue == "undefined" {
                            w.emit("let \(op.variableName);")
                        } else {
                            w.emit("let \(op.variableName) = \(initialValue);")
                        }
                    case .const:
                        w.emit("const \(op.variableName) = \(input(0));")
                    }
                }
                w.declare(instr.output, as: op.variableName)

            case .loadDisposableVariable:
                let V = w.declare(instr.output);
                w.emit("using \(V) = \(input(0));");

            case .loadAsyncDisposableVariable:
                let V = w.declare(instr.output);
                w.emit("await using \(V) = \(input(0));");

            case .beginObjectLiteral:
                // We force all expressions to evaluate before the object literal.
                // Technically we could allow expression inlining into object literals, but
                // in practice it wouldn't work a lot of the time (e.g. whenever we have
                // more than one value to inline) so isn't all that useful and adds complexity.
                w.emitPendingExpressions()

                objectLiteralStack.push(ObjectLiteralWriter())

                // Push a dummy script writer so we can assert that nothing writes to it (which shouldn't happen).
                w.pushTemporaryOutputBuffer(initialIndentionLevel: 0)

            case .objectLiteralAddProperty(let op):
                let PROPERTY = op.propertyName
                let VALUE = input(0)
                assert(!PROPERTY.contains(" "))
                currentObjectLiteral.addField("\(PROPERTY): \(VALUE)")

            case .objectLiteralAddElement(let op):
                let INDEX = op.index < 0 ? "[\(op.index)]" : String(op.index)
                let VALUE = input(0)
                currentObjectLiteral.addField("\(INDEX): \(VALUE)")

            case .objectLiteralAddComputedProperty:
                let PROPERTY = input(0)
                let VALUE = input(1)
                currentObjectLiteral.addField("[\(PROPERTY)]: \(VALUE)")

            case .objectLiteralCopyProperties:
                let EXPR = SpreadExpression.new() + "..." + input(0)
                currentObjectLiteral.addField("\(EXPR)")

            case .objectLiteralSetPrototype:
                let PROTO = input(0)
                currentObjectLiteral.addField("__proto__: \(PROTO)")

            case .beginObjectLiteralMethod(let op):
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                currentObjectLiteral.beginMethod("\(METHOD)(\(PARAMS)) {", &w)
                bindVariableToThis(instr.innerOutput(0))

            case .endObjectLiteralMethod:
                currentObjectLiteral.endMethod(&w)

            case .beginObjectLiteralComputedMethod(let op):
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = input(0)
                currentObjectLiteral.beginMethod("[\(METHOD)](\(PARAMS)) {", &w)
                bindVariableToThis(instr.innerOutput(0))

            case .endObjectLiteralComputedMethod:
                currentObjectLiteral.endMethod(&w)

            case .beginObjectLiteralGetter(let op):
                assert(instr.numInnerOutputs == 1)
                let PROPERTY = op.propertyName
                currentObjectLiteral.beginMethod("get \(PROPERTY)() {", &w)
                bindVariableToThis(instr.innerOutput(0))

            case .beginObjectLiteralSetter(let op):
                assert(instr.numInnerOutputs == 2)
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                currentObjectLiteral.beginMethod("set \(PROPERTY)(\(PARAMS)) {", &w)
                bindVariableToThis(instr.innerOutput(0))

            case .endObjectLiteralGetter,
                 .endObjectLiteralSetter:
                currentObjectLiteral.endMethod(&w)

            case .endObjectLiteral:
                // We don't expect anything to have been written to the dummy output buffer.
                // Everything needs to be written into the object literal writer.
                let dummy = w.popTemporaryOutputBuffer()
                // The dummy might still contain the comments.
                assert(dummy.isEmpty || dummy.split(separator: "\n").allSatisfy( {$0.hasPrefix("//")}))

                let literal = objectLiteralStack.pop()
                if literal.isEmpty {
                    w.assign(ObjectLiteral.new("{}"), to: instr.output)
                } else if literal.canInline {
                    // In this case, we inline the object literal.
                    let code = "{ \(literal.fields.joined(separator: ", ")) }";
                    w.assign(ObjectLiteral.new(code), to: instr.output)
                } else {
                    let LET = w.declarationKeyword(for: instr.output)
                    let V = w.declare(instr.output)
                    w.emit("\(LET) \(V) = {")
                    w.enterNewBlock()
                    for field in literal.fields {
                        w.emitBlock("\(field),")
                    }
                    w.leaveCurrentBlock()
                    w.emit("};")
                }

            case .beginClassDefinition(let op):
                // The name of the class is set to the uppercased variable name. This ensures that the heuristics used by the JavaScriptExploreLifting code to detect constructors works correctly (see shouldTreatAsConstructor).
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
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("constructor(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

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
                let INDEX = op.index < 0 ? "[\(op.index)]" : String(op.index)
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
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

            case .beginClassInstanceGetter(let op):
                let PROPERTY = op.propertyName
                w.emit("get \(PROPERTY)() {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

            case .beginClassInstanceSetter(let op):
                assert(instr.numInnerOutputs == 2)
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                w.emit("set \(PROPERTY)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

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
                let INDEX = op.index < 0 ? "[\(op.index)]" : String(op.index)
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
                w.emit("static {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

            case .beginClassStaticMethod(let op):
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("static \(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

            case .beginClassStaticGetter(let op):
                assert(instr.numInnerOutputs == 1)
                let PROPERTY = op.propertyName
                w.emit("static get \(PROPERTY)() {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput)

            case .beginClassStaticSetter(let op):
                assert(instr.numInnerOutputs == 2)
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let PROPERTY = op.propertyName
                w.emit("static set \(PROPERTY)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

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
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("#\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

            case .classAddPrivateStaticProperty(let op):
                let PROPERTY = op.propertyName
                if op.hasValue {
                    let VALUE = input(0)
                    w.emit("static #\(PROPERTY) = \(VALUE);")
                } else {
                    w.emit("static #\(PROPERTY);")
                }

            case .beginClassPrivateStaticMethod(let op):
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                let METHOD = op.methodName
                w.emit("static #\(METHOD)(\(PARAMS)) {")
                w.enterNewBlock()
                bindVariableToThis(instr.innerOutput(0))

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
                let values = op.values.map({ liftFloatValue($0).text }).joined(separator: ",")
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

            case .getProperty(let op):
                let obj = input(0)
                let accessOperator = op.isGuarded ? "?." : "."
                let expr = MemberExpression.new() + obj + accessOperator + op.propertyName
                w.assign(expr, to: instr.output)

            case .setProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updateProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let PROPERTY = MemberExpression.new() + obj + "." + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of a property deletion, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let accessOperator = op.isGuarded ? "?." : "."
                let target = MemberExpression.new() + obj + accessOperator + op.propertyName
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureProperty(let op):
                let OBJ = input(0)
                let PROPERTY = op.propertyName
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: inputs.dropFirst())
                w.emit("Object.defineProperty(\(OBJ), \"\(PROPERTY)\", \(DESCRIPTOR));")

            case .getElement(let op):
                let obj = input(0)
                let accessOperator = op.isGuarded ? "?.[" : "["
                let expr = MemberExpression.new() + obj + accessOperator + op.index + "]"
                w.assign(expr, to: instr.output)

            case .setElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = input(1)
                w.emit("\(ELEMENT) = \(VALUE);")

            case .updateElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let ELEMENT = MemberExpression.new() + obj + "[" + op.index + "]"
                let VALUE = input(1)
                w.emit("\(ELEMENT) \(op.op.token)= \(VALUE);")

            case .deleteElement(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an element deletion, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let accessOperator = op.isGuarded ? "?.[" : "["
                let target = MemberExpression.new() + obj + accessOperator + op.index + "]"
                let expr = UnaryExpression.new() + "delete " + target
                w.assign(expr, to: instr.output)

            case .configureElement(let op):
                let OBJ = input(0)
                let INDEX = op.index
                let DESCRIPTOR = liftPropertyDescriptor(flags: op.flags, type: op.type, values: inputs.dropFirst())
                w.emit("Object.defineProperty(\(OBJ), \(INDEX), \(DESCRIPTOR));")

            case .getComputedProperty(let op):
                let obj = input(0)
                let accessOperator = op.isGuarded ? "?.[" : "["
                let expr = MemberExpression.new() + obj + accessOperator + input(1).text + "]"
                w.assign(expr, to: instr.output)

            case .setComputedProperty:
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let PROPERTY = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let VALUE = input(2)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updateComputedProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let PROPERTY = MemberExpression.new() + obj + "[" + input(1).text + "]"
                let VALUE = input(2)
                w.emit("\(PROPERTY) \(op.op.token)= \(VALUE);")

            case .deleteComputedProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of a property deletion, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
                let accessOperator = op.isGuarded ? "?.[" : "["
                let target = MemberExpression.new() + obj + accessOperator + input(1).text + "]"
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

            case .void:
                let expr = UnaryExpression.new() + "void " + input(0)
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
                let vars = w.declareAll(instr.innerOutputs.dropFirst(), usePrefix: "a")
                let PARAMS = liftParameters(op.parameters, as: vars)
                w.emit("function \(NAME)(\(PARAMS)) {")
                w.enterNewBlock()
                // Disallow invoking constructors without `new` (i.e. Construct in FuzzIL).
                w.emit("if (!new.target) { throw 'must be called with new'; }")
                bindVariableToThis(instr.innerOutput(0))

            case .endConstructor:
                w.leaveCurrentBlock()
                w.emit("}")

            case .directive(let op):
                assert(!op.content.contains("'"))
                w.emit("'\(op.content)';")

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
                let f = inputAsIdentifier(0)
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args) + ")"
                w.assign(expr, to: instr.output)

            case .callFunctionWithSpread(let op):
                let f = inputAsIdentifier(0)
                let args = inputs.dropFirst()
                let expr = CallExpression.new() + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                w.assign(expr, to: instr.output)

            case .construct:
                let f = inputAsIdentifier(0)
                let args = inputs.dropFirst()
                let expr = NewExpression.new() + "new " + f + "(" + liftCallArguments(args) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions so that their result is always assigned to a new variable.
                w.assign(expr, to: instr.output, allowInlining: false)

            case .constructWithSpread(let op):
                let f = inputAsIdentifier(0)
                let args = inputs.dropFirst()
                let expr = NewExpression.new() + "new " + f + "(" + liftCallArguments(args, spreading: op.spreads) + ")"
                // For aesthetic reasons we disallow inlining "new" expressions so that their result is always assigned to a new variable.
                w.assign(expr, to: instr.output, allowInlining: false)

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
                var input = input(0)
                let expr: Expression
                // Special case: we need parenthesis when performing a unary negation on a negative number literal, otherwise we'd end up with something like `--42`.
                if op.op == .Minus && input.type === NegativeNumberLiteral {
                    input = NumberLiteral.new("(\(input.text))")
                }
                if op.op.isPostfix {
                    expr = UnaryExpression.new() + input + op.op.token
                } else {
                    expr = UnaryExpression.new() + op.op.token + input
                }
                w.assign(expr, to: instr.output)

            case .binaryOperation(let op):
                var lhs = input(0)
                let rhs = input(1)
                // Special case: we need parenthesis when performing an exponentiation on a negative number literal, otherwise we get a syntax error:
                // "Unary operator used immediately before exponentiation expression. Parenthesis must be used to disambiguate operator precedence"
                if op.op == .Exp && lhs.type === NegativeNumberLiteral {
                    lhs = NumberLiteral.new("(\(lhs.text))")
                }
                let expr = BinaryExpression.new() + lhs + " " + op.op.token + " " + rhs
                w.assign(expr, to: instr.output)

            case .ternaryOperation:
                let cond = input(0)
                let value1 = input(1)
                let value2 = input(2)
                let expr = TernaryExpression.new() + cond + " ? " + value1 + " : " + value2
                w.assign(expr, to: instr.output)

            case .reassign:
                let dest = input(0)
                assert(dest.type === Identifier)
                let expr = AssignmentExpression.new() + dest + " = " + input(1)
                w.reassign(instr.input(0), to: expr)

            case .update(let op):
                let dest = input(0)
                assert(dest.type === Identifier)
                let expr = AssignmentExpression.new() + dest + " \(op.op.token)= " + input(1)
                w.reassign(instr.input(0), to: expr)

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
                let EXPLORE = JavaScriptExploreLifting.exploreFunc
                let ID = op.id
                let VALUE = input(0)
                let ARGS = inputs.dropFirst().map({ $0.text }).joined(separator: ", ")
                let RNGSEED = op.rngSeed
                w.emit("\(EXPLORE)(\"\(ID)\", \(VALUE), this, [\(ARGS)], \(RNGSEED));")

            case .probe(let op):
                let PROBE = JavaScriptProbeLifting.probeFunc
                let ID = op.id
                let VALUE = input(0)
                w.emit("\(PROBE)(\"\(ID)\", \(VALUE));")

            case .fixup(let op):
                let FIXUP = JavaScriptFixupLifting.fixupFunc
                let ID = op.id
                // The action is encoded as JSON, so we can directly emit it here. No need to encode it as string and JSON.parse it on the other side.
                let ACTION = op.action
                let ARGS = inputs.map({ $0.text }).joined(separator: ", ")
                if op.hasOutput {
                    let LET = w.declarationKeyword(for: instr.output)
                    let V = w.declare(instr.output)
                    w.emit("\(LET) \(V) = \(FIXUP)(\"\(ID)\", \(ACTION), [\(ARGS)], this);")
                } else {
                    w.emit("\(FIXUP)(\"\(ID)\", \(ACTION), [\(ARGS)], this);")
                }

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
                let obj = inputAsIdentifier(0)
                let PROPERTY = MemberExpression.new() + obj + ".#" + op.propertyName
                let VALUE = input(1)
                w.emit("\(PROPERTY) = \(VALUE);")

            case .updatePrivateProperty(let op):
                // For aesthetic reasons, we don't want to inline the lhs of an assignment, so force it to be stored in a variable.
                let obj = inputAsIdentifier(0)
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

            case .getComputedSuperProperty(_):
                let expr = MemberExpression.new() + "super[" + input(0).text + "]"
                w.assign(expr, to: instr.output)

            case .setComputedSuperProperty(_):
                let PROPERTY = input(0).text
                let VALUE = input(1)
                w.emit("super[\(PROPERTY)] = \(VALUE);")

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

            case .beginWhileLoopHeader:
                // Must not inline across loop boundaries as that would change the program's semantics.
                w.emitPendingExpressions()
                handleBeginSingleExpressionContext(with: &w, initialIndentionLevel: 2)

            case .beginWhileLoopBody:
                let COND = handleEndSingleExpressionContext(result: input(0), with: &w)
                w.emitBlock("while (\(COND)) {")
                w.enterNewBlock()

            case .endWhileLoop:
                w.leaveCurrentBlock()
                w.emit("}")

            case .beginDoWhileLoopBody:
                w.emit("do {")
                w.enterNewBlock()

            case .beginDoWhileLoopHeader:
                w.leaveCurrentBlock()
                handleBeginSingleExpressionContext(with: &w, initialIndentionLevel: 2)

            case .endDoWhileLoop:
                let COND = handleEndSingleExpressionContext(result: input(0), with: &w)
                w.emitBlock("} while (\(COND))")

            case .beginForLoopInitializer:
                // While we could inline into the loop header, we probably don't want to do that as it will often lead
                // to the initializer block becoming an arrow function, which is not very readable. So instead force
                // all pending expressions to be emitted now, before the loop.
                w.emitPendingExpressions()

                // The loop initializer is a bit odd: it may be a single expression (`for (foo(); ...)`), but it
                // could also be a variable declaration containing multiple expressions (`for (let i = X, j = Y; ...`).
                // However, we'll figure this out at the end of the block in the .beginForLoopCondition case.
                handleBeginSingleExpressionContext(with: &w, initialIndentionLevel: 2)

            case .beginForLoopCondition(let op):
                let loopVars = w.declareAll(instr.innerOutputs, usePrefix: "i")

                // The logic for a for-loop's initializer block is a little different from the lifting logic for other block headers.
                let initializer: String
                if op.numLoopVariables == 0 {
                    assert(loopVars.isEmpty)
                    // In this case the initializer really is a single expression where the result is unused.
                    initializer = handleEndSingleExpressionContext(with: &w)
                } else {
                    // In this case, the initializer declares one or more variables. We first try to lift the variable declarations
                    // as `let i = X, j = Y, ...`, however, this is _only_ possible if we have as many expressions as we have
                    // variables to declare _and_ if they are in the correct order.
                    // In particular, the following syntax is invalid: `let i = foo(), bar(), j = baz()` and so we cannot chain
                    // independent expressions using the comma operator as we do for the other loop headers.
                    // In all other cases, we lift the initializer to something like `let [i, j] = (() => { CODE })()`.
                    if w.isCurrentTemporaryBufferEmpty && w.numPendingExpressions == 0 {
                        // The "good" case: we can emit `let i = X, j = Y, ...`
                        assert(loopVars.count == inputs.count)
                        let declarations = zip(loopVars, inputs).map({ "\($0) = \($1)" }).joined(separator: ", ")
                        initializer = "let \(declarations)"
                        let code = w.popTemporaryOutputBuffer()
                        assert(code.isEmpty)
                    } else {
                        // In this case, we have to emit a temporary arrow function that returns all initial values in an array
                        w.emitPendingExpressions()
                        if op.numLoopVariables == 1 {
                            // Emit a `let i = (() => { ...; return X; })()`
                            w.emit("return \(input(0));")
                            let I = loopVars[0]
                            let CODE = w.popTemporaryOutputBuffer()
                            initializer = "let \(I) = (() => {\n\(CODE)    })()"
                        } else {
                            // Emit a `let [i, j, k] = (() => { ...; return [X, Y, Z]; })()`
                            let initialLoopVarValues = inputs.map({ $0.text }).joined(separator: ", ")
                            w.emit("return [\(initialLoopVarValues)];")
                            let VARS = loopVars.joined(separator: ", ")
                            let CODE = w.popTemporaryOutputBuffer()
                            initializer = "let [\(VARS)] = (() => {\n\(CODE)    })()"
                        }
                    }
                }

                forLoopHeaderStack.push(ForLoopHeader(initializer: initializer, loopVariables: loopVars))
                handleBeginSingleExpressionContext(with: &w, initialIndentionLevel: 2)

            case .beginForLoopAfterthought:
                var condition = handleEndSingleExpressionContext(result: input(0), with: &w)
                // Small syntactic "optimization": an empty condition is always true, so we can replace the constant "true" with an empty condition.
                if condition == "true" {
                    condition = ""
                }

                forLoopHeaderStack.top.condition = condition

                w.declareAll(instr.innerOutputs, as: forLoopHeaderStack.top.loopVariables)
                handleBeginSingleExpressionContext(with: &w, initialIndentionLevel: 2)

            case .beginForLoopBody:
                let header = forLoopHeaderStack.pop()
                let INITIALIZER = header.initializer
                var CONDITION = header.condition
                var AFTERTHOUGHT = handleEndSingleExpressionContext(with: &w)

                if !INITIALIZER.contains("\n") && !CONDITION.contains("\n") && !AFTERTHOUGHT.contains("\n") {
                    if !CONDITION.isEmpty { CONDITION = " " + CONDITION }
                    if !AFTERTHOUGHT.isEmpty { AFTERTHOUGHT = " " + AFTERTHOUGHT }
                    w.emit("for (\(INITIALIZER);\(CONDITION);\(AFTERTHOUGHT)) {")
                } else {
                    w.emitBlock("""
                                for (\(INITIALIZER);
                                    \(CONDITION);
                                    \(AFTERTHOUGHT)) {
                                """)
                }

                w.declareAll(instr.innerOutputs, as: header.loopVariables)
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

            case .beginForOfLoopWithDestruct(let op):
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
                let I: String
                if op.exposesLoopCounter {
                    I = w.declare(instr.innerOutput)
                } else {
                    I = "i"
                }
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

            case .loadNewTarget:
                w.assign(Identifier.new("new.target"), to: instr.output)

            case .print:
                let VALUE = input(0)
                w.emit("fuzzilli('FUZZILLI_PRINT', \(VALUE));")

            case .createWasmGlobal(let op):
                let V = w.declare(instr.output)
                let LET = w.varKeyword
                let type = op.value.typeString()
                var value = op.value.valueToString()
                // TODO: make this nicer? if we create an i64, we need a bigint.
                if type == "i64" {
                    value = value + "n"
                }
                w.emit("\(LET) \(V) = new WebAssembly.Global({ value: \"\(type)\", mutable: \(op.isMutable) }, \(value));")

            case .createWasmMemory(let op):
                let V = w.declare(instr.output)
                let LET = w.varKeyword
                let isMemory64 = op.memType.isMemory64
                let minPageStr = String(op.memType.limits.min) + (isMemory64 ? "n" : "")
                var maxPagesStr = ""
                if let maxPages = op.memType.limits.max {
                    maxPagesStr = ", maximum: \(maxPages)" + (isMemory64 ? "n" : "")
                }
                let addressType = isMemory64 ? "'i64'" : "'i32'"
                w.emit("\(LET) \(V) = new WebAssembly.Memory({ initial: \(minPageStr)\(maxPagesStr), address: \(addressType) });")

            case .wrapSuspending(_):
                let V = w.declare(instr.output)
                let FUNCTION = input(0)
                let LET = w.varKeyword
                w.emit("\(LET) \(V) = new WebAssembly.Suspending(\(FUNCTION));")

            case .wrapPromising(_):
                let V = w.declare(instr.output)
                let FUNCTION = input(0)
                let LET = w.varKeyword
                w.emit("\(LET) \(V) = WebAssembly.promising(\(FUNCTION));")

            case .bindMethod(let op):
                let V = w.declare(instr.output)
                let OBJECT = input(0)
                let LET = w.varKeyword
                w.emit("\(LET) \(V) = Function.prototype.call.bind(\(OBJECT).\(op.methodName));")

            case .beginWasmModule:
                wasmCodeStarts = instr.index
                wasmLifter = WasmLifter(withTyper: typer!)

            case .endWasmModule:
                // Lift the FuzzILCode of this Block first.
                w.emitComment("WasmModule Code:")
                let code = Code(program.code[wasmCodeStarts!...instr.index])

                wasmCodeStarts = nil
                w.emitComment(FuzzILLifter().lift(code))
                let LET = w.declarationKeyword(for: instr.output)
                let V = w.declare(instr.output, as: "v\(instr.output.number)")
                // TODO: support a better diagnostics mode which stores the .wasm binary file alongside the samples.
                do {
                    let (bytecode, importRefs) = try wasmLifter!.lift()
                    // Get and check that we have the imports here as expressions and fail otherwise.
                    let imports: [(Variable, Expression)] = try importRefs.map { ref in
                        if let expr = w.retrieve(expressionsFor: [ref]) {
                            return (ref, expr[0])
                        } else {
                            throw WasmLifter.CompileError.failedRetrieval
                        }
                    }
                    w.emit("\(LET) \(V) = new WebAssembly.Instance(new WebAssembly.Module(new Uint8Array([")
                    w.enterNewBlock()
                    let blockSize = 10
                    for chunk in stride(from: 0, to: bytecode.count, by: blockSize).map({ Array(bytecode[$0 ..< Swift.min($0 + blockSize, bytecode.count)])}) {
                        let byteString = chunk.map({ String(format: "0x%02X", $0) }).joined(separator: ", ") + ","
                        w.emit("\(byteString)")
                    }
                    w.leaveCurrentBlock()
                    if importRefs.isEmpty {
                        w.emit("])));")
                    } else {
                        w.emit("])),")
                        w.emit("{ imports: {")
                        w.enterNewBlock()
                        for (idx, (importRef, expr)) in imports.enumerated() {
                            w.emit("import_\(idx)_\(importRef): \(expr),")
                        }
                        w.leaveCurrentBlock()
                        w.emit("} });")
                    }
                } catch {
                    wasmLiftingFailures += 1
                    logger.warning("WasmLifting failed with error \(error), current failure count:  \(wasmLiftingFailures) (failure rate: \(String(format: "%.5f", Double(wasmLiftingFailures) / Double(liftedSamples) * 100.0))%)")
                    do {
                        // Try to save this failed program for further analysis if diagnostics are enabled.
                        if let fuzzer = Fuzzer.current {
                            fuzzer.dispatchEvent(fuzzer.events.DiagnosticsEvent, data: (name: "FailedWasmLifting-\(error)", content: try program.asProtobuf().serializedData()))
                        } else {
                            logger.warning("Not saving sample because no fuzzer was found.")
                        }
                    } catch {
                        logger.warning("Could not serialize program.")
                    }
                    // Emit a throwing operation such that we don't keep this sample.
                    w.emit("throw \"Wasmlifting failed\";")
                }
                wasmLifter = nil

            case .createWasmTable(let op):
                let V = w.declare(instr.output)
                let LET = w.varKeyword
                let type: String
                switch op.tableType.elementType {
                case .wasmExternRef:
                    type = "externref"
                case .wasmFuncRef:
                    type = "anyfunc"
                default:
                    fatalError("Unknown table type")
                }

                var maxSizeStr = ""
                if let maxSize = op.tableType.limits.max {
                    maxSizeStr = ", maximum: \(maxSize)"
                }

                w.emit("\(LET) \(V) = new WebAssembly.Table({ element: \"\(type)\", initial: \(op.tableType.limits.min)\(maxSizeStr) });")

            case .createWasmJSTag(_):
                let V = w.declare(instr.output)
                let LET = w.varKeyword
                w.emit("\(LET) \(V) = WebAssembly.JSTag;")

            case .createWasmTag(let op):
                let V = w.declare(instr.output)
                let LET = w.varKeyword
                let types = op.parameters.map {type in
                    switch(type) {
                        case .wasmExternRef:
                            return "\"externref\""
                        case .wasmf32:
                            return "\"f32\""
                        case .wasmf64:
                            return "\"f64\""
                        case .wasmi32:
                            return "\"i32\""
                        case .wasmi64:
                            return "\"i64\""
                        default:
                            fatalError("Unhandled wasm type \(type)")
                    }
                }.joined(separator: ", ")
                w.emit("\(LET) \(V) = new WebAssembly.Tag({parameters: [\(types)]});")

            case .consti64(_),
                 .consti32(_),
                 .constf32(_),
                 .constf64(_),
                 .wasmReturn(_),
                 .wasmJsCall(_),
                 .wasmi32CompareOp(_),
                 .wasmi64CompareOp(_),
                 .wasmf32CompareOp(_),
                 .wasmf64CompareOp(_),
                 .wasmi64BinOp(_),
                 .wasmi32BinOp(_),
                 .wasmi32UnOp(_),
                 .wasmi64UnOp(_),
                 .wasmf32UnOp(_),
                 .wasmf64UnOp(_),
                 .wasmf32BinOp(_),
                 .wasmf64BinOp(_),
                 .wasmi32EqualZero(_),
                 .wasmi64EqualZero(_),
                 .wasmWrapi64Toi32(_),
                 .wasmTruncatef32Toi32(_),
                 .wasmTruncatef64Toi32(_),
                 .wasmExtendi32Toi64(_),
                 .wasmTruncatef32Toi64(_),
                 .wasmTruncatef64Toi64(_),
                 .wasmConverti32Tof32(_),
                 .wasmConverti64Tof32(_),
                 .wasmDemotef64Tof32(_),
                 .wasmConverti32Tof64(_),
                 .wasmConverti64Tof64(_),
                 .wasmPromotef32Tof64(_),
                 .wasmReinterpretf32Asi32(_),
                 .wasmReinterpretf64Asi64(_),
                 .wasmReinterpreti32Asf32(_),
                 .wasmReinterpreti64Asf64(_),
                 .wasmSignExtend8Intoi32(_),
                 .wasmSignExtend16Intoi32(_),
                 .wasmSignExtend8Intoi64(_),
                 .wasmSignExtend16Intoi64(_),
                 .wasmSignExtend32Intoi64(_),
                 .wasmTruncateSatf32Toi32(_),
                 .wasmTruncateSatf64Toi32(_),
                 .wasmTruncateSatf32Toi64(_),
                 .wasmTruncateSatf64Toi64(_),
                 .wasmReassign(_),
                 .wasmDefineGlobal(_),
                 .wasmDefineTable(_),
                 .wasmDefineMemory(_),
                 .wasmLoadGlobal(_),
                 .wasmStoreGlobal(_),
                 .wasmTableGet(_),
                 .wasmTableSet(_),
                 .wasmMemoryLoad(_),
                 .wasmMemoryStore(_),
                 .beginWasmFunction(_),
                 .endWasmFunction(_),
                 .wasmBeginBlock(_),
                 .wasmEndBlock(_),
                 .wasmBeginLoop(_),
                 .wasmEndLoop(_),
                 .wasmBeginTry(_),
                 .wasmBeginCatchAll(_),
                 .wasmBeginCatch(_),
                 .wasmEndTry(_),
                 .wasmBeginTryDelegate(_),
                 .wasmEndTryDelegate(_),
                 .wasmThrow(_),
                 .wasmRethrow(_),
                 .wasmDefineTag(_),
                 .wasmBranch(_),
                 .wasmBranchIf(_),
                 .wasmBeginIf(_),
                 .wasmBeginElse(_),
                 .wasmEndIf(_),
                 .wasmNop(_),
                 .wasmUnreachable(_),
                 .wasmSelect(_),
                 .constSimd128(_),
                 .wasmSimd128IntegerUnOp(_),
                 .wasmSimd128IntegerBinOp(_),
                 .wasmSimd128FloatUnOp(_),
                 .wasmSimd128FloatBinOp(_),
                 .wasmSimd128Compare(_),
                 .wasmI64x2Splat(_),
                 .wasmI64x2ExtractLane(_),
                 .wasmSimdLoad(_):
                 fatalError("unreachable")
            }

            // Handling of guarded operations, part 2: emit the guarded operation and surround it with a try-catch.
            if guarding {
                w.emitPendingExpressions()
                let code = w.popTemporaryOutputBuffer().trimmingCharacters(in: .whitespacesAndNewlines)
                assert(!code.isEmpty)
                let lines = code.split(separator: "\n")
                if lines.count == 1 {
                    w.emit("try { \(code) } catch (e) {}")
                } else {
                    assert(lines.count > 1)
                    w.emit("try {")
                    lines.forEach({ w.emit(String($0)) })
                    w.emit("} catch (e) {}")
                }
            }
        }

        w.emitPendingExpressions()

        if needToSupportProbing {
            w.emitBlock(JavaScriptProbeLifting.suffixCode)
        }

        w.emitBlock(suffix)

        if options.contains(.includeComments), let footer = program.comments.at(.footer) {
            w.emitComment(footer)
        }

        return w.code
    }

    // Signal that the following code needs to be lifted into a single expression.
    private func handleBeginSingleExpressionContext(with w: inout JavaScriptWriter, initialIndentionLevel: Int) {
        // Lift the following code into a temporary buffer so that it can either be emitted
        // as a single expression, or as body of a temporary function, see below.
        w.pushTemporaryOutputBuffer(initialIndentionLevel: initialIndentionLevel)
    }

    // Lift all code between the begin and end of the single expression context (e.g. a loop header) into a single expression.
    // The optional result parameter contains the value to which the entire expression must ultimately evaluate.
    private func handleEndSingleExpressionContext(result maybeResult: Expression? = nil, with w: inout JavaScriptWriter) -> String {
        if w.isCurrentTemporaryBufferEmpty {
            // This means that the code consists entirely of expressions that can be inlined, and that the result
            // variable is either not an inlined expression (but instead e.g. the identifier for a local variable), or that
            // it is the most recent pending expression (in which case previously pending expressions are not emitted).
            //
            // In this case, we can emit a single expression by combining all pending expressions using the comma operator.
            var COND = CommaExpression.new()
            let expressions = w.takePendingExpressions() + (maybeResult != nil ? [maybeResult!] : [])
            for expr in expressions {
                if COND.text.isEmpty {
                    COND = COND + expr
                } else {
                    COND = COND + ", " + expr
                }
            }

            let headerContent = w.popTemporaryOutputBuffer()
            assert(headerContent.isEmpty)

            return COND.text
        } else {
            // The code is more complicated, so emit a temporary function and call it.
            w.emitPendingExpressions()
            if let result = maybeResult {
                w.emit("return \(result);")
            }
            let CODE = w.popTemporaryOutputBuffer()
            assert(CODE.contains("\n"))
            assert(CODE.hasSuffix("\n"))
            return "(() => {\n\(CODE)    })()"
        }
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
        // This will produce functions with a recognizable .name property, which the JavaScriptExploreLifting code makes use of (see shouldTreatAsConstructor).
        guard let op = instr.op as? BeginAnyFunction else {
            fatalError("Invalid operation passed to liftFunctionDefinitionBegin")
        }
        let functionName: String
        if let op = instr.op as? BeginAnyNamedFunction, op.functionName != nil {
            functionName = op.functionName!
        } else {
            functionName = "f\(instr.output.number)"
        }
        let NAME = w.declare(instr.output, as: functionName)
        let vars = w.declareAll(instr.innerOutputs, usePrefix: "a")
        let PARAMS = liftParameters(op.parameters, as: vars)
        w.emit("\(FUNCTION) \(NAME)(\(PARAMS)) {")
        w.enterNewBlock()
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

    private func liftFloatValue(_ value: Double) -> Expression {
        if value.isNaN {
            return Identifier.new("NaN")
        } else if value.isEqual(to: -Double.infinity) {
            return UnaryExpression.new("-Infinity")
        } else if value.isEqual(to: Double.infinity) {
            return Identifier.new("Infinity")
        } else if value < 0.0 {
            return NegativeNumberLiteral.new(String(value))
        } else {
            return NumberLiteral.new(String(value))
        }
    }

    private func haveSpecialHandlingForGuardedOp(_ op: Operation) -> Bool {
        switch op.opcode {
            // We handle guarded property loads by emitting an optional chain, so no try-catch is necessary.
        case .getProperty,
             .getElement,
             .getComputedProperty,
             .deleteProperty,
             .deleteElement,
             .deleteComputedProperty:
            return true
        default:
            return false
        }
    }

    /// A wrapper around a ScriptWriter. It's main responsibility is expression inlining.
    ///
    /// Expression inlining roughly works as follows:
    /// - FuzzIL operations that map to a single JavaScript expressions are lifted to these expressions and associated with the output FuzzIL variable using assign()
    /// - If an expression is pure, such as for example a number literal, it will be inlined into all its uses
    /// - On the other hand, if an expression is effectful, it can only be inlined if there is a single use of the FuzzIL variable (otherwise, the expression would execute multiple times), _and_ if there is no other effectful expression before that use (otherwise, the execution order of instructions would change)
    /// - To achieve that, pending effectful expressions are kept in a list of expressions which must execute in FIFO order at runtime
    /// - To retrieve the expression for an input FuzzIL variable, the retrieve() function is used. If an inlined expression is returned, this function takes care of first emitting pending expressions if necessary (to ensure correct execution order)
    public struct JavaScriptWriter {
        private var writer: ScriptWriter
        private var analyzer: DefUseAnalyzer

        /// Variable declaration keywords to use.
        let varKeyword: String
        let constKeyword: String

        /// Code can be emitted into a temporary buffer instead of into the final script. This is mainly useful for inlining entire blocks.
        /// The typical way to use this would be to call pushTemporaryOutputBuffer() when handling a BeginXYZBlock, then calling
        /// popTemporaryOutputBuffer() when handling the corresponding EndXYZBlock and then either inlining the block's body
        /// or assigning it to a local variable.
        var temporaryOutputBufferStack = Stack<ScriptWriter>()

        var code: String {
            assert(pendingExpressions.isEmpty)
            assert(temporaryOutputBufferStack.isEmpty)
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

        // We also try to inline reassignments once, into the next use of the reassigned FuzzIL variable. However, for all subsequent uses we have to use the
        // identifier of the JavaScript variable again (the lhs of the reassignment). This map is used to remember these identifiers.
        // See `reassign()` for more details about reassignment inlining.
        private var inlinedReassignments = VariableMap<Expression>()

        init(analyzer: DefUseAnalyzer, version: ECMAScriptVersion, stripComments: Bool = false, includeLineNumbers: Bool = false, indent: Int = 4) {
            self.writer = ScriptWriter(stripComments: stripComments, includeLineNumbers: includeLineNumbers, indent: indent)
            self.analyzer = analyzer
            self.varKeyword = version == .es6 ? "let" : "var"
            self.constKeyword = version == .es6 ? "const" : "var"
        }

        /// Assign a JavaScript expression to a FuzzIL variable.
        ///
        /// If the expression can be inlined, it will be associated with the variable and returned at its use. If the expression cannot be inlined,
        /// the expression will be emitted either as part of a variable definition or as an expression statement (if the value isn't subsequently used).
        mutating func assign(_ expr: Expression, to v: Variable, allowInlining: Bool = true) {
            if let V = expressions[v] {
                // In some situations, for example in the case of guarded operations that require a try-catch around them,
                // the output variable is declared up-front and so we lift to a variable assignment.
                assert(V.type === Identifier)
                emit("\(V) = \(expr);")
            } else if allowInlining && shouldTryInlining(expr, producing: v) {
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

        /// Reassign a FuzzIL variable to a new JavaScript expression.
        /// The given expression is expected to be an AssignmentExpression.
        ///
        /// Variable reassignments such as `a = b` or `c += d` can be inlined once into the next use of the reassigned variable. All subsequent uses then again use the variable.
        /// For example:
        ///
        ///     a += b;
        ///     foo(a);
        ///     bar(a);
        ///
        /// Can also be lifted as:
        ///
        ///     foo(a += b);
        ///     bar(a);
        ///
        /// However, this is only possible if the next use is not again a reassignment, otherwise it'd lead to something like `(a = b) = c;`which is invalid.
        /// To simplify things, we therefore only allow the inlining if there is exactly one reassignment.
        mutating func reassign(_ v: Variable, to expr: Expression) {
            assert(expr.type === AssignmentExpression)
            assert(analyzer.numAssignments(of: v) > 1)
            guard analyzer.numAssignments(of: v) == 2 else {
                // There are multiple (re-)assignments, so we cannot inline the assignment expression.
                return emit("\(expr);")
            }

            guard let identifier = expressions[v] else {
                fatalError("Missing identifier for reassignment")
            }
            assert(identifier.type === Identifier)
            expressions[v] = expr
            pendingExpressions.append(v)
            assert(!inlinedReassignments.contains(v))
            inlinedReassignments[v] = identifier
        }

        /// Retrieve the JavaScript expressions assigned to the given FuzzIL variables.
        ///
        /// The returned expressions _must_ subsequently execute exactly in the order that they are returned (i.e. in the order of the input variables).
        /// Otherwise, expression inlining will change the semantics of the program.
        ///
        /// This is a mutating operation as it can modify the list of pending expressions or emit pending expression to retain the correct ordering.
        mutating func retrieve(expressionsFor queriedVariables: ArraySlice<Variable>) -> [Expression]? {
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
            // Filter the queried variables for the suffix matching: for that we only care about
            //  - variables for which the expressions are currently pending (i.e. are being inlined)
            //  - the first occurance of every variable. This is irrelevant for "normal" pending expressions
            //    since they can only occur once (otherwise, they wouldn't be inlined), but is important
            //    for inlined reassignments, e.g. to be able to correctly handle `foo(a = 42, a, bar(), a);`
            var queriedPendingExpressions = [Variable]()
            for v in queriedVariables where pendingExpressions.contains(v) && !queriedPendingExpressions.contains(v) {
                queriedPendingExpressions.append(v)
            }
            for v in queriedPendingExpressions.reversed() {
                assert(matchingSuffixLength < pendingExpressions.count)
                let currentSuffixPosition = pendingExpressions.count - 1 - matchingSuffixLength
                if matchingSuffixLength < pendingExpressions.count && v == pendingExpressions[currentSuffixPosition] {
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

            for v in queriedVariables {
                guard let expression = expressions[v] else {
                    return nil
                }
                if expression.isEffectful {
                    usePendingExpression(expression, forVariable: v)
                }
                results.append(expression)
            }

            return results
        }

        /// If the given expression is not an identifier, create a temporary variable and assign the expression to it.
        ///
        /// Mostly used for aesthetical reasons, if an expression is more readable if some subexpression is always an identifier.
        mutating func ensureIsIdentifier(_ expr: Expression, for v: Variable) -> Expression {
            if expr.type === Identifier {
                return expr
            } else if expr.type === AssignmentExpression {
                // Just need to emit the assignment now and return the lhs.
                emit("\(expr);")
                guard let identifier = inlinedReassignments[v] else {
                    fatalError("Don't have an identifier for a reassignment")
                }
                return identifier
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
        mutating func declareAll<Variables: Sequence>(_ vars: Variables, usePrefix prefix: String = "v") -> [String] where Variables.Element == Variable {
            return vars.map({ declare($0, as: prefix + String($0.number)) })
        }

        /// Declare all of the given variables. Equivalent to calling declare() for each of them.
        mutating func declareAll(_ vars: ArraySlice<Variable>, as names: [String]) {
            assert(vars.count == names.count)
            zip(vars, names).forEach({ declare($0, as: $1) })
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
            pendingExpressions.removeAll()
        }

        mutating func pushTemporaryOutputBuffer(initialIndentionLevel: Int) {
            temporaryOutputBufferStack.push(writer)
            writer = ScriptWriter(stripComments: writer.stripComments, includeLineNumbers: false, indent: writer.indent.count, initialIndentionLevel: initialIndentionLevel)
        }

        mutating func popTemporaryOutputBuffer() -> String {
            assert(pendingExpressions.isEmpty)
            let code = writer.code
            writer = temporaryOutputBufferStack.pop()
            return code
        }

        var isCurrentTemporaryBufferEmpty: Bool {
            return writer.code.isEmpty
        }

        var numPendingExpressions: Int {
            return pendingExpressions.count
        }

        // The following methods are mostly useful for lifting loop headers. See the corresponding for more details.
        mutating func takePendingExpressions() -> [Expression] {
            var result = [Expression]()
            for v in pendingExpressions {
                guard let expr = expressions[v] else {
                    fatalError("Missing expression for variable \(v)")
                }
                usePendingExpression(expr, forVariable: v)
                result.append(expr)
            }
            pendingExpressions.removeAll()
            return result
        }

        mutating func lastPendingExpressionIsFor(_ v: Variable) -> Bool {
            return pendingExpressions.last == v
        }

        mutating func isExpressionPending(for v: Variable) -> Bool {
            return pendingExpressions.contains(v)
        }

        /// Emit the pending expression for the given variable.
        /// Note: this does _not_ remove the variable from the pendingExpressions list. It is the caller's responsibility to do so (as the caller can usually batch multiple removals together).
        private mutating func emitPendingExpression(forVariable v: Variable) {
            guard let EXPR = expressions[v] else {
                fatalError("Missing expression for variable \(v)")
            }

            usePendingExpression(EXPR, forVariable: v)

            if EXPR.type === AssignmentExpression {
                // Reassignments require special handling: there is already a variable declared for the lhs,
                // so we only need to emit the AssignmentExpression as an expression statement.
                writer.emit("\(EXPR);")
            } else if analyzer.numUses(of: v) > 0 {
                let LET = declarationKeyword(for: v)
                let V = declare(v)
                // Need to use writer.emit instead of emit here as the latter will emit all pending expressions.
                writer.emit("\(LET) \(V) = \(EXPR);")
            } else {
                // Pending expressions with no uses are allowed and are for example necessary to be able to
                // combine multiple expressions into a single comma-expression for e.g. a loop header.
                // See the loop header lifting code and tests for examples.
                if EXPR.type === ObjectLiteral {
                    // Special case: we cannot just emit these as expression statements as they would
                    // not be distinguishable from block statements. So create a dummy variable.
                    let LET = constKeyword
                    let V = declare(v)
                    writer.emit("\(LET) \(V) = \(EXPR);")
                } else {
                    writer.emit("\(EXPR);")
                }
            }
        }

        /// When a pending expression is used (either emitted or attached to another expression), it should be removed from the list of
        /// available expressions. Further, inlined reassignments require additional handling, see `reassign` for more details.
        /// This function takes care of both of these things.
        private mutating func usePendingExpression(_ expr: Expression, forVariable v: Variable) {
            // Inlined expressions must only be used once, so delete it from the list of available expressions.
            expressions.removeValue(forKey: v)

            // If the inlined expression is an assignment expression, we now have to restore the previous
            // expression for that variable (which must be an identifier). See `reassign` for more details.
            if let lhs = inlinedReassignments[v] {
                assert(expr.type === AssignmentExpression)
                expressions[v] = lhs
            }
        }

        /// Decide if we should attempt to inline the given expression. We do that if:
        ///  * The output variable is not reassigned later on (otherwise, that reassignment would fail as the variable was never defined)
        ///  * The output variable is pure OR
        ///  * The output variable is effectful and at most one use. However, in this case, the expression will only be inlined if it is still the next expression to be evaluated at runtime.
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
                // We also attempt to inline expressions for variables that are unused. This may seem strange since it
                // usually will just lead to the expression being emitted as soon as the next line of code is emitted,
                // however it is necessary to be able to combime multiple expressions into a single comma-expression as
                // is done for example when lifting loop headers.
                return analyzer.numUses(of: v) <= 1
            }
        }
    }

    // Helper class for formatting object literals.
    private struct ObjectLiteralWriter {
        var fields: [String] = []
        var canInline = true

        var isEmpty: Bool { fields.isEmpty }

        mutating func addField(_ fieldDefinition: String) {
            fields.append(fieldDefinition)
            canInline = canInline && fields.count < 5
        }

        mutating func beginMethod(_ header: String, _ writer: inout JavaScriptWriter) {
            // We don't inline object literals if they have any methods
            canInline = false

            fields.append(header + "\n")
            // We must now emit pending expressions to prevent them from being inlined
            // into the method's body (which would not be semantically correct).
            writer.emitPendingExpressions()
            writer.pushTemporaryOutputBuffer(initialIndentionLevel: 0)
            writer.enterNewBlock()
        }

        mutating func endMethod(_ writer: inout JavaScriptWriter) {
            writer.leaveCurrentBlock()
            let body = writer.popTemporaryOutputBuffer()
            fields[fields.count - 1] += body + "}"
        }
    }
}
