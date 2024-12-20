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
    public static let InterestingIntegers: [Int64] = [
        -9223372036854775808, -9223372036854775807,               // Int64 min, mostly for BigInts
        -9007199254740992, -9007199254740991, -9007199254740990,  // Smallest integer value that is still precisely representable by a double
        -4294967297, -4294967296, -4294967295,                    // Negative Uint32 max
        -2147483649, -2147483648, -2147483647,                    // Int32 min
        -1073741824, -536870912, -268435456,                      // -2**32 / {4, 8, 16}
        -65537, -65536, -65535,                                   // -2**16
        -4096, -1024, -256, -128,                                 // Other powers of two
        -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64,         // Numbers around 0
        127, 128, 129,                                            // 2**7
        255, 256, 257,                                            // 2**8
        512, 1000, 1024, 4096, 10000,                             // Misc numbers
        65535, 65536, 65537,                                      // 2**16
        268435439, 268435440, 268435441,                          // V8 String kMaxLength (32-bit)
        536870887, 536870888, 536870889,                          // V8 String kMaxLength (64-bit)
        268435456, 536870912, 1073741824,                         // 2**32 / {4, 8, 16}
        1073741823, 1073741824, 1073741825,                       // 2**30
        2147483647, 2147483648, 2147483649,                       // Int32 max
        4294967295, 4294967296, 4294967297,                       // Uint32 max
        9007199254740990, 9007199254740991, 9007199254740992,     // Biggest integer value that is still precisely representable by a double
        9223372036854775807,                                      // Int64 max, mostly for BigInts
    ]

    static let wellKnownSymbols = ["iterator", "asyncIterator", "match", "matchAll", "replace", "search", "split", "hasInstance", "isConcatSpreadable", "unscopables", "species", "toPrimitive", "toStringTag", "dispose", "asyncDispose"]

    public let interestingIntegers = InterestingIntegers

    // Double values that are more likely to trigger edge-cases.
    public let interestingFloats = [-Double.infinity, -Double.greatestFiniteMagnitude, -1e-15, -1e12, -1e9, -1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -Double.ulpOfOne, -Double.leastNormalMagnitude, -0.0, 0.0, Double.leastNormalMagnitude, Double.ulpOfOne, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6, 1e9, 1e12, 1e-15, Double.greatestFiniteMagnitude, Double.infinity, Double.nan]

    // TODO more?
    public let interestingStrings = jsTypeNames

    // Copied from
    // https://cs.chromium.org/chromium/src/testing/libfuzzer/fuzzers/dicts/regexp.dict
    public let interestingRegExps = [
        // These do *not* work with unicode or unicodeSets
        (pattern: #"a\q"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{12,3b"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{z}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[z-\d]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{z}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(x)(x)(x)(x)(x)(x)(x)(x)(x)(x)\11"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\111]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\c!"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\11a]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\c!]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\c~]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\[\]\{\}\(\)\%\^\#\ "#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\[\]\{\}\(\)\%\^\#\ ]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\118"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\00011]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\c~"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{,}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[-123]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[-\xf0\x9f\x92\xa9]+"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{,}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{12,"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?!a)?a"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\111"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?!a)?a\1"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\1111]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{12,3b"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\c1]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?=a){0,10}a"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\q"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{12z}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\011"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\d-z]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\011]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\8"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\11a"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\118]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\1112"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{12,"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\d-\d]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\11"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(x)(x)(x)\4*"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?:(?=a))a\1"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\c_"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"a{"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(x)(x)(x)\4"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\c"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\x3z"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\c_]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{1z}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?=a){1,10}a"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\1111"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\u003z"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[\11]"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"\9"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"{}"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"(?=a){9,10}a"#, incompatibleFlags:  .unicode | .unicodeSets),
        (pattern: #"[a-b-c]"#, incompatibleFlags:  .unicode | .unicodeSets),

        // These work with all flags
        (pattern: #"(x)(x)(x)\1*"#, incompatibleFlags:  .empty),
        (pattern: #"\x01"#, incompatibleFlags:  .empty),
        (pattern: #"(?: foo )"#, incompatibleFlags:  .empty),
        (pattern: #"(ab|cde)"#, incompatibleFlags:  .empty),
        (pattern: #"foo|(bar|baz)|quux"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a*)*"#, incompatibleFlags:  .empty),
        (pattern: #"a{0,1}?"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a+)?"#, incompatibleFlags:  .empty),
        (pattern: #"a$"#, incompatibleFlags:  .empty),
        (pattern: #"a(?=b)"#, incompatibleFlags:  .empty),
        (pattern: #"foo[z]*"#, incompatibleFlags:  .empty),
        (pattern: #"\u{12345}\u{23456}"#, incompatibleFlags:  .empty),
        (pattern: #"(?!(a))\1"#, incompatibleFlags:  .empty),
        (pattern: #"abc+?"#, incompatibleFlags:  .empty),
        (pattern: #"a*b"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a?)*"#, incompatibleFlags:  .empty),
        (pattern: #"\xf0\x9f\x92\xa9"#, incompatibleFlags:  .empty),
        (pattern: #"a{1,2}?"#, incompatibleFlags:  .empty),
        (pattern: #"a\n"#, incompatibleFlags:  .empty),
        (pattern: #"\P{Decimal_Number}"#, incompatibleFlags:  .empty),
        (pattern: #"(?=)"#, incompatibleFlags:  .empty),
        (pattern: #"\1(a)"#, incompatibleFlags:  .empty),
        (pattern: #"."#, incompatibleFlags:  .empty),
        (pattern: #"()"#, incompatibleFlags:  .empty),
        (pattern: #"(a)"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a{5,1000000}){3,1000000}"#, incompatibleFlags:  .empty),
        (pattern: #"a\Sc"#, incompatibleFlags:  .empty),
        (pattern: #"a(?=b)c"#, incompatibleFlags:  .empty),
        (pattern: #"a{0}"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a*)+"#, incompatibleFlags:  .empty),
        (pattern: #"\ud808\udf45*"#, incompatibleFlags:  .empty),
        (pattern: #"a\w"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a+)*"#, incompatibleFlags:  .empty),
        (pattern: #"a(?:b)"#, incompatibleFlags:  .empty),
        (pattern: #"(?<=a)"#, incompatibleFlags:  .empty),
        (pattern: #"(x)(x)(x)\3"#, incompatibleFlags:  .empty),
        (pattern: #"foo(?<=bar)baz"#, incompatibleFlags:  .empty),
        (pattern: #"\xe2\x81\xa3"#, incompatibleFlags:  .empty),
        (pattern: #"ab\b\d\bcd"#, incompatibleFlags:  .empty),
        (pattern: #"[\ca]"#, incompatibleFlags:  .empty),
        (pattern: #"[\xf0\x9f\x92\xa9-\xf4\x8f\xbf\xbf]"#, incompatibleFlags:  .empty),
        (pattern: #"\p{Script_Extensions=Greek}"#, incompatibleFlags:  .empty),
        (pattern: #"\cj\cJ\ci\cI\ck\cK"#, incompatibleFlags:  .empty),
        (pattern: #"a\fb\nc\rd\te\vf"#, incompatibleFlags:  .empty),
        (pattern: #"\p{General_Category=Decimal_Number}"#, incompatibleFlags:  .empty),
        (pattern: #"\u{12345}"#, incompatibleFlags:  .empty),
        (pattern: #"a\b!"#, incompatibleFlags:  .empty),
        (pattern: #"a[^a]"#, incompatibleFlags:  .empty),
        (pattern: #"\1\2(a(?:\1(b\1\2))\2)\1"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab)+"#, incompatibleFlags:  .empty),
        (pattern: #"[^123]"#, incompatibleFlags:  .empty),
        (pattern: #"a(?!b)"#, incompatibleFlags:  .empty),
        (pattern: #"a\Bb"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab)?"#, incompatibleFlags:  .empty),
        (pattern: #"(?<a>)"#, incompatibleFlags:  .empty),
        (pattern: #"(?<!)"#, incompatibleFlags:  .empty),
        (pattern: #"a."#, incompatibleFlags:  .empty),
        (pattern: #"[]"#, incompatibleFlags:  .empty),
        (pattern: #"a\S"#, incompatibleFlags:  .empty),
        (pattern: #"abc"#, incompatibleFlags:  .empty),
        (pattern: #"(?<!a)"#, incompatibleFlags:  .empty),
        (pattern: #"\x60"#, incompatibleFlags:  .empty),
        (pattern: #"[\p{Script_Extensions=Mongolian}&&\p{Number}]"#, incompatibleFlags:  .empty),
        (pattern: #"a\nb\bc"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab)|cde"#, incompatibleFlags:  .empty),
        (pattern: #"^"#, incompatibleFlags:  .empty),
        (pattern: #"a\W"#, incompatibleFlags:  .empty),
        (pattern: #"a"#, incompatibleFlags:  .empty),
        (pattern: #"a[a]"#, incompatibleFlags:  .empty),
        (pattern: #"(x)(x)(x)\1"#, incompatibleFlags:  .empty),
        (pattern: #"[\cA]"#, incompatibleFlags:  .empty),
        (pattern: #"(ab)\1"#, incompatibleFlags:  .empty),
        (pattern: #"a(?=bbb|bb)c"#, incompatibleFlags:  .empty),
        (pattern: #"(x)(x)(x)(x)(x)(x)(x)(x)(x)(x)\10"#, incompatibleFlags:  .empty),
        (pattern: #"\P{sc=Greek}"#, incompatibleFlags:  .empty),
        (pattern: #"foo(?!bar)baz"#, incompatibleFlags:  .empty),
        (pattern: #"xyz??"#, incompatibleFlags:  .empty),
        (pattern: #"a[bc]d"#, incompatibleFlags:  .empty),
        (pattern: #"a*?"#, incompatibleFlags:  .empty),
        (pattern: #"((\xed\xa0\x80))\x02"#, incompatibleFlags:  .empty),
        (pattern: #"a+"#, incompatibleFlags:  .empty),
        (pattern: #"\P{scx=Greek}"#, incompatibleFlags:  .empty),
        (pattern: #"(?<=)"#, incompatibleFlags:  .empty),
        (pattern: #"(?:foo)"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{1,}?"#, incompatibleFlags:  .empty),
        (pattern: #"(a)\1"#, incompatibleFlags:  .empty),
        (pattern: #"a[a-z]"#, incompatibleFlags:  .empty),
        (pattern: #"\p{Nd}"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab)"#, incompatibleFlags:  .empty),
        (pattern: #"a+b|c"#, incompatibleFlags:  .empty),
        (pattern: #"(ab|cde)\1"#, incompatibleFlags:  .empty),
        (pattern: #"(\xed\xb0\x80)\x01"#, incompatibleFlags:  .empty),
        (pattern: #"((((.).).).)"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a?)+"#, incompatibleFlags:  .empty),
        (pattern: #"(a\1)"#, incompatibleFlags:  .empty),
        (pattern: #"\P{Any}"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{93}"#, incompatibleFlags:  .empty),
        (pattern: #"\x0f"#, incompatibleFlags:  .empty),
        (pattern: #"(ab)"#, incompatibleFlags:  .empty),
        (pattern: #"\w|\d"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{1,32}"#, incompatibleFlags:  .empty),
        (pattern: #"[x\dz]"#, incompatibleFlags:  .empty),
        (pattern: #"\xed\xa0\x80"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{1,}"#, incompatibleFlags:  .empty),
        (pattern: #"\p{gc=Nd}"#, incompatibleFlags:  .empty),
        (pattern: #"\xed\xb0\x80"#, incompatibleFlags:  .empty),
        (pattern: #"[\0]"#, incompatibleFlags:  .empty),
        (pattern: #"^xxx$"#, incompatibleFlags:  .empty),
        (pattern: #"a?"#, incompatibleFlags:  .empty),
        (pattern: #"a\s"#, incompatibleFlags:  .empty),
        (pattern: #"a+?"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{0,1}?"#, incompatibleFlags:  .empty),
        (pattern: #"(\1a)"#, incompatibleFlags:  .empty),
        (pattern: #"a(?!bbb|bb)c"#, incompatibleFlags:  .empty),
        (pattern: #"\p{Script=Greek}"#, incompatibleFlags:  .empty),
        (pattern: #"\u0060"#, incompatibleFlags:  .empty),
        (pattern: #"[xyz]"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a+){0,0}"#, incompatibleFlags:  .empty),
        (pattern: #"(\2)(\1)"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{1,32}?"#, incompatibleFlags:  .empty),
        (pattern: #"(?<a>.)"#, incompatibleFlags:  .empty),
        (pattern: #"[\cz]"#, incompatibleFlags:  .empty),
        (pattern: #"(x)(x)(x)\3*"#, incompatibleFlags:  .empty),
        (pattern: #"foo(?<!bar)baz"#, incompatibleFlags:  .empty),
        (pattern: #"abc+"#, incompatibleFlags:  .empty),
        (pattern: #"foo(?=bar)baz"#, incompatibleFlags:  .empty),
        (pattern: #"a|bc"#, incompatibleFlags:  .empty),
        (pattern: #"abc|def"#, incompatibleFlags:  .empty),
        (pattern: #"a*b|c"#, incompatibleFlags:  .empty),
        (pattern: #"(x)(x)(x)\2"#, incompatibleFlags:  .empty),
        (pattern: #"(?<a>.)\k<a>"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a+)+"#, incompatibleFlags:  .empty),
        (pattern: #"(?=.)"#, incompatibleFlags:  .empty),
        (pattern: #"\p{Changes_When_NFKC_Casefolded}"#, incompatibleFlags:  .empty),
        (pattern: #"a\sc"#, incompatibleFlags:  .empty),
        (pattern: #"a||bc"#, incompatibleFlags:  .empty),
        (pattern: #"a+b"#, incompatibleFlags:  .empty),
        (pattern: #"[\cZ]"#, incompatibleFlags:  .empty),
        (pattern: #"a|b"#, incompatibleFlags:  .empty),
        (pattern: #"\u0034"#, incompatibleFlags:  .empty),
        (pattern: #"\cA"#, incompatibleFlags:  .empty),
        (pattern: #"ab|c"#, incompatibleFlags:  .empty),
        (pattern: #"abc|def|ghi"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab|cde)"#, incompatibleFlags:  .empty),
        (pattern: #"xyz?"#, incompatibleFlags:  .empty),
        (pattern: #"[a-zA-Z0-9]"#, incompatibleFlags:  .empty),
        (pattern: #"(?:a?)?"#, incompatibleFlags:  .empty),
        (pattern: #"xyz{0,1}"#, incompatibleFlags:  .empty),
        (pattern: #"a\D"#, incompatibleFlags:  .empty),
        (pattern: #"(?!\1(a\1)\1)\1"#, incompatibleFlags:  .empty),
        (pattern: #"a\bc"#, incompatibleFlags:  .empty),
        (pattern: #"\P{gc=Decimal_Number}"#, incompatibleFlags:  .empty),
        (pattern: #"\b"#, incompatibleFlags:  .empty),
        (pattern: #"[x]"#, incompatibleFlags:  .empty),
        (pattern: #"(?:ab){4,7}"#, incompatibleFlags:  .empty),
        (pattern: #"a??"#, incompatibleFlags:  .empty),
        (pattern: #"(?<a>(?<b>(?<c>(?<d>.).).).)"#, incompatibleFlags:  .empty),
        (pattern: #"[\xe2\x81\xa3]"#, incompatibleFlags:  .empty),
    ]

    public let interestingRegExpQuantifiers = ["*", "+", "?"]

    public let intType = ILType.integer
    public let bigIntType = ILType.bigint
    public let floatType = ILType.float
    public let booleanType = ILType.boolean
    public let regExpType = ILType.jsRegExp
    public let stringType = ILType.jsString
    public let emptyObjectType = ILType.object()
    public let arrayType = ILType.jsArray
    public let argumentsType = ILType.jsArguments
    public let generatorType = ILType.jsGenerator
    public let promiseType = ILType.jsPromise

    /// Identifiers that should be used for custom properties and methods.
    public static let CustomPropertyNames = ["a", "b", "c", "d", "e", "f", "g", "h"]
    public static let CustomMethodNames = ["m", "n", "o", "p", "valueOf", "toString"]

    public private(set) var builtins = Set<String>()
    public let customProperties = Set<String>(CustomPropertyNames)
    public let customMethods = Set<String>(CustomMethodNames)
    public private(set) var builtinProperties = Set<String>()
    public private(set) var builtinMethods = Set<String>()

    private var builtinTypes: [String: ILType] = [:]
    private var groups: [String: ObjectGroup] = [:]
    private var producingMethods: [ILType: [(group: String, method: String)]] = [:]
    private var producingProperties: [ILType: [(group: String, property: String)]] = [:]
    private var subtypes: [ILType: [ILType]] = [:]

    public init(additionalBuiltins: [String: ILType] = [:], additionalObjectGroups: [ObjectGroup] = []) {
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
        registerObjectGroup(.jsArrays)
        registerObjectGroup(.jsArguments)
        registerObjectGroup(.jsGenerators)
        registerObjectGroup(.jsPromises)
        registerObjectGroup(.jsRegExps)
        registerObjectGroup(.jsFunctions)
        registerObjectGroup(.jsSymbols)
        registerObjectGroup(.jsMaps)
        registerObjectGroup(.jsWeakMaps)
        registerObjectGroup(.jsSets)
        registerObjectGroup(.jsWeakSets)
        registerObjectGroup(.jsWeakRefs)
        registerObjectGroup(.jsFinalizationRegistrys)
        registerObjectGroup(.jsArrayBuffers)
        registerObjectGroup(.jsSharedArrayBuffers)
        for variant in ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"] {
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
        registerObjectGroup(.jsDate)
        registerObjectGroup(.jsDateConstructor)
        registerObjectGroup(.jsJSONObject)
        registerObjectGroup(.jsReflectObject)
        registerObjectGroup(.jsArrayBufferConstructor)
        registerObjectGroup(.jsSharedArrayBufferConstructor)
        for variant in ["Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "AggregateError", "URIError", "SuppressedError"] {
            registerObjectGroup(.jsError(variant))
        }
        registerObjectGroup(.jsWasmGlobal)
        registerObjectGroup(.jsWasmMemory)
        registerObjectGroup(.wasmTable)
        registerObjectGroup(.jsWasmTag)

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
        for variant in ["Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "AggregateError", "URIError", "SuppressedError"] {
            registerBuiltin(variant, ofType: .jsErrorConstructor(variant))
        }
        registerBuiltin("ArrayBuffer", ofType: .jsArrayBufferConstructor)
        registerBuiltin("SharedArrayBuffer", ofType: .jsSharedArrayBufferConstructor)
        for variant in ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"] {
            registerBuiltin(variant, ofType: .jsTypedArrayConstructor(variant))
        }
        registerBuiltin("DataView", ofType: .jsDataViewConstructor)
        registerBuiltin("Date", ofType: .jsDateConstructor)
        registerBuiltin("Promise", ofType: .jsPromiseConstructor)
        registerBuiltin("Proxy", ofType: .jsProxyConstructor)
        registerBuiltin("Map", ofType: .jsMapConstructor)
        registerBuiltin("WeakMap", ofType: .jsWeakMapConstructor)
        registerBuiltin("Set", ofType: .jsSetConstructor)
        registerBuiltin("WeakSet", ofType: .jsWeakSetConstructor)
        registerBuiltin("WeakRef", ofType: .jsWeakRefConstructor)
        registerBuiltin("FinalizationRegistry", ofType: .jsFinalizationRegistryConstructor)
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

        for (builtin, type) in additionalBuiltins {
            registerBuiltin(builtin, ofType: type)
        }

        // Add some well-known builtin properties and methods.
        builtinProperties.insert("__proto__")
        builtinProperties.insert("constructor")
        builtinMethods.insert("valueOf")
        builtinMethods.insert("toString")
    }

    override func initialize() {
        // Ensure that some of the common property/method names exist.
        assert(builtinProperties.contains("__proto__"))
        assert(builtinProperties.contains("constructor"))
        assert(builtinMethods.contains("valueOf"))
        assert(builtinMethods.contains("toString"))

        checkConstructorAvailability()

        // Log detailed information about the environment here so users are aware of it and can modify things if they like.
        logger.info("Initialized static JS environment model")
        logger.info("Have \(builtins.count) available builtins: \(builtins)")
        logger.info("Have \(groups.count) different object groups: \(groups.keys)")
        logger.info("Have \(builtinProperties.count) builtin property names: \(builtinProperties)")
        logger.info("Have \(builtinMethods.count) builtin method names: \(builtinMethods)")
        logger.info("Have \(customProperties.count) custom property names: \(customProperties)")
        logger.info("Have \(customMethods.count) custom method names: \(customMethods)")
    }

    func checkConstructorAvailability() {
        logger.info("Checking constructor availability...")
        // These constructors return types that are well-known instead of .object types.
        let knownExceptions = [
            "Boolean",        // returns .boolean
            "Number",         // returns .number
            "Object",         // returns plain .object
            "Proxy",          // returns .anything
        ]
        for builtin in builtins where type(ofBuiltin: builtin).Is(.constructor()) {
            if knownExceptions.contains(builtin) { continue }
            if !hasGroup(builtin) { logger.warning("Missing group info for constructable \(builtin)")}
            if type(ofBuiltin: builtin).signature == nil {
                logger.warning("Missing signature for builtin \(builtin)")
            } else {
                if !type(ofBuiltin: builtin).signature!.outputType.Is(.object(ofGroup: builtin)) {
                    logger.warning("Signature for builtin \(builtin) is mismatching")
                }
            }

        }
        logger.info("Done checking constructor availability...")
    }

    public func hasBuiltin(_ name: String) -> Bool {
        return self.builtinTypes.keys.contains(name)
    }

    public func hasGroup(_ name: String) -> Bool {
        return self.groups.keys.contains(name)
    }

    private func addProducingMethod(forType type: ILType, by method: String, on group: String) {
        if producingMethods[type] == nil {
        producingMethods[type] = []
        }
        producingMethods[type]! += [(group: group, method: method)]
    }

    @discardableResult private func addProducingProperty(forType type: ILType, by property: String, on group: String) -> ILType {
        let actualType: ILType
        if type.Is(.constructor()) {
            actualType = type.signature!.outputType
        } else {
            actualType = type
        }
        if producingProperties[actualType] == nil {
            producingProperties[actualType] = []
        }
        producingProperties[actualType]! += [(group: group, property: property)]
        return actualType
    }

    public func registerObjectGroup(_ group: ObjectGroup) {
        assert(groups[group.name] == nil)
        groups[group.name] = group
        builtinProperties.formUnion(group.properties.keys)
        builtinMethods.formUnion(group.methods.keys)

        //
        // Step 1: Initialize `subtypes`
        //
        subtypes[group.instanceType] = [group.instanceType]
        var current = group
        while let parent = current.parent {
            // Parent groups are supposed to be defined before child groups
            current = groups[parent]!
            subtypes[current.instanceType]! += [group.instanceType]
        }

        //
        // Step 2: Initialize `producingMethods`
        //
        for overloads in group.methods {
            for method in overloads.value {
                assert(method.outputType != .nothing,
                  "Method \(overloads.key) in group \(group.name) has .nothing as outputType")
                if method.outputType == .undefined {
                    continue
                }
                let type = method.outputType
                addProducingMethod(forType: type, by: overloads.key, on: group.name)
                if let groupName = type.group {
                    if var current = groups[groupName] {
                        while let parent = current.parent {
                            current = groups[parent]!
                            addProducingMethod(forType: current.instanceType, by: overloads.key, on: group.name)
                        }
                    }
                }
            }
        }

        //
        // Step 3: Initialize `producingProperties`
        //
        for property in group.properties {
            let producedType = addProducingProperty(forType: property.value, by: property.key, on: group.name)
            if let groupName = producedType.group {
                if var current = groups[groupName] {
                    while let parent = current.parent {
                        current = groups[parent]!
                        addProducingProperty(forType: current.instanceType, by: property.key, on: group.name)
                    }
                }
            }
        }
    }

    public func registerBuiltin(_ name: String, ofType type: ILType) {
        assert(builtinTypes[name] == nil)
        builtinTypes[name] = type
        builtins.insert(name)

        let producedType = addProducingProperty(forType: type, by: name, on: "")
            if let groupName = producedType.group {
                if var current = groups[groupName] {
                    while let parent = current.parent {
                        current = groups[parent]!
                        addProducingProperty(forType: current.instanceType, by: name, on: "")
                    }
                }
            }
    }

    public func type(ofBuiltin builtinName: String) -> ILType {
        if let type = builtinTypes[builtinName] {
            return type
        } else {
            logger.warning("Missing type for builtin \(builtinName)")
            return .anything
        }
    }

    public func type (ofGroup groupName: String) -> ILType {
        if let type = groups[groupName]?.instanceType {
            return type
        } else {
            logger.warning("Missing type for group \(groupName)")
            return .anything
        }
    }

    public func type(ofProperty propertyName: String, on baseType: ILType) -> ILType {
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

        return .anything
    }

    public func signatures(ofMethod methodName: String, on baseType: ILType) -> [Signature] {
        if let groupName = baseType.group {
            if let group = groups[groupName] {
                if let signatures = group.methods[methodName] {
                    return signatures
                }
            } else {
                // This shouldn't happen, probably forgot to register the object group
                logger.warning("No type information for object group \(groupName) available")
            }
        }

        return [.forUnknownFunction]
    }

    public func getProducingMethods(ofType type: ILType) -> [(group: String, method: String)] {
        guard let array = producingMethods[type] else {
            return []
        }
        return array
    }

    public func getProducingProperties(ofType type: ILType) -> [(group: String, property: String)] {
        guard let array = producingProperties[type] else {
            return []
        }
        return array
    }

    public func getSubtypes(ofType type: ILType) -> [ILType] {
        guard let array = subtypes[type] else {
            return [type]
        }
        return array
    }

    public func isSubtype(_ type: ILType, of parent: ILType) -> Bool {
        return getSubtypes(ofType: parent).reduce(false) {
            $0 || type.Is($1)
        }
    }
}

/// A struct to encapsulate property and method type information for a group of related objects.
public struct ObjectGroup {
    public let name: String
    public let properties: [String: ILType]
    public let methods: [String: [Signature]]
    public let parent: String?

    /// The type of instances of this group.
    public let instanceType: ILType

    public init(name: String, instanceType: ILType, properties: [String: ILType], overloads: [String: [Signature]], parent: String? = nil) {
        self.name = name
        self.instanceType = instanceType
        self.properties = properties
        self.methods = overloads
        self.parent = parent

        // We could also only assert set inclusion here to implement "shared" properties/methods.
        // (which would then need some kind of fallback ObjectGroup that is consulted by the
        // type lookup routines if the real group doesn't have the requested information).
        assert(instanceType.group == name, "group name mismatch for group \(name)")
        assert(instanceType.properties == Set(properties.keys), "inconsistent property information for object group \(name): \(Set(properties.keys).symmetricDifference(instanceType.properties))")
        assert(instanceType.methods == Set(methods.keys), "inconsistent method information for object group \(name): \(Set(methods.keys).symmetricDifference(instanceType.methods))")
    }

    public init(name: String, instanceType: ILType, properties: [String: ILType], methods: [String: Signature], parent: String? = nil) {
       self.init(name: name, instanceType: instanceType, properties: properties, overloads: methods.mapValues({[$0]}), parent: parent)
    }

}

// Types of builtin objects, functions, and values.
//
// Most objects have a number of common fields, such as .constructor or the various methods defined on the object prototype.
// We do not model these here since it's usually relatively uninteresting to use these always-existing fields. __proto__ is the exception,
// and so for that we have special code generators that load or modify an object's prototype. Additionally, mutators like the
// ExplorationMutator will make use of __proto__ and other common fields.
//
// As such, one rule of thumb here is that each object type should only contain the properties and methods that are specific to this type
// and not shared with other, unrelated objects.
// Another rule of thumb is that the type information should either be complete or missing entirely. I.e. it is better to have a field be .anything
// or .anythingObject instead of only specifying a subset of its properties for example. Partial type information is usually bad as
// only the available parts will be used by e.g. CodeGenerators while for example the ExplorationMutator will believe that type information is
// complete and so it does not need to explore this value.
//
// Note, these must be kept in sync with the ObjectGroups below (in particular the properties and methods). To help with that, the ObjectGroup
// constructor asserts that the type information is consistent between instance type and the ObjectGroup.
public extension ILType {
    /// Type of a string in JavaScript.
    /// A JS string is both a string and an object on which methods can be called.
    static let jsString = ILType.string + ILType.iterable + ILType.object(ofGroup: "String", withProperties: ["length"], withMethods: ["charAt", "charCodeAt", "codePointAt", "concat", "includes", "endsWith", "indexOf", "lastIndexOf", "match", "matchAll", "padEnd", "padStart", "normalize", "repeat", "replace", "replaceAll", "search", "slice", "split", "startsWith", "substring", "trim", "trimStart", "trimLeft", "trimEnd", "trimRight" ,"toUpperCase", "toLowerCase", "localeCompare"])

    /// Type of a regular expression in JavaScript.
    /// A JS RegExp is both a RegExp and an object on which methods can be called.
    static let jsRegExp = ILType.regexp + ILType.object(ofGroup: "RegExp", withProperties: ["flags", "dotAll", "global", "ignoreCase", "multiline", "source", "sticky", "unicode"], withMethods: ["compile", "exec", "test"])

    /// Type of a JavaScript Symbol.
    static let jsSymbol = ILType.object(ofGroup: "Symbol", withProperties: ["description"])

    /// Type of a JavaScript array.
    static let jsArray = ILType.iterable + ILType.object(ofGroup: "Array", withProperties: ["length"], withMethods: ["at", "concat", "copyWithin", "fill", "find", "findIndex", "findLast", "findLastIndex", "pop", "push", "reverse", "shift", "unshift", "slice", "sort", "splice", "includes", "indexOf", "keys", "entries", "forEach", "filter", "map", "every", "some", "reduce", "reduceRight", "toString", "toLocaleString", "toReversed", "toSorted", "toSpliced", "with", "join", "lastIndexOf", "values", "flat", "flatMap"])

    /// Type of a function's arguments object.
    static let jsArguments = ILType.iterable + ILType.object(ofGroup: "Arguments", withProperties: ["length", "callee"])

    /// Type of a JavaScript generator object.
    static let jsGenerator = ILType.iterable + ILType.object(ofGroup: "Generator", withMethods: ["next", "return", "throw"])

    /// Type of a JavaScript Promise object.
    static let jsPromise = ILType.object(ofGroup: "Promise", withMethods: ["catch", "finally", "then"])

    /// Type of a JavaScript Map object.
    static let jsMap = ILType.iterable + ILType.object(ofGroup: "Map", withProperties: ["size"], withMethods: ["clear", "delete", "entries", "forEach", "get", "has", "keys", "set", "values"])

    /// Type of a JavaScript WeakMap object.
    static let jsWeakMap = ILType.object(ofGroup: "WeakMap", withMethods: ["delete", "get", "has", "set"])

    /// Type of a JavaScript Set object.
    static let jsSet = ILType.iterable + ILType.object(ofGroup: "Set", withProperties: ["size"], withMethods: ["add", "clear", "delete", "entries", "forEach", "has", "keys", "values"])

    /// Type of a JavaScript WeakSet object.
    static let jsWeakSet = ILType.object(ofGroup: "WeakSet", withMethods: ["add", "delete", "has"])

    /// Type of a JavaScript WeakRef object.
    static let jsWeakRef = ILType.object(ofGroup: "WeakRef", withMethods: ["deref"])

    /// Type of a JavaScript FinalizationRegistry object.
    static let jsFinalizationRegistry = ILType.object(ofGroup: "FinalizationRegistry", withMethods: ["register", "unregister"])

    /// Type of a JavaScript ArrayBuffer object.
    static let jsArrayBuffer = ILType.object(ofGroup: "ArrayBuffer", withProperties: ["byteLength", "maxByteLength", "resizable"], withMethods: ["resize", "slice", "transfer"])

    /// Type of a JavaScript SharedArrayBuffer object.
    static let jsSharedArrayBuffer = ILType.object(ofGroup: "SharedArrayBuffer", withProperties: ["byteLength", "maxByteLength", "growable"], withMethods: ["grow", "slice"])

    /// Type of a JavaScript DataView object.
    static let jsDataView = ILType.object(ofGroup: "DataView", withProperties: ["buffer", "byteLength", "byteOffset"], withMethods: ["getInt8", "getUint8", "getInt16", "getUint16", "getInt32", "getUint32", "getFloat32", "getFloat64", "getBigInt64", "setInt8", "setUint8", "setInt16", "setUint16", "setInt32", "setUint32", "setFloat32", "setFloat64", "setBigInt64"])

    /// Type of a JavaScript TypedArray object of the given variant.
    static func jsTypedArray(_ variant: String) -> ILType {
        return .iterable + .object(ofGroup: variant, withProperties: ["buffer", "byteOffset", "byteLength", "length"], withMethods: ["at", "copyWithin", "fill", "find", "findIndex", "findLast", "findLastIndex", "reverse", "slice", "sort", "includes", "indexOf", "keys", "entries", "forEach", "filter", "map", "every", "set", "some", "subarray", "reduce", "reduceRight", "join", "lastIndexOf", "values", "toLocaleString", "toString", "toReversed", "toSorted", "with"])
    }

    /// Type of a JavaScript function.
    /// A JavaScript function is also constructors. Moreover, it is also an object as it has a number of properties and methods.
    static func jsFunction(_ signature: Signature = Signature.forUnknownFunction) -> ILType {
        return .constructor(signature) + .function(signature) + .object(ofGroup: "Function", withProperties: ["prototype", "length", "arguments", "caller", "name"], withMethods: ["apply", "bind", "call"])
    }

    /// Type of the JavaScript Object constructor builtin.
    static let jsObjectConstructor = .functionAndConstructor([.anything...] => .object()) + .object(ofGroup: "ObjectConstructor", withProperties: ["prototype"], withMethods: ["assign", "fromEntries", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames", "getOwnPropertySymbols", "is", "preventExtensions", "seal", "create", "defineProperties", "defineProperty", "freeze", "getPrototypeOf", "setPrototypeOf", "isExtensible", "isFrozen", "isSealed", "keys", "entries", "values"])

    /// Type of the JavaScript Array constructor builtin.
    static let jsArrayConstructor = .functionAndConstructor([.integer] => .jsArray) + .object(ofGroup: "ArrayConstructor", withProperties: ["prototype"], withMethods: ["from", "of", "isArray"])

    /// Type of the JavaScript Function constructor builtin.
    static let jsFunctionConstructor = ILType.constructor([.string] => .jsFunction(Signature.forUnknownFunction))

    /// Type of the JavaScript String constructor builtin.
    static let jsStringConstructor = ILType.functionAndConstructor([.anything] => .jsString) + .object(ofGroup: "StringConstructor", withProperties: ["prototype"], withMethods: ["fromCharCode", "fromCodePoint", "raw"])

    /// Type of the JavaScript Boolean constructor builtin.
    static let jsBooleanConstructor = ILType.functionAndConstructor([.anything] => .boolean) + .object(ofGroup: "BooleanConstructor", withProperties: ["prototype"], withMethods: [])

    /// Type of the JavaScript Number constructor builtin.
    static let jsNumberConstructor = ILType.functionAndConstructor([.anything] => .number) + .object(ofGroup: "NumberConstructor", withProperties: ["prototype", "EPSILON", "MAX_SAFE_INTEGER", "MAX_VALUE", "MIN_SAFE_INTEGER", "MIN_VALUE", "NaN", "NEGATIVE_INFINITY", "POSITIVE_INFINITY"], withMethods: ["isNaN", "isFinite", "isInteger", "isSafeInteger"])

    /// Type of the JavaScript Symbol constructor builtin.
    static let jsSymbolConstructor = ILType.function([.string] => .jsSymbol) + .object(ofGroup: "SymbolConstructor", withProperties: JavaScriptEnvironment.wellKnownSymbols, withMethods: ["for", "keyFor"])

    /// Type of the JavaScript BigInt constructor builtin.
    static let jsBigIntConstructor = ILType.function([.number] => .bigint) + .object(ofGroup: "BigIntConstructor", withProperties: ["prototype"], withMethods: ["asIntN", "asUintN"])

    /// Type of the JavaScript RegExp constructor builtin.
    static let jsRegExpConstructor = ILType.jsFunction([.string] => .jsRegExp)

    /// Type of a JavaScript Error object of the given variant.
    static func jsError(_ variant: String) -> ILType {
       return .object(ofGroup: variant, withProperties: ["message", "name", "cause", "stack"], withMethods: ["toString"])
    }

    /// Type of the JavaScript Error constructor builtin
    static func jsErrorConstructor(_ variant: String) -> ILType {
        return .functionAndConstructor([.opt(.string)] => .jsError(variant))
    }

    /// Type of the JavaScript ArrayBuffer constructor builtin.
    static let jsArrayBufferConstructor = ILType.constructor([.integer, .opt(.object())] => .jsArrayBuffer) + .object(ofGroup: "ArrayBufferConstructor", withProperties: ["prototype"], withMethods: ["isView"])

    /// Type of the JavaScript SharedArrayBuffer constructor builtin.
    static let jsSharedArrayBufferConstructor = ILType.constructor([.integer, .opt(.object())] => .jsSharedArrayBuffer) + .object(ofGroup: "SharedArrayBufferConstructor", withProperties: ["prototype"], withMethods: [])

    /// Type of a JavaScript TypedArray constructor builtin.
    static func jsTypedArrayConstructor(_ variant: String) -> ILType {
        // TODO Also allow SharedArrayBuffers for first argument
        return .constructor([.oneof(.integer, .jsArrayBuffer), .opt(.integer), .opt(.integer)] => .jsTypedArray(variant))
    }

    /// Type of the JavaScript DataView constructor builtin. (TODO Also allow SharedArrayBuffers for first argument)
    static let jsDataViewConstructor = ILType.constructor([.plain(.jsArrayBuffer), .opt(.integer), .opt(.integer)] => .jsDataView)

    /// Type of the JavaScript Promise constructor builtin.
    static let jsPromiseConstructor = ILType.constructor([.function()] => .jsPromise) + .object(ofGroup: "PromiseConstructor", withProperties: ["prototype"], withMethods: ["resolve", "reject", "all", "any", "race", "allSettled"])

    /// Type of the JavaScript Proxy constructor builtin.
    static let jsProxyConstructor = ILType.constructor([.object(), .object()] => .anything)

    /// Type of the JavaScript Map constructor builtin.
    static let jsMapConstructor = ILType.constructor([.object()] => .jsMap)

    /// Type of the JavaScript WeakMap constructor builtin.
    static let jsWeakMapConstructor = ILType.constructor([.object()] => .jsWeakMap)

    /// Type of the JavaScript Set constructor builtin.
    static let jsSetConstructor = ILType.constructor([.object()] => .jsSet)

    /// Type of the JavaScript WeakSet constructor builtin.
    static let jsWeakSetConstructor = ILType.constructor([.object()] => .jsWeakSet)

    /// Type of the JavaScript WeakRef constructor builtin.
    static let jsWeakRefConstructor = ILType.constructor([.object()] => .jsWeakRef)

    /// Type of the JavaScript FinalizationRegistry constructor builtin.
    static let jsFinalizationRegistryConstructor = ILType.constructor([.function()] => .jsFinalizationRegistry)

    /// Type of the JavaScript Math constructor builtin.
    static let jsMathObject = ILType.object(ofGroup: "Math", withProperties: ["E", "PI"], withMethods: ["abs", "acos", "acosh", "asin", "asinh", "atan", "atanh", "atan2", "ceil", "cbrt", "expm1", "clz32", "cos", "cosh", "exp", "floor", "fround", "hypot", "imul", "log", "log1p", "log2", "log10", "max", "min", "pow", "random", "round", "sign", "sin", "sinh", "sqrt", "tan", "tanh", "trunc"])

    /// Type of the JavaScript Date object
    static let jsDate = ILType.object(ofGroup: "Date", withMethods: ["toISOString", "toDateString", "toTimeString", "toLocaleString", "getTime", "getFullYear", "getUTCFullYear", "getMonth", "getUTCMonth", "getDate", "getUTCDate", "getDay", "getUTCDay", "getHours", "getUTCHours", "getMinutes", "getUTCMinutes", "getSeconds", "getUTCSeconds", "getMilliseconds", "getUTCMilliseconds", "getTimezoneOffset", "getYear", "now", "setTime", "setMilliseconds", "setUTCMilliseconds", "setSeconds", "setUTCSeconds", "setMinutes", "setUTCMinutes", "setHours", "setUTCHours", "setDate", "setUTCDate", "setMonth", "setUTCMonth", "setFullYear", "setUTCFullYear", "setYear", "toJSON", "toUTCString", "toGMTString"])

    /// Type of the JavaScript Date constructor builtin
    static let jsDateConstructor = ILType.functionAndConstructor([.opt(.string | .number)] => .jsDate) + .object(ofGroup: "DateConstructor", withProperties: ["prototype"], withMethods: ["UTC", "now", "parse"])

    /// Type of the JavaScript JSON object builtin.
    static let jsJSONObject = ILType.object(ofGroup: "JSON", withMethods: ["parse", "stringify"])

    /// Type of the JavaScript Reflect object builtin.
    static let jsReflectObject = ILType.object(ofGroup: "Reflect", withMethods: ["apply", "construct", "defineProperty", "deleteProperty", "get", "getOwnPropertyDescriptor", "getPrototypeOf", "has", "isExtensible", "ownKeys", "preventExtensions", "set", "setPrototypeOf"])

    /// Type of the JavaScript isNaN builtin function.
    static let jsIsNaNFunction = ILType.function([.anything] => .boolean)

    /// Type of the JavaScript isFinite builtin function.
    static let jsIsFiniteFunction = ILType.function([.anything] => .boolean)

    /// Type of the JavaScript escape builtin function.
    static let jsEscapeFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript unescape builtin function.
    static let jsUnescapeFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript decodeURI builtin function.
    static let jsDecodeURIFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript decodeURIComponent builtin function.
    static let jsDecodeURIComponentFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript encodeURI builtin function.
    static let jsEncodeURIFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript encodeURIComponent builtin function.
    static let jsEncodeURIComponentFunction = ILType.function([.anything] => .jsString)

    /// Type of the JavaScript eval builtin function.
    static let jsEvalFunction = ILType.function([.string] => .anything)

    /// Type of the JavaScript parseInt builtin function.
    static let jsParseIntFunction = ILType.function([.string] => .integer)

    /// Type of the JavaScript parseFloat builtin function.
    static let jsParseFloatFunction = ILType.function([.string] => .float)

    /// Type of the JavaScript undefined value.
    static let jsUndefined = ILType.undefined

    /// Type of the JavaScript NaN value.
    static let jsNaN = ILType.float

    /// Type of the JavaScript Infinity value.
    static let jsInfinity = ILType.float

    // The JavaScript WebAssembly.Table object of the given variant, i.e. FuncRef or ExternRef
    static let wasmTable = ILType.object(ofGroup: "WasmTable", withProperties: ["length"], withMethods: ["get", "grow", "set"])
}

// Type information for the object groups that we use to model the JavaScript runtime environment.
// The general rules here are:
//  * "output" type information (properties and return values) should be as precise as possible
//  * "input" type information (function parameters) should be as broad as possible
public extension ObjectGroup {
    /// Object group modelling JavaScript strings
    static let jsStrings = ObjectGroup(
        name: "String",
        instanceType: .jsString,
        properties: [
            "length"      : .integer,
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
            "normalize"   : [] => .jsString,  // the first parameter must be a specific string value, so we have a CodeGenerator for that instead
            "padEnd"      : [.integer, .opt(.string)] => .jsString,
            "padStart"    : [.integer, .opt(.string)] => .jsString,
            "repeat"      : [.integer] => .jsString,
            "replace"     : [.oneof(.string, .regexp), .string] => .jsString,
            "replaceAll"  : [.string, .string] => .jsString,
            "search"      : [.regexp] => .integer,
            "slice"       : [.integer, .opt(.integer)] => .jsString,
            "split"       : [.opt(.string), .opt(.integer)] => .jsArray,
            "startsWith"  : [.string, .opt(.integer)] => .boolean,
            "substring"   : [.integer, .opt(.integer)] => .jsString,
            "trim"        : [] => .undefined,
            "trimStart"   : [] => .jsString,
            "trimLeft"    : [] => .jsString,
            "trimEnd"     : [] => .jsString,
            "trimRight"   : [] => .jsString,
            "toLowerCase" : [] => .jsString,
            "toUpperCase" : [] => .jsString,
            "localeCompare" : [.string, .opt(.string), .opt(.object())] => .jsString,
            //"toLocaleLowerCase" : [.opt(.string...] => .jsString,
            //"toLocaleUpperCase" : [.opt(.string...] => .jsString,
            // ...
        ]
    )

    /// Object group modelling JavaScript regular expressions.
    static let jsRegExps = ObjectGroup(
        name: "RegExp",
        instanceType: .jsRegExp,
        properties: [
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

    /// Object group modelling JavaScript arrays
    static let jsArrays = ObjectGroup(
        name: "Array",
        instanceType: .jsArray,
        properties: [
            "length"      : .integer,
        ],
        methods: [
            "at"             : [.integer] => .anything,
            "copyWithin"     : [.integer, .integer, .opt(.integer)] => .jsArray,
            "entries"        : [] => .jsArray,
            "every"          : [.function(), .opt(.object())] => .boolean,
            "fill"           : [.anything, .opt(.integer), .opt(.integer)] => .undefined,
            "find"           : [.function(), .opt(.object())] => .anything,
            "findIndex"      : [.function(), .opt(.object())] => .integer,
            "findLast"       : [.function(), .opt(.object())] => .anything,
            "findLastIndex"  : [.function(), .opt(.object())] => .integer,
            "forEach"        : [.function(), .opt(.object())] => .undefined,
            "includes"       : [.anything, .opt(.integer)] => .boolean,
            "indexOf"        : [.anything, .opt(.integer)] => .integer,
            "join"           : [.string] => .jsString,
            "keys"           : [] => .object(),          // returns an array iterator
            "lastIndexOf"    : [.anything, .opt(.integer)] => .integer,
            "reduce"         : [.function(), .opt(.anything)] => .anything,
            "reduceRight"    : [.function(), .opt(.anything)] => .anything,
            "reverse"        : [] => .undefined,
            "some"           : [.function(), .opt(.anything)] => .boolean,
            "sort"           : [.function()] => .undefined,
            "values"         : [] => .object(),
            "pop"            : [] => .anything,
            "push"           : [.anything...] => .integer,
            "shift"          : [] => .anything,
            "splice"         : [.integer, .opt(.integer), .anything...] => .jsArray,
            "unshift"        : [.anything...] => .integer,
            "concat"         : [.anything...] => .jsArray,
            "filter"         : [.function(), .opt(.object())] => .jsArray,
            "map"            : [.function(), .opt(.object())] => .jsArray,
            "slice"          : [.opt(.integer), .opt(.integer)] => .jsArray,
            "flat"           : [.opt(.integer)] => .jsArray,
            "flatMap"        : [.function(), .opt(.anything)] => .jsArray,
            "toString"       : [] => .jsString,
            "toLocaleString" : [.opt(.string), .opt(.object())] => .jsString,
            "toReversed"     : [] => .jsArray,
            "toSorted"       : [.opt(.function())] => .jsArray,
            "toSpliced"      : [.integer, .opt(.integer), .anything...] => .jsArray,
            "with"           : [.integer, .anything] => .jsArray,
        ]
    )

    /// ObjectGroup modelling JavaScript functions
    static let jsFunctions = ObjectGroup(
        name: "Function",
        instanceType: .jsFunction(),
        properties: [
            "prototype"   : .object(),
            "length"      : .integer,
            "arguments"   : .jsArray,
            "caller"      : .jsFunction(),
            "name"        : .jsString,
        ],
        methods: [
            "apply" : [.object(), .object()] => .anything,
            "call"  : [.object(), .anything...] => .anything,
            "bind"  : [.object(), .anything...] => .anything,
        ]
    )

    /// ObjectGroup modelling JavaScript Symbols
    static let jsSymbols = ObjectGroup(
        name: "Symbol",
        instanceType: .jsSymbol,
        properties: [
            "description" : .jsString,
        ],
        methods: [:]
    )

    /// Object group modelling JavaScript arguments objects.
    static let jsArguments = ObjectGroup(
        name: "Arguments",
        instanceType: .jsArguments,
        properties: [
            "length": .integer,
            "callee": .jsFunction(),
        ],
        methods: [:]
    )

    static let jsGenerators = ObjectGroup(
        name: "Generator",
        instanceType: .jsGenerator,
        properties: [:],
        methods: [
            "next"   : [.opt(.anything)] => .object(withProperties: ["done", "value"]),
            "return" : [.opt(.anything)] => .object(withProperties: ["done", "value"]),
            "throw"  : [.opt(.anything)] => .object(withProperties: ["done", "value"])
        ]
    )

    /// Object group modelling JavaScript promises.
    static let jsPromises = ObjectGroup(
        name: "Promise",
        instanceType: .jsPromise,
        properties: [:],
        methods: [
            "catch"   : [.function()] => .jsPromise,
            "then"    : [.function()] => .jsPromise,
            "finally" : [.function()] => .jsPromise,
        ]
    )

    /// ObjectGroup modelling JavaScript Map objects
    static let jsMaps = ObjectGroup(
        name: "Map",
        instanceType: .jsMap,
        properties: [
            "size"      : .integer
        ],
        methods: [
            "clear"   : [] => .undefined,
            "delete"  : [.anything] => .boolean,
            "entries" : [] => .object(),
            "forEach" : [.function(), .opt(.object())] => .undefined,
            "get"     : [.anything] => .anything,
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
        properties: [:],
        methods: [
            "delete" : [.anything] => .boolean,
            "get"    : [.anything] => .anything,
            "has"    : [.anything] => .boolean,
            "set"    : [.anything, .anything] => .jsWeakMap,
        ]
    )

    /// ObjectGroup modelling JavaScript Set objects
    static let jsSets = ObjectGroup(
        name: "Set",
        instanceType: .jsSet,
        properties: [
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
        properties: [:],
        methods: [
            "add"    : [.anything] => .jsWeakSet,
            "delete" : [.anything] => .boolean,
            "has"    : [.anything] => .boolean,
        ]
    )

    /// ObjectGroup modelling JavaScript WeakRef objects
    static let jsWeakRefs = ObjectGroup(
        name: "WeakRef",
        instanceType: .jsWeakRef,
        properties: [:],
        methods: [
            "deref"   : [] => .object(),
        ]
    )

    /// ObjectGroup modelling JavaScript FinalizationRegistry objects
    static let jsFinalizationRegistrys = ObjectGroup(
        name: "FinalizationRegistry",
        instanceType: .jsFinalizationRegistry,
        properties: [:],
        methods: [
            "register"   : [.object(), .anything, .opt(.object())] => .object(),
            "unregister" : [.anything] => .undefined,
        ]
    )

    /// ObjectGroup modelling JavaScript ArrayBuffer objects
    static let jsArrayBuffers = ObjectGroup(
        name: "ArrayBuffer",
        instanceType: .jsArrayBuffer,
        properties: [
            "byteLength"    : .integer,
            "maxByteLength" : .integer,
            "resizable"     : .boolean
        ],
        methods: [
            "resize"    : [.integer] => .undefined,
            "slice"     : [.integer, .opt(.integer)] => .jsArrayBuffer,
            "transfer"  : [] => .jsArrayBuffer,
        ]
    )

    /// ObjectGroup modelling JavaScript SharedArrayBuffer objects
    static let jsSharedArrayBuffers = ObjectGroup(
        name: "SharedArrayBuffer",
        instanceType: .jsSharedArrayBuffer,
        properties: [
            "byteLength"    : .integer,
            "maxByteLength" : .integer,
            "growable"      : .boolean,
        ],
        methods: [
            "grow"      : [.number] => .undefined,
            "slice"     : [.integer, .opt(.integer)] => .jsSharedArrayBuffer,
        ]
    )

    /// ObjectGroup modelling JavaScript TypedArray objects
    static func jsTypedArrays(_ variant: String) -> ObjectGroup {
        return ObjectGroup(
            name: variant,
            instanceType: .jsTypedArray(variant),
            properties: [
                "buffer"      : .jsArrayBuffer,
                "byteLength"  : .integer,
                "byteOffset"  : .integer,
                "length"      : .integer
            ],
            methods: [
                "at"          : [.integer] => .anything,
                "copyWithin"  : [.integer, .integer, .opt(.integer)] => .undefined,
                "entries"     : [] => .jsArray,
                "every"       : [.function(), .opt(.object())] => .boolean,
                "fill"        : [.anything, .opt(.integer), .opt(.integer)] => .undefined,
                "find"        : [.function(), .opt(.object())] => .anything,
                "findIndex"   : [.function(), .opt(.object())] => .integer,
                "findLast"    : [.function(), .opt(.object())] => .anything,
                "findLastIndex"  : [.function(), .opt(.object())] => .integer,
                "forEach"     : [.function(), .opt(.object())] => .undefined,
                "includes"    : [.anything, .opt(.integer)] => .boolean,
                "indexOf"     : [.anything, .opt(.integer)] => .integer,
                "join"        : [.string] => .jsString,
                "keys"        : [] => .object(),          // returns an array iterator
                "lastIndexOf" : [.anything, .opt(.integer)] => .integer,
                "reduce"      : [.function(), .opt(.anything)] => .anything,
                "reduceRight" : [.function(), .opt(.anything)] => .anything,
                "reverse"     : [] => .undefined,
                "set"         : [.object(), .opt(.integer)] => .undefined,
                "some"        : [.function(), .opt(.anything)] => .boolean,
                "sort"        : [.function()] => .undefined,
                "values"      : [] => .object(),
                "filter"      : [.function(), .opt(.object())] => .jsTypedArray(variant),
                "map"         : [.function(), .opt(.object())] => .jsTypedArray(variant),
                "slice"       : [.opt(.integer), .opt(.integer)] => .jsTypedArray(variant),
                "subarray"    : [.opt(.integer), .opt(.integer)] => .jsTypedArray(variant),
                "toString"       : [] => .jsString,
                "toLocaleString" : [.opt(.string), .opt(.object())] => .jsString,
                "toReversed"     : [] => .jsTypedArray(variant),
                "toSorted"       : [.opt(.function())] => .jsTypedArray(variant),
                "with"           : [.integer, .anything] => .jsTypedArray(variant),
            ]
        )
    }

    /// ObjectGroup modelling JavaScript DataView objects
    static let jsDataViews = ObjectGroup(
        name: "DataView",
        instanceType: .jsDataView,
        properties: [
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
            "getBigInt64": [.integer] => .bigint,
            "setInt8"    : [.integer, .integer] => .undefined,
            "setUint8"   : [.integer, .integer] => .undefined,
            "setInt16"   : [.integer, .integer] => .undefined,
            "setUint16"  : [.integer, .integer] => .undefined,
            "setInt32"   : [.integer, .integer] => .undefined,
            "setUint32"  : [.integer, .integer] => .undefined,
            "setFloat32" : [.integer, .float] => .undefined,
            "setFloat64" : [.integer, .float] => .undefined,
            "setBigInt64": [.integer, .bigint] => .undefined,
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
            "all"        : [.jsPromise...] => .jsPromise,
            "any"        : [.jsPromise...] => .jsPromise,
            "race"       : [.jsPromise...] => .jsPromise,
            "allSettled" : [.jsPromise...] => .jsPromise,
        ]
    )

    /// ObjectGroup modelling JavaScript Date objects
    static let jsDate = ObjectGroup(
        name: "Date",
        instanceType: .jsDate,
        properties: [:],
        methods: [
            "toISOString"           : [] => .jsString,
            "toDateString"          : [] => .jsString,
            "toTimeString"          : [] => .jsString,
            "toLocaleString"        : [] => .jsString,
            //"toLocaleDateString"    : [.localeObject] => .jsString,
            //"toLocaleTimeString"    : [.localeObject] => .jsString,
            "getTime"               : [] => .number,
            "getFullYear"           : [] => .number,
            "getUTCFullYear"        : [] => .number,
            "getMonth"              : [] => .number,
            "getUTCMonth"           : [] => .number,
            "getDate"               : [] => .number,
            "getUTCDate"            : [] => .number,
            "getDay"                : [] => .number,
            "getUTCDay"             : [] => .number,
            "getHours"              : [] => .number,
            "getUTCHours"           : [] => .number,
            "getMinutes"            : [] => .number,
            "getUTCMinutes"         : [] => .number,
            "getSeconds"            : [] => .number,
            "getUTCSeconds"         : [] => .number,
            "getMilliseconds"       : [] => .number,
            "getUTCMilliseconds"    : [] => .number,
            "getTimezoneOffset"     : [] => .number,
            "getYear"               : [] => .number,
            "now"                   : [] => .number,
            "setTime"               : [.number] => .jsDate,
            "setMilliseconds"       : [.number] => .jsDate,
            "setUTCMilliseconds"    : [.number] => .jsDate,
            "setSeconds"            : [.number] => .jsDate,
            "setUTCSeconds"         : [.number, .opt(.number)] => .jsDate,
            "setMinutes"            : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setUTCMinutes"         : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setHours"              : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setUTCHours"           : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setDate"               : [.number] => .jsDate,
            "setUTCDate"            : [.number] => .jsDate,
            "setMonth"              : [.number] => .jsDate,
            "setUTCMonth"           : [.number] => .jsDate,
            "setFullYear"           : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setUTCFullYear"        : [.number, .opt(.number), .opt(.number)] => .jsDate,
            "setYear"               : [.number] => .jsDate,
            "toJSON"                : [] => .jsString,
            "toUTCString"           : [] => .jsString,
            "toGMTString"           : [] => .jsString,
        ]
    )

    /// ObjectGroup modelling the JavaScript Date constructor
    static let jsDateConstructor = ObjectGroup(
        name: "DateConstructor",
        instanceType: .jsDateConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [
            "UTC"   : [.number, .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number)] => .jsDate,
            "now"   : [] => .jsDate,
            "parse" : [.string] => .jsDate,
        ]
    )

    /// ObjectGroup modelling the JavaScript Object constructor builtin
    static let jsObjectConstructor = ObjectGroup(
        name: "ObjectConstructor",
        instanceType: .jsObjectConstructor,
        properties: [
            "prototype" : .object(),        // TODO
        ],
        methods: [
            "assign"                    : [.object(), .object()] => .undefined,
            "create"                    : [.object(), .object()] => .object(),
            "defineProperty"            : [.object(), .string, .oneof(.object(withProperties: ["configurable", "writable", "enumerable", "value"]), .object(withMethods: ["get", "set"]))] => .undefined,
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
            "isView" : [.anything] => .boolean
        ]
    )

    static let jsSharedArrayBufferConstructor = ObjectGroup(
        name: "SharedArrayBufferConstructor",
        instanceType: .jsSharedArrayBufferConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [:]
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
            "unscopables"        : .jsSymbol,
            "species"            : .jsSymbol,
            "toPrimitive"        : .jsSymbol,
            "toStringTag"        : .jsSymbol,
            "dispose"            : .jsSymbol,
            "asyncDispose"       : .jsSymbol
        ],
        methods: [
            "for"    : [.string] => .jsSymbol,
            "keyFor" : [.object(ofGroup: "Symbol")] => .jsString,
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
            // TODO: should there be a .jsNumber type?
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
            "max"    : [.anything...] => .anything,
            "min"    : [.anything...] => .anything,
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
            "parse"     : [.string, .opt(.function())] => .anything,
            "stringify" : [.anything, .opt(.function()), .opt(.number | .string)] => .jsString,
        ]
    )

    /// ObjectGroup modelling the JavaScript Reflect builtin
    static let jsReflectObject = ObjectGroup(
        name: "Reflect",
        instanceType: .jsReflectObject,
        properties: [:],
        methods: [
            "apply"                    : [.function(), .anything, .object()] => .anything,
            "construct"                : [.constructor(), .object(), .opt(.object())] => .anything,
            "defineProperty"           : [.object(), .string, .object()] => .boolean,
            "deleteProperty"           : [.object(), .string] => .boolean,
            "get"                      : [.object(), .string, .opt(.object())] => .anything,
            "getOwnPropertyDescriptor" : [.object(), .string] => .anything,
            "getPrototypeOf"           : [.anything] => .anything,
            "has"                      : [.object(), .string] => .boolean,
            "isExtensible"             : [.anything] => .boolean,
            "ownKeys"                  : [.anything] => .jsArray,
            "preventExtensions"        : [.object()] => .boolean,
            "set"                      : [.object(), .string, .anything, .opt(.object())] => .boolean,
            "setPrototypeOf"           : [.object(), .object()] => .boolean,
        ]
    )

    /// ObjectGroup modelling JavaScript Error objects
    static func jsError(_ variant: String) -> ObjectGroup {
        return ObjectGroup(
            name: variant,
            instanceType: .jsError(variant),
            properties: [
                "message"     : .jsString,
                "name"        : .jsString,
                "cause"       : .anything,
                "stack"       : .jsString,
            ],
            methods: [
                "toString" : [] => .jsString,
            ]
        )
    }

    /// ObjectGroup modelling JavaScript WebAssembly Global objects.
    static let jsWasmGlobal = ObjectGroup(
        name: "WasmGlobal",
        instanceType: .object(ofGroup: "WasmGlobal", withProperties: ["value"]),
        properties: [
            // TODO: Try using precise JS types based on the global's underlying valuetype (e.g. float for f32 and f64).
            "value" : .anything
        ],
        methods: [:]
    )

    /// ObjectGroup modelling JavaScript WebAssembly Memory objects.
    static let jsWasmMemory = ObjectGroup(
        name: "WasmMemory",
        instanceType: .object(ofGroup: "WasmMemory", withProperties: ["buffer"], withMethods: ["grow"]),
        properties: [
            "buffer" : .jsArrayBuffer | .jsSharedArrayBuffer
        ],
        methods: [
            "grow" : [.number] => .number
        ]
    )

    // TOOD(mliedtke): Reconsider whether WebAssembly.Tag and WebAssembly.JSTag should share the
    // same object group. When split, we can register the type() prototype method.
    static let jsWasmTag = ObjectGroup(
        name: "WasmTag",
        instanceType: .object(ofGroup: "WasmTag"),
        properties: [:],
        methods: [:]
    )

    /// ObjectGroup modelling JavaScript WebAssembly Table objects
    static let wasmTable = ObjectGroup(
        name: "WasmTable",
        instanceType: .wasmTable,
        properties: [
            "length": .number
        ],
        methods: [
            "get": [.number] => .anything,
            "grow": [.number, .opt(.anything)] => .number,
            "set": [.number, .anything] => .undefined,
        ]
    )
}
