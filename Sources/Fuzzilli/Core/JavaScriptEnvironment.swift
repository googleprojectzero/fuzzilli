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

public class JavaScriptEnvironment: ComponentBase, Environment {
    // Possible return values of the 'typeof' operator.
    public static let jsTypeNames = ["undefined", "boolean", "number", "string", "symbol", "function", "object", "bigint"]
    
    // Integer values that are more likely to trigger edge-cases.
    public let interestingIntegers: [Int64] = [-9007199254740993, -9007199254740992, -9007199254740991,          // Smallest integer value that is still precisely representable by a double
                                      -4294967297, -4294967296, -4294967295,                            // Negative Uint32 max
                                      -2147483649, -2147483648, -2147483647,                            // Int32 min
                                      -1073741824, -536870912, -268435456,                              // -2**32 / {4, 8, 16}
                                      -65537, -65536, -65535,                                           // -2**16
                                      -4096, -1024, -256, -128,                                         // Other powers of two
                                      -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64,                 // Numbers around 0
                                      127, 128, 129,                                                    // 2**7
                                      255, 256, 257,                                                    // 2**8
                                      512, 1000, 1024, 4096, 10000,                                     // Misc numbers
                                      65535, 65536, 65537,                                              // 2**16
                                      268435456, 536870912, 1073741824,                                 // 2**32 / {4, 8, 16}
                                      2147483647, 2147483648, 2147483649,                               // Int32 max
                                      4294967295, 4294967296, 4294967297,                               // Uint32 max
                                      9007199254740991, 9007199254740992, 9007199254740993,             // Biggest integer value that is still precisely representable by a double
    ]
    
    // Double values that are more likely to trigger edge-cases.
    public let interestingFloats = [-Double.infinity, -Double.greatestFiniteMagnitude, -1e12, -1e9, -1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -Double.ulpOfOne, -Double.leastNormalMagnitude, -0.0, 0.0, Double.leastNormalMagnitude, Double.ulpOfOne, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6, 1e9, 1e12, Double.greatestFiniteMagnitude, Double.infinity, Double.nan]

    // TODO more?
    public let interestingStrings = jsTypeNames

    // TODO more?
    public let interestingRegExps = [".", "\\d", "\\w", "\\s", "\\D", "\\W", "\\S"]
    public let interestingRegExpQuantifiers = ["*", "+", "?"]
    
    public var intType = Type.integer
    public var bigIntType = Type.bigint
    public var floatType = Type.float
    public var booleanType = Type.boolean
    public var regExpType = Type.jsRegExp
    public var stringType = Type.jsString
    public var arrayType = Type.jsArray
    public var objectType = Type.jsPlainObject
    
    public func functionType(forSignature signature: FunctionSignature) -> Type {
        return .jsFunction(signature)
    }
    
    public private(set) var builtins = Set<String>()
    public private(set) var methodNames = Set<String>()
    public private(set) var readPropertyNames = Set<String>()
    public private(set) var writePropertyNames = Set<String>()
    public private(set) var customPropertyNames = Set<String>()
    public private(set) var customMethodNames = Set<String>()
    
    private var builtinTypes: [String: Type] = [:]
    private var groups: [String: ObjectGroup] = [:]
    
    public init(additionalBuiltins: [String: Type], additionalObjectGroups: [ObjectGroup]) {
        super.init(name: "JavaScriptEnvironment")
        
        // Build model of the JavaScript environment

        // Register all object groups that we use to model the JavaScript runtime environment.
        // The object groups allow us to associate type information for properties and methods
        // with groups of related objects, e.g. strings, arrays, etc.
        // It generally doesn't hurt to leave all of these enabled. If specific APIs should be disabled,
        // it is best to either just disable the builtin that exposes it (e.g. Map constructor) or
        // selectively disable methods/properties by commenting out parts of the ObjectGroup and
        // Type definitions at the end of this file.
        registerObjectGroup(.jsStrings)
        registerObjectGroup(.jsPlainObjects)
        registerObjectGroup(.jsArrays)
        registerObjectGroup(.jsPromises)
        registerObjectGroup(.jsRegExps)
        registerObjectGroup(.jsFunctions)
        registerObjectGroup(.jsSymbols)
        registerObjectGroup(.jsMaps)
        registerObjectGroup(.jsWeakMaps)
        registerObjectGroup(.jsSets)
        registerObjectGroup(.jsWeakSets)
        registerObjectGroup(.jsArrayBuffers)
        for variant in ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray"] {
            registerObjectGroup(.jsTypedArrays(variant))
        }
        registerObjectGroup(.jsDataViews)
        
        registerObjectGroup(.jsObjectConstructor)
        registerObjectGroup(.jsPromiseConstructor)
        registerObjectGroup(.jsArrayConstructor)
        registerObjectGroup(.jsStringConstructor)
        registerObjectGroup(.jsSymbolConstructor)
        registerObjectGroup(.jsBigIntConstructor)
        registerObjectGroup(.jsBooleanConstructor)
        registerObjectGroup(.jsNumberConstructor)
        registerObjectGroup(.jsMathObject)
        registerObjectGroup(.jsJSONObject)
        registerObjectGroup(.jsReflectObject)
        registerObjectGroup(.jsArrayBufferConstructor)
        
