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

// TODO: move common parts (e.g. generators) into a V8CommonProfile.swift.
fileprivate let ForceJITCompilationThroughLoopGenerator = CodeGenerator("ForceJITCompilationThroughLoopGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)
    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}
fileprivate let ForceTurboFanCompilationGenerator = CodeGenerator("ForceTurboFanCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)
    b.callFunction(f, withArgs: arguments)
    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);
    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)
    b.eval("%OptimizeFunctionOnNextCall(%@)", with: [f]);
    b.callFunction(f, withArgs: arguments)
}
fileprivate let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)
    b.callFunction(f, withArgs: arguments)
    b.eval("%PrepareFunctionForOptimization(%@)", with: [f]);
    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)
    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f]);
    b.callFunction(f, withArgs: arguments)
}
// Insert random GC calls throughout our code.
fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    let gc = b.createNamedVariable(forBuiltin: "gc")
    // Do minor GCs more frequently.
    let type = b.loadString(probability(0.25) ? "major" : "minor")
    // If the execution type is 'async', gc() returns a Promise, we currently
    // do not really handle other than typing the return of gc to .undefined |
    // .jsPromise. One could either chain a .then or create two wrapper
    // functions that are differently typed such that fuzzilli always knows
    // what the type of the return value is.
    let execution = b.loadString(probability(0.5) ? "sync" : "async")
    b.callFunction(gc, withArgs: [b.createObject(with: ["type": type, "execution": execution])])
}

// This value generator inserts Hole leaks into the program.  Use this if you
// want to fuzz for Memory Corruption using holes, this should be used in
// conjunction with the --hole-fuzzing runtime flag.
fileprivate let HoleLeakGenerator = ValueGenerator("HoleLeakGenerator") { b, args in
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
    timeout: 250,
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
        (GcGenerator,                             10),
        (HoleLeakGenerator,                       25),
    ],
    additionalProgramTemplates: WeightedList<ProgramTemplate>([
    ]),
    disabledCodeGenerators: [],
    disabledMutators: [],
    additionalBuiltins: [
        "gc"                                            : .function([] => (.undefined | .jsPromise)),
        "d8"                                            : .object(),
        "Worker"                                        : .constructor([.anything, .object()] => .object(withMethods: ["postMessage","getMessage"])),
    ],
    additionalObjectGroups: [],
    optionalPostProcessor: nil
)
