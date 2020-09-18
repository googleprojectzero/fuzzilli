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


// These CodeTemplates create more complex code samples and are better
// suited for the HybridFuzzing mode.
public let CodeTemplates: [CodeTemplate] = [
    CodeTemplate("JIT1Function") { b in
        let genSize = 3

        // Generate random function signatures as our helpers
        var functionSignatures = CodeTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        // Generate random property types
        CodeTemplate.generateRandomPropertyTypes(forBuilder: b)

        // Generate random method types
        CodeTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

        b.generate(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            // Here generate a random function type, e.g. arrow/generator etc
            b.definePlainFunction(withSignature: signature) { args in
                b.generate(n: genSize)
            }
        }

        // Generate a larger function
        let signature = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f = b.definePlainFunction(withSignature: signature) { args in
            // Generate (larger) function body
            b.generate(n: 30)
        }

        // Generate some random instructions now
        b.generate(n: genSize)

        // trigger JIT
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
        }

        // more random instructions
        b.generate(n: genSize)
        b.callFunction(f, withArgs: b.generateCallArguments(for: signature))

        // maybe trigger recompilation
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
        }

        // more random instructions
        b.generate(n: genSize)

        b.callFunction(f, withArgs: b.generateCallArguments(for: signature))
    },
    CodeTemplate("TypeConfusionTemplate") { b in
        // This is mostly the template built by Javier Jimenez
        // (https://sensepost.com/blog/2020/the-hunt-for-chromium-issue-1072171/).
        let signature = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: Int.random(in: 2...5))

        let f = b.definePlainFunction(withSignature: signature) { _ in
            b.generate(n: 5)
            let array = b.generateVariable(ofType: .object(ofGroup: "Array"))

            let index = b.genIndex()
            b.loadElement(index, of: array)
            b.doReturn(value: b.randVar())
        }

        // TODO: check if these are actually different, or if
        // generateCallArguments generates the argument once and the others
        // just use them.
        let initialArgs = b.generateCallArguments(for: signature)
        let optimizationArgs = b.generateCallArguments(for: signature)
        let triggeredArgs = b.generateCallArguments(for: signature)

        b.callFunction(f, withArgs: initialArgs)

        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
            b.callFunction(f, withArgs: optimizationArgs)
        }

        b.callFunction(f, withArgs: triggeredArgs)
    },
    CodeTemplate("ClassStructure") { b in
        // Generate a medium-sized function
        let signature = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: 2)
        let f = b.definePlainFunction(withSignature: signature) { args in
            // force the load of this, such that generators can use this.
            let this = b.loadBuiltin("this")
            b.generate(n: 30)
        }

        let signature2 = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: 2)
        let f2 = b.definePlainFunction(withSignature: signature) { args in 
            let this = b.loadBuiltin("this")
            b.generate(n: 30)
        }

        let proto = b.loadProperty("prototype", of: f)

        let propName = b.genPropertyNameForWrite()

        // f.prototype.f2 = f2
        b.storeProperty(f2, as: propName, on: proto)

        b.generate(n: 6)

        let instance = b.construct(f, withArgs: b.generateCallArguments(for: signature))

        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callMethod(propName, on: instance, withArgs: b.generateCallArguments(for: signature))
        }

        b.callMethod(propName, on: instance, withArgs: b.generateCallArguments(for: signature))
    },
    CodeTemplate("JIT2Functions") { b in
        let genSize = 3

        // Generate random function signatures as our helpers
        var functionSignatures = CodeTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        // Generate random property types
        CodeTemplate.generateRandomPropertyTypes(forBuilder: b)

        // Generate random method types
        CodeTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

        b.generate(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            // Here generate a random function type, e.g. arrow/generator etc
            b.definePlainFunction(withSignature: signature) { args in
                b.generate(n: genSize)
            }
        }

        // Generate a larger function
        let signature1 = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f1 = b.definePlainFunction(withSignature: signature1) { args in
            // Generate (larger) function body
            b.generate(n: 15)
        }

        // Generate a second larger function
        let signature2 = CodeTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f2 = b.definePlainFunction(withSignature: signature2) { args in
            // Generate (larger) function body
            b.generate(n: 15)
        }

        // Generate some random instructions now
        b.generate(n: genSize)

        // trigger JIT for first function
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        }

        // trigger JIT for second function
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        }

        // more random instructions
        b.generate(n: genSize)

        b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))

        // maybe trigger recompilation
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        }

        // maybe trigger recompilation
        b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        }

        // more random instructions
        b.generate(n: genSize)

        b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
    },
]
