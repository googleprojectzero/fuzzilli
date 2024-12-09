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

/// A JavaScript operation in the FuzzIL language.
class JsOperation: Operation {
    override init(numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, firstVariadicInput: Int = -1, attributes: Attributes = [], requiredContext: Context = .javascript, contextOpened: Context = .empty) {
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, firstVariadicInput: firstVariadicInput, attributes: attributes, requiredContext: requiredContext, contextOpened: contextOpened)
    }
}

/// A JavaScript operation that can guard against runtime exceptions.
///
/// This can be used when it cannot statically be guaranteed that an
/// operation will not cause a runtime exception. For example, if we're
/// generating a method call but aren't sure that the method exists, or
/// if we're emitting a binary operation where one of the inputs may be
/// a bigint and the other a number.
///
/// During lifting, guarded operations will typically be surrounded by
/// try-catch blocks, although special handling is also possible. For
/// example, a guarded property load could be lifted as `o?.a`.
///
/// Using a guardable operation is more efficient than emitting explicit
/// try-catch blocks: for one, it allows the outputs of a guarded operation
/// to be used by subsequent code. Further, it makes it possible to use
/// runtime instrumentation to fix guarded operations or turn them into
/// unguarded ones if no runtime exception is raised.
///
/// The outputs of guarded operations (i.e. `GuardableOperations`
/// where the guard is active) should always be typed as `.anything`
/// by our static type inference. This allows us to try and fix failing
/// operations at runtime (when we have a full picture of e.g. the methods
/// that exist on an object or the types of variables available as inputs)
/// because we know that the following code will not make any specific
/// assumptions about the type of the outputs.
class GuardableOperation: JsOperation {
    /// Whether guarding is active or not.
    /// When lifting to JavaScript, this generally determines whether a try-catch
    /// is emitted around the operation or not.
    let isGuarded: Bool

    init(isGuarded: Bool, numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, firstVariadicInput: Int = -1, attributes: Attributes = [], requiredContext: Context = .javascript) {
        assert(attributes.isDisjoint(with: [.isBlockStart, .isBlockEnd]), "Only simple operations can be guardable")
        self.isGuarded = isGuarded
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, firstVariadicInput: firstVariadicInput, attributes: attributes, requiredContext: requiredContext)
    }

    // Helper functions to enable guards.
    // If the given operation already has guarding enabled, then this function does
    // nothing and simply returns the input. Otherwise it creates a copy of the
    // operations which has guarding enabled.
    static func enableGuard(of operation: GuardableOperation) -> GuardableOperation {
        if operation.isGuarded {
            return operation
        }
        switch operation.opcode {
        case .getProperty(let op):
            return GetProperty(propertyName: op.propertyName, isGuarded: true)
        case .deleteProperty(let op):
            return DeleteProperty(propertyName: op.propertyName, isGuarded: true)
        case .getElement(let op):
            return GetElement(index: op.index, isGuarded: true)
        case .deleteElement(let op):
            return DeleteElement(index: op.index, isGuarded: true)
        case .getComputedProperty:
            return GetComputedProperty(isGuarded: true)
        case .deleteComputedProperty:
            return DeleteComputedProperty(isGuarded: true)
        case .callFunction(let op):
            return CallFunction(numArguments: op.numArguments, isGuarded: true)
        case .callFunctionWithSpread(let op):
            return CallFunctionWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: true)
        case .construct(let op):
            return Construct(numArguments: op.numArguments, isGuarded: true)
        case .constructWithSpread(let op):
            return ConstructWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: true)
        case .callMethod(let op):
            return CallMethod(methodName: op.methodName, numArguments: op.numArguments, isGuarded: true)
        case .callMethodWithSpread(let op):
            return CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments, spreads: op.spreads, isGuarded: true)
        case .callComputedMethod(let op):
            return CallComputedMethod(numArguments: op.numArguments, isGuarded: true)
        case .callComputedMethodWithSpread(let op):
            return CallComputedMethodWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: true)
        default:
            fatalError("All guardable operations should be handled")
        }
    }

    // Helper functions to disable guards.
    // If the given operation already has guarding disabled, then this function does
    // nothing and simply returns the input. Otherwise it creates a copy of the
    // operations which has guarding disabled.
    static func disableGuard(of operation: GuardableOperation) -> GuardableOperation {
        if !operation.isGuarded {
            return operation
        }
        switch operation.opcode {
        case .getProperty(let op):
            return GetProperty(propertyName: op.propertyName, isGuarded: false)
        case .deleteProperty(let op):
            return DeleteProperty(propertyName: op.propertyName, isGuarded: false)
        case .getElement(let op):
            return GetElement(index: op.index, isGuarded: false)
        case .deleteElement(let op):
            return DeleteElement(index: op.index, isGuarded: false)
        case .getComputedProperty:
            return GetComputedProperty(isGuarded: false)
        case .deleteComputedProperty:
            return DeleteComputedProperty(isGuarded: false)
        case .callFunction(let op):
            return CallFunction(numArguments: op.numArguments, isGuarded: false)
        case .callFunctionWithSpread(let op):
            return CallFunctionWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: false)
        case .construct(let op):
            return Construct(numArguments: op.numArguments, isGuarded: false)
        case .constructWithSpread(let op):
            return ConstructWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: false)
        case .callMethod(let op):
            return CallMethod(methodName: op.methodName, numArguments: op.numArguments, isGuarded: false)
        case .callMethodWithSpread(let op):
            return CallMethodWithSpread(methodName: op.methodName, numArguments: op.numArguments, spreads: op.spreads, isGuarded: false)
        case .callComputedMethod(let op):
            return CallComputedMethod(numArguments: op.numArguments, isGuarded: false)
        case .callComputedMethodWithSpread(let op):
            return CallComputedMethodWithSpread(numArguments: op.numArguments, spreads: op.spreads, isGuarded: false)
        default:
            fatalError("All guardable operations should be handled")
        }
    }
}

