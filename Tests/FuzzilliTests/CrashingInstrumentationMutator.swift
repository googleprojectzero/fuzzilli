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

import Foundation
@testable import Fuzzilli

// This mutator generates a crashing instrumented program.
// It is used for testing: the process()'d program should be
// reported instead of the instrument()'d program, if that program
// also crashes, in order to enable better minimization.

class CrashingInstrumentationMutator: RuntimeAssistedMutator {
    private let shouldProcessedProgramCrash: Bool

    init(shouldProcessedProgramCrash: Bool = true) {
        self.shouldProcessedProgramCrash = shouldProcessedProgramCrash
        super.init("CrashingInstrumentationMutator", verbose: true)
    }

    override func instrument(_ program: Program, for fuzzer: Fuzzer) -> Program? {
        let b = fuzzer.makeBuilder()
        b.eval("fuzzilli('FUZZILLI_CRASH', 0)");

        // Add a JsInternalOperation to satisfy the assertion in RuntimeAssistedMutator.swift:89
        let v = b.loadInt(42)
        b.doPrint(v)

        b.append(program)
        return b.finalize()
    }


    override func process(_ output: String, ofInstrumentedProgram instrumentedProgram: Program, using b: ProgramBuilder) -> (Program?, Outcome) {
        // Purpose of this print: Distinguish crashes originating from instrument() and process().
        let printFct = b.createNamedVariable(forBuiltin: "print")
        b.callFunction(printFct, withArgs: [b.loadString("This is the processed program")])
        if self.shouldProcessedProgramCrash {
            b.append(instrumentedProgram)
        }
        return (b.finalize(), .success)
    }

    override func logAdditionalStatistics() {}
}
