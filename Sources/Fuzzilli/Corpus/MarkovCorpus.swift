import Foundation

/// Corpus & Scheduler based on
/// Coverage-based Greybox Fuzzing as Markov Chain paper
/// https://mboehme.github.io/paper/TSE18.pdf
/// Simply put, the corpus keeps track of which paths have been found, and prioritizes seeds
/// whose path has been hit less than average. Ideally, this allows the fuzzer to prioritize
/// less explored coverage.
/// In the paper, a number of iterations is assigned to each sample, and each sample is then
/// scheduled that number of times. This implementation finds 1 / desiredSelectionProportion
/// of the least hit edges, and schedules those. After those have been mutated and evalutated,
/// the list is regenerated.
/// TODO:
/// - In order to properly implement the paper, the number of executions of each sample needs
///     to be scaled by its execution time (e.g. multiple by timeout / execution time), to
///     prioritize faster samples

public class MarkovCorpus: ComponentBase, Corpus {
    // All programs that were added to the corpus so far
    private var allIncludedPrograms: [Program] = []
    // Queue of programs to be executed next, all of which hit a rare edge
    private var programExecutionQueue: [Program] = []

    // For each edge encountered thus far, track which program initially discovered it
    private var edgeMap: [UInt32:Program] = [:]

    // This scheduler tracks the total number of samples it has returned
    // This allows it to build an initial baseline by randomly selecting a program to mutate
    // before switching to the more computationally expensive selection of programs that
    // hit infreqent edges
    private var totalExecs: UInt32 = 0

    // This scheduler returns one base program multiple times, in order to compensate the overhead caused by tracking
    // edge counts
    private var currentProg: Program
    private var remainingEnergy: UInt32 = 0

    // Markov corpus requires an evaluator that tracks edge coverage
    // Thus, the corpus object keeps a reference to the evaluator, in order to only downcast once
    private var covEvaluator: ProgramCoverageEvaluator

    // Rate at which selected samples will be included, to promote diversity between instances
    // Equivalent to 1 - dropoutRate
    private var dropoutRate: Double

    // The scheduler will initially selectd the 1 / desiredSelectionProportion samples with the least frequent
    // edge hits in each round, before dropout is applied
    private let desiredSelectionProportion = 8

    public init(covEvaluator: ProgramCoverageEvaluator, dropoutRate: Double) {
        self.dropoutRate = dropoutRate
        covEvaluator.enableEdgeTracking()
        self.covEvaluator = covEvaluator
        self.currentProg = Program()
        super.init(name: "MarkovCorpus")
    }

    override func initialize() {
        assert(covEvaluator === fuzzer.evaluator as! ProgramCoverageEvaluator)
        
        // Log initial coverage state
        let stats = getCoverageStatistics()
        logger.info("MarkovCorpus: Initialized with \(stats.description)")
    }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        guard program.size > 0 else { return }

        guard let origCov = aspects as? CovEdgeSet else {
            logger.fatal("Markov Corpus needs to be provided a CovEdgeSet when adding a program")
        }

        prepareProgramForInclusion(program, index: self.size)

        allIncludedPrograms.append(program)
        let edges = origCov.getEdges()
        for e in edges {
            edgeMap[e] = program
        }
        
        // Log coverage statistics for the added program
        let edgeCount = edges.count
        let currentCoverage = covEvaluator.currentScore
        let totalEdges = covEvaluator.getEdgeHitCounts().count
        let coveragePercentage = totalEdges > 0 ? Double(edgeCount) / Double(totalEdges) * 100.0 : 0.0
        
