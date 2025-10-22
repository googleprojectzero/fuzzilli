// Copyright 2023 Google LLC
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

// This value generator inserts Hole leaks into the program.  Use this if you
// want to fuzz for Memory Corruption using holes, this should be used in
// conjunction with the --hole-fuzzing runtime flag.
fileprivate let HoleLeakGenerator = CodeGenerator("HoleLeakGenerator", produces: [.jsAnything]) { b in
    b.eval("%LeakHole()", hasOutput: true)
}

let v8HoleFuzzingProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--expose-gc",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--hole-fuzzing",
            "--jit-fuzzing",
            "--future",
            "--harmony",
        ]
        return args
    },

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: 400,

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that "hard" crashes are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 7)", .shouldCrash),

        // Check that DEBUG is not defined.
        ("fuzzilli('FUZZILLI_CRASH', 8)", .shouldNotCrash),

        // DCHECK and CHECK failures should be ignored.
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldNotCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldNotCrash),
    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (V8GcGenerator,                           10),
        (HoleLeakGenerator,                       25),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                                            : .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise)),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.jsAnything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ],

    additionalObjectGroups: [jsD8, jsD8Test, jsD8FastCAPI, gcOptions],

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    optionalPostProcessor: nil
)
