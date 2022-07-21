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

public class CovEdgeSet: ProgramAspects {
    var _count: UInt64
    var edges: UnsafeMutablePointer<UInt32>?

    init(edges: UnsafeMutablePointer<UInt32>?, count: UInt64) {
        self._count = count
        self.edges = edges
        super.init(outcome: .succeeded)
    }

    deinit {
        free(edges)
    }

    public override var description: String {
        return "new coverage: \(count) newly discovered edge\(count > 1 ? "s" : "") in the CFG of the target"
    }

    /// This adds additional copies, but is only hit when new programs are added to the corpus
    /// It is used by corpus schedulers such as MarkovCorpus that require knowledge of which samples trigger which edges
    public func toEdges() -> [UInt32] {
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
        self._count = UInt64(collection.count)
        for (i, edge) in collection.enumerated() {
            self.edges![i] = edge
        }
    }

    override public var count: UInt64 {
        return self._count + super.count
    }

}

public class ProgramCoverageEvaluator: ComponentBase, ProgramEvaluator {
    /// Counts the number of instances. Used to create unique shared memory regions in every instance.
    private static var instances = 0
    
    private var shouldTrackEdges : Bool

    /// Keep track of how often an edge has been reset. Frequently set/cleared edges will be ignored
    private var resetCounts : [UInt32:UInt64] = [:]
    private var maxResetCount : UInt64

    /// The current edge coverage percentage.
    public var currentScore: Double {
        return Double(context.found_edges) / Double(context.num_edges)
    }
    
    /// Context for the C library.
    private var context = libcoverage.cov_context()
    
    public init(runner: ScriptRunner, maxResetCount: UInt64) {
        // In order to keep clean abstractions, any corpus scheduler requiring edge counting
        // needs to call EnableEdgeTracking(), via downcasting of ProgramEvaluator
        self.shouldTrackEdges = false

        self.maxResetCount = maxResetCount

        super.init(name: "Coverage")        

        let id = ProgramCoverageEvaluator.instances
        ProgramCoverageEvaluator.instances += 1
        

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
    
    public func enableEdgeTracking() {
        Assert(!isInitialized) // This should only be called prior to initialization
        shouldTrackEdges = true
    }


    public func getEdgeCounts() -> [UInt32] {
        var edgeCounts = libcoverage.edge_counts()
        let result = libcoverage.cov_get_edge_counts(&context, &edgeCounts)
        if result == -1 {
            logger.error("Error retrifying smallest hit count edges")
            return []
        }
        var edgeArray = Array(UnsafeBufferPointer(start: edgeCounts.edge_hit_count, count: Int(edgeCounts.count)))

        // Clear all edges that have hit their reset limits
        for (edge, count) in resetCounts {
            if count >= maxResetCount {
                edgeArray[Int(edge)] = 0
            }
        }

        return edgeArray
    }

    override func initialize() {

        // Must clear the shared memory bitmap before every execution
        fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { execution in
            libcoverage.cov_clear_bitmap(&self.context)
        }
        
        // Unlink the shared memory regions on shutdown
        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            libcoverage.cov_shutdown(&self.context)
        }
        
        let _ = fuzzer.execute(Program())
        libcoverage.cov_finish_initialization(&context, shouldTrackEdges ? 1 : 0)
        logger.info("Initialized, \(context.num_edges) edges")
    }
    
    public func evaluate(_ execution: Execution) -> ProgramAspects? {
        Assert(execution.outcome == .succeeded)
        var newEdgeSet = libcoverage.edge_set()
        let result = libcoverage.cov_evaluate(&context, &newEdgeSet)
        if result == -1 {
            logger.error("Could not evaluate sample")
            return nil
        }
        if result == 1 {
            return CovEdgeSet(edges: newEdgeSet.edge_indices, count: newEdgeSet.count)
        } else {
            Assert(newEdgeSet.edge_indices == nil && newEdgeSet.count == 0)
            return nil
        }

    }

