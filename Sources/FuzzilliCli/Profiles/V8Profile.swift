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

fileprivate let ForceJITCompilationThroughLoopGenerator = CodeGenerator("ForceJITCompilationThroughLoopGenerator", input: .function()) { b, f in
    // The MutationEngine may use variables of unknown type as input as well, however, we only want to call functions that we generated ourselves. Further, attempting to call a non-function will result in a runtime exception.
    // For both these reasons, we abort here if we cannot prove that f is indeed a function.
    guard b.type(of: f).Is(.function()) else { return }
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceTurboFanCompilationGenerator = CodeGenerator("ForceTurboFanCompilationGenerator", input: .function()) { b, f in
    // See comment in ForceJITCompilationThroughLoopGenerator.
    guard b.type(of: f).Is(.function()) else { return }
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", input: .function()) { b, f in
    // See comment in ForceJITCompilationThroughLoopGenerator.
    guard b.type(of: f).Is(.function()) else { return }
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

fileprivate let TurbofanVerifyTypeGenerator = CodeGenerator("TurbofanVerifyTypeGenerator", input: .anything) { b, v in
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

fileprivate let SerializeDeserializeGenerator = CodeGenerator("SerializeDeserializeGenerator", input: .object()) { b, o in
    // Load necessary builtins
    let d8 = b.loadBuiltin("d8")
    let serializer = b.getProperty("serializer", of: d8)
    let Uint8Array = b.loadBuiltin("Uint8Array")

    // Serialize a random object
    let content = b.callMethod("serialize", on: serializer, withArgs: [o])
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

    // Deserialized object is available in a variable now and can be used by following code
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

fileprivate let MapTransitionsTemplate = ProgramTemplate("MapTransitionsTemplate") { b in
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

    // Keep track of all objects created in this template so that they can be verified at the end.
    var objects = [Variable]()

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
            objects.append(obj)
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
            objects.append(obj)
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
            objects.append(obj)
        }
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", input: objType) { b, obj in
        b.getProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", input: objType) { b, obj in
        let numProperties = Int.random(in: 1...4)
        for _ in 0..<numProperties {
            b.setProperty(chooseUniform(from: propertyNames), of: obj, to: b.randomVariable())
        }
    }
    let functionDefinitionGenerator = RecursiveCodeGenerator("FunctionDefinition") { b in
        let prevSize = objects.count

        // We use either a randomly generated signature or a fixed on that ensures we use our object type frequently.
        var parameters = b.randomParameters()
        if probability(0.5) && !objects.isEmpty {
            parameters = .parameters(.plain(objType), .plain(objType), .anything, .anything)
        }

        let f = b.buildPlainFunction(with: parameters) { params in
            for p in params where b.type(of: p).Is(objType) {
                objects.append(p)
            }
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        objects.removeLast(objects.count - prevSize)

        for _ in 0..<3 {
            let rval = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
            if b.type(of: rval).Is(objType) {
                objects.append(rval)
            }
        }
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", input: .function()) { b, f in
        let rval = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        if b.type(of: rval).Is(objType) {
            objects.append(rval)
        }
    }
    let constructorCallGenerator = CodeGenerator("ConstructorCall", input: .constructor()) { b, f in
        let rval = b.construct(f, withArgs: b.randomArguments(forCalling: f))
        if b.type(of: rval).Is(objType) {
            objects.append(rval)
        }
     }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", input: .function()) { b, f in
        let args = b.randomArguments(forCalling: f)
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: args)       // Rval goes out-of-scope immediately, so no need to track it
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
        (primitiveValueGenerator,     2),
        (createObjectGenerator,       1),
        (objectMakerGenerator,        1),
        (objectConstructorGenerator,  1),
        (propertyLoadGenerator,       2),
        (propertyStoreGenerator,      5),
        (functionDefinitionGenerator, 1),
        (functionCallGenerator,       2),
        (constructorCallGenerator,    1),
        (functionJitCallGenerator,    1)
    ]))

    // ... run some of the ValueGenerators to create some initial objects ...
    b.buildValues(5)
    // ... and generate a bunch of code.
    b.build(n: 100, by: .generating)

    // Now, restore the previous code generators and generate some more code.
    b.fuzzer.setCodeGenerators(prevCodeGenerators)
    b.build(n: 10)

    // Finally, run HeapObjectVerify on all our generated objects (that are still in scope).
    for obj in objects {
        b.eval("%HeapObjectVerify(%@)", with: [obj])
    }
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
        // Future features that should sometimes be enabled.
        //
        if probability(0.25) {
            args.append("--harmony-struct")
        }

        if probability(0.25) {
            args.append("--minor-mc")
        }

        if probability(0.25) {
            args.append("--shared-string-table")
        }

        if probability(0.25) {
            args.append("--turboshaft")

            if probability(0.25) {
                args.append("--turboshaft-assert-types")
            }
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
            args.append("--assert-types")
        }
        if probability(0.1) {
            args.append("--turbo-verify-allocation")
        }

        //
        // Existing features that should sometimes be disabled.
        //
        if probability(0.1) {
            args.append("--no-turbofan")
        }

        if probability(0.1) {
            args.append("--no-maglev")
        }

        if probability(0.1) {
            args.append("--no-sparkplug")
        }

        //
        // More exotic configuration changes.
        //
        if probability(0.05) {
            args.append(probability(0.5) ? "--always-sparkplug" : "--no-always-sparkplug")
            args.append(probability(0.5) ? "--always-osr" : "--no-always-osr")
            args.append(probability(0.5) ? "--force-slow-path" : "--no-force-slow-path")
            if !args.contains("--no-turbofan") {
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
        (SerializeDeserializeGenerator,           10),
        (WorkerGenerator,                         10),
        (GcGenerator,                             10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionsTemplate, 1),
    ]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"                                            : .function([] => (.undefined | .jsPromise)),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.anything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ]
)
