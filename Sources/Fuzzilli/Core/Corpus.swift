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
public class Corpus: ComponentBase {
    /// The minimum number of samples that should be kept in the corpus.
    private let minSize: Int
    
    /// The minimum number of times that a sample from the corpus was used
    /// for mutation before it can be discarded from the active set.
    private let minMutationsPerSample: Int
    
    /// The current set of interesting programs used for mutations.
    private var programs: RingBuffer<Program>
    private var ages: RingBuffer<Int>
    
    public init(minSize: Int, maxSize: Int, minMutationsPerSample: Int) {
        assert(maxSize >= minSize)
        
        self.minSize = minSize
        self.minMutationsPerSample = minMutationsPerSample
        
        self.programs = RingBuffer(maxSize: maxSize)
        self.ages = RingBuffer(maxSize: maxSize)
        
        super.init(name: "Corpus")
    }
    
    override func initialize() {
        // Add interesting samples to the corpus
        fuzzer.events.InterestingProgramFound.observe { event in
            self.add(event.program)
        }
        
        // Schedule a timer to perform cleanup regularly
        fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
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
    
    public func exportState() -> [Program] {
        return [Program](programs)
    }
    
    public func importState(_ state: [Program]) throws {
        guard state.count > 0 else {
            throw RuntimeError("Cannot import an empty corpus.")
        }
        
        self.programs.removeAll()
        self.ages.removeAll()
        
        state.forEach(add)
    }
    
    private func cleanup() {
        var newPrograms = RingBuffer<Program>(maxSize: programs.maxSize)
        var newAges = RingBuffer<Int>(maxSize: ages.maxSize)
        
        for i in 0..<programs.count {
            let remaining = programs.count - i
            if ages[i] < minMutationsPerSample || remaining <= (minSize - newPrograms.count) {
                newPrograms.append(programs[i])
                newAges.append(ages[i])
            }
        }

        logger.info("Corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
        programs = newPrograms
        ages = newAges
    }
}
