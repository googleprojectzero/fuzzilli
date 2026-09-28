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

import Collections
import Foundation

/// Corpus that schedules programs for mutation based on how rarely their coverage edges
/// have been seen, decaying with mutation age and program size.
/// Seeds whose energy dropped to 0.0 (all their tracked rare edges saturated) are evicted.
public class RarityCorpus: ComponentBase, Collection, Corpus {
    private weak var covEvaluator: ProgramCoverageEvaluator?

    private final class Seed: Comparable {
        let program: Program
        let rareEdges: [UInt32]
        let id: Int
        var age: Int = 0
        var energy: Double = 0.0

        init(program: Program, rareEdges: [UInt32], id: Int, age: Int = 0, energy: Double = 0.0) {
            self.program = program
            self.rareEdges = rareEdges
            self.id = id
            self.age = age
            self.energy = energy
        }

        static func == (lhs: Seed, rhs: Seed) -> Bool {
            return lhs.id == rhs.id
        }

        static func < (lhs: Seed, rhs: Seed) -> Bool {
            if lhs.energy != rhs.energy {
                return lhs.energy < rhs.energy
            }
            if lhs.age != rhs.age {
                return lhs.age > rhs.age
            }
            if lhs.program.size != rhs.program.size {
                return lhs.program.size > rhs.program.size
            }
            return lhs.id < rhs.id
        }
    }

    private var seeds: [Seed] = []
    /// Total number of seeds ever added, used to give each seed a unique `id`.
    private var totalEntryCounter = 0
    private var edgeSeenCount: [UInt8] = []
    private var energyHeap = Heap<Seed>()
    private var heapNeedsRebuild = false

    /// Exponents controlling how seed energy scales with mutation age, program size, and edge rarity:
    /// energy = rarity / ((age + 1)^ageExponent * (1 + ln(size)^sizeExponent))
    /// where rarity = sum(1 / edgeSeenCount[e]^rarityExponent) over tracked rare edges.
    private let ageExponent: Double
    private let sizeExponent: Double
    private let rarityExponent: Double
    /// Maximum number of times an edge can be seen across corpus seeds before its rarity weight
    /// drops to 0 (so thousands of common edges do not outweigh a few genuinely rare ones).
    private let rareEdgeLimit: UInt8
    private let maxTrackedEdgesPerSeed: Int = 128

    public init(
        ageExponent: Double = 2.0,
        sizeExponent: Double = 2.0,
        rarityExponent: Double = 3.0,
        rareEdgeLimit: Int = 8,
        covEvaluator: ProgramCoverageEvaluator? = nil
    ) {
        if rareEdgeLimit < 1 || rareEdgeLimit >= Int(UInt8.max) {
            fatalError("rareEdgeLimit must be between 1 and \(UInt8.max - 1)")
        }
        if !ageExponent.isFinite || ageExponent < 0.0 {
            fatalError("ageExponent must be a non-negative finite number")
        }
        if !sizeExponent.isFinite || sizeExponent < 0.0 {
            fatalError("sizeExponent must be a non-negative finite number")
        }
        if !rarityExponent.isFinite || rarityExponent < 0.0 {
            fatalError("rarityExponent must be a non-negative finite number")
        }
        self.ageExponent = ageExponent
        self.sizeExponent = sizeExponent
        self.rarityExponent = rarityExponent
        self.rareEdgeLimit = UInt8(rareEdgeLimit)
        self.covEvaluator = covEvaluator

        super.init(name: "RarityCorpus")
    }

