// Copyright 2019-2024 Google LLC
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

fileprivate let StressXSGC = CodeGenerator("StressXSGC", inputs: .required(.function())) { b, f in
    let arguments = b.randomArguments(forCalling: f)

    let index = b.loadInt(1)
    let end = b.loadInt(128)
    let gc = b.createNamedVariable(forBuiltin: "gc")
    b.callFunction(gc, withArgs: [index])
    b.buildWhileLoop({b.compare(index, with: end, using: .lessThan)}) {
        b.callFunction(f, withArgs: arguments)
        b.unary(.PostInc, index)
        let result = b.callFunction(gc, withArgs: [index])
        b.buildIf(result) {
            b.loopBreak()
        }
    }
}

fileprivate let StressXSMemoryFail = CodeGenerator("StressXSMemoryFail", inputs: .required(.function())) { b, f in
    let arguments = b.randomArguments(forCalling: f)

    let index = b.loadInt(1)
    let max = b.loadInt(1000000)
    let memoryFail = b.createNamedVariable(forBuiltin: "memoryFail")
    b.callFunction(memoryFail, withArgs: [max])    // count how many allocations this function makes
    b.callFunction(f, withArgs: arguments)
    var end = b.callFunction(memoryFail, withArgs: [index])
    end = b.binary(max, end, with: .Sub)
    b.buildWhileLoop({b.compare(index, with: end, using: .lessThan)}) {
        b.callFunction(f, withArgs: arguments)
        b.unary(.PostInc, index)
        b.callFunction(memoryFail, withArgs: [index])
    }
}

fileprivate let HardenGenerator = CodeGenerator("HardenGenerator", inputs: .required(.object())) { b, obj in
    let harden = b.createNamedVariable(forBuiltin: "harden")

    if probability(0.05) {
        let lockdown = b.createNamedVariable(forBuiltin: "lockdown")
        b.callFunction(lockdown)
    }
    b.callFunction(harden, withArgs: [obj])
}

fileprivate let ModuleSourceGenerator = RecursiveCodeGenerator("ModuleSourceGenerator") { b in
    let moduleSourceConstructor = b.createNamedVariable(forBuiltin: "ModuleSource")

    let code = b.buildCodeString() {
        b.buildRecursive()
    }

    b.construct(moduleSourceConstructor, withArgs: [code])
}

fileprivate let CompartmentGenerator = RecursiveCodeGenerator("CompartmentGenerator") { b in
    let compartmentConstructor = b.createNamedVariable(forBuiltin: "Compartment")

    var endowments = [String: Variable]()        // may be used as endowments argument or globalLexicals
    var moduleMap = [String: Variable]()
    var options = [String: Variable]()

    for _ in 0..<Int.random(in: 1...4) {
        let propertyName = b.randomCustomPropertyName()
        endowments[propertyName] = b.randomVariable()
    }
    var endowmentsObject = b.createObject(with: endowments)

	// to do: populate moduleMap
    let moduleMapObject = b.createObject(with: moduleMap)
    let resolveHook = b.buildPlainFunction(with: .parameters(n: 2)) { _ in
        b.buildRecursive(block: 1, of: 4)
        b.doReturn(b.randomVariable())
    }
    let moduleMapHook = b.buildPlainFunction(with: .parameters(n: 1)) { _ in
        b.buildRecursive(block: 2, of: 4)
        b.doReturn(b.randomVariable())
    }
    let loadNowHook = b.dup(moduleMapHook)
    let loadHook = b.buildAsyncFunction(with: .parameters(n: 1)) { _ in
        b.buildRecursive(block: 3, of: 4)
        b.doReturn(b.randomVariable())
    }
    options["resolveHook"] = resolveHook
    options["moduleMapHook"] = moduleMapHook
    options["loadNowHook"] = loadNowHook
    options["loadHook"] = loadHook

    if probability(0.5) {
        options["globalLexicals"] = endowmentsObject
        endowmentsObject = b.createObject(with: [:]) 
    }
    let optionsObject = b.createObject(with: options)

    let compartment = b.construct(compartmentConstructor, withArgs: [endowmentsObject, moduleMapObject, optionsObject])

    if probability(0.5) {
        let code = b.buildCodeString() {
            b.buildRecursive(block: 4, of: 4)
        }
        b.callMethod("evaluate", on: compartment, withArgs: [code])
    }
}

fileprivate let UnicodeStringGenerator = CodeGenerator("UnicodeStringGenerator") { b in
    var s = ""
    for _ in 0..<Int.random(in: 1...100) {
        let codePoint = UInt32.random(in: 0..<0x10FFFF)
        // ignore surrogate pair code points
        if !((0xD800 <= codePoint) && (codePoint < 0xE000)) {
            s += String(Unicode.Scalar(codePoint)!)
        }
    }
    b.loadString(s)
}

