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
import libcoverage

/// Represents a set of newly discovered CFG edges in the target program.
public class CovEdgeSet: ProgramAspects {
    private var numEdges: UInt32
    fileprivate var edges: UnsafeMutablePointer<UInt32>?

    init(edges: UnsafeMutablePointer<UInt32>?, numEdges: UInt32) {
        self.numEdges = numEdges
        self.edges = edges
        super.init(outcome: .succeeded)
    }

    deinit {
        free(edges)
    }

    /// The number of aspects is simply the number of newly discovered coverage edges.
    public override var count: UInt32 {
        return numEdges
    }

    public override var description: String {
        return
            "new coverage: \(count) newly discovered edge\(count > 1 ? "s" : "") in the CFG of the target"
    }

    /// Returns an array of all the newly discovered edges of this CovEdgeSet.
    ///
    /// This adds additional copies, but is only hit when new programs are added to the corpus
    /// It is used by corpus schedulers such as MarkovCorpus that require knowledge of which samples trigger which edges
    public func getNewEdges() -> [UInt32] {
        return Array(UnsafeBufferPointer(start: edges, count: Int(count)))
    }

    public static func == (lhsEdges: CovEdgeSet, rhsEdges: CovEdgeSet) -> Bool {
        if lhsEdges.outcome != rhsEdges.outcome { return false }
        if lhsEdges.count != rhsEdges.count { return false }
        for i in 0..<Int(lhsEdges.count) {
            if lhsEdges.edges![i] != rhsEdges.edges![i] {
                return false
            }
        }
        return true
    }

    // Updates the internal state to match the provided collection
    fileprivate func setEdges<T: Collection>(_ collection: T) where T.Element == UInt32 {
        precondition(collection.count <= self.count)
        self.numEdges = UInt32(collection.count)
        for (i, edge) in collection.enumerated() {
            self.edges![i] = edge
        }
    }
}

/// A copy of (or an intersection of several) coverage bitmaps of past executions.
public final class CoverageBitmap {
    fileprivate let bits: UnsafeMutablePointer<UInt8>
    fileprivate let size: Int

    fileprivate init(size: Int) {
        self.size = size
        // At least 8 bytes, so that `bits` is always valid, and 8-byte aligned, because libcoverage
        // reads it as 64-bit words.
        let byteCount = Swift.max(size, 8)
        self.bits = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 8)
            .initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    }

    deinit {
        bits.deallocate()
    }
}

public class ProgramCoverageEvaluator: ComponentBase, ProgramEvaluator {
    /// Counts the number of instances. Used to create unique shared memory regions in every instance.
    private static var instances = 0
    private static let instancesLock = NSLock()

    /// Whether per-edge hit counts should be tracked as well.
    /// These are expensive to compute, so this need to be enabled explicitly.
    private var shouldTrackEdgeCounts: Bool

    /// Keep track of how often an edge has been reset. Frequently set/cleared edges will be ignored
    private var resetCounts: [UInt32: UInt64] = [:]

    /// How often an edge may be reset at most before it is considered non-deterministic.
    /// In that case, the edge is marked as found, but will not be considered an aspect of any program.
    private let maxResetCount: UInt64 = 1000

    /// The current edge coverage percentage.
    public var currentScore: Double {
        return Double(context.found_edges) / Double(context.num_edges)
    }

    /// Context for the C library.
    private var context = libcoverage.cov_context()
    private var isShutDown = false

    public init(runner: ScriptRunner) {
        // In order to keep clean abstractions, any corpus scheduler requiring edge counting
        // needs to call EnableEdgeTracking(), via downcasting of ProgramEvaluator
        self.shouldTrackEdgeCounts = false

        super.init(name: "Coverage")

        // Locked because tests create evaluators in parallel.
        let id = Self.instancesLock.withLock {
            defer { Self.instances += 1 }
            return Self.instances
        }

        context.id = Int32(id)
        guard libcoverage.cov_initialize(&context) == 0 else {
            fatalError("Could not initialize libcoverage")
        }
        #if os(Windows)
            runner.setEnvironmentVariable("SHM_ID", to: "shm_id_\(GetCurrentProcessId())_\(id)")
        #else
            runner.setEnvironmentVariable("SHM_ID", to: "shm_id_\(getpid())_\(id)")
        #endif

    }

    public func shutdown() {
        guard !isShutDown else { return }
        libcoverage.cov_shutdown(&context)
        isShutDown = true
    }

    deinit {
        shutdown()
    }

