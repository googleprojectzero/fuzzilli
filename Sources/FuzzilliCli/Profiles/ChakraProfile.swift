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

fileprivate func ForceSimpleJitCompilationGenerator(_ b: ProgramBuilder) {
    let f = b.randVar(ofType: .Function)
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))

    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(10), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate func ForceFullJitCompilationGenerator(_ b: ProgramBuilder) {
    let f = b.randVar(ofType: .Function)
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))

    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let chakraProfile = Profile(
    processArguments: ["-maxinterpretcount:10",
                       "-maxsimplejitruncount:100",
                       "-bgjit-",
                       "-oopjit-",
                       "-reprl",
                       "fuzzcode.js"],

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    codePrefix: """
                function main() {
                """,

    codeSuffix: """
                }
                main();
                """,

    crashTests: ["crash(0)", "crash(1)", "crash(2)"],

    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceSimpleJitCompilationGenerator, 5),
        (ForceFullJitCompilationGenerator, 5),
    ]),

    builtins: defaultBuiltins,
    propertyNames: defaultPropertyNames,
    methodNames: defaultMethodNames
)
