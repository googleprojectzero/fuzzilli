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

public extension ILType {
    static let jsD8 = ILType.object(ofGroup: "D8", withProperties: ["test"], withMethods: [])

    static let jsD8Test = ILType.object(ofGroup: "D8Test", withProperties: ["FastCAPI"], withMethods: [])

    static let jsD8FastCAPI = ILType.object(ofGroup: "D8FastCAPI", withProperties: [], withMethods: ["throw_no_fallback", "add_32bit_int"])

    static let jsD8FastCAPIConstructor = ILType.constructor([] => .jsD8FastCAPI)

    static let gcTypeEnum = ILType.enumeration(ofName: "gcType", withValues: ["minor", "major"])
    static let gcExecutionEnum = ILType.enumeration(ofName: "gcExecution", withValues: ["async", "sync"])
}

public let gcOptions = ObjectGroup(
    name: "GCOptions",
    instanceType: .object(ofGroup: "GCOptions", withProperties: ["type", "execution"], withMethods: []),
    properties: ["type": .gcTypeEnum,
                 "execution": .gcExecutionEnum],
    methods: [:])

public let fastCallables : [(group: ILType, method: String)] = [
    (group: .jsD8FastCAPI, method: "throw_no_fallback"),
    (group: .jsD8FastCAPI, method: "add_32bit_int"),
]

// Insert random GC calls throughout our code.
public let V8GcGenerator = CodeGenerator("GcGenerator") { b in
    let gc = b.createNamedVariable(forBuiltin: "gc")

    // `gc()` takes a `type` parameter. If the value is 'async', gc() returns a
    // Promise. We currently do not really handle this other than typing the
    // return of gc to .undefined | .jsPromise. One could either chain a .then
    // or create two wrapper functions that are differently typed such that
    // fuzzilli always knows what the type of the return value is.
    b.callFunction(gc, withArgs: b.findOrGenerateArguments(forSignature: b.fuzzer.environment.type(ofBuiltin: "gc").signature!))
}

public let ForceJITCompilationThroughLoopGenerator = CodeGenerator("ForceJITCompilationThroughLoopGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

public let ForceTurboFanCompilationGenerator = CodeGenerator("ForceTurboFanCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

public let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: arguments)
}

public let TurbofanVerifyTypeGenerator = CodeGenerator("TurbofanVerifyTypeGenerator", inputs: .one) { b, v in
    b.eval("%VerifyType(%@)", with: [v])
}

public let WorkerGenerator = CodeGenerator("WorkerGenerator") { b in
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
            b.buildRecursive(n: Int.random(in: 2...5))
        }
        b.setProperty("onmessage", of: this, to: onmessageFunction)

        b.buildRecursive(n: Int.random(in: 3...10))
    }
    let workerConstructor = b.createNamedVariable(forBuiltin: "Worker")

    let functionString = b.loadString("function")
    let argumentsArray = b.createArray(with: b.randomArguments(forCalling: workerFunction))

    let configObject = b.createObject(with: ["type": functionString, "arguments": argumentsArray])

    let worker = b.construct(workerConstructor, withArgs: [workerFunction, configObject])
    // Fuzzilli can now use the worker.
}

public let WasmStructGenerator = CodeGenerator("WasmStructGenerator") { b in
    b.eval("%WasmStruct()", hasOutput: true);
}

public let WasmArrayGenerator = CodeGenerator("WasmArrayGenerator") { b in
    b.eval("%WasmArray()", hasOutput: true);
}

public let SharedObjectGenerator = CodeGenerator("SharedObjectGenerator", inputs: .one) { b, v in
    b.eval("%ShareObject(%@)", with: [v], hasOutput: true);
}

public let PretenureAllocationSiteGenerator = CodeGenerator("PretenureAllocationSiteGenerator", inputs: .required(.object())) { b, obj in
    b.eval("%PretenureAllocationSite(%@)", with: [obj]);
}