    /// The coverage shared memory, for tests that write coverage like an instrumented engine.
    var sharedMemory: UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(context.shmem)
    }

    public func enableEdgeTracking() {
        assert(!isInitialized)  // This should only be called prior to initialization
        shouldTrackEdgeCounts = true
    }

    public func getEdgeHitCounts() -> [UInt32] {
        var edgeCounts = libcoverage.edge_counts()
        let result = libcoverage.cov_get_edge_counts(&context, &edgeCounts)
        if result == -1 {
            logger.error("Error retrieving smallest hit count edges")
            return []
        }
        var edgeArray = Array(
            UnsafeBufferPointer(start: edgeCounts.edge_hit_count, count: Int(edgeCounts.count)))

        // Clear all edges that have hit their reset limits
        for (edge, count) in resetCounts {
            if count >= maxResetCount {
                edgeArray[Int(edge)] = 0
            }
        }

        return edgeArray
    }

    public func getAllEdges() -> [UInt32] {
        var edgeSet = libcoverage.edge_set()
        let result = libcoverage.cov_get_current_edges(&context, &edgeSet)
        return takeEdges(edgeSet, result: result)
    }

    /// Frees `edgeSet` and returns its edges, without those reset `maxResetCount` times.
    private func takeEdges(_ edgeSet: libcoverage.edge_set, result: Int32) -> [UInt32] {
        if result == -1 {
            logger.error("Error retrieving edges")
            return []
        }
        defer { free(edgeSet.edge_indices) }
        let buffer = UnsafeBufferPointer(start: edgeSet.edge_indices, count: Int(edgeSet.count))
        if resetCounts.isEmpty {
            return Array(buffer)
        }
        return buffer.filter { (resetCounts[$0] ?? 0) < maxResetCount }
    }

    /// Returns a new, empty bitmap that can hold the coverage of one execution.
    public func makeCoverageBitmap() -> CoverageBitmap {
        return CoverageBitmap(size: Int(context.bitmap_size))
    }

    /// Copies the coverage bitmap of the last execution into `bitmap`.
    public func copyCurrentCoverage(into bitmap: CoverageBitmap) {
        precondition(bitmap.size == Int(context.bitmap_size))
        libcoverage.cov_copy_current_bitmap(&context, bitmap.bits)
    }

    /// Returns the edges set in `bitmap` (and in `mask`, if given). Like `getAllEdges`, skips edges
    /// reset `maxResetCount` times.
    public func getAllDeterministicEdges(
        in bitmap: CoverageBitmap, intersectedWith mask: CoverageBitmap? = nil
    )
        -> [UInt32]
    {
        precondition(bitmap.size == Int(context.bitmap_size))
        precondition(mask == nil || mask!.size == Int(context.bitmap_size))
        var edgeSet = libcoverage.edge_set()
        let result = libcoverage.cov_get_edges_in_bitmap(
            &context, bitmap.bits, mask?.bits, &edgeSet)
        return takeEdges(edgeSet, result: result)
    }

    /// Intersection of the coverage of all `computeAspectIntersection` runs since
    /// `startCollectingDeterministicCoverage`. Nil when not collecting.
    private var deterministicCoverage: CoverageBitmap? = nil
    private var deterministicCoverageRuns = 0

    /// Starts intersecting the full coverage of every `computeAspectIntersection` run.
    public func startCollectingDeterministicCoverage() {
        deterministicCoverage = makeCoverageBitmap()
        deterministicCoverageRuns = 0
    }

    /// Stops collecting and returns the intersection, or nil if there was no run.
    public func stopCollectingDeterministicCoverage() -> CoverageBitmap? {
        let result = deterministicCoverageRuns > 0 ? deterministicCoverage : nil
        deterministicCoverage = nil
        deterministicCoverageRuns = 0
        return result
    }

    /// Reads `context.shmem->edges`, which `PreExecute` clears before every execution.
    private func collectDeterministicCoverage() {
        guard let bitmap = deterministicCoverage else { return }
        if deterministicCoverageRuns == 0 {
            libcoverage.cov_copy_current_bitmap(&context, bitmap.bits)
        } else {
            libcoverage.cov_intersect_current_bitmap(&context, bitmap.bits)
        }
        deterministicCoverageRuns += 1
    }

    override func initialize() {
        // Must clear the shared memory bitmap before every execution
        fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { [weak self] execution in
            guard let self = self else { return }
            libcoverage.cov_clear_bitmap(&self.context)
        }

        // Unlink the shared memory regions on shutdown
        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { [weak self] _ in
            self?.shutdown()
        }

        let _ = fuzzer.execute(Program(isBundle: false), purpose: .startup)
        libcoverage.cov_finish_initialization(&context, shouldTrackEdgeCounts ? 1 : 0)
        logger.info("Initialized, \(context.num_edges) edges")
    }

    public func evaluate(_ execution: Execution) -> ProgramAspects? {
        assert(execution.outcome == .succeeded)
        var newEdgeSet = libcoverage.edge_set()
        let result = libcoverage.cov_evaluate(&context, &newEdgeSet)
        guard result != -1 else {
            logger.error("Could not evaluate sample")
            return nil
        }

        if result == 1 {
            return CovEdgeSet(edges: newEdgeSet.edge_indices, numEdges: newEdgeSet.count)
        } else {
            assert(newEdgeSet.edge_indices == nil && newEdgeSet.count == 0)
            return nil
        }
    }

    public func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
        assert(execution.outcome.isCrash())
        let result = libcoverage.cov_evaluate_crash(&context)
        guard result != -1 else {
            logger.error("Could not evaluate crash")
            return nil
        }

        if result == 1 {
            // For minimization of crashes we only care about the outcome, not the edges covered.
            return ProgramAspects(outcome: execution.outcome)
        } else {
            return nil
        }
    }

    public func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
        guard execution.outcome == aspects.outcome else {
            return false
        }

        if execution.outcome.isCrash() || execution.outcome.isDifferential() {
            // For crashes and differentials, we don't care about the edges that were triggered, just about the outcome itself.
            return true
        }

        guard let edgeSet = aspects as? CovEdgeSet else {
            fatalError("Invalid aspects passed to hasAspects")
        }

        let result = libcoverage.cov_compare_equal(&context, edgeSet.edges, edgeSet.count)
        if result == -1 {
            logger.error("Could not compare progam executions")
        }
        return result == 1
    }

    public func computeAspectIntersection(of program: Program, with aspects: ProgramAspects)
        -> ProgramAspects?
    {
        guard let firstCovEdgeSet = aspects as? CovEdgeSet else {
            logger.fatal("Coverage Evaluator received non coverage aspects")
        }

        // Mark all edges in the provided aspects as undiscovered so they can be retriggered during the next execution.
        resetAspects(firstCovEdgeSet)

        // Execute the program and collect coverage information.
        let execution = fuzzer.execute(program, purpose: .checkForDeterministicBehavior)
        guard execution.outcome == .succeeded else { return nil }
        collectDeterministicCoverage()
        guard let secondCovEdgeSet = evaluate(execution) as? CovEdgeSet else { return nil }

        let firstEdgeSet = Set(
            UnsafeBufferPointer(start: firstCovEdgeSet.edges, count: Int(firstCovEdgeSet.count)))
        let secondEdgeSet = Set(
            UnsafeBufferPointer(start: secondCovEdgeSet.edges, count: Int(secondCovEdgeSet.count)))

        // Reset all edges that were only triggered by the 2nd execution (those only triggered by the 1st execution were already reset earlier).
        for edge in secondEdgeSet.subtracting(firstEdgeSet) {
            resetEdge(edge)
        }

        // Compute the intersection of the edges.
        let intersectedEdgeSet = secondEdgeSet.intersection(firstEdgeSet)
        guard intersectedEdgeSet.count != 0 else { return nil }

        // Here we reuse one of the existing CovEdgeSets instead of creating a new one to avoid a malloc() and free() of the backing buffer.
        let intersectedCovEdgeSet = secondCovEdgeSet
        intersectedCovEdgeSet.setEdges(intersectedEdgeSet)

        return intersectedCovEdgeSet
    }

    public func exportState() -> Data {
        var state = Data()
        state.append(Data(bytes: &context.num_edges, count: 4))
        state.append(Data(bytes: &context.bitmap_size, count: 4))
        state.append(Data(bytes: &context.found_edges, count: 4))
        state.append(context.virgin_bits, count: Int(context.bitmap_size))
        state.append(context.crash_bits, count: Int(context.bitmap_size))
        return state
    }

    public func importState(_ state: Data) throws {
        assert(isInitialized)
        let headerSize = 12  // 3 x 4 bytes: num_edges, bitmap_size, found_edges. See exportState() above

        guard state.count == headerSize + Int(context.bitmap_size) * 2 else {
            throw FuzzilliError.evaluatorStateImportError(
                "Cannot import coverage state as it has an unexpected size. Ensure all instances use the same build of the target"
            )
        }

        let numEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let bitmapSize = state.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
        let foundEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

        guard bitmapSize == context.bitmap_size && numEdges == context.num_edges else {
            throw FuzzilliError.evaluatorStateImportError(
                "Cannot import coverage state due to different bitmap sizes. Ensure all instances use the same build of the target"
            )
        }

        context.found_edges = foundEdges

        var start = state.startIndex + headerSize
        state.copyBytes(to: context.virgin_bits, from: start..<start + Int(bitmapSize))
        start += Int(bitmapSize)
        state.copyBytes(to: context.crash_bits, from: start..<start + Int(bitmapSize))

        logger.info("Imported existing coverage state with \(foundEdges) edges already discovered")
    }

    public func resetState() {
        resetCounts = [:]
        libcoverage.cov_reset_state(&context)
    }

    // TODO See if we want to count the number of non-deterministic edges and expose them through the fuzzer statistics (if deterministic mode is enabled)
    private func resetEdge(_ edge: UInt32) {
        resetCounts[edge] = (resetCounts[edge] ?? 0) + 1
        if resetCounts[edge]! <= maxResetCount {
            libcoverage.cov_clear_edge_data(&context, edge)
        }
    }

    private func resetAspects(_ aspects: CovEdgeSet) {
        for i in 0..<Int(aspects.count) {
            resetEdge(aspects.edges![i])
        }
    }
}
