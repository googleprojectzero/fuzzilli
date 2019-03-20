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

import Fuzzilli

/// Enabled code generators.
let defaultCodeGenerators = WeightedList<CodeGenerator>([
    // Base generators
    (IntegerLiteralGenerator,            2),
    (FloatLiteralGenerator,              1),
    (StringLiteralGenerator,             1),
    (BooleanLiteralGenerator,            1),
    (UndefinedValueGenerator,            1),
    (NullValueGenerator,                 1),
    (BuiltinGenerator,                   5),
    (ObjectLiteralGenerator,             10),
    (ArrayLiteralGenerator,              10),
    (ObjectLiteralWithSpreadGenerator,   5),
    (ArrayLiteralWithSpreadGenerator,    5),
    (FunctionDefinitionGenerator,        15),
    (FunctionReturnGenerator,            3),
    (PropertyRetrievalGenerator,         20),
    (PropertyAssignmentGenerator,        20),
    (PropertyRemovalGenerator,           5),
    (ElementRetrievalGenerator,          20),
    (ElementAssignmentGenerator,         20),
    (ElementRemovalGenerator,            5),
    (TypeTestGenerator,                  5),
    (InstanceOfGenerator,                5),
    (InGenerator,                        3),
    (ComputedPropertyRetrievalGenerator, 20),
    (ComputedPropertyAssignmentGenerator,20),
    (ComputedPropertyRemovalGenerator,   5),
    (FunctionCallGenerator,              30),
    (FunctionCallWithSpreadGenerator,    10),
    (MethodCallGenerator,                30),
    (ConstructorCallGenerator,           20),
    (UnaryOperationGenerator,            25),
    (BinaryOperationGenerator,           60),
    (PhiGenerator,                       20),
    (ReassignmentGenerator,              20),
    (WithStatementGenerator,             5),
    (LoadFromScopeGenerator,             4),
    (StoreToScopeGenerator,              4),
    (ComparisonGenerator,                10),
    (IfStatementGenerator,               25),
    (WhileLoopGenerator,                 20),
    (DoWhileLoopGenerator,               20),
    (ForLoopGenerator,                   20),
    (ForInLoopGenerator,                 10),
    (ForOfLoopGenerator,                 10),
    (BreakGenerator,                     5),
    (ContinueGenerator,                  5),
    // Try-catch is currently disabled as it quickly leads to parser edges being triggered
    // (e.g. through try { new Function(rand_string); }), which aren't very interesting...
    //(TryCatchGenerator,                  5),
    //(ThrowGenerator,                     1),
    
    // Special generators
    (WellKnownPropertyLoadGenerator,     5),
    (WellKnownPropertyStoreGenerator,    5),
    (TypedArrayGenerator,                10),
    (FloatArrayGenerator,                5),
    (IntArrayGenerator,                  5),
    (ObjectArrayGenerator,               5),
    (PrototypeAccessGenerator,           15),
    (PrototypeOverwriteGenerator,        15),
    (CallbackPropertyGenerator,          15),
    (PropertyAccessorGenerator,          15),
    (ProxyGenerator,                     15),
    (LengthChangeGenerator,              5),
    (ElementKindChangeGenerator,         5),
])

// Default environment. We avoid things that trigger parser code or similar. Typed arrays are created by the TypedArrayGenerator.
let defaultBuiltins = ["Object", "Function", "Array", "Number", "Boolean", "String", "Symbol", /*"Date",*/ "Promise", "RegExp", "Error", "ArrayBuffer", /* we get these through code generators "Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "DataView",*/ "Map", "Set", "WeakMap", "WeakSet", "Proxy", "Reflect", /*"JSON",*/ "Math", /*"escape", "unescape",*/ "parseFloat", "parseInt", /*"undefined"*/ /* pseudo-builtins: */ "this", "arguments"]

