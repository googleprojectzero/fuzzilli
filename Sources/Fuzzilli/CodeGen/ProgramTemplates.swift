// Copyright 2020 Google LLC
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


/// Builtin program templates to target specific types of bugs.
public let ProgramTemplates = [
    ProgramTemplate("Codegen100") { b in
        b.buildPrefix()
        // Go wild.
        b.build(n: 100)
    },

    ProgramTemplate("Codegen50") { b in
        b.buildPrefix()
        // Go (a little less) wild.
        b.build(n: 50)
    },

    WasmProgramTemplate("WasmCodegen50") { b in
        b.buildPrefix()
        let m = b.buildWasmModule() { _ in
            b.build(n: 50)
        }
        b.build(n: 10)

        let exports = m.loadExports()

        b.build(n: 20)
    },

    WasmProgramTemplate("WasmCodegen100") { b in
        b.buildPrefix()
        let m = b.buildWasmModule() { _ in
            b.build(n: 100)
        }
        b.build(n: 10)

        let exports = m.loadExports()

        b.build(n: 20)
    },

    WasmProgramTemplate("MixedJsAndWasm1") { b in
        b.buildPrefix()
        b.build(n: 10)
        let m = b.buildWasmModule() { _ in
            b.build(n:30)
        }
        b.build(n: 20)

        let exports = m.loadExports()

        b.build(n: 20)
    },

    WasmProgramTemplate("MixedJsAndWasm2") { b in
        b.buildPrefix()
        b.build(n: 10)
        b.buildWasmModule() { _ in
            b.build(n: 20)
        }
        b.build(n: 10)
        let m = b.buildWasmModule() { _ in
            b.build(n: 20)
        }
        b.build(n: 20)

        let exports = m.loadExports()

        b.build(n: 20)
    },

    WasmProgramTemplate("JSPI") { b in
        b.buildPrefix()
        b.build(n: 20)

        var f: Variable? = nil

        withEqualProbability({
            f = b.buildAsyncFunction(with: b.randomParameters()) { _ in
                b.build(n: Int.random(in: 5...20))
            }
        }, {
            f = b.buildPlainFunction(with: b.randomParameters()) { _ in
                b.build(n: Int.random(in: 5...20))
            }
        })

        let signature = b.type(of: f!).signature ?? Signature.forUnknownFunction
        // As we do not yet know what types we have in the Wasm module when we try to call this, let Fuzzilli know that it could potentially use all Wasm types here.

])

        var wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(signature, availableTypes: allWasmTypes)
        let wrapped = b.wrapSuspending(function: f!)

        let m = b.buildWasmModule { mod in


]) { fbuilder, _, _  in
                // This will create a bunch of locals, which should create large (>4KB) frames.
                if probability(0.02) {
                    for _ in 0..<1000 {
                        fbuilder.consti64(b.randomInt())
                    }
                }
                b.build(n: 20)
                let args = b.randomWasmArguments(forWasmSignature: wasmSignature)
                // Best effort call...
                // TODO: Extend findOrGenerateArguments to work in Wasm as well.
                if let args {
                    fbuilder.wasmJsCall(function: wrapped, withArgs: args, withWasmSignature: wasmSignature)
                }
                b.build(n: 4)

]
            }
            if probability(0.2) {
                b.build(n: 20)
            }
        }

        var exportedMethod = b.getProperty(m.getExportedMethod(at: 0), of: m.loadExports())

        if probability(0.9) {
            exportedMethod = b.wrapPromising(function: exportedMethod)
        }

        b.build(n: 10)

        b.callFunction(exportedMethod, withArgs: b.randomArguments(forCallingFunctionWithSignature: signature))

        b.build(n: 5)
    },

    WasmProgramTemplate("ThrowInWasmCatchInJS") { b in
        b.buildPrefix()
        b.build(n: 10)

        // A few tags (wasm exception kinds) to be used later on.
        let wasmTags = (0...Int.random(in: 0..<5)).map { _ in
            b.createWasmTag(parameterTypes: b.randomTagParameters())
        }

] + wasmTags
        let tagToThrow = chooseUniform(from: wasmTags)
        let throwParamTypes = b.type(of: tagToThrow).wasmTagType!.parameters
        let tagToCatchForRethrow = chooseUniform(from: tags)

]

        let module = b.buildWasmModule { wasmModule in
            // Wasm function that throws a tag, catches a tag (the same or a different one) to
            // rethrow it again (or another exnref if present).


]) { function, label, args in
                b.build(n: 10)


]) { catchRefLabel, _ in
                    // TODO(mliedtke): We should probably allow mutations of try_tables to make
                    // these cases more generic. This would probably require being able to wrap
                    // things in a new block (so we can insert a target destination for a new catch
                    // with a matching signature) or to at least create a new tag for an existing
                    // block target. Either way, this is non-trivial.




]) { _, _ in
                        b.build(n: 10)
                        function.WasmBuildThrow(tag: tagToThrow, inputs: throwParamTypes.map(function.findOrGenerateWasmVar))

]
                    }
                    return catchBlockOutputTypes.map(function.findOrGenerateWasmVar)
                }
                b.build(n: 10)
                function.wasmBuildThrowRef(exception: b.randomVariable(ofType: .wasmExnRef)!)

]
            }
        }

        let exports = module.loadExports()
        b.buildTryCatchFinally {
            b.build(n: 10)
            // Call the exported wasm function.

])
            b.build(n: 5)
        } catchBody: { exception in
            // Do something, potentially using the `exception` thrown by wasm.
            b.build(n: 20)
        }
        b.build(n: 5)
    },

    WasmProgramTemplate("WasmReturnCalls") { b in
        b.buildPrefix()
        b.build(n: 10)

        let calleeSig = b.randomWasmSignature()
        let mainSig = b.randomWasmSignature().parameterTypes => calleeSig.outputTypes
        let useTable64 = Bool.random()
        let numCallees = Int.random(in: 1...5)

        let module = b.buildWasmModule { wasmModule in
            let callees = (0..<numCallees).map {_ in wasmModule.addWasmFunction(with: calleeSig) { function, label, params in
                b.build(n: 10)
                return calleeSig.outputTypes.map(function.findOrGenerateWasmVar)
            }}

            let table = wasmModule.addTable(elementType: .wasmFuncRef,
                                            minSize: 10,
                                            definedEntries: callees.enumerated().map { (index, callee) in
                                                .init(indexInTable: index, signature: calleeSig)
                                            },
                                            definedEntryValues: callees,
                                            isTable64: useTable64)

            let main = wasmModule.addWasmFunction(with: mainSig) { function, label, params in
                b.build(n:20)
                if let arguments = b.randomWasmArguments(forWasmSignature: calleeSig) {
                    if Bool.random() {
                        function.wasmReturnCallDirect(signature: calleeSig, function: callees.randomElement()!, functionArgs: arguments)
                    } else {
                        let calleeIndex = useTable64
                            ? function.consti64(Int64(Int.random(in: 0..<callees.count)))
                            : function.consti32(Int32(Int.random(in: 0..<callees.count)))
                        function.wasmReturnCallIndirect(signature: calleeSig, table: table, functionArgs: arguments, tableIndex: calleeIndex)
                    }
                }
                return mainSig.outputTypes.map(function.findOrGenerateWasmVar)
            }
        }

        let exports = module.loadExports()
        let args = b.randomArguments(forCallingFunctionWithSignature:
            ProgramBuilder.convertWasmSignatureToJsSignature(mainSig))
        b.callMethod(module.getExportedMethod(at: numCallees), on: exports, withArgs: args)
    },

    ProgramTemplate("JIT1Function") { b in
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 30)
            b.doReturn(b.randomJsVariable())
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    ProgramTemplate("JIT2Functions") { b in
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f1 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
            b.doReturn(b.randomJsVariable())
        }

        // Generate a second larger function
        let f2 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
            b.doReturn(b.randomJsVariable())
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT for first function
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // trigger JIT for second function
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // maybe trigger recompilation
        b.buildRepeatLoop(n: numIterations) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
    },

    ProgramTemplate("JITTrickyFunction") { b in
        // This templates generates functions that behave differently in some of the iterations.
        // The functions will essentially look like this:
        //
        //     function f(arg1, arg2, i) {
        //         if (i == N) {
        //             // do stuff
        //         }
        //         // do stuff
        //     }
        //
        // Or like this:
        //
        //     function f(arg1, arg2, i) {
        //         if (i % N == 0) {
        //             // do stuff
        //         }
        //         // do stuff
        //     }
        //
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Helper function to generate code that only runs during some of the iterations.
        func buildCodeThatRunsInOnlySomeIterations(iterationCount: Variable) {
            // Decide when to run the code.
            let cond: Variable
            if probability(0.5) {
                // Run the code in one specific iteration
                let selectedIteration = withEqualProbability({
                    // Prefer to perform the action during one of the last iterations
                    assert(numIterations > 10)
                    return Int.random(in: (numIterations - 10)..<numIterations)
                }, {
                    return Int.random(in: 0..<numIterations)
                })
                cond = b.compare(iterationCount, with: b.loadInt(Int64(selectedIteration)), using: .equal)
            } else {
                // Run the code every nth iteration
                let modulus = b.loadInt(chooseUniform(from: [2, 5, 10, 25]))
                let remainder = b.binary(iterationCount, modulus, with: .Mod)
                cond = b.compare(remainder, with: b.loadInt(0), using: .equal)
            }

            // We hide the cond variable since it's probably not very useful for subsequent code to use it.
            // The other variables (e.g. remainder) are maybe a bit more useful, so we leave them visible.
            b.hide(cond)

            // Now build the code, wrapped in an if block.
            b.buildIf(cond) {
                b.build(n: 5)
            }
        }

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate the target function.
        // Here we simply prepend the iteration count to randomly generated parameters.
        // This way, the signature is still valid even if the last parameter is a rest parameter.
        let baseParams = b.randomParameters().parameterTypes
        let actualParams = [.integer] + baseParams
        let f = b.buildPlainFunction(with: .parameters(actualParams)) { args in
            // Generate a few "prefix" instructions
            b.build(n: smallCodeBlockSize)

            // Build code that will only be executed in some of the iterations.
            buildCodeThatRunsInOnlySomeIterations(iterationCount: args[0])

            // Build the main body.
            b.build(n: 20)
            b.doReturn(b.randomJsVariable())
        }

        // Generate some more random instructions.
        b.build(n: smallCodeBlockSize)

        // Call the function repeatedly to trigger JIT compilation, then perform additional steps in the final iteration. Do this 2 times to potentially trigger recompilation.
        b.buildRepeatLoop(n: 2) {
            b.buildRepeatLoop(n: numIterations) { i in
                buildCodeThatRunsInOnlySomeIterations(iterationCount: i)
                var args = [i] + b.randomArguments(forCallingFunctionWithParameters: baseParams)
                b.callFunction(f, withArgs: args)
            }
        }

        // Call the function again, this time with potentially different arguments.
        b.buildRepeatLoop(n: numIterations) { i in
            buildCodeThatRunsInOnlySomeIterations(iterationCount: i)
            var args = [i] + b.randomArguments(forCallingFunctionWithParameters: baseParams)
            b.callFunction(f, withArgs: args)
        }
    },

    ProgramTemplate("JSONFuzzer") { b in
        b.buildPrefix()

        // Create some random values that will be JSON.stringified below.
        b.build(n: 25)

        // Generate random JSON payloads by stringifying random values
        let JSON = b.createNamedVariable(forBuiltin: "JSON")
        var jsonPayloads = [Variable]()
        for _ in 0..<Int.random(in: 1...5) {
            let json = b.callMethod("stringify", on: JSON, withArgs: [b.randomJsVariable()])
            jsonPayloads.append(json)
        }

        // Optionally mutate (some of) the json string
        let mutateJson = b.buildPlainFunction(with: .parameters(.string)) { args in
            let json = args[0]

            // Helper function to pick a random index in the json string.
            let randIndex = b.buildPlainFunction(with: .parameters(.integer)) { args in
                let max = args[0]
                let Math = b.createNamedVariable(forBuiltin: "Math")
                // We "hardcode" the random value here (instead of calling `Math.random()` in JS) so that testcases behave deterministically.
                var random = b.loadFloat(Double.random(in: 0..<1))
                random = b.binary(random, max, with: .Mul)
                random = b.callMethod("floor", on: Math, withArgs: [random])
                b.doReturn(random)
            }

            // Flip a random character of the JSON string:
            // Select a random index at which to flip the character.
            let String = b.createNamedVariable(forBuiltin: "String")
            let length = b.getProperty("length", of: json)
            let index = b.callFunction(randIndex, withArgs: [length])

            // Save the substrings before and after the character that will be changed.
            let zero = b.loadInt(0)
            let prefix = b.callMethod("substring", on: json, withArgs: [zero, index])
            let indexPlusOne = b.binary(index, b.loadInt(1), with: .Add)
            let suffix = b.callMethod("substring", on: json, withArgs: [indexPlusOne])

            // Extract the original char code, xor it with a random 7-bit number, then construct the new character value.
            let originalCharCode = b.callMethod("charCodeAt", on: json, withArgs: [index])
            let newCharCode = b.binary(originalCharCode, b.loadInt(Int64.random(in: 1..<128)), with: .Xor)
            let newChar = b.callMethod("fromCharCode", on: String, withArgs: [newCharCode])

            // And finally construct the mutated string.
            let tmp = b.binary(prefix, newChar, with: .Add)
            let newJson = b.binary(tmp, suffix, with: .Add)
            b.doReturn(newJson)
        }

        for (i, json) in jsonPayloads.enumerated() {
            // Performing (essentially binary) mutations on the JSON content will mostly end up fuzzing the JSON parser, not the JSON object
            // building logic (which, in optimized JS engines, is likely much more complex). So perform these mutations somewhat rarely.
            guard probability(0.25) else { continue }
            jsonPayloads[i] = b.callFunction(mutateJson, withArgs: [json])
        }

        // Parse the JSON payloads back into JS objects.
        // Instead of shuffling the jsonString array, we generate random indices so that there is a chance that the same string is parsed multiple times.
        for _ in 0..<(jsonPayloads.count * 2) {
            let json = chooseUniform(from: jsonPayloads)
            // Parsing will throw if the input is invalid, so add guards
            b.callMethod("parse", on: JSON, withArgs: [json], guard: true)
        }

        // Generate some more random code to (hopefully) use the parsed JSON in some interesting way.
        b.build(n: 25)
    },



    b.buildPrefix()

    // Load constructors and helpers
    let Int32Array = b.createNamedVariable(forBuiltin: "Int32Array")
    let Float64Array = b.createNamedVariable(forBuiltin: "Float64Array")
    let Uint8Array = b.createNamedVariable(forBuiltin: "Uint8Array")
    let Uint16Array = b.createNamedVariable(forBuiltin: "Uint16Array")
    let ArrayBuffer = b.createNamedVariable(forBuiltin: "ArrayBuffer")
    let ArrayCtor = b.createNamedVariable(forBuiltin: "Array")
    let ObjectCtor = b.createNamedVariable(forBuiltin: "Object")
    let print = b.createNamedVariable(forBuiltin: "print")

    // Typed arrays
    let t1 = b.construct(Int32Array, withArgs: [b.loadInt(64)])
    let t2 = b.construct(Float64Array, withArgs: [b.loadInt(64)])
    let t3 = b.construct(Uint8Array, withArgs: [b.loadInt(64)])

    // Optional RAB/GSAB: create resizable ArrayBuffer and a Uint16Array view, tolerate lack of support
    var t4: Variable? = nil
    var rab: Variable? = nil
    b.buildTryCatchFinally {
        let options = b.createObject(with: [
            "maxByteLength": b.loadInt(512),
            "resizable": b.loadBool(true)
        ])
        rab = b.construct(ArrayBuffer, withArgs: [b.loadInt(256), options])
        t4 = b.construct(Uint16Array, withArgs: [rab!, b.loadInt(0), b.loadInt(64)])
    } catchBody: { _ in }

    // Hot function f(ta, i, v): keyed store, named .length/.byteLength/.byteOffset loads, then keyed read with varied index
    let f = b.buildPlainFunction(with: .parameters([.jsAnything, .jsAnything, .jsAnything])) { args in
        let ta = args[0]
        let i = args[1]
        let v = args[2]

        // Store ta[i] = v
        b.setElement(i, of: ta, to: v)

        // Named loads
        let L = b.getProperty("length", of: ta)
        let bl = b.getProperty("byteLength", of: ta)
        let bo = b.getProperty("byteOffset", of: ta)

        // Candidate indices: c = (L % 4) selects among {0, L-1, L, i}
        let zero = b.loadInt(0)
        let four = b.loadInt(4)
        let Lm1 = b.binary(L, b.loadInt(1), with: .Sub)
        let c = b.binary(L, four, with: .Mod)
        let is0 = b.compare(c, with: b.loadInt(0), using: .equal)
        let is1 = b.compare(c, with: b.loadInt(1), using: .equal)
        let is2 = b.compare(c, with: b.loadInt(2), using: .equal)
        let is3 = b.compare(c, with: b.loadInt(3), using: .equal)
        var i2 = zero
        b.buildIf(is0) { i2 = zero }
        b.buildIf(is1) { i2 = Lm1 }
        b.buildIf(is2) { i2 = L }
        b.buildIf(is3) { i2 = i }

        // Keyed load: ta[i2]
        let read = b.getElement(i2, of: ta)

        // Consume byteLength/byteOffset to avoid DCE and keep named path alive
        let sum = b.binary(bl, bo, with: .Add)
        b.callFunction(print, withArgs: [sum])

        // Coerce to int32 with bitwise OR 0
        let xi32 = b.binary(read, b.loadInt(0), with: .BitOr)

        // Return array-like via new Array(xi32, L)
        let ret = b.construct(ArrayCtor, withArgs: [xi32, L])
        b.doReturn(ret)
    }

    // Phase 1: Warmup monomorphic on t1
    let L1 = b.getProperty("length", of: t1)
    b.buildRepeatLoop(n: 6000) { it in
        let idx = b.binary(it, L1, with: .Mod)
        var val = b.binary(it, b.loadInt(3), with: .Mod)
        val = b.binary(val, b.loadInt(1), with: .Add)
        b.callFunction(f, withArgs: [t1, idx, val])
    }

    // Boundary indices to trigger deopts
    let Lm1_t1 = b.binary(L1, b.loadInt(1), with: .Sub)
    b.callFunction(f, withArgs: [t1, Lm1_t1, b.loadInt(1)])
    b.callFunction(f, withArgs: [t1, L1, b.loadInt(1)])
    b.callFunction(f, withArgs: [t1, b.loadInt(-1), b.loadInt(1)])

    // Phase 2: Morph feedback with Float64Array and Uint8Array
    let L2 = b.getProperty("length", of: t2)
    b.buildRepeatLoop(n: 256) { it in
        let idx = b.binary(it, L2, with: .Mod)
        let itMod2 = b.binary(it, b.loadInt(2), with: .Mod)
        let isEven = b.compare(itMod2, with: b.loadInt(0), using: .equal)
        var val2 = b.loadFloat(Double.nan)
        b.buildIf(isEven) { val2 = b.loadFloat(Double.infinity) }
        b.callFunction(f, withArgs: [t2, idx, val2])
    }

    let L3 = b.getProperty("length", of: t3)
    b.buildRepeatLoop(n: 256) { it in
        let idx = b.binary(it, L3, with: .Mod)
        let m4 = b.binary(it, b.loadInt(4), with: .Mod)
        let is0 = b.compare(m4, with: b.loadInt(0), using: .equal)
        let is1 = b.compare(m4, with: b.loadInt(1), using: .equal)
        let is2 = b.compare(m4, with: b.loadInt(2), using: .equal)
        var val3 = b.loadFloat(Double.nan)
        b.buildIf(is0) { val3 = b.loadFloat(1.5) }
        b.buildIf(is1) { val3 = b.loadFloat(-0.0) }
        b.buildIf(is2) { val3 = b.loadFloat(1099511627776.0) }
        b.callFunction(f, withArgs: [t3, idx, val3])
    }

    // Megamorphic fallback: pass a non-typed receiver a few times, in try/catch to be safe
    b.buildTryCatchFinally {
        let o = b.construct(ObjectCtor, withArgs: [])
        b.callFunction(f, withArgs: [o, b.loadInt(0), b.loadInt(1)])
        b.callFunction(f, withArgs: [o, b.loadInt(1), b.loadInt(2)])
        b.callFunction(f, withArgs: [o, b.loadInt(2), b.loadInt(3)])
    } catchBody: { _ in }

    // Prototype/own-property perturbation; tolerate failure
    let s = b.construct(Uint8Array, withArgs: [b.loadInt(32)])
    b.buildTryCatchFinally {
        let getter = b.buildPlainFunction(with: .parameters([])) { _ in
            b.doReturn(b.loadInt(7))
        }
        let desc = b.createObject(with: ["get": getter])
        let Obj = b.createNamedVariable(forBuiltin: "Object")
        b.callMethod("defineProperty", on: Obj, withArgs: [s, b.loadString("length"), desc])
    } catchBody: { _ in }
    b.callFunction(f, withArgs: [s, b.loadInt(0), b.loadInt(1)])
    let sLen = b.getProperty("length", of: s)
    b.callFunction(print, withArgs: [sLen])

    // Optional RAB/GSAB path usage
    if let t4var = t4, let rabvar = rab {
        let L4 = b.getProperty("length", of: t4var)
        let L4m1 = b.binary(L4, b.loadInt(1), with: .Sub)
        b.callFunction(f, withArgs: [t4var, L4m1, b.loadInt(1)])
        b.callFunction(f, withArgs: [t4var, L4, b.loadInt(1)])
        b.buildTryCatchFinally {
            b.callMethod("resize", on: rabvar, withArgs: [b.loadInt(512)])
        } catchBody: { _ in }
        let L4b = b.getProperty("length", of: t4var)
        let L4b_m1 = b.binary(L4b, b.loadInt(1), with: .Sub)
        b.callFunction(f, withArgs: [t4var, L4b_m1, b.loadInt(1)])
    }

    // Extra store coercion stress on integer typed arrays
    b.callFunction(f, withArgs: [t1, b.loadInt(1), b.loadFloat(1.5)])
    b.callFunction(f, withArgs: [t1, b.loadInt(2), b.loadFloat(-0.0)])
    b.callFunction(f, withArgs: [t1, b.loadInt(3), b.loadFloat(1099511627776.0)])
    b.callFunction(f, withArgs: [t3, b.loadInt(1), b.loadFloat(1.5)])
    b.callFunction(f, withArgs: [t3, b.loadInt(2), b.loadFloat(-0.0)])
    b.callFunction(f, withArgs: [t3, b.loadInt(3), b.loadFloat(Double.nan)])
},
]