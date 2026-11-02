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

/// Tests the initial synchronization of in-process (ThreadSync) workers with their parent.
@Suite struct ThreadSyncTests {
    private static let baseFuzzer = makeMockFuzzer()

    private func makeTestProgram(intVal: Int64) -> Program {
        return Self.baseFuzzer.sync {
            let b = Self.baseFuzzer.makeBuilder()
            b.loadInt(intVal)
            return b.finalize()
        }
    }

    @Test func testChildIsSynchronizedWhileParentImportsCorpus() {
        // A child connecting while the parent is still importing a corpus must immediately receive
        // the parent's current state.
        let parentFuzzer = makeThreadParent()
        let queue = ThreadSafeImportQueue([
            makeTestProgram(intVal: 10), makeTestProgram(intVal: 20),
        ])
        parentFuzzer.sync {
            parentFuzzer.scheduleCorpusImport(queue, importMode: .full)
            parentFuzzer.initialize()
            // Don't call fuzzOne() here: it reschedules itself and would finish the import
            // asynchronously, making the parent's state at child registration time racy.
            #expect(parentFuzzer.state == .corpusImport)
        }

        let childFuzzer = makeThreadChild(of: parentFuzzer)
        childFuzzer.sync {
            childFuzzer.initialize()
            #expect(childFuzzer.state == .waiting)
        }
        flushThreadSyncMessages(parentFuzzer, childFuzzer)

        #expect(parentFuzzer.sync { parentFuzzer.state } == .corpusImport)
        // The child received the (still empty) corpus via the sync message and left .waiting.
        #expect(childFuzzer.sync { childFuzzer.state } == .corpusGeneration)
    }

    @Test func testChildIsSynchronizedWhileParentGeneratesCorpus() {
        let parentFuzzer = makeThreadParent()
        parentFuzzer.sync {
            parentFuzzer.initialize()
            #expect(parentFuzzer.state == .corpusGeneration)
        }

        let childFuzzer = makeThreadChild(of: parentFuzzer)
        childFuzzer.sync {
            childFuzzer.initialize()
            #expect(childFuzzer.state == .waiting)
        }
        flushThreadSyncMessages(parentFuzzer, childFuzzer)

        #expect(childFuzzer.sync { childFuzzer.state } == .corpusGeneration)
    }

    @Test func testChildReceivesParentCorpus() {
        let parentFuzzer = makeThreadParent()
        parentFuzzer.sync {
            parentFuzzer.initialize()
            parentFuzzer.corpus.add(
                makeTestProgram(intVal: 10), ProgramAspects(outcome: .succeeded))
            parentFuzzer.corpus.add(
                makeTestProgram(intVal: 20), ProgramAspects(outcome: .succeeded))
        }

        let childFuzzer = makeThreadChild(of: parentFuzzer)
        childFuzzer.sync {
            childFuzzer.initialize()
        }
        flushThreadSyncMessages(parentFuzzer, childFuzzer)

        #expect(childFuzzer.sync { childFuzzer.state } == .fuzzing)
        #expect(childFuzzer.sync { childFuzzer.corpus.size } == 2)
    }
}