let defaultPropertyNames = [/* Object */ "getPrototypeOf", "setPrototypeOf", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames", "getOwnPropertySymbols", "keys", "defineProperty", "defineProperties", "create", "seal", "freeze", "preventExtensions", "isSealed", "isFrozen", "isExtensible", "is", "assign", "values", "entries", "fromEntries", "name", "prototype", "length", /* Function */ /* Array */ "of", "from", "isArray", /* Number */ "isFinite", "isNaN", "isSafeInteger", "EPSILON", "MAX_VALUE", "MIN_VALUE", "MAX_SAFE_INTEGER", "MIN_SAFE_INTEGER", "NEGATIVE_INFINITY", "POSITIVE_INFINITY", "NaN", "parseInt", "parseFloat", "isInteger", /* Boolean */ /* String */ "fromCharCode", "fromCodePoint", "raw", /* Symbol */ "for", "keyFor", "hasInstance", "isConcatSpreadable", "asyncIterator", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables", /* Promise */ "resolve", "reject", "race", "all", /* RegExp */ "input", "multiline", "lastMatch", "lastParen", "leftContext", "rightContext", /* Error */ "stackTraceLimit", /* ArrayBuffer */ "isView", /* Uint8Array */ "BYTES_PER_ELEMENT", /* Int8Array */ /* Uint16Array */ /* Int16Array */ /* Uint32Array */ /* Int32Array */ /* Float32Array */ /* Float64Array */ /* Uint8ClampedArray */ /* DataView */ /* Map */ /* Set */ /* WeakMap */ /* WeakSet */ /* Proxy */ "revocable", /* Reflect */ "apply", "construct", "deleteProperty", "get", "has", "ownKeys", "set", /* Math */ "E", "LN2", "LN10", "LOG2E", "LOG10E", "PI", "SQRT1_2", "SQRT2", "abs", "acos", "asin", "atan", "acosh", "asinh", "atanh", "atan2", "cbrt", "ceil", "clz32", "cos", "cosh", "exp", "expm1", "floor", "fround", "hypot", "log", "log10", "log1p", "log2", "max", "min", "pow", "random", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc", "imul", /* Object.prototype */ "toString", "toLocaleString", "valueOf", "hasOwnProperty", "propertyIsEnumerable", "isPrototypeOf", "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__", "__proto__", "constructor", /* Function.prototype */ "call", "bind", /* Array.prototype */ "concat", "fill", "join", "pop", "push", "reverse", "shift", "slice", "sort", "splice", "unshift", "every", "forEach", "some", "indexOf", "lastIndexOf", "filter", "flat", "flatMap", "reduce", "reduceRight", "map", "find", "findIndex", "includes", "copyWithin", /* Number.prototype */ "toFixed", "toExponential", "toPrecision", /* Boolean.prototype */ /* String.prototype */ "padStart", "padEnd", "repeat", /*"anchor", "big", "bold", "blink", "fixed", "fontcolor", "fontsize", "italics", "link", "small", "strike", "sub", "sup",*/ "charAt", "charCodeAt", "codePointAt", "substr", "substring", "toLowerCase", "toUpperCase", "localeCompare", "toLocaleLowerCase", "toLocaleUpperCase", "trim", "startsWith", "endsWith", "normalize", "trimStart", "trimLeft", "trimEnd", "trimRight", /* Symbol.prototype */ /* Promise.prototype */ "then", "catch", "finally", /* RegExp.prototype */ "compile", "exec", "global", "dotAll", "ignoreCase", "sticky", "unicode", "source", "flags", "test", /* Error.prototype */ "message", /* ArrayBuffer.prototype */ /* Uint8Array.prototype */ "subarray", /* Int8Array.prototype */ /* Uint16Array.prototype */ /* Int16Array.prototype */ /* Uint32Array.prototype */ /* Int32Array.prototype */ /* Float32Array.prototype */ /* Float64Array.prototype */ /* Uint8ClampedArray.prototype */ /* DataView.prototype */ "getInt8", "getUint8", "getInt16", "getUint16", "getInt32", "getUint32", "getFloat32", "getFloat64", "setInt8", "setUint8", "setInt16", "setUint16", "setInt32", "setUint32", "setFloat32", "setFloat64", /* Map.prototype */ "clear", "delete", /* Set.prototype */ "add", /* WeakMap.prototype */ /* WeakSet.prototype */ /* Custom property names */ "a", "b", "c"]

let defaultMethodNames = [/* Object */ "getPrototypeOf", "setPrototypeOf", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames", "getOwnPropertySymbols", "keys", "defineProperty", "defineProperties", "create", "seal", "freeze", "preventExtensions", "isSealed", "isFrozen", "isExtensible", "is", "assign", "values", "entries", "fromEntries", /* Function */ "prototype", /* Array */ "of", "from", "isArray", /* Number */ "isFinite", "isNaN", "isSafeInteger", "parseInt", "parseFloat", "isInteger", /* Boolean */ /* String */ "fromCharCode", "fromCodePoint", "raw", /* Symbol */ "for", "keyFor", /* Promise */ "resolve", "reject", "race", "all", /* RegExp */ /* Error */ /* ArrayBuffer */ "isView", /* Uint8Array */ /* Int8Array */ /* Uint16Array */ /* Int16Array */ /* Uint32Array */ /* Int32Array */ /* Float32Array */ /* Float64Array */ /* Uint8ClampedArray */ /* DataView */ /* Map */ /* Set */ /* WeakMap */ /* WeakSet */ /* Proxy */ "revocable", /* Reflect */ "apply", "construct", "deleteProperty", "get", "has", "ownKeys", "set", /* Math */ "abs", "acos", "asin", "atan", "acosh", "asinh", "atanh", "atan2", "cbrt", "ceil", "clz32", "cos", "cosh", "exp", "expm1", "floor", "fround", "hypot", "log", "log10", "log1p", "log2", "max", "min", "pow", "random", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc", "imul", /* Object.prototype */ "toString", "toLocaleString", "valueOf", "hasOwnProperty", "propertyIsEnumerable", "isPrototypeOf", "__defineGetter__", "__defineSetter__", "__lookupGetter__", "__lookupSetter__", "constructor", /* Function.prototype */ "call", "bind", /* Array.prototype */ "concat", "fill", "join", "pop", "push", "reverse", "shift", "slice", "sort", "splice", "unshift", "every", "forEach", "some", "indexOf", "lastIndexOf", "filter", "flat", "flatMap", "reduce", "reduceRight", "map", "find", "findIndex", "includes", "copyWithin", /* Number.prototype */ "toFixed", "toExponential", "toPrecision", /* Boolean.prototype */ /* String.prototype */ "match", "padStart", "padEnd", "repeat", "replace", "search", "split", /*"anchor", "big", "bold", "blink", "fixed", "fontcolor", "fontsize", "italics", "link", "small", "strike", "sub", "sup",*/ "charAt", "charCodeAt", "codePointAt", "substr", "substring", "toLowerCase", "toUpperCase", "localeCompare", "toLocaleLowerCase", "toLocaleUpperCase", "trim", "startsWith", "endsWith", "normalize", "trimStart", "trimLeft", "trimEnd", "trimRight", /* Symbol.prototype */ /* Promise.prototype */ "then", "catch", "finally", /* RegExp.prototype */ "compile", "exec", "test", /* Error.prototype */ /* ArrayBuffer.prototype */ /* Uint8Array.prototype */ "subarray", /* Int8Array.prototype */ /* Uint16Array.prototype */ /* Int16Array.prototype */ /* Uint32Array.prototype */ /* Int32Array.prototype */ /* Float32Array.prototype */ /* Float64Array.prototype */ /* Uint8ClampedArray.prototype */ /* DataView.prototype */ "getInt8", "getUint8", "getInt16", "getUint16", "getInt32", "getUint32", "getFloat32", "getFloat64", "setInt8", "setUint8", "setInt16", "setUint16", "setInt32", "setUint32", "setFloat32", "setFloat64", /* Map.prototype */ "clear", "delete", /* Set.prototype */ "add", /* WeakMap.prototype */ /* WeakSet.prototype */ /* Custom method names */ "a", "b", "c"]