        for group in additionalObjectGroups {
            registerObjectGroup(group)
        }
        
        
        // Register builtins that should be available for fuzzing.
        // Here it is easy to selectively disable/enable some APIs for fuzzing by
        // just commenting out the corresponding lines.
        registerBuiltin("Object", ofType: .jsObjectConstructor)
        registerBuiltin("Array", ofType: .jsArrayConstructor)
        registerBuiltin("Function", ofType: .jsFunctionConstructor)
        registerBuiltin("String", ofType: .jsStringConstructor)
        registerBuiltin("Boolean", ofType: .jsBooleanConstructor)
        registerBuiltin("Number", ofType: .jsNumberConstructor)
        registerBuiltin("Symbol", ofType: .jsSymbolConstructor)
        registerBuiltin("BigInt", ofType: .jsBigIntConstructor)
        registerBuiltin("RegExp", ofType: .jsRegExpConstructor)
        registerBuiltin("ArrayBuffer", ofType: .jsArrayBufferConstructor)
        for variant in ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray"] {
            registerBuiltin(variant, ofType: .jsTypedArrayConstructor(variant))
        }
        registerBuiltin("DataView", ofType: .jsDataViewConstructor)
        registerBuiltin("Promise", ofType: .jsPromiseConstructor)
        registerBuiltin("Proxy", ofType: .jsProxyConstructor)
        registerBuiltin("Map", ofType: .jsMapConstructor)
        registerBuiltin("WeakMap", ofType: .jsWeakMapConstructor)
        registerBuiltin("Set", ofType: .jsSetConstructor)
        registerBuiltin("WeakSet", ofType: .jsWeakSetConstructor)
        registerBuiltin("Math", ofType: .jsMathObject)
        registerBuiltin("JSON", ofType: .jsJSONObject)
        registerBuiltin("Reflect", ofType: .jsReflectObject)
        registerBuiltin("isNaN", ofType: .jsIsNaNFunction)
        registerBuiltin("isFinite", ofType: .jsIsFiniteFunction)
        //registerBuiltin("escape:", ofType: .jsEscapeFunction)
        //registerBuiltin("unescape:", ofType: .jsUnescapeFunction)
        //registerBuiltin("decodeURI:", ofType: .jsDecodeURIFunction)
        //registerBuiltin("decodeURIComponent:", ofType: .jsDecodeURIComponentFunction)
        //registerBuiltin("encodeURI:", ofType: .jsEncodeURIFunction)
        //registerBuiltin("encodeURIComponent:", ofType: .jsEncodeURIComponentFunction)
        registerBuiltin("eval", ofType: .jsEvalFunction)
        registerBuiltin("parseInt", ofType: .jsParseIntFunction)
        registerBuiltin("parseFloat", ofType: .jsParseFloatFunction)
        registerBuiltin("undefined", ofType: .jsUndefined)
        registerBuiltin("NaN", ofType: .jsNaN)
        registerBuiltin("Infinity", ofType: .jsInfinity)
        
        // Register pseudo builtins
        registerBuiltin("this", ofType: .object())
        registerBuiltin("arguments", ofType: .object())
        
        for (builtin, type) in additionalBuiltins {
            registerBuiltin(builtin, ofType: type)
        }

        // Check that we have type information for every group (besides the *Constructor groups).
        // This is necessary because we assume in the ProgramBuilder that we can use these type information
        // to generate variables of desired types. We assume that we can use these group names as constructors
        // and call them just like that in JavaScript. If at some point this is not true, we will need to be able to
        // associate FuzzIL constructors to groups in a different way.
        for group in groups.keys where !group.contains("Constructor") {
            assert(builtins.contains(group), "We cannot call the constructor for the given group \(group)")
        }
        
        customPropertyNames = ["a", "b", "c", "d", "e"]
        // This is needed in ProgramBuilder.generateVariable, such that method names don't collide with property names.
        customMethodNames = ["f", "g", "h", "i"]
        methodNames.formUnion(customPropertyNames)
        writePropertyNames = customPropertyNames.union(["toString", "valueOf", "__proto__", "constructor", "length"])
        readPropertyNames.formUnion(writePropertyNames.union(customPropertyNames))
    }
    
    override func initialize() {
        assert(!readPropertyNames.isEmpty)
        assert(!writePropertyNames.isEmpty)
        assert(!methodNames.isEmpty)
        // Needed for ProgramBuilder.generateVariable
        assert(customMethodNames.isDisjoint(with: customPropertyNames))
        
        // Log detailed information about the environment here so users are aware of it and can modify things if they like.
        logger.info("initialized static JS environment model")
        logger.info("Have \(builtins.count) available builtins: \(builtins)")
        logger.info("Have \(methodNames.count) available method names: \(methodNames)")
        logger.info("Have \(readPropertyNames.count) property names that are available for read access: \(readPropertyNames)")
        logger.info("Have \(writePropertyNames.count) property names that are available for write access: \(writePropertyNames)")
        logger.info("Have \(customPropertyNames.count) custom property names: \(customPropertyNames)")
    }
    
    public func registerObjectGroup(_ group: ObjectGroup) {
        assert(groups[group.name] == nil)
        groups[group.name] = group
        methodNames.formUnion(group.methods.keys)
        readPropertyNames.formUnion(group.properties.keys)
    }
    
    public func registerBuiltin(_ name: String, ofType type: Type) {
        assert(builtinTypes[name] == nil)
        builtinTypes[name] = type
        builtins.insert(name)
    }
    
    public func type(ofBuiltin builtinName: String) -> Type {
        if let type = builtinTypes[builtinName] {
            return type
        } else {
            logger.warning("Missing type for builtin \(builtinName)")
            return .unknown
        }
    }
        
    public func type(ofProperty propertyName: String, on baseType: Type) -> Type {
        if let groupName = baseType.group {
            if let group = groups[groupName] {
                if let type = group.properties[propertyName] {
                    return type
                }
            } else {
                // This shouldn't happen, probably forgot to register the object group
                logger.warning("No type information for object group \(groupName) available")
            }
        }
        
        return .unknown
    }
    
    public func signature(ofMethod methodName: String, on baseType: Type) -> FunctionSignature {
        if let groupName = baseType.group {
            if let group = groups[groupName] {
                if let type = group.methods[methodName] {
                    return type
                }
            } else {
                // This shouldn't happen, probably forgot to register the object group
                logger.warning("No type information for object group \(groupName) available")
            }
        }
        
        return FunctionSignature.forUnknownFunction
    }
}

