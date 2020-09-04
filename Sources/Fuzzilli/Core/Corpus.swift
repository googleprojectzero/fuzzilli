// Copyright 2019 Google LLC
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
public class Corpus: ComponentBase, Collection {
    /// The minimum number of samples that should be kept in the corpus.
    private let minSize: Int
    
    /// The minimum number of times that a sample from the corpus was used
    /// for mutation before it can be discarded from the active set.
    private let minMutationsPerSample: Int
    
    /// The current set of interesting programs used for mutations.
    private var programs: RingBuffer<Program>
    private var ages: RingBuffer<Int>

    /// Corpus deduplicates the runtime types of its programs to conserve memory.
    private var typeExtensionDeduplicationSet = Set<TypeExtension>()
    
    public init(minSize: Int, maxSize: Int, minMutationsPerSample: Int) {
        // The corpus must never be empty. Other components, such as the ProgramBuilder, rely on this
        precondition(minSize >= 1)
        precondition(maxSize >= minSize)
        
        self.minSize = minSize
        self.minMutationsPerSample = minMutationsPerSample
        
        self.programs = RingBuffer(maxSize: maxSize)
        self.ages = RingBuffer(maxSize: maxSize)
        
        super.init(name: "Corpus")
    }
    
    override func initialize() {
        // Add interesting samples to the corpus
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            self.add(ev.program)
        }
        
        // Schedule a timer to perform cleanup regularly
        fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
        
        // The corpus must never be empty
        if self.isEmpty {
            let b = fuzzer.makeBuilder()
            let objectConstructor = b.loadBuiltin("Object")
            b.callFunction(objectConstructor, withArgs: [])
            add(b.finalize())
        }
    }
    
    public var size: Int {
        return programs.count
    }
    
    public var isEmpty: Bool {
        return size == 0
    }
    
    /// Adds a program to the corpus.
    public func add(_ program: Program) {
        if program.size > 0 {
            deduplicateTypeExtensions(in: program)
            programs.append(program)
            ages.append(0)
        }
    }
    
    /// Adds multiple programs to the corpus.
    public func add(_ programs: [Program]) {
        programs.forEach(add)
    }
    
    /// Returns a random program from this corpus and potentially increases its age by one.
    public func randomElement(increaseAge: Bool = true) -> Program {
        let idx = Int.random(in: 0..<programs.count)
        if increaseAge {
            ages[idx] += 1
        }
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
        newPrograms.forEach(add)
    }

    /// Change type extensions for cached ones to save memory
    private func deduplicateTypeExtensions(in program: Program) {
        var deduplicatedRuntimeTypes = VariableMap<Type>()
        for (variable, runtimeType) in program.runtimeTypes {
            deduplicatedRuntimeTypes[variable] = runtimeType.uniquify(with: &typeExtensionDeduplicationSet)
        }
        program.runtimeTypes = deduplicatedRuntimeTypes
    }
    
    private func cleanup() {
        // Reset deduplication set
        typeExtensionDeduplicationSet = Set<TypeExtension>()
        var newPrograms = RingBuffer<Program>(maxSize: programs.maxSize)
        var newAges = RingBuffer<Int>(maxSize: ages.maxSize)
        
        for i in 0..<programs.count {
            let remaining = programs.count - i
            if ages[i] < minMutationsPerSample || remaining <= (minSize - newPrograms.count) {
                deduplicateTypeExtensions(in: programs[i])
                newPrograms.append(programs[i])
                newAges.append(ages[i])
            }
        }

        logger.info("Corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
        programs = newPrograms
        ages = newAges
    }

    public var startIndex: Int {
        programs.startIndex
    }

    public var endIndex: Int {
        programs.endIndex
    }

    public subscript(index: Int) -> Program {
        programs[index]
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }


}
