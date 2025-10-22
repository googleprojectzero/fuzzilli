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

let v8Profile = Profile(
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
            "--wasm-staging",
            "--wasm-fast-api",
            "--expose-fast-api",
            "--experimental-wasm-rab-integration",
            "--wasm-test-streaming", // WebAssembly.compileStreaming & WebAssembly.instantiateStreaming()
        ]

        guard randomize else { return args }

        //
        // Existing features that should sometimes be disabled.
        //
        if probability(0.1) {
            args.append("--no-turbofan")
        }

        if probability(0.1) {
            args.append("--no-maglev")
        }

        if probability(0.1) {
            args.append("--no-sparkplug")
        }

        if probability(0.1) {
            args.append("--no-short-builtin-calls")
        }

        // Disabling Liftoff enables "direct" coverage for the optimizing compiler, though some
        // features (like speculative inlining) require a combination of Liftoff and Turbofan.
        // Note that this flag only affects WebAssembly.
        if probability(0.5) {
            args.append("--no-liftoff")
            if probability(0.3) {
                args.append("--wasm-assert-types")
            }
        }

        // This greatly helps the fuzzer to decide inlining wasm functions into each other when
        // %WasmTierUpFunction() is used as in most cases the call counts will be way too low to
        // align with V8's current inlining heuristics (which uses absolute call counts as a
        // deciding factor).
        if probability(0.5) {
            args.append("--wasm-inlining-ignore-call-counts")
        }

        //
        // Future features that should sometimes be enabled.
        //
        if probability(0.1) {
            args.append("--minor-ms")
        }

        if probability(0.25) {
            args.append("--shared-string-table")
        }

        if probability(0.25) && !args.contains("--no-maglev") {
            args.append("--maglev-future")
        }

        if probability(0.1) {
            args.append("--turboshaft-typed-optimizations")
        }

        if probability(0.5) {
            args.append("--turbolev")
            if probability(0.82) {
                args.append("--turbolev-future")
            }
        }

        if probability(0.1) {
            args.append("--turboshaft-wasm-in-js-inlining")
        }

        if probability(0.1) {
            args.append("--harmony-struct")
        }

        if probability(0.1) {
            args.append("--efficiency-mode")
        }

        if probability(0.1) {
            args.append("--battery-saver-mode")
        }

        if probability(0.1) {
            args.append("--stress-scavenger-conservative-object-pinning-random")
        }

        if probability(0.1) {
            args.append("--precise-object-pinning")
        }

        if probability(0.1) {
            args.append("--handle-weak-ref-weakly-in-minor-gc")
        }

        if probability(0.1) {
            args.append("--scavenger-chaos-mode")
            let threshold = Int.random(in: 0...100)
            args.append("--scavenger-chaos-mode-threshold=\(threshold)")
        }

        if probability(0.1) {
            let stackSize = Int.random(in: 54...863)
            args.append("--stack-size=\(stackSize)")
        }

        // Temporarily enable the three flags below with high probability to
        // stress-test JSPI.
        // Lower the probabilities once we have enough coverage.
        if (probability(0.5)) {
            let stackSwitchingSize = Int.random(in: 1...300)
            args.append("--wasm-stack-switching-stack-size=\(stackSwitchingSize)")
        }
        if (probability(0.5)) {
            args.append("--experimental-wasm-growable-stacks")
        }
        if (probability(0.5)) {
            args.append("--stress-wasm-stack-switching")
        }

        if probability(0.5) {
            args.append("--proto-assign-seq-opt")
        }

        //
        // Sometimes enable additional verification/stressing logic (which may be fairly expensive).
        //
        if probability(0.1) {
            args.append("--verify-heap")
        }
        if probability(0.1) {
            args.append("--turbo-verify")
        }
        if probability(0.1) {
            args.append("--turbo-verify-allocation")
        }
        if probability(0.1) {
            args.append("--assert-types")
        }
        if probability(0.1) {
            args.append("--turboshaft-assert-types")
        }
        if probability(0.1) {
            args.append("--deopt-every-n-times=\(chooseUniform(from: [100, 250, 500, 1000, 2500, 5000, 10000]))")
        }
        if probability(0.1) {
            args.append("--stress-ic")
        }
        if probability(0.1) {
            args.append("--optimize-on-next-call-optimizes-to-maglev")
        }
        if probability(0.2) {
            args.append("--turboshaft-verify-load-elimination")
        }

        //
        // A gc-stress session with some fairly expensive flags.
        //
        if probability(0.1) {
            if probability(0.4) {
                args.append("--stress-marking=\(Int.random(in: 1...100))")
            }
            if probability(0.4) {
                args.append("--stress-scavenge=\(Int.random(in: 1...100))")
            }
            if probability(0.5) {
                args.append("--stress-flush-code")
                args.append("--flush-bytecode")
            }
            if probability(0.5) {
                args.append("--wasm-code-gc")
                args.append("--stress-wasm-code-gc")
            }
            if probability(0.4) {
                args.append(chooseUniform(
                    from: ["--gc-interval=\(Int.random(in: 100...10000))",
                           "--random-gc-interval=\(Int.random(in: 1000...10000))"]))
            }
            if probability(0.4) {
                args.append("--concurrent-recompilation-queue-length=\(Int.random(in: 4...64))")
                args.append("--concurrent-recompilation-delay=\(Int.random(in: 1...500))")
            }
            if probability(0.6) {
                args.append(chooseUniform(
                    from: ["--stress-compaction", "--stress-compaction-random"]))
            }
        }

        //
        // More exotic configuration changes.
        //
        if probability(0.05) {
            if probability(0.5) { args.append("--stress-gc-during-compilation") }
            if probability(0.5) { args.append("--lazy-new-space-shrinking") }
            if probability(0.5) { args.append("--stress-wasm-memory-moving") }
            if probability(0.5) { args.append("--stress-background-compile") }
            if probability(0.5) { args.append("--parallel-compile-tasks-for-lazy") }
            if probability(0.5) { args.append("--parallel-compile-tasks-for-eager-toplevel") }

            args.append(probability(0.5) ? "--always-sparkplug" : "--no-always-sparkplug")
            args.append(probability(0.5) ? "--always-osr" : "--no-always-osr")
            args.append(probability(0.5) ? "--concurrent-osr" : "--no-concurrent-osr")
            args.append(probability(0.5) ? "--force-slow-path" : "--no-force-slow-path")

            // Maglev related flags
            args.append(probability(0.5) ? "--maglev-inline-api-calls" : "--no-maglev-inline-api-calls")

            // Compiler related flags
            args.append(probability(0.5) ? "--turbo-move-optimization" : "--no-turbo-move-optimization")
            args.append(probability(0.5) ? "--turbo-jt" : "--no-turbo-jt")
            args.append(probability(0.5) ? "--turbo-loop-peeling" : "--no-turbo-loop-peeling")
            args.append(probability(0.5) ? "--turbo-loop-variable" : "--no-turbo-loop-variable")
            args.append(probability(0.5) ? "--turbo-loop-rotation" : "--no-turbo-loop-rotation")
            args.append(probability(0.5) ? "--turbo-cf-optimization" : "--no-turbo-cf-optimization")
            args.append(probability(0.5) ? "--turbo-escape" : "--no-turbo-escape")
            args.append(probability(0.5) ? "--turbo-allocation-folding" : "--no-turbo-allocation-folding")
            args.append(probability(0.5) ? "--turbo-instruction-scheduling" : "--no-turbo-instruction-scheduling")
            args.append(probability(0.5) ? "--turbo-stress-instruction-scheduling" : "--no-turbo-stress-instruction-scheduling")
            args.append(probability(0.5) ? "--turbo-store-elimination" : "--no-turbo-store-elimination")
            args.append(probability(0.5) ? "--turbo-rewrite-far-jumps" : "--no-turbo-rewrite-far-jumps")
            args.append(probability(0.5) ? "--turbo-optimize-apply" : "--no-turbo-optimize-apply")
            args.append(chooseUniform(from: ["--no-enable-sse3", "--no-enable-ssse3", "--no-enable-sse4-1", "--no-enable-sse4-2", "--no-enable-avx", "--no-enable-avx2"]))
            args.append(probability(0.5) ? "--turbo-load-elimination" : "--no-turbo-load-elimination")
            args.append(probability(0.5) ? "--turbo-inlining" : "--no-turbo-inlining")
            args.append(probability(0.5) ? "--turbo-splitting" : "--no-turbo-splitting")
        }

        return args
    },

    // We typically fuzz without any sanitizer instrumentation, but if any sanitizers are active, "abort_on_error=1" must probably be set so that sanitizer errors can be detected.
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
        (PretenureAllocationSiteGenerator,         5),
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

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    optionalPostProcessor: nil
)