/// A struct to encapsulate property and method type information for a group of related objects.
public struct ObjectGroup {
    public let name: String
    public let properties: [String: Type]
    public let methods: [String: FunctionSignature]
    
    /// The type of instances of this group.
    public let instanceType: Type
    
    public init(name: String, instanceType: Type, properties: [String: Type], methods: [String: FunctionSignature]) {
        self.name = name
        self.instanceType = instanceType
        self.properties = properties
        self.methods = methods
        
        // We could also only assert set inclusion here to implement "shared" properties/methods.
        // (which would then need some kind of fallback ObjectGroup that is consulted by the
        // type lookup routines if the real group doesn't have the requested information).
        assert(instanceType.group == name, "group name mismatch for group \(name)")
        assert(instanceType.properties == Set(properties.keys), "inconsistent property information for object group \(name): \(Set(properties.keys).symmetricDifference(instanceType.properties))")
        assert(instanceType.methods == Set(methods.keys), "inconsistent method information for object group \(name): \(Set(methods.keys).symmetricDifference(instanceType.methods))")
    }
}

// All instance types are installed as extensions on Type.
// Note, these must be kept in sync with the ObjectGroups below (in particular the properties and methods).
// To help with that, the ObjectGroup constructor asserts that the type information is consistent between
// instance type and the ObjectGroup.
public extension Type {
    /// Type of a string in JavaScript.
    /// A JS string is both a string and an object on which methods can be called.
    static let jsString = Type.string + Type.iterable + Type.object(ofGroup: "String", withProperties: ["__proto__", "constructor", "length"], withMethods: ["charAt", "charCodeAt", "codePointAt", "concat", "includes", "endsWith", "indexOf", "lastIndexOf", "match", "matchAll", "padEnd", "padStart", "repeat", "replace", "replaceAll", "search", "slice", "split", "startsWith", "substring", "trim"])
    
    /// Type of a regular expression in JavaScript.
    /// A JS RegExp is both a RegExp and an object on which methods can be called.
    static let jsRegExp = Type.regexp + Type.object(ofGroup: "RegExp", withProperties: ["__proto__", "flags", "dotAll", "global", "ignoreCase", "multiline", "source", "sticky", "unicode"], withMethods: ["compile", "exec", "test"])
    
    /// Type of a JavaScript Symbol.
    static let jsSymbol = Type.object(ofGroup: "Symbol", withProperties: ["__proto__", "description"])

    /// Type of a plain JavaScript object.
    static let jsPlainObject = Type.object(ofGroup: "Object", withProperties: ["__proto__"])
    
    /// Type of a JavaScript array.
    static let jsArray = Type.iterable + Type.object(ofGroup: "Array", withProperties: ["__proto__", "length", "constructor"], withMethods: ["concat", "copyWithin", "fill", "find", "findIndex", "pop", "push", "reverse", "shift", "unshift", "slice", "sort", "splice", "includes", "indexOf", "keys", "entries", "forEach", "filter", "map", "every", "some", "reduce", "reduceRight", "toString", "toLocaleString", "join", "lastIndexOf", "values", "flat", "flatMap"])
    
    /// Type of a JavaScript Map object.
    static let jsMap = Type.iterable + Type.object(ofGroup: "Map", withProperties: ["__proto__", "size"], withMethods: ["clear", "delete", "entries", "forEach", "get", "has", "keys", "set", "values"])

    /// Type of a JavaScript Promise object.
    static let jsPromise = Type.object(ofGroup: "Promise", withProperties: ["__proto__"], withMethods: ["catch", "finally", "then"])
    
    /// Type of a JavaScript WeakMap object.
    static let jsWeakMap = Type.object(ofGroup: "WeakMap", withProperties: ["__proto__"], withMethods: ["delete", "get", "has", "set"])
    
    /// Type of a JavaScript Set object.
    static let jsSet = Type.iterable + Type.object(ofGroup: "Set", withProperties: ["__proto__", "size"], withMethods: ["add", "clear", "delete", "entries", "forEach", "has", "keys", "values"])
    
    /// Type of a JavaScript WeakSet object.
    static let jsWeakSet = Type.object(ofGroup: "WeakSet", withProperties: ["__proto__"], withMethods: ["add", "delete", "has"])
    
    /// Type of a JavaScript ArrayBuffer object.
    static let jsArrayBuffer = Type.object(ofGroup: "ArrayBuffer", withProperties: ["__proto__", "byteLength"], withMethods: ["slice"])
    
    /// Type of a JavaScript DataView object.
    static let jsDataView = Type.object(ofGroup: "DataView", withProperties: ["__proto__", "buffer", "byteLength", "byteOffset"], withMethods: ["getInt8", "getUint8", "getInt16", "getUint16", "getInt32", "getUint32", "getFloat32", "getFloat64", "setInt8", "setUint8", "setInt16", "setUint16", "setInt32", "setUint32", "setFloat32", "setFloat64"])
    
    /// Type of a JavaScript TypedArray object of the given variant.
    static func jsTypedArray(_ variant: String) -> Type {
        return .iterable + .object(ofGroup: variant, withProperties: ["__proto__", "length", "constructor", "buffer", "byteOffset", "byteLength"], withMethods: ["copyWithin", "fill", "find", "findIndex", "reverse", "slice", "sort", "includes", "indexOf", "keys", "entries", "forEach", "filter", "map", "every", "set", "some", "subarray", "reduce", "reduceRight", "join", "lastIndexOf", "values"])
    }
    
