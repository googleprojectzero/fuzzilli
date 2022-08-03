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

import XCTest
@testable import Fuzzilli

class InliningTests: XCTestCase {
    func testBasicInlining() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        let f = b.buildPlainFunction(withSignature: FunctionSignature(withParameterCount: 3)) { args in
            b.buildIfElse(args[0], ifBody: {
                b.doReturn(value: args[1])
            }, elseBody: {
                b.doReturn(value: args[2])
            })
        }
        var a1 = b.loadBool(true)
        var a2 = b.loadInt(1337)
        var r = b.callFunction(f, withArgs: [a1, a2])
        b.unary(.BitwiseNot, r)

        let program = b.finalize()

        let reducer = InliningReducer()
        var inlinedCode = reducer.inline(f, in: program.code)

        // Must normalize the code after inlining.
        inlinedCode.normalize()

        XCTAssert(inlinedCode.isStaticallyValid())

        let inlinedProgram = Program(with: inlinedCode)

        let u: Variable

        // Resulting program should be:
        a1 = b.loadBool(true)
        a2 = b.loadInt(1337)
        u = b.loadUndefined()
        r = b.loadUndefined()
        b.buildIfElse(a1, ifBody: {
            b.reassign(r, to: a2)
        }, elseBody: {
            b.reassign(r, to: u)
        })
        b.unary(.BitwiseNot, r)

        let referenceProgram = b.finalize()

        XCTAssertEqual(inlinedProgram, referenceProgram)
    }
}

extension InliningTests {
    static var allTests : [(String, (InliningTests) -> () throws -> Void)] {
        return [
            ("testBasicInlining", testBasicInlining),
        ]
    }
}