final class LoadInteger: JsOperation {
    override var opcode: Opcode { .loadInteger(self) }

    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadBigInt: JsOperation {
    override var opcode: Opcode { .loadBigInt(self) }

    // This could be a bigger integer type, but it's most likely not worth the effort
    let value: Int64

    init(value: Int64) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadFloat: JsOperation {
    override var opcode: Opcode { .loadFloat(self) }

    let value: Double

    init(value: Double) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadString: JsOperation {
    override var opcode: Opcode { .loadString(self) }

    let value: String

    init(value: String) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadBoolean: JsOperation {
    override var opcode: Opcode { .loadBoolean(self) }

    let value: Bool

    init(value: Bool) {
        self.value = value
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

final class LoadUndefined: JsOperation {
    override var opcode: Opcode { .loadUndefined(self) }

    init() {
        super.init(numOutputs: 1)
    }
}

final class LoadNull: JsOperation {
    override var opcode: Opcode { .loadNull(self) }

    init() {
        super.init(numOutputs: 1)
    }
}

final class LoadThis: JsOperation {
    override var opcode: Opcode { .loadThis(self) }

    init() {
        super.init(numOutputs: 1)
    }
}

final class LoadArguments: JsOperation {
    override var opcode: Opcode { .loadArguments(self) }

    init() {
        super.init(numOutputs: 1, requiredContext: [.javascript, .subroutine])
    }
}

/// Named Variables.
///
/// Named variables are variables with a specific name. They are created through the
/// CreateNamedVariable operation and are useful whenever the name of a variable is
/// (potentially) important. In particular they are used frequenty when compiling
/// existing JavaScript code to FuzzIL. Furthermore, named variables are also used to
/// access builtins as these are effectively just global/pre-existing named variables.
///
/// When declaring a new named variable (i.e. when the declarationMode is not .none),
/// then an initial value must be provided (as first and only input to the operation).
/// "Uninitialized" named variables can be created by using `undefined` as initial value.
///
/// The following code is a simple demonstration of named variables:
///
///    // Make an existing named variable (e.g. a builtin) available
///    v0 <- CreateNamedVariable 'print', declarationMode: .none
///
///    // Overwrite an existing named variable
///    v1 <- CreateNamedVariable 'foo', declarationMode: .none
///    v2 <- CallFunction v0, v1
///    v3 <- LoadString 'bar'
///    Reassign v1, v3
///
///    // Declare a new named variable
///    v4 <- CreateNamedVariable 'baz', declarationMode: .var, v1
///    v5 <- LoadString 'bla'
///    Update v4 '+' v5
///    v5 <- CallFunction v0, v4
///
/// This will lift to JavaScript code similar to the following:
///
///    print(foo);
///    foo = "bar";
///    var baz = foo;
///    baz += "bla";
///    print(baz);
///
public enum NamedVariableDeclarationMode : CaseIterable {
    // The variable is assumed to already exist and therefore is not declared again.
    // This is for example used for global variables and builtins, but also to support
    // variable and function hoisting where an identifier is used before it is defined.
    case none
    // Declare the variable as global variable without any declaration keyword.
    case global
    // Declare the variable using the 'var' keyword.
    case `var`
    // Declare the variable using the 'let' keyword.
    case `let`
    // Declare the variable using the 'const' keyword.
    case const
}

final class CreateNamedVariable: JsOperation {
    override var opcode: Opcode { .createNamedVariable(self) }

    let variableName: String
    let declarationMode: NamedVariableDeclarationMode

    // Currently, all named variable declarations need an initial value. "undefined" can be
    // used when no initial value is available, in which case the lifter will not emit an assignment.
    // We could also consider allowing variable declarations without an initial value, however for
    // both .global and .const declarations, we always need an initial value to produce valid code.
    var hasInitialValue: Bool {
        return declarationMode != .none
    }

    init(_ name: String, declarationMode: NamedVariableDeclarationMode) {
        self.variableName = name
        self.declarationMode = declarationMode
        super.init(numInputs: declarationMode == .none ? 0 : 1, numOutputs: 1, attributes: .isMutable)
    }
}

final class LoadDisposableVariable: JsOperation {
    override var opcode: Opcode { .loadDisposableVariable(self) }

    init() {
        // Based on spec text, it is a Syntax error if UsingDeclaration and AwaitUsingDeclaration
        // are not contained, either directly or indirectly, within a Block, CaseBlock, ForStatement,
        // ForInOfStatement, FunctionBody, GeneratorBody, AsyncGeneratorBody, AsyncFunctionBody,
        // or ClassStaticBlockBody.
        // https://tc39.es/proposal-explicit-resource-management/#sec-let-and-const-declarations-static-semantics-early-errors

        // TODO: Add support for block context to complete LoadDisposableVariable and
        // LoadAsyncDisposableVariable operations.
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.javascript, .subroutine])
    }
}

final class LoadAsyncDisposableVariable: JsOperation {
    override var opcode: Opcode { .loadAsyncDisposableVariable(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.javascript, .asyncFunction])
    }
}

public struct RegExpFlags: OptionSet, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public func asString() -> String {
        var strRepr = ""

        // These flags are mutually exclusive, will lead to runtime exceptions if used together
        assert(!(contains(.unicode) && contains(.unicodeSets)))

        for (flag, char) in RegExpFlags.flagToCharDict {
            if contains(flag) {
                strRepr += char
            }
        }
        return strRepr
    }

    public static func fromString(_ str: String) -> RegExpFlags? {
        var flags = RegExpFlags()
        for c in str {
            switch c {
            case "i":
                flags.formUnion(.caseInsensitive)
            case "g":
                flags.formUnion(.global)
            case "m":
                flags.formUnion(.multiline)
            case "s":
                flags.formUnion(.dotall)
            case "u":
                flags.formUnion(.unicode)
            case "y":
                flags.formUnion(.sticky)
            case "d":
                flags.formUnion(.hasIndices)
            case "v":
                flags.formUnion(.unicodeSets)
            default:
                return nil
            }
        }
        // These flags are mutually exclusive, will lead to runtime exceptions if used together
        assert(!(flags.contains(.unicode) && flags.contains(.unicodeSets)))
        return flags
    }

    static let empty           = RegExpFlags([])
    static let caseInsensitive = RegExpFlags(rawValue: 1 << 0) // i
    static let global          = RegExpFlags(rawValue: 1 << 1) // g
    static let multiline       = RegExpFlags(rawValue: 1 << 2) // m
    static let dotall          = RegExpFlags(rawValue: 1 << 3) // s
    static let unicode         = RegExpFlags(rawValue: 1 << 4) // u
    static let sticky          = RegExpFlags(rawValue: 1 << 5) // y
    static let hasIndices      = RegExpFlags(rawValue: 1 << 6) // d
    static let unicodeSets     = RegExpFlags(rawValue: 1 << 7) // v

    public static func random() -> RegExpFlags {
        var flags = RegExpFlags(rawValue: UInt32.random(in: 0..<(1<<8)))
        if flags.contains(.unicode) && flags.contains(.unicodeSets) {
            // clear one of them as they are mutually exclusive, they will throw a runtime exception if used together.
            withEqualProbability({
                flags.subtract(.unicode)
            }, {
                flags.subtract(.unicodeSets)
            })
        }
        return flags
    }

    private static let flagToCharDict: [RegExpFlags:String] = [
        .empty:           "",
        .caseInsensitive: "i",
        .global:          "g",
        .multiline:       "m",
        .dotall:          "s",
        .unicode:         "u",
        .sticky:          "y",
        .hasIndices:      "d",
        .unicodeSets:     "v",
    ]

    static func |(lhs: RegExpFlags, rhs: RegExpFlags) -> RegExpFlags {
        return RegExpFlags(rawValue: lhs.rawValue | rhs.rawValue)
    }
}

final class LoadRegExp: JsOperation {
    override var opcode: Opcode { .loadRegExp(self) }

    let flags: RegExpFlags
    let pattern: String

    init(pattern: String, flags: RegExpFlags) {
        self.pattern = pattern
        self.flags = flags
        super.init(numOutputs: 1, attributes: [.isMutable])
    }
}

//
// Object literals
//
// In FuzzIL, object literals are represented as special blocks:
//
//      BeginObjectLiteral
//          ObjectLiteralAddProperty 'foo', v13
//          ObjectLiteralAddElement '0', v9
//          ObjectLiteralAddComputedProperty v3, v27
//          ObjectLiteralCopyProperties v42
//          BeginObjectLiteralMethod 'bar' -> v47, v48
//              // v47 is the |this| object
//              ...
//          EndObjectLiteralMethod
//          BeginObjectLiteralComputedMethod v19 -> v51, v52
//              // v51 is the |this| object
//              ...
//          EndObjectLiteralComputedMethod
//          BeginObjectLiteralGetter 'baz' -> v56
//              // v56 is the |this| object
//              ...
//          EndObjectLiteralGetter
//          BeginObjectLiteralSetter 'baz' -> v60, v61
//              // v60 is the |this| object, v61 the new value
//              ...
//          EndObjectLiteralSetter
//      v64 <- EndObjectLiteral
//
// Note, the output is defined by the EndObjectLiteral operation since the value itself is not available inside the object literal.
final class BeginObjectLiteral: JsOperation {
    override var opcode: Opcode { .beginObjectLiteral(self) }

    init() {
        super.init(attributes: .isBlockStart, contextOpened: .objectLiteral)
    }
}

// A "regular" property, for example `"a": 42`,
final class ObjectLiteralAddProperty: JsOperation {
    override var opcode: Opcode { .objectLiteralAddProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, attributes: .isMutable, requiredContext: .objectLiteral)
    }
}

// An element property, for example `0: v7,`
final class ObjectLiteralAddElement: JsOperation {
    override var opcode: Opcode { .objectLiteralAddElement(self) }

    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 1, attributes: .isMutable, requiredContext: .objectLiteral)
    }
}

// A computed property, for example `["prop" + v9]: "foobar",`
final class ObjectLiteralAddComputedProperty: JsOperation {
    override var opcode: Opcode { .objectLiteralAddComputedProperty(self) }

    init() {
        super.init(numInputs: 2, requiredContext: .objectLiteral)
    }
}


// A spread operation (e.g. `...v13,`) copying the properties from another object
final class ObjectLiteralCopyProperties: JsOperation {
    override var opcode: Opcode { .objectLiteralCopyProperties(self) }

    init() {
        super.init(numInputs: 1, requiredContext: .objectLiteral)
    }
}

// Set a custom prototype for this object, for example `"__proto__": Array.prototype`,
final class ObjectLiteralSetPrototype: JsOperation {
    override var opcode: Opcode { .objectLiteralSetPrototype(self) }

    init() {
        // Having duplicate __proto__ fields in an object literal leads to runtime exceptions.
        super.init(numInputs: 1, attributes: .isSingular, requiredContext: .objectLiteral)
    }
}

// A method, for example `someMethod(a3, a4) {`
final class BeginObjectLiteralMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginObjectLiteralMethod(self) }

    let methodName: String

    init(methodName: String, parameters: Parameters) {
        self.methodName = methodName
        // First inner output is the explicit |this| parameter
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: [.isBlockStart, .isMutable], requiredContext: .objectLiteral, contextOpened: [.javascript, .subroutine, .method])
    }
}

final class EndObjectLiteralMethod: EndAnySubroutine {
    override var opcode: Opcode { .endObjectLiteralMethod(self) }
}

// A computed method, for example `[Symbol.toPrimitive](a3, a4) {`
final class BeginObjectLiteralComputedMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginObjectLiteralComputedMethod(self) }

    init(parameters: Parameters) {
        // First inner output is the explicit |this| parameter
        super.init(parameters: parameters, numInputs: 1, numInnerOutputs: parameters.count + 1, attributes: .isBlockStart, requiredContext: .objectLiteral, contextOpened: [.javascript, .subroutine, .method])
    }
}

final class EndObjectLiteralComputedMethod: EndAnySubroutine {
    override var opcode: Opcode { .endObjectLiteralComputedMethod(self) }
}

// A getter, for example `get prop() {`
final class BeginObjectLiteralGetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginObjectLiteralGetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 0), numInnerOutputs: 1, attributes: [.isBlockStart, .isMutable], requiredContext: .objectLiteral, contextOpened: [.javascript, .subroutine, .method])
    }
}

final class EndObjectLiteralGetter: EndAnySubroutine {
    override var opcode: Opcode { .endObjectLiteralGetter(self) }
}

