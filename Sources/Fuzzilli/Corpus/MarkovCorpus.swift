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

    public init() {
        // The corpus must never be empty. Other components, such as the ProgramBuilder, rely on this
        self.allIncludedPrograms = []
        self.programExecutionQueue = []
        self.totalExecs = 0
        self.edgeMap = [:]
        super.init(name: "Corpus")

    }
    
    override func initialize() {
        // The corpus must never be empty
        if self.isEmpty {
            for _ in 1...5 {
                let b = fuzzer.makeBuilder()
                let objectConstructor = b.loadBuiltin("Object")
                b.callFunction(objectConstructor, withArgs: [])
                add(b.finalize())
            }
        }
    }

    /// Adds an individual program to the corpus
    public func add(_ program: Program) {
        if program.size > 0 {
            let execution = fuzzer.execute(program)
            guard execution.outcome == .succeeded else { return }
            if let aspects = fuzzer.evaluator.evaluate(execution) {
                add(program, aspects)
            }
        }
    }

    /// Adds multiple programs to the corpus.
    public func add(_ programs: [Program]) {
        logger.info("Markov Corpus import of \(programs.count) programs")
        for (index, prog) in programs.enumerated() {
            if index % 500 == 0 {
                logger.info("Markov Corpus import at \(index) of \(programs.count)")
            }
            add(prog)
        }
    }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        if program.size > 0 {
            self.allIncludedPrograms.append(program)
            let edges = aspects.toEdges()
            for e in edges {
                self.edgeMap[e] = program
            }
        }
    }

    // Switch evenly between programs in the current queue and all programs available to the corpus
    public func randomElement() -> Program {
        assert(self.size > 0)
        if let prog = self.programExecutionQueue.randomElement(), probability(0.5) {
            assert(prog.size != 0)
            return prog
        }
        let prog = self.allIncludedPrograms.randomElement()!
        assert(prog.size != 0)
        return prog
    }

    public func getNextSeed() -> (seed: Program, energy: UInt64) {
        self.totalExecs += 1
        assert(self.size > 0)
        // Only do computationally expensive work choosing the next program when there is a solid
        // baseline of execution data
        if self.totalExecs > 500 {
            // Check if more programs are needed
            if self.programExecutionQueue.count == 0 {
                self.regenProgramList()
            }
            assert(self.programExecutionQueue.count > 0)
            let prog = self.programExecutionQueue.popLast()!
            return (prog, self.energyBase())
        } else {
            let element = self.allIncludedPrograms.randomElement()!
            return (element, 1)
        }
    }

    // Regenerates the internal program list, with dropoff to ensure some diversity among instances
    // Ends up with ~ 1/32th of the Corpus
    private func regenProgramList() {
        assert(self.programExecutionQueue.count == 0)
        // TODO: Hook things up so that configurable constant "numConsecutiveMutations" is used rather than 5
        let edges = self.fuzzer.evaluator.smallestEdges(desiredEdgeCount: UInt64(self.size/8), expectedRounds: self.energyBase() * 5)!.toEdges()
        for e in edges {
            if let prog = self.edgeMap[e], probability(0.25) {
                self.programExecutionQueue.append(prog)
            }
        }
        logger.info("Markov Corpus selected \(self.programExecutionQueue.count) new programs")
    }

    public func exportState() throws -> Data {
        let res = try encodeProtobufCorpus(self.allIncludedPrograms)
        logger.info("Successfully serialized \(self.allIncludedPrograms.count) programs")
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)        
        add(newPrograms)
    }

    public var requiresEdgeTracking: Bool {
        true
    }

    public var size: Int {
        return self.allIncludedPrograms.count 
    }
    
    public var isEmpty: Bool {
        return size == 0
    }

    public subscript(index: Int) -> Program {
        return self.allIncludedPrograms[index]
    }

    // Ramp up amount of energy over time
    private func energyBase() -> UInt64 {
        return UInt64(Foundation.log10(Float(self.totalExecs))) + 1 
    }

}