    public func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
        Assert(execution.outcome.isCrash())
        let result = libcoverage.cov_evaluate_crash(&context)
        if result == -1 {
            logger.error("Could not evaluate crash")
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
        
        if let edgeSet = aspects as? CovEdgeSet {
            // We don't minimize crashes based on the coverage, only based on the crash outcome itself
            Assert(!aspects.outcome.isCrash())
            let result = libcoverage.cov_compare_equal(&context, edgeSet.edges, edgeSet.count)
            if result == -1 {
                logger.error("Could not compare progam executions")
            }
            return result == 1
        } else {
            return true
        }
    }


    // TODO See if we want to count the number of non-deterministic edges and expose them through the fuzzer statistics (if deterministic mode is enabled)
    func resetEdge(_ edge: UInt32) {
        resetCounts[edge] = (resetCounts[edge] ?? 0) + 1
        if resetCounts[edge]! <= maxResetCount {
            libcoverage.cov_clear_edge_data(&context, UInt64(edge))
        }
    }

    public func resetAspects(_ aspects: ProgramAspects) {
        let edgeSet = aspects as! CovEdgeSet
        for edge in edgeSet.toEdges() {
            resetEdge(edge)
        }
    }

    public func evaluateAndIntersect(_ program: Program, with aspects: ProgramAspects) -> ProgramAspects? {

        guard let firstCov = aspects as? CovEdgeSet else { 
            logger.fatal("Coverage Evaluator received non coverage aspects")
        }

        resetAspects(aspects)
        let execution = fuzzer.execute(program)

        guard execution.outcome == .succeeded else { return nil }

        guard let secondCovEdgeSet = evaluate(execution) as? CovEdgeSet else { return nil }

        let firstCovSet = Set(UnsafeBufferPointer(start: firstCov.edges, count: Int(firstCov.count)))
        let secondCovSet = Set(UnsafeBufferPointer(start: secondCovEdgeSet.edges, count: Int(secondCovEdgeSet.count)))

        // Reset any edges found in the second execution but not the first
        for edge in secondCovSet.subtracting(firstCovSet) {
            resetEdge(edge)
        }

        let intersectionEdges = secondCovSet.intersection(firstCovSet)
        guard intersectionEdges.count != 0 else { return nil }

        let sortedIntersetionEdges = Array(intersectionEdges).sorted()

        secondCovEdgeSet.setEdges(sortedIntersetionEdges)

        return secondCovEdgeSet
    }

    public func exportState() -> Data {
        var state = Data()
        state.append(Data(bytes: &context.num_edges, count: 8))
        state.append(Data(bytes: &context.bitmap_size, count: 8))
        state.append(Data(bytes: &context.found_edges, count: 8))
        state.append(context.virgin_bits, count: Int(context.bitmap_size))
        state.append(context.crash_bits, count: Int(context.bitmap_size))
        return state
    }

    public func importState(_ state: Data) throws {
        Assert(isInitialized)
        
        guard state.count == 24 + context.bitmap_size * 2 else {
            throw FuzzilliError.evaluatorStateImportError("Cannot import coverage state as it has an unexpected size. Ensure all instances use the same build of the target")
        }
        
        let numEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }
        let bitmapSize = state.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let foundEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        
        guard bitmapSize == context.bitmap_size && numEdges == context.num_edges else {
            throw FuzzilliError.evaluatorStateImportError("Cannot import coverage state due to different bitmap sizes. Ensure all instances use the same build of the target")
        }
        
        context.found_edges = foundEdges
        
        var start = state.startIndex + 24
        state.copyBytes(to: context.virgin_bits, from: start..<start + Int(bitmapSize))
        start += Int(bitmapSize)
        state.copyBytes(to: context.crash_bits, from: start..<start + Int(bitmapSize))
        
        logger.info("Imported existing coverage state with \(foundEdges) edges already discovered")
    }

    public func resetState() {
        resetCounts = [:]
        libcoverage.cov_reset_state(&context)
    }

}
