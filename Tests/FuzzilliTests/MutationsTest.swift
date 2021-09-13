// Copyright 2020 Google LLC
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
@testable import Fuzzilli

extension BaseInstructionMutator {
    func mockMutate(_ program: Program, for fuzzer: Fuzzer, at index: Int) -> Program {
        beginMutation(of: program)
        let b = fuzzer.makeBuilder()
        b.adopting(from: program) {
            for instr in program.code {
                if instr.index == index {
                    mutate(instr, b)
                } else {
                    b.adopt(instr, keepTypes: true)
                }
            }
        }

        return b.finalize()
    }
}

class MutationsTests: XCTestCase {

    func testPrepareMutationRuntimeTypes() {
        let engine = MutationEngine(numConsecutiveMutations: 5)
        let fuzzer = makeMockFuzzer(engine: engine)

        let b = fuzzer.makeBuilder()
        b.loadInt(47)
        b.loadString("foobar")
        engine.setPrefix(b.finalize())

        let x = b.loadInt(42)
        b.beginIf(b.loadBool(true)) {
            b.reassign(x, to: b.loadFloat(1.1))
        }
        b.beginElse() {
            b.reassign(x, to: b.loadString("test"))
        }
        b.endIf()
        let program = b.finalize()
        // set some runtime types and see how they change after prepareForMutation call
        program.types = ProgramTypes(
            from: VariableMap([.number, .boolean, .float]),
            in: program,
            quality: .runtime
        )

        let preparedProgram = engine.prepareForMutation(program)
        let expectedTypes = ProgramTypes(
            from: VariableMap([2: .number, 3: .boolean, 4: .float]),
            in: preparedProgram,
            quality: .runtime
        )
        
        XCTAssertEqual(preparedProgram.types.onlyRuntimeTypes(), expectedTypes)
    }

    func testInputMutatorRuntimeTypes() {
        let fuzzer = makeMockFuzzer()

        let b = fuzzer.makeBuilder()
        b.loadString("test")
        let v3 = b.binary(b.loadInt(1), b.loadInt(2), with: .Add)
        b.unary(.BitwiseNot, v3)
        let program = b.finalize()
        var types: [Type?] = [.string, .integer, .integer, .integer, .integer]
        program.types = ProgramTypes(from: VariableMap(types), in: program, quality: .runtime)

        // Mutate only 3rd instruction
        let mutatedProgram = InputMutator(isTypeAware: false).mockMutate(program, for: fuzzer, at: 3)

        // v3 was mutated, we should discard this type
        // v4 depends on mutated v3, but for now we keep its type
        types[3] = nil
        // Assert only runtime types changes
        XCTAssertEqual(
            mutatedProgram.types.onlyRuntimeTypes(),
            ProgramTypes(from: VariableMap(types), in: mutatedProgram, quality: .runtime)
        )
    }
}

extension MutationsTests {
    static var allTests : [(String, (MutationsTests) -> () throws -> Void)] {
        return [
            ("testPrepareMutationRuntimeTypes", testPrepareMutationRuntimeTypes),
            ("testInputMutatorRuntimeTypes", testInputMutatorRuntimeTypes),
        ]
    }
}
