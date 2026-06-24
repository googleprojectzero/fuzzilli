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
    let extraArguments = [
        "--print-boundary"
    ]

    let (wasmBytes, jsonOutput) = BinaryenRunner.runWasmOptWithTempFiles(
        fuzzer: b.fuzzer,
        extraArguments: extraArguments
    )

    // Parse JSON output and build WasmModuleMetadata dynamically
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
