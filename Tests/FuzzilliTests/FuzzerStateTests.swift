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
import Testing

@testable import Fuzzilli

@Suite struct FuzzerStateTests {
    private func addPrograms(_ count: Int, to fuzzer: Fuzzer) {
        for i in 0..<count {
            let b = fuzzer.makeBuilder()
            b.loadInt(Int64(i))
            fuzzer.corpus.add(b.finalize(), ProgramAspects(outcome: .succeeded))
        }
    }

    @Test func testExportAndImportState() throws {
        let source = makeMockFuzzer()
        let state = try source.sync {
            addPrograms(3, to: source)
            #expect(source.supportsFastStateSynchronization)
            return try source.exportState()
        }

        let target = makeMockFuzzer()
        try target.sync {
            #expect(target.corpus.isEmpty)
            try target.importState(state)
            #expect(target.corpus.size == 3)
            #expect(target.corpus.allPrograms() == source.sync { source.corpus.allPrograms() })
        }
    }

    @Test func testImportStateRejectsInconsistentConfiguration() throws {
        let source = makeMockFuzzer(config: Configuration(logLevel: .error, isWasmEnabled: false))
        let state = try source.sync {
            addPrograms(1, to: source)
            return try source.exportState()
        }

        let target = makeMockFuzzer(config: Configuration(logLevel: .error, isWasmEnabled: true))
        target.sync {
            #expect(throws: FuzzilliError.self) { try target.importState(state) }
            #expect(target.corpus.isEmpty)
        }
    }
}
