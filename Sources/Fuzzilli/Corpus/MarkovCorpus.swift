import Foundation

/// Corpus & Scheduler based on 
/// Coverage-based Greybox Fuzzing as Markov Chain paper
/// https://mboehme.github.io/paper/TSE18.pdf
/// Simply put, the corpus keeps track of which paths have been found, and prioritizes seeds
/// whose path has been hit less than average. Ideally, this allows the fuzzer to prioritize
/// less explored coverage

public class MarkovCorpus: ComponentBase, Corpus {

    private var allIncludedPrograms: [Program] // All programs currently in the corpus
    private var programExecutionQueue: [Program]  // Queue of programs to be executed next, all of which hit a rare edge

    private var edgeMap: [UInt64:Program]

    private var totalExecs: UInt64

    private var currentProg: Program?

    private var remainingEnergy: UInt64

    public init() {
        self.allIncludedPrograms = []
        self.programExecutionQueue = []
        self.totalExecs = 0
        self.edgeMap = [:]
        self.currentProg = nil
        self.remainingEnergy = 0
        super.init(name: "MarkovCorpus")
    }
    
    override func initialize() {
        // The corpus must never be empty. Other components, such as the ProgramBuilder, rely on this
        if isEmpty {
            for _ in 1...5 {
                let b = fuzzer.makeBuilder()
                let objectConstructor = b.loadBuiltin("Object")
                b.callFunction(objectConstructor, withArgs: [])
                add(b.finalize(), ProgramAspects(outcome: .succeeded))
            }
        }
    }

    // /// Adds an individual program to the corpus.
    // /// This method should only be called for programs from outside sources, such as other connected workers, and imports from disk
    // /// to ensure that new edges are acquired/tracked properly.
    // public func add(_ program: Program) {
    //     guard program.size > 0 else { return }
    //     let execution = fuzzer.execute(program)
    //     guard execution.outcome == .succeeded else { return }
    //     if let aspects = fuzzer.evaluator.evaluate(execution) {
    //         add(program, aspects)
    //     }
    // }

    // /// Adds multiple programs to the corpus.
    // public func add(_ programs: [Program]) {
    //     logger.info("Import of \(programs.count) programs")
    //     for (index, prog) in programs.enumerated() {
    //         if index % 500 == 0 {
    //             logger.info("Markov Corpus import at \(index) of \(programs.count)")
    //         }
    //         add(prog)
    //     }
    // }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        guard program.size > 0 else { return }
        allIncludedPrograms.append(program)
        let edges = aspects.toEdges()
        for e in edges {
            edgeMap[e] = program
        }
    }

    // Switch evenly between programs in the current queue and all programs available to the corpus
    public func randomElementForSplicing() -> Program {
        assert(size > 0)
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
        assert(size > 0)
        // Only do computationally expensive work choosing the next program when there is a solid
        // baseline of execution data
        if totalExecs > 500 {
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

    // Regenerates the internal program list, with dropoff to ensure some diversity among instances
    // Ends up with ~ 1/32th of the Corpus
    private func regenProgramList() {
        assert(programExecutionQueue.count == 0)
        // TODO: Hook things up so that configurable constant "numConsecutiveMutations" is used rather than 5
        let edges = fuzzer.evaluator.smallestEdges(desiredEdgeCount: UInt64(size/8), expectedRounds: energyBase() * 5)!.toEdges()
        for e in edges {
            if let prog = edgeMap[e] {
                if probability(0.25) {
                    programExecutionQueue.append(prog)
                }
            } else {
                logger.warning("Failed to find edge in map")
            }
        }
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

    public var requiresEdgeTracking: Bool {
        true
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

    // Ramp up amount of energy over time
    private func energyBase() -> UInt64 {
        return UInt64(Foundation.log10(Float(totalExecs))) + 1 
    }

}