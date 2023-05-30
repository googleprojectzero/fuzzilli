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

/// This class wraps a NodeJS executable and allows executing JavaScript code with it.
public class NodeJS {
    /// Path to the node.js binary.
    let nodejsExecutablePath: String

    /// Prefix to execute before every JavaScript testcase. Its main task is to define the `output` function.
    let prefix = Data("const output = console.log;\n".utf8)

    public init?() {
        if let path = NodeJS.findNodeJsExecutable() {
            self.nodejsExecutablePath = path
        } else {
            return nil
        }
    }

    /// Executes the JavaScript script using the configured engine and returns the stdout.
    public func executeScript(_ script: String) throws -> (exitcode: Int32, output: String) {
        return try execute(nodejsExecutablePath, withInput: prefix + script.data(using: .utf8)!, withArguments: ["--allow-natives-syntax"])
    }

    /// Executes the JavaScript script at the specified path using the configured engine and returns the stdout.
    public func executeScript(at url: URL) throws -> (exitcode: Int32, output: String) {
        let script = try Data(contentsOf: url)
        return try execute(nodejsExecutablePath, withInput: prefix + script, withArguments: ["--allow-natives-syntax"])
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

    /// Looks for an executable named `node` in the $PATH and, if found, returns it.
    private static func findNodeJsExecutable() -> String? {
        if let pathVar = ProcessInfo.processInfo.environment["PATH"] {
            var directories = pathVar.split(separator: ":")
            // Also append the homebrew binary path since it may not be in $PATH, especially inside XCode.
            directories.append("/opt/homebrew/bin")
            for directory in directories {
                let path = String(directory + "/node")
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
}

