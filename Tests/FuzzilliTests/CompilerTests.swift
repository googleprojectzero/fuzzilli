// Copyright 2023 Google LLC
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
import Testing

@testable import Fuzzilli

/// Compiler testsuite.
///
/// This testcase runs a number of "end-to-end" compiler tests using the .js files located in the CompilerTests/ directory:
/// For every such JavaScript testcase:
///  - The original code is executed inside a JavaScript engine (e.g. node.js) and the output recorded
///  - The code is parsed into an AST, then compiled to FuzzIL
///  - The resulting FuzzIL program is lifted back to JavaScript
///  - The new JavaScript code is again executed inside the same engine and the output again recorded
///  - The test passes if there are no errors along the way and if the output of both executions is identical
@Suite(.enabled(if: shouldRunCompilerTests()))
struct CompilerTests {
    let testcases: CompilerTestcases

    init() throws {
        self.testcases = try CompilerTestcases()
    }

    @Test func testFuzzILCompiler() throws {
        for testcasePath in testcases.paths {
            let testName = URL(fileURLWithPath: testcasePath).lastPathComponent

            // Execute the original code and record the output.
            let result1 = try testcases.nodejs.executeScript(at: URL(fileURLWithPath: testcasePath))
            guard result1.isSuccess else {
                Issue.record("TestCase \(testName) failed to execute. Output:\n\(result1.output)")
                continue
            }

            // Compile the JavaScript code to FuzzIL...
            guard let program = testcases.compile(testcaseAt: testcasePath) else { continue }

            // ... then lift it back to JavaScript and execute it again.
            guard
                let output = try testcases.execute(
                    testcases.lifter.lift(program),
                    describedAs: "TestCase \(testName) after compiling and lifting")
            else { continue }

            // The output of both executions must be identical.
            #expect(
                result1.output == output,
                "Testcase \(testName) failed.\nExpected output:\n\(result1.output)\nActual output:\n\(output)"
            )
        }
    }

    @Test func testInvalidDestructuredUsing() throws {
        // 1. Object destructuring with using: for (using {x} of y)
        let script1 = "for (using {x} of [{}]) {}"
        let error1 = try #require(throws: JavaScriptParser.ParserError.self) {
            try compile(script: script1)
        }
        guard case .parsingFailed(let message1) = error1 else {
            Issue.record("Expected parsingFailed, got \(error1)")
            return
        }
        #expect(message1.contains("SyntaxError") || message1.contains("Assertion failed"))

        // 2. Destructuring with using is forbidden in ECMAScript: { using {x} = {}; }
        let script2 = "{ using {x} = {}; }"
        let error2 = try #require(throws: JavaScriptParser.ParserError.self) {
            try compile(script: script2)
        }
        guard case .parsingFailed(let message2) = error2 else {
            Issue.record("Expected parsingFailed, got \(error2)")
            return
        }
        #expect(message2.contains("SyntaxError"))
    }

    @Test func testArrayExceedingMaxElementsThrows() throws {
        // Array literals with more elements than can fit in FuzzIL (> UInt16.max)
        // must throw CompilerError rather than crashing with a runtime integer overflow.
        // Store the element in a JS variable so each array element reuses the same
        // FuzzIL variable instead of emitting a LoadInteger instruction per element.
        let script =
            "const v = 0; const a = [" + Array(repeating: "v", count: 65536).joined(separator: ", ")
            + "];"
        #expect(throws: JavaScriptCompiler.CompilerError.self) {
            try compile(script: script)
        }
    }

    private func compile(script: String) throws -> Program {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".js")
        try script.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let ast = try testcases.parser.parse(tempFile.path)
        return try testcases.compiler.compile(ast)
    }

    public enum TestError: Error {
        case parserError(String)
    }

}