    /// Type of a JavaScript function.
    /// A JavaScript function is also constructors. Moreover, it is also an object as it has a number of properties and methods.
    static func jsFunction(_ signature: FunctionSignature = FunctionSignature.forUnknownFunction) -> Type {
        return .constructor(signature) + .function(signature) + .object(ofGroup: "Function", withProperties: ["__proto__", "prototype", "length", "constructor", "arguments", "caller", "name"], withMethods: ["apply", "bind", "call"])
    }
    
    /// Type of the JavaScript Object constructor builtin.
    static let jsObjectConstructor = .functionAndConstructor([.anything...] => .object()) + .object(ofGroup: "ObjectConstructor", withProperties: ["prototype"], withMethods: ["assign", "fromEntries", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames", "getOwnPropertySymbols", "is", "preventExtensions", "seal", "create", "defineProperties", "defineProperty", "freeze", "getPrototypeOf", "setPrototypeOf", "isExtensible", "isFrozen", "isSealed", "keys", "entries", "values"])
    
    /// Type of the JavaScript Array constructor builtin.
    static let jsArrayConstructor = .functionAndConstructor([.integer] => .jsArray) + .object(ofGroup: "ArrayConstructor", withProperties: ["prototype"], withMethods: ["from", "of", "isArray"])
    
    /// Type of the JavaScript Function constructor builtin.
    static let jsFunctionConstructor = Type.constructor([.string] => .jsFunction(FunctionSignature.forUnknownFunction))
    
    /// Type of the JavaScript String constructor builtin.
    static let jsStringConstructor = Type.functionAndConstructor([.anything] => .jsString) + .object(ofGroup: "StringConstructor", withProperties: ["prototype"], withMethods: ["fromCharCode", "fromCodePoint", "raw"])
    
    /// Type of the JavaScript Boolean constructor builtin.
    static let jsBooleanConstructor = Type.functionAndConstructor([.anything] => .boolean) + .object(ofGroup: "BooleanConstructor", withProperties: ["prototype"], withMethods: [])
    
    /// Type of the JavaScript Number constructor builtin.
    static let jsNumberConstructor = Type.functionAndConstructor([.anything] => .number) + .object(ofGroup: "NumberConstructor", withProperties: ["prototype", "EPSILON", "MAX_SAFE_INTEGER", "MAX_VALUE", "MIN_SAFE_INTEGER", "MIN_VALUE", "NaN", "NEGATIVE_INFINITY", "POSITIVE_INFINITY"], withMethods: ["isNaN", "isFinite", "isInteger", "isSafeInteger"])
    
    /// Type of the JavaScript Symbol constructor builtin.
    static let jsSymbolConstructor = Type.function([.string] => .jsSymbol) + .object(ofGroup: "SymbolConstructor", withProperties: ["iterator", "asyncIterator", "match", "matchAll", "replace", "search", "split", "hasInstance", "isConcatSpreadable", "unscopable", "species", "toPrimitive", "toStringTag"], withMethods: ["for", "keyFor"])

    /// Type of the JavaScript BigInt constructor builtin.
    static let jsBigIntConstructor = Type.function([.number] => .bigint) + .object(ofGroup: "BigIntConstructor", withProperties: ["prototype"], withMethods: ["asIntN", "asUintN"])
    
    /// Type of the JavaScript RegExp constructor builtin.
    static let jsRegExpConstructor = Type.jsFunction([.string] => .jsRegExp)
    
    /// Type of the JavaScript ArrayBuffer constructor builtin.
    static let jsArrayBufferConstructor = Type.constructor([.integer] => .jsArrayBuffer) + .object(ofGroup: "ArrayBufferConstructor", withProperties: ["prototype"], withMethods: ["isView"])
    
    /// Type of a JavaScript TypedArray constructor builtin.
    static func jsTypedArrayConstructor(_ variant: String) -> Type {
        return .constructor([.integer | .object(ofGroup: "ArrayBuffer")] => .jsTypedArray(variant))
    }
    
    /// Type of the JavaScript DataView constructor builtin.
    static let jsDataViewConstructor = Type.constructor([.object(ofGroup: "ArrayBuffer"), .opt(.integer), .opt(.integer)] => .jsDataView)

    /// Type of the JavaScript Promise constructor builtin.
    static let jsPromiseConstructor = Type.constructor([.function()] => .jsPromise) + .object(ofGroup: "PromiseConstructor", withProperties: ["prototype"], withMethods: ["resolve", "reject", "all", "race", "allSettled"])
    
    /// Type of the JavaScript Proxy constructor builtin.
    static let jsProxyConstructor = Type.constructor([.object(), .object()] => .unknown)
    
    /// Type of the JavaScript Map constructor builtin.
    static let jsMapConstructor = Type.constructor([.object()] => .jsMap)
    
    /// Type of the JavaScript WeakMap constructor builtin.
    static let jsWeakMapConstructor = Type.constructor([.object()] => .jsWeakMap)
    
    /// Type of the JavaScript Set constructor builtin.
    static let jsSetConstructor = Type.constructor([.object()] => .jsSet)
    
    /// Type of the JavaScript WeakSet constructor builtin.
    static let jsWeakSetConstructor = Type.constructor([.object()] => .jsWeakSet)
    
    /// Type of the JavaScript Math constructor builtin.
    static let jsMathObject = Type.object(ofGroup: "Math", withProperties: ["E", "PI"], withMethods: ["abs", "acos", "acosh", "asin", "asinh", "atan", "atanh", "atan2", "ceil", "cbrt", "expm1", "clz32", "cos", "cosh", "exp", "floor", "fround", "hypot", "imul", "log", "log1p", "log2", "log10", "max", "min", "pow", "random", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc"])
    
    /// Type of the JavaScript JSON object builtin.
    static let jsJSONObject = Type.object(ofGroup: "JSON", withMethods: ["parse", "stringify"])
    
    /// Type of the JavaScript Reflect object builtin.
    static let jsReflectObject = Type.object(ofGroup: "Reflect", withMethods: ["apply", "construct", "defineProperty", "deleteProperty", "get", "getOwnPropertyDescriptor", "getPrototypeOf", "has", "isExtensible", "ownKeys", "preventExtensions", "set", "setPrototypeOf"])
    
    /// Type of the JavaScript isNaN builtin function.
    static let jsIsNaNFunction = Type.function([.anything] => .boolean)
    
    /// Type of the JavaScript isFinite builtin function.
    static let jsIsFiniteFunction = Type.function([.anything] => .boolean)
    
    /// Type of the JavaScript escape builtin function.
    static let jsEscapeFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript unescape builtin function.
    static let jsUnescapeFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript decodeURI builtin function.
    static let jsDecodeURIFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript decodeURIComponent builtin function.
    static let jsDecodeURIComponentFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript encodeURI builtin function.
    static let jsEncodeURIFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript encodeURIComponent builtin function.
    static let jsEncodeURIComponentFunction = Type.function([.anything] => .jsString)
    
    /// Type of the JavaScript eval builtin function.
    static let jsEvalFunction = Type.function([.string] => .unknown)
    
    /// Type of the JavaScript parseInt builtin function.
    static let jsParseIntFunction = Type.function([.string] => .integer)
    
    /// Type of the JavaScript parseFloat builtin function.
    static let jsParseFloatFunction = Type.function([.string] => .float)
    
    /// Type of the JavaScript undefined value.
    static let jsUndefined = Type.undefined
    
    /// Type of the JavaScript NaN value.
    static let jsNaN = Type.float
    
    /// Type of the JavaScript Infinity value.
    static let jsInfinity = Type.float
}

// Type information for the object groups that we use to model the JavaScript runtime environment.
// The general rules here are:
//  * "output" type information (properties and return values) should be as precise as possible
//  * "input" type information (function parameters) should be as broad as possible (the largest type that won't lead to a runtime exception)
public extension ObjectGroup {
    /// Object group modelling JavaScript strings
    static let jsStrings = ObjectGroup(
        name: "String",
        instanceType: .jsString,
        properties: [
            "__proto__"   : .object(),
            "length"      : .integer,
            "constructor" : .function()
        ],
        methods: [
            "charAt"      : [.integer] => .jsString,
            "charCodeAt"  : [.integer] => .integer,
            "codePointAt" : [.integer] => .integer,
            "concat"      : [.anything...] => .jsString,
            "includes"    : [.anything, .opt(.integer)] => .boolean,
            "endsWith"    : [.string, .opt(.integer)] => .boolean,
            "indexOf"     : [.anything, .opt(.integer)] => .integer,
            "lastIndexOf" : [.anything, .opt(.integer)] => .integer,
            "match"       : [.regexp] => .jsString,
            "matchAll"    : [.regexp] => .jsString,
            //"normalize"   : [.string] => .jsString),
            "padEnd"      : [.integer, .opt(.string)] => .jsString,
            "padStart"    : [.integer, .opt(.string)] => .jsString,
            "repeat"      : [.integer] => .jsString,
            "replace"     : [.string | .regexp, .string] => .jsString,
            "replaceAll"  : [.string, .string] => .jsString,
            "search"      : [.regexp] => .integer,
            "slice"       : [.integer, .opt(.integer)] => .jsString,
            "split"       : [.opt(.string), .opt(.integer)] => .jsArray,
            "startsWith"  : [.string, .opt(.integer)] => .boolean,
            "substring"   : [.integer, .opt(.integer)] => .jsString,
            "trim"        : [] => .undefined,
            // ...
        ]
    )
    
    /// Object group modelling plain JavaScript objects
    static let jsPlainObjects = ObjectGroup(
        name: "Object",
        instanceType: .jsPlainObject,
        properties: [
            "__proto__" : .object()
        ],
        methods: [:]
    )

    /// Object group modelling JavaScript regular expressions.
    static let jsRegExps = ObjectGroup(
        name: "RegExp",
        instanceType: .jsRegExp,
        properties: [
            "__proto__"  : .object(),
            "flags"      : .string,
            "dotAll"     : .boolean,
            "global"     : .boolean,
            "ignoreCase" : .boolean,
            "multiline"  : .boolean,
            "source"     : .string,
            "sticky"     : .boolean,
            "unicode"    : .boolean,
        ],
        methods: [
            "compile"    : [.string] => .jsRegExp,
            "exec"       : [.string] => .jsArray,
            "test"       : [.string] => .boolean,
        ]
    )

    /// Object group modelling JavaScript promises.
    static let jsPromises = ObjectGroup(
        name: "Promise",
        instanceType: .jsPromise,
        properties: [
            "__proto__" : .object(),
        ],
        methods: [
            "catch"   : [.function()] => .jsPromise,
            "then"    : [.function()] => .jsPromise,
            "finally" : [.function()] => .jsPromise,
        ]
    )
    
    /// Object group modelling JavaScript arrays
    static let jsArrays = ObjectGroup(
        name: "Array",
        instanceType: .jsArray,
        properties: [
            "__proto__"   : .object(),
            "length"      : .integer,
            "constructor" : .jsFunction([.integer] => .jsArray),
        ],
        methods: [
            "copyWithin"     : [.integer, .integer, .opt(.integer)] => .jsArray,
            "entries"        : [] => .jsArray,
            "every"          : [.function(), .opt(.object())] => .boolean,
            "fill"           : [.anything, .opt(.integer), .opt(.integer)] => .undefined,
            "find"           : [.function(), .opt(.object())] => .unknown,
            "findIndex"      : [.function(), .opt(.object())] => .integer,
            "forEach"        : [.function(), .opt(.object())] => .undefined,
            "includes"       : [.anything, .opt(.integer)] => .boolean,
            "indexOf"        : [.anything, .opt(.integer)] => .integer,
            "join"           : [.string] => .jsString,
            "keys"           : [] => .object(),          // returns an array iterator
            "lastIndexOf"    : [.anything, .opt(.integer)] => .integer,
            "reduce"         : [.function(), .opt(.anything)] => .unknown,
            "reduceRight"    : [.function(), .opt(.anything)] => .unknown,
            "reverse"        : [] => .undefined,
            "some"           : [.function(), .opt(.anything)] => .boolean,
            "sort"           : [.function()] => .undefined,
            "values"         : [] => .object(),
            "pop"            : [] => .unknown,
            "push"           : [.anything...] => .integer,
            "shift"          : [] => .unknown,
            "splice"         : [.integer, .opt(.integer), .anything...] => .jsArray,
            "unshift"        : [.anything...] => .integer,
            "concat"         : [.anything...] => .jsArray,
            "filter"         : [.function(), .opt(.object())] => .jsArray,
            "map"            : [.function(), .opt(.object())] => .jsArray,
            "slice"          : [.opt(.integer), .opt(.integer)] => .jsArray,
            "flat"           : [.opt(.integer)] => .jsArray,
            "flatMap"        : [.function(), .opt(.anything)] => .jsArray,
            "toString"       : [] => .jsString,
            "toLocaleString" : [] => .jsString,
        ]
    )
    
    /// ObjectGroup modelling JavaScript functions
    static let jsFunctions = ObjectGroup(
        name: "Function",
        instanceType: .jsFunction(),
        properties: [
            "__proto__"   : .object(),
            "prototype"   : .object(),
            "constructor" : .jsFunction(),
            "length"      : .integer,
            "arguments"   : .jsArray,
            "caller"      : .jsFunction(),
            "name"        : .jsString,
        ],
        methods: [
            "apply" : [.object(), .object()] => .unknown,
            "call"  : [.object(), .anything...] => .unknown,
            "bind"  : [.object(), .anything...] => .unknown,
        ]
    )
    
    /// ObjectGroup modelling JavaScript Symbols
    static let jsSymbols = ObjectGroup(
        name: "Symbol",
        instanceType: .jsSymbol,
        properties: [
            "__proto__"   : .object(),
            "description" : .jsString,
        ],
        methods: [:]
    )
    
    /// ObjectGroup modelling JavaScript Map objects
    static let jsMaps = ObjectGroup(
        name: "Map",
        instanceType: .jsMap,
        properties: [
            "__proto__" : .object(),
            "size"      : .integer
        ],
        methods: [
            "clear"   : [] => .undefined,
            "delete"  : [.anything] => .boolean,
            "entries" : [] => .object(),
            "forEach" : [.function(), .opt(.object())] => .undefined,
            "get"     : [.anything] => .unknown,
            "has"     : [.anything] => .boolean,
            "keys"    : [] => .object(),
            "set"     : [.anything, .anything] => .jsMap,
            "values"  : [] => .object(),
        ]
    )
    
    /// ObjectGroup modelling JavaScript WeakMap objects
    static let jsWeakMaps = ObjectGroup(
        name: "WeakMap",
        instanceType: .jsWeakMap,
        properties: [
            "__proto__" : .object(),
        ],
        methods: [
            "delete" : [.anything] => .boolean,
            "get"    : [.anything] => .unknown,
            "has"    : [.anything] => .boolean,
            "set"    : [.anything, .anything] => .jsWeakMap,
        ]
    )
    
    /// ObjectGroup modelling JavaScript Set objects
    static let jsSets = ObjectGroup(
        name: "Set",
        instanceType: .jsSet,
        properties: [
            "__proto__" : .object(),
            "size"      : .integer
        ],
        methods: [
            "add"     : [.anything] => .jsSet,
            "clear"   : [] => .undefined,
            "delete"  : [.anything] => .boolean,
            "entries" : [] => .object(),
            "forEach" : [.function(), .opt(.object())] => .undefined,
            "has"     : [.anything] => .boolean,
            "keys"    : [] => .object(),
            "values"  : [] => .object(),
        ]
    )
    
    /// ObjectGroup modelling JavaScript WeakSet objects
    static let jsWeakSets = ObjectGroup(
        name: "WeakSet",
        instanceType: .jsWeakSet,
        properties: [
            "__proto__" : .object(),
        ],
        methods: [
            "add"    : [.anything] => .jsWeakSet,
            "delete" : [.anything] => .boolean,
            "has"    : [.anything] => .boolean,
        ]
    )
    
    /// ObjectGroup modelling JavaScript ArrayBuffer objects
    static let jsArrayBuffers = ObjectGroup(
        name: "ArrayBuffer",
        instanceType: .jsArrayBuffer,
        properties: [
            "__proto__"  : .object(),
            "byteLength" : .integer
        ],
        methods: [
            "slice" : [.integer, .opt(.integer)] => .jsArrayBuffer,
        ]
    )
    
    /// ObjectGroup modelling JavaScript TypedArray objects
    static func jsTypedArrays(_ variant: String) -> ObjectGroup {
        return ObjectGroup(
            name: variant,
            instanceType: .jsTypedArray(variant),
            properties: [
                "__proto__"   : .object(),
                "constructor" : .function(),
                "buffer"      : .object(),
                "byteLength"  : .integer,
                "byteOffset"  : .integer,
                "length"      : .integer
            ],
            methods: [
                "copyWithin"  : [.integer, .integer, .opt(.integer)] => .undefined,
                "entries"     : [] => .jsArray,
                "every"       : [.function(), .opt(.object())] => .boolean,
                "fill"        : [.anything, .opt(.integer), .opt(.integer)] => .undefined,
                "find"        : [.function(), .opt(.object())] => .unknown,
                "findIndex"   : [.function(), .opt(.object())] => .integer,
                "forEach"     : [.function(), .opt(.object())] => .undefined,
                "includes"    : [.anything, .opt(.integer)] => .boolean,
                "indexOf"     : [.anything, .opt(.integer)] => .integer,
                "join"        : [.string] => .jsString,
                "keys"        : [] => .object(),          // returns an array iterator
                "lastIndexOf" : [.anything, .opt(.integer)] => .integer,
                "reduce"      : [.function(), .opt(.anything)] => .unknown,
                "reduceRight" : [.function(), .opt(.anything)] => .unknown,
                "reverse"     : [] => .undefined,
                "set"         : [.object(), .opt(.integer)] => .undefined,
                "some"        : [.function(), .opt(.anything)] => .boolean,
                "sort"        : [.function()] => .undefined,
                "values"      : [] => .object(),
                "filter"      : [.function(), .opt(.object())] => .jsTypedArray(variant),
                "map"         : [.function(), .opt(.object())] => .jsTypedArray(variant),
                "slice"       : [.opt(.integer), .opt(.integer)] => .jsTypedArray(variant),
                "subarray"    : [.opt(.integer), .opt(.integer)] => .jsTypedArray(variant)
            ]
        )
    }
    
    /// ObjectGroup modelling JavaScript DataView objects
    static let jsDataViews = ObjectGroup(
        name: "DataView",
        instanceType: .jsDataView,
        properties: [
            "__proto__"  : .object(),
            "buffer"     : .jsArrayBuffer,
            "byteLength" : .integer,
            "byteOffset" : .integer
        ],
        methods: [
            "getInt8"    : [.integer] => .integer,
            "getUint8"   : [.integer] => .integer,
            "getInt16"   : [.integer] => .integer,
            "getUint16"  : [.integer] => .integer,
            "getInt32"   : [.integer] => .integer,
            "getUint32"  : [.integer] => .integer,
            "getFloat32" : [.integer] => .float,
            "getFloat64" : [.integer] => .float,
            "setInt8"    : [.integer, .integer] => .undefined,
            "setUint8"   : [.integer, .integer] => .undefined,
            "setInt16"   : [.integer, .integer] => .undefined,
            "setUint16"  : [.integer, .integer] => .undefined,
            "setInt32"   : [.integer, .integer] => .undefined,
            "setUint32"  : [.integer, .integer] => .undefined,
            "setFloat32" : [.integer, .float] => .undefined,
            "setFloat64" : [.integer, .float] => .undefined,
        ]
    )
    
    /// ObjectGroup modelling the JavaScript Promise constructor builtin
    static let jsPromiseConstructor = ObjectGroup(
        name: "PromiseConstructor",
        instanceType: .jsPromiseConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "resolve"    : [.anything] => .jsPromise,
            "reject"     : [.anything] => .jsPromise,
            "all"        : [.object()] => .jsPromise,
            "race"       : [.object()] => .jsPromise,
            "allSettled" : [.object()] => .jsPromise,
        ]
    )
    
    /// ObjectGroup modelling the JavaScript Object constructor builtin
    static let jsObjectConstructor = ObjectGroup(
        name: "ObjectConstructor",
        instanceType: .jsObjectConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "assign"                    : [.object(), .object()] => .undefined,
            "create"                    : [.object(), .object()] => .object(),
            "defineProperty"            : [.object(), .string, .object(withProperties: ["configurable", "writable", "enumerable", "value"]) | .object(withMethods: ["get", "set"])] => .undefined,
            "defineProperties"          : [.object(), .object()] => .undefined,
            "entries"                   : [.object()] => .object(),
            "freeze"                    : [.object()] => .undefined,
            "fromEntries"               : [.object()] => .object(),
            "getOwnPropertyDescriptor"  : [.object(), .string] => .object(withProperties: ["configurable", "writable", "enumerable", "value"]),
            "getOwnPropertyDescriptors" : [.object()] => .object(),
            "getOwnPropertyNames"       : [.object()] => .jsArray,
            "getOwnPropertySymbols"     : [.object()] => .jsArray,
            "getPrototypeOf"            : [.object()] => .object(),
            "is"                        : [.object(), .object()] => .boolean,
            "isExtensible"              : [.object()] => .boolean,
            "isFrozen"                  : [.object()] => .boolean,
            "isSealed"                  : [.object()] => .boolean,
            "keys"                      : [.object()] => .jsArray,
            "preventExtensions"         : [.object()] => .object(),
            "seal"                      : [.object()] => .object(),
            "setPrototypeOf"            : [.object(), .object()] => .object(),
            "values"                    : [.object()] => .jsArray,
        ]
    )
    
    /// ObjectGroup modelling the JavaScript Array constructor builtin
    static let jsArrayConstructor = ObjectGroup(
        name: "ArrayConstructor",
        instanceType: .jsArrayConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "from"    : [.anything, .opt(.function()), .opt(.object())] => .jsArray,
            "isArray" : [.anything] => .boolean,
            "of"      : [.anything...] => .jsArray,
        ]
    )

    static let jsArrayBufferConstructor = ObjectGroup(
        name: "ArrayBufferConstructor",
        instanceType: .jsArrayBufferConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "isView" : [.anything] => .boolean,
        ]
    )
    
