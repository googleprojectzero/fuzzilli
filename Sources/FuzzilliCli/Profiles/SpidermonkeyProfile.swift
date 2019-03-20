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

fileprivate func ForceSpidermonkeyIonGenerator(_ b: ProgramBuilder) {
    let f = b.randVar(ofType: .Function)
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))
    
    let start = b.loadInt(0)
    let end = b.loadInt(100)
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let spidermonkeyProfile = Profile(
    processArguments: [
        "--no-threads",
        "--cpu-count=1",
        "--ion-offthread-compile=off",
        "--baseline-warmup-threshold=10",
        "--ion-warmup-threshold=100",
        "--ion-check-range-analysis",
        "--ion-extra-checks",
        "--fuzzing-safe",
        "--reprl",
    ],

    processEnv: ["UBSAN_OPTIONS": "handle_segv=0"],

    codePrefix: """
                function main() {
                """,

    codeSuffix: """
                }
                main();
                gc();
                """,

    crashTests: ["crash(0);", "crash(1);", "crash(2);"],

    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceSpidermonkeyIonGenerator, 10),
    ]),
    
    builtins: defaultBuiltins + ["gc", "enqueueJob", "drainJobQueue", "bailout"],
    propertyNames: defaultPropertyNames,
    methodNames: defaultMethodNames
)
