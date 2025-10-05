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

public class JavaScriptEnvironment: ComponentBase {
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

    /// Identifiers that should be used for custom properties and methods.
    public static let CustomPropertyNames = ["a", "b", "c", "d", "e", "f", "g", "h"]
    public static let CustomMethodNames = ["m", "n", "o", "p", "valueOf", "toString"]

    public private(set) var builtins = Set<String>()
    public let customProperties = Set<String>(CustomPropertyNames)
    public let customMethods = Set<String>(CustomMethodNames)
    public private(set) var builtinProperties = Set<String>()
    public private(set) var builtinMethods = Set<String>()


    // Something that can generate a variable
    public typealias EnvironmentValueGenerator = (ProgramBuilder) -> Variable

    private var builtinTypes: [String: ILType] = [:]
    private var groups: [String: ObjectGroup] = [:]
    private var enums: [String: ILType] = [:]

    // Producing generators, keyed on `type.group`
    private var producingGenerators: [String: (generator: EnvironmentValueGenerator, probability: Double)] = [:]
    // Named string generators, keyed on `type.group`
    private var namedStringGenerators: [String: () -> String] = [:]
    private var producingMethods: [ILType: [(group: String, method: String)]] = [:]
    private var producingProperties: [ILType: [(group: String, property: String)]] = [:]
    private var subtypes: [ILType: [ILType]] = [:]

