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
    ProgramTemplate("JIT1Function") { b in
        let genSize = 3

        // Generate random function signatures as our helpers
        var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)
        ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

        b.build(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            b.buildPlainFunction(with: .signature(signature)) { args in
                b.build(n: genSize)
            }
        }

        // Generate a larger function
        let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f = b.buildPlainFunction(with: .signature(signature)) { args in
            // Generate (larger) function body
            b.build(n: 30)
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
    },

    ProgramTemplate("JIT2Functions") { b in
        let genSize = 3

        // Generate random function signatures as our helpers
        var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)
        ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

        b.build(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            b.buildPlainFunction(with: .signature(signature)) { args in
                b.build(n: genSize)
            }
        }

        // Generate a larger function
        let signature1 = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f1 = b.buildPlainFunction(with: .signature(signature1)) { args in
            // Generate (larger) function body
            b.build(n: 15)
        }

        // Generate a second larger function
        let signature2 = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f2 = b.buildPlainFunction(with: .signature(signature2)) { args in
            // Generate (larger) function body
            b.build(n: 15)
        }

        // Generate some random instructions now
        b.build(n: genSize)

        // trigger JIT for first function
        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        }

        // trigger JIT for second function
        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        }

        // more random instructions
        b.build(n: genSize)

        b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))

        // maybe trigger recompilation
        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        }

        // maybe trigger recompilation
        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { args in
            b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
        }

        // more random instructions
        b.build(n: genSize)

        b.callFunction(f1, withArgs: b.generateCallArguments(for: signature1))
        b.callFunction(f2, withArgs: b.generateCallArguments(for: signature2))
    },

    // TODO turn "JITFunctionGenerator" into another template?

    ProgramTemplate("TypeConfusionTemplate") { b in
        // This is mostly the template built by Javier Jimenez
        // (https://sensepost.com/blog/2020/the-hunt-for-chromium-issue-1072171/).
        let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: Int.random(in: 2...5))

        let f = b.buildPlainFunction(with: .signature(signature)) { _ in
            b.build(n: 5)
            let array = b.generateVariable(ofType: .object(ofGroup: "Array"))

            let index = b.genIndex()
            b.loadElement(index, of: array)
            b.doReturn(b.randVar())
        }

        // TODO: check if these are actually different, or if
        // generateCallArguments generates the argument once and the others
        // just use them.
        let initialArgs = b.generateCallArguments(for: signature)
        let optimizationArgs = b.generateCallArguments(for: signature)
        let triggeredArgs = b.generateCallArguments(for: signature)

        b.callFunction(f, withArgs: initialArgs)

        b.buildForLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
            b.callFunction(f, withArgs: optimizationArgs)
        }

        b.callFunction(f, withArgs: triggeredArgs)
    },
]
