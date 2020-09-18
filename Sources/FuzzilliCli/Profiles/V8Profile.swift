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
    guard let arguments = b.randCallArguments(for: f) else { return }
    
    let start = b.loadInt(0)
    let end = b.loadInt(100)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let v8Profile = Profile(
    processArguments: ["--debug-code",
                       "--expose-gc",
                       "--single-threaded",
                       "--predictable",
                       "--allow-natives-syntax",
                       "--interrupt-budget=1024",
                       "--assert-types",
                       "--fuzzing",
                       "--reprl"],
    
    processEnv: [:],
    
    codePrefix: """
                function main() {
                """,
    
    codeSuffix: """
                }
                %NeverOptimizeFunction(main);
                main();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],
    
    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceV8TurbofanGenerator, 10),
    ]),
       
    disabledCodeGenerators: [],
    
    additionalBuiltins: [
        "gc"                : .function([] => .undefined),
    ]
)