public let MapTransitionFuzzer = ProgramTemplate("MapTransitionFuzzer") { b in
    // This template is meant to stress the v8 Map transition mechanisms.
    // Basically, it generates a bunch of CreateObject, GetProperty, SetProperty, FunctionDefinition,
    // and CallFunction operations operating on a small set of objects and property names.

    let propertyNames = b.fuzzer.environment.customProperties
    assert(Set(propertyNames).isDisjoint(with: b.fuzzer.environment.customMethods))

    // Use this as base object type. For one, this ensures that the initial map is stable.
    // Moreover, this guarantees that when querying for this type, we will receive one of
    // the objects we created and not e.g. a function (which is also an object).
    assert(propertyNames.contains("a"))
    let objType = ILType.object(withProperties: ["a"])

    // Helper function to pick random properties and values.
    func randomProperties(in b: ProgramBuilder) -> ([String], [Variable]) {
        if !b.hasVisibleVariables {
            // Use integer values if there are no visible variables, which should be a decent fallback.
            b.loadInt(b.randomInt())
        }

        var properties = ["a"]
        var values = [b.randomJsVariable()]
        for _ in 0..<3 {
            let property = chooseUniform(from: propertyNames)
            guard !properties.contains(property) else { continue }
            properties.append(property)
            values.append(b.randomJsVariable())
        }
        assert(Set(properties).count == values.count)
        return (properties, values)
    }

    // Temporarily overwrite the active code generators with the following generators...
    let primitiveCodeGenerator = CodeGenerator("PrimitiveValue", produces: [.primitive]) { b in
        // These should roughly correspond to the supported property representations of the engine.
        withEqualProbability({
            b.loadInt(b.randomInt())
        }, {
            b.loadFloat(b.randomFloat())
        }, {
            b.loadString(b.randomString())
        })
    }
    let createObjectGenerator = CodeGenerator("CreateObject", produces: [.object()]) { b in
        let (properties, values) = randomProperties(in: b)
        let obj = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
        assert(b.type(of: obj).Is(objType))
    }
    let objectMakerGenerator = CodeGenerator("ObjectMaker") { b in
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            let (properties, values) = randomProperties(in: b)
            let o = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            b.doReturn(o)
        }
        for _ in 0..<3 {
            let obj = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectConstructorGenerator = CodeGenerator("ObjectConstructor") { b in
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]
            let (properties, values) = randomProperties(in: b)
            for (p, v) in zip(properties, values) {
                b.setProperty(p, of: this, to: v)
            }
        }
        for _ in 0..<3 {
            let obj = b.construct(c, withArgs: b.randomArguments(forCalling: c))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectClassGenerator = CodeGenerator("ObjectClassGenerator") { b in
        let superclass = b.hasVisibleVariables && probability(0.5) ? b.randomVariable(ofType: .constructor()) : nil
        let (properties, values) = randomProperties(in: b)
        let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
            for (p, v) in zip(properties, values) {
                cls.addInstanceProperty(p, value: v)
            }
        }
        for _ in 0..<3 {
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
            b.setProperty(chooseUniform(from: propertyNames), of: obj, to: b.randomJsVariable())
        }
    }
    let propertyConfigureGenerator = CodeGenerator("PropertyConfigure", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.configureProperty(chooseUniform(from: propertyNames), of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomJsVariable()))
    }
    let functionDefinitionGenerator = CodeGenerator("FunctionDefinition") { b in
        // We use either a randomly generated signature or a fixed on that ensures we use our object type frequently.
        var parameters = b.randomParameters()
        let haveVisibleObjects = b.visibleVariables.contains(where: { b.type(of: $0).Is(objType) })
        if probability(0.5) && haveVisibleObjects {
            parameters = .parameters(.plain(objType), .plain(objType), .jsAnything, .jsAnything)
        }

        let f = b.buildPlainFunction(with: parameters) { params in
            b.buildRecursive(n: Int.random(in: 3...10))
            b.doReturn(b.randomJsVariable())
        }

        for _ in 0..<3 {
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        }
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
        let rval = b.callFunction(f, withArgs: arguments, guard: !matches)
    }
    let constructorCallGenerator = CodeGenerator("ConstructorCall", inputs: .required(.constructor())) { b, c in
        assert(b.type(of: c).Is(.constructor()))
        let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: c)
        let rval = b.construct(c, withArgs: arguments, guard: !matches)
     }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let args = b.randomArguments(forCalling: f)
        b.buildRepeatLoop(n: 100) { _ in
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
        (primitiveCodeGenerator,     2),
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

    // ... run some of the CodeGenerators to create some initial objects ...
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

public let ValueSerializerFuzzer = ProgramTemplate("ValueSerializerFuzzer") { b in
    b.buildPrefix()

    // Create some random values that can be serialized below.
    b.build(n: 50)

    // Load necessary builtins
    let d8 = b.createNamedVariable(forBuiltin: "d8")
    let serializer = b.getProperty("serializer", of: d8)
    let Uint8Array = b.createNamedVariable(forBuiltin: "Uint8Array")

    // Serialize a random object
    let content = b.callMethod("serialize", on: serializer, withArgs: [b.randomJsVariable()])
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
public let V8RegExpFuzzer = ProgramTemplate("RegExpFuzzer") { b in
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

    b.eval("%SetForceSlowPath(false)");
    // compile the regexp once
    b.callFunction(f)
    let resFast = b.callFunction(f)
    b.eval("%SetForceSlowPath(true)");
    let resSlow = b.callFunction(f)
    b.eval("%SetForceSlowPath(false)");

    b.build(n: 15)
}

// Emits calls with recursive calls of limited depth.
public let LazyDeoptFuzzer = ProgramTemplate("LazyDeoptFuzzer") { b in
    b.buildPrefix()
    b.build(n: 30)

    let counter = b.loadInt(0)
    let max = b.loadInt(Int64.random(in: 2...5))
    let params = b.randomParameters()
    let dummyFct = b.buildPlainFunction(with: params) { args in
        b.loadString("Dummy function for emitting recursive call")
    }
    let realFct = b.buildPlainFunction(with: params) { args in
        b.build(n: 10)

        b.buildIf(b.compare(counter, with: max, using: .lessThan)) {
            b.reassign(counter, to: b.binary(counter, b.loadInt(1), with: .Add))
            b.callFunction(dummyFct, withArgs: b.randomArguments(forCalling: dummyFct))
        }
        // Mark the function for deoptimization. Due to the recursive pattern above, on the outer
        // stack frames this should trigger a lazy deoptimization.
        b.eval("%DeoptimizeNow();");
        b.build(n: 30)
        b.doReturn(b.randomJsVariable())
    }

    // Turn the call into a recursive call.
    b.reassign(dummyFct, to: realFct)
    let args = b.randomArguments(forCalling: realFct)
    b.eval("%PrepareFunctionForOptimization(%@)", with: [realFct]);
    b.callFunction(realFct, withArgs: args)
    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [realFct]);
    // Call the function.
    b.callFunction(realFct, withArgs: args)
}

public let WasmDeoptFuzzer = WasmProgramTemplate("WasmDeoptFuzzer") { b in
    b.buildPrefix()
    b.build(n: 10)

    let calleeSignature = b.randomWasmSignature()
    // The main function takes the table slot index as an argument to call to a different callee one
    // after the other.
    let mainSignatureBase = b.randomWasmSignature()
    let useTable64 = Bool.random()
    let mainSignature = [useTable64 ? .wasmi64 : .wasmi32] + mainSignatureBase.parameterTypes
        => mainSignatureBase.outputTypes
    let numCallees = Int.random(in: 2...5)

    // Emit a TypeGroup to increase the chance for interesting wasm-gc cases.
    b.wasmDefineTypeGroup() {
        b.build(n: 10)
    }

    let wasmModule = b.buildWasmModule { wasmModule in
        b.build(n: 10)
        // Emit the callees for the call_indirect
        let callees = (0..<numCallees).map { _ in
            wasmModule.addWasmFunction(with: calleeSignature) { function, label, args in
                b.build(n: 10)
                return calleeSignature.outputTypes.map(function.findOrGenerateWasmVar)
            }
        }

        let table = wasmModule.addTable(
            elementType: .wasmFuncRef,
            minSize: numCallees,
            definedEntries: (0..<numCallees).map {i in .init(indexInTable: i, signature: calleeSignature)},
            definedEntryValues: callees,
            isTable64: useTable64)

        wasmModule.addWasmFunction(with: mainSignature) { function, label, args in
            b.build(n: 10)
            let callArgs = calleeSignature.parameterTypes.map(function.findOrGenerateWasmVar)
            function.wasmCallIndirect(signature: calleeSignature, table: table, functionArgs: callArgs, tableIndex: args[0])
            b.build(n: 10)
            return mainSignature.outputTypes.map(function.findOrGenerateWasmVar)
        }
    }

    let exports = wasmModule.loadExports()
    let mainFctName = wasmModule.getExportedMethods().last!.0
    let mainFct = b.getProperty(mainFctName, of: exports)
    let mainSignatureJS = ProgramBuilder.convertWasmSignatureToJsSignature(mainSignature)
    for index in (0..<numCallees).shuffled() {
        var args = b.findOrGenerateArguments(forSignature: mainSignatureJS)
        args[0] = useTable64 ? b.loadBigInt(Int64(index)) : b.loadInt(Int64(index))
        b.callFunction(mainFct, withArgs: args)
        b.eval("%WasmTierUpFunction(%@)", with: [mainFct])
        b.callFunction(mainFct, withArgs: args)
    }
}

public let WasmTurbofanFuzzer = WasmProgramTemplate("WasmTurbofanFuzzer") { b in
    b.buildPrefix()
    b.build(n: 10)

    let wasmSignature = b.randomWasmSignature()

    // Emit a TypeGroup to increase the chance for interesting wasm-gc cases.
    b.wasmDefineTypeGroup() {
        b.build(n: 10)
    }

    let wasmModule = b.buildWasmModule { wasmModule in
        // Have some budget for tables, globals, memories, other functions that can be called, ...
        b.build(n: 30)

        // Add the function that we are going to call and optimize from JS.
        wasmModule.addWasmFunction(with: wasmSignature) { function, label, args in
            b.build(n: 20)
            return wasmSignature.outputTypes.map(function.findOrGenerateWasmVar)
        }
    }

    let exports = wasmModule.loadExports()
    let wasmFctName = wasmModule.getExportedMethods().last!.0
    let wasmFct = b.getProperty(wasmFctName, of: exports)
    let jsSignature = ProgramBuilder.convertWasmSignatureToJsSignature(wasmSignature)
    var args = b.findOrGenerateArguments(forSignature: jsSignature)
    b.callFunction(wasmFct, withArgs: args)
    // Force tier-up (Turbofan compilation).
    b.eval("%WasmTierUpFunction(%@)", with: [wasmFct])
    b.callFunction(wasmFct, withArgs: args)
}

public let jsD8 = ObjectGroup(name: "D8", instanceType: .jsD8, properties: ["test" : .jsD8Test], methods: [:])

public let jsD8Test = ObjectGroup(name: "D8Test", instanceType: .jsD8Test, properties: ["FastCAPI": .jsD8FastCAPIConstructor], methods: [:])

public let jsD8FastCAPI = ObjectGroup(name: "D8FastCAPI", instanceType: .jsD8FastCAPI, properties: [:],
        methods:["throw_no_fallback": [] => .integer,
                 "add_32bit_int": [.integer, .integer] => .integer
    ])

public let WasmFastCallFuzzer = WasmProgramTemplate("WasmFastCallFuzzer") { b in
    b.buildPrefix()
    b.build(n: 10)
    let target = fastCallables.randomElement()!
    let apiObj = b.findOrGenerateType(target.group)

    // Bind the API function so that it can be called from WebAssembly.
    let wrapped = b.bindMethod(target.method, on: apiObj)

    let functionSig = chooseUniform(from: b.methodSignatures(of: target.method, on: target.group))
    let wrappedSig = [.plain(b.type(of: apiObj))] + functionSig.parameters => functionSig.outputType

    let m = b.buildWasmModule { m in
        let allWasmTypes: WeightedList<ILType> = WeightedList([(.wasmi32, 1), (.wasmi64, 1), (.wasmf32, 1), (.wasmf64, 1), (.wasmExternRef, 1), (.wasmFuncRef, 1)])
        let wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(wrappedSig, availableTypes: allWasmTypes)
        m.addWasmFunction(with: wasmSignature) {fbuilder, _, _  in
            let args = b.randomWasmArguments(forWasmSignature: wasmSignature)
            if let args {
                let maybeRet = fbuilder.wasmJsCall(function: wrapped, withArgs: args, withWasmSignature: wasmSignature)
                if let ret = maybeRet {
                  return [ret]
                }
            } else {
                logger.error("Arguments should have been generated")
            }
            return wasmSignature.outputTypes.map(fbuilder.findOrGenerateWasmVar)
        }
    }

    let exports = m.loadExports()

    for (methodName, _) in m.getExportedMethods() {
        let exportedMethod = b.getProperty(methodName, of: exports)
        b.eval("%WasmTierUpFunction(%@)", with: [exportedMethod])
        let args = b.findOrGenerateArguments(forSignature: wrappedSig)
        b.callMethod(methodName, on: exports, withArgs: args)
    }
}

public let FastApiCallFuzzer = ProgramTemplate("FastApiCallFuzzer") { b in
    b.buildPrefix()
    b.build(n: 20)
    let parameterCount = probability(0.5) ? 0 : Int.random(in: 1...4)

    let f = b.buildPlainFunction(with: .parameters(n: parameterCount)) { args in
        b.build(n: 10)
        let target = fastCallables.randomElement()!
        let apiObj = b.findOrGenerateType(target.group)
        let functionSig = chooseUniform(from: b.methodSignatures(of: target.method, on: target.group))
        let apiCall = b.callMethod(target.method, on: apiObj, withArgs: b.findOrGenerateArguments(forSignature: functionSig), guard: true)
        b.doReturn(apiCall)
    }

    let args = b.randomJsVariables(n: Int.random(in: 0...5))
    b.callFunction(f, withArgs: args)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);

    b.callFunction(f, withArgs: args)
    b.callFunction(f, withArgs: args)

    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);

    b.callFunction(f, withArgs: args)

    b.build(n: 10)
}

