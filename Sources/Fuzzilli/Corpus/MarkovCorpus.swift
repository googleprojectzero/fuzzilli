import Foundation

/// Corpus & Scheduler based on 
/// Coverage-based Greybox Fuzzing as Markov Chain paper
/// https://mboehme.github.io/paper/TSE18.pdf
/// Simply put, the corpus keeps track of which paths have been found, and prioritizes seeds
/// whose path has been hit less than average. Ideally, this allows the fuzzer to prioritize
/// less explored coverage.

public class MarkovCorpus: ComponentBase, Corpus {

    // All programs currently in the corpus
    private var allIncludedPrograms: [Program] = []
    // Queue of programs to be executed next, all of which hit a rare edge
    private var programExecutionQueue: [Program] = []

    // For each edge encountered thus far, track which program initially discovered it
    private var edgeMap: [UInt64:Program] = [:]

    // This scheduler tracks the total number of samples it has returned
    // This allows it to build an initial baseline by randomly selecting a program to mutate
    // before switching to the more computationally expensive selection of programs that
    // hit infreqent edges
    private var totalExecs: UInt64 = 0

    // This scheduler returns one base program multiple times, in order to compensate the overhead caused by tracking
    // edge counts
    private var currentProg: Program? = nil
    private var remainingEnergy: UInt64 = 0

    // Markov corpus requires an evaluator that tracks edge coverage
    // Thus, the corpus object keeps a reference to the evaluator, in order to only downcast once
    private var covEvaluator: ProgramCoverageEvaluator

    // This is required as MarkovCorpus increments all edges by this value when they are selected,
    // to prevent issues with edge non-determinism
    private var numConsecutiveMutations: UInt64

    // This ensures the coverage map is done correctly for the initial program
    private var genericProg: Program? = nil

    public init(numConsecutiveMutations: Int, evaluator: ProgramEvaluator) {
        self.numConsecutiveMutations = UInt64(numConsecutiveMutations)
        if let covEvaluator = evaluator as? ProgramCoverageEvaluator {
            self.covEvaluator = covEvaluator
            covEvaluator.enableEdgeTracking()
        } else {
            // covEvaluator needs to be set prior to super.init, which means logger hasn't been instantiated
            print("Markov corpus requires the use of a ProgramCoverageEvaluator as its evaluator")
            exit(-1)
        }
        super.init(name: "MarkovCorpus")
    }

    override func initialize() {
        genericProg = makeSeedProgram()
    }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        guard program.size > 0 else { return }
        allIncludedPrograms.append(program)
        if let covAspects = aspects as? CovEdgeSet {
            let edges = covAspects.toEdges()
            for e in edges {
                edgeMap[e] = program
            }
        } else {
            logger.fatal("Markov Corpus needs to be provided a CovEdgeSet when adding a program")
        }
    }

    // Switch evenly between programs in the current queue and all programs available to the corpus
    public func randomElementForSplicing() -> Program {
        if size <= 1 {
            return genericProg!
        }
        var prog = programExecutionQueue.randomElement()
        if prog == nil || probability(0.5) {
            prog = allIncludedPrograms.randomElement()
        }
        assert(prog!.size != 0)
        return prog!
    }

    /// For the first 500 executions, randomly choose a program. This is done to build a base list of edge counts
    /// Once that base is acquired, provide samples that trigger an infrequently hit edge
    public func randomElementForMutating() -> Program {
        totalExecs += 1
        if size <= 1 {
            return genericProg!
        }
        // Only do computationally expensive work choosing the next program when there is a solid
        // baseline of execution data. The data tracked in the statistics module is not used, as modules are intended 
        // to not be required for the fuzzer to function.
        if totalExecs > 1000 {
            // Check if more programs are needed
            if programExecutionQueue.count == 0 {
                regenProgramList()
            }
            assert(programExecutionQueue.count > 0)
            var prog : Program
            if let tempProg = currentProg, remainingEnergy > 0 {
                prog = tempProg
                remainingEnergy -= 1
            } else {
                prog = programExecutionQueue.popLast()!
                currentProg = prog
                remainingEnergy = energyBase()
            }
            return prog
        } else {
            return allIncludedPrograms.randomElement()!
        }
    }

    private func regenProgramList() {
        assert(programExecutionQueue.count == 0)
        let covEdgesBuffPtr = covEvaluator.getEdgeCountPtr()!
        // Per https://developer.apple.com/documentation/swift/unsafebufferpointer, making an array from an UnsafeBufferPtr copies the memory
        var covEdgesArr = Array(covEdgesBuffPtr)
        covEdgesArr.sort()

        // Find the edge with the smallest count
        var startIndex = -1
        for (i, val) in covEdgesArr.enumerated() {
            if startIndex == -1 && val != 0 {
                startIndex = i
                break
            }
        }
        assert(startIndex != -1)
        
        // Find the nth interesting edge's count
        let desiredEdgeCount = max(size / 8, 30)
        let endIndex = min(startIndex + desiredEdgeCount, covEdgesArr.count - 1)
        let maxEdgeCountToFind = covEdgesArr[endIndex]
        let amountToAge = energyBase() * numConsecutiveMutations // Likely overaggressive

        // Find the n edges with counts <= maxEdgeCountToFind. Age them appropriately,
        // to ensure non-deterministic samples are not continuously selected
        for (i, val) in covEdgesBuffPtr.enumerated() {
            // Applies dropout on otherwise valid samples, to ensure variety between instances
            // This will likely select some samples multiple times, which is acceptable as
            // it is proportional to how many infrquently hit edges the sample has
            if val != 0 && val <= maxEdgeCountToFind && probability(0.25){ 
                if let prog = edgeMap[UInt64(i)] {
                    programExecutionQueue.append(prog)
                    covEdgesBuffPtr[i] += amountToAge
                } else {
                    logger.warning("Failed to find edge in map")
                }
            }
        }
        assert(programExecutionQueue.count > 0)
        logger.info("Markov Corpus selected \(programExecutionQueue.count) new programs")
    }

    public func exportState() throws -> Data {
        let res = try encodeProtobufCorpus(allIncludedPrograms)
        logger.info("Successfully serialized \(allIncludedPrograms.count) programs")
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)        
        for prog in newPrograms { 
            add(prog, ProgramAspects(outcome: .succeeded))
        }
    }

    public var size: Int {
        return allIncludedPrograms.count + 1
    }
    
    public var isEmpty: Bool {
        return size == 0
    }

    public subscript(index: Int) -> Program {
        return allIncludedPrograms[index]
    }

    // Ramp up amount of energy over time
    private func energyBase() -> UInt64 {
        return UInt64(Foundation.log10(Float(totalExecs))) + 1 
    }

}
