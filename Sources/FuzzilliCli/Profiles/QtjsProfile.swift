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
fileprivate let ForceQV4JITGenerator = CodeGenerator("ForceQV4JITGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: 100){ _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let qtjsProfile = Profile(
    processArgs: { randomize in
        ["-reprl"]
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
    ],

    additionalCodeGenerators: [
        (ForceQV4JITGenerator,    20),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                : .function([] => .undefined),
    ],

    additionalObjectGroups: [],

    optionalPostProcessor: nil
)