    public init(additionalBuiltins: [String: ILType] = [:], additionalObjectGroups: [ObjectGroup] = [], additionalEnumerations: [ILType] = []) {
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
        registerObjectGroup(.jsUint8ArrayConstructor)
        registerObjectGroup(.jsUint8ArrayPrototype)
        registerObjectGroup(.jsDataViews)

        registerObjectGroup(.jsObjectConstructor)
        registerObjectGroup(.jsPromiseConstructor)
        registerObjectGroup(.jsPromisePrototype)
        registerObjectGroup(.jsArrayConstructor)
        registerObjectGroup(.jsStringConstructor)
        registerObjectGroup(.jsStringPrototype)
        registerObjectGroup(.jsSymbolConstructor)
        registerObjectGroup(.jsBigIntConstructor)
        registerObjectGroup(.jsBooleanConstructor)
        registerObjectGroup(.jsNumberConstructor)
        registerObjectGroup(.jsMathObject)
        registerObjectGroup(.jsDate)
        registerObjectGroup(.jsDateConstructor)
        registerObjectGroup(.jsDatePrototype)
        registerObjectGroup(.jsJSONObject)
        registerObjectGroup(.jsReflectObject)
        registerObjectGroup(.jsArrayBufferConstructor)
        registerObjectGroup(.jsArrayBufferPrototype)
        registerObjectGroup(.jsSharedArrayBufferConstructor)
        registerObjectGroup(.jsSharedArrayBufferPrototype)
        for variant in ["Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "AggregateError", "URIError", "SuppressedError"] {
            registerObjectGroup(.jsError(variant))
        }
        registerObjectGroup(.jsWebAssemblyCompileOptions)
        registerObjectGroup(.jsWebAssemblyModuleConstructor)
        registerObjectGroup(.jsWebAssemblyGlobalConstructor)
        registerObjectGroup(.jsWebAssemblyGlobalPrototype)
        registerObjectGroup(.jsWebAssemblyInstanceConstructor)
        registerObjectGroup(.jsWebAssemblyInstance)
        registerObjectGroup(.jsWebAssemblyModule)
        registerObjectGroup(.jsWebAssemblyMemoryPrototype)
        registerObjectGroup(.jsWebAssemblyMemoryConstructor)
        registerObjectGroup(.jsWebAssemblyTablePrototype)
        registerObjectGroup(.jsWebAssemblyTableConstructor)
        registerObjectGroup(.jsWebAssemblyTagPrototype)
        registerObjectGroup(.jsWebAssemblyTagConstructor)
        registerObjectGroup(.jsWebAssemblyException)
        registerObjectGroup(.jsWebAssemblyExceptionPrototype)
        registerObjectGroup(.jsWebAssemblyExceptionConstructor)
        registerObjectGroup(.jsWebAssembly)
        registerObjectGroup(.jsWasmGlobal)
        registerObjectGroup(.jsWasmMemory)
        registerObjectGroup(.wasmTable)
        registerObjectGroup(.jsWasmTag)
        registerObjectGroup(.jsWasmSuspendingObject)
        registerObjectGroup(.jsTemporalObject)
        registerObjectGroup(.jsTemporalNow)
        registerObjectGroup(.jsTemporalInstant)
        registerObjectGroup(.jsTemporalInstantConstructor)
        registerObjectGroup(.jsTemporalInstantPrototype)
        registerObjectGroup(.jsTemporalDuration)
        registerObjectGroup(.jsTemporalDurationConstructor)
        registerObjectGroup(.jsTemporalDurationPrototype)
        registerObjectGroup(.jsTemporalPlainTime)
        registerObjectGroup(.jsTemporalPlainTimeConstructor)
        registerObjectGroup(.jsTemporalPlainTimePrototype)
        registerObjectGroup(.jsTemporalPlainYearMonth)
        registerObjectGroup(.jsTemporalPlainYearMonthConstructor)
        registerObjectGroup(.jsTemporalPlainYearMonthPrototype)
        registerObjectGroup(.jsTemporalPlainMonthDay)
        registerObjectGroup(.jsTemporalPlainMonthDayConstructor)
        registerObjectGroup(.jsTemporalPlainMonthDayPrototype)
        registerObjectGroup(.jsTemporalPlainDate)
        registerObjectGroup(.jsTemporalPlainDateConstructor)
        registerObjectGroup(.jsTemporalPlainDatePrototype)
        registerObjectGroup(.jsTemporalPlainDateTime)
        registerObjectGroup(.jsTemporalPlainDateTimeConstructor)
        registerObjectGroup(.jsTemporalPlainDateTimePrototype)
        registerObjectGroup(.jsTemporalZonedDateTime)
        registerObjectGroup(.jsTemporalZonedDateTimeConstructor)
        registerObjectGroup(.jsTemporalZonedDateTimePrototype)
        registerObjectGroup(.jsIntlObject)
        registerObjectGroup(.jsIntlCollator)
        registerObjectGroup(.jsIntlCollatorConstructor)
        registerObjectGroup(.jsIntlCollatorPrototype)
        registerObjectGroup(.jsIntlDateTimeFormat)
        registerObjectGroup(.jsIntlDateTimeFormatConstructor)
        registerObjectGroup(.jsIntlDateTimeFormatPrototype)
        registerObjectGroup(.jsIntlListFormat)
        registerObjectGroup(.jsIntlListFormatConstructor)
        registerObjectGroup(.jsIntlListFormatPrototype)
        registerObjectGroup(.jsIntlNumberFormat)
        registerObjectGroup(.jsIntlNumberFormatConstructor)
        registerObjectGroup(.jsIntlNumberFormatPrototype)
        registerObjectGroup(.jsIntlPluralRules)
        registerObjectGroup(.jsIntlPluralRulesConstructor)
        registerObjectGroup(.jsIntlPluralRulesPrototype)
        registerObjectGroup(.jsIntlRelativeTimeFormat)
        registerObjectGroup(.jsIntlRelativeTimeFormatConstructor)
        registerObjectGroup(.jsIntlRelativeTimeFormatPrototype)
        registerObjectGroup(.jsIntlSegmenter)
        registerObjectGroup(.jsIntlSegmenterConstructor)
        registerObjectGroup(.jsIntlSegmenterPrototype)
        registerObjectGroup(.jsIntlSegmenterSegments)

        for group in additionalObjectGroups {
            registerObjectGroup(group)
        }

        registerEnumeration(.jsTemporalCalendarEnum)
        registerEnumeration(ObjectGroup.jsTemporalDirectionParam)
        registerEnumeration(ObjectGroup.jsIntlRelativeTimeFormatUnitEnum)
        registerEnumeration(ObjectGroup.jsIntlSupportedValuesEnum)
        registerEnumeration(OptionsBag.jsTemporalUnitEnum)
        registerEnumeration(OptionsBag.jsTemporalRoundingModeEnum)
        registerEnumeration(OptionsBag.jsTemporalShowCalendarEnum)
        registerEnumeration(OptionsBag.jsTemporalShowOffsetEnum)
        registerEnumeration(OptionsBag.jsTemporalShowTimeZoneEnum)
        registerEnumeration(OptionsBag.jsTemporalOverflowEnum)
        registerEnumeration(OptionsBag.jsTemporalDisambiguationEnum)
        registerEnumeration(OptionsBag.jsTemporalOffsetEnum)
        registerEnumeration(OptionsBag.jsIntlLocaleMatcherEnum)
        registerEnumeration(OptionsBag.jsIntlNumberingSystemEnum)
        registerEnumeration(OptionsBag.jsIntlHourCycleEnum)
        registerEnumeration(OptionsBag.jsIntlLongShortNarrowEnum)
        registerEnumeration(OptionsBag.jsIntlLongShortEnum)
        registerEnumeration(OptionsBag.jsIntlAutoAlwaysEnum)
        registerEnumeration(OptionsBag.jsIntlNumeric2DigitEnum)
        registerEnumeration(OptionsBag.jsIntlMonthEnum)
        registerEnumeration(OptionsBag.jsIntlTimeZoneNameEnum)
        registerEnumeration(OptionsBag.jsIntlFormatMatcherEnum)
        registerEnumeration(OptionsBag.jsIntlFullLongMediumShort)
        registerEnumeration(OptionsBag.jsIntlCollatorUsageEnum)
        registerEnumeration(OptionsBag.jsIntlCollationEnum)
        registerEnumeration(OptionsBag.jsIntlCaseFirstEnum)
        registerEnumeration(OptionsBag.jsIntlCollatorSensitivityEnum)
        registerEnumeration(OptionsBag.jsIntlListFormatTypeEnum)
        registerEnumeration(OptionsBag.jsIntlNumberFormatStyleEnum)
        registerEnumeration(OptionsBag.jsIntlCurrencySystemEnum)
        registerEnumeration(OptionsBag.jsIntlCurrencyDisplayEnum)
        registerEnumeration(OptionsBag.jsIntlCurrencySignEnum)
        registerEnumeration(OptionsBag.jsIntlRoundingPriorityEnum)
        registerEnumeration(OptionsBag.jsIntlRoundingModeEnum)
        registerEnumeration(OptionsBag.jsIntlTrailingZeroDisplayEnum)
        registerEnumeration(OptionsBag.jsIntlNumberFormatNotationEnum)
        registerEnumeration(OptionsBag.jsIntlNumberFormatGroupingEnum)
        registerEnumeration(OptionsBag.jsIntlSignDisplayEnum)
        registerEnumeration(OptionsBag.jsIntlPluralRulesTypeEnum)
        registerEnumeration(OptionsBag.jsIntlSegmenterGranularityEnum)
        registerEnumeration(OptionsBag.base64Alphabet)
        registerEnumeration(OptionsBag.base64LastChunkHandling)

        for enumeration in additionalEnumerations {
            assert(enumeration.isEnumeration)
            registerEnumeration(enumeration)
        }

        registerOptionsBag(.jsTemporalDifferenceSettingOrRoundTo)
        registerOptionsBag(.jsTemporalToStringSettings)
        registerOptionsBag(.jsTemporalOverflowSettings)
        registerOptionsBag(.jsTemporalZonedInterpretationSettings)
        registerOptionsBag(.jsTemporalDurationRoundToSettings)
        registerOptionsBag(.jsTemporalDurationTotalOfSettings)
        registerOptionsBag(.toBase64Settings)
        registerOptionsBag(.fromBase64Settings)
        registerOptionsBag(.jsTemporalPlainDateToZDTSettings)
        registerOptionsBag(.jsIntlDateTimeFormatSettings)
        registerOptionsBag(.jsIntlCollatorSettings)
        registerOptionsBag(.jsIntlListFormatSettings)
        registerOptionsBag(.jsIntlNumberFormatSettings)
        registerOptionsBag(.jsIntlPluralRulesSettings)
        registerOptionsBag(.jsIntlRelativeTimeFormatSettings)
        registerOptionsBag(.jsIntlSegmenterSettings)
        registerOptionsBag(.jsIntlLocaleMatcherSettings)

        registerTemporalFieldsObject(.jsTemporalPlainTimeLikeObject, forWith: false, dateFields: false, timeFields: true, zonedFields: false)
        registerTemporalFieldsObject(.jsTemporalPlainDateLikeObject, forWith: false, dateFields: true, timeFields: false, zonedFields: false)
        registerTemporalFieldsObject(.jsTemporalPlainDateLikeObjectForWith, forWith: true, dateFields: true, timeFields: false, zonedFields: false)
        registerTemporalFieldsObject(.jsTemporalPlainDateTimeLikeObject, forWith: false, dateFields: true, timeFields: true, zonedFields: false)
        registerTemporalFieldsObject(.jsTemporalPlainDateTimeLikeObjectForWith, forWith: true, dateFields: true, timeFields: true, zonedFields: false)
        registerTemporalFieldsObject(.jsTemporalZonedDateTimeLikeObject, forWith: false, dateFields: true, timeFields: true, zonedFields: true)
        registerTemporalFieldsObject(.jsTemporalZonedDateTimeLikeObjectForWith, forWith: true, dateFields: true, timeFields: true, zonedFields: true)

        // This isn't a normal "temporal fields object" but is similar, and needs a similar producing generator
        registerObjectGroup(.jsTemporalDurationLikeObject)
        addProducingGenerator(forType: ObjectGroup.jsTemporalDurationLikeObject.instanceType, with: { b in b.createTemporalDurationFieldsObject() })
        addNamedStringGenerator(forType: ObjectGroup.jsTemporalTimeZoneLike,
         with: {
            if Bool.random() {
                return ProgramBuilder.randomTimeZoneString()
            } else {
                return ProgramBuilder.randomUTCOffsetString(mayHaveSeconds: true)
            }
        })
        addNamedStringGenerator(forType: .jsIntlLocaleLike, with: { ProgramBuilder.constructIntlLocaleString() })
        addNamedStringGenerator(forType: .jsIntlUnit, with: { ProgramBuilder.constructIntlUnit() })

        // Temporal types are produced by a large number of methods; which means findOrGenerateType(), when asked to produce
        // a Temporal type, will tend towards trying to call a method on another Temporal type, which needs more Temporal types,
        // leading to a large amount of code generated. We do wish to test these codepaths as well, but by and large we
        // just want a freshly generated type.
        addProducingGenerator(forType: .jsTemporalInstant, with: { $0.constructTemporalInstant() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalDuration, with: { $0.constructTemporalDuration() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalPlainTime, with: { $0.constructTemporalTime() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalPlainYearMonth, with: { $0.constructTemporalYearMonth() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalPlainMonthDay, with: { $0.constructTemporalMonthDay() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalPlainDate, with: { $0.constructTemporalDate() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalPlainDateTime, with: { $0.constructTemporalDateTime() }, probability: 0.9)
        addProducingGenerator(forType: .jsTemporalZonedDateTime, with: { $0.constructTemporalZonedDateTime() }, probability: 0.9)

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
        for variant in ["Error", "EvalError", "RangeError", "ReferenceError", "SyntaxError", "TypeError", "URIError", "SuppressedError"] {
            registerBuiltin(variant, ofType: .jsErrorConstructor(variant))
        }
        registerBuiltin("AggregateError", ofType: .functionAndConstructor([.plain(.iterable), .opt(.string), .opt(.object())] => .jsError("AggregateError")))
        registerBuiltin("ArrayBuffer", ofType: .jsArrayBufferConstructor)
        registerBuiltin("SharedArrayBuffer", ofType: .jsSharedArrayBufferConstructor)
        // Uint8Array handled below.
        for variant in ["Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"] {
            registerBuiltin(variant, ofType: .jsTypedArrayConstructor(variant))
        }
        registerBuiltin("Uint8Array", ofType: .jsUint8ArrayConstructor)
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
        registerBuiltin("Temporal", ofType: .jsTemporalObject)
        registerBuiltin("Intl", ofType: .jsIntlObject)
        registerBuiltin("WebAssembly", ofType: ObjectGroup.jsWebAssembly.instanceType)

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
            "Proxy",          // returns .jsAnything
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

    // Add a generator that produces an object of the provided `type`.
    //
    // The probability is how often this generator should be called when this type is required.
    //
    // The default probability (1) is for groups that are never generated as return types of other objects.
    // Use a lower probability if there are other ways to generate the object.
    //
    // Note that Fuzzilli is able to discover ways to construct types on its own. There are two use cases for this:
    // - "Options bag" type objects where no JS API produces them, so we *must* run a producing generator
    // - Temporal objects: These can be obtained from the result of other API calls, however a
    //   a lot of these API calls need more Temporal objects, leading to runaway recursion attempting
    //   to generate a large number of Temporal objects. Instead, we bias heavily towards the producing generator.
    public func addProducingGenerator(forType type: ILType, with generator: @escaping EnvironmentValueGenerator, probability: Double = 1.0) {
        assert(type.Is(.object()), "Producing generators can only be registered for objects, found \(type)")
        producingGenerators[type.group!] = (generator, probability)
    }

    // Register a generator for a custom named string.
    public func addNamedStringGenerator(forType type: ILType, with generator: @escaping () -> String) {
        assert(type.Is(.string), "Named string generators can only be registered for strings, found \(type)")
        namedStringGenerators[type.group!] = generator
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

    public func registerEnumeration(_ type: ILType) {
        assert(type.isEnumeration)
        let group = type.group!
        assert(enums[group] == nil, "Registered duplicate enum \(group)")
        enums[group] = type
    }

    public func registerObjectGroup(_ group: ObjectGroup) {
        assert(groups[group.name] == nil, "Registered duplicate enum \(group.name)")
        groups[group.name] = group
        builtinProperties.formUnion(group.properties.keys)
        builtinMethods.formUnion(group.methods.keys)

        //func register
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

    // Temporal has a large number of "fields" object (aka "partial temporal objects" or "temporal-like objects")
    // which have a number of datetime-like fields. These are never produced as a result from any JS APIs, so we cannot
    // expect instances of them to already exist in scope. Instead, we generate them ourselves when requested.
    public func registerTemporalFieldsObject(_ group: ObjectGroup, forWith: Bool, dateFields: Bool, timeFields: Bool, zonedFields: Bool) {
        registerObjectGroup(group)
        addProducingGenerator(forType: group.instanceType, with: { b in
            b.createTemporalFieldsObject(forWith: forWith, dateFields: dateFields, timeFields: timeFields, zonedFields: zonedFields)
        })
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

    public func registerOptionsBag(_ bag: OptionsBag) {
        registerObjectGroup(bag.group)

        for property in bag.properties.values {
            if property.isEnumeration {
                assert(enums[property.group!] != nil, "Enum \(property.group!) used in options bag but not registered on the JavaScriptEnvironment")
            }
        }

        addProducingGenerator(forType: bag.group.instanceType, with: { b in b.createOptionsBag(bag) })
    }

    public func type(ofBuiltin builtinName: String) -> ILType {
        if let type = builtinTypes[builtinName] {
            return type
        } else {
            logger.warning("Missing type for builtin \(builtinName)")
            return .jsAnything
        }
    }

    public func type (ofGroup groupName: String) -> ILType {
        if let type = groups[groupName]?.instanceType {
            return type
        } else {
            logger.warning("Missing type for group \(groupName)")
            return .jsAnything
        }
    }

    public func type(ofProperty propertyName: String, on baseType: ILType) -> ILType {
        if let groupName = baseType.group {
            if let group = groups[groupName] {
                if let type = group.properties[propertyName] {
                    return type
                }
                if let signatures = group.methods[propertyName] {
                    return .unboundFunction(signatures.first, receiver: baseType)
                }
            } else {
                // This shouldn't happen, probably forgot to register the object group
                logger.warning("No type information for object group \(groupName) available")
            }
        }

        return .jsAnything
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

    public func getEnum(ofName name: String) -> ILType? {
        return enums[name]
    }

    public func getProducingMethods(ofType type: ILType) -> [(group: String, method: String)] {
        guard let array = producingMethods[type] else {
            return []
        }
        return array
    }

    // For ObjectGroups, get a generator that is registered as being able to produce this
    // ObjectGroup.
    public func getProducingGenerator(ofType type: ILType) -> (generator: EnvironmentValueGenerator, probability: Double)? {
        type.group.flatMap {producingGenerators[$0]}
    }

    // For named strings, get a generator that is registered as being able to produce this
    // named string.
    public func getNamedStringGenerator(ofName name: String) -> (() -> String)? {
        namedStringGenerators[name]
    }


    // If the object group refers to a constructor, get its path.
    public func getPathIfConstructor(ofGroup groupName: String) -> [String]? {
        guard let group = groups[groupName] else {
            return nil
        }
        return group.constructorPath
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
    public var properties: [String: ILType]
    public var methods: [String: [Signature]]
    public let parent: String?
    // Path to constructor function from `globalThis` if available (e.g. `["Temporal", "Instant"]`).
    public let constructorPath: [String]?

    /// The type of instances of this group.
    public var instanceType: ILType

    public init(name: String, constructorPath: String? = nil, instanceType: ILType?, properties: [String: ILType], overloads: [String: [Signature]], parent: String? = nil) {
        self.name = name
        self.properties = properties
        self.methods = overloads
        self.parent = parent

        if let instanceType {
            // We could also only assert set inclusion here to implement "shared" properties/methods.
            // (which would then need some kind of fallback ObjectGroup that is consulted by the
            // type lookup routines if the real group doesn't have the requested information).
            assert(instanceType.group == name, "group name mismatch for group \(name)")
            assert(instanceType.properties == Set(properties.keys), "inconsistent property information for object group \(name): \(Set(properties.keys).symmetricDifference(instanceType.properties))")
            assert(instanceType.methods == Set(methods.keys), "inconsistent method information for object group \(name): \(Set(methods.keys).symmetricDifference(instanceType.methods))")
            self.instanceType = instanceType
        } else {
            // Simply calculate the instance type based on the ObjectGroup information.
            self.instanceType = .object(ofGroup: name, withProperties: Array(properties.keys), withMethods: Array(methods.keys))
        }

        if let constructorPath {
            assert(self.instanceType.Is(.constructor()) || self.instanceType.Is(.function()), "\(name) has a constructor path set but does not wrap a constructor")
            self.constructorPath = constructorPath.split(separator: ".").map({ String($0) })
        } else {
            self.constructorPath = nil
        }
    }

    public init(name: String, constructorPath: String? = nil, instanceType: ILType?, properties: [String: ILType], methods: [String: Signature], parent: String? = nil) {
       self.init(name: name, constructorPath: constructorPath, instanceType: instanceType, properties: properties, overloads: methods.mapValues({[$0]}), parent: parent)
    }
}

// Some APIs take an "options bag", a list of options like {foo: "something", bar: "something", baz: 1}
//
// It is useful to be able to represent simple options bags so that we can efficiently codegen them
public struct OptionsBag {
    // The type of each property, not including `| .undefined`.
    // We may extend this once we start supporting more complex bags
    public var properties: [String: ILType]
    // An ObjectGroup representing this bag
    public var group: ObjectGroup

    public init(name: String, properties: [String: ILType]) {
        self.properties = properties
        let properties = properties.mapValues {
            // This list can be expanded over time as long as createOptionsBag() supports this
            assert($0.isEnumeration || $0.Is(.number | .integer | .boolean) ||
                    // Has a producing generator registered
                    $0.Is(.jsTemporalPlainTime) ||
                    // Has explicit support in createOptionsBag
                    $0.Is(OptionsBag.jsTemporalRelativeTo),
                   "Found unsupported option type \($0) in options bag \(name)")
            return $0 | .undefined;
        }
        self.group = ObjectGroup(name: name, instanceType: nil, properties: properties, overloads: [:])
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
// Another rule of thumb is that the type information should either be complete or missing entirely. I.e. it is better to have a field be .jsAnything
// or .jsAnythingObject instead of only specifying a subset of its properties for example. Partial type information is usually bad as
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
        let extraMethods = variant == "Uint8Array" ? ["setFromBase64", "setFromHex", "toBase64", "toHex"] : []
        return .iterable + .object(ofGroup: variant, withProperties: ["buffer", "byteOffset", "byteLength", "length"], withMethods: ["at", "copyWithin", "fill", "find", "findIndex", "findLast", "findLastIndex", "reverse", "slice", "sort", "includes", "indexOf", "keys", "entries", "forEach", "filter", "map", "every", "set", "some", "subarray", "reduce", "reduceRight", "join", "lastIndexOf", "values", "toLocaleString", "toString", "toReversed", "toSorted", "with"]
            + extraMethods)
    }

    static let jsUint8Array = jsTypedArray("Uint8Array")

    /// Type of a JavaScript function.
    /// A JavaScript function is also constructors. Moreover, it is also an object as it has a number of properties and methods.
    static func jsFunction(_ signature: Signature = Signature.forUnknownFunction) -> ILType {
        return .constructor(signature) + .function(signature) + .object(ofGroup: "Function", withProperties: ["prototype", "length", "arguments", "caller", "name"], withMethods: ["apply", "bind", "call"])
    }

    /// Type of the JavaScript Object constructor builtin.
    static let jsObjectConstructor = .functionAndConstructor([.jsAnything...] => .object()) + .object(ofGroup: "ObjectConstructor", withProperties: ["prototype"], withMethods: ["assign", "fromEntries", "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames", "getOwnPropertySymbols", "is", "preventExtensions", "seal", "create", "defineProperties", "defineProperty", "freeze", "getPrototypeOf", "setPrototypeOf", "isExtensible", "isFrozen", "isSealed", "keys", "entries", "values"])

    /// Type of the JavaScript Array constructor builtin.
    static let jsArrayConstructor = .functionAndConstructor([.integer] => .jsArray) + .object(ofGroup: "ArrayConstructor", withProperties: ["prototype"], withMethods: ["from", "of", "isArray"])

    /// Type of the JavaScript Function constructor builtin.
    static let jsFunctionConstructor = ILType.constructor([.string] => .jsFunction(Signature.forUnknownFunction))

    /// Type of the JavaScript String constructor builtin.
    static let jsStringConstructor = ILType.functionAndConstructor([.jsAnything] => .jsString) + .object(ofGroup: "StringConstructor", withProperties: ["prototype"], withMethods: ["fromCharCode", "fromCodePoint", "raw"])

    /// Type of the JavaScript Boolean constructor builtin.
    static let jsBooleanConstructor = ILType.functionAndConstructor([.jsAnything] => .boolean) + .object(ofGroup: "BooleanConstructor", withProperties: ["prototype"], withMethods: [])

    /// Type of the JavaScript Number constructor builtin.
    static let jsNumberConstructor = ILType.functionAndConstructor([.jsAnything] => .number) + .object(ofGroup: "NumberConstructor", withProperties: ["prototype", "EPSILON", "MAX_SAFE_INTEGER", "MAX_VALUE", "MIN_SAFE_INTEGER", "MIN_VALUE", "NaN", "NEGATIVE_INFINITY", "POSITIVE_INFINITY"], withMethods: ["isNaN", "isFinite", "isInteger", "isSafeInteger"])

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
        return .constructor([.opt(.integer | .jsArrayBuffer), .opt(.integer), .opt(.integer)] => .jsTypedArray(variant))
    }

    static let jsUint8ArrayConstructor = jsTypedArrayConstructor("Uint8Array")
        + .object(ofGroup: "Uint8ArrayConstructor", withProperties: ["prototype"], withMethods: ["fromBase64", "fromHex"])

    /// Type of the JavaScript DataView constructor builtin. (TODO Also allow SharedArrayBuffers for first argument)
    static let jsDataViewConstructor = ILType.constructor([.plain(.jsArrayBuffer), .opt(.integer), .opt(.integer)] => .jsDataView)

    /// Type of the JavaScript Promise constructor builtin.
    static let jsPromiseConstructor = ILType.constructor([.function()] => .jsPromise) + .object(ofGroup: "PromiseConstructor", withProperties: ["prototype"], withMethods: ["resolve", "reject", "all", "any", "race", "allSettled"])

    /// Type of the JavaScript Proxy constructor builtin.
    static let jsProxyConstructor = ILType.constructor([.object(), .object()] => .jsAnything)

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
    static let jsDate = ILType.object(ofGroup: "Date", withMethods: ["toISOString", "toDateString", "toTimeString", "toLocaleString", "getTime", "getFullYear", "getUTCFullYear", "getMonth", "getUTCMonth", "getDate", "getUTCDate", "getDay", "getUTCDay", "getHours", "getUTCHours", "getMinutes", "getUTCMinutes", "getSeconds", "getUTCSeconds", "getMilliseconds", "getUTCMilliseconds", "getTimezoneOffset", "getYear", "setTime", "setMilliseconds", "setUTCMilliseconds", "setSeconds", "setUTCSeconds", "setMinutes", "setUTCMinutes", "setHours", "setUTCHours", "setDate", "setUTCDate", "setMonth", "setUTCMonth", "setFullYear", "setUTCFullYear", "setYear", "toJSON", "toUTCString", "toGMTString", "toTemporalInstant"])

    /// Type of the JavaScript Date constructor builtin
    static let jsDateConstructor = ILType.functionAndConstructor([.opt(.string | .number)] => .jsDate) + .object(ofGroup: "DateConstructor", withProperties: ["prototype"], withMethods: ["UTC", "now", "parse"])

    /// Type of the JavaScript JSON object builtin.
    static let jsJSONObject = ILType.object(ofGroup: "JSON", withMethods: ["parse", "stringify"])

    /// Type of the JavaScript Reflect object builtin.
    static let jsReflectObject = ILType.object(ofGroup: "Reflect", withMethods: ["apply", "construct", "defineProperty", "deleteProperty", "get", "getOwnPropertyDescriptor", "getPrototypeOf", "has", "isExtensible", "ownKeys", "preventExtensions", "set", "setPrototypeOf"])

    /// Type of the JavaScript isNaN builtin function.
    static let jsIsNaNFunction = ILType.function([.jsAnything] => .boolean)

    /// Type of the JavaScript isFinite builtin function.
    static let jsIsFiniteFunction = ILType.function([.jsAnything] => .boolean)

    /// Type of the JavaScript escape builtin function.
    static let jsEscapeFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript unescape builtin function.
    static let jsUnescapeFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript decodeURI builtin function.
    static let jsDecodeURIFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript decodeURIComponent builtin function.
    static let jsDecodeURIComponentFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript encodeURI builtin function.
    static let jsEncodeURIFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript encodeURIComponent builtin function.
    static let jsEncodeURIComponentFunction = ILType.function([.jsAnything] => .jsString)

    /// Type of the JavaScript eval builtin function.
    static let jsEvalFunction = ILType.function([.string] => .jsAnything)

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

    static let jsWebAssemblyModule = ILType.object(ofGroup: "WebAssembly.Module")

    /// Type of the WebAssembly.Module() constructor.
    // TODO: The first constructor argument can also be any typed array and .jsSharedArrayBuffer.
    static let jsWebAssemblyModuleConstructor =
        ILType.constructor([.plain(.jsArrayBuffer)] => .jsWebAssemblyModule)
        + .object(ofGroup: "WebAssemblyModuleConstructor", withProperties: ["prototype"],
            withMethods: ["customSections", "imports", "exports"])

    static let jsWebAssemblyGlobalConstructor =
        // We do not type the result as being part of the ObjectGroup "WasmGlobal" as that would
        // require to also add a WasmTypeExtension to its type. This is fine as the proper
        // construction of globals is done via the high-level Wasm operations and these builtins
        // only serve the purpose of fuzzing the API.
        ILType.constructor([.plain(.object()), .jsAnything] => .object(withProperties: ["value"], withMethods: ["valueOf"]))
        + .object(ofGroup: "WebAssemblyGlobalConstructor", withProperties: ["prototype"], withMethods: [])

    static let jsWebAssemblyInstance = ILType.object(ofGroup: "WebAssembly.Instance",
        withProperties: ["exports"])

    static let jsWebAssemblyInstanceConstructor =
        ILType.constructor([.plain(.jsWebAssemblyModule), .plain(.object())] => .jsWebAssemblyInstance)
        + .object(ofGroup: "WebAssemblyInstanceConstructor", withProperties: ["prototype"], withMethods: [])

    // Similarly to Wasm globals, we do not type the results as being part of an object group as the
    // result type doesn't have a valid WasmTypeExtension.
    static let jsWebAssemblyMemoryConstructor = ILType.constructor([.plain(.object(withProperties: ["initial"]))] => .object(withProperties: ["buffer"], withMethods: ["grow", "toResizableBuffer", "toFixedLengthBuffer"]))
        + .object(ofGroup: "WebAssemblyMemoryConstructor", withProperties: ["prototype"])

    static let jsWebAssemblyTableConstructor = ILType.constructor([.plain(.object(withProperties: ["initial"]))] => object(withProperties: ["length"], withMethods: ["get", "grow", "set"]))
        + .object(ofGroup: "WebAssemblyTableConstructor", withProperties: ["prototype"])

    static let jsWebAssemblyTagConstructor = ILType.constructor([.plain(.object(withProperties: ["parameters"]))] => object(withMethods: []))
        + .object(ofGroup: "WebAssemblyTagConstructor", withProperties: ["prototype"])

    static let jsWebAssemblyExceptionConstructor = ILType.constructor([.plain(ObjectGroup.jsWasmTag.instanceType), .plain(.jsArray), .opt(.object(withProperties: ["traceStack"]))] => ObjectGroup.jsWebAssemblyException.instanceType)
        + .object(ofGroup: "WebAssemblyExceptionConstructor", withProperties: ["prototype"])

    // The JavaScript WebAssembly.Table object of the given variant, i.e. FuncRef or ExternRef
    static let wasmTable = ILType.object(ofGroup: "WasmTable", withProperties: ["length"], withMethods: ["get", "grow", "set"])

    // Temporal types
    static let jsTemporalObject = ILType.object(ofGroup: "Temporal", withProperties: ["Instant", "Duration", "PlainTime", "PlainYearMonth", "PlainMonthDay", "PlainDate", "PlainDateTime", "ZonedDateTime", "Now"])

    // TODO(mliedtke): Can we stop documenting Object.prototype methods? It doesn't make much sense that half of the ObjectGroups register a toString method,
    // the other half doesn't and not a single one registers e.g. propertyIsEnumerable or isPrototypeOf.`?
    //
    // Note that Temporal toString accepts additional parameters
    private static let commonStringifierMethods = ["toString", "toJSON", "toLocaleString"]

    static let jsTemporalInstant = ILType.object(ofGroup: "Temporal.Instant", withProperties: ["epochMilliseconds", "epochNanoseconds"], withMethods: ["add", "subtract", "until", "since", "round", "equals", "toZonedDateTimeISO"] + commonStringifierMethods)

    static let jsTemporalInstantConstructor = ILType.functionAndConstructor([.bigint] => .jsTemporalInstant) + .object(ofGroup: "TemporalInstantConstructor", withProperties: ["prototype"], withMethods: ["from", "fromEpochMilliseconds", "fromEpochNanoseconds", "compare"])

    static let jsTemporalDuration = ILType.object(ofGroup: "Temporal.Duration", withProperties: ["years", "months", "weeks", "days", "hours", "minutes", "seconds", "milliseconds", "microseconds", "nanoseconds", "sign", "blank"], withMethods: ["with", "negated", "abs", "add", "subtract", "round", "total"] + commonStringifierMethods)

    static let jsTemporalDurationConstructor = ILType.functionAndConstructor([.opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number)] => .jsTemporalDuration) + .object(ofGroup: "TemporalDurationConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])

    fileprivate static let timeProperties = ["hour", "minute", "second", "millisecond", "microsecond", "nanosecond"]
    static let jsTemporalPlainTime = ILType.object(ofGroup: "Temporal.PlainTime", withProperties: timeProperties, withMethods: ["add", "subtract", "with", "until", "since", "round", "equals"] + commonStringifierMethods)

    static let jsTemporalPlainTimeConstructor = ILType.functionAndConstructor([.opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number)] => .jsTemporalPlainTime) + .object(ofGroup: "TemporalPlainTimeConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])

    static let jsTemporalCalendarEnum = ILType.enumeration(ofName: "temporalCalendar", withValues: ["buddhist", "chinese", "coptic", "dangi", "ethioaa", "ethiopic", "ethiopic-amete-alem", "gregory", "hebrew", "indian", "islamic-civil", "islamic-tbla", "islamic-umalqura", "islamicc", "iso8601", "japanese", "persian", "roc"])

    fileprivate static let yearMonthProperties = ["calendarId", "era", "eraYear", "year", "month", "monthCode", "daysInMonth", "daysInYear", "monthsInYear", "inLeapYear"]

    static let jsTemporalPlainYearMonth = ILType.object(ofGroup: "Temporal.PlainYearMonth", withProperties: yearMonthProperties, withMethods: ["with", "add", "subtract", "until", "since", "equals", "toPlainDate"] + commonStringifierMethods)

    static let jsTemporalPlainYearMonthConstructor = ILType.functionAndConstructor([.integer, .integer, .opt(.jsTemporalCalendarEnum), .opt(.integer)] => .jsTemporalPlainYearMonth) + .object(ofGroup: "TemporalPlainYearMonthConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])

    static let jsTemporalPlainMonthDay = ILType.object(ofGroup: "Temporal.PlainMonthDay", withProperties: ["calendarId", "monthCode", "day"], withMethods: ["with", "equals", "toPlainDate"] + commonStringifierMethods)

    static let jsTemporalPlainMonthDayConstructor = ILType.functionAndConstructor([.integer, .integer, .opt(.jsTemporalCalendarEnum), .opt(.integer)] => .jsTemporalPlainMonthDay) + .object(ofGroup: "TemporalPlainMonthDayConstructor", withProperties: ["prototype"], withMethods: ["from"])

    fileprivate static let dateProperties = yearMonthProperties + ["day", "dayOfYear", "dayOfWeek", "weekOfYear", "yearOfWeek", "daysInWeek"]

    static let jsTemporalPlainDate = ILType.object(ofGroup: "Temporal.PlainDate", withProperties: dateProperties, withMethods: ["toPlainYearMonth", "toPlainMonthDay", "add", "subtract", "with", "withCalendar", "until", "since", "equals", "toPlainDateTime", "toZonedDateTime"] + commonStringifierMethods)

    static let jsTemporalPlainDateConstructor = ILType.functionAndConstructor([.number, .number, .number, .opt(.jsTemporalCalendarEnum)] => .jsTemporalPlainDate) + .object(ofGroup: "TemporalPlainDateConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])


    static let jsTemporalPlainDateTime = ILType.object(ofGroup: "Temporal.PlainDateTime", withProperties: dateProperties + timeProperties, withMethods: ["with", "withPlainTime", "withCalendar", "add", "subtract", "until", "since", "round", "equals", "toZonedDateTime", "toPlainDate", "toPlainTime"] + commonStringifierMethods)

    static let jsTemporalPlainDateTimeConstructor = ILType.functionAndConstructor([.number, .number, .number, .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.number), .opt(.jsTemporalCalendarEnum)] => .jsTemporalPlainDateTime) + .object(ofGroup: "TemporalPlainDateTimeConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])

    static let jsTemporalZonedDateTime = ILType.object(ofGroup: "Temporal.ZonedDateTime", withProperties: dateProperties + timeProperties + ["timeZoneId", "epochMilliseconds", "epochNanoseconds", "offsetNanoseconds", "offset"], withMethods: ["with", "withPlainTime", "withTimeZone", "withCalendar", "add", "subtract", "until", "since", "round", "equals", "startOfDay", "getTimeZoneTransition", "toInstant", "toPlainDate", "toPlainTime", "toPlainDateTime"] + commonStringifierMethods)

    static let jsTemporalZonedDateTimeConstructor = ILType.functionAndConstructor([.bigint, .string, .opt(.jsTemporalCalendarEnum)] => .jsTemporalZonedDateTime) + .object(ofGroup: "TemporalZonedDateTimeConstructor", withProperties: ["prototype"], withMethods: ["from", "compare"])

    static let jsTemporalNow = ILType.object(ofGroup: "Temporal.Now", withProperties: [], withMethods: ["timeZoneId", "instant", "plainDateTimeISO", "zonedDateTimeISO", "plainDateISO", "plainTimeISO"])
}

public extension ObjectGroup {
    // Creates an object group representing a "prototype" object on a built-in, like Date.prototype.
    // These objects are somewhat special in JavaScript as they describe an object which has
    // methods on them for which you shall not call them with the bound this as a receiver, e.g.
    // `Date.prototype.getTime()` fails as `Date.prototype` is not a `Date`.
    // Therefore the methods are registered as properties, so Fuzzilli doesn't generate calls for
    // them. Instead Fuzzilli generates GetProperty operations for them which will then be typed as
    // an `ILType.unboundFunction` which knows the required receiver type (in the example `Date`),
    // so Fuzzilli can generate sequences like `Date.prototype.getTime.call(new Date())`.
    static func createPrototypeObjectGroup(_ receiver: ObjectGroup) -> ObjectGroup {
        let name = receiver.name + ".prototype"
        var properties = Dictionary(uniqueKeysWithValues: receiver.methods.map {
            ($0.0, ILType.unboundFunction($0.1.first, receiver: receiver.instanceType)) })
        // These functions are getters instead of regular functions, and error when called
        // on the prototype. We hide them from the prototype object to avoid
        // generating `let v0 = Intl.DateTimeFormat.prototype.format`.
        // https://tc39.es/ecma402/#sec-intl.datetimeformat.prototype.format
        if receiver.name == "Intl.DateTimeFormat" || receiver.name == "Intl.NumberFormat" {
            properties.removeValue(forKey: "format")
        } else if receiver.name == "Intl.Collator" {
            properties.removeValue(forKey: "compare")
        }
        return ObjectGroup(
            name: name,
            instanceType: .object(ofGroup: name, withProperties: properties.map {$0.0}, withMethods: []),
            properties: properties,
            methods: [:]
        )
    }
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
            "concat"      : [.jsAnything...] => .jsString,
            "includes"    : [.jsAnything, .opt(.integer)] => .boolean,
            "endsWith"    : [.string, .opt(.integer)] => .boolean,
            "indexOf"     : [.jsAnything, .opt(.integer)] => .integer,
            "lastIndexOf" : [.jsAnything, .opt(.integer)] => .integer,
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
            "at"             : [.integer] => .jsAnything,
            "copyWithin"     : [.integer, .integer, .opt(.integer)] => .jsArray,
            "entries"        : [] => .jsArray,
            "every"          : [.function(), .opt(.object())] => .boolean,
            "fill"           : [.jsAnything, .opt(.integer), .opt(.integer)] => .undefined,
            "find"           : [.function(), .opt(.object())] => .jsAnything,
            "findIndex"      : [.function(), .opt(.object())] => .integer,
            "findLast"       : [.function(), .opt(.object())] => .jsAnything,
            "findLastIndex"  : [.function(), .opt(.object())] => .integer,
            "forEach"        : [.function(), .opt(.object())] => .undefined,
            "includes"       : [.jsAnything, .opt(.integer)] => .boolean,
            "indexOf"        : [.jsAnything, .opt(.integer)] => .integer,
            "join"           : [.string] => .jsString,
            "keys"           : [] => .object(),          // returns an array iterator
            "lastIndexOf"    : [.jsAnything, .opt(.integer)] => .integer,
            "reduce"         : [.function(), .opt(.jsAnything)] => .jsAnything,
            "reduceRight"    : [.function(), .opt(.jsAnything)] => .jsAnything,
            "reverse"        : [] => .undefined,
            "some"           : [.function(), .opt(.jsAnything)] => .boolean,
            "sort"           : [.function()] => .undefined,
            "values"         : [] => .object(),
            "pop"            : [] => .jsAnything,
            "push"           : [.jsAnything...] => .integer,
            "shift"          : [] => .jsAnything,
            "splice"         : [.integer, .opt(.integer), .jsAnything...] => .jsArray,
            "unshift"        : [.jsAnything...] => .integer,
            "concat"         : [.jsAnything...] => .jsArray,
            "filter"         : [.function(), .opt(.object())] => .jsArray,
            "map"            : [.function(), .opt(.object())] => .jsArray,
            "slice"          : [.opt(.integer), .opt(.integer)] => .jsArray,
            "flat"           : [.opt(.integer)] => .jsArray,
            "flatMap"        : [.function(), .opt(.jsAnything)] => .jsArray,
            "toString"       : [] => .jsString,
            "toLocaleString" : [.opt(.string), .opt(.object())] => .jsString,
            "toReversed"     : [] => .jsArray,
            "toSorted"       : [.opt(.function())] => .jsArray,
            "toSpliced"      : [.integer, .opt(.integer), .jsAnything...] => .jsArray,
            "with"           : [.integer, .jsAnything] => .jsArray,
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
            "apply" : [.object(), .object()] => .jsAnything,
            "call"  : [.object(), .jsAnything...] => .jsAnything,
            "bind"  : [.object(), .jsAnything...] => .jsAnything,
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
            "next"   : [.opt(.jsAnything)] => .object(withProperties: ["done", "value"]),
            "return" : [.opt(.jsAnything)] => .object(withProperties: ["done", "value"]),
            "throw"  : [.opt(.jsAnything)] => .object(withProperties: ["done", "value"])
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
            "delete"  : [.jsAnything] => .boolean,
            "entries" : [] => .object(),
            "forEach" : [.function(), .opt(.object())] => .undefined,
            "get"     : [.jsAnything] => .jsAnything,
            "has"     : [.jsAnything] => .boolean,
            "keys"    : [] => .object(),
            "set"     : [.jsAnything, .jsAnything] => .jsMap,
            "values"  : [] => .object(),
        ]
    )

    /// ObjectGroup modelling JavaScript WeakMap objects
    static let jsWeakMaps = ObjectGroup(
        name: "WeakMap",
        instanceType: .jsWeakMap,
        properties: [:],
        methods: [
            "delete" : [.jsAnything] => .boolean,
            "get"    : [.jsAnything] => .jsAnything,
            "has"    : [.jsAnything] => .boolean,
            "set"    : [.jsAnything, .jsAnything] => .jsWeakMap,
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
            "add"     : [.jsAnything] => .jsSet,
            "clear"   : [] => .undefined,
            "delete"  : [.jsAnything] => .boolean,
            "entries" : [] => .object(),
            "forEach" : [.function(), .opt(.object())] => .undefined,
            "has"     : [.jsAnything] => .boolean,
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
            "add"    : [.jsAnything] => .jsWeakSet,
            "delete" : [.jsAnything] => .boolean,
            "has"    : [.jsAnything] => .boolean,
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
            "register"   : [.object(), .jsAnything, .opt(.object())] => .object(),
            "unregister" : [.jsAnything] => .undefined,
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
        // Extra methods from the base64 proposal: https://tc39.es/proposal-arraybuffer-base64/
        let extraMethods: [String: Signature] = variant != "Uint8Array" ? [:] : [
            "toBase64": [.opt(OptionsBag.toBase64Settings.group.instanceType)] => .string,
            "toHex": [] => .string,
            "setFromBase64": [.string, .opt(OptionsBag.fromBase64Settings.group.instanceType)]
                => .object(withProperties: ["read", "written"]),
            "setFromHex": [.string] => .object(withProperties: ["read", "written"]),
        ]
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
                "at"          : [.integer] => .jsAnything,
                "copyWithin"  : [.integer, .integer, .opt(.integer)] => .undefined,
                "entries"     : [] => .jsArray,
                "every"       : [.function(), .opt(.object())] => .boolean,
                "fill"        : [.jsAnything, .opt(.integer), .opt(.integer)] => .undefined,
                "find"        : [.function(), .opt(.object())] => .jsAnything,
                "findIndex"   : [.function(), .opt(.object())] => .integer,
                "findLast"    : [.function(), .opt(.object())] => .jsAnything,
                "findLastIndex"  : [.function(), .opt(.object())] => .integer,
                "forEach"     : [.function(), .opt(.object())] => .undefined,
                "includes"    : [.jsAnything, .opt(.integer)] => .boolean,
                "indexOf"     : [.jsAnything, .opt(.integer)] => .integer,
                "join"        : [.string] => .jsString,
                "keys"        : [] => .object(),          // returns an array iterator
                "lastIndexOf" : [.jsAnything, .opt(.integer)] => .integer,
                "reduce"      : [.function(), .opt(.jsAnything)] => .jsAnything,
                "reduceRight" : [.function(), .opt(.jsAnything)] => .jsAnything,
                "reverse"     : [] => .undefined,
                "set"         : [.object(), .opt(.integer)] => .undefined,
                "some"        : [.function(), .opt(.jsAnything)] => .boolean,
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
                "with"           : [.integer, .jsAnything] => .jsTypedArray(variant),
            ].merging(extraMethods) { _, _ in fatalError("duplicate method") }
        )
    }

    static let jsUint8ArrayPrototype = createPrototypeObjectGroup(jsTypedArrays("Uint8Array"))

    static let jsUint8ArrayConstructor = ObjectGroup(
        name: "Uint8ArrayConstructor",
        instanceType: .jsUint8ArrayConstructor,
        properties: [
            "prototype": jsUint8ArrayPrototype.instanceType,
        ],
        methods: [
            "fromBase64": [.plain(.string), .opt(OptionsBag.fromBase64Settings.group.instanceType)] => .jsUint8Array,
            "fromHex": [.plain(.string)] => .jsUint8Array,
        ]
    )

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

    static let jsPromisePrototype = createPrototypeObjectGroup(jsPromises)

    /// ObjectGroup modelling the JavaScript Promise constructor builtin
    static let jsPromiseConstructor = ObjectGroup(
        name: "PromiseConstructor",
        constructorPath: "Promise",
        instanceType: .jsPromiseConstructor,
        properties: [
            "prototype" : jsPromisePrototype.instanceType
        ],
        methods: [
            "resolve"    : [.jsAnything] => .jsPromise,
            "reject"     : [.jsAnything] => .jsPromise,
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
            "toTemporalInstant"     : [] => .jsTemporalInstant,
        ]
    )

    static let jsDatePrototype = createPrototypeObjectGroup(jsDate)

    /// ObjectGroup modelling the JavaScript Date constructor
    static let jsDateConstructor = ObjectGroup(
        name: "DateConstructor",
        constructorPath: "Date",
        instanceType: .jsDateConstructor,
        properties: [
            "prototype" : jsDatePrototype.instanceType
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
        constructorPath: "Object",
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
        constructorPath: "Array",
        instanceType: .jsArrayConstructor,
        properties: [
            // This might seem wrong, note however that `Array.isArray(Array.prototype)` is true.
            "prototype" : .jsArray,
        ],
        methods: [
            "from"    : [.jsAnything, .opt(.function()), .opt(.object())] => .jsArray,
            "isArray" : [.jsAnything] => .boolean,
            "of"      : [.jsAnything...] => .jsArray,
        ]
    )

    static let jsArrayBufferPrototype = createPrototypeObjectGroup(jsArrayBuffers)

    static let jsArrayBufferConstructor = ObjectGroup(
        name: "ArrayBufferConstructor",
        constructorPath: "ArrayBuffer",
        instanceType: .jsArrayBufferConstructor,
        properties: [
            "prototype" : jsArrayBufferPrototype.instanceType
        ],
        methods: [
            "isView" : [.jsAnything] => .boolean
        ]
    )

    static let jsSharedArrayBufferPrototype = createPrototypeObjectGroup(jsSharedArrayBuffers)

    static let jsSharedArrayBufferConstructor = ObjectGroup(
        name: "SharedArrayBufferConstructor",
        constructorPath: "SharedArrayBuffer",
        instanceType: .jsSharedArrayBufferConstructor,
        properties: [
            "prototype" : jsSharedArrayBufferPrototype.instanceType
        ],
        methods: [:]
    )

    static let jsStringPrototype = createPrototypeObjectGroup(jsStrings)

    /// Object group modelling the JavaScript String constructor builtin
    static let jsStringConstructor = ObjectGroup(
        name: "StringConstructor",
        constructorPath: "String",
        instanceType: .jsStringConstructor,
        properties: [
            "prototype" : jsStringPrototype.instanceType
        ],
        methods: [
            "fromCharCode"  : [.jsAnything...] => .jsString,
            "fromCodePoint" : [.jsAnything...] => .jsString,
            "raw"           : [.jsAnything...] => .jsString
        ]
    )

    /// Object group modelling the JavaScript Symbol constructor builtin
    static let jsSymbolConstructor = ObjectGroup(
        name: "SymbolConstructor",
        constructorPath: "Symbol",
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
        constructorPath: "BigInt",
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
        constructorPath: "Boolean",
        instanceType: .jsBooleanConstructor,
        properties: [
            "prototype" : .object()
        ],
        methods: [:]
    )

    /// Object group modelling the JavaScript Number constructor builtin
    static let jsNumberConstructor = ObjectGroup(
        name: "NumberConstructor",
        constructorPath: "Number",
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
            "isNaN"         : [.jsAnything] => .boolean,
            "isFinite"      : [.jsAnything] => .boolean,
            "isInteger"     : [.jsAnything] => .boolean,
            "isSafeInteger" : [.jsAnything] => .boolean,
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
            "abs"    : [.jsAnything] => .number,
            "acos"   : [.jsAnything] => .number,
            "acosh"  : [.jsAnything] => .number,
            "asin"   : [.jsAnything] => .number,
            "asinh"  : [.jsAnything] => .number,
            "atan"   : [.jsAnything] => .number,
            "atanh"  : [.jsAnything] => .number,
            "atan2"  : [.jsAnything, .jsAnything] => .number,
            "cbrt"   : [.jsAnything] => .number,
            "ceil"   : [.jsAnything] => .number,
            "clz32"  : [.jsAnything] => .number,
            "cos"    : [.jsAnything] => .number,
            "cosh"   : [.jsAnything] => .number,
            "exp"    : [.jsAnything] => .number,
            "expm1"  : [.jsAnything] => .number,
            "floor"  : [.jsAnything] => .number,
            "fround" : [.jsAnything] => .number,
            "hypot"  : [.jsAnything...] => .number,
            "imul"   : [.jsAnything, .jsAnything] => .integer,
            "log"    : [.jsAnything] => .number,
            "log1p"  : [.jsAnything] => .number,
            "log10"  : [.jsAnything] => .number,
            "log2"   : [.jsAnything] => .number,
            "max"    : [.jsAnything...] => .jsAnything,
            "min"    : [.jsAnything...] => .jsAnything,
            "pow"    : [.jsAnything, .jsAnything] => .number,
            "random" : [] => .number,
            "round"  : [.jsAnything] => .number,
            "sign"   : [.jsAnything] => .number,
            "sin"    : [.jsAnything] => .number,
            "sinh"   : [.jsAnything] => .number,
            "sqrt"   : [.jsAnything] => .number,
            "tan"    : [.jsAnything] => .number,
            "tanh"   : [.jsAnything] => .number,
            "trunc"  : [.jsAnything] => .number,
        ]
    )

    /// ObjectGroup modelling the JavaScript JSON builtin
    static let jsJSONObject = ObjectGroup(
        name: "JSON",
        instanceType: .jsJSONObject,
        properties: [:],
        methods: [
            "parse"     : [.string, .opt(.function())] => .jsAnything,
            "stringify" : [.jsAnything, .opt(.function()), .opt(.number | .string)] => .jsString,
        ]
    )

    /// ObjectGroup modelling the JavaScript Reflect builtin
    static let jsReflectObject = ObjectGroup(
        name: "Reflect",
        instanceType: .jsReflectObject,
        properties: [:],
        methods: [
            "apply"                    : [.function(), .jsAnything, .object()] => .jsAnything,
            "construct"                : [.constructor(), .object(), .opt(.object())] => .jsAnything,
            "defineProperty"           : [.object(), .string, .object()] => .boolean,
            "deleteProperty"           : [.object(), .string] => .boolean,
            "get"                      : [.object(), .string, .opt(.object())] => .jsAnything,
            "getOwnPropertyDescriptor" : [.object(), .string] => .jsAnything,
            "getPrototypeOf"           : [.jsAnything] => .jsAnything,
            "has"                      : [.object(), .string] => .boolean,
            "isExtensible"             : [.jsAnything] => .boolean,
            "ownKeys"                  : [.jsAnything] => .jsArray,
            "preventExtensions"        : [.object()] => .boolean,
            "set"                      : [.object(), .string, .jsAnything, .opt(.object())] => .boolean,
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
                "cause"       : .jsAnything,
                "stack"       : .jsString,
            ],
            methods: [
                "toString" : [] => .jsString,
            ]
        )
    }

    // TODO(mliedtke): We need to construct these to make code generators be able to provide
    // somewhat reasonable compile options.
    static let jsWebAssemblyCompileOptions = ObjectGroup(
        name: "WebAssemblyCompileOptions",
        instanceType: nil,
        properties: [
            "builtins": .jsArray,
            "importedStringConstants": .jsString,
        ],
        methods: [:]
    )

    // Note: This supports all typed arrays, however, that would add a huge amount of overloads, so
    // we only add a few selected typed arrays here.
    static let wasmBufferTypes = [
        ILType.jsArrayBuffer, .jsSharedArrayBuffer, .jsTypedArray("Int8Array"),
        .jsTypedArray("Float32Array"), .jsTypedArray("BigUint64Array")]

    static let jsWebAssemblyModule = ObjectGroup(
        name: "WebAssembly.Module",
        instanceType: .jsWebAssemblyModule,
        properties: [:],
        methods: [:]
    )

    static let jsWebAssemblyModuleConstructor = ObjectGroup(
        name: "WebAssemblyModuleConstructor",
        constructorPath: "WebAssembly.Module",
        instanceType: .jsWebAssemblyModuleConstructor,
        properties: [
            "prototype": .object()
        ],
        methods: [
            "customSections": [.plain(jsWebAssemblyModule.instanceType), .plain(.jsString)] => .jsArray,
            "exports": [.plain(jsWebAssemblyModule.instanceType)] => .jsArray,
            "imports": [.plain(jsWebAssemblyModule.instanceType)] => .jsArray,
        ]
    )

    static let jsWebAssemblyGlobalPrototype = createPrototypeObjectGroup(jsWasmGlobal)

    static let jsWebAssemblyGlobalConstructor = ObjectGroup(
        name: "WebAssemblyGlobalConstructor",
        constructorPath: "WebAssembly.Global",
        instanceType: .jsWebAssemblyGlobalConstructor,
        properties: [
            "prototype": jsWebAssemblyGlobalPrototype.instanceType,
        ],
        methods: [:]
    )

    static let jsWebAssemblyInstanceConstructor = ObjectGroup(
        name: "WebAssemblyInstanceConstructor",
        constructorPath: "WebAssembly.Instance",
        instanceType: .jsWebAssemblyInstanceConstructor,
        properties: [
            "prototype": .object(),
        ],
        methods: [:]
    )

    static let jsWebAssemblyInstance = ObjectGroup(
        name: "WebAssembly.Instance",
        instanceType: .jsWebAssemblyInstance,
        properties: [
            "exports": .object(),
        ],
        methods: [:]
    )

    static let jsWebAssemblyMemoryPrototype = createPrototypeObjectGroup(jsWasmMemory)

    static let jsWebAssemblyMemoryConstructor = ObjectGroup(
        name: "WebAssemblyMemoryConstructor",
        constructorPath: "WebAssembly.Memory",
        instanceType: .jsWebAssemblyMemoryConstructor,
        properties: [
            "prototype": jsWebAssemblyMemoryPrototype.instanceType,
        ],
        methods: [:]
    )

    static let jsWebAssemblyTablePrototype = createPrototypeObjectGroup(wasmTable)

    static let jsWebAssemblyTableConstructor = ObjectGroup(
        name: "WebAssemblyTableConstructor",
        constructorPath: "WebAssembly.Table",
        instanceType: .jsWebAssemblyTableConstructor,
        properties: [
            "prototype": jsWebAssemblyTablePrototype.instanceType,
        ],
        methods: [:]
    )

    static let jsWebAssemblyTagPrototype = createPrototypeObjectGroup(jsWasmTag)

    static let jsWebAssemblyTagConstructor = ObjectGroup(
        name: "WebAssemblyTagConstructor",
        constructorPath: "WebAssembly.Tag",
        instanceType: .jsWebAssemblyTagConstructor,
        properties: [
            "prototype": jsWebAssemblyTagPrototype.instanceType,
        ],
        methods: [:]
    )

    static let jsWebAssemblyException = ObjectGroup(
        name: "WebAssembly.Exception",
        instanceType: nil,
        properties: [
            "stack": .string | .undefined,
        ],
        methods: [
            "getArg": [.plain(jsWasmTag.instanceType), .plain(.integer)] => .jsAnything,
            "is": [.plain(jsWasmTag.instanceType)] => .boolean,
        ]
    )

    static let jsWebAssemblyExceptionPrototype = createPrototypeObjectGroup(jsWebAssemblyException)

    static let jsWebAssemblyExceptionConstructor = ObjectGroup(
        name: "WebAssemblyExceptionConstructor",
        constructorPath: "WebAssembly.Exception",
        instanceType: .jsWebAssemblyExceptionConstructor,
        properties: [
            "prototype": jsWebAssemblyExceptionPrototype.instanceType,
        ],
        methods: [:]
    )

    // WebAssembly.CompileError, .LinkError, .RuntimeError don't offer anything interesting but a
    // constructor.
    fileprivate static let webAssemblyErrorConstructorType =
        ILType.constructor([.opt(.string), .opt(.object() | .string), .opt(.string)] => .object())
        + .object(withProperties: ["prototype"])
    fileprivate static let webAssemblySuspendingConstructorType = ILType.constructor([.plain(.function())] => .object())

    static let jsWebAssembly = ObjectGroup(
        name: "WebAssembly",
        instanceType: nil,
        properties: [
            "JSTag": .object(ofGroup: "WasmTag", withWasmType: WasmTagType([.wasmExternRef], isJSTag: true)),
            "Module": .jsWebAssemblyModuleConstructor,
            "Global": .jsWebAssemblyGlobalConstructor,
            "Instance": .jsWebAssemblyInstanceConstructor,
            "Memory": .jsWebAssemblyMemoryConstructor,
            "Table": .jsWebAssemblyTableConstructor,
            "Tag": .jsWebAssemblyTagConstructor,
            "Exception": .jsWebAssemblyExceptionConstructor,
            "CompileError": webAssemblyErrorConstructorType,
            "LinkError": webAssemblyErrorConstructorType,
            "RuntimeError": webAssemblyErrorConstructorType,
            "SuspendError": webAssemblyErrorConstructorType,
            "Suspending": webAssemblySuspendingConstructorType,
        ],
        overloads: [
            "compile": wasmBufferTypes.map {
                [.plain($0), .opt(jsWebAssemblyCompileOptions.instanceType)] => .jsPromise},
            // TODO: The first parameter should be a Response which Fuzzilli doesn't know as it is
            // mostly used by WebAPIs like fetch().
            "compileStreaming": [
                [.object(), .opt(jsWebAssemblyCompileOptions.instanceType)] => .jsPromise],
            "instantiate": wasmBufferTypes.map {
                [.plain($0), /*imports*/ .opt(.object()),
                 .opt(jsWebAssemblyCompileOptions.instanceType)] => .jsPromise},
            // TODO: Same as compileStreaming(), the first parameter has to be a Response.
            "instantiateStreaming": [
                [.object(), /*imports*/ .opt(.object()),
                 .opt(jsWebAssemblyCompileOptions.instanceType)] => .jsPromise],
            "validate": wasmBufferTypes.map {
                [.plain($0), .opt(jsWebAssemblyCompileOptions.instanceType)] => .jsPromise},
            // The argument needs to be an exported Wasm function. Fuzzilli's type system does not
            // distinguish between Wasm and JS functions, so we can't express this precisely.
            "promising": [[.function()] => .function()]
        ]
    )

    /// ObjectGroup modelling JavaScript WebAssembly Global objects.
    static let jsWasmGlobal = ObjectGroup(
        name: "WasmGlobal",
        instanceType: nil,
        properties: [
            // TODO: Try using precise JS types based on the global's underlying valuetype (e.g. float for f32 and f64).
            "value" : .jsAnything
        ],
        methods: ["valueOf": [] => .jsAnything]
    )

    /// ObjectGroup modelling JavaScript WebAssembly Memory objects.
    static let jsWasmMemory = ObjectGroup(
        name: "WasmMemory",
        instanceType: .object(ofGroup: "WasmMemory", withProperties: ["buffer"], withMethods: ["grow", "toResizableBuffer", "toFixedLengthBuffer"]),
        properties: [
            "buffer" : .jsArrayBuffer | .jsSharedArrayBuffer
        ],
        methods: [
            "grow" : [.number] => .number,
            "toResizableBuffer" : [] => (.jsArrayBuffer | .jsSharedArrayBuffer),
            "toFixedLengthBuffer" : [] => (.jsArrayBuffer | .jsSharedArrayBuffer),
        ]
    )

    // TOOD(mliedtke): Reconsider whether WebAssembly.Tag and WebAssembly.JSTag should share the
    // same object group. When split, we can register the type() prototype method.
    static let jsWasmTag = ObjectGroup(
        name: "WasmTag",
        instanceType: nil, // inferred
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
            "get": [.number] => .jsAnything,
            "grow": [.number, .opt(.jsAnything)] => .number,
            "set": [.number, .jsAnything] => .undefined,
        ]
    )

    static let jsWasmSuspendingObject = ObjectGroup(
        name: "WasmSuspendingObject",
        instanceType: .object(ofGroup: "WasmSuspendingObject"),
        properties: [:],
        methods: [:]
    )

    // Temporal types

    // Helpers for constructing common signatures
    private static func temporalAddSubtractSignature(forType: ILType, needsOverflow: Bool) -> [Signature] {
        if needsOverflow {
            return jsTemporalDurationLikeParameters.map { [.plain($0), .opt(jsTemporalOverflowSettings)] => forType }
        } else {
            return jsTemporalDurationLikeParameters.map { [.plain($0)] => forType }
        }
    }
    private static func temporalUntilSinceSignature(possibleParams: [ILType]) -> [Signature] {
        return possibleParams.map { [.plain($0), .opt(jsTemporalDifferenceSettings)] => .jsTemporalDuration }
    }
    private static func temporalFromSignature(forType: ILType, possibleParams: [ILType], settingsArg: ILType? = nil) -> [Signature] {
        if let settingsArg {
            return possibleParams.map { [.plain($0), .opt(settingsArg)] => forType }
        } else {
            return possibleParams.map { [.plain($0), .opt(jsTemporalDifferenceSettings)] => forType }
        }
    }
    private static func temporalCompareSignature(possibleParams: [ILType], settingsArg: ILType? = nil) -> [Signature] {
        possibleParams.flatMap { param1 in
            return possibleParams.map { param2 in
                if let settingsArg {
                    return [.plain(param1), .plain(param2), .opt(settingsArg)] => .number
                } else {
                    return [.plain(param1), .plain(param2)] => .number
                }
            }
        }
    }

    private static func temporalEqualsSignature(possibleParams: [ILType]) -> [Signature] {
        return possibleParams.map { [.plain($0)] => .boolean }
    }

    private static func temporalTimeZoneLikeSignature(signature: (ILType) -> Signature) -> [Signature] {
        return [
            signature(jsTemporalTimeZoneLike),
            signature(.jsTemporalZonedDateTime),
        ]
    }

    /// Object group modelling the JavaScript Temporal builtin
    static let jsTemporalObject = ObjectGroup(
        name: "Temporal",
        instanceType: .jsTemporalObject,
        properties: [
            "Instant"  : .jsTemporalInstantConstructor,
            "Duration"  : .jsTemporalDurationConstructor,
            "PlainTime"  : .jsTemporalPlainTimeConstructor,
            "PlainYearMonth"  : .jsTemporalPlainYearMonthConstructor,
            "PlainMonthDay"  : .jsTemporalPlainMonthDayConstructor,
            "PlainDate"  : .jsTemporalPlainDateConstructor,
            "PlainDateTime"  : .jsTemporalPlainDateTimeConstructor,
            "ZonedDateTime"  : .jsTemporalZonedDateTimeConstructor,
            "Now": .jsTemporalNow,
        ],
        methods: [:]
    )

    static let jsTemporalNow = ObjectGroup(
        name: "Temporal.Now",
        instanceType: .jsTemporalNow,
        properties: [:],
        overloads: [
            "timeZoneId": [[] => .string],
            "instant": [[] => .jsTemporalInstant],
            "plainDateTimeISO": temporalTimeZoneLikeSignature { [.opt($0)] => .jsTemporalPlainDateTime },
            "zonedDateTimeISO": temporalTimeZoneLikeSignature { [.opt($0)] => .jsTemporalZonedDateTime },
            "plainDateISO": temporalTimeZoneLikeSignature { [.opt($0)] => .jsTemporalPlainDate },
            "plainTimeISO": temporalTimeZoneLikeSignature { [.opt($0)] => .jsTemporalPlainTime },
        ]
    )

    /// ObjectGroup modelling JavaScript Temporal.Instant objects
    static let jsTemporalInstant = ObjectGroup(
        name: "Temporal.Instant",
        instanceType: .jsTemporalInstant,
        properties: [
            "epochMilliseconds": .number,
            "epochNanoseconds": .bigint,
        ],
        overloads: [
            "add": temporalAddSubtractSignature(forType: .jsTemporalInstant, needsOverflow: false),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalInstant, needsOverflow: false),
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalInstantLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalInstantLikeParameters),
            "round": [[.plain(jsTemporalRoundTo)] => .jsTemporalInstant],
            "equals": temporalEqualsSignature(possibleParams: jsTemporalInstantLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
            "toZonedDateTimeISO": temporalTimeZoneLikeSignature { [.plain($0)] => .jsTemporalZonedDateTime },
        ]
    )

    static let jsTemporalInstantPrototype = createPrototypeObjectGroup(jsTemporalInstant)

    /// ObjectGroup modelling the JavaScript Temporal.Instant constructor
    static let jsTemporalInstantConstructor = ObjectGroup(
        name: "TemporalInstantConstructor",
        constructorPath: "Temporal.Instant",
        instanceType: .jsTemporalInstantConstructor,
        properties: [
            "prototype" : jsTemporalInstantPrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalInstant, possibleParams: jsTemporalInstantLikeParameters),
            "fromEpochMilliseconds": [[.number] => .jsTemporalInstant],
            "fromEpochNanoseconds": [[.bigint] => .jsTemporalInstant],
            "compare": temporalCompareSignature(possibleParams: jsTemporalInstantLikeParameters),
        ]
    )
    /// ObjectGroup modelling JavaScript Temporal.Duration objects
    static let jsTemporalDuration = ObjectGroup(
        name: "Temporal.Duration",
        instanceType: .jsTemporalDuration,
        properties: [
            "years": .number,
            "months": .number,
            "weeks": .number,
            "days": .number,
            "hours": .number,
            "minutes": .number,
            "seconds": .number,
            "milliseconds": .number,
            "microseconds": .number,
            "nanoseconds": .number,
            "sign": .number,
            "blank": .boolean,
        ],
        overloads: [
            "with": [[.plain(jsTemporalDurationLikeObject.instanceType)] => .jsTemporalDuration],
            "negated": [[] => .jsTemporalDuration],
            "abs": [[] => .jsTemporalDuration],
            "add": temporalAddSubtractSignature(forType: .jsTemporalDuration, needsOverflow: false),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalDuration, needsOverflow: false),
            "round": [[.plain(jsTemporalDurationRoundToSettings)] => .jsTemporalDuration],
            "total": [[.plain(jsTemporalDurationTotalOfSettings)] => .jsTemporalDuration],
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
        ]
    )

    static let jsTemporalDurationPrototype = createPrototypeObjectGroup(jsTemporalDuration)

    /// ObjectGroup modelling the JavaScript Temporal.Duration constructor
    static let jsTemporalDurationConstructor = ObjectGroup(
        name: "TemporalDurationConstructor",
        constructorPath: "Temporal.Duration",
        instanceType: .jsTemporalDurationConstructor,
        properties: [
            "prototype" : jsTemporalDurationPrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalDuration, possibleParams: jsTemporalDurationLikeParameters),
            "compare": temporalCompareSignature(possibleParams: jsTemporalDurationLikeParameters, settingsArg: jsTemporalDurationCompareSettings),
        ]
    )

    static let jsTemporalPlainTime = ObjectGroup(
        name: "Temporal.PlainTime",
        instanceType: .jsTemporalPlainTime,
        properties: [
            "hour": .number,
            "minute": .number,
            "second": .number,
            "millisecond": .number,
            "microsecond": .number,
            "nanosecond": .number,
        ],
        overloads: [
            "add": temporalAddSubtractSignature(forType: .jsTemporalPlainTime, needsOverflow: false),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalPlainTime, needsOverflow: false),
            "with": [[.plain(jsTemporalPlainTimeLikeObject.instanceType), .opt(jsTemporalOverflowSettings)] => .jsTemporalPlainTime],
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalPlainTimeLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalPlainTimeLikeParameters),
            "round": [[.plain(jsTemporalRoundTo)] => .jsTemporalPlainTime],
            "equals": temporalEqualsSignature(possibleParams: jsTemporalPlainTimeLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
        ]
    )

    static let jsTemporalPlainTimePrototype = createPrototypeObjectGroup(jsTemporalPlainTime)

    /// ObjectGroup modelling the JavaScript Temporal.PlainTime constructor
    static let jsTemporalPlainTimeConstructor = ObjectGroup(
        name: "TemporalPlainTimeConstructor",
        constructorPath: "Temporal.PlainTime",
        instanceType: .jsTemporalPlainTimeConstructor,
        properties: [
            "prototype" : jsTemporalPlainTimePrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalPlainTime, possibleParams: jsTemporalPlainTimeLikeParameters),
            "compare": temporalCompareSignature(possibleParams: jsTemporalPlainTimeLikeParameters),
        ]
    )

    private static let jsTemporalPlainYearMonthProperties = [
        "calendarId": .string,
        "era": .string | .undefined,
        "eraYear": .integer | .undefined,
        "year": .integer,
        "month": .integer,
        "monthCode": .string | .undefined,
        "daysInMonth": .integer,
        "daysInYear": .integer,
        "monthsInYear": .integer,
        "inLeapYear": .boolean,
    ];

    static let jsTemporalPlainYearMonth = ObjectGroup(
        name: "Temporal.PlainYearMonth",
        instanceType: .jsTemporalPlainYearMonth,
        properties: jsTemporalPlainYearMonthProperties,
        overloads: [
            "with":  [[.plain(jsTemporalPlainDateLikeObjectForWith.instanceType), .opt(jsTemporalOverflowSettings)] => .jsTemporalPlainYearMonth],
            "add": temporalAddSubtractSignature(forType: .jsTemporalPlainYearMonth, needsOverflow: true),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalPlainYearMonth, needsOverflow: true),
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalPlainYearMonthLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalPlainYearMonthLikeParameters),
            "equals": temporalEqualsSignature(possibleParams: jsTemporalPlainYearMonthLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
            "toPlainDate": [[.plain(jsTemporalPlainDateLikeObject.instanceType)] => .jsTemporalPlainDate],
        ]
    )

    static let jsTemporalPlainYearMonthPrototype = createPrototypeObjectGroup(jsTemporalPlainYearMonth)

    /// ObjectGroup modelling the JavaScript Temporal.PlainYearMonth constructor
    static let jsTemporalPlainYearMonthConstructor = ObjectGroup(
        name: "TemporalPlainYearMonthConstructor",
        constructorPath: "Temporal.PlainYearMonth",
        instanceType: .jsTemporalPlainYearMonthConstructor,
        properties: [
            "prototype" : jsTemporalPlainYearMonthPrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalPlainYearMonth, possibleParams: jsTemporalPlainYearMonthLikeParameters),
            "compare": temporalCompareSignature(possibleParams: jsTemporalPlainYearMonthLikeParameters),
        ]
    )

