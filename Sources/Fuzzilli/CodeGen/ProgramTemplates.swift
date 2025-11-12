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
        let allWasmTypes: WeightedList<ILType> = WeightedList([(.wasmi32, 1), (.wasmi64, 1), (.wasmf32, 1), (.wasmf64, 1), (.wasmExternRef, 1), (.wasmFuncRef, 1)])

        var wasmSignature = ProgramBuilder.convertJsSignatureToWasmSignature(signature, availableTypes: allWasmTypes)
        let wrapped = b.wrapSuspending(function: f!)

        let m = b.buildWasmModule { mod in
            mod.addWasmFunction(with: [] => []) { fbuilder, _, _  in
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
                return []
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
        let tags = [b.createWasmJSTag()] + wasmTags
        let tagToThrow = chooseUniform(from: wasmTags)
        let throwParamTypes = b.type(of: tagToThrow).wasmTagType!.parameters
        let tagToCatchForRethrow = chooseUniform(from: tags)
        let catchBlockOutputTypes = b.type(of: tagToCatchForRethrow).wasmTagType!.parameters + [.wasmExnRef]

        let module = b.buildWasmModule { wasmModule in
            // Wasm function that throws a tag, catches a tag (the same or a different one) to
            // rethrow it again (or another exnref if present).
            wasmModule.addWasmFunction(with: [] => []) { function, label, args in
                b.build(n: 10)
                let caughtValues = function.wasmBuildBlockWithResults(with: [] => catchBlockOutputTypes, args: []) { catchRefLabel, _ in
                    // TODO(mliedtke): We should probably allow mutations of try_tables to make
                    // these cases more generic. This would probably require being able to wrap
                    // things in a new block (so we can insert a target destination for a new catch
                    // with a matching signature) or to at least create a new tag for an existing
                    // block target. Either way, this is non-trivial.
                    function.wasmBuildTryTable(with: [] => [], args: [tagToCatchForRethrow, catchRefLabel], catches: [.Ref]) { _, _ in
                        b.build(n: 10)
                        function.WasmBuildThrow(tag: tagToThrow, inputs: throwParamTypes.map(function.findOrGenerateWasmVar))
                        return []
                    }
                    return catchBlockOutputTypes.map(function.findOrGenerateWasmVar)
                }
                b.build(n: 10)
                function.wasmBuildThrowRef(exception: b.randomVariable(ofType: .wasmExnRef)!)
                return []
            }
        }

        let exports = module.loadExports()
        b.buildTryCatchFinally {
            b.build(n: 10)
            // Call the exported wasm function.
            b.callMethod(module.getExportedMethod(at: 0), on: exports, withArgs: [b.loadInt(42)])
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


    ProgramTemplate("MaglevTypeGuardElimination") { b in
        let smallCodeBlockSize = 10
        let numIterations = 100

        // Start with random prefix and setup
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Create objects with unstable type information
        let obj = b.createObject(with: ["prop": b.loadInt(42)])
        let arr = b.createArray(with: [b.loadInt(1), b.loadString("test")])

        // Generate a function that challenges type inference
        let f = b.buildPlainFunction(with: .parameters(n: 2)) { args in
            // Generate code that creates type instability
            b.build(n: 15)
            
            // Type-changing property access
            let propAccess = b.getProperty("prop", of: obj)
            
            // Mixed-type operations that challenge type guards
            let mixedOp = b.binary(args[0], args[1], with: .Add)
            
            // Computed property access with varying types
            b.setComputedProperty(b.loadInt(0), of: arr, to: propAccess)
            
            // Return value with potential type confusion
            b.doReturn(mixedOp)
        }

        // Generate some random code before the main loop
        b.build(n: smallCodeBlockSize)

        // Main loop that triggers type guard elimination issues
        b.buildRepeatLoop(n: numIterations) { i in
            // Vary object types in different iterations
            let remainder = b.binary(i, b.loadInt(2), with: .Mod)
            let cond = b.compare(remainder, with: b.loadInt(0), using: .equal)
            b.buildIfElse(cond) {
                // Change object property to string in some iterations
                b.setProperty("prop", of: obj, to: b.loadString("changed"))
            } elseBody: {
                // Change to different numeric types in other iterations
                b.setProperty("prop", of: obj, to: i)
            }

            // Call function with different type combinations
            let args = [obj, arr] + b.randomArguments(forCallingFunctionWithParameters: [.plain(.jsAnything), .plain(.jsAnything)])
            b.callFunction(f, withArgs: args)
        }

        // Additional random code after loop
        b.build(n: smallCodeBlockSize)

        // Force recompilation with different type patterns
        b.buildRepeatLoop(n: numIterations) { i in
            // Create more type instability
            let mixedValue = b.binary(i, b.loadString("suffix"), with: .Add)
            b.setProperty("prop", of: obj, to: mixedValue)
            
            b.callFunction(f, withArgs: [obj, arr])
        }
    },


    ProgramTemplate("PhiRepresentationChallenge") { b in
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a function that creates phi nodes through control flow merging
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            // Create a variable that will flow through control flow and create phi nodes
            var result = b.loadInt(0)
            
            // Generate some random code
            b.build(n: 10)
            
            // Create control flow that naturally generates phi nodes
            // This creates a phi node for 'result' at the merge point
            withEqualProbability({
                // Branch 1: assign integer
                result = b.loadInt(42)
            }, {
                // Branch 2: assign float  
                result = b.loadFloat(3.14)
            }, {
                // Branch 3: assign string
                result = b.loadString("test")
            }, {
                // Branch 4: assign boolean
                result = b.loadBool(true)
            })
            
            // This is the merge point where a phi node is created for 'result'
            
            // Create loop phis by using the result in a loop
            var loopCounter = b.loadInt(0)
            b.buildRepeatLoop(n: 10) { i in
                // Create type transitions within the loop
                // This creates loop phis for 'result' and 'loopCounter'
                withEqualProbability({
                    result = b.loadInt(0)
                }, {
                    result = b.loadFloat(0.0)
                })
                
                // Update loop counter - creates loop phi
                loopCounter = b.binary(loopCounter, b.loadInt(1), with: .Add)
            }
            
            // Return the result which may have different types from different paths
            b.doReturn(result)
        }

        // Generate some more random code
        b.build(n: smallCodeBlockSize)

        // Call the function with varying argument types to create type pressure
        b.buildRepeatLoop(n: numIterations) { i in
            // Create different argument types to stress phi representation selection
            let arg: Variable
            if probability(0.25) {
                arg = b.loadInt(0)
            } else if probability(0.33) {
                arg = b.loadFloat(0.0)
            } else if probability(0.5) {
                arg = b.loadString("arg")
            } else {
                arg = b.loadBool(false)
            }
            b.callFunction(f, withArgs: [arg])
        }

        // More random code to potentially trigger recompilation
        b.build(n: smallCodeBlockSize)
        
        // Final calls with mixed types to stress representation selection
        b.callFunction(f, withArgs: [b.loadInt(0)])
        b.callFunction(f, withArgs: [b.loadFloat(1.0)])
        b.callFunction(f, withArgs: [b.loadString("final")])
        b.callFunction(f, withArgs: [b.loadBool(false)])
    },


    ProgramTemplate("CheckMapsChallenge") { b in
        // This template targets CheckMaps node processing vulnerabilities in V8
        // by creating complex object shapes and type transitions
        
        let smallCodeBlockSize = 5
        let numIterations = 100

        // Start with a random prefix and some random code
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Create multiple objects with different initial shapes
        // This creates different maps that will be tracked by V8
        let obj1 = b.buildPlainFunction(with: b.randomParameters()) { args in
            b.build(n: 10)
            let obj = b.buildObjectLiteral { obj in
                obj.addProperty("a", as: b.randomJsVariable())
                obj.addProperty("b", as: b.randomJsVariable())
            }
            b.doReturn(obj)
        }

        let obj2 = b.buildPlainFunction(with: b.randomParameters()) { args in
            b.build(n: 10)
            let obj = b.buildObjectLiteral { obj in
                obj.addProperty("a", as: b.randomJsVariable())
                obj.addProperty("c", as: b.randomJsVariable())
            }
            b.doReturn(obj)
        }

        // Generate some random instructions
        b.build(n: smallCodeBlockSize)

        // Create objects with the different shapes
        let o1 = b.callFunction(obj1, withArgs: b.randomArguments(forCalling: obj1))
        let o2 = b.callFunction(obj2, withArgs: b.randomArguments(forCalling: obj2))

        // Create a class to introduce more complex shape transitions
        let cls = b.buildPlainFunction(with: b.randomParameters()) { args in
            b.build(n: 10)
            let classDef = b.buildClassDefinition { cls in
                cls.addInstanceProperty("x", value: b.randomJsVariable())
                cls.addInstanceProperty("y", value: b.randomJsVariable())
            }
            b.doReturn(classDef)
        }

        let classObj = b.callFunction(cls, withArgs: b.randomArguments(forCalling: cls))

        // Generate more random code
        b.build(n: smallCodeBlockSize)

        // Create a function that processes objects with varying types
        // This will stress CheckMaps node processing
        let processor = b.buildPlainFunction(with: .parameters(.object())) { args in
            let obj = args[0]
            
            // Access properties that may or may not exist
            // This creates CheckMaps nodes for property access
            b.getProperty("a", of: obj, guard: true)
            b.getProperty("b", of: obj, guard: true) 
            b.getProperty("c", of: obj, guard: true)
            
            // Add new properties to change object shape
            b.setProperty("newProp", of: obj, to: b.randomJsVariable())
            
            b.build(n: 10)
            b.doReturn(obj)
        }

        // Call the processor with different object types
        // This creates type stability transitions
        b.buildRepeatLoop(n: numIterations) { i in
            // Alternate between different object types
            if probability(0.5) {
                b.callFunction(processor, withArgs: [o1])
            } else {
                b.callFunction(processor, withArgs: [o2])
            }
            
            // Occasionally use the class object
            if probability(0.2) {
                b.callFunction(processor, withArgs: [classObj])
            }
        }

        // More property mutations to create additional map transitions
        b.build(n: smallCodeBlockSize)
        
        // Add properties to existing objects to change their shapes
        b.setProperty("dynamic1", of: o1, to: b.randomJsVariable())
        b.setProperty("dynamic2", of: o2, to: b.randomJsVariable())
        
        // Final calls to processor with mutated objects
        b.buildRepeatLoop(n: numIterations / 2) { i in
            b.callFunction(processor, withArgs: [o1])
            b.callFunction(processor, withArgs: [o2])
        }

        // Generate final random code
        b.build(n: smallCodeBlockSize)
    },
]