// Copyright 2020 Google LLC
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

/// Corpus for mutation-based fuzzing.
///
/// The corpus contains FuzzIL programs that can be used as input for mutations.
/// Any newly found interesting program is added to the corpus.
/// Programs are evicted from the copus for two reasons:
///
///  - if the corpus grows too large (larger than maxCorpusSize), in which
///    case the oldest programs are removed.
///  - if a program has been mutated often enough (at least
///    minMutationsPerSample times).
///
/// However, once reached, the corpus will never shrink below minCorpusSize again.
/// Further, once initialized, the corpus is guaranteed to always contain at least one program.
public class BasicCorpus: ComponentBase, Collection, Corpus {
    /// The minimum number of samples that should be kept in the corpus.
    private let minSize: Int
    
    /// The minimum number of times that a sample from the corpus was used
    /// for mutation before it can be discarded from the active set.
    private let minMutationsPerSample: Int
    
    /// The current set of interesting programs used for mutations.
    private var programs: RingBuffer<Program>
    private var ages: RingBuffer<Int>

    /// Counts the total number of entries in the corpus.
    private var totalEntryCounter = 0

    /// Corpus deduplicates the runtime types of its programs to conserve memory.
    private var typeExtensionDeduplicationSet = Set<TypeExtension>()
    
    public init(minSize: Int, maxSize: Int, minMutationsPerSample: Int) {
        // The corpus must never be empty. Other components, such as the ProgramBuilder, rely on this
        assert(minSize >= 1)
        assert(maxSize >= minSize)
        
        self.minSize = minSize
        self.minMutationsPerSample = minMutationsPerSample

        self.programs = RingBuffer(maxSize: maxSize)
        self.ages = RingBuffer(maxSize: maxSize)
        
        super.init(name: "Corpus")
    }
    
    override func initialize() {
        // Schedule a timer to perform cleanup regularly
        fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
        
        // The corpus must never be empty
        if self.isEmpty {
            // The fuzzer runs several sample programs on start to check for successful
            // execution by the target engine. Thus, the seed program is known to successfully
            // execute
            add(makeSeedProgram(), ProgramAspects(outcome: .succeeded))
        }
    }
    
    public var size: Int {
        return programs.count
    }
    
    public var isEmpty: Bool {
        return size == 0
    }
 
    public func add(_ program: Program, _ : ProgramAspects) {
        if program.size > 0 {
            deduplicateTypeExtensions(in: program, deduplicationSet: &typeExtensionDeduplicationSet)
            prepareProgramForInclusion(program, index: totalEntryCounter)
            programs.append(program)
            ages.append(0)

            totalEntryCounter += 1
        }
    }

    /// Returns a random program from this corpus for use in splicing to another program
    public func randomElementForSplicing() -> Program {
        let idx = Int.random(in: 0..<programs.count)
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }

    /// Returns a random program from this corpus and increases its age by one.
    public func randomElementForMutating() -> Program {
        let idx = Int.random(in: 0..<programs.count)
        ages[idx] += 1
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }

    public func exportState() throws -> Data {
        let res = try encodeProtobufCorpus(programs)
        logger.info("Successfully serialized \(programs.count) programs")
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)        
        programs.removeAll()
        ages.removeAll()
        for prog in newPrograms {
            // Programs provided by a master instance in an initial sync must have ran successfully
            add(prog, ProgramAspects(outcome: .succeeded))
        }
    }
    
    private func cleanup() {
        // Reset deduplication set
        typeExtensionDeduplicationSet = Set<TypeExtension>()
        var newPrograms = RingBuffer<Program>(maxSize: programs.maxSize)
        var newAges = RingBuffer<Int>(maxSize: ages.maxSize)
        
        for i in 0..<programs.count {
            let remaining = programs.count - i
            if ages[i] < minMutationsPerSample || remaining <= (minSize - newPrograms.count) {
                deduplicateTypeExtensions(in: programs[i], deduplicationSet: &typeExtensionDeduplicationSet)
                newPrograms.append(programs[i])
                newAges.append(ages[i])
            }
        }

        logger.info("Corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
        programs = newPrograms
        ages = newAges
    }

    public var startIndex: Int {
        return programs.startIndex
    }

    public var endIndex: Int {
        return programs.endIndex
    }

    public subscript(index: Int) -> Program {
        return programs[index]
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }
}
