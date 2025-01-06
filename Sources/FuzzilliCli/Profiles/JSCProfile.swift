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

fileprivate let ForceDFGCompilationGenerator = CodeGenerator("ForceDFGCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 10) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceFTLCompilationGenerator = CodeGenerator("ForceFTLCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.buildRepeatLoop(n: 100) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    b.callFunction(b.createNamedVariable(forBuiltin: "gc"))
}

let jscProfile = Profile(
    processArgs: { randomize in
        var args = [
            "--validateOptions=true",
            // No need to call functions thousands of times before they are JIT compiled
            "--thresholdForJITSoon=10",
            "--thresholdForJITAfterWarmUp=10",
            "--thresholdForOptimizeAfterWarmUp=100",
            "--thresholdForOptimizeAfterLongWarmUp=100",
            "--thresholdForOptimizeSoon=100",
            "--thresholdForFTLOptimizeAfterWarmUp=1000",
            "--thresholdForFTLOptimizeSoon=1000",
            // Enable bounds check elimination validation
            "--validateBCE=true",
            "--reprl"]

        guard randomize else { return args }

        args.append("--useBaselineJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useDFGJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useFTLJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useRegExpJIT=\(probability(0.9) ? "true" : "false")")
        args.append("--useTailCalls=\(probability(0.9) ? "true" : "false")")
        args.append("--optimizeRecursiveTailCalls=\(probability(0.9) ? "true" : "false")")
        args.append("--useObjectAllocationSinking=\(probability(0.9) ? "true" : "false")")
        args.append("--useArityFixupInlining=\(probability(0.9) ? "true" : "false")")
        args.append("--useValueRepElimination=\(probability(0.9) ? "true" : "false")")
        args.append("--useArchitectureSpecificOptimizations=\(probability(0.9) ? "true" : "false")")
        args.append("--useAccessInlining=\(probability(0.9) ? "true" : "false")")

        return args
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

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
        (ForceDFGCompilationGenerator, 5),
        (ForceFTLCompilationGenerator, 5),
        (GcGenerator,                  5),
    ],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    disabledMutators: [],

    additionalBuiltins: [
        "gc"                  : .function([] => .undefined),
        "transferArrayBuffer" : .function([.object(ofGroup: "ArrayBuffer")] => .undefined),
        "noInline"            : .function([.function()] => .undefined),
        "noFTL"               : .function([.function()] => .undefined),
        "createGlobalObject"  : .function([] => .object()),
        "OSRExit"             : .function([] => .anything),
        "drainMicrotasks"     : .function([] => .anything),
        "runString"           : .function([.string] => .anything),
        "makeMasquerader"     : .function([] => .anything),
        "fullGC"              : .function([] => .undefined),
        "edenGC"              : .function([] => .undefined),
        "fiatInt52"           : .function([.number] => .number),
        "forceGCSlowPaths"    : .function([] => .anything),
        "ensureArrayStorage"  : .function([] => .anything),
    ],

    additionalObjectGroups: [],

    optionalPostProcessor: nil
)
