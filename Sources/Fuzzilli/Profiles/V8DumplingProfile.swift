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

                    // Math.random shim
                    const rng = function() {
                        let s = 0x12345678;
                        return function() {
                            s ^= s << 13; s ^= s >> 17; s ^= s << 5;
                            return (s >>> 0) / 4294967296;
                        };
                    }();
                    Math.random = rng;

                    if (typeof Temporal !== 'undefined' && Temporal.Now) {
                        const fixedInstant = Temporal.Instant.fromEpochMilliseconds(FIXED_TIME);

                        Temporal.Now.instant = () => fixedInstant;

                        // Shim Zoned/Plain methods to use the fixed instant
                        Temporal.Now.zonedDateTimeISO = (tzLike) =>
                            fixedInstant.toZonedDateTimeISO(tzLike || Temporal.Now.timeZoneId());

                        Temporal.Now.plainDateTimeISO = (tzLike) =>
                            fixedInstant.toZonedDateTimeISO(tzLike || Temporal.Now.timeZoneId()).toPlainDateTime();

                        Temporal.Now.plainDateISO = (tzLike) =>
                            fixedInstant.toZonedDateTimeISO(tzLike || Temporal.Now.timeZoneId()).toPlainDate();

                        Temporal.Now.plainTimeISO = (tzLike) =>
                            fixedInstant.toZonedDateTimeISO(tzLike || Temporal.Now.timeZoneId()).toPlainTime();
                    }
                })();
                // --- End Determinism Shim ---
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
        (ForceOsrGenerator,                        5),
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

    optionalPostProcessor: DumplingFuzzingPostProcessor()
)

/// A post-processor for the Dumpling profile.
///
/// Work-around for differential fuzzing to avoid f.arguments.
/// Or any access to "arguments" with a computed property. We just
/// overapproximate this by checking for any string occurence of
/// "arguments" and reject the sample.
public struct DumplingFuzzingPostProcessor: FuzzingPostProcessor {
    public func process(_ program: Program, for fuzzer: Fuzzer) throws -> Program {
        for instr in program.code {
            switch instr.op.opcode {
            case .loadString(let op) where op.value == "arguments":
                throw InternalError.postProcessRejection("\"arguments\" string")
            case .getProperty(let op) where op.propertyName == "arguments":
                throw InternalError.postProcessRejection("f.arguments access")
            case .setProperty(let op) where op.propertyName == "arguments":
                throw InternalError.postProcessRejection("f.arguments assignment")
            case .updateProperty(let op) where op.propertyName == "arguments":
                throw InternalError.postProcessRejection("f.arguments update")
            case .deleteProperty(let op) where op.propertyName == "arguments":
                throw InternalError.postProcessRejection("f.arguments deletion")
            default:
                break
            }
        }

        return program
    }
}
