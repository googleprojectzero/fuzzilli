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

        b.build(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            b.buildPlainFunction(with: .parameters(signature.parameters)) { args in
                b.build(n: genSize)
            }
        }

        // Generate a larger function
        let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f = b.buildPlainFunction(with: .parameters(signature.parameters)) { args in
            // Generate (larger) function body
            b.build(n: 30)
        }

        // Generate some random instructions now
        b.build(n: genSize)

        // trigger JIT
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: genSize)
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: genSize)

        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    ProgramTemplate("JIT2Functions") { b in
        let genSize = 3

        // Generate random function signatures as our helpers
        var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

        b.build(n: genSize)

        // Generate some small functions
        for signature in functionSignatures {
            b.buildPlainFunction(with: .parameters(signature.parameters)) { args in
                b.build(n: genSize)
            }
        }

        // Generate a larger function
        let signature1 = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f1 = b.buildPlainFunction(with: .parameters(signature1.parameters)) { args in
            // Generate (larger) function body
            b.build(n: 15)
        }

        // Generate a second larger function
        let signature2 = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
        let f2 = b.buildPlainFunction(with: .parameters(signature2.parameters)) { args in
            // Generate (larger) function body
            b.build(n: 15)
        }

        // Generate some random instructions now
        b.build(n: genSize)

        // trigger JIT for first function
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // trigger JIT for second function
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: genSize)

        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // maybe trigger recompilation
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: genSize)

        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
    },

    // TODO turn "JITFunctionGenerator" into another template?
]
