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
import XCTest

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
class CompilerTests: XCTestCase {
    var nodejs: JavaScriptExecutor!
    var parser: JavaScriptParser!
    var compiler: JavaScriptCompiler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard
            let executor = JavaScriptExecutor(
                type: .nodejs, withArguments: ["--allow-natives-syntax"])
        else {
            throw XCTSkip(
                "Could not find NodeJS executable. See Sources/Fuzzilli/Compiler/Parser/README.md for details on how to set up the parser."
            )
        }
        self.nodejs = executor

        guard let parser = JavaScriptParser(executor: executor) else {
            throw XCTSkip(
                "The JavaScript parser does not appear to be working. See Sources/Fuzzilli/Compiler/Parser/README.md for details on how to set up the parser."
            )
        }
        self.parser = parser
        self.compiler = JavaScriptCompiler()
    }

    func testFuzzILCompiler() throws {
        let lifter = JavaScriptLifter(ecmaVersion: .es6, environment: JavaScriptEnvironment())

        for testcasePath in enumerateAllTestcases() {
            let testName = URL(fileURLWithPath: testcasePath).lastPathComponent

            // Execute the original code and record the output.
            let result1 = try nodejs.executeScript(at: URL(fileURLWithPath: testcasePath))
            guard result1.isSuccess else {
                XCTFail("TestCase \(testName) failed to execute. Output:\n\(result1.output)")
                continue
            }

            // Compile the JavaScript code to FuzzIL...
            guard let ast = try? parser.parse(testcasePath) else {
                XCTFail("Could not parse \(testName)")
                continue
            }
            guard let program = try? compiler.compile(ast) else {
                XCTFail("Could not compile \(testName)")
                continue
            }

            // ... then lift it back to JavaScript and execute it again.
            let script = lifter.lift(program)
            let result2 = try nodejs.executeScript(script)
            guard result2.isSuccess else {
                XCTFail(
                    "TestCase \(testName) failed to execute after compiling and lifting. Output:\n\(result2.output)\nScript:\n\(script)"
                )
                continue
            }

            // The output of both executions must be identical.
            if result1.output != result2.output {
                XCTFail(
                    "Testcase \(testName) failed.\nExpected output:\n\(result1.output)\nActual output:\n\(result2.output)"
                )
            }
        }
    }

    func testInvalidDestructuredUsing() throws {
        // 1. Object destructuring with using: for (using {x} of y)
        let script1 = "for (using {x} of [{}]) {}"
        XCTAssertThrowsError(try compile(script: script1)) {
            error in
            guard let parserError = error as? JavaScriptParser.ParserError else {
                return XCTFail("Expected JavaScriptParser.ParserError, got \(error)")
            }
            guard case .parsingFailed(let message) = parserError else {
                return XCTFail("Expected parsingFailed, got \(parserError)")
            }
            XCTAssertTrue(message.contains("SyntaxError") || message.contains("Assertion failed"))
        }

        // 2. Destructuring with using is forbidden in ECMAScript: { using {x} = {}; }
        // Note: `for (using [x] of [[]])` is structurally valid JavaScript because using is not e reserved keyword!
        // Hence, `using [x]` is simply parsed as the index 'x' of the array 'using'.
        // (reassignment of using[x]) but `using {x}` inside a block is a true SyntaxError
        let script2 = "{ using {x} = {}; }"
        XCTAssertThrowsError(try compile(script: script2)) {
            error in
            guard let parserError = error as? JavaScriptParser.ParserError else {
                return XCTFail("Expected JavaScriptParser.ParserError, got \(error)")
            }
            guard case .parsingFailed(let message) = parserError else {
                return XCTFail("Expected parsingFailed, got \(parserError)")
            }
            XCTAssertTrue(message.contains("SyntaxError"))
        }

    }

    private func compile(script: String) throws -> Program {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".js")
        try script.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let ast = try parser.parse(tempFile.path)
        return try compiler.compile(ast)
    }

    /// Returns the absolute paths of all .js compiler testcases.
    private func enumerateAllTestcases() -> [String] {
        return Bundle.module.paths(forResourcesOfType: "js", inDirectory: "CompilerTests")
    }

    public enum TestError: Error {
        case parserError(String)
    }

}
