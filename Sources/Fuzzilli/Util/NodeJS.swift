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

    /// The result of executing a Script.
    public struct Result {
        enum Outcome {
            case terminated(status: Int32)
            case timedOut
        }

        let outcome: Outcome
        let output: String

        var isSuccess: Bool {
            switch outcome {
            case .terminated(status: let status):
                return status == 0
            case .timedOut:
                return false
            }
        }
        var isFailure: Bool {
            return !isSuccess
        }
    }

    /// Executes the JavaScript script using the configured engine and returns the stdout.
    public func executeScript(_ script: String, withTimeout timeout: TimeInterval? = nil) throws -> Result {
        return try execute(nodejsExecutablePath, withInput: prefix + script.data(using: .utf8)!, withArguments: ["--allow-natives-syntax"], timeout: timeout)
    }

    /// Executes the JavaScript script at the specified path using the configured engine and returns the stdout.
    public func executeScript(at url: URL, withTimeout timeout: TimeInterval? = nil) throws -> Result {
        let script = try Data(contentsOf: url)
        return try execute(nodejsExecutablePath, withInput: prefix + script, withArguments: ["--allow-natives-syntax"], timeout: timeout)
    }

    func execute(_ path: String, withInput input: Data = Data(), withArguments arguments: [String] = [], timeout maybeTimeout: TimeInterval? = nil) throws -> Result {
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

        var timedOut = false
        if let timeout = maybeTimeout {
            let start = Date()
            while Date().timeIntervalSince(start) < timeout {
                Thread.sleep(forTimeInterval: 1 * Seconds)
                if !task.isRunning {
                    break
                }
            }
            if task.isRunning {
                task.terminate()
                timedOut = true
            }
        }

        task.waitUntilExit()

        // Fetch and return the output.
        var output = ""
        if let data = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            output = data
        } else {
            output = "Process output is not valid UTF-8"
        }
        var outcome: Result.Outcome
        if timedOut {
            outcome = .timedOut
            output += "\nError: Timed out"
        } else {
            outcome = .terminated(status: task.terminationStatus)
        }
        return Result(outcome: outcome, output: output)
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

