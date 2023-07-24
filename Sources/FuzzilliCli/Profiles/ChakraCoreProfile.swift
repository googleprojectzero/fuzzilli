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

let chakraProfile = Profile(
    //getProcessArguments: { (randomizingArguments: Bool) -> [String] in
      processArgs: { (randomizingArguments: Bool) -> [String] in
	  var args = [
            "--maxinterpretcount=10",
            // No need to call functions thousands of times before they are JIT compiled
            "--maxsimplejitruncount=100",
            "-bgjit",
            "-oopjit",
            "-reprl",
            "fuzzcode.js"]

        return args
    },

    processEnv: ["UBSAN_OPTIONS":"handle_segv=0"],
    
    maxExecsBeforeRespawn: 1000,

    timeout: 250,

    codePrefix: """
                function classOf(object) {
                   var string = Object.prototype.toString.call(object);
                   return string.substring(8, string.length - 1);
                }

                function deepObjectEquals(a, b) {
                  var aProps = Object.keys(a);
                  aProps.sort();
                  var bProps = Object.keys(b);
                  bProps.sort();
                  if (!deepEquals(aProps, bProps)) {
                    return false;
                  }
                  for (var i = 0; i < aProps.length; i++) {
                    if (!deepEquals(a[aProps[i]], b[aProps[i]])) {
                      return false;
                    }
                  }
                  return true;
                }

                function deepEquals(a, b) {
                  if (a === b) {
                    if (a === 0) return (1 / a) === (1 / b);
                    return true;
                  }
                  if (typeof a != typeof b) return false;
                  if (typeof a == 'number') return (isNaN(a) && isNaN(b)) || (a===b);
                  if (typeof a !== 'object' && typeof a !== 'function' && typeof a !== 'symbol') return false;
                  var objectClass = classOf(a);
                  if (objectClass === 'Array') {
                    if (a.length != b.length) {
                      return false;
                    }
                    for (var i = 0; i < a.length; i++) {
                      if (!deepEquals(a[i], b[i])) return false;
                    }
                    return true;
                  }                
                  if (objectClass !== classOf(b)) return false;
                  if (objectClass === 'RegExp') {
                    return (a.toString() === b.toString());
                  }
                  if (objectClass === 'Function') return true;
                  
                  if (objectClass == 'String' || objectClass == 'Number' ||
                      objectClass == 'Boolean' || objectClass == 'Date') {
                    if (a.valueOf() !== b.valueOf()) return false;
                  }
                  return deepObjectEquals(a, b);
                }
                
                function opt(opt_param){
                """,

    codeSuffix: """
                }
                function main(){
                	let gflag = true;
                	let jit_a0 = opt(true);
                	let jit_a0_0 = opt(false);
                	for(let i=0;i<0x10;i++){opt(false);}
                	let jit_a2 = opt(true);
                	if (jit_a0 === undefined && jit_a2 === undefined) {
                    	opt(true);
                	} else {
                    	if (jit_a0_0===jit_a0 && !deepEquals(jit_a0, jit_a2)) {
                        	gflag = false;
                    	}
                	}
                	for(let i=0;i<0x200;i++){opt(false);}
                	let jit_a4 = opt(true);
                	if (jit_a0 === undefined && jit_a4 === undefined) {
                    	opt(true);
                	} else {
                    	if (gflag && jit_a0_0===jit_a0 && !deepEquals(jit_a0, jit_a4)) {
                        	fuzzilli('FUZZILLI_CRASH', 0);
                    	}
                	}
                }
                main();
                """,
                
	ecmaVersion: ECMAScriptVersion.es6,
	crashTests: ["fuzzilli('FUZZILLI_CRASH', 0)", "fuzzilli('FUZZILLI_CRASH', 1)", "fuzzilli('FUZZILLI_CRASH', 2)"],

    additionalCodeGenerators: [],

    additionalProgramTemplates: WeightedList<ProgramTemplate>([]),

    disabledCodeGenerators: [],
    
    additionalBuiltins: [
        "CollectGarbage"            : .function([] => .undefined),
    ]

)
