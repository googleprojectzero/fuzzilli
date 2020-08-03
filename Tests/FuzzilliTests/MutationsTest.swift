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

class MutationsTests: XCTestCase {

    func testPrepareMutationRuntimeTypes() {
        let fuzzer = makeMockFuzzer()
        var b = fuzzer.makeBuilder()
        b.phi(b.loadInt(47))
        fuzzer.engine.setPrefix(b.finalize())
        b = fuzzer.makeBuilder()
        let x = b.phi(b.loadInt(42))
        b.beginIf(b.loadBool(true)) {
            b.copy(b.loadFloat(1.1), to: x)
        }
        b.beginElse() {
            b.copy(b.loadString("test"), to: x)
        }
        b.endIf()
        let program = b.finalize()
        let types: [Type] = [.integer, .number, .boolean, .float]
        program.runtimeTypes = VariableMap<Type>(types)

        let preparedProgram = fuzzer.engine.prepareForMutation(program)
        XCTAssertEqual(preparedProgram.runtimeTypes, VariableMap<Type>([nil, nil] + types))
    }

    func testInputMutatorRuntimeTypes() {
        let fuzzer = makeMockFuzzer()
        let mutator = InputMutator()
        let b = fuzzer.makeBuilder()
        b.loadString("test")
        b.binary(b.loadInt(1), b.loadInt(2), with: .Add)
        let program = b.finalize()
        var types: [Type] = [.string, .integer, .integer, .integer]
        program.runtimeTypes = VariableMap<Type>(types)

        let mutatedProgram = mutator.mutate(program, for: fuzzer)!

        // last variable was mutated, we should discard this type
        types.removeLast()
        XCTAssertEqual(mutatedProgram.runtimeTypes, VariableMap<Type>(types))
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
