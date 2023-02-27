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

import XCTest
import Foundation
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
    /// Path to the node.js binary. The testcase will first look for the `node` binary in the $PATH and store it here.
    /// Will be used to execute testcases and to run the JavaScript parser to obtain an AST from JavaScript code.
    var nodejsPath = ""

    /// Prefix to execute before every JavaScript testcase. Its main task is to define the `output` function.
    let prefix = Data("const output = console.log;\n".utf8)

    func testFuzzILCompiler() throws {
        // Initialize the parser. This can fail if no node.js executable is found or if the
        // parser's node.js dependencies are not installed. In that case, skip these tests.
        guard let parser = JavaScriptParser() else {
            throw XCTSkip("The JavaScript parser does not appear to be working. See Sources/Fuzzilli/Compiler/Parser/README.md for details on how to set up the parser.")
        }

        // Reuse the node.js executable used by the parser to execute the testcases.
        nodejsPath = parser.nodejsExecutablePath

        let compiler = JavaScriptCompiler()

        let lifter = JavaScriptLifter(ecmaVersion: .es6)

        for testcasePath in enumerateAllTestcases() {
            let testName = URL(fileURLWithPath: testcasePath).lastPathComponent

            // Execute the original code and record the output.
            let (exitcode1, expectedOutput) = try executeScript(testcasePath)
            guard exitcode1 == 0 else {
                XCTFail("Tescase \(testName) failed to execute. Output:\n\(expectedOutput)")
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
            let outputPath = writeTemporaryFile(withContent: script)
            let (exitcode2, actualOutput) = try executeScript(outputPath)
            try FileManager.default.removeItem(atPath: outputPath)
            guard exitcode2 == 0 else {
                XCTFail("Tescase \(testName) failed to execute after compiling and lifting. Output:\n\(actualOutput)")
                continue
            }

            // The output of both executions must be identical.
            if expectedOutput != actualOutput {
                XCTFail("Testcase \(testName) failed.\nExpected output:\n\(expectedOutput)\nActual output:\n\(actualOutput)")
            }
        }
    }

    /// Executes the JavaScript script at the specified path using the configured engine and returns the stdout.
    private func executeScript(_ path: String) throws -> (exitcode: Int32, output: String) {
        let script = try Data(contentsOf: URL(fileURLWithPath: path))
        return try execute(nodejsPath, withInput: prefix + script, withArguments: ["--allow-natives-syntax"])
    }

    func execute(_ path: String, withInput input: Data = Data(), withArguments arguments: [String] = []) throws -> (exitcode: Int32, output: String) {
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        // Write input into input pipe, then close it.
        try inputPipe.fileHandleForWriting.write(contentsOf: input)
        try inputPipe.fileHandleForWriting.close()

        // Execute the subprocess.
        let task = Process()
        task.standardOutput = outputPipe
        task.standardError = outputPipe
        task.arguments = arguments
        task.executableURL = URL(fileURLWithPath: path)
        task.standardInput = inputPipe
        try task.run()
        task.waitUntilExit()

        // Fetch and return the output.
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(data: data, encoding: .utf8)!)
    }

    /// Returns the absolute path of a random file inside the temporary directory. The file is not created.
    private func getTemporaryFilename(withExtension ext: String) -> String {
        return FileManager.default.temporaryDirectory.path + "/" + UUID().uuidString + "." + ext
    }

    /// Writes the given data to a newly created temporary file and returns the absolute path to that file.
    private func writeTemporaryFile(withContent content: String) -> String {
        let path = getTemporaryFilename(withExtension: "js")
        FileManager.default.createFile(atPath: path, contents: Data(content.utf8))
        return path
    }

    /// Returns the absolute paths of all .js compiler testcases.
    private func enumerateAllTestcases() -> [String] {
        return Bundle.module.paths(forResourcesOfType: "js", inDirectory: "CompilerTests")
    }

    public enum TestError: Error {
        case parserError(String)
    }

}
