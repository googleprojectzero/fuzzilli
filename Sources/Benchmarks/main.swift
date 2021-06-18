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
import Fuzzilli

// Tiny benchmarking suite

// How often to repeat every benchmark
let repetitions = 10

// Current timestamp in seconds (with at least millisecond precision)
func now() -> Double {
    return Date().timeIntervalSince1970
}


func benchmarkCodeGeneration() {
    let corpus = BasicCorpus(minSize: 1, maxSize: 1000, minMutationsPerSample: 5)
    let fuzzer = makeMockFuzzer(corpus: corpus)
    let b = fuzzer.makeBuilder()

    for _ in 0..<1000 {
        b.generate(n: 100)
        let program = b.finalize()

        // Add to corpus since generate() does splicing as well
        fuzzer.corpus.add(program, ProgramAspects(outcome: .succeeded))
    }
}

// TODO add more, e.g. for mutators
var benchmarks: [String: () -> ()] = [
    "CodeGenerationBenchmark": benchmarkCodeGeneration
]

for (name, benchmark) in benchmarks {
    var totalTime = 0.0
    for _ in 0..<repetitions {
        let start = now()
        benchmark()
        totalTime += now() - start
    }
    let avgTime = totalTime / Double(repetitions)
    print("Benchmark \(name) finished after \(String(format: "%.2f", avgTime)) seconds on average")
}