    static let jsTemporalPlainMonthDay = ObjectGroup(
        name: "Temporal.PlainMonthDay",
        instanceType: .jsTemporalPlainMonthDay,
        properties: [
            "calendarId": .string,
            "monthCode": .string,
            "day": .integer,
        ],
        overloads: [
            "with":  [[.plain(jsTemporalPlainDateLikeObjectForWith.instanceType), .opt(jsTemporalOverflowSettings)] => .jsTemporalPlainYearMonth],
            "equals": temporalEqualsSignature(possibleParams: jsTemporalPlainYearMonthLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
            "toPlainDate": [[.plain(jsTemporalPlainDateLikeObject.instanceType)] => .jsTemporalPlainDate],
        ]
    )

    static let jsTemporalPlainMonthDayPrototype = createPrototypeObjectGroup(jsTemporalPlainMonthDay)

    /// ObjectGroup modelling the JavaScript Temporal.PlainMonthDay constructor.
    static let jsTemporalPlainMonthDayConstructor = ObjectGroup(
        name: "TemporalPlainMonthDayConstructor",
        constructorPath: "Temporal.PlainMonthDay",
        instanceType: .jsTemporalPlainMonthDayConstructor,
        properties: [
            "prototype" : jsTemporalPlainMonthDayPrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalPlainMonthDay, possibleParams: jsTemporalPlainMonthDayLikeParameters),
        ]
    )