    /// Object group modelling the JavaScript String constructor builtin
    static let jsStringConstructor = ObjectGroup(
        name: "StringConstructor",
        instanceType: .jsStringConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "fromCharCode"  : [.anything...] => .jsString,
            "fromCodePoint" : [.anything...] => .jsString,
            "raw"           : [.anything...] => .jsString
        ]
    )
    
    /// Object group modelling the JavaScript Symbol constructor builtin
    static let jsSymbolConstructor = ObjectGroup(
        name: "SymbolConstructor",
        instanceType: .jsSymbolConstructor,
        properties: [
            "iterator"           : .jsSymbol,
            "asyncIterator"      : .jsSymbol,
            "match"              : .jsSymbol,
            "matchAll"           : .jsSymbol,
            "replace"            : .jsSymbol,
            "search"             : .jsSymbol,
            "split"              : .jsSymbol,
            "hasInstance"        : .jsSymbol,
            "isConcatSpreadable" : .jsSymbol,
            "unscopable"         : .jsSymbol,
            "species"            : .jsSymbol,
            "toPrimitive"        : .jsSymbol,
            "toStringTag"        : .jsSymbol
        ],
        methods: [
            "for"    : [.string] => .jsSymbol,
            "keyFor" : [.jsSymbol] => .jsString,
        ]
    )

    /// Object group modelling the JavaScript BigInt constructor builtin
    static let jsBigIntConstructor = ObjectGroup(
        name: "BigIntConstructor",
        instanceType: .jsBigIntConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "asIntN"  : [.number, .bigint] => .bigint,
            "asUintN" : [.number, .bigint] => .bigint,
        ]
    )
    
    /// Object group modelling the JavaScript Boolean constructor builtin
    static let jsBooleanConstructor = ObjectGroup(
        name: "BooleanConstructor",
        instanceType: .jsBooleanConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [:]
    )
    
    /// Object group modelling the JavaScript Number constructor builtin
    static let jsNumberConstructor = ObjectGroup(
        name: "NumberConstructor",
        instanceType: .jsNumberConstructor,
        properties: [
            "prototype"         : .object(),
            "EPSILON"           : .number,
            "MAX_SAFE_INTEGER"  : .number,
            "MAX_VALUE"         : .number,
            "MIN_SAFE_INTEGER"  : .number,
            "MIN_VALUE"         : .number,
            "NaN"               : .number,
            "NEGATIVE_INFINITY" : .number,
            "POSITIVE_INFINITY" : .number,
        ],
        methods: [
            "isNaN"         : [.anything] => .boolean,
            "isFinite"      : [.anything] => .boolean,
            "isInteger"     : [.anything] => .boolean,
            "isSafeInteger" : [.anything] => .boolean,
        ]
    )
    
    /// Object group modelling the JavaScript Math builtin
    static let jsMathObject = ObjectGroup(
        name: "Math",
        instanceType: .jsMathObject,
        properties: [
            "E"  : .number,
            "PI" : .number
        ],
        methods: [
            "abs"    : [.anything] => .number,
            "acos"   : [.anything] => .number,
            "acosh"  : [.anything] => .number,
            "asin"   : [.anything] => .number,
            "asinh"  : [.anything] => .number,
            "atan"   : [.anything] => .number,
            "atanh"  : [.anything] => .number,
            "atan2"  : [.anything, .anything] => .number,
            "cbrt"   : [.anything] => .number,
            "ceil"   : [.anything] => .number,
            "clz32"  : [.anything] => .number,
            "cos"    : [.anything] => .number,
            "cosh"   : [.anything] => .number,
            "exp"    : [.anything] => .number,
            "expm1"  : [.anything] => .number,
            "floor"  : [.anything] => .number,
            "fround" : [.anything] => .number,
            "hypot"  : [.anything...] => .number,
            "imul"   : [.anything, .anything] => .integer,
            "log"    : [.anything] => .number,
            "log1p"  : [.anything] => .number,
            "log10"  : [.anything] => .number,
            "log2"   : [.anything] => .number,
            "max"    : [.anything...] => .unknown,
            "min"    : [.anything...] => .unknown,
            "pow"    : [.anything, .anything] => .number,
            "random" : [] => .number,
            "round"  : [.anything] => .number,
            "sign"   : [.anything] => .number,
            "sin"    : [.anything] => .number,
            "sinh"   : [.anything] => .number,
            "sqrt"   : [.anything] => .number,
            "tan"    : [.anything] => .number,
            "tanh"   : [.anything] => .number,
            "trunc"  : [.anything] => .number,
        ]
    )
    
    /// ObjectGroup modelling the JavaScript JSON builtin
    static let jsJSONObject = ObjectGroup(
        name: "JSON",
        instanceType: .jsJSONObject,
        properties: [:],
        methods: [
            "parse"     : [.string, .opt(.function())] => .unknown,
            "stringify" : [.anything, .opt(.function()), .opt(.number | .string)] => .jsString,
        ]
    )
    
    /// ObjectGroup modelling the JavaScript Reflect builtin
    static let jsReflectObject = ObjectGroup(
        name: "Reflect",
        instanceType: .jsReflectObject,
        properties: [:],
        methods: [
            "apply"                    : [.function(), .anything, .object()] => .unknown,
            "construct"                : [.constructor(), .object(), .opt(.object())] => .unknown,
            "defineProperty"           : [.object(), .string, .object()] => .boolean,
            "deleteProperty"           : [.object(), .string] => .boolean,
            "get"                      : [.object(), .string, .opt(.object())] => .unknown,
            "getOwnPropertyDescriptor" : [.object(), .string] => .unknown,
            "getPrototypeOf"           : [.anything] => .unknown,
            "has"                      : [.object(), .string] => .boolean,
            "isExtensible"             : [.anything] => .boolean,
            "ownKeys"                  : [.anything] => .jsArray,
            "preventExtensions"        : [.object()] => .boolean,
            "set"                      : [.object(), .string, .anything, .opt(.object())] => .boolean,
            "setPrototypeOf"           : [.object(), .object()] => .boolean,
        ]
    )
}
