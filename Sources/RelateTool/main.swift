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
import Fuzzilli

public struct V8DifferentialConfig {
    public static let commonArgs: [String] = [
        "--expose-gc",
        "--omit-quit",
        "--allow-natives-for-differential-fuzzing",
        "--fuzzing",
        "--future",
        "--harmony",
        "--predictable",
        "--trace",
        "--print-bytecode",
        "--correctness-fuzzer-suppressions",
        "--no-lazy-feedback-allocation",
    ]

    public static let differentialArgs: [String] = [
        "--no-sparkplug",
        "--jit-fuzzing",
        "--maglev-dumping",
        "--turbofan-dumping",
        "--turbofan-dumping-print-deopt-frames"
    ]

    public static let referenceArgs: [String] = [
        "--no-turbofan",
        "--no-maglev",
        "--sparkplug-dumping",
        "--interpreter-dumping"
    ]
}

struct Relater {
    let d8Path: String
    let pocPath: String
    let dumpFilePath: String

    private func runV8(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: d8Path)
        process.arguments = args + [pocPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
    }

    private func readDumpFile() throws -> String {
        return try String(contentsOfFile: dumpFilePath, encoding: .utf8)
    }

    private func cleanDumpFile() {
        try? FileManager.default.removeItem(atPath: dumpFilePath)
    }

    /// Main execution flow.
    func run() {
        do {
            cleanDumpFile()
            let optArgs = V8DifferentialConfig.commonArgs + V8DifferentialConfig.differentialArgs
            try runV8(args: optArgs)
            let optDumps = try readDumpFile()

            cleanDumpFile()
            let refArgs = V8DifferentialConfig.commonArgs + V8DifferentialConfig.referenceArgs
            try runV8(args: refArgs)
            let unOptDumps = try readDumpFile()

            let result = DiffOracle.relate(optDumps, with: unOptDumps)
            print("Differential check result: \(result)")

            if !result {
                exit(1)
            }

        } catch {
            print("Error during relate: \(error)")
            exit(1)
        }
    }
}

let args = Arguments.parse(from: CommandLine.arguments)

guard let jsShellPath = args["--d8"],
      let pocPath = args["--poc"] else {
    print("Usage: --d8 <path_to_d8> --poc <path_to_poc> [--dump <path_to_dump_file>]")
    exit(1)
}

// Parse optional dump path, default to /tmp/output_dump.txt
let dumpPath = args["--dump"] ?? "/tmp/output_dump.txt"

let relater = Relater(d8Path: jsShellPath, pocPath: pocPath, dumpFilePath: dumpPath)
relater.run()