// A setter, for example `set prop(a5) {`
final class BeginObjectLiteralSetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginObjectLiteralSetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 1), numInnerOutputs: 2, attributes: [.isBlockStart, .isMutable], requiredContext: .objectLiteral, contextOpened: [.javascript, .subroutine, .method])
    }
}

final class EndObjectLiteralSetter: EndAnySubroutine {
    override var opcode: Opcode { .endObjectLiteralSetter(self) }
}

final class EndObjectLiteral: JsOperation {
    override var opcode: Opcode { .endObjectLiteral(self) }

    init() {
        super.init(numOutputs: 1, attributes: .isBlockEnd, requiredContext: .objectLiteral)
    }
}

//
// Classes
//
// Classes in FuzzIL look roughly as follows:
//
//     v0 <- BeginClassDefinition [optional superclass]
//         ClassAddInstanceProperty
//         ClassAddInstanceElement
//         ClassAddInstanceComputedProperty
//         BeginClassConstructor -> v1, v2
//             // v1 is the |this| object
//             ...
//         EndClassConstructor
//         BeginClassInstanceMethod -> v6, v7, v8
//             // v6 is the |this| object
//             ...
//         EndClassInstanceMethod
//
//         BeginClassInstanceGetter -> v12
//             // v12 is the |this| object
//             ...
//         EndClassInstanceGetter
//         BeginClassInstanceSetter -> v18, v19
//             // v18 is |this|, v19 the new value
//             ...
//         EndClassInstanceSetter
//
//         ClassAddStaticProperty
//         ClassAddStaticElement
//         ClassAddStaticComputedProperty
//         BeginClassStaticMethod -> v24, v25
//             // v24 is the |this| object
//             ...
//         EndClassStaticMethod
//         BeginClassStaticInitializer
//         EndClassStaticInitializer
//
//         ClassAddPrivateInstanceProperty
//         BeginClassPrivateInstanceMethod -> v29
//             // v29 is the |this| object
//             ...
//         EndClassPrivateInstanceMethod
//         ClassAddPrivateStaticProperty
//         BeginClassPrivateStaticMethod -> v34, v35
//             // v34 is the |this| object
//             ...
//         EndClassPrivateStaticMethod
//     EndClassDefinition
//
final class BeginClassDefinition: JsOperation {
    override var opcode: Opcode { .beginClassDefinition(self) }

    let hasSuperclass: Bool

    init(hasSuperclass: Bool) {
        self.hasSuperclass = hasSuperclass
        super.init(numInputs: hasSuperclass ? 1 : 0, numOutputs: 1, attributes: .isBlockStart, contextOpened: .classDefinition)
    }
}

final class BeginClassConstructor: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassConstructor(self) }

    init(parameters: Parameters) {
        // First inner output is the explicit |this| parameter
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: [.isBlockStart, .isSingular], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassConstructor: EndAnySubroutine {
    override var opcode: Opcode { .endClassConstructor(self) }
}

final class ClassAddInstanceProperty: JsOperation {
    override var opcode: Opcode { .classAddInstanceProperty(self) }

    let propertyName: String
    var hasValue: Bool {
        return numInputs == 1
    }

    init(propertyName: String, hasValue: Bool) {
        self.propertyName = propertyName
        super.init(numInputs: hasValue ? 1 : 0, attributes: .isMutable, requiredContext: .classDefinition)
    }
}

final class ClassAddInstanceElement: JsOperation {
    override var opcode: Opcode { .classAddInstanceElement(self) }

    let index: Int64
    var hasValue: Bool {
        return numInputs == 1
    }

    init(index: Int64, hasValue: Bool) {
        self.index = index
        super.init(numInputs: hasValue ? 1 : 0, attributes: .isMutable, requiredContext: .classDefinition)
    }
}

final class ClassAddInstanceComputedProperty: JsOperation {
    override var opcode: Opcode { .classAddInstanceComputedProperty(self) }

    var hasValue: Bool {
        return numInputs == 2
    }

    init(hasValue: Bool) {
        super.init(numInputs: hasValue ? 2 : 1, requiredContext: .classDefinition)
    }
}

final class BeginClassInstanceMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassInstanceMethod(self) }

    let methodName: String

    init(methodName: String, parameters: Parameters) {
        self.methodName = methodName
        // First inner output is the explicit |this| parameter
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: [.isMutable, .isBlockStart], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassInstanceMethod: EndAnySubroutine {
    override var opcode: Opcode { .endClassInstanceMethod(self) }
}

final class BeginClassInstanceGetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassInstanceGetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 0), numInnerOutputs: 1, attributes: [.isBlockStart, .isMutable], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassInstanceGetter: EndAnySubroutine {
    override var opcode: Opcode { .endClassInstanceGetter(self) }
}

final class BeginClassInstanceSetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassInstanceSetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 1), numInnerOutputs: 2, attributes: [.isBlockStart, .isMutable], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassInstanceSetter: EndAnySubroutine {
    override var opcode: Opcode { .endClassInstanceSetter(self) }
}

final class ClassAddStaticProperty: JsOperation {
    override var opcode: Opcode { .classAddStaticProperty(self) }

    let propertyName: String
    var hasValue: Bool {
        return numInputs == 1
    }

    init(propertyName: String, hasValue: Bool) {
        self.propertyName = propertyName
        super.init(numInputs: hasValue ? 1 : 0, attributes: .isMutable, requiredContext: .classDefinition)
    }
}

final class ClassAddStaticElement: JsOperation {
    override var opcode: Opcode { .classAddStaticElement(self) }

    let index: Int64
    var hasValue: Bool {
        return numInputs == 1
    }

    init(index: Int64, hasValue: Bool) {
        self.index = index
        super.init(numInputs: hasValue ? 1 : 0, attributes: .isMutable, requiredContext: .classDefinition)
    }
}

final class ClassAddStaticComputedProperty: JsOperation {
    override var opcode: Opcode { .classAddStaticComputedProperty(self) }

    var hasValue: Bool {
        return numInputs == 2
    }

    init(hasValue: Bool) {
        super.init(numInputs: hasValue ? 2 : 1, requiredContext: .classDefinition)
    }
}

final class BeginClassStaticInitializer: JsOperation {
    override var opcode: Opcode { .beginClassStaticInitializer(self) }

    init() {
        // Inner output is the explicit |this| parameter
        // Static initializer blocks do not have .subroutine context as `return` is disallowed inside of them.
        super.init(numInnerOutputs: 1, attributes: .isBlockStart, requiredContext: .classDefinition, contextOpened: [.javascript, .method, .classMethod])
    }
}

