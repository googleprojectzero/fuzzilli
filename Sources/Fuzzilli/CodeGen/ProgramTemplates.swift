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

    ProgramTemplate("JIT1Function") { b in
        let smallCodeBlockSize = 5

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 30)
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))

        // maybe trigger recompilation
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    ProgramTemplate("JIT2Functions") { b in
        let smallCodeBlockSize = 5

        // Start with a random prefix and some random code.
        b.buildPrefix()
        b.build(n: smallCodeBlockSize)

        // Generate a larger function
        let f1 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
        }

        // Generate a second larger function
        let f2 = b.buildPlainFunction(with: b.randomParameters()) { args in
            assert(args.count > 0)
            // Generate (larger) function body
            b.build(n: 20)
        }

        // Generate some random instructions now
        b.build(n: smallCodeBlockSize)

        // trigger JIT for first function
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        }

        // trigger JIT for second function
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
        }

        // more random instructions
        b.build(n: smallCodeBlockSize)

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
        b.build(n: smallCodeBlockSize)

        b.callFunction(f1, withArgs: b.randomArguments(forCalling: f1))
        b.callFunction(f2, withArgs: b.randomArguments(forCalling: f2))
    },

    ProgramTemplate("JSONFuzzer") { b in
        b.buildPrefix()

        // Create some random values that will be JSON.stringified below.
        b.build(n: 25)

        // Generate random JSON payloads by stringifying random values
        let JSON = b.loadBuiltin("JSON")
        var jsonPayloads = [Variable]()
        for _ in 0..<Int.random(in: 1...5) {
            let json = b.callMethod("stringify", on: JSON, withArgs: [b.randomVariable()])
            jsonPayloads.append(json)
        }

        // Optionally mutate (some of) the json string
        let mutateJson = b.buildPlainFunction(with: .parameters(.string)) { args in
            let json = args[0]

            // Helper function to pick a random index where we'll replace a part of the json string.
            let randInt = b.buildPlainFunction(with: .parameters(.integer)) { args in
                let max = args[0]
                let Math = b.loadBuiltin("Math")
                var random = b.callMethod("random", on: Math)
                random = b.binary(random, max, with: .Mul)
                random = b.callMethod("floor", on: Math, withArgs: [random])
                b.doReturn(random)
            }

            // Replace a random character with a random string
            let length = b.getProperty("length", of: json)
            let index = b.callFunction(randInt, withArgs: [length])
            let zero = b.loadInt(0)
            let part1 = b.callMethod("substring", on: json, withArgs: [zero, index])
            let indexPlusOne = b.binary(index, b.loadInt(1), with: .Add)
            let part2 = b.callMethod("substring", on: json, withArgs: [indexPlusOne])
            let replacement = b.loadString(b.randomString())
            let tmp = b.binary(part1, replacement, with: .Add)
            let newJson = b.binary(tmp, part2, with: .Add)
            b.doReturn(newJson)
        }
        for (i, json) in jsonPayloads.enumerated() {
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

    // TODO turn "JITFunctionGenerator" into another template?
]
