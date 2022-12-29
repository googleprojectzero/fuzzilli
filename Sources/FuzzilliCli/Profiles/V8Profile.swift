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

fileprivate let ForceV8TurbofanGenerator = CodeGenerator("ForceV8TurbofanGenerator", input: .function()) { b, f in
    // The MutationEngine may use variables of unknown type as input as well, however, we only want to call functions that we generated ourselves. Further, attempting to call a non-function will result in a runtime exception.
    // For both these reasons, we abort here if we cannot prove that f is indeed a function.
    guard b.type(of: f).Is(.function()) else { return }
    guard let arguments = b.randCallArguments(for: f) else { return }

    b.buildRepeat(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
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
    let workerFunction = b.buildPlainFunction(with: .signature(workerSignature)) { args in
        let this = b.loadThis()

        // Generate a random onmessage handler for incoming messages.
        let onmessageFunction = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.buildRecursive(block: 1, of: 2)
        }
        b.storeProperty(onmessageFunction, as: "onmessage", on: this)

        b.buildRecursive(block: 2, of: 2)
    }
    let workerConstructor = b.loadBuiltin("Worker")

    let functionString = b.loadString("function")
    let argumentsArray = b.createArray(with: b.generateCallArguments(for: workerSignature))

    let configObject = b.createObject(with: ["type": functionString, "arguments": argumentsArray])

    let worker = b.construct(workerConstructor, withArgs: [workerFunction, configObject])
    // Fuzzilli can now use the worker.
}

fileprivate let SerializeDeserializeGenerator = CodeGenerator("SerializeDeserializeGenerator", input: .object()) { b, o in
    // Load necessary builtins
    let d8 = b.reuseOrLoadBuiltin("d8")
    let serializer = b.loadProperty("serializer", of: d8)
    let Uint8Array = b.reuseOrLoadBuiltin("Uint8Array")

    // Serialize a random object
    let content = b.callMethod("serialize", on: serializer, withArgs: [o])
    let u8 = b.construct(Uint8Array, withArgs: [content])

    // Choose a random byte to change
    let index = Int64.random(in: 0..<100)

    // Either flip or replace the byte
    let newByte: Variable
    if probability(0.5) {
        let bit = b.loadInt(1 << Int.random(in: 0..<8))
        let oldByte = b.loadElement(index, of: u8)
        newByte = b.binary(oldByte, bit, with: .Xor)
    } else {
        newByte = b.loadInt(Int64.random(in: 0..<256))
    }
    b.storeElement(newByte, at: index, of: u8)

    // Deserialize the resulting buffer
    let _ = b.callMethod("deserialize", on: serializer, withArgs: [content])

    // Deserialized object is available in a variable now and can be used by following code
}

fileprivate let MapTransitionsTemplate = ProgramTemplate("MapTransitionsTemplate") { b in
    // This template is meant to stress the v8 Map transition mechanisms.
    // Basically, it generates a bunch of CreateObject, LoadProperty, StoreProperty, FunctionDefinition,
    // and CallFunction operations operating on a small set of objects and property names.

    let propertyNames = ["a", "b", "c", "d", "e", "f", "g"]
    assert(Set(propertyNames).isDisjoint(with: b.fuzzer.environment.customMethodNames))

    // Use this as base object type. For one, this ensures that the initial map is stable.
    // Moreover, this guarantees that when querying for this type, we will receive one of
    // the objects we created and not e.g. a function (which is also an object).
    let objType = JSType.object(withProperties: ["a"])

    // Signature of functions generated in this template
    let sig = [.plain(objType), .plain(objType)] => objType

    // Create property values: integers, doubles, and heap objects.
    // These should correspond to the supported property representations of the engine.
    let intVal = b.loadInt(42)
    let floatVal = b.loadFloat(13.37)
    let objVal = b.createObject(with: [:])
    let propertyValues = [intVal, floatVal, objVal]

    // Keep track of all objects created in this template so that they can be verified at the end.
    var objects = [objVal]

    // Now create a bunch of objects to operate on and one function that constructs a new object.
    b.buildPlainFunction(with: .parameters(n: 0)) { args in
        let o = b.createObject(with: ["a": intVal])
        b.doReturn(o)
    }
    for _ in 0..<3 {
        objects.append(b.createObject(with: ["a": intVal]))
    }

    // Next, temporarily overwrite the active code generators with the following generators...
    let createObjectGenerator = CodeGenerator("CreateObject") { b in
        let obj = b.createObject(with: ["a": intVal])
        objects.append(obj)
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", input: objType) { b, obj in
        assert(objects.contains(obj))
        b.loadProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", input: objType) { b, obj in
        assert(objects.contains(obj))
        let numProperties = Int.random(in: 1...4)
        for _ in 0..<numProperties {
            b.storeProperty(chooseUniform(from: propertyValues), as: chooseUniform(from: propertyNames), on: obj)
        }
    }
    let functionDefinitionGenerator = RecursiveCodeGenerator("FunctionDefinition") { b in
        let prevSize = objects.count
        b.buildPlainFunction(with: .signature(sig)) { params in
            objects += params
            b.buildRecursive()
            b.doReturn(b.randVar(ofType: objType)!)
        }
        objects.removeLast(objects.count - prevSize)
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", input: .function()) { b, f in
        let args = b.randCallArguments(for: sig)!
        assert(objects.contains(args[0]) && objects.contains(args[1]))
        let rval = b.callFunction(f, withArgs: args)
        assert(b.type(of: rval).Is(objType))
        objects.append(rval)
    }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", input: .function()) { b, f in
        let args = b.randCallArguments(for: sig)!
        assert(objects.contains(args[0]) && objects.contains(args[1]))
        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
            b.callFunction(f, withArgs: args)       // Rval goes out-of-scope immediately, so no need to track it
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.codeGenerators = WeightedList<CodeGenerator>([
        (createObjectGenerator,       1),
        (propertyLoadGenerator,       2),
        (propertyStoreGenerator,      5),
        (functionDefinitionGenerator, 1),
        (functionCallGenerator,       2),
        (functionJitCallGenerator,    1)
    ])

    // ... and generate a bunch of code.
    b.build(n: 100, by: .runningGenerators)

    // Now, restore the previous code generators, re-enable splicing, and generate some more code
    b.fuzzer.codeGenerators = prevCodeGenerators
    b.build(n: 10)

    // Finally, run HeapObjectVerify on all our generated objects (that are still in scope)
    for obj in objects {
        b.eval("%HeapObjectVerify(%@)", with: [obj])
    }
}