fileprivate let HexGenerator = CodeGenerator("HexGenerator") { b in
    let hexValues = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F"]

    let Uint8Array = b.createNamedVariable(forBuiltin: "Uint8Array")

    withEqualProbability({
            var s = ""
            for _ in 0..<Int.random(in: 1...10) {
                s += chooseUniform(from: hexValues)
                s += chooseUniform(from: hexValues)
            }
            let hex = b.loadString(s)

            if probability(0.5) {
                b.callMethod("fromHex", on: Uint8Array, withArgs: [hex])
            } else {
                let target = b.construct(Uint8Array, withArgs: [b.loadInt(Int64.random(in: 0...0x100))])
                b.callMethod("setFromHex", on: target, withArgs: [hex])
            }
        }, {
            var values = [Variable]()
            for _ in 0..<Int.random(in: 1...20) {
                values.append(b.loadInt(Int64.random(in: 0...0xFF)))
            }

            let bytes = b.callMethod("of", on: Uint8Array, withArgs: values)
            b.callMethod("toHex", on: bytes, withArgs: [])
        }
    )
}

fileprivate let Base64Generator = CodeGenerator("Base64Generator") { b in
    let base64Alphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "/"]
    let base64URLAlphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"]

    let Uint8Array = b.createNamedVariable(forBuiltin: "Uint8Array")

    withEqualProbability({
            var options = [String: Variable]()
            var alphabet = chooseUniform(from: [base64Alphabet, base64URLAlphabet])

            options["alphabet"] = b.loadString((alphabet == base64Alphabet) ? "base64" : "base64url")
            options["lastChunkHandling"] = b.loadString(
                chooseUniform(
                    from: ["loose", "strict", "stop-before-partial"]
                )
            )

            var s = ""
            for _ in 0..<Int.random(in: 1...32) * 4 {
                s += chooseUniform(from: alphabet)
            }

            // extend by 0, 1, or 2 bytes
            switch (Int.random(in: 0...3)) {
                case 1:
                    s += base64Alphabet[Int.random(in: 0...63)]
                    s += base64Alphabet[Int.random(in: 0...63) & 0x30]
                    s += "=="
                    break

                case 2:
                    s += base64Alphabet[Int.random(in: 0...63)]
                    s += base64Alphabet[Int.random(in: 0...63)]
                    s += base64Alphabet[Int.random(in: 0...63) & 0x3C]
                    s += "="
                    break

                default:
                    break
            }

            let base64 = b.loadString(s)

            let optionsObject = b.createObject(with: options)
            if probability(0.5) {
                b.callMethod("fromBase64", on: Uint8Array, withArgs: [base64, optionsObject])
            } else {
                let target = b.construct(Uint8Array, withArgs: [b.loadInt(Int64.random(in: 0...0x100))])
                b.callMethod("setFromBase64", on: target, withArgs: [base64, optionsObject])
            }
        }, {
            var values = [Variable]()
            for _ in 0..<Int.random(in: 1...64) {
                values.append(b.loadInt(Int64.random(in: 0...0xFF)))
            }

            let bytes = b.callMethod("of", on: Uint8Array, withArgs: values)
            b.callMethod("toBase64", on: bytes, withArgs: [])
        }
    )
}

fileprivate let CompartmentEvaluateGenerator = CodeGenerator("CompartmentEvaluateGenerator", inputs: .required(.object(ofGroup: "Compartment"))) { b, target in
    let code = b.buildCodeString() {
        b.buildRecursive()
    }
    b.callMethod("evaluate", on: target, withArgs: [code])
}

// this template taken from V8Profile.swift (with light modifications for XS)
fileprivate let RegExpFuzzer = ProgramTemplate("RegExpFuzzer") { b in
    // Taken from: https://source.chromium.org/chromium/chromium/src/+/refs/heads/main:v8/test/fuzzer/regexp-builtins.cc;l=212;drc=a61b95c63b0b75c1cfe872d9c8cdf927c226046e
    let twoByteSubjectString = "f\\uD83D\\uDCA9ba\\u2603"

    let replacementCandidates = [
      "'X'",
      "'$1$2$3'",
      "'$$$&$`$\\'$1'",
      "() => 'X'",
      "(arg0, arg1, arg2, arg3, arg4) => arg0 + arg1 + arg2 + arg3 + arg4",
      "() => 42"
    ]

    let lastIndices = [
      "undefined",  "-1",         "0",
      "1",          "2",          "3",
      "4",          "5",          "6",
      "7",          "8",          "9",
      "50",         "4294967296", "2147483647",
      "2147483648", "NaN",        "Not a Number"
    ]

    let f = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
        let (pattern, flags) = b.randomRegExpPatternAndFlags()
        let regExpVar = b.loadRegExp(pattern, flags)

        let lastIndex = chooseUniform(from: lastIndices)
        let lastIndexString = b.loadString(lastIndex)

        b.setProperty("lastIndex", of: regExpVar, to: lastIndexString)

        let subjectVar: Variable

        if probability(0.1) {
            subjectVar = b.loadString(twoByteSubjectString)
        } else {
            subjectVar = b.loadString(b.randomString())
        }

        let resultVar = b.loadNull()

        b.buildTryCatchFinally(tryBody: {
            let symbol = b.createNamedVariable(forBuiltin: "Symbol")
            withEqualProbability({
                let res = b.callMethod("exec", on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("match", of: symbol)
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("replace", of: symbol)
                let replacement = withEqualProbability({
                    b.loadString(b.randomString())
                }, {
                    b.loadString(chooseUniform(from: replacementCandidates))
                })
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar, replacement])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("search", of: symbol)
                let res = b.callComputedMethod(prop, on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            }, {
                let prop = b.getProperty("split", of: symbol)
                let randomSplitLimit = withEqualProbability({
                    "undefined"
                }, {
                    "'not a number'"
                }, {
                    String(b.randomInt())
                })
                let limit = b.loadString(randomSplitLimit)
                let res = b.callComputedMethod(symbol, on: regExpVar, withArgs: [subjectVar, limit])
                b.reassign(resultVar, to: res)
            }, {
                let res = b.callMethod("test", on: regExpVar, withArgs: [subjectVar])
                b.reassign(resultVar, to: res)
            })
        }, catchBody: { _ in
        })

        b.build(n: 7)

        b.doReturn(resultVar)
    }

    b.callFunction(f)

    b.build(n: 15)
}

