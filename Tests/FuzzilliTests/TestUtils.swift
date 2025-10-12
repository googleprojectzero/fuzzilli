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

import Foundation
import XCTest
@testable import Fuzzilli

extension Program: @retroactive Equatable {
    // Fairly expensive equality testing, but it's only needed for testing anyway... :)
    public static func == (lhs: Program, rhs: Program) -> Bool {
        // Quick check, they have to be of equal length.
        guard lhs.code.count == rhs.code.count else {
            return false
        }

        do {
            for (instrA, instrB) in zip(lhs.code, rhs.code) {
                // We need to compare on a binary level as the Protobuf datastructure can contain floats for i.e. LoadFloat and Constf64 instructions. If those contain a NaN, they won't be equal to one another although we only care about their binary representation being equal.
                // This might also flake and not deterministically serialize super small floats(?)
                let instrASerialized = try instrA.asProtobuf().serializedData()
                let instrBSerialized = try instrB.asProtobuf().serializedData()
                if instrASerialized != instrBSerialized {
                    return false
                }
            }

            return true
        } catch {
            fatalError("foo")
        }
    }
}

// Convenience variable constructor
func v(_ n: Int) -> Variable {
    return Variable(number: n)
}

func GetJavaScriptExecutorOrSkipTest() throws -> JavaScriptExecutor {
    guard let runner = JavaScriptExecutor() else {
        throw XCTSkip("Could not find js shell executable. Install Node.js (or if you want to use a different shell, modify the FUZZILLI_TEST_SHELL variable).")
    }
    return runner
}

func GetJavaScriptExecutorOrSkipTest(type: JavaScriptExecutor.ExecutorType, withArguments args: [String]) throws -> JavaScriptExecutor {
    guard let runner = JavaScriptExecutor(type: type, withArguments: args) else {
        throw XCTSkip("Could not find js shell executable. Install Node.js (or if you want to use a different shell, modify the FUZZILLI_TEST_SHELL variable).")
    }
    return runner
}


func buildAndLiftProgram(withLiftingOptions: LiftingOptions, buildFunc: (ProgramBuilder) -> ()) -> String {
    let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)

    // We have to use the proper JavaScriptEnvironment here.
    // This ensures that we use the available builtins.
    let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
    let b = fuzzer.makeBuilder()

    buildFunc(b)

    // AssertThat prog == Deserialize(Serilize(prog))
    let prog = b.finalize()
    let serializedBytes = try! prog.asProtobuf().serializedData()
    let deserialized = try! Program(from: Fuzzilli_Protobuf_Program(serializedBytes: serializedBytes))
    XCTAssertEqual(prog, deserialized)

    return fuzzer.lifter.lift(prog, withOptions: withLiftingOptions)
}

func buildAndLiftProgram(buildFunc: (ProgramBuilder) -> ()) -> String {
    return buildAndLiftProgram(withLiftingOptions: [], buildFunc: buildFunc)
}