    static let jsTemporalPlainDate = ObjectGroup(
        name: "Temporal.PlainDate",
        instanceType: .jsTemporalPlainDate,
        properties: mergeFields(jsTemporalPlainYearMonthProperties, [
            "day": .integer,
            "dayOfWeek": .integer,
            "dayOfYear": .integer,
            "weekOfYear": .integer,
            "yearOfWeek": .integer,
            "daysInWeek": .integer,
        ]),
        overloads: [
            "toPlainYearMonth": [[] => .jsTemporalPlainYearMonth],
            "toPlainMonthDay": [[] => .jsTemporalPlainMonthDay],
            "add": temporalAddSubtractSignature(forType: .jsTemporalPlainDate, needsOverflow: true),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalPlainDate, needsOverflow: true),
            "with":  [[.plain(jsTemporalPlainDateLikeObjectForWith.instanceType), .opt(jsTemporalOverflowSettings)] => .jsTemporalPlainDate],
            "withCalendar": [[.plain(.jsTemporalCalendarEnum)] => .jsTemporalPlainDate],
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalPlainDateLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalPlainDateLikeParameters),
            "equals": temporalEqualsSignature(possibleParams: jsTemporalPlainDateLikeParameters),
            "toPlainDateTime": jsTemporalPlainTimeLikeParameters.map {[.opt($0)] => .jsTemporalPlainDateTime},
            "toZonedDateTime": temporalTimeZoneLikeSignature { [.plain($0)] => .jsTemporalZonedDateTime }
                // Can also accept an object with timezone/time fields
                + [[.plain(OptionsBag.jsTemporalPlainDateToZDTSettings.group.instanceType)] => .jsTemporalZonedDateTime],
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
        ]
    )

    static let jsTemporalPlainDatePrototype = createPrototypeObjectGroup(jsTemporalPlainDate)

    /// ObjectGroup modelling the JavaScript Temporal.PlainDate constructor
    static let jsTemporalPlainDateConstructor = ObjectGroup(
        name: "TemporalPlainDateConstructor",
        constructorPath: "Temporal.PlainDate",
        instanceType: .jsTemporalPlainDateConstructor,
        properties: [
            "prototype" : jsTemporalPlainDatePrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalPlainDate, possibleParams: jsTemporalPlainDateLikeParameters),
            "compare": temporalCompareSignature(possibleParams: jsTemporalPlainDateLikeParameters),
        ]
    )

    static let jsTemporalPlainDateTime = ObjectGroup(
        name: "Temporal.PlainDateTime",
        instanceType: .jsTemporalPlainDateTime,
        properties: mergeFields(jsTemporalPlainDate.properties, jsTemporalPlainTime.properties),
        overloads: [
            "with":  [[.plain(jsTemporalPlainDateTimeLikeObjectForWith.instanceType), .opt(jsTemporalOverflowSettings)] => .jsTemporalPlainDateTime],
            "withPlainTime": jsTemporalPlainTimeLikeParameters.map {[.opt($0)] => .jsTemporalPlainDateTime},
            "withCalendar": [[.plain(.jsTemporalCalendarEnum)] => .jsTemporalPlainDateTime],
            "add": temporalAddSubtractSignature(forType: .jsTemporalPlainDateTime, needsOverflow: true),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalPlainDateTime, needsOverflow: true),
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalPlainDateTimeLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalPlainDateTimeLikeParameters),
            "round": [[.plain(jsTemporalRoundTo)] => .jsTemporalPlainDateTime],
            "equals": temporalEqualsSignature(possibleParams: jsTemporalPlainDateTimeLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
            "toZonedDateTime": temporalTimeZoneLikeSignature { [.plain($0), .opt(OptionsBag.jsTemporalZonedInterpretationSettings.group.instanceType)] => .jsTemporalZonedDateTime },
            "toPlainDate": [[] => .jsTemporalPlainDate],
            "toPlainTime": [[] => .jsTemporalPlainTime],
        ]
    )

    static let jsTemporalPlainDateTimePrototype = createPrototypeObjectGroup(jsTemporalPlainDateTime)

    /// ObjectGroup modelling the JavaScript Temporal.PlainDateTime constructor
    static let jsTemporalPlainDateTimeConstructor = ObjectGroup(
        name: "TemporalPlainDateTimeConstructor",
        constructorPath: "Temporal.PlainDateTime",
        instanceType: .jsTemporalPlainDateTimeConstructor,
        properties: [
            "prototype" : jsTemporalPlainDateTimePrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalPlainDateTime, possibleParams: jsTemporalPlainDateTimeLikeParameters, settingsArg: jsTemporalOverflowSettings),
            "compare": temporalCompareSignature(possibleParams: jsTemporalPlainDateTimeLikeParameters),
        ]
    )


    static let jsTemporalZonedDateTime = ObjectGroup(
        name: "Temporal.ZonedDateTime",
        instanceType: .jsTemporalZonedDateTime,
        properties: mergeFields(jsTemporalPlainDate.properties, jsTemporalPlainTime.properties, [
            "timeZoneId": .string,
            "epochMilliseconds": .integer,
            "epochNanoseconds": .bigint,
            "offsetNanoseconds": .integer,
            "offset": .string,
        ]),
        overloads: [
            "with":  [[.plain(jsTemporalZonedDateTimeLikeObjectForWith.instanceType), .opt(jsTemporalZonedInterpretationSettings)] => .jsTemporalZonedDateTime],
            "withPlainTime": jsTemporalPlainTimeLikeParameters.map {[.opt($0)] => .jsTemporalZonedDateTime},
            "withCalendar": [[.plain(.jsTemporalCalendarEnum)] => .jsTemporalZonedDateTime],
            "withTimeZone": [[.string] => .jsTemporalZonedDateTime],
            "add": temporalAddSubtractSignature(forType: .jsTemporalZonedDateTime, needsOverflow: true),
            "subtract": temporalAddSubtractSignature(forType: .jsTemporalZonedDateTime, needsOverflow: true),
            "until": temporalUntilSinceSignature(possibleParams: jsTemporalZonedDateTimeLikeParameters),
            "since": temporalUntilSinceSignature(possibleParams: jsTemporalZonedDateTimeLikeParameters),
            "round": [[.plain(jsTemporalRoundTo)] => .jsTemporalZonedDateTime],
            "equals": temporalEqualsSignature(possibleParams: jsTemporalZonedDateTimeLikeParameters),
            "toString": [[.opt(jsTemporalToStringSettings)] => .string],
            "toJSON": [[] => .string],
            "toLocaleString": [[.opt(.string), .opt(jsTemporalToLocaleStringSettings)] => .string],
            "startOfDay": [[] => .jsTemporalZonedDateTime],
            "getTimeZoneTransition": [[.plain(jsTemporalDirectionParam)] => .jsTemporalZonedDateTime],
            "toInstant": [[] => .jsTemporalInstant],
            "toPlainDate": [[] => .jsTemporalPlainDate],
            "toPlainTime": [[] => .jsTemporalPlainTime],
            "toPlainDateTime": [[] => .jsTemporalPlainDateTime],
        ]
    )

    static let jsTemporalZonedDateTimePrototype = createPrototypeObjectGroup(jsTemporalZonedDateTime)

    /// ObjectGroup modelling the JavaScript Temporal.ZonedDateTime constructor
    static let jsTemporalZonedDateTimeConstructor = ObjectGroup(
        name: "TemporalZonedDateTimeConstructor",
        constructorPath: "Temporal.ZonedDateTime",
        instanceType: .jsTemporalZonedDateTimeConstructor,
        properties: [
            "prototype" : jsTemporalZonedDateTimePrototype.instanceType
        ],
        overloads: [
            "from": temporalFromSignature(forType: .jsTemporalZonedDateTime, possibleParams: jsTemporalZonedDateTimeLikeParameters, settingsArg: jsTemporalZonedInterpretationSettings),
            "compare": temporalCompareSignature(possibleParams: jsTemporalZonedDateTimeLikeParameters),
        ]
    )

    // Temporal helpers

    // Temporal-like objects
    // These are objects like {years: 1, days: 2} that have similar fields to a Temporal type
    // and can be used for constructing them.

    fileprivate static let jsTemporalDurationLikeObject = ObjectGroup(
        name: "TemporalDurationLikeObject",
        instanceType: nil,
        properties: [
            "years": .number | .undefined,
            "months": .number | .undefined,
            "weeks": .number | .undefined,
            "days": .number | .undefined,
            "hours": .number | .undefined,
            "minutes": .number | .undefined,
            "seconds": .number | .undefined,
            "milliseconds": .number | .undefined,
            "microseconds": .number | .undefined,
            "nanoseconds": .number | .undefined,
        ],
        methods: [:])

    private static let jsTemporalTimeLikeFields : [String: ILType] = [
            "hour": .number | .undefined,
            "minute": .number | .undefined,
            "second": .number | .undefined,
            "millisecond": .number | .undefined,
            "microsecond": .number | .undefined,
            "nanosecond": .number | .undefined,
    ]

    private static let jsTemporalCalendarField : [String: ILType] = [
            "calendar": .jsTemporalCalendarEnum | .undefined,
    ]

    private static let jsTemporalDateLikeFields : [String: ILType] = [
            "era": .string | .undefined,
            "eraYear": .number | .undefined,
            "month": .number | .undefined,
            "monthCode": .string | .undefined,
            "day": .number | .undefined,
    ]

    private static func mergeFields(_ fields: [String: ILType]...) -> [String: ILType] {
      fields.reduce([:]) {
        $0.merging($1) { _, _ in
          fatalError("Duplicate field in \(fields)")
        }
      }
    }

    fileprivate static let jsTemporalPlainTimeLikeObject = ObjectGroup(
        name: "TemporalPlainTimeLikeObject",
        instanceType: nil,
        properties: jsTemporalTimeLikeFields,
        methods: [:])

    fileprivate static let jsTemporalPlainDateLikeObject = ObjectGroup(
        name: "TemporalPlainDateLikeObject",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields, jsTemporalCalendarField),
        methods: [:])

    fileprivate static let jsTemporalPlainDateTimeLikeObject = ObjectGroup(
        name: "TemporalPlainDateTimeLikeObject",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields, jsTemporalTimeLikeFields, jsTemporalCalendarField),
        methods: [:])

    fileprivate static let jsTemporalZonedDateTimeLikeObject = ObjectGroup(
        name: "TemporalZonedDateTimeLikeObject",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields, jsTemporalTimeLikeFields,
                                ["timeZone": .string | .undefined, "offset": .string | .undefined],
                                jsTemporalCalendarField),
        methods: [:])

    // with() takes a reduced set of fields: it cannot have a calendar or timeZone,
    // and will error if you give it these fields.
    fileprivate static let jsTemporalPlainDateLikeObjectForWith = ObjectGroup(
        name: "TemporalPlainDateLikeObjectForWith",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields),
        methods: [:])

    fileprivate static let jsTemporalPlainDateTimeLikeObjectForWith = ObjectGroup(
        name: "TemporalPlainDateTimeLikeObjectForWith",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields, jsTemporalTimeLikeFields),
        methods: [:])

    fileprivate static let jsTemporalZonedDateTimeLikeObjectForWith = ObjectGroup(
        name: "TemporalZonedDateTimeLikeObjectForWith",
        instanceType: nil,
        properties: mergeFields(jsTemporalDateLikeFields, jsTemporalTimeLikeFields, ["offset": .string | .undefined]),
        methods: [:])

    // Temporal-object-like parameters (accepted by ToTemporalFoo)
    // ToTemporalFoo, and APIs based on it (from, compare, until, since, equals, occasionally withFoo/toFoo) accept
    // a Temporal-like object, a Temporal object that is a superset of the type, or a string representation.
    // TODO(manishearth, 439921647) Most of the stringy types here are with a specific format, we should consider generating them
    private static let jsTemporalDurationLikeParameters: [ILType] = [jsTemporalDurationLikeObject.instanceType, .jsTemporalDuration, .string]
    private static let jsTemporalInstantLikeParameters: [ILType] = [.jsTemporalInstant, .jsTemporalZonedDateTime, .string]
    private static let jsTemporalPlainTimeLikeParameters: [ILType] = [jsTemporalPlainTimeLikeObject.instanceType, .jsTemporalPlainTime, .jsTemporalPlainDateTime, .jsTemporalZonedDateTime, .string]
    private static let jsTemporalPlainYearMonthLikeParameters: [ILType] = [jsTemporalPlainDateLikeObject.instanceType, .jsTemporalPlainYearMonth, .string]
    private static let jsTemporalPlainMonthDayLikeParameters: [ILType] = [jsTemporalPlainDateLikeObject.instanceType, .jsTemporalPlainMonthDay, .string]
    private static let jsTemporalPlainDateLikeParameters: [ILType] = [jsTemporalPlainDateLikeObject.instanceType, .jsTemporalPlainDate, .jsTemporalPlainDateTime, .jsTemporalZonedDateTime, .string]
    private static let jsTemporalPlainDateTimeLikeParameters: [ILType] = [jsTemporalPlainDateTimeLikeObject.instanceType, .jsTemporalPlainDate, .jsTemporalPlainDateTime, .jsTemporalZonedDateTime, .string]
    private static let jsTemporalZonedDateTimeLikeParameters: [ILType] = [jsTemporalZonedDateTimeLikeObject.instanceType, .string]

    // Stringy objects
    // TODO(manishearth, 439921647) support stringy objects
    fileprivate static let jsTemporalTimeZoneLike = ILType.namedString(ofName: "TemporalTimeZoneString")

    // Options objects
    fileprivate static let jsTemporalDifferenceSettings = OptionsBag.jsTemporalDifferenceSettingOrRoundTo.group.instanceType
    // roundTo accepts a subset of fields compared to differenceSettings; we merge the two bag types but retain separate
    // variables for clarity in the signatures above.
    fileprivate static let jsTemporalRoundTo = OptionsBag.jsTemporalDifferenceSettingOrRoundTo.group.instanceType
    fileprivate static let jsTemporalToStringSettings = OptionsBag.jsTemporalToStringSettings.group.instanceType
    fileprivate static let jsTemporalOverflowSettings = OptionsBag.jsTemporalOverflowSettings.group.instanceType
    fileprivate static let jsTemporalZonedInterpretationSettings = OptionsBag.jsTemporalZonedInterpretationSettings.group.instanceType
    fileprivate static let jsTemporalDirectionParam = ILType.enumeration(ofName: "directionParam", withValues: ["previous", "next"])
    fileprivate static let jsTemporalDurationRoundToSettings = OptionsBag.jsTemporalDurationRoundToSettings.group.instanceType
    fileprivate static let jsTemporalDurationTotalOfSettings = OptionsBag.jsTemporalDurationTotalOfSettings.group.instanceType
    fileprivate static let jsTemporalDurationCompareSettings = OptionsBag.jsTemporalDurationCompareSettings.group.instanceType
    // This is huge and comes from Intl, not Temporal
    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat/DateTimeFormat#parameters
    fileprivate static let jsTemporalToLocaleStringSettings = ILType.jsAnything
    fileprivate static let jsTemporalZonedOptions = ILType.jsAnything
}

