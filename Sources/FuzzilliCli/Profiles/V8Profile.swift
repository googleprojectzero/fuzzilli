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

fileprivate let ForceJITCompilationThroughLoopGenerator = CodeGenerator("ForceJITCompilationThroughLoopGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceTurboFanCompilationGenerator = CodeGenerator("ForceTurboFanCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let TurbofanVerifyTypeGenerator = CodeGenerator("TurbofanVerifyTypeGenerator", inputs: .one) { b, v in
    b.eval("%VerifyType(%@)", with: [v])
}

fileprivate let WorkerGenerator = RecursiveCodeGenerator("WorkerGenerator") { b in
    let workerSignature = Signature(withParameterCount: Int.random(in: 0...3))

    // TODO(cffsmith): currently Fuzzilli does not know that this code is sent
    // to another worker as a string. This has the consequence that we might
    // use variables inside the worker that are defined in a different scope
    // and as such they are not accessible / undefined. To fix this we should
    // define an Operation attribute that tells Fuzzilli to ignore variables
    // defined in outer scopes.
    let workerFunction = b.buildPlainFunction(with: .parameters(workerSignature.parameters)) { args in
        let this = b.loadThis()

        // Generate a random onmessage handler for incoming messages.
        let onmessageFunction = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildRecursive(block: 1, of: 2)
        }
        b.setProperty("onmessage", of: this, to: onmessageFunction)

        b.buildRecursive(block: 2, of: 2)
    }
    let workerConstructor = b.loadBuiltin("Worker")

    let functionString = b.loadString("function")
    let argumentsArray = b.createArray(with: b.randomArguments(forCalling: workerFunction))

    let configObject = b.createObject(with: ["type": functionString, "arguments": argumentsArray])

    let worker = b.construct(workerConstructor, withArgs: [workerFunction, configObject])
    // Fuzzilli can now use the worker.
}

// Insert random GC calls throughout our code.
fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    let gc = b.loadBuiltin("gc")

    // Do minor GCs more frequently.
    let type = b.loadString(probability(0.25) ? "major" : "minor")
    // If the execution type is 'async', gc() returns a Promise, we currently
    // do not really handle other than typing the return of gc to .undefined |
    // .jsPromise. One could either chain a .then or create two wrapper
    // functions that are differently typed such that fuzzilli always knows
    // what the type of the return value is.
    let execution = b.loadString(probability(0.5) ? "sync" : "async")
    b.callFunction(gc, withArgs: [b.createObject(with: ["type": type, "execution": execution])])
}

