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

fileprivate func ForceDFGCompilationGenerator(_ b: ProgramBuilder) {
    let f = b.randVar(ofType: .function())
    let arguments = b.generateCallArguments(for: f)
    
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(10), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

fileprivate func ForceFTLCompilationGenerator(_ b: ProgramBuilder) {
    let f = b.randVar(ofType: .function())
    let arguments = b.generateCallArguments(for: f)
    
    b.forLoop(b.loadInt(0), .lessThan, b.loadInt(100), .Add, b.loadInt(1)) { _ in
        b.callFunction(f, withArgs: arguments)
    }
}

let jscProfile = Profile(
    processArguments: ["--validateOptions=true",
                       // Concurrency doesn't really benefit us, it makes things undeterministic and potentially slows us down since all cores are busy already.
                       "--useConcurrentJIT=false", "--useConcurrentGC=false",
                       // No need to call functions thousands of times before they are JIT compiled
                       "--thresholdForJITSoon=10",
                       "--thresholdForJITAfterWarmUp=10",
                       "--thresholdForOptimizeAfterWarmUp=100",
                       "--thresholdForOptimizeAfterLongWarmUp=100",
                       "--thresholdForOptimizeAfterLongWarmUp=100",
                       "--thresholdForFTLOptimizeAfterWarmUp=1000",
                       "--thresholdForFTLOptimizeSoon=1000",
                       // This might catch some memory corruption that would otherwise stay undetected
                       "--gcAtEnd=true",
                       // Our client-side REPRL implementation currently requires a dummy filename
                       "fuzzcode.js"],
    
    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],

    codePrefix: """
                function main() {
                """,
    
    codeSuffix: """
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
        
    additionalBuiltins: [
        "gc"                  : .function([] => .undefined),
        "transferArrayBuffer" : .function([.jsArrayBuffer] => .undefined),
        "noInline"            : .function([.function()] => .undefined),
        "noFTL"               : .function([.function()] => .undefined),
        "createGlobalObject"  : .function([] => .object()),
    ]
)