extension OptionsBag {
    // Individual enums
    fileprivate static let jsTemporalUnitEnum = ILType.enumeration(ofName: "temporalUnit", withValues: ["auto", "year", "month", "week", "day", "hour", "minute", "second", "millisecond", "microsecond", "nanosecond", "auto", "years", "months", "weeks", "days", "hours", "minutes", "seconds", "milliseconds", "microseconds", "nanoseconds"])
    fileprivate static let jsTemporalRoundingModeEnum = ILType.enumeration(ofName: "temporalRoundingMode", withValues: ["ceil", "floor", "expand", "trunc", "halfCeil", "halfFloor", "halfExpand", "halfTrunc", "halfEven"])
    fileprivate static let jsTemporalShowCalendarEnum = ILType.enumeration(ofName: "temporalShowCalendar", withValues: ["auto", "always", "never", "critical"])
    fileprivate static let jsTemporalShowOffsetEnum = ILType.enumeration(ofName: "temporalShowOffset", withValues: ["auto", "never"])
    fileprivate static let jsTemporalShowTimeZoneEnum = ILType.enumeration(ofName: "temporalShowOfTimeZone", withValues: ["auto", "never", "critical"])
    fileprivate static let jsTemporalOverflowEnum = ILType.enumeration(ofName: "temporalOverflow", withValues: ["constrain", "reject"])
    fileprivate static let jsTemporalDisambiguationEnum = ILType.enumeration(ofName: "temporalDisambiguation", withValues: ["compatible", "earlier", "later", "reject"])
    fileprivate static let jsTemporalOffsetEnum = ILType.enumeration(ofName: "temporalOffset", withValues: ["prefer", "use", "ignore", "reject"])