public extension ILType {
    /// Type of a JavaScript Compartment object.
    static let jsCompartment = ILType.object(ofGroup: "Compartment", withProperties: ["globalThis"], withMethods: ["evaluate", "import", "importNow" /* , "module" */])

    static let jsCompartmentConstructor = ILType.constructor([.opt(.object()), .opt(.object()), .opt(.object())] => .jsCompartment) + .object(ofGroup: "CompartmentConstructor", withProperties: ["prototype"], withMethods: [])

    static let jsModuleSource = ILType.object(ofGroup: "ModuleSource", withProperties: ["bindings", "needsImport", "needsImportMeta"])

    static let jsModuleSourceConstructor = ILType.constructor([.opt(.string)] => .jsModuleSource) + .object(ofGroup: "ModuleSourceConstructor", withProperties: ["prototype"], withMethods: [])
}

/// Object group modelling JavaScript compartments.
let jsCompartments = ObjectGroup(
    name: "Compartment",
    instanceType: .jsCompartment,
    properties: [
        "globalThis"  : .object()
    ],
    methods: [  //@@ import/importNow can accept more than strings
        "import"    : [.string] => .jsPromise,
        "importNow" : [.string] => .anything,
        // "module"    : [.opt(.string)] => .object(), (currently unavailable)
        "evaluate"  : [.string] => .anything,
    ]
)

let jsCompartmentConstructor = ObjectGroup(
    name: "CompartmentConstructor",
    instanceType: .jsCompartmentConstructor,
    properties: [
        "prototype" : .object()
    ],
    methods: [:]
)

/// Object group modelling JavaScript ModuleSources.
let jsModuleSources = ObjectGroup(
    name: "ModuleSource",
    instanceType: .jsModuleSource,
    properties: [
        "bindings" : .object(), 
        "needsImport" : .object(), 
        "needsImportMeta" : .object(),
    ],
    methods: [:]
)

let jsModuleSourceConstructor = ObjectGroup(
    name: "ModuleSourceConstructor",
    instanceType: .jsModuleSourceConstructor,
    properties: [
        "prototype" : .object()
    ],
    methods: [:]
)

let xsProfile = Profile(
    processArgs: { randomize in
        ["-f"]
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0:symbolize=1:print_stacktrace=1:silence_unsigned_overflow=1",
                 "ASAN_OPTIONS": "handle_segv=0:abort_on_error=1:symbolize=1",
                 "MSAN_OPTIONS": "handle_segv=0:abort_on_error=1:symbolize=1",
                 "MSAN_SYMBOLIZER_PATH": "/usr/bin/llvm-symbolizer"],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                gc();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),
    ],

    additionalCodeGenerators: [
        (StressXSMemoryFail,            5),
        (StressXSGC,                    5),
        (HardenGenerator,               5),
        (CompartmentGenerator,          5),
        (CompartmentEvaluateGenerator,  5),
        (UnicodeStringGenerator,        2),
        (ModuleSourceGenerator,         3),
        (HexGenerator,                  2),
        (Base64Generator,               2),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (RegExpFuzzer, 1),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                  : .function([] => .undefined),
        "memoryFail"          : .function([.number] => .number),
        "print"               : .function([.string] => .undefined),

        // hardened javascript
        "Compartment"         : .function([.opt(.object()), .opt(.object()), .opt(.object())] => .jsCompartmentConstructor),
        "ModuleSource"        : .function([.opt(.string)] => .jsModuleSourceConstructor),
        "harden"              : .function([.object()] => .object()),
        "lockdown"            : .function([] => .undefined) ,
        "petrify"             : .function([.anything] => .anything),
        "mutabilities"        : .function([.object()] => .object())
    ],

    additionalObjectGroups: [jsCompartments, jsCompartmentConstructor, jsModuleSources, jsModuleSourceConstructor],

    optionalPostProcessor: nil
)
