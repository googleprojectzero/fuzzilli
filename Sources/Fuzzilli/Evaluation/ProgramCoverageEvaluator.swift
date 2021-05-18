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
    var count: UInt64
    var edges: UnsafeMutablePointer<UInt32>?

    init(edges: UnsafeMutablePointer<UInt32>?, count: UInt64) {
        self.count = count
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

    public static func == (lhs: CovEdgeSet, rhs: CovEdgeSet) -> Bool {
        if lhs.outcome != rhs.outcome { return false }
        if lhs.count != rhs.count { return false }
        for i in 0..<Int(lhs.count) {
            if lhs.edges![i] != rhs.edges![i] {
                return false
            }
        }
        return true
    }

    public override func intersect(_ otherAspect: ProgramAspects) -> Bool {
        guard let otherCovEdgeSet = otherAspect as? CovEdgeSet else { return false }
        let edgeSet = Set(UnsafeBufferPointer(start: edges, count: Int(count)))
        let otherEdgeSet = Set(UnsafeBufferPointer(start: otherCovEdgeSet.edges, count: Int(otherCovEdgeSet.count)))
        let intersection = edgeSet.intersection(otherEdgeSet)

        guard intersection.count > 0 else {
            self.count = 0
            return false
        }

        // Update internal state to match the intersection
        self.count = UInt64(intersection.count)
        for (i, edge) in intersection.enumerated() {
            self.edges![i] = edge
        }
        return self.count != 0
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
        runner.setEnvironmentVariable("SHM_ID", to: "shm_id_\(getpid())_\(id)")
    }
    
    public func enableEdgeTracking() {
        assert(!isInitialized) // This should only be called prior to initialization
        shouldTrackEdges = true
    }


    public func getEdgeCounts() -> [UInt32] {
        var edgeCounts = libcoverage.edge_counts()
        let result = libcoverage.get_edge_counts(&context, &edgeCounts)
        if result == -1 {
            logger.error("Error retrifying smallest hit count edges")
            return []
        }
        return Array(UnsafeBufferPointer(start: edgeCounts.edge_hit_count, count: Int(edgeCounts.count)))
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
        assert(execution.outcome == .succeeded)
        var newEdgeSet = libcoverage.edge_set()
        let result = libcoverage.cov_evaluate(&context, &newEdgeSet)
        if result == -1 {
            logger.error("Could not evaluate sample")
            return nil
        }
        if result == 1 {
            return CovEdgeSet(edges: newEdgeSet.edge_indices, count: newEdgeSet.count)
        } else {
            assert(newEdgeSet.edge_indices == nil && newEdgeSet.count == 0)
            return nil
        }

    }
    
    public func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
        assert(execution.outcome.isCrash())
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
            let result = libcoverage.cov_compare_equal(&context, edgeSet.edges, edgeSet.count)
            if result == -1 {
                logger.error("Could not compare progam executions")
            }
            return result == 1
        } else {
            return true
        }
    }

    public func resetAspects(_ aspects: ProgramAspects) {
        let edgeSet = aspects as! CovEdgeSet
        for edge in edgeSet.toEdges() {
            resetCounts[edge] = (resetCounts[edge] ?? 0) + 1
            if resetCounts[edge]! <= maxResetCount {
                libcoverage.clear_edge_data(&context, UInt64(edge))
            }
        }
    }

    /// Resets the edges shared by two aspects
    public func resetAspectDifferences(_ lhs: ProgramAspects, _ rhs: ProgramAspects){
        if let lCovEdgeSet = lhs as? CovEdgeSet, let rCovEdgeSet = rhs as? CovEdgeSet {
            let lEdges = Set(UnsafeBufferPointer(start: lCovEdgeSet.edges, count: Int(lCovEdgeSet.count)))
            let rEdges = Set(UnsafeBufferPointer(start: rCovEdgeSet.edges, count: Int(rCovEdgeSet.count)))
            for edge in lEdges.subtracting(rEdges) {
                resetCounts[edge] = (resetCounts[edge] ?? 0) + 1
                if resetCounts[edge]! <= maxResetCount {
                    libcoverage.clear_edge_data(&context, UInt64(edge))
                }
            }
        } else {
            logger.fatal("Coverage Evaluator received non coverage aspects")
        }
    }

    // Whether or not an edge has hit the reset limit
    public func hitResetLimit(_ edge: UInt32) -> Bool {
        guard let count = resetCounts[edge] else { return false }
        return count >= maxResetCount
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
        assert(isInitialized)
        
        guard state.count == 24 + context.bitmap_size * 2 else {
            throw FuzzilliError.evaluatorStateImportError("Cannot import coverage state as it has an unexpected size. Ensure all instances use the same build of the target")
        }
        
        let numEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt64.self) }
        let bitmapSize = state.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt64.self) }
        let foundEdges = state.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt64.self) }
        
        guard bitmapSize == context.bitmap_size && numEdges == context.num_edges else {
            throw FuzzilliError.evaluatorStateImportError("Cannot import coverage state due to different bitmap sizes. Ensure all instances use the same build of the target")
        }
        
        if foundEdges < context.found_edges {
            return logger.info("Not importing coverage state as it has less found edges than ours")
        }
        
        context.found_edges = foundEdges
        
        var start = state.startIndex + 24
        state.copyBytes(to: context.virgin_bits, from: start..<start + Int(bitmapSize))
        start += Int(bitmapSize)
        state.copyBytes(to: context.crash_bits, from: start..<start + Int(bitmapSize))
        
        logger.info("Imported existing coverage state with \(foundEdges) edges already discovered")
    }
}