    static let jsTemporalRelativeTo = ILType.jsTemporalZonedDateTime | ILType.jsTemporalPlainDateTime | ILType.jsTemporalPlainDate | .string

    // differenceSettings and roundTo are mostly the same, with differenceSettings accepting an additional largestUnit
    // note that the Duration roundTo option is different
    static let jsTemporalDifferenceSettingOrRoundTo = OptionsBag(
        name: "TemporalDifferenceSettingsObject",
        properties: [
            "smallestUnit": jsTemporalUnitEnum,
            "largestUnit": jsTemporalUnitEnum,
            "roundingMode": jsTemporalRoundingModeEnum,
            "roundingIncrement": .integer,
        ])

    // Technically some of these parameters are only read by ZonedDateTime; but they're
    // otherwise largely shared
    static let jsTemporalToStringSettings = OptionsBag(
        name: "TemporalToStringSettingsObject",
        properties: [
            "calendarName": jsTemporalShowCalendarEnum,
            "fractionalSecondDigits": .number,
            "offset": jsTemporalShowOffsetEnum,
            "timeZoneName": jsTemporalShowTimeZoneEnum,
            "roundingMode": jsTemporalRoundingModeEnum,
            "smallestUnit": jsTemporalUnitEnum,
        ])

    static let jsTemporalOverflowSettings = OptionsBag(
        name: "jsTemporalOverflowSettingsObject",
        properties: [
            "overflow": jsTemporalOverflowEnum,
        ])

