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

struct BinaryenError: Error, CustomStringConvertible {
    let description: String
}

private func runWasmOpt(wasmOptPath: String, arguments: [String]) -> Result<String, BinaryenError> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: wasmOptPath)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let stdoutData = OutputBuffer()
    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        stdoutData.append(handle.availableData)
    }

    let stderrData = OutputBuffer()
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        stderrData.append(handle.availableData)
    }

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
    } catch {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        return .failure(BinaryenError(description: "Failed to run wasm-opt: \(error)"))
    }

    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil

    let stdoutStr = String(data: stdoutData.currentData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
        let stderrStr = String(data: stderrData.currentData, encoding: .utf8) ?? ""
        return .failure(
            BinaryenError(
                description:
                    "wasm-opt failed with status \(process.terminationStatus). Stderr:\n\(stderrStr)\nStdout:\n\(stdoutStr)"
            ))
    }

    return .success(stdoutStr)
}

struct WasmBoundary: Decodable {
    struct Export: Decodable {
        let name: String
        let kind: String
        let type: ExportType?
    }

    enum ExportType: Decodable {
        case signature(FunctionSignature)
        case typeString(String)

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
                let typeStr = try? container.decode(String.self)
            {
                self = .typeString(typeStr)
            } else if let funcSig = try? FunctionSignature(from: decoder) {
                self = .signature(funcSig)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected String or FunctionSignature for ExportType"
                    )
                )
            }
        }
    }

    struct FunctionSignature: Decodable {
        let params: [String]
        let results: [String]
    }

    let exports: [Export]
}

private func mapBinaryenTypeToILType(_ typeStr: String) -> ILType {
    switch typeStr {
    case "i32": return .integer
    case "i64": return .bigint
    case "f32", "f64": return .float
    default:
        if typeStr.hasPrefix("null") || typeStr.hasPrefix("(null") {
            return .nullish
        }
        return .jsAnything
    }
}

public func runBinaryenWasmGenerator(b: ProgramBuilder) -> WasmModuleMetadata? {
    let fileManager = FileManager.default
    guard let wasmOptPath = b.fuzzer.config.wasmOptPath else {
        fatalError("wasm-opt path not configured")
    }

    let tempDir: String
    if let storagePath = b.fuzzer.config.storagePath {
        tempDir = storagePath + "/binaryen_temp"
    } else {
        tempDir = FileManager.default.temporaryDirectory.path + "/binaryen_temp"
    }

    // Ensure temp dir exists
    try? fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

    let uuid = UUID().uuidString
    let seedFile = tempDir + "/seed-\(uuid).bin"
    let outputWasmFile = tempDir + "/output-\(uuid).wasm"

    // 1. Generate random bytes for seed
    let seedSize = Int.random(in: 128...4096)
    let seedBytes = (0..<seedSize).map { _ in UInt8.random(in: 0...255) }
    do {
        try Data(seedBytes).write(to: URL(fileURLWithPath: seedFile))
    } catch {
        fatalError("BinaryenWasmGenerator: Failed to write seed file: \(error)")
    }

    defer {
        // Clean up files
        try? fileManager.removeItem(atPath: seedFile)
        try? fileManager.removeItem(atPath: outputWasmFile)
    }

    // 2. Run wasm-opt to generate mutated module in WASM format directly
    let arguments = [
        "-ttf", seedFile,
        "--print-boundary",
        "-o", outputWasmFile,
        "--fuzz-against-js",
        "-g",
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

    let jsonOutput: String
    switch runWasmOpt(wasmOptPath: wasmOptPath, arguments: arguments) {
    case .success(let output):
        jsonOutput = output
    case .failure(let error):
        fatalError("BinaryenWasmGenerator: wasm-opt failed: \(error)")
    }

    // 3. Read WASM bytes
    let wasmBytes: Data = try! Data(contentsOf: URL(fileURLWithPath: outputWasmFile))

    // 4. Parse JSON output and build WasmModuleMetadata dynamically
    let boundary: WasmBoundary = try! JSONDecoder().decode(
        WasmBoundary.self, from: Data(jsonOutput.utf8))

    var functions: [WasmModuleMetadata.FunctionExport] = []
    var globals: [String] = []
    var tables: [String] = []
    var tags: [String] = []

    for export in boundary.exports {
        switch export.kind {
        case "func":
            guard let type = export.type, case .signature(let sig) = type else {
                fatalError(
                    "BinaryenWasmGenerator: Export \(export.name) of kind 'func' is missing a function signature type"
                )
            }
            let params = sig.params.map { Parameter.plain(mapBinaryenTypeToILType($0)) }
            let results = sig.results.map(mapBinaryenTypeToILType)
            let returnType: ILType =
                if results.isEmpty {
                    .undefined
                } else if results.count == 1 {
                    results[0]
                } else {
                    .jsArray
                }
            let jsSig = params => returnType
            functions.append(WasmModuleMetadata.FunctionExport(name: export.name, signature: jsSig))

        case "global":
            globals.append(export.name)
        case "table":
            tables.append(export.name)
        case "tag":
            tags.append(export.name)
        default:
            break
        }
    }

    let metadata = WasmModuleMetadata(
        functions: functions, globals: globals, tables: tables, tags: tags)

    // Emit the RawWasmModule operation
    let instance = b.rawWasmModule(bytes: [UInt8](wasmBytes), metadata: metadata)

    // Emit a getProperty for the exports object to make it easier to use
    b.getProperty("exports", of: instance)

    return metadata
}

public let BinaryenWasmGenerator = CodeGenerator(
    "BinaryenWasmGenerator",
    inContext: .single(.javascript)
) { b in
    _ = runBinaryenWasmGenerator(b: b)
}