final class EndClassStaticInitializer: JsOperation {
    override var opcode: Opcode { .endClassStaticInitializer(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

final class BeginClassStaticMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassStaticMethod(self) }

    let methodName: String

    init(methodName: String, parameters: Parameters) {
        self.methodName = methodName
        // First inner output is the explicit |this| parameter
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: [.isMutable, .isBlockStart], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassStaticMethod: EndAnySubroutine {
    override var opcode: Opcode { .endClassStaticMethod(self) }
}

final class BeginClassStaticGetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassStaticGetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 0), numInnerOutputs: 1, attributes: [.isBlockStart, .isMutable], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassStaticGetter: EndAnySubroutine {
    override var opcode: Opcode { .endClassStaticGetter(self) }
}

final class BeginClassStaticSetter: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassStaticSetter(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // First inner output is the explicit |this| parameter
        super.init(parameters: Parameters(count: 1), numInnerOutputs: 2, attributes: [.isBlockStart, .isMutable], requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassStaticSetter: EndAnySubroutine {
    override var opcode: Opcode { .endClassStaticSetter(self) }
}

final class ClassAddPrivateInstanceProperty: JsOperation {
    override var opcode: Opcode { .classAddPrivateInstanceProperty(self) }

    let propertyName: String
    var hasValue: Bool {
        return numInputs == 1
    }

    init(propertyName: String, hasValue: Bool) {
        self.propertyName = propertyName
        // We currently don't want to change the names of private properties since that has a good chance of making
        // following code _syntactically_ incorrect (if it uses them) because an undeclared private field is accessed.
        super.init(numInputs: hasValue ? 1 : 0, requiredContext: .classDefinition)
    }
}

final class BeginClassPrivateInstanceMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassPrivateInstanceMethod(self) }

    let methodName: String

    init(methodName: String, parameters: Parameters) {
        self.methodName = methodName
        // First inner output is the explicit |this| parameter.
        // See comment in ClassAddPrivateInstanceProperty for why this operation isn't mutable.
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: .isBlockStart, requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassPrivateInstanceMethod: EndAnySubroutine {
    override var opcode: Opcode { .endClassPrivateInstanceMethod(self) }
}

final class ClassAddPrivateStaticProperty: JsOperation {
    override var opcode: Opcode { .classAddPrivateStaticProperty(self) }

    let propertyName: String
    var hasValue: Bool {
        return numInputs == 1
    }

    init(propertyName: String, hasValue: Bool) {
        self.propertyName = propertyName
        // See comment in ClassAddPrivateInstanceProperty for why this operation isn't mutable.
        super.init(numInputs: hasValue ? 1 : 0, requiredContext: .classDefinition)
    }
}

final class BeginClassPrivateStaticMethod: BeginAnySubroutine {
    override var opcode: Opcode { .beginClassPrivateStaticMethod(self) }

    let methodName: String

    init(methodName: String, parameters: Parameters) {
        self.methodName = methodName
        // First inner output is the explicit |this| parameter.
        // See comment in ClassAddPrivateInstanceProperty for why this operation isn't mutable.
        super.init(parameters: parameters, numInnerOutputs: parameters.count + 1, attributes: .isBlockStart, requiredContext: .classDefinition, contextOpened: [.javascript, .subroutine, .method, .classMethod])
    }
}

final class EndClassPrivateStaticMethod: EndAnySubroutine {
    override var opcode: Opcode { .endClassPrivateStaticMethod(self) }
}

final class EndClassDefinition: JsOperation {
    override var opcode: Opcode { .endClassDefinition(self) }

    init() {
        super.init(attributes: .isBlockEnd, requiredContext: .classDefinition)
    }
}

final class CreateArray: JsOperation {
    override var opcode: Opcode { .createArray(self) }

    var numInitialValues: Int {
        return numInputs
    }

    init(numInitialValues: Int) {
        super.init(numInputs: numInitialValues, numOutputs: 1, firstVariadicInput: 0, attributes: [.isVariadic])
    }
}

final class CreateIntArray: JsOperation {
    override var opcode: Opcode { .createIntArray(self) }

    let values: [Int64]

    init(values: [Int64]) {
        self.values = values
        super.init(numOutputs: 1, attributes: .isMutable)
    }
}

final class CreateFloatArray: JsOperation {
    override var opcode: Opcode { .createFloatArray(self) }

    let values: [Double]

    init(values: [Double]) {
        self.values = values
        super.init(numOutputs: 1, attributes: .isMutable)
    }
}

final class CreateArrayWithSpread: JsOperation {
    override var opcode: Opcode { .createArrayWithSpread(self) }

    // Which inputs to spread.
    let spreads: [Bool]

    init(spreads: [Bool]) {
        self.spreads = spreads
        var flags: Operation.Attributes = [.isVariadic]
        if spreads.count > 0 {
            flags.insert(.isMutable)
        }
        super.init(numInputs: spreads.count, numOutputs: 1, firstVariadicInput: 0, attributes: flags)
    }
}

final class CreateTemplateString: JsOperation {
    override var opcode: Opcode { .createTemplateString(self) }

    // Stores the string elements of the template literal
    let parts: [String]

    var numInterpolatedValues: Int {
        return numInputs
    }

    init(parts: [String]) {
        assert(parts.count > 0)
        self.parts = parts
        super.init(numInputs: parts.count - 1, numOutputs: 1, firstVariadicInput: 0, attributes: [.isMutable, .isVariadic])
    }
}

final class GetProperty: GuardableOperation {
    override var opcode: Opcode { .getProperty(self) }

    let propertyName: String

    init(propertyName: String, isGuarded: Bool) {
        self.propertyName = propertyName
        super.init(isGuarded: isGuarded, numInputs: 1, numOutputs: 1, attributes: .isMutable)
    }
}

final class SetProperty: JsOperation {
    override var opcode: Opcode { .setProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 2, attributes: .isMutable)
    }
}

final class UpdateProperty: JsOperation {
    override var opcode: Opcode { .updateProperty(self) }

    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 2, attributes: .isMutable)
    }
}

final class DeleteProperty: GuardableOperation {
    override var opcode: Opcode { .deleteProperty(self) }

    let propertyName: String

    init(propertyName: String, isGuarded: Bool) {
        self.propertyName = propertyName
        super.init(isGuarded: isGuarded, numInputs: 1, numOutputs: 1, attributes: .isMutable)
    }
}

public struct PropertyFlags: OptionSet {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let writable         = PropertyFlags(rawValue: 1 << 0)
    static let configurable     = PropertyFlags(rawValue: 1 << 1)
    static let enumerable       = PropertyFlags(rawValue: 1 << 2)

    public static func random() -> PropertyFlags {
        return PropertyFlags(rawValue: UInt8.random(in: 0..<8))
    }
}

enum PropertyType: CaseIterable {
    case value
    case getter
    case setter
    case getterSetter
}

final class ConfigureProperty: JsOperation {
    override var opcode: Opcode { .configureProperty(self) }

    let propertyName: String
    let flags: PropertyFlags
    let type: PropertyType

    init(propertyName: String, flags: PropertyFlags, type: PropertyType) {
        self.propertyName = propertyName
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 3 : 2, attributes: .isMutable)
    }
}

final class GetElement: GuardableOperation {
    override var opcode: Opcode { .getElement(self) }

    let index: Int64

    init(index: Int64, isGuarded: Bool) {
        self.index = index
        super.init(isGuarded: isGuarded, numInputs: 1, numOutputs: 1, attributes: .isMutable)
    }
}

final class SetElement: JsOperation {
    override var opcode: Opcode { .setElement(self) }

    let index: Int64

    init(index: Int64) {
        self.index = index
        super.init(numInputs: 2, attributes: .isMutable)
    }
}

final class UpdateElement: JsOperation {
    override var opcode: Opcode { .updateElement(self) }

    let index: Int64
    let op: BinaryOperator

    init(index: Int64, operator op: BinaryOperator) {
        self.index = index
        self.op = op
        super.init(numInputs: 2, attributes: .isMutable)
    }
}

final class DeleteElement: GuardableOperation {
    override var opcode: Opcode { .deleteElement(self) }

    let index: Int64

    init(index: Int64, isGuarded: Bool) {
        self.index = index
        super.init(isGuarded: isGuarded, numInputs: 1, numOutputs: 1, attributes: .isMutable)
    }
}

final class ConfigureElement: JsOperation {
    override var opcode: Opcode { .configureElement(self) }

    let index: Int64
    let flags: PropertyFlags
    let type: PropertyType

    init(index: Int64, flags: PropertyFlags, type: PropertyType) {
        self.index = index
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 3 : 2, attributes: .isMutable)
    }
}

final class GetComputedProperty: GuardableOperation {
    override var opcode: Opcode { .getComputedProperty(self) }

    init(isGuarded: Bool) {
        super.init(isGuarded: isGuarded, numInputs: 2, numOutputs: 1)
    }
}

final class SetComputedProperty: JsOperation {
    override var opcode: Opcode { .setComputedProperty(self) }

    init() {
        super.init(numInputs: 3, numOutputs: 0)
    }
}

final class UpdateComputedProperty: JsOperation {
    override var opcode: Opcode { .updateComputedProperty(self) }

    let op: BinaryOperator

    init(operator op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 3, numOutputs: 0)
    }
}

final class DeleteComputedProperty: GuardableOperation {
    override var opcode: Opcode { .deleteComputedProperty(self) }

    init(isGuarded: Bool) {
        super.init(isGuarded: isGuarded, numInputs: 2, numOutputs: 1)
    }
}

final class ConfigureComputedProperty: JsOperation {
    override var opcode: Opcode { .configureComputedProperty(self) }

    let flags: PropertyFlags
    let type: PropertyType

    init(flags: PropertyFlags, type: PropertyType) {
        self.flags = flags
        self.type = type
        super.init(numInputs: type == .getterSetter ? 4 : 3, attributes: .isMutable)
    }
}

