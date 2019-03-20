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

public class Corpus: ComponentBase {
    /// The minimum number of samples that should be kept in the corpus.
    private let minSize: Int
    
    /// The minimum number of times that a sample from the corpus was used
    /// for mutation before it can be discarded from the active set.
    private let minMutationsPerSample: Int
    
    /// All interesting programs ever found.
    private var all: [Program]
    
    /// The current set of interesting programs used for mutations.
    private var active: [(program: Program, age: Int)]
    
    public init(minSize: Int, minMutationsPerSample: Int) {
        self.minSize = minSize
        self.minMutationsPerSample = minMutationsPerSample
        self.all = []
        self.active = []
        
        super.init(name: "Corpus")
    }
    
    override func initialize() {
        // Add interesting samples to the corpus
        addEventListener(for: fuzzer.events.InterestingProgramFound) { event in
            self.add(event.program)
        }
        
        // Schedule a timer to perform cleanup regularly
        fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
    }
    
    public var size: Int {
        return active.count
    }
    
    public var isEmpty: Bool {
        return size == 0
    }
    
    /// Exports the entire corpus as a list of programs.
    public func export() -> [Program] {
        return all
    }
    
    /// Adds a program to the corpus.
    func add(_ program: Program) {
        if program.size > 0 {
            active.append((program, 0))
            all.append(program)
        }
    }
    
    func takeSample(count: Bool = true) -> Program {
        let idx = Int.random(in: 0..<active.count)
        if count {
            active[idx].age += 1
        }
        let program = active[idx].program
        assert(!program.isEmpty)
        return program
    }
    
    private func cleanup() {
        var newSamples = [(Program, Int)]()
        
        for i in 0..<active.count {
            let remaining = active.count - i
            if active[i].age < minMutationsPerSample || remaining <= (minSize - newSamples.count) {
                newSamples.append(active[i])
            }
        }

        logger.info("Corpus cleanup finished: \(self.active.count) -> \(newSamples.count)")
        active = newSamples
    }
}
