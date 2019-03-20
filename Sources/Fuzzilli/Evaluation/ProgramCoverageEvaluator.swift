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

import libcoverage

class CovEdgeSet: ProgramAspects {
    let count: Int
    let edges: UnsafeMutablePointer<UInt32>?

    init(edges: UnsafeMutablePointer<UInt32>?, count: Int) {
        self.count = count
        self.edges = edges
        super.init(outcome: .succeeded)
    }
    
    deinit {
        if edges != nil {
            free(edges!)
        }
    }
}

public class ProgramCoverageEvaluator: ComponentBase, ProgramEvaluator {
    /// Counts the number of instances. Used to create unique shared memory regions in every instance.
    private static var instances = 0
    
    /// The current edge coverage percentage.
    public var currentScore: Double {
        return Double(context.found_edges) / Double(context.num_edges)
    }
    
    /// Context for the C library.
    private var context = libcoverage.cov_context()
    
    public init(runner: ScriptRunner) {
        super.init(name: "Coverage")
        
        let id = ProgramCoverageEvaluator.instances
        ProgramCoverageEvaluator.instances += 1
        
        context.id = Int32(id)
        guard libcoverage.cov_initialize(&context) == 0 else {
            fatalError("Could not initialize libcoverage")
        }
        runner.setEnvironmentVariable("SHM_ID", to: "shm_id_\(getpid())_\(id)")
    }
    
    override func initialize() {
        // Must clear the shared memory bitmap before every execution
        addEventListener(for: fuzzer.events.PreExecute) { execution in
            libcoverage.cov_clear_bitmap(&self.context)
        }
        
        // Unlink the shared memory regions on shutdown
        addEventListener(for: fuzzer.events.Shutdown) {
            libcoverage.cov_shutdown(&self.context)
        }
        
        let _ = fuzzer.execute(Program())
        libcoverage.cov_finish_initialization(&context)
        logger.info("Initialized, \(context.num_edges) edges")
    }
    
    public func evaluate(_ execution: Execution) -> ProgramAspects? {
        assert(execution.outcome == .succeeded)
        var edgeSet = libcoverage.edge_set();
        let result = libcoverage.cov_evaluate(&context, &edgeSet)
        if result == -1 {
            logger.error("Could not evaluate sample")
        }
        
        if result == 1 {
            return CovEdgeSet(edges: edgeSet.edges, count: edgeSet.count)
        } else {
            assert(edgeSet.edges == nil && edgeSet.count == 0)
            return nil
        }
    }
    
    public func evaluateCrash(_ execution: Execution) -> ProgramAspects? {
        assert(execution.outcome == .crashed)
        let result = libcoverage.cov_evaluate_crash(&context)
        if result == -1 {
            logger.error("Could not evaluate crash")
        }
        
        if result == 1 {
            // For minimization of crashes we only care about the outcome, not the edges covered.
            return ProgramAspects(outcome: .crashed)
        } else {
            return nil
        }
    }
    
    public func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool {
        guard execution.outcome == aspects.outcome else {
            return false
        }
        
        if let edgeSet = aspects as? CovEdgeSet {
            let result = libcoverage.cov_compare_equal(&context, edgeSet.edges!, edgeSet.count)
            if result == -1 {
                logger.error("Could not compare progam executions")
            }
            return result == 1
        } else {
            return true
        }
    }
}
