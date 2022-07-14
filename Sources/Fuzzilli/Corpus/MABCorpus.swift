import Foundation

public class MABCorpus: ComponentBase, Corpus {
    // All programs that were added to the corpus so far
    private var allIncludedPrograms: [Program] = []

    // All seeds that we have imported from a compiled corpus
    private var allSeedPrograms: [Program] = []
    
    /// MAB for Programs
    public var mabProgram: ProgramMultiArmedBandit

    /// MAB for seed programs
    public var mabSeedProgram: ProgramMultiArmedBandit

    /// Tracks the number of program selections from the corpus
    public var numProgramSelections: Int = 0

    /// Tracks the number of seed selections from the corpus
    public var numSeedSelections: Int = 0

    /// Corpus deduplicates the runtime types of its programs to conserve memory.
    private var typeExtensionDeduplicationSet = Set<TypeExtension>()

    public init() {
        self.mabProgram = ProgramMultiArmedBandit(critMassThreshold: 100, maxCacheSize: 20, minMutationsPerSample: 16, regenerateThreshold: 2)
        self.mabSeedProgram = ProgramMultiArmedBandit(critMassThreshold: 100, maxCacheSize: 20, minMutationsPerSample: 16, regenerateThreshold: 2)
        super.init(name: "MABCorpus")
    }

    public func evaluateProgramSuccess() {
        mabProgram.evaluateProgramSuccess()
        guard numCompiledSeeds > 0 else { return }
        if fuzzer.isSpliceMutation {
            mabSeedProgram.evaluateProgramSuccess()
        }
    }

    public func evaluateProgramFailure() {
        mabProgram.evaluateProgramFailure()
        guard numCompiledSeeds > 0 else { return }
        if fuzzer.isSpliceMutation {
            mabSeedProgram.evaluateProgramSuccess()
        }
    }

    public func evaluateTotal() {
        mabProgram.evaluateTotal(iterations: numProgramSelections)
    }

    public func evaluateSeedTotal() {
        guard numCompiledSeeds > 0 else { return }
        mabSeedProgram.evaluateTotal(iterations: numSeedSelections)
    }

    public func updateWeightedActionsIfEpochNotReached() {
        mabProgram.updateWeightedActionsIfEpochNotReached()
    }

    public func updateSeedWeightedActionsIfEpochNotReached() {
        guard numCompiledSeeds > 0 else { return }
        mabSeedProgram.updateWeightedActionsIfEpochNotReached()
    }

    public func updateTotalEstimatedRewardIfEpochNotReached() {
        mabProgram.updateTotalEstimatedRewardIfEpochNotReached()
    }

    public func updateSeedTotalEstimatedRewardIfEpochNotReached() {
        guard numCompiledSeeds > 0 else { return }
        mabSeedProgram.updateTotalEstimatedRewardIfEpochNotReached()
    }

    public func updateTrialsIfEpochNotReached() {
        mabProgram.updateTrialsIfEpochNotReached()
    }

    public func updateSeedTrialsIfEpochNotReached() {
        guard numCompiledSeeds > 0 else { return }
        mabSeedProgram.updateTrialsIfEpochNotReached()
    }

    public func getMABCorpusStats() -> String {
            return """
            Program MAB Statistics:
            -----------------------
            Program Selections:         \(numProgramSelections)
            Trial:                      \(mabProgram.trials)
            Epoch:                      \(mabProgram.epochs)
            EpochThreshold:             \(mabProgram.epochThreshold)
            Gamma:                      \(mabProgram.gamma)
            \(mabProgram.toString())
            """
    }

    public func add(_ program: Program, _ aspects: ProgramAspects) {
        guard program.size > 0 else { return }
    
        prepareProgramForInclusion(program, index: self.size)
        deduplicateTypeExtensions(in: program, deduplicationSet: &typeExtensionDeduplicationSet)

        allIncludedPrograms.append(program)
        self.mabProgram.addProgramWeightedAction(programIndex: allIncludedPrograms.count - 1)
    }

   public func addSeed(_ program: Program) {
        guard program.size > 0 else { return }

        self.prepareProgramForInclusion(program, index: self.size)

        self.allSeedPrograms.append(program)
        self.mabSeedProgram.addProgramWeightedAction(programIndex: self.allSeedPrograms.count - 1)
    }
    
    public func randomElementForSplicing() -> Program {
        numSeedSelections += 1
        let prog: Program? = numCompiledSeeds > 0 ? allSeedPrograms[mabSeedProgram.randomElement()] : allIncludedPrograms.randomElement()
        assert(prog != nil && prog!.size > 0)
        return prog!
    }
    
    public func randomElementForMutating() -> Program {
        // Increment the number of program selections
        numProgramSelections += 1
        return allIncludedPrograms[mabProgram.randomElement()]
    }

