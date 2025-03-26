// Copyright 2025 Google LLC
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

import XCTest
import Testing
@testable import Fuzzilli

class MutatorTests: XCTestCase {
    func testSpliceMutatorWasmTypeGroups() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // Insert another sample that has a typegroup into the corpus
        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi64, mutability: true)
        })

        fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))

        // Now try the splice mutator

        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
        })

        let prog = b.finalize()

        let originalEndTypeGroupInstructions = prog.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssert(originalEndTypeGroupInstructions.count == 1)
        XCTAssert(originalEndTypeGroupInstructions[0].numInputs == 1)

        let spliceMutator = SpliceMutator()

        let candidates = prog.code.filter { instr in spliceMutator.canMutate(instr) == true }
        XCTAssert(candidates.count == 1)

        let mutatedProg = spliceMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssert(newEndTypeGroupInstructions.count == 1)
        XCTAssert(newEndTypeGroupInstructions[0].numInputs > 1)
    }

    func testCodeGenMutatorWasmTypeGroups() {
        let env = JavaScriptEnvironment()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // We need a minimum number of visible variables for codeGeneration.
        b.loadInt(1)
        b.loadInt(2)

        b.wasmDefineTypeGroup(recursiveGenerator: {
            b.wasmDefineArrayType(elementType: .wasmi32, mutability: true)
        })

        let prog = b.finalize()

        let originalEndTypeGroupInstructions = prog.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssert(originalEndTypeGroupInstructions.count == 1)
        XCTAssert(originalEndTypeGroupInstructions[0].numInputs == 1)

        let codeGenMutator = CodeGenMutator()

        let candidates = prog.code.filter { instr in codeGenMutator.canMutate(instr) == true }
        XCTAssert(candidates.count == 1)

        let mutatedProg = codeGenMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssert(newEndTypeGroupInstructions.count == 1)
        XCTAssert(newEndTypeGroupInstructions[0].numInputs > 1)
    }
}
