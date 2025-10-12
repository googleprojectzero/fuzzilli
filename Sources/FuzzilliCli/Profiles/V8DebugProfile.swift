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


let v8DebugProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--trace-turbo",
            "--trace-turbo-path=/home/diddy/v8DebugProfileOut",
            "--trace-feedback-updates",
        ]
        return args
    },

    // We typically fuzz without any sanitizer instrumentation, but if any sanitizers are active, "abort_on_error=1" must probably be set so that sanitizer errors can be detected.
    processEnv: [:],

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
        // IMMEDIATE_CRASH()
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        // CHECK failure
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        // DCHECK failure
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),
        // Wild-write
        ("fuzzilli('FUZZILLI_CRASH', 3)", .shouldCrash),
        // Check that DEBUG is defined.
        ("fuzzilli('FUZZILLI_CRASH', 8)", .shouldCrash),

        // TODO we could try to check that OOM crashes are ignored here ( with.shouldNotCrash).
    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (TurbofanVerifyTypeGenerator,             10),

        (WorkerGenerator,                         10),
        (V8GcGenerator,                           10),

        (WasmStructGenerator,                     15),
        (WasmArrayGenerator,                      15),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionFuzzer,    1),
        (ValueSerializerFuzzer,  1),
        (V8RegExpFuzzer,         1),
        (WasmFastCallFuzzer,     1),
        (FastApiCallFuzzer,      1),
        (LazyDeoptFuzzer,        1),
        (WasmDeoptFuzzer,        1),
        (WasmTurbofanFuzzer,     1),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                                            : .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise)),
        "d8"                                            : .jsD8,
        "Worker"                                        : .constructor([.jsAnything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ],

    additionalObjectGroups: [jsD8, jsD8Test, jsD8FastCAPI, gcOptions],

    // The other v8 configs have this as well
    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    optionalPostProcessor: nil
)