    public func updateMABState() {
        /// Restart MAB if we have an empty cache
        if mabProgram.restartThresholdReached(numProgramSelections) {
            print("Restarting Corpus MAB")
            mabProgram.restartMAB()
            // TODO: Consider using a power function to grow the values of maxSimultaneousMutations and maxCodeGen
        } else if mabProgram.critMassProgramsReached(numProgramSelections) {
            // estimated reward is less than our guessed upperbound
            if mabProgram.epochReached() {
                // estimated reward is greater than our upperbound, update the epoch count
                mabProgram.epochCountUpdate()
                //As we are in a new epoch reset the codegenerator mab
                mabProgram.resetMaxEstimatedTotalRewardForCache()
            } else {
                // If we reach a critical mass of iterations but not an epoch then 
                // Rescale weights so that we don't encounter crazy run offs
                // and increment the cache age
                mabProgram.rescaleCacheWeights()
            }

            // We may want to regenerate the cache if we aren't finding new coverage from the current cache
            if mabProgram.shouldRegenerateCache() {
                mabProgram.regenerateCache()
            }
        }
    }

    public func updateSeedMABState() {
        guard numCompiledSeeds > 0 else { return }
        /// Restart MAB if we have an empty cache
        if mabSeedProgram.restartThresholdReached(numSeedSelections) {
            print("Restarting Seed MAB")
            mabSeedProgram.restartMAB()
            // TODO: Consider using a power function to grow the values of maxSimultaneousMutations and maxCodeGen
        } else if mabSeedProgram.critMassProgramsReached(numSeedSelections) {
            // estimated reward is less than our guessed upperbound
            if mabSeedProgram.epochReached() {
                // estimated reward is greater than our upperbound, update the epoch count
                mabSeedProgram.epochCountUpdate()
                //As we are in a new epoch reset the codegenerator mab
                mabSeedProgram.resetMaxEstimatedTotalRewardForCache()
            } else {
                // If we reach a critical mass of iterations but not an epoch then 
                // Rescale weights so that we don't encounter crazy run offs
                // and increment the cache age
                mabSeedProgram.rescaleCacheWeights()
            }

            // We may want to regenerate the cache if we aren't finding new coverage from the current cache
            if mabSeedProgram.shouldRegenerateCache() {
                mabSeedProgram.regenerateCache()
            }
        }
    }

    public var size: Int {
        return allIncludedPrograms.count
    }

    public var numCompiledSeeds: Int {
        return allSeedPrograms.count
    }
    
    public var isEmpty: Bool {
        return size == 0
    }

    public func allPrograms() -> [Program] {
        return allIncludedPrograms
    }

    public func allCompiledSeeds() -> [Program] {
        return allSeedPrograms
    }

    public var supportsFastStateSynchronization: Bool {
        return true
    }

    private func addInternal(_ program: Program) {
        if program.size > 0 {
            prepareProgramForInclusion(program, index: self.size)
            deduplicateTypeExtensions(in: program, deduplicationSet: &typeExtensionDeduplicationSet)

            allIncludedPrograms.append(program)
            self.mabProgram.addProgramWeightedAction(programIndex: allIncludedPrograms.count - 1)
        }
    }

    private func addInternalSeed(_ program: Program) {
        if program.size > 0 && program.compiledSeed {
            prepareProgramForInclusion(program, index: self.size)
            deduplicateTypeExtensions(in: program, deduplicationSet: &typeExtensionDeduplicationSet)

            allSeedPrograms.append(program)
            self.mabSeedProgram.addProgramWeightedAction(programIndex: allSeedPrograms.count - 1)
        }
    }

    public func exportState() throws -> Data {
        let res = try encodeProtobufCorpus(allIncludedPrograms)
        logger.info("Successfully serialized \(allIncludedPrograms.count) programs")
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)        
        allIncludedPrograms.removeAll()
        allSeedPrograms.removeAll()
        mabProgram = ProgramMultiArmedBandit(critMassThreshold: 100, maxCacheSize: 20, minMutationsPerSample: 16, regenerateThreshold: 2)
        newPrograms.forEach(addInternal)
    }

    public func exportSeeds() throws -> Data {
        let res = try encodeProtobufCorpus(allSeedPrograms)
        logger.info("Successfully serialized \(allSeedPrograms.count) seed programs")
        return res
    }

    public func importSeeds(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)        
        allSeedPrograms.removeAll()
        mabSeedProgram = ProgramMultiArmedBandit(critMassThreshold: 100, maxCacheSize: 20, minMutationsPerSample: 16, regenerateThreshold: 2)
        newPrograms.forEach(addInternalSeed)
    }
}