    override func initialize() {
        if covEvaluator == nil {
            covEvaluator = fuzzer.evaluator as? ProgramCoverageEvaluator
        }
        // When a program crashes, the few last edges leading to the crash need to be recorded
        // this lowers (we measured it) the amount of duplicates of the same bug in a session
        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            if ev.behaviour == .deterministic, let evaluator = self.covEvaluator {
                // TODO(rherouart): b/564888741 - use/extend normal convergence algorithm to only get deterministic edges
                self.recordCrashEdges(evaluator.getCurrentEdges())
            }
        }
    }

    public var size: Int {
        return seeds.count
    }

    public var isEmpty: Bool {
        return seeds.isEmpty
    }

    public var supportsFastStateSynchronization: Bool {
        return true
    }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        addInternal(program, aspects: aspects)
    }

    public func addInternal(_ program: Program, aspects: ProgramAspects? = nil) {
        guard program.size > 0 else { return }

        // `aspects` only contains the newly discovered virgin edges that caused this program
        // to be added to the corpus (already verified as deterministic by Fuzzer.processMaybeInteresting).
        // To also track rare edges shared with earlier seeds, we execute the program twice and
        // union `newEdges` with the intersection of all edges hit in both runs.
        let newEdges = Set((aspects as? CovEdgeSet)?.getEdges() ?? [])
        var deterministicEdges = newEdges
        if let evaluator = covEvaluator {
            // TODO(rherouart): b/564888741 - use/extend normal convergence algorithm to only get deterministic edges
            let exec1 = fuzzer.execute(program, purpose: .other)
            if exec1.outcome == .succeeded {
                let edges1 = Set(evaluator.getCurrentEdges())
                let exec2 = fuzzer.execute(program, purpose: .other)
                if exec2.outcome == .succeeded {
                    let edges2 = Set(evaluator.getCurrentEdges())
                    deterministicEdges.formUnion(edges1.intersection(edges2))
                }
            }
        }

        recordEdgesSeen(deterministicEdges)

        // Keep only edges that are still considered rare (seen fewer than `rareEdgeLimit` times)
        // so that thousands of common edges (an empty program hits ~25K edges deterministically)
        // do not accumulate and dominate a few genuinely rare edges.
        // After `recordEdgesSeen`, only the newly discovered edges of this program have
        // `edgeSeenCount == 1` (previously seen edges have count >= 2). Sorting by `edgeSeenCount`
        // ascending therefore automatically prioritizes new edges first when capping at `maxTrackedEdgesPerSeed`.
        let candidateRareEdges = deterministicEdges.filter {
            edgeSeenCount[Int($0)] < rareEdgeLimit
        }
        let trackedEdges = Array(
            candidateRareEdges
                .sorted { edgeSeenCount[Int($0)] < edgeSeenCount[Int($1)] }
                .prefix(maxTrackedEdgesPerSeed)
        )

        let id = totalEntryCounter
        totalEntryCounter += 1
        prepareProgramForInclusion(program, index: id)
        seeds.append(Seed(program: program, rareEdges: trackedEdges, id: id))
        heapNeedsRebuild = true
    }

    private func recordEdgesSeen<C: Collection>(_ edges: C) where C.Element == UInt32 {
        guard let maxEdge = edges.max() else { return }
        let maxEdgeIndex = Int(maxEdge)
        if maxEdgeIndex >= edgeSeenCount.count {
            edgeSeenCount.append(
                contentsOf: repeatElement(
                    UInt8(0), count: maxEdgeIndex - edgeSeenCount.count + 1024)
            )
        }
        for edge in edges {
            let idx = Int(edge)
            // Even an empty program hits ~25K edges deterministically. We ignore edges seen
            // >= rareEdgeLimit times so thousands of common edges don't outweigh a few rare ones.
            // Once an edge reaches rareEdgeLimit its weight is 0, so we can stop counting.
            if edgeSeenCount[idx] < rareEdgeLimit {
                edgeSeenCount[idx] += 1
            }
        }
    }

    private func computeRarity(for edges: [UInt32]) -> Double {
        var sum = 0.0
        for edge in edges {
            let seen = edgeSeenCount[Int(edge)]
            if seen < rareEdgeLimit {
                sum += 1.0 / Foundation.pow(Double(Swift.max(1, seen)), rarityExponent)
            }
        }
        return sum
    }

    /// Computes the scheduling energy for a seed based on edge rarity, mutation age, and program size.
    /// - Size corresponds to the number of FuzzIL instructions (`seed.program.size`).
    /// - `sizeWeight = 1.0 + ln(size)^sizeExponent` ensures that single-instruction programs have weight 1.0
    private func computeEnergy(for seed: Seed) -> Double {
        let rarity = computeRarity(for: seed.rareEdges)
        let lnSize = Foundation.log(Double(Swift.max(1, seed.program.size)))
        let sizeWeight = 1.0 + Foundation.pow(lnSize, sizeExponent)
        return rarity / (Foundation.pow(Double(seed.age + 1), ageExponent) * sizeWeight)
    }

    func recordCrashEdges(_ edges: [UInt32]) {
        guard !edges.isEmpty else { return }
        recordEdgesSeen(edges)
        heapNeedsRebuild = true
    }

    private func ensureHeapUpdated() {
        guard heapNeedsRebuild else { return }
        var activeSeeds: [Seed] = []
        activeSeeds.reserveCapacity(seeds.count)
        for seed in seeds {
            seed.energy = computeEnergy(for: seed)
            if seed.energy > 0.0 {
                activeSeeds.append(seed)
            }
        }
        // Energy never increases (edge counts and ages only grow), so a seed with 0.0 energy can
        // never be scheduled again: evict it from RAM as well. The corpus must never become empty,
        // so if no seed has energy left, all seeds are kept.
        if !activeSeeds.isEmpty {
            seeds = activeSeeds
        }
        energyHeap = Heap(activeSeeds)
        heapNeedsRebuild = false
    }

    func seedEnergy(at index: Int) -> Double {
        ensureHeapUpdated()
        return computeEnergy(for: seeds[index])
    }

    func seedRarity(at index: Int) -> Double {
        return computeRarity(for: seeds[index].rareEdges)
    }

    func seedAge(at index: Int) -> Int {
        return seeds[index].age
    }

    func edgeCount(for edge: UInt32) -> Int {
        let idx = Int(edge)
        return idx < edgeSeenCount.count ? Int(edgeSeenCount[idx]) : 0
    }

    // TODO(rherouart): Consider also selecting based on energy
    public func randomElementForSplicing() -> Program {
        assert(!seeds.isEmpty)
        return seeds[Int.random(in: 0..<seeds.count)].program
    }

    public func randomElementForMutating() -> Program {
        assert(!seeds.isEmpty)
        ensureHeapUpdated()

        guard let seed = energyHeap.popMax() else {
            let idx = Int.random(in: 0..<seeds.count)
            seeds[idx].age += 1
            return seeds[idx].program
        }

        seed.age += 1
        seed.energy = computeEnergy(for: seed)
        if seed.energy > 0.0 {
            energyHeap.insert(seed)
        }
        return seed.program
    }

    public func allPrograms() -> [Program] {
        return seeds.map { $0.program }
    }

    private struct SerializedState: Codable {
        let programs: Data
        let seedEdges: [[UInt32]]
        let seedAges: [Int]
        let edgeSeenCount: [UInt8]
    }

    public func exportState() throws -> Data {
        let programs = allPrograms()
        let state = SerializedState(
            programs: try encodeProtobufCorpus(programs),
            seedEdges: seeds.map { $0.rareEdges },
            seedAges: seeds.map { $0.age },
            edgeSeenCount: edgeSeenCount
        )
        let res = try PropertyListEncoder().encode(state)
        logger.info("Successfully serialized \(programs.count) programs")
        return res
    }

    public func importState(_ buffer: Data) throws {
        let state = try PropertyListDecoder().decode(SerializedState.self, from: buffer)
        let newPrograms = try decodeProtobufCorpus(state.programs)
        guard newPrograms.count == state.seedEdges.count,
            newPrograms.count == state.seedAges.count,
            state.seedAges.allSatisfy({ $0 >= 0 })
        else {
            throw FuzzilliError.corpusImportError("Mismatched program and rarity metadata counts")
        }

        edgeSeenCount = state.edgeSeenCount
        if let maxEdge = state.seedEdges.joined().max(), Int(maxEdge) >= edgeSeenCount.count {
            edgeSeenCount.append(
                contentsOf: repeatElement(UInt8(0), count: Int(maxEdge) - edgeSeenCount.count + 1)
            )
        }

        seeds.removeAll(keepingCapacity: true)
        seeds.reserveCapacity(newPrograms.count)
        for i in 0..<newPrograms.count {
            let program = newPrograms[i]
            prepareProgramForInclusion(program, index: i)
            seeds.append(
                Seed(
                    program: program, rareEdges: state.seedEdges[i], id: i,
                    age: state.seedAges[i])
            )
        }
        totalEntryCounter = newPrograms.count
        heapNeedsRebuild = true
    }

    public var startIndex: Int {
        return seeds.startIndex
    }

    public var endIndex: Int {
        return seeds.endIndex
    }

    public subscript(index: Int) -> Program {
        return seeds[index].program
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }
}