// Configure V8 invocation arguments. `forSandbox` is used by the V8SandboxProfile. As the sandbox
// fuzzer does not crash on regular assertions, most validation flags do not make sense in that
// configuraiton.
public func v8ProcessArgs(randomize: Bool, forSandbox: Bool) -> [String] {
    var args = [
        "--expose-gc",
        "--expose-externalize-string",
        "--omit-quit",
        "--allow-natives-syntax",
        "--fuzzing",
        "--jit-fuzzing",
        "--future",
        "--harmony",
        "--experimental-fuzzing",
        "--js-staging",
        "--wasm-staging",
        "--wasm-fast-api",
        "--expose-fast-api",
        "--wasm-test-streaming", // WebAssembly.compileStreaming & WebAssembly.instantiateStreaming()
    ]

    guard randomize else { return args }

    //
    // Existing features that should sometimes be disabled.
    //
    if probability(0.1) {
        args.append("--no-turbofan")
        if probability(0.5) {
            args.append("--maglev-as-top-tier")
        }
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

    // Disabling Liftoff enables "direct" coverage for the optimizing compiler, though some
    // features (like speculative inlining) require a combination of Liftoff and Turbofan.
    // Note that this flag only affects WebAssembly.
    if probability(0.5) {
        args.append("--no-liftoff")
        if probability(0.3) && !forSandbox {
            args.append("--wasm-assert-types")
        }
    }

    // This greatly helps the fuzzer to decide inlining wasm functions into each other when
    // %WasmTierUpFunction() is used as in most cases the call counts will be way too low to
    // align with V8's current inlining heuristics (which uses absolute call counts as a
    // deciding factor).
    if probability(0.5) {
        args.append("--wasm-inlining-ignore-call-counts")
    }

    //
    // Future features that should sometimes be enabled.
    //
    if probability(0.1) {
        args.append("--minor-ms")
    }

    // Enable the shared heap.
    if probability(0.25) {
        // Either use the shared-string-table (needed for JS shared structs) or only allow
        // shared strings (needed for shared Wasm objects).
        args.append(Bool.random() ? "--shared-string-table" : "--shared-strings")
    }

    if probability(0.25) && !args.contains("--no-maglev") {
        args.append("--maglev-future")
    }

    if probability(0.2) && !args.contains("--no-maglev") {
        args.append("--maglev-non-eager-inlining")
        if probability(0.4) { // TODO: @tacet decrease this probability to max 0.2
            args.append("--max_maglev_inlined_bytecode_size_small=0")
        }
    }

    if probability(0.1) {
        args.append("--turboshaft-typed-optimizations")
    }

    if probability(0.5) {
        args.append("--turbolev")
        if probability(0.82) {
            args.append("--turbolev-future")
            if probability(0.3) { // TODO: @tacet change to 0.15
                args.append("--max_inlined_bytecode_size_small=0")
            }
        }
    }

    if probability(0.1) {
        args.append("--turboshaft-wasm-in-js-inlining")
    }

    if probability(0.1) {
        args.append("--harmony-struct")
    }

    if probability(0.1) {
        args.append("--efficiency-mode")
    }

    if probability(0.1) {
        args.append("--battery-saver-mode")
    }

    if probability(0.1) {
        args.append("--stress-scavenger-conservative-object-pinning-random")
    }

    if probability(0.1) {
        args.append("--precise-object-pinning")
    }

    if probability(0.1) {
        args.append("--scavenger-chaos-mode")
        let threshold = Int.random(in: 0...100)
        args.append("--scavenger-chaos-mode-threshold=\(threshold)")
    }

    if probability(0.1) {
        let stackSize = Int.random(in: 54...863)
        args.append("--stack-size=\(stackSize)")
    }

    // Temporarily enable the three flags below with high probability to
    // stress-test JSPI.
    // Lower the probabilities once we have enough coverage.
    if (probability(0.5)) {
        let stackSwitchingSize = Int.random(in: 1...300)
        args.append("--wasm-stack-switching-stack-size=\(stackSwitchingSize)")
    }
    if (probability(0.5)) {
        args.append("--experimental-wasm-growable-stacks")
    }
    if (probability(0.5)) {
        args.append("--stress-wasm-stack-switching")
    }

    if probability(0.5) {
        args.append("--proto-assign-seq-opt")
    }

    //
    // Sometimes enable additional verification/stressing logic (which may be fairly expensive).
    //
    if !forSandbox {
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
        if probability(0.2) {
            args.append("--turboshaft-verify-load-elimination")
        }
    }

    if probability(0.1) {
        args.append("--deopt-every-n-times=\(chooseUniform(from: [100, 250, 500, 1000, 2500, 5000, 10000]))")
    }
    if probability(0.1) {
        args.append("--stress-ic")
    }
    if probability(0.1) {
        args.append("--optimize-on-next-call-optimizes-to-maglev")
    }

    //
    // A gc-stress session with some fairly expensive flags.
    //
    if probability(0.1) {
        if probability(0.4) {
            args.append("--stress-marking=\(Int.random(in: 1...100))")
        }
        if probability(0.4) {
            args.append("--stress-scavenge=\(Int.random(in: 1...100))")
        }
        if probability(0.5) {
            args.append("--stress-flush-code")
            args.append("--flush-bytecode")
        }
        if probability(0.5) {
            args.append("--wasm-code-gc")
            args.append("--stress-wasm-code-gc")
        }
        if probability(0.4) {
            args.append(chooseUniform(
                from: ["--gc-interval=\(Int.random(in: 100...10000))",
                        "--random-gc-interval=\(Int.random(in: 1000...10000))"]))
        }
        if probability(0.4) {
            args.append("--concurrent-recompilation-queue-length=\(Int.random(in: 4...64))")
            args.append("--concurrent-recompilation-delay=\(Int.random(in: 1...500))")
        }
        if probability(0.6) {
            args.append(chooseUniform(
                from: ["--stress-compaction", "--stress-compaction-random"]))
        }
    }

    //
    // More exotic configuration changes.
    //
    if probability(0.05) {
        if probability(0.5) { args.append("--stress-gc-during-compilation") }
        if probability(0.5) { args.append("--lazy-new-space-shrinking") }
        if probability(0.5) { args.append("--stress-wasm-memory-moving") }
        if probability(0.5) { args.append("--stress-background-compile") }
        if probability(0.5) { args.append("--parallel-compile-tasks-for-lazy") }
        if probability(0.5) { args.append("--parallel-compile-tasks-for-eager-toplevel") }

        args.append(probability(0.5) ? "--always-sparkplug" : "--no-always-sparkplug")
        args.append(probability(0.5) ? "--always-osr" : "--no-always-osr")
        args.append(probability(0.5) ? "--concurrent-osr" : "--no-concurrent-osr")
        args.append(probability(0.5) ? "--force-slow-path" : "--no-force-slow-path")

        // Maglev related flags
        args.append(probability(0.5) ? "--maglev-inline-api-calls" : "--no-maglev-inline-api-calls")

        // Compiler related flags
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

    return args
}