        logger.info("MarkovCorpus: Added program with \(edgeCount) edges, coverage: \(String(format: "%.6f%%", coveragePercentage)), current total coverage: \(String(format: "%.6f%%", currentCoverage * 100))")
    }

    /// Split evenly between programs in the current queue and all programs available to the corpus
    public func randomElementForSplicing() -> Program {
        var prog = programExecutionQueue.randomElement()
        if prog == nil || probability(0.5) {
            prog = allIncludedPrograms.randomElement()
        }
        assert(prog != nil && prog!.size > 0)
        return prog!
    }

    /// For the first 250 executions, randomly choose a program. This is done to build a base list of edge counts
    /// Once that base is acquired, provide samples that trigger an infrequently hit edge
    public func randomElementForMutating() -> Program {
        totalExecs += 1
        
        // Log transition from random to coverage-based selection
        if totalExecs == 251 {
            let currentCoverage = covEvaluator.currentScore
            let edgeCounts = covEvaluator.getEdgeHitCounts()
            let hitEdges = edgeCounts.filter { $0 > 0 }.count
            logger.info("MarkovCorpus: Switching to coverage-based selection at exec \(totalExecs), corpus size: \(size), hit edges: \(hitEdges), current coverage: \(String(format: "%.6f%%", currentCoverage * 100))")
        }
        
        // Log periodic coverage statistics every 1000 executions
        if totalExecs % 1000 == 0 {
            let stats = getCoverageStatistics()
            logger.info("MarkovCorpus: Periodic stats at exec \(totalExecs) - \(stats.description)")
            logger.info("MarkovCorpus: \(stats.edgeHitSummary)")
        }
        
        // Only do computationally expensive work choosing the next program when there is a solid
        // baseline of execution data. The data tracked in the statistics module is not used, as modules are intended
        // to not be required for the fuzzer to function.
        if totalExecs > 250 {
            // Check if more programs are needed
            if programExecutionQueue.isEmpty {
                regenProgramList()
            }
            if remainingEnergy > 0 {
                remainingEnergy -= 1
            } else {
                remainingEnergy = energyBase()
                currentProg = programExecutionQueue.popLast()!
            }
            return currentProg
        } else {
            return allIncludedPrograms.randomElement()!
        }
    }

    private func regenProgramList() {
        if programExecutionQueue.count != 0 {
            logger.fatal("Attempted to generate execution list while it still has programs")
        }
        let edgeCounts = covEvaluator.getEdgeHitCounts()
        let edgeCountsSorted = edgeCounts.sorted()
        
        // Log comprehensive coverage statistics
        let currentCoverage = covEvaluator.currentScore
        let totalEdges = edgeCounts.count
        let hitEdges = edgeCounts.filter { $0 > 0 }.count
        let hitPercentage = totalEdges > 0 ? Double(hitEdges) / Double(totalEdges) * 100.0 : 0.0
        let totalHits = edgeCounts.reduce(0, +)
        let averageHitsPerEdge = hitEdges > 0 ? Double(totalHits) / Double(hitEdges) : 0.0
        
        logger.info("MarkovCorpus: Coverage stats - Total edges: \(totalEdges), Hit edges: \(hitEdges) (\(String(format: "%.2f%%", hitPercentage))), Total hits: \(totalHits), Avg hits/edge: \(String(format: "%.2f", averageHitsPerEdge)), Current coverage: \(String(format: "%.6f%%", currentCoverage * 100))")

        // Find the edge with the smallest count
        var startIndex = -1
        for (i, val) in edgeCountsSorted.enumerated() {
            if val != 0 {
                startIndex = i
                break
            }
        }
        if startIndex == -1 {
            logger.fatal("No edges found in edge count")
        }

        // Find the nth interesting edge's count
        let desiredEdgeCount = max(size / desiredSelectionProportion, 30)
        let endIndex = min(startIndex + desiredEdgeCount, edgeCountsSorted.count - 1)
        let maxEdgeCountToFind = edgeCountsSorted[endIndex]
        
        logger.info("MarkovCorpus: Edge selection - Desired count: \(desiredEdgeCount), Max edge count to find: \(maxEdgeCountToFind), Start index: \(startIndex), End index: \(endIndex)")

        // Find the n edges with counts <= maxEdgeCountToFind.
        var selectedEdges = 0
        for (i, val) in edgeCounts.enumerated() {
            // Applies dropout on otherwise valid samples, to ensure variety between instances
            // This will likely select some samples multiple times, which is acceptable as
            // it is proportional to how many infrquently hit edges the sample has
            if val != 0 && val <= maxEdgeCountToFind && (probability(1 - dropoutRate) || programExecutionQueue.isEmpty) {
                if let prog = edgeMap[UInt32(i)] {
                    programExecutionQueue.append(prog)
                    selectedEdges += 1
                }
            }
        }
        
        logger.info("MarkovCorpus: Selected \(selectedEdges) edges for program queue generation")

        // Determine how many edges have been leaked and produce a warning if over 1% of total edges
        // Done as second pass for code clarity
        // Testing on v8 shows that < 0.01% of total edges are leaked
        // Potential causes:
        //  - Libcoverage iterates over the edge map twice, once for new coverage, and once for edge counts.
        //      This occurs while the target JS engine is running, so the coverage may be slightly different between the passes
        //      However, this is unlikely to be useful coverage for the purposes of Fuzzilli
        //  - Crashing samples may find new coverage and thus increment counters, but are not added to the corpus
        var missingEdgeCount = 0
        for (i, val) in edgeCounts.enumerated() {
            if val != 0 && edgeMap[UInt32(i)] == nil {
                missingEdgeCount += 1
            }
        }
        if missingEdgeCount > (edgeCounts.count / 100) {
            let missingPercentage = Double(missingEdgeCount) / Double(edgeCounts.count) * 100.0
            logger.warning("\(missingPercentage)% of total edges have been leaked")
        }

        if programExecutionQueue.count == 0 {
            logger.fatal("Program regeneration failed")
        }
        logger.info("Markov Corpus selected \(programExecutionQueue.count) new programs")
    }

    public var size: Int {
        return allIncludedPrograms.count
    }

    public var isEmpty: Bool {
        return size == 0
    }

    public subscript(index: Int) -> Program {
        return allIncludedPrograms[index]
    }

    public func allPrograms() -> [Program] {
        return allIncludedPrograms
    }

    // We don't currently support fast state synchronization.
    // Instead, we need to import every sample separately (potentially
    // multiple times for determinism) to determine the edges it triggers.
    public var supportsFastStateSynchronization: Bool {
        return false
    }

    // Note that this exports all programs, but does not include edge counts
    public func exportState() throws -> Data {
        fatalError("Not Supported")
    }

    public func importState(_ buffer: Data) throws {
        fatalError("Not Supported")
    }

    // Ramp up the number of times a sample is used as the initial seed over time
    private func energyBase() -> UInt32 {
        return UInt32(Foundation.log10(Float(totalExecs))) + 1
    }
    
    /// Get comprehensive coverage statistics for the MarkovCorpus
    public func getCoverageStatistics() -> MarkovCorpusStatistics {
        let edgeCounts = covEvaluator.getEdgeHitCounts()
        let currentCoverage = covEvaluator.currentScore
        let totalEdges = edgeCounts.count
        let hitEdges = edgeCounts.filter { $0 > 0 }.count
        let hitPercentage = totalEdges > 0 ? Double(hitEdges) / Double(totalEdges) * 100.0 : 0.0
        let totalHits = edgeCounts.reduce(0, +)
        let averageHitsPerEdge = hitEdges > 0 ? Double(totalHits) / Double(hitEdges) : 0.0
        
        // Calculate edge hit distribution
        let edgeHitDistribution = edgeCounts.reduce(into: [Int: Int]()) { counts, hitCount in
            counts[Int(hitCount), default: 0] += 1
        }
        
        return MarkovCorpusStatistics(
            totalPrograms: allIncludedPrograms.count,
            totalExecutions: Int(totalExecs),
            currentCoverage: currentCoverage,
            totalEdges: totalEdges,
            hitEdges: hitEdges,
            hitPercentage: hitPercentage,
            totalHits: Int(totalHits),
            averageHitsPerEdge: averageHitsPerEdge,
            queueSize: programExecutionQueue.count,
            edgeHitDistribution: edgeHitDistribution
        )
    }
}

// MARK: - Supporting Types

/// Statistics for MarkovCorpus coverage tracking
public struct MarkovCorpusStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let currentCoverage: Double
    public let totalEdges: Int
    public let hitEdges: Int
    public let hitPercentage: Double
    public let totalHits: Int
    public let averageHitsPerEdge: Double
    public let queueSize: Int
    public let edgeHitDistribution: [Int: Int]
    
    public var description: String {
        return "Programs: \(totalPrograms), Executions: \(totalExecutions), Coverage: \(String(format: "%.6f%%", currentCoverage * 100)), Edges: \(hitEdges)/\(totalEdges) (\(String(format: "%.2f%%", hitPercentage))), Total hits: \(totalHits), Avg hits/edge: \(String(format: "%.2f", averageHitsPerEdge)), Queue: \(queueSize)"
    }
    
    /// Get a summary of edge hit distribution
    public var edgeHitSummary: String {
        let sortedDistribution = edgeHitDistribution.sorted { $0.key < $1.key }
        let summary = sortedDistribution.prefix(10).map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        return "Edge hit distribution (hit_count:edge_count): \(summary)\(sortedDistribution.count > 10 ? "..." : "")"
    }
}