final class TypeOf: JsOperation {
    override var opcode: Opcode { .typeOf(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

final class Void_: JsOperation {
    override var opcode: Opcode { .void(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

final class TestInstanceOf: JsOperation {
    override var opcode: Opcode { .testInstanceOf(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }
}

final class TestIn: JsOperation {
    override var opcode: Opcode { .testIn(self) }

    init() {
        super.init(numInputs: 2, numOutputs: 1)
    }

}

// The parameters of a FuzzIL subroutine.
public struct Parameters {
    /// The total number of parameters.
    private let numParameters: UInt32
    /// Whether the last parameter is a rest parameter.
    let hasRestParameter: Bool

    /// The total number of parameters. This is equivalent to the number of inner outputs produced from the parameters.
    var count: Int {
        return Int(numParameters)
    }

    init(count: Int, hasRestParameter: Bool = false) {
        self.numParameters = UInt32(count)
        self.hasRestParameter = hasRestParameter
    }
}

// Subroutine definitions.
// A subroutine is the umbrella term for any invocable unit of code. Functions, (class) constructors, and methods are all subroutines.
// This intermediate Operation class contains the parameters of the surbroutine and makes it easy to identify whenever .subroutine context is opened.
class BeginAnySubroutine: JsOperation {
    let parameters: Parameters

    init(parameters: Parameters, numInputs: Int = 0, numOutputs: Int = 0, numInnerOutputs: Int = 0, attributes: Operation.Attributes = .isBlockStart, requiredContext: Context = .javascript, contextOpened: Context) {
        assert(contextOpened.contains(.subroutine))
        assert(attributes.contains(.isBlockStart))
        self.parameters = parameters
        super.init(numInputs: numInputs, numOutputs: numOutputs, numInnerOutputs: numInnerOutputs, attributes: attributes, requiredContext: requiredContext, contextOpened: contextOpened)
    }
}

class EndAnySubroutine: JsOperation {
    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

// Function definitions.
// Roughly speaking, a function is any subroutine that is supposed to be invoked via CallFunction. In JavaScript, they are typically defined through the 'function' keyword or an arrow function.
// Functions beginnings are not considered mutable since it likely makes little sense to change things like the number of parameters.
class BeginAnyFunction: BeginAnySubroutine {
    init(parameters: Parameters, contextOpened: Context = [.javascript, .subroutine]) {
        super.init(parameters: parameters,
                   numInputs: 0,
                   numOutputs: 1,
                   numInnerOutputs: parameters.count,
                   contextOpened: contextOpened)
    }
}
class EndAnyFunction: EndAnySubroutine {}

// Functions that can (optionally) be given a name.
class BeginAnyNamedFunction: BeginAnyFunction {
    // If the function has no name (the name is nil), then a  name is automatically assigned
    // during lifting. Typically it will be something like `f3`, and the lifter guarantees
    // that there are no name collisions with other functions.
    // If a name is present, the lifter will use that for the function. In that case, the
    // lifter cannot guarantee that there are no name collisions with other named functions.
    let functionName: String?

    init(parameters: Parameters, functionName: String?, contextOpened: Context = [.javascript, .subroutine]) {
        assert(functionName == nil || !functionName!.isEmpty)
        self.functionName = functionName
        super.init(parameters: parameters, contextOpened: contextOpened)
    }
}

// A plain function
final class BeginPlainFunction: BeginAnyNamedFunction {
    override var opcode: Opcode { .beginPlainFunction(self) }
}
final class EndPlainFunction: EndAnyFunction {
    override var opcode: Opcode { .endPlainFunction(self) }
}

// A ES6 arrow function
final class BeginArrowFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginArrowFunction(self) }
}
final class EndArrowFunction: EndAnyFunction {
    override var opcode: Opcode { .endArrowFunction(self) }
}

// A ES6 generator function
final class BeginGeneratorFunction: BeginAnyNamedFunction {
    override var opcode: Opcode { .beginGeneratorFunction(self) }

    init(parameters: Parameters, functionName: String?) {
        super.init(parameters: parameters, functionName: functionName, contextOpened: [.javascript, .subroutine, .generatorFunction])
    }
}
final class EndGeneratorFunction: EndAnyFunction {
    override var opcode: Opcode { .endGeneratorFunction(self) }
}

// A ES6 async function
final class BeginAsyncFunction: BeginAnyNamedFunction {
    override var opcode: Opcode { .beginAsyncFunction(self) }

    init(parameters: Parameters, functionName: String?) {
        super.init(parameters: parameters, functionName: functionName, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
final class EndAsyncFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncFunction(self) }
}

// A ES6 async arrow function
final class BeginAsyncArrowFunction: BeginAnyFunction {
    override var opcode: Opcode { .beginAsyncArrowFunction(self) }

    init(parameters: Parameters) {
        super.init(parameters: parameters, contextOpened: [.javascript, .subroutine, .asyncFunction])
    }
}
final class EndAsyncArrowFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncArrowFunction(self) }
}

// A ES6 async generator function
final class BeginAsyncGeneratorFunction: BeginAnyNamedFunction {
    override var opcode: Opcode { .beginAsyncGeneratorFunction(self) }

    init(parameters: Parameters, functionName: String?) {
        super.init(parameters: parameters, functionName: functionName, contextOpened: [.javascript, .subroutine, .asyncFunction, .generatorFunction])
    }
}
final class EndAsyncGeneratorFunction: EndAnyFunction {
    override var opcode: Opcode { .endAsyncGeneratorFunction(self) }
}

// A constructor.
// This will also be lifted to a plain function in JavaScript. However, in FuzzIL it has an explicit |this| parameter as first inner output.
// A constructor is not a function since it is supposed to be constructed, not called.
final class BeginConstructor: BeginAnySubroutine {
    override var opcode: Opcode { .beginConstructor(self) }

    init(parameters: Parameters) {
        super.init(parameters: parameters, numOutputs: 1, numInnerOutputs: parameters.count + 1, contextOpened: [.javascript, .subroutine])
    }
}
final class EndConstructor: EndAnySubroutine {
    override var opcode: Opcode { .endConstructor(self) }
}

// A directive for the JavaScript engine.
//
// These are strings such as "use strict" that have special meaning
// if placed at the top of a function. Support in FuzzIL is very basic
// and simple: a directive is simply a string for which a string literal
// will be created in the generated JavaScript code. There is also no
// guarantee that these will be placed at the start of a function's body,
// and due to mutations they might appear elsewhere in a program (which
// is probably a feature). They will also quickly be removed by the
// minimizer if they are not important (which is probably also desirable
// as strict mode function are more likely to raise exceptions).
final class Directive: JsOperation {
    override var opcode: Opcode { .directive(self) }

    let content: String

    init(_ content: String) {
        // Currently we only support "use strict" and don't support mutating the content.
        // We could easily change both of these constraints and allow arbitrary directives
        // or a list of known directives if we deem that useful in the future though.
        assert(content == "use strict")
        self.content = content
        super.init(numInputs: 0, numOutputs: 0, attributes: [], requiredContext: [.javascript])
    }
}

final class Return: JsOperation {
    override var opcode: Opcode { .return(self) }

    var hasReturnValue: Bool {
        assert(numInputs == 0 || numInputs == 1)
        return numInputs == 1
    }

    init(hasReturnValue: Bool) {
        super.init(numInputs: hasReturnValue ? 1 : 0, attributes: [.isJump], requiredContext: [.javascript, .subroutine])
    }
}

// A yield expression in JavaScript
final class Yield: JsOperation {
    override var opcode: Opcode { .yield(self) }

    var hasArgument: Bool {
        assert(numInputs == 0 || numInputs == 1)
        return numInputs == 1
    }

    init(hasArgument: Bool) {
        super.init(numInputs: hasArgument ? 1 : 0, numOutputs: 1, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

// A yield* expression in JavaScript
final class YieldEach: JsOperation {
    override var opcode: Opcode { .yieldEach(self) }

    init() {
        super.init(numInputs: 1, attributes: [], requiredContext: [.javascript, .generatorFunction])
    }
}

final class Await: JsOperation {
    override var opcode: Opcode { .await(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, attributes: [], requiredContext: [.javascript, .asyncFunction])
    }
}

final class CallFunction: GuardableOperation {
    override var opcode: Opcode { .callFunction(self) }

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, isGuarded: Bool) {
        // The called function is the first input.
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

final class CallFunctionWithSpread: GuardableOperation {
    override var opcode: Opcode { .callFunctionWithSpread(self) }

    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, spreads: [Bool], isGuarded: Bool) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The called function is the first input.
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall, .isMutable])
    }
}

final class Construct: GuardableOperation {
    override var opcode: Opcode { .construct(self) }

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, isGuarded: Bool) {
        // The constructor is the first input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall])
    }
}

final class ConstructWithSpread: GuardableOperation {
    override var opcode: Opcode { .constructWithSpread(self) }

    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(numArguments: Int, spreads: [Bool], isGuarded: Bool) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The constructor is the first input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall, .isMutable])
    }
}

final class CallMethod: GuardableOperation {
    override var opcode: Opcode { .callMethod(self) }

    let methodName: String

    var numArguments: Int {
        return numInputs - 1
    }

    init(methodName: String, numArguments: Int, isGuarded: Bool) {
        self.methodName = methodName
        // The reference object is the first input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isMutable, .isVariadic, .isCall])
    }
}

final class CallMethodWithSpread: GuardableOperation {
    override var opcode: Opcode { .callMethodWithSpread(self) }

    let methodName: String
    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 1
    }

    init(methodName: String, numArguments: Int, spreads: [Bool], isGuarded: Bool) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.methodName = methodName
        self.spreads = spreads
        // The reference object is the first input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isMutable, .isVariadic, .isCall])
    }
}

final class CallComputedMethod: GuardableOperation {
    override var opcode: Opcode { .callComputedMethod(self) }

    var numArguments: Int {
        return numInputs - 2
    }

    init(numArguments: Int, isGuarded: Bool) {
        // The reference object is the first input and the method name is the second input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 2, numOutputs: 1, firstVariadicInput: 2, attributes: [.isVariadic, .isCall])
    }
}

final class CallComputedMethodWithSpread: GuardableOperation {
    override var opcode: Opcode { .callComputedMethodWithSpread(self) }

    let spreads: [Bool]

    var numArguments: Int {
        return numInputs - 2
    }

    init(numArguments: Int, spreads: [Bool], isGuarded: Bool) {
        assert(!spreads.isEmpty)
        assert(spreads.count == numArguments)
        self.spreads = spreads
        // The reference object is the first input and the method name is the second input
        super.init(isGuarded: isGuarded, numInputs: numArguments + 2, numOutputs: 1, firstVariadicInput: 2, attributes: [.isMutable, .isVariadic, .isCall])
    }
}

public enum UnaryOperator: String, CaseIterable {
    case PreInc     = "++"
    case PreDec     = "--"
    case PostInc    = "++ "     // Raw value must be unique
    case PostDec    = "-- "     // Raw value must be unique
    case LogicalNot = "!"
    case BitwiseNot = "~"
    case Plus       = "+"
    case Minus      = "-"

