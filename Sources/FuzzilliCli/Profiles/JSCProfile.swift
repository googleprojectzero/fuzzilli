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

fileprivate let ForceDFGCompilationGenerator = CodeGenerator("ForceDFGCompilationGenerator", input: .function()) { b, f in
   guard let arguments = b.randCallArguments(for: f) else { return }
    
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(10), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate let ForceFTLCompilationGenerator = CodeGenerator("ForceFTLCompilationGenerator", input: .function()) { b, f in
   guard let arguments = b.randCallArguments(for: f) else { return }
    
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let jscProfile = Profile(
    processArguments: ["--validateOptions=true",
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
                       "--reprl"],
    
    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    codePrefix: """
                function placeholder(){}
                function main() {
                """,

    codeSuffix: """
                gc();
                }
                noDFG(main);
                noFTL(main);
                main();
                """,

    ecmaVersion: ECMAScriptVersion.es6,

    crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: WeightedList<CodeGenerator>([
        (ForceDFGCompilationGenerator, 5),
        (ForceFTLCompilationGenerator, 5),
    ]),

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],

    additionalBuiltins: [
        "gc"                  : .function([] => .undefined),
        "transferArrayBuffer" : .function([.plain(.jsArrayBuffer)] => .undefined),
        "noInline"            : .function([.plain(.function())] => .undefined),
        "noFTL"               : .function([.plain(.function())] => .undefined),
        "createGlobalObject"  : .function([] => .object()),
        "placeholder"         : .function([] => .undefined),
        "OSRExit"             : .function([] => .unknown),
        "drainMicrotasks"     : .function([] => .unknown),
        "runString"           : .function([.plain(.jsString)] => .unknown),
        "makeMasquerader"     : .function([] => .unknown),
        "fullGC"              : .function([] => .undefined),
        "edenGC"              : .function([] => .undefined),
        "fiatInt52"           : .function([.plain(.number)] => .number),
        "forceGCSlowPaths"    : .function([] => .unknown),
        "ensureArrayStorage"  : .function([] => .unknown),
    ]
)
