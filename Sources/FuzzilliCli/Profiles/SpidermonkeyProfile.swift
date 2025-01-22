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

fileprivate let ForceSpidermonkeyIonGenerator = CodeGenerator("ForceSpidermonkeyIonGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
}

let spidermonkeyProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--baseline-warmup-threshold=10",
            "--ion-warmup-threshold=100",
            "--ion-check-range-analysis",
            "--ion-extra-checks",
            "--fuzzing-safe",
            "--disable-oom-functions",
            "--reprl"]

        guard randomize else { return args }

        args.append("--small-function-length=\(1<<Int.random(in: 7...12))")
        args.append("--inlining-entry-threshold=\(1<<Int.random(in: 2...10))")
        args.append("--gc-zeal=\(probability(0.5) ? UInt32(0) : UInt32(Int.random(in: 1...24)))")
        args.append("--ion-scalar-replacement=\(probability(0.9) ? "on": "off")")
        args.append("--ion-pruning=\(probability(0.9) ? "on": "off")")
        args.append("--ion-range-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--ion-inlining=\(probability(0.9) ? "on": "off")")
        args.append("--ion-gvn=\(probability(0.9) ? "on": "off")")
        args.append("--ion-osr=\(probability(0.9) ? "on": "off")")
        args.append("--ion-edgecase-analysis=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-size=\(1<<Int.random(in: 0...5))")
        args.append("--nursery-strings=\(probability(0.9) ? "on": "off")")
        args.append("--nursery-bigints=\(probability(0.9)  ? "on": "off")")
        args.append("--spectre-mitigations=\(probability(0.1) ? "on": "off")")
        if probability(0.1) {
            args.append("--no-native-regexp")
        }
        args.append("--ion-optimize-shapeguards=\(probability(0.9) ? "on": "off")")
        args.append("--ion-licm=\(probability(0.9) ? "on": "off")")
        args.append("--ion-instruction-reordering=\(probability(0.9) ? "on": "off")")
        args.append("--cache-ir-stubs=\(probability(0.9) ? "on": "off")")
        args.append(chooseUniform(from: ["--no-sse3", "--no-ssse3", "--no-sse41", "--no-sse42", "--enable-avx"]))
        if probability(0.1) {
            args.append("--ion-regalloc=testbed")
        }
        args.append(probability(0.9) ? "--enable-watchtower" : "--disable-watchtower")
        args.append("--ion-sink=\(probability(0.0) ? "on": "off")") // disabled
        return args
    },

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                """,

    codeSuffix: """
                gc();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    startupTests: [
        // Check that the fuzzilli integration is available.
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        // Check that common crash types are detected.
        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),

        // TODO we could try to check that OOM crashes are ignored here ( with.shouldNotCrash).
    ],

    additionalCodeGenerators: [
        (ForceSpidermonkeyIonGenerator, 10),
        (GcGenerator,                   10),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"            : .function([] => .undefined),
        "enqueueJob"    : .function([.function()] => .undefined),
        "drainJobQueue" : .function([] => .undefined),
        "bailout"       : .function([] => .undefined),

    ],

    additionalObjectGroups: [],

    optionalPostProcessor: nil
)