    var token: String {
        return self.rawValue.trimmingCharacters(in: [" "])
    }

    var reassignsInput: Bool {
        return self == .PreInc || self == .PreDec || self == .PostInc || self == .PostDec
    }

    var isPostfix: Bool {
        return self == .PostInc || self == .PostDec
    }
}

final class UnaryOperation: JsOperation {
    override var opcode: Opcode { .unaryOperation(self) }

    let op: UnaryOperator

    init(_ op: UnaryOperator) {
        self.op = op
        super.init(numInputs: 1, numOutputs: 1, attributes: .isMutable)
    }
}

public enum BinaryOperator: String, CaseIterable {
    case Add      = "+"
    case Sub      = "-"
    case Mul      = "*"
    case Div      = "/"
    case Mod      = "%"
    case BitAnd   = "&"
    case BitOr    = "|"
    case LogicAnd = "&&"
    case LogicOr  = "||"
    case Xor      = "^"
    case LShift   = "<<"
    case RShift   = ">>"
    case Exp      = "**"
    case UnRShift = ">>>"
    // Nullish coalescing operator (??)
    case NullCoalesce = "??"

    var token: String {
        return self.rawValue
    }
}

final class BinaryOperation: JsOperation {
    override var opcode: Opcode { .binaryOperation(self) }

    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2, numOutputs: 1, attributes: .isMutable)
    }
}

/// Ternary operator: a ? b : c.
final class TernaryOperation: JsOperation {
    override var opcode: Opcode { .ternaryOperation(self) }

    init() {
        super.init(numInputs: 3, numOutputs: 1)
    }
}

/// Reassigns an existing variable, essentially doing `input1 = input2;`
final class Reassign: JsOperation {
    override var opcode: Opcode { .reassign(self) }

    init() {
        super.init(numInputs: 2)
    }
}

/// Updates a variable by applying a binary operation to it and another variable.
final class Update: JsOperation {
    override var opcode: Opcode { .update(self) }

    let op: BinaryOperator

    init(_ op: BinaryOperator) {
        self.op = op
        super.init(numInputs: 2)
    }
}

/// Duplicates a variable, essentially doing `output = input;`
final class Dup: JsOperation {
    override var opcode: Opcode { .dup(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1)
    }
}

/// Destructs an array into n output variables.
final class DestructArray: JsOperation {
    override var opcode: Opcode { .destructArray(self) }

    let indices: [Int64]
    let lastIsRest: Bool

    init(indices: [Int64], lastIsRest: Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.lastIsRest = lastIsRest
        super.init(numInputs: 1, numOutputs: indices.count)
    }
}

/// Destructs an array and reassigns the output to n existing variables.
final class DestructArrayAndReassign: JsOperation {
    override var opcode: Opcode { .destructArrayAndReassign(self) }

    let indices: [Int64]
    let lastIsRest: Bool

    init(indices: [Int64], lastIsRest:Bool) {
        assert(indices == indices.sorted(), "Indices must be sorted in ascending order")
        assert(indices.count == Set(indices).count, "Indices must not have duplicates")
        self.indices = indices
        self.lastIsRest = lastIsRest
        // The first input is the array being destructed
        super.init(numInputs: 1 + indices.count, numOutputs: 0)
    }
}

/// Destructs an object into n output variables
final class DestructObject: JsOperation {
    override var opcode: Opcode { .destructObject(self) }

    let properties: [String]
    let hasRestElement: Bool

    init(properties: [String], hasRestElement: Bool) {
        assert(!properties.isEmpty || hasRestElement, "Must have at least one output")
        self.properties = properties
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numOutputs: properties.count + (hasRestElement ? 1 : 0))
    }
}

/// Destructs an object and reassigns the output to n existing variables
final class DestructObjectAndReassign: JsOperation {
    override var opcode: Opcode { .destructObjectAndReassign(self) }

    let properties: [String]
    let hasRestElement: Bool

    init(properties: [String], hasRestElement:Bool) {
        self.properties = properties
        self.hasRestElement = hasRestElement
        // The first input is the object being destructed
        super.init(numInputs: 1 + properties.count + (hasRestElement ? 1 : 0), numOutputs: 0)
    }
}

// This array must be kept in sync with the Comparator Enum in operations.proto
public enum Comparator: String, CaseIterable {
    case equal              = "=="
    case strictEqual        = "==="
    case notEqual           = "!="
    case strictNotEqual     = "!=="
    case lessThan           = "<"
    case lessThanOrEqual    = "<="
    case greaterThan        = ">"
    case greaterThanOrEqual = ">="

    var token: String {
        return self.rawValue
    }
}

final class Compare: JsOperation {
    override var opcode: Opcode { .compare(self) }

    let op: Comparator

    init(_ comparator: Comparator) {
        self.op = comparator
        super.init(numInputs: 2, numOutputs: 1, attributes: .isMutable)
    }
}

/// An operation that will be lifted to a given string. The string can use %@ placeholders which
/// will be replaced by the expressions for the input variables during lifting.
final class Eval: JsOperation {
    override var opcode: Opcode { .eval(self) }

    let code: String

    var hasOutput: Bool {
        assert(numOutputs == 0 || numOutputs == 1)
        return numOutputs == 1
    }

    init(_ string: String, numArguments: Int, hasOutput: Bool) {
        self.code = string
        super.init(numInputs: numArguments, numOutputs: hasOutput ? 1 : 0)
    }
}

final class BeginWith: JsOperation {
    override var opcode: Opcode { .beginWith(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .with])
    }
}

final class EndWith: JsOperation {
    override var opcode: Opcode { .endWith(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class CallSuperConstructor: JsOperation {
    override var opcode: Opcode { .callSuperConstructor(self) }

    var numArguments: Int {
        return numInputs
    }

    init(numArguments: Int) {
        super.init(numInputs: numArguments, firstVariadicInput: 0, attributes: [.isVariadic, .isCall], requiredContext: [.javascript, .method])
    }
}

final class CallSuperMethod: JsOperation {
    override var opcode: Opcode { .callSuperMethod(self) }

    let methodName: String

    var numArguments: Int {
        return numInputs
    }

    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        super.init(numInputs: numArguments, numOutputs: 1, firstVariadicInput: 0, attributes: [.isCall, .isMutable, .isVariadic], requiredContext: [.javascript, .method])
    }
}

final class GetPrivateProperty: JsOperation {
    override var opcode: Opcode { .getPrivateProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // Accessing a private property that isn't declared in the surrounding class definition is a syntax error
        // (and so cannot even be handled with a try-catch). Since mutating private property names would often
        // result in an access to such an undefined private property, and therefore a syntax error, we do not mutate them.
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.javascript, .classMethod])
    }
}

final class SetPrivateProperty: JsOperation {
    override var opcode: Opcode { .setPrivateProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        // See comment in GetPrivateProperty for why these aren't mutable.
        super.init(numInputs: 2, requiredContext: [.javascript, .classMethod])
    }
}

final class UpdatePrivateProperty: JsOperation {
    override var opcode: Opcode { .updatePrivateProperty(self) }

    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        // See comment in GetPrivateProperty for why these aren't mutable.
        super.init(numInputs: 2, requiredContext: [.javascript, .classMethod])
    }
}

final class CallPrivateMethod: JsOperation {
    override var opcode: Opcode { .callPrivateMethod(self) }

    let methodName: String

    var numArguments: Int {
        return numInputs - 1
    }

    init(methodName: String, numArguments: Int) {
        self.methodName = methodName
        // The reference object is the first input.
        // See comment in GetPrivateProperty for why these aren't mutable.
        super.init(numInputs: numArguments + 1, numOutputs: 1, firstVariadicInput: 1, attributes: [.isVariadic, .isCall], requiredContext: [.javascript, .classMethod])
    }
}

final class GetSuperProperty: JsOperation {
    override var opcode: Opcode { .getSuperProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numOutputs: 1, attributes: .isMutable, requiredContext: [.javascript, .method])
    }
}

final class SetSuperProperty: JsOperation {
    override var opcode: Opcode { .setSuperProperty(self) }

    let propertyName: String

    init(propertyName: String) {
        self.propertyName = propertyName
        super.init(numInputs: 1, attributes: .isMutable, requiredContext: [.javascript, .method])
    }
}

final class SetComputedSuperProperty: JsOperation {
    override var opcode: Opcode { .setComputedSuperProperty(self) }

    init() {
        super.init(numInputs: 2, requiredContext: [.javascript, .method])
    }
}

final class GetComputedSuperProperty: JsOperation {
    override var opcode: Opcode { .getComputedSuperProperty(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: [.javascript, .method])
    }
}


final class UpdateSuperProperty: JsOperation {
    override var opcode: Opcode { .updateSuperProperty(self) }

    let propertyName: String
    let op: BinaryOperator

    init(propertyName: String, operator op: BinaryOperator) {
        self.propertyName = propertyName
        self.op = op
        super.init(numInputs: 1, attributes: .isMutable, requiredContext: [.javascript, .method])
    }
}

final class BeginIf: JsOperation {
    override var opcode: Opcode { .beginIf(self) }

