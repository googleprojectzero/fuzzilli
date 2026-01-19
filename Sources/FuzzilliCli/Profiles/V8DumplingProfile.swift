// Copyright 2026 Google LLC
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

let v8DumplingProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--expose-gc",
            "--expose-externalize-string",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--jit-fuzzing",
            "--future",
            "--harmony",
            "--experimental-fuzzing",
            "--js-staging",
            "--expose-fast-api",
            "--predictable",
            "--no-sparkplug",
            "--maglev-dumping",
            "--turbofan-dumping",
            "--turbofan-dumping-print-deopt-frames"
        ]

        return args
    },

    // TODO(mdanylo): currently we run Fuzzilli in differential fuzzing
    // mode if processArgsReference is not nil. We should reconsider
    // this decision in the future in favour of something nicer.
    processArgsReference: [
        "--sparkplug-dumping",
        "--interpreter-dumping",
        "--no-maglev",
        "--no-turbofan",
        "--expose-gc",
        "--expose-externalize-string",
        "--omit-quit",
        "--allow-natives-syntax",
        "--fuzzing",
        "--jit-fuzzing",
        "--future",
        "--harmony",
        "--experimental-fuzzing",
        "--js-staging",
        "--expose-fast-api",
        "--predictable"
    ],

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: Timeout.interval(300, 900),

    codePrefix: """
                """,

    codeSuffix: """
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [

    ],

    additionalCodeGenerators: [
        (ForceJITCompilationThroughLoopGenerator,  5),
        (ForceTurboFanCompilationGenerator,        5),
        (ForceMaglevCompilationGenerator,          5),
        (TurbofanVerifyTypeGenerator,             10),

        (V8GcGenerator,                           10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionFuzzer,    1),
        (ValueSerializerFuzzer,  1),
        (V8RegExpFuzzer,         1),
        (FastApiCallFuzzer,      1),
        (LazyDeoptFuzzer,        1),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"      : .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise)),
        "d8"      : .jsD8,
        "Worker"  : .constructor([.jsAnything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ],

    additionalObjectGroups: [jsD8, jsD8Test, jsD8FastCAPI, gcOptions],

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    optionalPostProcessor: nil
)
