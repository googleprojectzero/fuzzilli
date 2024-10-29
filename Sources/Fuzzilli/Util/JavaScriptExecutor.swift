// Copyright 2024 Google LLC
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

public class JavaScriptExecutor {
    /// Path to the js shell binary.
    let executablePath: String

    /// Prefix to execute before every JavaScript testcase. Its main task is to define the `output` function.
    let prefix = Data("const output = console.log;\n".utf8)

    /// The js shell mode for this JavaScriptExecutor
    public enum ExecutorType {
        // The default behavior, we will try to use the user supplied binary first.
        // And fall back to node if we don't find anything supplied through FUZZILLI_TEST_SHELL
        case any
        // Try to find the node binary (useful if node modules are required) or fail.
        case nodejs
        // Try to find the user supplied binary or fail
        case user
    }

    let arguments: [String]

    /// Depending on the type this constructor will try to find the requested shell or fail
    public init?(type: ExecutorType = .any, withArguments maybeArguments: [String]? = nil) {
        self.arguments = maybeArguments ?? []
        let path: String?

        switch type {
            case .any:
                path = JavaScriptExecutor.findJsShellExecutable() ?? JavaScriptExecutor.findNodeJsExecutable()
            case .nodejs:
                path = JavaScriptExecutor.findNodeJsExecutable()
            case .user:
                path = JavaScriptExecutor.findJsShellExecutable()
        }

        if path == nil {
            return nil
        }

        self.executablePath = path!
    }

    /// Executes the JavaScript script using the configured engine and returns the stdout.
    public func executeScript(_ script: String, withTimeout timeout: TimeInterval? = nil) throws -> Result {
        return try execute(executablePath, withInput: prefix + script.data(using: .utf8)!, withArguments: self.arguments, timeout: timeout)
    }

    /// Executes the JavaScript script at the specified path using the configured engine and returns the stdout.
    public func executeScript(at url: URL, withTimeout timeout: TimeInterval? = nil) throws -> Result {
        let script = try Data(contentsOf: url)
        return try execute(executablePath, withInput: prefix + script, withArguments: self.arguments, timeout: timeout)
    }

    func execute(_ path: String, withInput input: Data = Data(), withArguments arguments: [String] = [], timeout maybeTimeout: TimeInterval? = nil) throws -> Result {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        // Write input into file.
        let url = FileManager.default.temporaryDirectory
               .appendingPathComponent(UUID().uuidString)
               .appendingPathExtension("js")

        try input.write(to: url)
        // Close stdin
        try inputPipe.fileHandleForWriting.close()

        // Execute the subprocess.
        let task = Process()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        task.arguments = arguments + [url.path]
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
                // Properly kill the task now with SIGKILL as it might be stuck
                // in Wasm, where SIGTERM is not enough.
                kill(task.processIdentifier, SIGKILL)
                timedOut = true
            }
        }

        task.waitUntilExit()

        // Delete the temporary file
        try FileManager.default.removeItem(at: url)

        // Fetch and return the output.
        var output = ""
        if let data = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            output = data
        } else {
            output = "Process output is not valid UTF-8"
        }
        var error = ""
        if let data = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
            error = data
        } else {
            error = "Process stderr is not valid UTF-8"
        }
        var outcome: Result.Outcome
        if timedOut {
            outcome = .timedOut
            output += "\nError: Timed out"
        } else {
            outcome = .terminated(status: task.terminationStatus)
        }
        return Result(outcome: outcome, output: output, error: error)
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

    /// Tries to find a JS shell that is usable for testing.
    private static func findJsShellExecutable() -> String? {
        return ProcessInfo.processInfo.environment["FUZZILLI_TEST_SHELL"]
    }

    /// The Result of a JavaScript Execution, the exit code and any associated output.
    public struct Result {
        enum Outcome: Equatable {
            case terminated(status: Int32)
            case timedOut
        }

        let outcome: Outcome
        let output: String
        let error: String

        var isSuccess: Bool {
            return outcome == .terminated(status: 0)
        }
        var isFailure: Bool {
            return !isSuccess
        }
        var isTimeOut: Bool {
            return outcome == .timedOut
        }
    }
}