// A variant of the JITFunction template that sprinkles calls to the %VerifyType builtin into the target function.
// Probably should be kept in sync with the original template.
fileprivate let VerifyTypeTemplate = ProgramTemplate("VerifyTypeTemplate") { b in
    let genSize = 3

    // Generate random function signatures as our helpers
    var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

    // Generate random property types
    ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)

    // Generate random method types
    ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

    b.build(n: genSize)

    // Generate some small functions
    for signature in functionSignatures {
        // Here generate a random function type, e.g. arrow/generator etc
        b.buildPlainFunction(with: .signature(signature)) { args in
            b.build(n: genSize)
        }
    }

    // Generate a larger function
    let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
    let f = b.buildPlainFunction(with: .signature(signature)) { args in
        // Generate function body and sprinkle calls to %VerifyType
        for _ in 0..<10 {
            b.build(n: 3)
            b.eval("%VerifyType(%@)", with: [b.randVar()])
        }
    }

    // Generate some random instructions now
    b.build(n: genSize)

    // trigger JIT
    b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
        b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
    }

    // more random instructions
    b.build(n: genSize)
    b.callFunction(f, withArgs: b.generateCallArguments(for: signature))

    // maybe trigger recompilation
    b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
        b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
    }

    // more random instructions
    b.build(n: genSize)

    b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
}

let v8Profile = Profile(
    getProcessArguments: { (randomizingArguments: Bool) -> [String] in
        var args = [
            "--expose-gc",
            "--omit-quit",
            "--future",
            "--harmony",
            "--assert-types",
            "--harmony-rab-gsab",
            "--harmony-struct",
            "--allow-natives-syntax",
            "--interrupt-budget=1000",
            "--fuzzing"]

        guard randomizingArguments else { return args }

        args.append(probability(0.9) ? "--sparkplug" : "--no-sparkplug")
        args.append(probability(0.9) ? "--opt" : "--no-opt")
        args.append(probability(0.9) ? "--lazy" : "--no-lazy")
        args.append(probability(0.1) ? "--always-opt" : "--no-always-opt")
        args.append(probability(0.1) ? "--always-osr" : "--no-always-osr")
        args.append(probability(0.1) ? "--force-slow-path" : "--no-force-slow-path")
        args.append(probability(0.9) ? "--turbo-move-optimization" : "--no-turbo-move-optimization")
        args.append(probability(0.9) ? "--turbo-jt" : "--no-turbo-jt")
        args.append(probability(0.9) ? "--turbo-loop-peeling" : "--no-turbo-loop-peeling")
        args.append(probability(0.9) ? "--turbo-loop-variable" : "--no-turbo-loop-variable")
        args.append(probability(0.9) ? "--turbo-loop-rotation" : "--no-turbo-loop-rotation")
        args.append(probability(0.9) ? "--turbo-cf-optimization" : "--no-turbo-cf-optimization")
        args.append(probability(0.9) ? "--turbo-escape" : "--no-turbo-escape")
        args.append(probability(0.9) ? "--turbo-allocation-folding" : "--no-turbo-allocation-folding")
        args.append(probability(0.9) ? "--turbo-instruction-scheduling" : "--no-turbo-instruction-scheduling")
        args.append(probability(0.9) ? "--turbo-stress-instruction-scheduling" : "--no-turbo-stress-instruction-scheduling")
        args.append(probability(0.9) ? "--turbo-store-elimination" : "--no-turbo-store-elimination")
        args.append(probability(0.9) ? "--turbo-rewrite-far-jumps" : "--no-turbo-rewrite-far-jumps")
        args.append(probability(0.9) ? "--turbo-optimize-apply" : "--no-turbo-optimize-apply")
        args.append(chooseUniform(from: ["--no-enable-sse3", "--no-enable-ssse3", "--no-enable-sse4-1", "--no-enable-sse4-2", "--no-enable-avx", "--no-enable-avx2"]))
        args.append(probability(0.9) ? "--turbo-load-elimination" : "--no-turbo-load-elimination")
        args.append(probability(0.9) ? "--turbo-inlining" : "--no-turbo-inlining")
        args.append(probability(0.9) ? "--turbo-splitting" : "--no-turbo-splitting")

        return args
    },

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                gc();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: [
        (ForceV8TurbofanGenerator,      10),
        (TurbofanVerifyTypeGenerator,   10),
        (SerializeDeserializeGenerator, 10),
        (WorkerGenerator,               10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionsTemplate, 1),
        (VerifyTypeTemplate, 1)
    ]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"                                            : .function([] => .undefined),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.anything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ]
)
