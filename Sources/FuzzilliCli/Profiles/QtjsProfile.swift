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
fileprivate let ForceQV4JITGenerator = CodeGenerator("ForceQV4JITGenerator", input: .function()) { b, f in 
    guard let arguments = b.randCallArguments(for: f) else { return }
    let start = b.loadInt(0)
    let end = b.loadInt(100)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}
fileprivate let QV4JITVerifyTypeGenerator = CodeGenerator("QV4JITVerifyTypeGenerator", input: .anything) { b, v in
    b.eval("%VerifyType(%@)", with: [v])
}

fileprivate let VerifyTypeTemplate = ProgramTemplate("VerifyTypeTemplate") { b in
    let genSize = 3

    // Generate random function signatures as our helpers
    var functionSignatures = ProgramTemplate.generateRandomFunctionSignatures(forFuzzer: b.fuzzer, n: 2)

    // Generate random property types
    ProgramTemplate.generateRandomPropertyTypes(forBuilder: b)

    // Generate random method types
    ProgramTemplate.generateRandomMethodTypes(forBuilder: b, n: 2)

    b.generate(n: genSize)

    // Generate some small functions
    for signature in functionSignatures {
        // Here generate a random function type, e.g. arrow/generator etc
        b.definePlainFunction(withSignature: signature) { args in
            b.generate(n: genSize)
        }
    }

    // Generate a larger function
    let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: 4)
    let f = b.definePlainFunction(withSignature: signature) { args in
        // Generate function body and sprinkle calls to %VerifyType
        for _ in 0..<10 {
            b.generate(n: 3)
            b.eval("%VerifyType(%@)", with: [b.randVar()])
        }
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
}

let qtjsProfile = Profile(
    processArguments: ["-reprl"],
    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    codePrefix: """
                function main() { 
                """,

    codeSuffix: """
                }
                main();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    // JavaScript code snippets that cause a crash in the target engine.
    // Used to verify that crashes can be detected.
    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)"],
    
    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceQV4JITGenerator,    200),
        (QV4JITVerifyTypeGenerator, 200),
    ]),

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (VerifyTypeTemplate, 1),
    ]),
    disabledCodeGenerators: [],
   
    additionalBuiltins: [
        "gc"                : .function([] => .undefined),
    ])
