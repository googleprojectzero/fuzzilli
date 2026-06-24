// Copyright 2026 Google LLC
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

public struct BinaryenRunner {
    /// List of experimental Wasm GC and other feature flags passed to wasm-opt
    public static let featureArguments = [
        "--enable-gc",
        "--enable-reference-types",
        "--enable-typed-function-references",
        "--enable-sign-ext",
        "--enable-threads",
        "--enable-mutable-globals",
        "--enable-nontrapping-float-to-int",
        "--enable-simd",
        "--enable-bulk-memory",
        "--enable-bulk-memory-opt",
        "--enable-exception-handling",
        "--enable-tail-call",
        "--enable-multivalue",
        "--enable-memory64",
        "--enable-relaxed-simd",
        "--enable-extended-const",
        "--enable-multimemory",
        "--enable-custom-descriptors",
        "--enable-multibyte",
        "--enable-relaxed-atomics",
    ]

    struct BinaryenError: Error, CustomStringConvertible {
        let description: String
    }

    /// Internal process executor for wasm-opt (restored from BinaryenWasmGenerator)
    private static func runWasmOpt(wasmOptPath: String, arguments: [String]) -> Result<
        String, BinaryenError
    > {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wasmOptPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutDataBuffer = OutputBuffer()
        let stderrDataBuffer = OutputBuffer()
        let readGroup = DispatchGroup()

        setupConcurrentRead(from: stdoutPipe, into: stdoutDataBuffer, group: readGroup)
        setupConcurrentRead(from: stderrPipe, into: stderrDataBuffer, group: readGroup)

        let timeout: TimeInterval = 1.0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        timer.resume()
        defer {
            timer.cancel()
        }

        do {
            try process.run()
            process.waitUntilExit()
            readGroup.wait()
        } catch {
            return .failure(BinaryenError(description: "Failed to run wasm-opt: \(error)"))
        }

        guard let stdoutStr = String(data: stdoutDataBuffer.currentData, encoding: .utf8) else {
            return .failure(BinaryenError(description: "stdout not a valid utf8 string"))
        }

        if process.terminationStatus != 0 {
            let stderrStr = String(data: stderrDataBuffer.currentData, encoding: .utf8) ?? ""
            return .failure(
                BinaryenError(
                    description:
                        "wasm-opt failed with status \(process.terminationStatus). Stderr:\n\(stderrStr)\nStdout:\n\(stdoutStr)"
                ))
        }

        return .success(stdoutStr)
    }

    /// Consolidates file management and executes wasm-opt
    public static func runWasmOptWithTempFiles(
        fuzzer: Fuzzer,
        inputBytes: [UInt8]? = nil,
        extraArguments: [String]
    ) -> (outputBytes: [UInt8], stdout: String) {
        let fileManager = FileManager.default
        guard let wasmOptPath = fuzzer.config.wasmOptPath else {
            fatalError("BinaryenRunner: wasm-opt path not configured")
        }

        let tempDir: String
        if let storagePath = fuzzer.config.storagePath {
            tempDir = storagePath + "/binaryen_temp"
        } else {
            tempDir = FileManager.default.temporaryDirectory.path + "/binaryen_temp"
        }

        // Ensure temp dir exists
        try! fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let seedFile = tempDir + "/seed-\(uuid).bin"
        let outputFile = tempDir + "/output-\(uuid).wasm"
        let inputFile = tempDir + "/input-\(uuid).wasm"

        defer {
            try? fileManager.removeItem(atPath: seedFile)
            try? fileManager.removeItem(atPath: outputFile)
            try? fileManager.removeItem(atPath: inputFile)
        }

        // Generate random bytes for seed and write to file
        let seedSize = Int.random(in: 128...4096)
        let seedBytes = (0..<seedSize).map { _ in UInt8.random(in: 0...255) }
        try! Data(seedBytes).write(to: URL(fileURLWithPath: seedFile))

        var arguments = ["-ttf", seedFile, "-o", outputFile, "--fuzz-against-js", "-g"]

        // Write input file if mutating
        if let input = inputBytes {
            try! Data(input).write(to: URL(fileURLWithPath: inputFile))
            arguments += ["-if", inputFile]
        }

        arguments += extraArguments + featureArguments

        let stdout: String
        switch runWasmOpt(wasmOptPath: wasmOptPath, arguments: arguments) {
        case .success(let output):
            stdout = output
        case .failure(let error):
            fatalError("BinaryenRunner: wasm-opt failed: \(error)")
        }

        let outputBytes = try! Data(contentsOf: URL(fileURLWithPath: outputFile))
        return ([UInt8](outputBytes), stdout)
    }
}