    static let jsTemporalZonedInterpretationSettings = OptionsBag(
        name: "TemporalZonedInterpretationSettingsObject",
        properties: [
            "overflow": jsTemporalOverflowEnum,
            "disambiguation": jsTemporalDisambiguationEnum,
            "offset": jsTemporalOffsetEnum,
        ])

    static let jsTemporalDurationRoundToSettings =  OptionsBag(
        name: "TemporalDurationRoundToSettingsObject",
        properties: [
            "largestUnit": OptionsBag.jsTemporalUnitEnum,
            "roundingMode": OptionsBag.jsTemporalRoundingModeEnum,
            "roundingIncrement": .integer,
            "relativeTo": jsTemporalRelativeTo,
            "smallestUnit": OptionsBag.jsTemporalUnitEnum,
        ]
    )
    static let jsTemporalDurationTotalOfSettings =  OptionsBag(
        name: "TemporalDurationTotalOfSettingsObject",
        properties: [
            "relativeTo": jsTemporalRelativeTo,
            "unit": OptionsBag.jsTemporalUnitEnum,
        ]
    )
    static let jsTemporalDurationCompareSettings =  OptionsBag(
        name: "TemporalDurationCompareSettingsObject",
        properties: [
            "relativeTo": jsTemporalRelativeTo,
        ]
    )

    static let jsTemporalPlainDateToZDTSettings = OptionsBag(
        name: "TemporalPlainDateToZDTSettings",
        properties: [
            "timeZone": ObjectGroup.jsTemporalTimeZoneLike,
            "plainTime": .jsTemporalPlainTime,
        ]
    )
}

// Intl
extension ILType {
    // Intl types
    static let jsIntlObject = ILType.object(ofGroup: "Intl", withProperties: ["DateTimeFormat", "Collator", "ListFormat", "NumberFormat", "PluralRules", "RelativeTimeFormat", "Segmenter"], withMethods: ["getCanonicalLocales", "supportedValuesOf"])

    static let jsIntlCollator = ILType.object(ofGroup: "Intl.Collator", withProperties: [], withMethods: ["compare", "resolvedOptions"])
    static let jsIntlCollatorConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlCollatorSettings.group.instanceType)] => .jsIntlCollator) + .object(ofGroup: "IntlCollatorConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlDateTimeFormat = ILType.object(ofGroup: "Intl.DateTimeFormat", withProperties: [], withMethods: ["format", "formatRange", "formatRangeToParts", "formatToParts", "resolvedOptions"])
    static let jsIntlDateTimeFormatConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlDateTimeFormatSettings.group.instanceType)] => .jsIntlDateTimeFormat) + .object(ofGroup: "IntlDateTimeFormatConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlListFormat = ILType.object(ofGroup: "Intl.ListFormat", withProperties: [], withMethods: ["format", "formatToParts", "resolvedOptions"])
    static let jsIntlListFormatConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlListFormatSettings.group.instanceType)] => .jsIntlListFormat) + .object(ofGroup: "IntlListFormatConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlNumberFormat = ILType.object(ofGroup: "Intl.NumberFormat", withProperties: [], withMethods: ["format", "formatRange", "formatRangeToParts", "formatToParts", "resolvedOptions"])
    static let jsIntlNumberFormatConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlNumberFormatSettings.group.instanceType)] => .jsIntlNumberFormat) + .object(ofGroup: "IntlNumberFormatConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlPluralRules = ILType.object(ofGroup: "Intl.PluralRules", withProperties: [], withMethods: ["select", "selectRange", "resolvedOptions"])
    static let jsIntlPluralRulesConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlPluralRulesSettings.group.instanceType)] => .jsIntlPluralRules) + .object(ofGroup: "IntlPluralRulesConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlRelativeTimeFormat = ILType.object(ofGroup: "Intl.RelativeTimeFormat", withProperties: [], withMethods: ["format", "formatToParts", "resolvedOptions"])
    static let jsIntlRelativeTimeFormatConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlRelativeTimeFormatSettings.group.instanceType)] => .jsIntlRelativeTimeFormat) + .object(ofGroup: "IntlRelativeTimeFormatConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlSegmenter = ILType.object(ofGroup: "Intl.Segmenter", withProperties: [], withMethods: ["segment", "resolvedOptions"])
    static let jsIntlSegmenterConstructor = ILType.functionAndConstructor([.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlSegmenterSettings.group.instanceType)] => .jsIntlSegmenter) + .object(ofGroup: "IntlSegmenterConstructor", withProperties: ["prototype"], withMethods: ["supportedLocalesOf"])

    static let jsIntlSegmenterSegments = ILType.object(ofGroup: "IntlSegmenterSegments", withProperties: [], withMethods: ["containing"])

    static let jsIntlLocaleLike = ILType.namedString(ofName: "IntlLocaleString")
    static let jsIntlUnit = ILType.namedString(ofName: "IntlUnitString")
}

extension ObjectGroup {
    static let jsIntlSupportedValuesEnum = ILType.enumeration(ofName: "IntlSupportedValues", withValues: ["calendar", "collation", "currency", "numberingSystem", "timeZone"])

    static let jsIntlObject = ObjectGroup(
        name: "Intl",
        instanceType: .jsIntlObject,
        properties: [
            "Collator"  : .jsIntlCollatorConstructor,
            "DateTimeFormat"  : .jsIntlDateTimeFormatConstructor,
            "ListFormat"  : .jsIntlListFormatConstructor,
            "NumberFormat"  : .jsIntlNumberFormatConstructor,
            "PluralRules"  : .jsIntlPluralRulesConstructor,
            "RelativeTimeFormat"  : .jsIntlRelativeTimeFormatConstructor,
            "Segmenter"  : .jsIntlSegmenterConstructor,
        ],
        methods: [
            "getCanonicalLocales": [] => .jsArray,
            "supportedValuesOf": [.plain(jsIntlSupportedValuesEnum)] => .jsArray,
        ]
    )

    static let jsIntlCollator = ObjectGroup(
        name: "Intl.Collator",
        instanceType: .jsIntlCollator,
        properties: [:],
        methods: [
            "compare": [.string, .string] => .integer,
            "resolvedOptions": [] => .object(),
        ]
    )

    static let jsIntlCollatorPrototype = createPrototypeObjectGroup(jsIntlCollator)

