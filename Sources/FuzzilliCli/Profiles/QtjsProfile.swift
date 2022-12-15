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

// QV4 is the Execution Engine behind QTJS
fileprivate let ForceQV4JITGenerator = CodeGenerator("ForceQV4JITGenerator", input: .function()) { b, f in
    // The MutationEngine may use variables of unknown type as input as well, however, we only want to call functions that we generated ourselves. Further, attempting to call a non-function will result in a runtime exception.
    // For both these reasons, we abort here if we cannot prove that f is indeed a function.
    guard b.type(of: f).Is(.function()) else { return }
    guard let arguments = b.randCallArguments(for: f) else { return }
    b.buildRepeat(n: 100){ _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let qtjsProfile = Profile(
    getProcessArguments: { (randomizingArguments: Bool) -> [String] in
        return ["-reprl"]
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    // JavaScript code snippets that cause a crash in the target engine.
    // Used to verify that crashes can be detected.
    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)"],

    additionalCodeGenerators: [
        (ForceQV4JITGenerator,    20),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"                : .function([] => .undefined),
    ])
