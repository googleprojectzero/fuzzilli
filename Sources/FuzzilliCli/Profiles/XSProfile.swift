// Copyright 2019-2022 Google LLC
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

// swift run FuzzilliCli --profile=xs --jobs=8 --storagePath=./results --resume --inspect=history --timeout=100 $MODDABLE/build/bin/mac/debug/xst
// swift run -c release FuzzilliCli --profile=xs --jobs=8 --storagePath=./results --resume --timeout=200 $MODDABLE/build/bin/mac/debug/xst

fileprivate let StressXSGC = CodeGenerator("StressXSGC", inputs: .required(.function())) { b, f in
	guard b.type(of: f).Is(.function()) else { return }		//@@ where did this come from??
    let arguments = b.randomArguments(forCalling: f)

    let index = b.loadInt(1)
    let end = b.loadInt(128)
    let gc = b.loadBuiltin("gc")
	b.callFunction(gc, withArgs: [index])
	b.buildWhileLoop({b.compare(index, with: end, using: .lessThan)}) {
        b.callFunction(f, withArgs: arguments)
		b.unary(.PostInc, index)
		let result = b.callFunction(gc, withArgs: [index])
		b.buildIfElse(result, ifBody: {
			b.loopBreak();
		}, elseBody: {
		});
	}
}

fileprivate let StressXSMemoryFail = CodeGenerator("StressXSMemoryFail", inputs: .required(.function())) { b, f in
	guard b.type(of: f).Is(.function()) else { return }		//@@ where did this come from??
    let arguments = b.randomArguments(forCalling: f)

    let index = b.loadInt(1)
    let max = b.loadInt(1000000)
    let memoryFail = b.loadBuiltin("memoryFail")
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
	let harden = b.loadBuiltin("harden")

	if (Int.random(in: 0...20) < 1) {
		let lockdown = b.loadBuiltin("lockdown")
		b.callFunction(lockdown, withArgs: [])
	}
	b.callFunction(harden, withArgs: [obj])
}

fileprivate let ModuleSourceGenerator = RecursiveCodeGenerator("ModuleSourceGenerator") { b in
	let moduleSourceConstructor = b.loadBuiltin("ModuleSource");

    let code = b.buildCodeString() {
        b.buildRecursive()
    }

	b.construct(moduleSourceConstructor, withArgs: [code])
}

fileprivate let CompartmentGenerator = RecursiveCodeGenerator("CompartmentGenerator") { b in
	let compartmentConstructor = b.loadBuiltin("Compartment");

	var endowments = [String: Variable]()		// may be used as endowments argument or globalLexicals
	var moduleMap = [String: Variable]()
	var options = [String: Variable]()

	for _ in 0..<Int.random(in: 1...4) {
		let propertyName = b.randomCustomPropertyName()
		endowments[propertyName] = b.randomVariable()
	}
	var endowmentsObject = b.createObject(with: endowments)

//@@ populate a moduleMap
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
	options["resolveHook"] = resolveHook;
	options["moduleMapHook"] = moduleMapHook;
	options["loadNowHook"] = loadNowHook;
	options["loadHook"] = loadHook;

	if (Int.random(in: 0...100) < 50) {
		options["globalLexicals"] = endowmentsObject
		endowmentsObject = b.createObject(with: [:]) 
	}
	let optionsObject = b.createObject(with: options)

	let compartment = b.construct(compartmentConstructor, withArgs: [endowmentsObject, moduleMapObject, optionsObject])

	if (Int.random(in: 0...100) < 50) {
		let code = b.buildCodeString() {
			b.buildRecursive(block: 4, of: 4)
		}
		b.callMethod("evaluate", on: compartment, withArgs: [code])
	}
}

fileprivate let UnicodeStringGenerator = CodeGenerator("UnicodeStringGenerator", inputs: .required(.object())) { b, obj in
	var s = ""
	for _ in 0..<Int.random(in: 1...100) {
		let codePoint = UInt32.random(in: 0..<0x10FFFF)
		if ((0xD800 <= codePoint) && (codePoint < 0xE000)) {
			// ignore surrogate pair code points
		}
		else {
			s += String(Unicode.Scalar(codePoint)!)
		}
	}
	b.loadString(s)
}

/*
The inputs to this aren't filtered to jsCompartment but seem to be any just .object()
That's not very useful, so leaving this disabled until that is sorted out

fileprivate let CompartmentEvaluateGenerator = CodeGenerator("CompartmentEvaluateGenerator", inputs: .required(.jsCompartment)) { b, target in
	let code = b.buildCodeString() {
		b.buildRecursive()
	}
	b.callMethod("evaluate", on: target, withArgs: [code])
}
*/

// This template fuzzes the RegExp engine.
// It finds bugs like: crbug.com/1437346 and crbug.com/1439691.
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
            let symbol = b.loadBuiltin("Symbol")
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

    b.eval("%SetForceSlowPath(false)");
    // compile the regexp once
    b.callFunction(f)
    let resFast = b.callFunction(f)
    b.eval("%SetForceSlowPath(true)");
    let resSlow = b.callFunction(f)
    b.eval("%SetForceSlowPath(false)");

    b.build(n: 15)
}

public extension ILType {
    /// Type of a JavaScript Compartment object.
    static let jsCompartment = ILType.object(ofGroup: "Compartment", withProperties: ["globalThis"], withMethods: ["evaluate", "import", "importNow" /* , "module" */])

    static let jsCompartmentConstructor = ILType.constructor([.function()] => .jsCompartment) + .object(ofGroup: "CompartmentConstructor", withProperties: ["prototype"], withMethods: [])

    static let jsModuleSource = ILType.object(ofGroup: "ModuleSource", withProperties: ["bindings", "needsImport", "needsImportMeta"])

    static let jsModuleSourceConstructor = ILType.constructor([.function()] => .jsModuleSource) + .object(ofGroup: "ModuleSourceConstructor", withProperties: ["prototype"], withMethods: [])
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
        (StressXSMemoryFail,    5),
        (StressXSGC,    5),
        (HardenGenerator, 5),
        (CompartmentGenerator, 5),
        (UnicodeStringGenerator, 2),
        (ModuleSourceGenerator, 3)
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
        "Compartment"         : .function([] => .jsCompartmentConstructor),
        "ModuleSource"        : .function([] => .jsModuleSourceConstructor),
		"harden"              : .function([.plain(.anything)] => .undefined),
		"lockdown"            : .function([] => .undefined) ,
		"petrify"             : .function([.plain(.anything)] => .undefined),
		"mutabilities"        : .function([.plain(.anything)] => .object())
    ],

    additionalObjectGroups: [jsCompartments, jsCompartmentConstructor, jsModuleSources, jsModuleSourceConstructor],

    optionalPostProcessor: nil
)
