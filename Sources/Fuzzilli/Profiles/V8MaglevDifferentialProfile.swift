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

/// Differential fuzzing profile for Maglev: the optimized run uses Maglev (with
/// Maglev-only code), the reference run uses the interpreter/Sparkplug with Maglev
/// and TurboFan disabled. The two executions are compared by their observable
/// output (see Profile.DifferentialMode.output), which catches silent
/// miscompilations that do not crash or trip a Maglev assertion.
public let v8MaglevDifferentialProfile = Profile(
    processArgs: { randomize, isWasmEnabled in
        var args = v8MaglevCommonProcessArgs
        args.append("--maglev")
        args.append("--maglev-as-top-tier")
        args.append("--maglev-inlining")
        // Turn representation-invariant violations into hard failures in debug
        // builds. These flags only affect the optimized run.
        args.append("--maglev-assert")
        args.append("--maglev-assert-types")
        return args
    },

    processArgsReference: v8MaglevCommonProcessArgs + ["--no-maglev"],

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    // Maglev compilation plus periodic GC is noticeably slower than a normal
    // run, hence the larger timeout.
    timeout: Timeout.interval(1000, 3000),

    codePrefix: """
        // --- Determinism Shim ---
        (function() {
            const originalDate = Date;
            const FIXED_TIME = 1767225600000;
            const FIXED_STRING = new originalDate(FIXED_TIME).toString();

            Date.now = function() { return FIXED_TIME; };
            globalThis.Date = new Proxy(originalDate, {
                construct(target, args) {
                    if (args.length === 0) return new target(FIXED_TIME);
                    return new target(...args);
                },
                apply(target, thisArg, args) { return FIXED_STRING; }
            });
            globalThis.Date.prototype = originalDate.prototype;

            const rng = function() {
                let s = 0x12345678;
                return function() {
                    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
                    return (s >>> 0) / 4294967296;
                };
            }();
            Math.random = rng;

            // Timing-dependent values must not differ between the two runs.
            if (typeof performance !== 'undefined' && performance.now) {
                performance.now = function() { return FIXED_TIME; };
            }
        })();
        // --- End Determinism Shim ---
        """,

    codeSuffix: "",

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed)
    ],

    additionalCodeGenerators: [
        (ForceMaglevCompilationGenerator, 15),
        (ForceJITCompilationThroughLoopGenerator, 10),
        (CompileBaselineGenerator, 10),
        (ForceOsrGenerator, 10),
        (NeverOptimizeFunctionGenerator, 5),
        (DisableEagerInliningGenerator, 5),
        (DeoptimizeFunctionGenerator, 10),
        (DeoptimizeNowGenerator, 5),
        (SetForceSlowPathGenerator, 5),
        // Force GC cycles so that stores and value-equal representations are
        // observed after objects may have moved.
        (V8GcGenerator, 15),
        (V8MajorGcGenerator, 10),
        (V8SimulateNewspaceFullGenerator, 5),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MaglevTypeConfusionFuzzer, 100)
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc": .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise()))
    ],

    additionalObjectGroups: [gcOptions],

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    additionalOptionsBags: [],

    optionalPostProcessor: nil,

    differentialMode: .output
)

/// Determinism shim shared by the Maglev differential profiles.
private let v8MaglevDeterminismShim = """
    // --- Determinism Shim ---
    (function() {
        const originalDate = Date;
        const FIXED_TIME = 1767225600000;
        const FIXED_STRING = new originalDate(FIXED_TIME).toString();

        Date.now = function() { return FIXED_TIME; };
        globalThis.Date = new Proxy(originalDate, {
            construct(target, args) {
                if (args.length === 0) return new target(FIXED_TIME);
                return new target(...args);
            },
            apply(target, thisArg, args) { return FIXED_STRING; }
        });
        globalThis.Date.prototype = originalDate.prototype;

        const rng = function() {
            let s = 0x12345678;
            return function() {
                s ^= s << 13; s ^= s >> 17; s ^= s << 5;
                return (s >>> 0) / 4294967296;
            };
        }();
        Math.random = rng;

        // Timing-dependent values must not differ between the two runs.
        if (typeof performance !== 'undefined' && performance.now) {
            performance.now = function() { return FIXED_TIME; };
        }
    })();
    // --- End Determinism Shim ---
    """

private let v8MaglevAdditionalCodeGenerators: [(CodeGenerator, Int)] = [
    (ForceMaglevCompilationGenerator, 15),
    (ForceJITCompilationThroughLoopGenerator, 10),
    (CompileBaselineGenerator, 10),
    (ForceOsrGenerator, 10),
    (NeverOptimizeFunctionGenerator, 5),
    (DisableEagerInliningGenerator, 5),
    (DeoptimizeFunctionGenerator, 10),
    (DeoptimizeNowGenerator, 5),
    (SetForceSlowPathGenerator, 5),
    (V8GcGenerator, 15),
    (V8MajorGcGenerator, 10),
    (V8SimulateNewspaceFullGenerator, 5),
]

/// Fault-injection variant of the Maglev differential profile. Requires a V8
/// build with the `--maglev-fuzz-drop-heapobject-check` hook (see
/// Targets/V8/Patches/maglev-fault-injection.patch). The hook drops the
/// HeapObjectness of numeric Phis during untagging and removes the following
/// CheckHeapObject, making the 486657483 shape crash deterministically.
public let v8MaglevFaultInjectionProfile = Profile(
    processArgs: { randomize, isWasmEnabled in
        var args = v8MaglevCommonProcessArgs
        args.append("--maglev")
        args.append("--maglev-as-top-tier")
        args.append("--maglev-inlining")
        args.append("--maglev-assert")
        args.append("--maglev-assert-types")
        args.append("--maglev-fuzz-drop-heapobject-check")
        return args
    },

    processArgsReference: v8MaglevCommonProcessArgs + [
        "--no-maglev", "--maglev-fuzz-drop-heapobject-check",
    ],

    processEnv: [:],

    maxExecsBeforeRespawn: 1000,

    timeout: Timeout.interval(1000, 3000),

    codePrefix: v8MaglevDeterminismShim,

    codeSuffix: "",

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed)
    ],

    additionalCodeGenerators: v8MaglevAdditionalCodeGenerators,

    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MaglevPhiHeapObjectnessFaultFuzzer, 1000),
        (MaglevTypeConfusionFuzzer, 10),
    ]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc": .function([.opt(gcOptions.instanceType)] => (.undefined | .jsPromise()))
    ],

    additionalObjectGroups: [gcOptions],

    additionalEnumerations: [.gcTypeEnum, .gcExecutionEnum],

    additionalOptionsBags: [],

    optionalPostProcessor: nil,

    differentialMode: .output
)

/// Arguments shared by the optimized and the reference runner. Both runs must
/// use identical flags except for the ones that select the execution tier, so
/// that any output difference is attributable to Maglev.
private let v8MaglevCommonProcessArgs = [
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
    // Force a GC every 100 allocations to observe heap objects and value-equal
    // representations after a potential move. --gc-interval=1 is stronger but
    // makes V8 startup alone take multiple seconds; the template also calls gc()
    // explicitly after suspect stores.
    "--gc-interval=100",
    // Keep both runs below the optimizing tier so that the only difference is
    // whether Maglev is enabled.
    "--no-turbofan",
]
