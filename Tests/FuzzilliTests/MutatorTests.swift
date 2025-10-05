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

        XCTAssertEqual(originalEndTypeGroupInstructions.count, 1)
        XCTAssertEqual(originalEndTypeGroupInstructions[0].numInputs, 1)

        let spliceMutator = SpliceMutator()

        let candidates = prog.code.filter { instr in spliceMutator.canMutate(instr) == true }
        XCTAssertEqual(candidates.count, 1)

        let mutatedProg = spliceMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(newEndTypeGroupInstructions.count, 1)
        XCTAssertGreaterThan(newEndTypeGroupInstructions[0].numInputs, 1)
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

        XCTAssertEqual(originalEndTypeGroupInstructions.count, 1)
        XCTAssertEqual(originalEndTypeGroupInstructions[0].numInputs, 1)

        let codeGenMutator = CodeGenMutator()

        let candidates = prog.code.filter { instr in codeGenMutator.canMutate(instr) == true }
        XCTAssertEqual(candidates.count, 1)

        let mutatedProg = codeGenMutator.mutate(prog, using: b, for: fuzzer)!

        let newEndTypeGroupInstructions = mutatedProg.code.filter { instr in
            instr.op is WasmEndTypeGroup
        }

        XCTAssertEqual(newEndTypeGroupInstructions.count, 1)
        XCTAssertGreaterThan(newEndTypeGroupInstructions[0].numInputs, 1)
    }

    func testCodeGenMutatorNamedStrings() {
        // A generator that deterministically generates a different value each time.
        var called = false
        func generateString() -> String {
            if called {
                return "newValue"
            } else {
                called = true
                return "originalValue"
            }
        }
        let mockNamedString = ILType.namedString(ofName: "NamedString");

        let env = JavaScriptEnvironment()
        env.addNamedStringGenerator(forType: mockNamedString, with: generateString)

        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, environment: env)
        let b = fuzzer.makeBuilder()

        // We need a minimum number of visible variables for codeGeneration.
        b.loadInt(1)
        b.loadInt(2)

        let _ = b.findOrGenerateType(mockNamedString)
        XCTAssert(called)

        let prog = b.finalize()

        let originalLoadInstruction = prog.code.filter { instr in
            instr.op is LoadString
        }

        XCTAssertEqual(originalLoadInstruction.count, 1)
        let originalLoad = originalLoadInstruction[0].op as! LoadString
        XCTAssertEqual(originalLoad.value, "originalValue")

        // Mutator is probabalistic, try 10 times to ensure we are very likely
        // to hit the generateString call.
        let mutator = OperationMutator()
        for _ in 1...10 {
            let newBuilder = fuzzer.makeBuilder()
            newBuilder.adopting(from: prog) {
                mutator.mutate(originalLoadInstruction[0], newBuilder)
            }

            let mutatedProg = newBuilder.finalize()

            let newLoadInstruction = mutatedProg.code.filter { instr in
                instr.op is LoadString
            }

            XCTAssertEqual(newLoadInstruction.count, 1)
            let newLoad = newLoadInstruction[0].op as! LoadString
            if newLoad.value == "newValue" {
                return;
            }
        }
        XCTFail("Mutator ran 10 times without rerunning custom string generator")
    }
}