    // If true, the condition for this if block will be negated.
    let inverted: Bool

    init(inverted: Bool) {
        self.inverted = inverted
        super.init(numInputs: 1, attributes: [.isBlockStart, .isMutable, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class BeginElse: JsOperation {
    override var opcode: Opcode { .beginElse(self) }

    init() {
        super.init(attributes: [.isBlockEnd, .isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class EndIf: JsOperation {
    override var opcode: Opcode { .endIf(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

///
/// Loops.
///
/// Loops in FuzzIL generally have the following format:
///
///     BeginLoopHeader
///        v7 <- Compare v1, v2, '<'
///     BeginLoopBody <- v7
///        ...
///     EndLoop
///
/// Which would be lifted to something like
///
///     loop(v1 < v2) {
///       // body
///     }
///
/// As such, it is possible to perform arbitrary computations in the loop header, as it is in JavaScript.
/// JavaScript only allows a single expression inside a loop header. However, this is purely a syntactical
/// restriction, and can be overcome for example by declaring and invoking an arrow function in the
/// header if necessary:
///
///     BeginLoopHeader
///         foo
///     BeginLoopBody
///         ...
///     EndLoopBody
///
/// Can be lifted to
///
///     loop((() => { foo })()) {
///         // body
///     }
///
/// For simpler cases that only involve expressions, the header can also be lifted to
///
///     loop(foo(), bar(), baz()) {
///         // body
///     }
///

final class BeginWhileLoopHeader: JsOperation {
    override var opcode: Opcode { .beginWhileLoopHeader(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

// The input is the loop condition. This also prevents empty loop headers which are forbidden by the language.
final class BeginWhileLoopBody: JsOperation {
    override var opcode: Opcode { .beginWhileLoopBody(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class EndWhileLoop: JsOperation {
    override var opcode: Opcode { .endWhileLoop(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

final class BeginDoWhileLoopBody: JsOperation {
    override var opcode: Opcode { .beginDoWhileLoopBody(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class BeginDoWhileLoopHeader: JsOperation {
    override var opcode: Opcode { .beginDoWhileLoopHeader(self) }

    init() {
        super.init(attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

// The input is the loop condition. This also prevents empty loop headers which are forbidden by the language.
final class EndDoWhileLoop: JsOperation {
    override var opcode: Opcode { .endDoWhileLoop(self) }

    init() {
        super.init(numInputs: 1, attributes: .isBlockEnd)
    }
}

///
/// For loops.
///
/// For loops have the following shape:
///
///     BeginForLoopInitializer
///         // ...
///         // v0 = initial value of the (single) loop variable
///     BeginForLoopCondition v0 -> v1
///         // v1 = current value of the (single) loop variable
///         // ...
///     BeginForLoopAfterthought -> v2
///         // v2 = current value of the (single) loop variable
///         // ...
///     BeginForLoopBody -> v3
///         // v3 = current value of the (single) loop variable
///         // ...
///     EndForLoop
///
/// This would be lifted to:
///
///     for (let vX = init; cond; afterthought) {
///         body
///     }
///
/// This format allows arbitrary computations to be performed in every part of the loop header. It also
/// allows zero, one, or multiple loop variables to be declared, which correspond to the inner outputs
/// of the blocks. During lifting, all the inner outputs are expected to lift to the same identifier (vX in
/// the example above).
/// Similar to while- and do-while loops, the code in the header blocks may be lifted to arrow functions
/// if it requires more than one expression.
///
final class BeginForLoopInitializer: JsOperation {
    override var opcode: Opcode { .beginForLoopInitializer(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class BeginForLoopCondition: JsOperation {
    override var opcode: Opcode { .beginForLoopCondition(self) }

    var numLoopVariables: Int {
        return numInnerOutputs
    }

    init(numLoopVariables: Int) {
        super.init(numInputs: numLoopVariables, numInnerOutputs: numLoopVariables, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class BeginForLoopAfterthought: JsOperation {
    override var opcode: Opcode { .beginForLoopAfterthought(self) }

    var numLoopVariables: Int {
        return numInnerOutputs
    }

    init(numLoopVariables: Int) {
        super.init(numInputs: 1, numInnerOutputs: numLoopVariables, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class BeginForLoopBody: JsOperation {
    override var opcode: Opcode { .beginForLoopBody(self) }

    var numLoopVariables: Int {
        return numInnerOutputs
    }

    init(numLoopVariables: Int) {
        super.init(numInnerOutputs: numLoopVariables, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class EndForLoop: JsOperation {
    override var opcode: Opcode { .endForLoop(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

final class BeginForInLoop: JsOperation {
    override var opcode: Opcode { .beginForInLoop(self) }

    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class EndForInLoop: JsOperation {
    override var opcode: Opcode { .endForInLoop(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

final class BeginForOfLoop: JsOperation {
    override var opcode: Opcode { .beginForOfLoop(self) }

    init() {
        super.init(numInputs: 1, numInnerOutputs: 1, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class BeginForOfLoopWithDestruct: JsOperation {
    override var opcode: Opcode { .beginForOfLoopWithDestruct(self) }

    let indices: [Int64]
    let hasRestElement: Bool

    init(indices: [Int64], hasRestElement: Bool) {
        assert(indices.count >= 1)
        self.indices = indices
        self.hasRestElement = hasRestElement
        super.init(numInputs: 1, numInnerOutputs: indices.count, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class EndForOfLoop: JsOperation {
    override var opcode: Opcode { .endForOfLoop(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

// A loop that simply runs N times and is therefore always guaranteed to terminate.
// Useful for example to force JIT compilation without creating more complex loops, which can often quickly end up turning into infinite loops due to mutations.
// These could be lifted simply as `for (let i = 0; i < N; i++) { body() }`
final class BeginRepeatLoop: JsOperation {
    override var opcode: Opcode { .beginRepeatLoop(self) }

    let iterations: Int

    // Whether the current iteration number is exposed as an inner output variable.
    var exposesLoopCounter: Bool {
        assert(numInnerOutputs == 0 || numInnerOutputs == 1)
        return numInnerOutputs == 1
    }

    init(iterations: Int, exposesLoopCounter: Bool = true) {
        self.iterations = iterations
        super.init(numInnerOutputs: exposesLoopCounter ? 1 : 0, attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: [.javascript, .loop])
    }
}

final class EndRepeatLoop: JsOperation {
    override var opcode: Opcode { .endRepeatLoop(self) }

    init() {
        super.init(attributes: .isBlockEnd)
    }
}

final class LoopBreak: JsOperation {
    override var opcode: Opcode { .loopBreak(self) }

    init() {
        super.init(attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

final class LoopContinue: JsOperation {
    override var opcode: Opcode { .loopContinue(self) }

    init() {
        super.init(attributes: [.isJump], requiredContext: [.javascript, .loop])
    }
}

final class BeginTry: JsOperation {
    override var opcode: Opcode { .beginTry(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext])
    }
}

final class BeginCatch: JsOperation {
    override var opcode: Opcode { .beginCatch(self) }

    init() {
        super.init(numInnerOutputs: 1, attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext])
    }
}

final class BeginFinally: JsOperation {
    override var opcode: Opcode { .beginFinally(self) }

    init() {
        super.init(attributes: [.isBlockStart, .isBlockEnd, .propagatesSurroundingContext])
    }
}

final class EndTryCatchFinally: JsOperation {
    override var opcode: Opcode { .endTryCatchFinally(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

final class ThrowException: JsOperation {
    override var opcode: Opcode { .throwException(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isJump])
    }
}

/// Generates a block of instructions, which is lifted to a string literal, that is a suitable as an argument to eval()
final class BeginCodeString: JsOperation {
    override var opcode: Opcode { .beginCodeString(self) }

    init() {
        super.init(numOutputs: 1, attributes: [.isBlockStart], contextOpened: .javascript)
    }
}

final class EndCodeString: JsOperation {
    override var opcode: Opcode { .endCodeString(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

/// Generates a block of instructions, which is lifted to a block statement.
final class BeginBlockStatement: JsOperation {
    override var opcode: Opcode { .beginBlockStatement(self) }

    init() {
        super.init(attributes: [.isBlockStart, .propagatesSurroundingContext], contextOpened: .javascript)
    }
}

final class EndBlockStatement: JsOperation {
    override var opcode: Opcode { .endBlockStatement(self) }

    init() {
        super.init(attributes: [.isBlockEnd])
    }
}

///
/// Switch-Cases
///
/// (1) Represent switch-case as a single block group, started by a BeginSwitch
///     and with each case started by a BeginSwitchCase:
///
///         BeginSwitch
///             // instructions of the first case
///         BeginSwitchCase
///             // instructions of the second case
///         BeginSwitchCase
///             // instructions of the third case
///         BeginSwitchDefaultCase
///             // instructions of the default case
///         ...
///         EndSwitch
///
///     The main issue with this design is that it makes it hard to add new
///     cases through splicing or code generation add new BeginSwitchCase
///     instructions into this program as this would 'cut' an existing
///     BeginSwitchCase sub-block into two halves, producing invalid code. Due
///     to that limitation, the minimizer is then also unable to minize these
///     BeginSwitchCase blocks as this would violate the "any feature removed
///     by the minimizer can be added back by a mutator" invariant. The result
///     is static switch blocks that are never mutated and often nedlessly keep
///     many other variables alive.
///
/// (2) Represent switch-case as a switch block with sub-blocks for the cases:
///
///         BeginSwitch
///             BeginSwitchCase
///                // instructions of the first case
///             EndSwitchCase
///             BeginSwitchCase
///                // instructions of the second case
///             EndSwitchCase
///             BeginSwitchCase
///                 // instructions of the third case
///             EndSwitchCase
///             BeginSwitchDefaultCase
///                 // instructions of the default case
///             EndSwitchCase
///             ...
///         EndSwitch
///
///     Inside the BeginSwitch, there is a .switchBlock but no .script context
///     and so only BeginSwitchCase and EndSwitchCase can be placed there. This
///     then trivially allows adding new cases from code generation or splicing,
///     in turn allowing proper minimization of switch-case blocks.
///
final class BeginSwitch: JsOperation {
    override var opcode: Opcode { .beginSwitch(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart], contextOpened: [.switchBlock])
    }
}

final class BeginSwitchCase: JsOperation {
    override var opcode: Opcode { .beginSwitchCase(self) }

    init() {
        super.init(numInputs: 1, attributes: [.isBlockStart, .resumesSurroundingContext], requiredContext: .switchBlock, contextOpened: [.switchCase, .javascript])
    }
}

/// This is the default case, it has no inputs, this is always in a BeginSwitch/EndSwitch block group.
/// We currently do not minimize this away. It is expected for other minimizers to reduce the contents of this block,
/// such that, if necessary, the BeginSwitch/EndSwitch reducer can remove the whole switch case altogether.
final class BeginSwitchDefaultCase: JsOperation {
    override var opcode: Opcode { .beginSwitchDefaultCase(self) }

    init() {
        super.init(attributes: [.isBlockStart, .resumesSurroundingContext, .isSingular], requiredContext: .switchBlock, contextOpened: [.switchCase, .javascript])
    }
}

/// This ends BeginSwitchCase and BeginDefaultSwitchCase blocks.
final class EndSwitchCase: JsOperation {
    override var opcode: Opcode { .endSwitchCase(self) }

    /// If true, causes this case to fall through (and so no "break;" is emitted by the Lifter)
    let fallsThrough: Bool

    init(fallsThrough: Bool) {
        self.fallsThrough = fallsThrough
        super.init(attributes: .isBlockEnd)
    }
}

final class EndSwitch: JsOperation {
    override var opcode: Opcode { .endSwitch(self) }

    init() {
        super.init(attributes: .isBlockEnd, requiredContext: .switchBlock)
    }
}

final class SwitchBreak: JsOperation {
    override var opcode: Opcode { .switchBreak(self) }

    init() {
        super.init(attributes: .isJump, requiredContext: [.javascript, .switchCase])
    }
}

final class LoadNewTarget: JsOperation {
    override var opcode: Opcode { .loadNewTarget(self) }

    init() {
        super.init(numOutputs: 1, requiredContext: .subroutine)
    }
}

final class BeginWasmModule: JsOperation {
    override var opcode: Opcode { .beginWasmModule(self) }
    init() {
        super.init(numOutputs: 0, attributes: [.isBlockStart], requiredContext: [.javascript], contextOpened: [.wasm])
    }
}

// The output of this instruction will be the compiled wasm module, i.e. the `instance` field will have the methods.
class EndWasmModule: JsOperation {
    override var opcode: Opcode { .endWasmModule(self) }
    init() {
        super.init(numOutputs: 1, attributes: [.isBlockEnd], requiredContext: [.wasm])
    }
}

class WrapPromising: JsOperation {
    override var opcode: Opcode { .wrapPromising(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: .javascript)
    }
}

class WrapSuspending: JsOperation {
    override var opcode: Opcode { .wrapSuspending(self) }

    init() {
        super.init(numInputs: 1, numOutputs: 1, requiredContext: .javascript)
    }
}

// This is used to bind methods for use as utility functions.
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Function/bind#transforming_methods_to_utility_functions
// This allows us to call these things from Wasm and V8 has optimizations to help with well-known imports.
class BindMethod: JsOperation {
    override var opcode: Opcode { .bindMethod(self) }

    let methodName: String

    init(methodName: String) {
        self.methodName = methodName
        // TODO(cffsmith): We probably want to expand this in the future to also bind arguments at some point.
        super.init(numInputs: 1, numOutputs: 1, requiredContext: .javascript)
    }
}


// This instruction is used to create strongly typed WasmGlobals in the JS world that can be imported by a WasmModule.
class CreateWasmGlobal: JsOperation {
    override var opcode: Opcode { .createWasmGlobal(self) }

    let value: WasmGlobal
    let isMutable: Bool

    init(value: WasmGlobal, isMutable: Bool) {
        self.value = value
        self.isMutable = isMutable
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript])
    }
}

// This instruction is used to create strongly typed WasmMemories in the JS world that can be imported by a WasmModule.
class CreateWasmMemory: JsOperation {
   override var opcode: Opcode { .createWasmMemory(self) }

   let memType: WasmMemoryType

   init(limits: Limits, isShared: Bool = false, isMemory64: Bool = false) {
       self.memType = WasmMemoryType(limits: limits, isShared: isShared, isMemory64: isMemory64)
       super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript])
   }
}

// This instruction is used to create strongly typed WasmTables in the JS world that can be imported by a WasmModule.
class CreateWasmTable: JsOperation {
    override var opcode: Opcode { .createWasmTable(self) }

    // We need to store the element type here such that the lifter can easily list the correct type 'externref' or 'anyfunc' when constructing.
    let tableType: WasmTableType

    init(elementType: ILType, limits: Limits) {
        self.tableType = WasmTableType(elementType: elementType, limits: limits)
        super.init(numOutputs: 1, attributes: [.isMutable], requiredContext: [.javascript])
    }
}

class CreateWasmJSTag: JsOperation {
    override var opcode: Opcode { .createWasmJSTag(self) }

    init() {
        super.init(numOutputs: 1, requiredContext: [.javascript])
    }
}

class CreateWasmTag: JsOperation {
    override var opcode: Opcode { .createWasmTag(self) }
    public let parameters: ParameterList

    init(parameters: ParameterList) {
        self.parameters = parameters
        // Note that tags in wasm are nominal (differently to types) meaning that two tags with the same input are not
        // the same, therefore this operation is not considered to be .pure.
        super.init(numOutputs: 1, attributes: [], requiredContext: [.javascript])
    }
}

/// Internal operations.
///
/// These can be used for internal fuzzer operations but will not appear in the corpus.
class JsInternalOperation: JsOperation {
    init(numInputs: Int, numOutputs: Int = 0) {
        super.init(numInputs: numInputs, numOutputs: numOutputs, attributes: [.isInternal])
    }
}

/// Writes the argument to the output stream.
final class Print: JsInternalOperation {
    override var opcode: Opcode { .print(self) }

    init() {
        super.init(numInputs: 1)
    }
}

/// Explore the input variable at runtime to determine which actions can be performed on it.
/// Used by the ExplorationMutator.
final class Explore: JsInternalOperation {
    override var opcode: Opcode { .explore(self) }

    let id: String
    // This makes a single explore operation deterministic by seeding a JS RNG
    let rngSeed: UInt32

    init(id: String, numArguments: Int, rngSeed: UInt32) {
        // IDs should be valid JavaScript property names since they will typically be used in that way.
        assert(id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) && id.contains(where: { $0.isLetter }))

        self.id = id
        self.rngSeed = rngSeed
        super.init(numInputs: numArguments + 1)
    }
}

/// Turn the input value into a probe that records the actions performed on it.
/// Used by the ProbingMutator.
final class Probe: JsInternalOperation {
    override var opcode: Opcode { .probe(self) }

    let id: String

    init(id: String) {
        // IDs should be valid JavaScript property names since they will typically be used in that way.
        assert(id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) && id.contains(where: { $0.isLetter }))

        self.id = id
        super.init(numInputs: 1)
    }
}

/// Wraps an "action" (essentially another FuzzIL instruction) and, based on runtime information, attempts to make it "better".
/// For example, this may remove unneeded guards (i.e. try-catch), or change the property/method accessed on an object if the original property/method doesn't exist.
/// Used by the FixupMutator.
final class Fixup: JsInternalOperation {
    override var opcode: Opcode { .fixup(self) }

    let id: String
    // The JSON-encoded action performed and modified by this Fixup operation. See the FixupMutator and RuntimeAssistedMutator classes.
    let action: String
    // The name of the original FuzzIL operation (e.g. "GetComputedProperty") that this Fixup operation replaces. Currently only used for verification.
    let originalOperation: String

    var hasOutput: Bool {
        assert(numOutputs == 0 || numOutputs == 1)
        return numOutputs == 1
    }

    init(id: String, action: String, originalOperation: String, numArguments: Int, hasOutput: Bool) {
        self.id = id
        self.action = action
        self.originalOperation = originalOperation
        super.init(numInputs: numArguments, numOutputs: hasOutput ? 1 : 0)
    }
}