fileprivate let MapTransitionFuzzer = ProgramTemplate("MapTransitionFuzzer") { b in
    // This template is meant to stress the v8 Map transition mechanisms.
    // Basically, it generates a bunch of CreateObject, GetProperty, SetProperty, FunctionDefinition,
    // and CallFunction operations operating on a small set of objects and property names.

    let propertyNames = b.fuzzer.environment.customProperties
    assert(Set(propertyNames).isDisjoint(with: b.fuzzer.environment.customMethods))

    // Use this as base object type. For one, this ensures that the initial map is stable.
    // Moreover, this guarantees that when querying for this type, we will receive one of
    // the objects we created and not e.g. a function (which is also an object).
    assert(propertyNames.contains("a"))
    let objType = JSType.object(withProperties: ["a"])

    // Helper function to pick random properties and values.
    func randomProperties(in b: ProgramBuilder) -> ([String], [Variable]) {
        if !b.hasVisibleVariables {
            // Use integer values if there are no visible variables, which should be a decent fallback.
            b.loadInt(b.randomInt())
        }

        var properties = ["a"]
        var values = [b.randomVariable()]
        for _ in 0..<3 {
            let property = chooseUniform(from: propertyNames)
            guard !properties.contains(property) else { continue }
            properties.append(property)
            values.append(b.randomVariable())
        }
        assert(Set(properties).count == values.count)
        return (properties, values)
    }

    // Temporarily overwrite the active code generators with the following generators...
    let primitiveValueGenerator = ValueGenerator("PrimitiveValue") { b, n in
        for _ in 0..<n {
            // These should roughly correspond to the supported property representations of the engine.
            withEqualProbability({
                b.loadInt(b.randomInt())
            }, {
                b.loadFloat(b.randomFloat())
            }, {
                b.loadString(b.randomString())
            })
        }
    }
    let createObjectGenerator = ValueGenerator("CreateObject") { b, n in
        for _ in 0..<n {
            let (properties, values) = randomProperties(in: b)
            let obj = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectMakerGenerator = ValueGenerator("ObjectMaker") { b, n in
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            let (properties, values) = randomProperties(in: b)
            let o = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            b.doReturn(o)
        }
        for _ in 0..<n {
            let obj = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectConstructorGenerator = ValueGenerator("ObjectConstructor") { b, n in
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]
            let (properties, values) = randomProperties(in: b)
            for (p, v) in zip(properties, values) {
                b.setProperty(p, of: this, to: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(c, withArgs: b.randomArguments(forCalling: c))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectClassGenerator = ValueGenerator("ObjectClassGenerator") { b, n in
        let superclass = b.hasVisibleVariables && probability(0.5) ? b.randomVariable(ofType: .constructor()) : nil
        let (properties, values) = randomProperties(in: b)
        let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
            for (p, v) in zip(properties, values) {
                cls.addInstanceProperty(p, value: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(cls)
            assert(b.type(of: obj).Is(objType))
        }
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.getProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        let numProperties = Int.random(in: 1...3)
        for _ in 0..<numProperties {
            b.setProperty(chooseUniform(from: propertyNames), of: obj, to: b.randomVariable())
        }
    }
    let propertyConfigureGenerator = CodeGenerator("PropertyConfigure", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.configureProperty(chooseUniform(from: propertyNames), of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
    }
    let functionDefinitionGenerator = RecursiveCodeGenerator("FunctionDefinition") { b in
        // We use either a randomly generated signature or a fixed on that ensures we use our object type frequently.
        var parameters = b.randomParameters()
        let haveVisibleObjects = b.visibleVariables.contains(where: { b.type(of: $0).Is(objType) })
        if probability(0.5) && haveVisibleObjects {
            parameters = .parameters(.plain(objType), .plain(objType), .anything, .anything)
        }

        let f = b.buildPlainFunction(with: parameters) { params in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }

        for _ in 0..<3 {
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let rval = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    }
    let constructorCallGenerator = CodeGenerator("ConstructorCall", inputs: .required(.constructor())) { b, c in
        assert(b.type(of: c).Is(.constructor()))
        let rval = b.construct(c, withArgs: b.randomArguments(forCalling: c))
     }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let args = b.randomArguments(forCalling: f)
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: args)
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
        (primitiveValueGenerator,     2),
        (createObjectGenerator,       1),
        (objectMakerGenerator,        1),
        (objectConstructorGenerator,  1),
        (objectClassGenerator,        1),

        (propertyStoreGenerator,      10),
        (propertyLoadGenerator,       10),
        (propertyConfigureGenerator,  5),
        (functionDefinitionGenerator, 2),
        (functionCallGenerator,       3),
        (constructorCallGenerator,    2),
        (functionJitCallGenerator,    2)
    ]))

    // ... run some of the ValueGenerators to create some initial objects ...
    b.buildPrefix()
    // ... and generate a bunch of code.
    b.build(n: 100, by: .generating)

    // Now, restore the previous code generators and generate some more code.
    b.fuzzer.setCodeGenerators(prevCodeGenerators)
    b.build(n: 10)

    // Finally, run HeapObjectVerify on all our generated objects (that are still in scope).
    for obj in b.visibleVariables where b.type(of: obj).Is(objType) {
        b.eval("%HeapObjectVerify(%@)", with: [obj])
    }
}

fileprivate let ValueSerializerFuzzer = ProgramTemplate("ValueSerializerFuzzer") { b in
    b.buildPrefix()

    // Create some random values that can be serialized below.
    b.build(n: 50)

    // Load necessary builtins
    let d8 = b.loadBuiltin("d8")
    let serializer = b.getProperty("serializer", of: d8)
    let Uint8Array = b.loadBuiltin("Uint8Array")

    // Serialize a random object
    let content = b.callMethod("serialize", on: serializer, withArgs: [b.randomVariable()])
    let u8 = b.construct(Uint8Array, withArgs: [content])

    // Choose a random byte to change
    let index = Int64.random(in: 0..<100)

    // Either flip or replace the byte
    let newByte: Variable
    if probability(0.5) {
        let bit = b.loadInt(1 << Int.random(in: 0..<8))
        let oldByte = b.getElement(index, of: u8)
        newByte = b.binary(oldByte, bit, with: .Xor)
    } else {
        newByte = b.loadInt(Int64.random(in: 0..<256))
    }
    b.setElement(index, of: u8, to: newByte)

    // Deserialize the resulting buffer
    let _ = b.callMethod("deserialize", on: serializer, withArgs: [content])

    // Generate some more random code to (hopefully) use the deserialized objects in some interesting way.
    b.build(n: 10)
}

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

let v8Profile = Profile(
    processArgs: { randomize in
        var args = [
            "--expose-gc",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--jit-fuzzing",
            "--future",
            "--harmony"
        ]

        guard randomize else { return args }

        //
        // Existing features that should sometimes be disabled.
        //
        if probability(0.1) {
            args.append("--no-turbofan")
        }

        if probability(0.1) {
            args.append("--no-turboshaft")
        }

        if probability(0.1) {
            args.append("--no-maglev")
        }

        if probability(0.1) {
            args.append("--no-sparkplug")
        }

        if probability(0.1) {
            args.append("--no-short-builtin-calls")
        }

        //
        // Future features that should sometimes be enabled.
        //
        if probability(0.25) {
            args.append("--minor-mc")
        }

        if probability(0.25) {
            args.append("--shared-string-table")
        }

        if probability(0.25) && !args.contains("--no-maglev") {
            args.append("--maglev-future")
        }

        if probability(0.1) {
            args.append("--harmony-struct")
        }

        if probability(0.1) {
            args.append("--turboshaft-typed-optimizations")
        }

        //
        // Sometimes enable additional verification logic (which may be fairly expensive).
        //
        if probability(0.1) {
            args.append("--verify-heap")
        }
        if probability(0.1) {
            args.append("--turbo-verify")
        }
        if probability(0.1) {
            args.append("--turbo-verify-allocation")
        }
        if probability(0.1) {
            args.append("--assert-types")
        }
        if probability(0.1) {
            args.append("--turboshaft-assert-types")
        }

        //
        // More exotic configuration changes.
        //
        if probability(0.05) {
            args.append(probability(0.5) ? "--always-sparkplug" : "--no-always-sparkplug")
            args.append(probability(0.5) ? "--always-osr" : "--no-always-osr")
            args.append(probability(0.5) ? "--concurrent-osr" : "--no-concurrent-osr")
            args.append(probability(0.5) ? "--force-slow-path" : "--no-force-slow-path")
            if !args.contains("--no-turbofan") && !args.contains("--no-turboshaft") {
                args.append(probability(0.5) ? "--always-turbofan" : "--no-always-turbofan")
                args.append(probability(0.5) ? "--turbo-move-optimization" : "--no-turbo-move-optimization")
                args.append(probability(0.5) ? "--turbo-jt" : "--no-turbo-jt")
                args.append(probability(0.5) ? "--turbo-loop-peeling" : "--no-turbo-loop-peeling")
                args.append(probability(0.5) ? "--turbo-loop-variable" : "--no-turbo-loop-variable")
                args.append(probability(0.5) ? "--turbo-loop-rotation" : "--no-turbo-loop-rotation")
                args.append(probability(0.5) ? "--turbo-cf-optimization" : "--no-turbo-cf-optimization")
                args.append(probability(0.5) ? "--turbo-escape" : "--no-turbo-escape")
                args.append(probability(0.5) ? "--turbo-allocation-folding" : "--no-turbo-allocation-folding")
                args.append(probability(0.5) ? "--turbo-instruction-scheduling" : "--no-turbo-instruction-scheduling")
                args.append(probability(0.5) ? "--turbo-stress-instruction-scheduling" : "--no-turbo-stress-instruction-scheduling")
                args.append(probability(0.5) ? "--turbo-store-elimination" : "--no-turbo-store-elimination")
                args.append(probability(0.5) ? "--turbo-rewrite-far-jumps" : "--no-turbo-rewrite-far-jumps")
                args.append(probability(0.5) ? "--turbo-optimize-apply" : "--no-turbo-optimize-apply")
                args.append(chooseUniform(from: ["--no-enable-sse3", "--no-enable-ssse3", "--no-enable-sse4-1", "--no-enable-sse4-2", "--no-enable-avx", "--no-enable-avx2"]))
                args.append(probability(0.5) ? "--turbo-load-elimination" : "--no-turbo-load-elimination")
                args.append(probability(0.5) ? "--turbo-inlining" : "--no-turbo-inlining")
                args.append(probability(0.5) ? "--turbo-splitting" : "--no-turbo-splitting")
            }
        }

        return args
    },

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (TurbofanVerifyTypeGenerator,             10),

        (WorkerGenerator,                         10),
        (GcGenerator,                             10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionFuzzer,    1),
        (ValueSerializerFuzzer,  1),
        (RegExpFuzzer,           1),
    ]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"                                            : .function([] => (.undefined | .jsPromise)),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.anything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ]
)
