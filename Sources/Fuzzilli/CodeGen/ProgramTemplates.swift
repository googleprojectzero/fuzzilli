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

    
        let allWasmTypes: WeightedList<ILType> = WeightedList([(.wasmi32, 1), (.wasmi64, 1), (.wasmf32, 1), (.wasmf64, 1), (.wasmExternRef, 1), (.wasmFuncRef, 1)




])

        var wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(signature, availableTypes: allWasmTypes)
        let wrapped = b.wrapSuspending(function: f!)

        let m = b.buildWasmModule { mod in

    
            mod.addWasmFunction(with: [




] => [




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

    
                return [




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

    
        let tags = [b.createWasmJSTag()




] + wasmTags
        let tagToThrow = chooseUniform(from: wasmTags)
        let throwParamTypes = b.type(of: tagToThrow).wasmTagType!.parameters
        let tagToCatchForRethrow = chooseUniform(from: tags)

    
        let catchBlockOutputTypes = b.type(of: tagToCatchForRethrow).wasmTagType!.parameters + [.wasmExnRef




]

        let module = b.buildWasmModule { wasmModule in
            // Wasm function that throws a tag, catches a tag (the same or a different one) to
            // rethrow it again (or another exnref if present).

    
            wasmModule.addWasmFunction(with: [




] => [



]) { function, label, args in
                b.build(n: 10)

    
                let caughtValues = function.wasmBuildBlockWithResults(with: [



] => catchBlockOutputTypes, args: [



]) { catchRefLabel, _ in
                    // TODO(mliedtke): We should probably allow mutations of try_tables to make
                    // these cases more generic. This would probably require being able to wrap
                    // things in a new block (so we can insert a target destination for a new catch
                    // with a matching signature) or to at least create a new tag for an existing
                    // block target. Either way, this is non-trivial.

    
                    function.wasmBuildTryTable(with: [


] => [


], args: [tagToCatchForRethrow, catchRefLabel


], catches: [.Ref


]) { _, _ in
                        b.build(n: 10)
                        function.WasmBuildThrow(tag: tagToThrow, inputs: throwParamTypes.map(function.findOrGenerateWasmVar))

    
                        return [

]
                    }
                    return catchBlockOutputTypes.map(function.findOrGenerateWasmVar)
                }
                b.build(n: 10)
                function.wasmBuildThrowRef(exception: b.randomVariable(ofType: .wasmExnRef)!)

    
                return [

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


    ProgramTemplate("MaglevClosureEscapeNumericField") { b in
        // Keep generation bounded and deterministic
        b.buildPrefix()
        b.build(n: 10)

        // Object with numeric-string properties to avoid implicit array element semantics
        let zero = b.loadInt(0)
        let one  = b.loadInt(1)
let obj  = b.createObject(with: ["p0": zero, "p1": one])

        // Holder for escaping closure
        let holder = b.createObject(with: [:])

        // Outer function that creates and leaks a closure capturing `obj`
        let makeClosure = b.buildPlainFunction(with: .parameters()) { _ in
            // Closure that reads and bumps obj["0"]
            let inner = b.buildPlainFunction(with: .parameters()) { _ in
let cur = b.getProperty("p0", of: obj, guard: true)
                let inc = b.loadInt(1)
                let nxt = b.binary(cur, inc, with: .Add)
b.setProperty("p0", of: obj, to: nxt, guard: true)
                b.doReturn(nxt)
            }
            // Leak closure by storing it on a reachable object
            b.setProperty("leaked", of: holder, to: inner)
            b.doReturn(inner)
        }

        // Instantiate and leak the closure
        let _ = b.callFunction(makeClosure, withArgs: [], guard: true)

        // Bounded warmup loop to exercise Maglev closure escape/optimization
        b.buildRepeatLoop(n: 32) { _ in
            let c = b.getProperty("leaked", of: holder, guard: true)
            _ = b.callFunction(c, withArgs: [], guard: true)
        }

        // Mix in a small random tail
        b.build(n: 5)
    }

    ,
    ProgramTemplate("KeyedStore_ElementsTransition_Stress") { b in
        // Global knobs (bounded randomness to stress tiering while staying performant)
        let warmIters = Int.random(in: 8000...12000)
        let appendCount = Int.random(in: 256...1024)
        let bigIndexSparse = Int.random(in: 65536...131072)
        let cowSliceLen = Int.random(in: 64...256)

        // Seed program and values
        b.buildPrefix()
        b.build(n: 10)

        // Helper: maybeGC (no-op, portable)
        let maybeGC = b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            b.doReturn(b.loadUndefined())
        }

        // Common builtins/objects
        let ArrayCtor = b.createNamedVariable(forBuiltin: "Array")
        let ObjectCtor = b.createNamedVariable(forBuiltin: "Object")
        let MathObj   = b.createNamedVariable(forBuiltin: "Math")
        let ReflectObj = b.createNamedVariable(forBuiltin: "Reflect")
        let Uint8ArrayCtor = b.createNamedVariable(forBuiltin: "Uint8Array")

        // Part A setup: array `a` (start PACKED_SMI), create holes by writing at a high index.
        var a = b.createArray(with: [b.loadInt(1), b.loadInt(2), b.loadInt(3)])
        b.setElement(10, of: a, to: b.loadInt(9))  // grow with holes => HOLEY

        // f1: SMI → DOUBLE → OBJECT transitions via phased stores into a[0]
        let f1 = b.buildPlainFunction(with: .parameters(.object(), .jsAnything)) { args in
            let arr = args[0]
            let smiVal = b.loadInt(1)
            let dblVal = b.loadFloat(1.5)
            let objVal = MathObj  // any object
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                let t1 = b.compare(i, with: b.loadInt(Int64(warmIters/3)), using: .lessThan)
                b.buildIfElse(t1) {
                    b.setElement(0, of: arr, to: smiVal)
                } elseBody: {
                    let t2 = b.compare(i, with: b.loadInt(Int64(2*warmIters/3)), using: .lessThan)
                    b.buildIfElse(t2) {
                        b.setElement(0, of: arr, to: dblVal)  // transition SMI→DOUBLE
                    } elseBody: {
                        b.setElement(0, of: arr, to: objVal)  // transition DOUBLE→OBJECT
                    }
                }
                _ = b.getElement(0, of: arr)
                // Rare no-op GC call to create phase boundaries without affecting portability
                let mod = b.binary(i, b.loadInt(1024), with: .Mod)
                let cond = b.compare(mod, with: b.loadInt(0), using: .equal)
                b.buildIf(cond) {
                    _ = b.callFunction(maybeGC, withArgs: [])
                }
            }
            b.doReturn(arr)
        }

        // Part B: HOLEY_DOUBLE with NaN holes, then transition to OBJECT
        let zeroF = b.loadFloat(0.0)
        let nanVal = b.binary(zeroF, zeroF, with: .Div)  // 0.0 / 0.0 => NaN
        var bArr = b.createArray(with: [])
        b.setElement(0, of: bArr, to: b.loadFloat(1.1))
        b.setElement(2, of: bArr, to: nanVal)
        b.setElement(5, of: bArr, to: b.loadFloat(3.3))

        let f2 = b.buildPlainFunction(with: .parameters(.object(), .integer)) { args in
            let arr = args[0]
            let idx = args[1]
            let dbl = b.loadFloat(4.4)
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                let before = b.compare(i, with: b.loadInt(Int64(3*warmIters/4)), using: .lessThan)
                b.buildIfElse(before) {
                    b.setComputedProperty(idx, of: arr, to: dbl)   // stay DOUBLE
                } elseBody: {
                    b.setComputedProperty(idx, of: arr, to: MathObj)  // transition DOUBLE→OBJECT on HOLEY
                }
                _ = b.getComputedProperty(idx, of: arr)
            }
            b.doReturn(arr)
        }

        // Part C: Capacity growth + COW via slice
        let cLen = b.loadInt(Int64(cowSliceLen))
        let cArr = b.construct(ArrayCtor, withArgs: [cLen])
        _ = b.callMethod("fill", on: cArr, withArgs: [b.loadInt(1)])  // PACKED_SMI
        let dArr = b.callMethod("slice", on: cArr, withArgs: [b.loadInt(0)])  // COW backing store

        let f3 = b.buildPlainFunction(with: .parameters(.object(), .integer)) { args in
            let t = args[0]
            let _ = args[1]  // n (unused, kept for signature richness)
            b.buildRepeatLoop(n: appendCount) { j in
                b.setComputedProperty(j, of: t, to: j)
                _ = b.getComputedProperty(j, of: t)
            }
            b.doReturn(t)
        }

        // Part D: Packed→Holey flip and sparse write to force handler update/deopt
        let f4 = b.buildPlainFunction(with: .parameters(.object())) { args in
            let arr = args[0]
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                // Densely update index 1 for packed feedback
                b.setElement(1, of: arr, to: i)
                // Flip near end to HOLEY by deleting index 1 and perform a large sparse write
                let trigger = b.compare(i, with: b.loadInt(Int64(warmIters - 1)), using: .equal)
                b.buildIf(trigger) {
                    _ = b.callMethod("deleteProperty", on: ReflectObj, withArgs: [arr, b.loadString("1")])
                    b.setElement(Int64(bigIndexSparse), of: arr, to: b.loadInt(7))
                }
            }
            b.doReturn(arr)
        }

        // Part E: Integrity levels and non-extensible arrays
        let f5 = b.buildPlainFunction(with: .parameters(.object())) { args in
            let z = args[0]
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                b.setElement(0, of: z, to: i)
                let trigger = b.compare(i, with: b.loadInt(Int64(warmIters - 2)), using: .equal)
                b.buildIf(trigger) {
                    _ = b.callMethod("preventExtensions", on: ObjectCtor, withArgs: [z])
                }
            }
            // Post preventExtensions: in-bounds and append attempts
            b.setElement(1, of: z, to: b.loadInt(99))
            b.setElement(100, of: z, to: b.loadInt(42))
            _ = b.getProperty("length", of: z)
            b.doReturn(z)
        }

        // Part F: TypedArray OOB ignore semantics + polymorphism with normal arrays
        let ta = b.construct(Uint8ArrayCtor, withArgs: [b.loadInt(64)])
        let f6 = b.buildPlainFunction(with: .parameters(.object())) { args in
            let tarr = args[0]
            let L = b.getProperty("length", of: tarr)
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                let before = b.compare(i, with: b.loadInt(Int64(warmIters - 8)), using: .lessThan)
                b.buildIfElse(before) {
                    let idx = b.binary(i, b.loadInt(63), with: .Mod)
                    b.setComputedProperty(idx, of: tarr, to: b.loadInt(255))
                } elseBody: {
                    let big = b.binary(L, b.loadInt(1024), with: .Add)
                    b.setComputedProperty(big, of: tarr, to: b.loadInt(1))  // OOB for TAs, ignored
                }
            }
            b.doReturn(tarr)
        }

        // Part G: Prototype validity cell invalidation
        let proto = b.getProperty("prototype", of: ArrayCtor)
        let f7 = b.buildPlainFunction(with: .parameters(.object())) { args in
            let arr = args[0]
            b.buildRepeatLoop(n: Int(warmIters)) { i in
                b.setElement(0, of: arr, to: i)
                let t1 = b.compare(i, with: b.loadInt(Int64(warmIters/2)), using: .equal)
                b.buildIf(t1) {
                    b.setComputedProperty(b.loadString("0"), of: proto, to: b.loadInt(123))
                }
                let t2 = b.compare(i, with: b.loadInt(Int64(warmIters - 1)), using: .equal)
                b.buildIf(t2) {
                    _ = b.callMethod("deleteProperty", on: ReflectObj, withArgs: [proto, b.loadString("0")])
                }
            }
            b.doReturn(arr)
        }

        // Orchestration & sequencing
        // f1: transition pipeline
        _ = b.callFunction(f1, withArgs: [a, b.loadInt(1)])

        // f2: HOLEY_DOUBLE to OBJECT on chosen index
        _ = b.callFunction(f2, withArgs: [bArr, b.loadInt(2)])

        // f3: growth on c, then EnsureWritable+COW split on d
        let cOut = b.callFunction(f3, withArgs: [cArr, b.loadInt(Int64(appendCount))])
        let dOut = b.callFunction(f3, withArgs: [dArr, b.loadInt(Int64(appendCount))])
        // Alternate writes to test aliasing absence
        b.setElement(0, of: cArr, to: b.loadInt(101))
        b.setElement(0, of: dArr, to: b.loadInt(202))
        _ = cOut; _ = dOut

        // f4: packed→holey and sparse write
        let eArr = b.createArray(with: [b.loadInt(0), b.loadInt(0), b.loadInt(0)])
        _ = b.callFunction(f4, withArgs: [eArr])

        // f5: integrity levels after warmup
        let zArr = b.createArray(with: [b.loadInt(0), b.loadInt(0)])
        _ = b.callFunction(f5, withArgs: [zArr])

        // f6: typed array first, then normal JS array for polymorphism
        _ = b.callFunction(f6, withArgs: [ta])
        _ = b.callFunction(f6, withArgs: [a])

        // f7: prototype validity invalidation
        _ = b.callFunction(f7, withArgs: [a])

        // Verification reads to keep values live
        _ = b.getElement(0, of: a)
        _ = b.getElement(2, of: bArr)
        _ = b.getProperty("length", of: cArr)
        _ = b.getProperty("length", of: dArr)
        _ = b.getProperty("length", of: zArr)
        _ = b.getProperty("length", of: eArr)
}ProgramTemplate("MaglevDeopt_HoleyDoubleArray_Materialization_A") { b in
    // 1) Define function f(o, flagBool)
    let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
        let o = args[0]
        let flag = args[1]

        // Start with a packed double array a = [1.1 + 0.0, 2.2, 3.3]
        var d11 = b.loadFloat(1.1)
        let d00 = b.loadFloat(0.0)
        d11 = b.binary(d11, d00, with: .Add)
        let d22 = b.loadFloat(2.2)
        let d33 = b.loadFloat(3.3)
        let a = b.createArray(with: [d11, d22, d33])

        // a[5] = -0.0 (creates holes at 3,4)
        let negZero = b.loadFloat(-0.0)
        b.setElement(5, of: a, to: negZero)

        // Reflect.deleteProperty(a, "1")
        let Reflect = b.createNamedVariable(forBuiltin: "Reflect")
        _ = b.callMethod("deleteProperty", on: Reflect, withArgs: [a, b.loadString("1")])

        // a[2] = NaN (compute via 0.0 / 0.0 to avoid introducing non-number)
        let z = b.loadFloat(0.0)
        let nanv = b.binary(z, z, with: .Div)
        b.setElement(2, of: a, to: nanv)

        // a[0] = 1/0 (Infinity)
        let one = b.loadFloat(1.0)
        let infv = b.binary(one, d00, with: .Div)
        b.setElement(0, of: a, to: infv)

        // if (flagBool === true) { void o.x; a.length = 32; }
        let cond = b.compare(flag, with: b.loadBool(true), using: .equal)
        b.buildIf(cond) {
            let xprop = b.getProperty("x", of: o)
            b.hide(xprop)
            b.setProperty("length", of: a, to: b.loadInt(32))
        }

        b.doReturn(a)
    }

    // 2) Warmup and optimize
    // o_good = {x:42}
    let ObjectCtor = b.createNamedVariable(forBuiltin: "Object")
    let o_good = b.construct(ObjectCtor, withArgs: [])
    b.setProperty("x", of: o_good, to: b.loadInt(42))

    let falseVar = b.loadBool(false)
    b.buildRepeatLoop(n: 1000) { _ in
        b.callFunction(f, withArgs: [o_good, falseVar])
    }

    // try { new Function("f", "%PrepareFunctionForOptimization(f)")(f); } catch {}
    b.buildTryCatchFinally {
        let FunctionCtor = b.createNamedVariable(forBuiltin: "Function")
        let prep = b.construct(FunctionCtor, withArgs: [b.loadString("f"), b.loadString("%PrepareFunctionForOptimization(f)")])
        b.callFunction(prep, withArgs: [f])
    } catchBody: { _ in }

    // try { new Function("f", "%OptimizeFunctionOnNextCall(f)")(f); } catch {}
    b.buildTryCatchFinally {
        let FunctionCtor = b.createNamedVariable(forBuiltin: "Function")
        let opt = b.construct(FunctionCtor, withArgs: [b.loadString("f"), b.loadString("%OptimizeFunctionOnNextCall(f)")])
        b.callFunction(opt, withArgs: [f])
    } catchBody: { _ in }

    // Call f twice to trigger optimization
    b.callFunction(f, withArgs: [o_good, falseVar])
    b.callFunction(f, withArgs: [o_good, falseVar])

    // arr = f({}, true) // induce deopt on missing property in guarded block
    let o_bad = b.construct(ObjectCtor, withArgs: [])
    let trueVar = b.loadBool(true)
    let arr = b.callFunction(f, withArgs: [o_bad, trueVar])

    // 3) Post-deopt consumers (inside try/catch)
    b.buildTryCatchFinally {
        let v0 = b.getElement(0, of: arr)
        let v1 = b.getElement(1, of: arr)
        let v2 = b.getElement(2, of: arr)
        let v5 = b.getElement(5, of: arr)

        let one = b.loadFloat(1.0)
        _ = b.binary(one, v5, with: .Div)

        let NumberObj = b.createNamedVariable(forBuiltin: "Number")
        _ = b.callMethod("isNaN", on: NumberObj, withArgs: [v2])

        _ = b.callMethod("includes", on: arr, withArgs: [b.loadUndefined()])
        _ = b.callMethod("join", on: arr, withArgs: [b.loadString("|")])
        _ = b.callMethod("copyWithin", on: arr, withArgs: [b.loadInt(0), b.loadInt(2)])
        _ = b.callMethod("fill", on: arr, withArgs: [b.loadFloat(4.4), b.loadInt(3), b.loadInt(6)])

        let s = b.callMethod("slice", on: arr, withArgs: [])
        let reducer = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            let sum = b.binary(args[0], args[1], with: .Add)
            b.doReturn(sum)
        }
        _ = b.callMethod("reduce", on: s, withArgs: [reducer, b.loadFloat(0.0)])
        _ = b.callMethod("indexOf", on: arr, withArgs: [b.loadUndefined()])
    } catchBody: { _ in }

    // 4) GC pressure best-effort
    b.buildTryCatchFinally {
        let gcFn = b.createNamedVariable(forBuiltin: "gc")
        _ = b.callFunction(gcFn, withArgs: [])
    } catchBody: { _ in }

    b.buildRepeatLoop(n: 20) { _ in
        let dA = b.createArray(with: [b.loadFloat(0.1), b.loadFloat(0.2)])
        b.setElement(1000, of: dA, to: b.loadFloat(9.9))
    }
},
]