    static let jsIntlCollatorConstructor = ObjectGroup(
        name: "IntlCollatorConstructor",
        constructorPath: "Intl.Collator",
        instanceType: .jsIntlCollatorConstructor,
        properties: [
            "prototype" : jsIntlCollatorPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    fileprivate static func dateTimeFormatSignature(_ returnType: ILType) -> [Signature] {
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat/format#date
        // No ZonedDateTime as stated in the docs.
        [ILType.jsDate, .jsTemporalPlainDate, .jsTemporalPlainTime, .jsTemporalPlainMonthDay, .jsTemporalPlainYearMonth, .jsTemporalPlainDateTime].map {
            [.opt($0)] => returnType
        }
    }
    fileprivate static func dateTimeFormatRangeSignature(_ returnType: ILType) -> [Signature] {
        // Docs list all Temporal types except ZDT, but we don't wish to explode the signatures so we just pick
        // the two main relevant ones.
        [ILType.jsDate, .jsTemporalPlainDateTime].flatMap { firstParam in
            [ILType.jsDate, .jsTemporalPlainDateTime].map {
                [.opt(firstParam), .opt($0)] => returnType
            }
        }
    }
    static let jsIntlDateTimeFormat = ObjectGroup(
        name: "Intl.DateTimeFormat",
        instanceType: .jsIntlDateTimeFormat,
        properties: [:],
        overloads: [
            "format": dateTimeFormatSignature(.string),
            "formatRange": dateTimeFormatRangeSignature(.string),
            "formatRangeToParts": dateTimeFormatRangeSignature(.jsArray),
            "formatToParts": dateTimeFormatSignature(.jsArray),
            "resolvedOptions": [[] => .object()],
        ]
    )

    static let jsIntlDateTimeFormatPrototype = createPrototypeObjectGroup(jsIntlDateTimeFormat)

    static let jsIntlDateTimeFormatConstructor = ObjectGroup(
        name: "IntlDateTimeFormatConstructor",
        constructorPath: "Intl.DateTimeFormat",
        instanceType: .jsIntlDateTimeFormatConstructor,
        properties: [
            "prototype" : jsIntlDateTimeFormatPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    static let jsIntlListFormat = ObjectGroup(
        name: "Intl.ListFormat",
        instanceType: .jsIntlListFormat,
        properties: [:],
        methods: [
            "format": [.plain(.jsArray)] => .string,
            "formatToParts": [.plain(.jsArray)] => .jsArray,
            "resolvedOptions": [] => .object(),
        ]
    )

    static let jsIntlListFormatPrototype = createPrototypeObjectGroup(jsIntlListFormat)

    static let jsIntlListFormatConstructor = ObjectGroup(
        name: "IntlListFormatConstructor",
        constructorPath: "Intl.ListFormat",
        instanceType: .jsIntlListFormatConstructor,
        properties: [
            "prototype" : jsIntlListFormatPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    fileprivate static func numberFormatSignature(_ returnType: ILType) -> [Signature] {
        // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/NumberFormat/format
        [ILType.number, .bigint, .string].map {
            [.opt($0)] => returnType
        }
    }
    fileprivate static func numberFormatRangeSignature(_ returnType: ILType) -> [Signature] {
        [ILType.number, .bigint, .string].flatMap { firstParam in
            [ILType.number, .bigint, .string].map {
                [.opt(firstParam), .opt($0)] => returnType
            }
        }
    }

    static let jsIntlNumberFormat = ObjectGroup(
        name: "Intl.NumberFormat",
        instanceType: .jsIntlNumberFormat,
        properties: [:],
        overloads: [
            "format": numberFormatSignature(.string),
            "formatRange": numberFormatRangeSignature(.string),
            "formatRangeToParts": numberFormatRangeSignature(.jsArray),
            "formatToParts": numberFormatSignature(.jsArray),
            "resolvedOptions": [[] => .object()],
        ]
    )

    static let jsIntlNumberFormatPrototype = createPrototypeObjectGroup(jsIntlNumberFormat)

    static let jsIntlNumberFormatConstructor = ObjectGroup(
        name: "IntlNumberFormatConstructor",
        constructorPath: "Intl.NumberFormat",
        instanceType: .jsIntlNumberFormatConstructor,
        properties: [
            "prototype" : jsIntlNumberFormatPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    static let jsIntlPluralRules = ObjectGroup(
        name: "Intl.PluralRules",
        instanceType: .jsIntlPluralRules,
        properties: [:],
        methods: [
            "select": [.number] => .string,
            "selectRange": [.number, .number] => .string,
            "resolvedOptions": [] => .object(),
        ]
    )

    static let jsIntlPluralRulesPrototype = createPrototypeObjectGroup(jsIntlPluralRules)

    static let jsIntlPluralRulesConstructor = ObjectGroup(
        name: "IntlPluralRulesConstructor",
        constructorPath: "Intl.PluralRules",
        instanceType: .jsIntlPluralRulesConstructor,
        properties: [
            "prototype" : jsIntlPluralRulesPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    static let jsIntlRelativeTimeFormatUnitEnum = ILType.enumeration(ofName: "IntlRelativeTimeFormatUnit", withValues: ["year", "quarter", "month", "week", "day", "hour", "minute", "second"])

    static let jsIntlRelativeTimeFormat = ObjectGroup(
        name: "Intl.RelativeTimeFormat",
        instanceType: .jsIntlRelativeTimeFormat,
        properties: [:],
        methods: [
            "format": [.number, .plain(jsIntlRelativeTimeFormatUnitEnum)] => .string,
            "formatToParts": [.number, .plain(jsIntlRelativeTimeFormatUnitEnum)] => .jsArray,
            "resolvedOptions": [] => .object(),
        ]
    )

    static let jsIntlRelativeTimeFormatPrototype = createPrototypeObjectGroup(jsIntlRelativeTimeFormat)

    static let jsIntlRelativeTimeFormatConstructor = ObjectGroup(
        name: "IntlRelativeTimeFormatConstructor",
        constructorPath: "Intl.RelativeTimeFormat",
        instanceType: .jsIntlRelativeTimeFormatConstructor,
        properties: [
            "prototype" : jsIntlRelativeTimeFormatPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )

    static let jsIntlSegmenter = ObjectGroup(
        name: "Intl.Segmenter",
        instanceType: .jsIntlSegmenter,
        properties: [:],
        methods: [
            "segment": [.string] => .jsIntlSegmenterSegments,
            "resolvedOptions": [] => .object(),
        ]
    )

    static let jsIntlSegmenterPrototype = createPrototypeObjectGroup(jsIntlSegmenter)

    static let jsIntlSegmenterConstructor = ObjectGroup(
        name: "IntlSegmenterConstructor",
        constructorPath: "Intl.Segmenter",
        instanceType: .jsIntlSegmenterConstructor,
        properties: [
            "prototype" : jsIntlSegmenterPrototype.instanceType
        ],
        methods: [
            // TODO(manishearth) this also accepts arrays of locale-likes
            "supportedLocalesOf": [.opt(.jsIntlLocaleLike), .opt(OptionsBag.jsIntlLocaleMatcherSettings.group.instanceType)] => .jsArray,
        ]
    )
    static let jsIntlSegmenterSegments = ObjectGroup(
        name: "IntlSegmenterSegments",
        instanceType: .jsIntlSegmenterSegments,
        properties: [:],
        methods: [
            "containing": [.number] => .object(),
        ]
    )
}

extension OptionsBag {
    fileprivate static let jsIntlLocaleMatcherEnum = ILType.enumeration(ofName: "IntlLocaleMatcher", withValues: ["lookup", "best fit"])
    fileprivate static let jsIntlNumberingSystemEnum = ILType.enumeration(ofName: "IntlNumberingSystem", withValues: Locale.NumberingSystem.availableNumberingSystems.map { $0.identifier })
    fileprivate static let jsIntlHourCycleEnum = ILType.enumeration(ofName: "IntlHourCycle", withValues: ["h11", "h12", "h23", "h24"])
    fileprivate static let jsIntlLongShortNarrowEnum = ILType.enumeration(ofName: "IntlLongShortNarrow", withValues: ["long", "short", "narrow"])
    fileprivate static let jsIntlLongShortEnum = ILType.enumeration(ofName: "IntlLongShort", withValues: ["long", "short"])
    fileprivate static let jsIntlAutoAlwaysEnum = ILType.enumeration(ofName: "IntlAutoAlways", withValues: ["auto", "always"])
    fileprivate static let jsIntlNumeric2DigitEnum = ILType.enumeration(ofName: "IntlNumeric2Digit", withValues: ["numeric", "2-digit"])
    fileprivate static let jsIntlMonthEnum = ILType.enumeration(ofName: "IntlMonth", withValues: ["numeric", "2-digit", "long", "short", "narrow"])
    fileprivate static let jsIntlTimeZoneNameEnum = ILType.enumeration(ofName: "IntlTimeZoneName", withValues: ["long", "short", "shortOffset", "longOffset", "shortGeneric", "longGeneric"])
    fileprivate static let jsIntlFormatMatcherEnum = ILType.enumeration(ofName: "IntlFormatMatcher", withValues: ["basic", "best fit"])
    fileprivate static let jsIntlFullLongMediumShort = ILType.enumeration(ofName: "IntlFullLongMediumShort", withValues: ["full", "long", "medium", "short"])
    fileprivate static let jsIntlCollatorUsageEnum = ILType.enumeration(ofName: "IntlCollatorUsage", withValues: ["sort", "search"])
    fileprivate static let jsIntlCollationEnum = ILType.enumeration(ofName: "IntlCollation", withValues: ["emoji", "pinyin", "stroke"])
    fileprivate static let jsIntlCaseFirstEnum = ILType.enumeration(ofName: "IntlCaseFirst", withValues: ["upper", "lower", "false"])
    fileprivate static let jsIntlCollatorSensitivityEnum = ILType.enumeration(ofName: "IntlCollatorSensitivity", withValues: ["base", "accent", "case", "variant"])
    fileprivate static let jsIntlListFormatTypeEnum = ILType.enumeration(ofName: "IntlListFormatTypeEnum", withValues: ["conjunction", "disjunction", "unit"])
    fileprivate static let jsIntlNumberFormatStyleEnum = ILType.enumeration(ofName: "IntlNumberFormatStyleEnum", withValues: ["decimal", "currency", "percent", "unit"])
    fileprivate static let jsIntlCurrencySystemEnum = ILType.enumeration(ofName: "IntlCurrency", withValues: Locale.Currency.isoCurrencies.map { $0.identifier })
    fileprivate static let jsIntlCurrencyDisplayEnum = ILType.enumeration(ofName: "IntlCurrencyDisplayEnum", withValues: ["code", "symbol", "narrowSymbol", "name"])
    fileprivate static let jsIntlCurrencySignEnum = ILType.enumeration(ofName: "IntlCurrencySignEnum", withValues: ["standard", "accounting"])
    fileprivate static let jsIntlRoundingPriorityEnum = ILType.enumeration(ofName: "IntlRoundingPriority", withValues: ["auto", "morePrecision", "lessPrecision"])
    fileprivate static let jsIntlRoundingModeEnum = ILType.enumeration(ofName: "IntlRoundingMode", withValues: ["ceil", "floor", "expand", "trunc", "halfCeil", "halfFloor", "halfExpand", "halfTrunc", "halfEven"])
    fileprivate static let jsIntlTrailingZeroDisplayEnum = ILType.enumeration(ofName: "IntlTrailingZeroDisplay", withValues: ["auto", "stripIfInteger"])
    fileprivate static let jsIntlNumberFormatNotationEnum = ILType.enumeration(ofName: "IntlNumberFormatNotation", withValues: ["standard", "scientific", "engineering", "compact"])
    fileprivate static let jsIntlNumberFormatGroupingEnum = ILType.enumeration(ofName: "IntlNumberFormatGrouping", withValues: ["always", "auto", "min2", "true", "false"])
    fileprivate static let jsIntlSignDisplayEnum = ILType.enumeration(ofName: "IntlSignDisplay", withValues: ["auto", "always", "exceptZero", "negative", "never"])
    fileprivate static let jsIntlPluralRulesTypeEnum = ILType.enumeration(ofName: "IntlPluralRulesTypeEnum", withValues: ["cardinal", "ordinal"])
    fileprivate static let jsIntlSegmenterGranularityEnum = ILType.enumeration(ofName: "IntlSegmenterGranularityEnum", withValues: ["grapheme", "word", "sentence"])

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat/DateTimeFormat#parameters
    static let jsIntlDateTimeFormatSettings = OptionsBag(
        name: "IntlLocaleSettings",
        properties: [
            // Locale options
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "calendar": .jsTemporalCalendarEnum,
            "numberingSystem": jsIntlNumberingSystemEnum,
            "hour12": .boolean,
            "hourCycle": jsIntlHourCycleEnum,
            "timeZone": ObjectGroup.jsTemporalTimeZoneLike,
            // datetime options
            "weekday": jsIntlLongShortNarrowEnum,
            "era": jsIntlLongShortNarrowEnum,
            "year": jsIntlNumeric2DigitEnum,
            "month": jsIntlMonthEnum,
            "day": jsIntlNumeric2DigitEnum,
            "dayPeriod": jsIntlLongShortNarrowEnum,
            "hour": jsIntlNumeric2DigitEnum,
            "minute": jsIntlNumeric2DigitEnum,
            "second": jsIntlNumeric2DigitEnum,
            "fractionalSecondDigits": .integer, // Technically only 1-3
            "timeZoneName": jsIntlTimeZoneNameEnum,
            "formatMatcher": jsIntlFormatMatcherEnum,
            // style options
            "dateStyle": jsIntlFullLongMediumShort,
            "timeStyle": jsIntlFullLongMediumShort,
        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/Collator/Collator#options
    static let jsIntlCollatorSettings = OptionsBag(
        name: "IntlCollatorSettings",
        properties: [
            "usage": jsIntlCollatorUsageEnum,
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "collation": jsIntlCollationEnum,
            "numeric": .boolean,
            "caseFirst": jsIntlCaseFirstEnum,
            "sensitivity": jsIntlCollatorSensitivityEnum,
            "ignorePunctuation": .boolean,
        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/ListFormat/ListFormat#options
    static let jsIntlListFormatSettings = OptionsBag(
        name: "IntlListFormatSettings",
        properties: [
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "type": jsIntlListFormatTypeEnum,
            "style": jsIntlLongShortNarrowEnum,
        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/NumberFormat/NumberFormat#options
    static let jsIntlNumberFormatSettings = OptionsBag(
        name: "IntlNumberFormatSettings",
        properties: [
            // locale options
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "numberingSystem": jsIntlNumberingSystemEnum,
            // style options
            "style": jsIntlNumberFormatStyleEnum,
            "currency": jsIntlCurrencySystemEnum,
            "currencyDisplay": jsIntlCurrencyDisplayEnum,
            "currencySign": jsIntlCurrencySignEnum,
            "unit": .jsIntlUnit,
            "unitDisplay": jsIntlLongShortNarrowEnum,
            // digit options
            "minimumIntegerDigits": .integer,
            "minimumFractionDigits": .integer,
            "maximumFractionDigits": .integer,
            "minimumSignificantDigits": .integer,
            "maximumSignificantDigits": .integer,
            "roundingPriority": jsIntlRoundingPriorityEnum,
            "roundingIncrement": .integer,
            "roundingMode": jsIntlRoundingModeEnum,
            "trailingZeroDisplay": jsIntlTrailingZeroDisplayEnum,
            // other options
            "notation": jsIntlNumberFormatNotationEnum,
            "compactDisplay": jsIntlLongShortEnum,
            "useGrouping": jsIntlNumberFormatGroupingEnum,
            "signDisplay": jsIntlSignDisplayEnum,
        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/PluralRules/PluralRules#options
    static let jsIntlPluralRulesSettings = OptionsBag(
        name: "IntlPluralRulesSettings",
        properties: [
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "type": jsIntlPluralRulesTypeEnum,

            // NumberFormat digit options
            "minimumIntegerDigits": .integer,
            "minimumFractionDigits": .integer,
            "maximumFractionDigits": .integer,
            "minimumSignificantDigits": .integer,
            "maximumSignificantDigits": .integer,
            "roundingPriority": jsIntlRoundingPriorityEnum,
            "roundingIncrement": .integer,
            "roundingMode": jsIntlRoundingModeEnum,

        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/RelativeTimeFormat/RelativeTimeFormat#options
    static let jsIntlRelativeTimeFormatSettings = OptionsBag(
        name: "IntlRelativeTimeFormatSettings",
        properties: [
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "numberingSystem": jsIntlNumberingSystemEnum,
            "style": jsIntlLongShortNarrowEnum,
            "numeric": jsIntlAutoAlwaysEnum,
        ]
    )

    // https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/Segmenter/Segmenter#options
    static let jsIntlSegmenterSettings = OptionsBag(
        name: "IntlSegmenterSettings",
        properties: [
            "localeMatcher": jsIntlLocaleMatcherEnum,
            "granularity": jsIntlSegmenterGranularityEnum,
        ]
    )

    static let jsIntlLocaleMatcherSettings = OptionsBag(
        name: "IntlLocaleMatcherSettings",
        properties: [
            "localeMatcher": jsIntlLocaleMatcherEnum,
        ]
    )
}

// Base64
extension OptionsBag {
    fileprivate static let base64Alphabet =
        ILType.enumeration(ofName: "base64Alphabet", withValues: ["base64", "base64url"])
    fileprivate static let base64LastChunkHandling =
        ILType.enumeration(ofName: "base64LastChunkHandling", withValues: ["loose", "strict", "stop-before-partial"])

    static let toBase64Settings = OptionsBag(
        name: "ToBase64Settings",
        properties: [
            "alphabet": base64Alphabet,
            "omitPadding": .boolean,
        ])

    static let fromBase64Settings = OptionsBag(
        name: "FromBase64Settings",
        properties: [
            "alphabet": base64Alphabet,
            "lastChunkHandling": base64LastChunkHandling
        ]
    )
}
