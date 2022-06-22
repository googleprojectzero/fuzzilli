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

struct ProgramWeightedAction {
    // Index into the program array used by the corpus
    let programIndex: Int
    let index: Int
    var weight: Double

    var programsFound: Int
    // Original current reward
    var latestReward: Double
    // Previous recorded normalised reward
    var previousReward: Double

    // Count of number of times the program was successful when selected
    var invocationCount: Int
    
    // Age of the program
    var age: Int

    // Original reward sums essential for performing normalisation used to get standard deviation
    // Accumulated sum of original reward squared
    var sumOfSquaredRewards: Double
    // Accumulated sum of original reward
    var sumOfRewards: Double

    // G^(t+1) = Accumulated sum of x^(t) the total reward of a program for MAB
    var estimatedTotalReward: Double
    
}

extension Array where Element == ProgramWeightedAction {
    /// Returns the probability of the program in the array
    func probability(for cache:[Int], withAction action: ProgramWeightedAction) -> Double {
        return action.weight/Double(self.totalWeights(cache))
    }

    /// Returns the probability of the program in the array
    func probability(for cache:[Int], withAction action: ProgramWeightedAction, withGamma gamma: Double) -> Double {
       return ((1.0-gamma) * (action.weight / self.totalWeights(cache))) + (gamma / Double(cache.count)) 
    }
    
    /// Returns the estimated reward x^(t) of the program in the array with gamma
    func estimatedReward(for cache:[Int], withAction action: ProgramWeightedAction, withGamma gamma: Double) -> Double {
        let reward = action.latestReward
        let probability = self.probability(for: cache, withAction: action,withGamma: gamma)
        let estimatedReward = Double(reward) / Double(probability)
        return estimatedReward
    }

    /// Returns the new evaluated weight for the weighted action of the action in the array for a given gamma 
    func newWeight(for cache:[Int],withSelectedAction action: ProgramWeightedAction, andGamma gamma: Double) -> Double {
        return action.weight * exp(gamma*(estimatedReward(for: cache, withAction:action, withGamma: gamma)/Double(cache.count)))
    }

    /// Identifies and returns the max estimated reward in the weighted action array
    func programActionWithMaxEstimatedTotalReward(for cache: [Int]) -> ProgramWeightedAction {
        let index = cache.max{self[$0].estimatedTotalReward < self[$1].estimatedTotalReward}
        return self[index!]
    }

    /// Creates the probability distribution from thw eights in weighted actions
    func generateProbabilityDistribution(for cache:[Int]) -> [Double] {
        return cache.map({self.probability(for: cache, withAction: self[$0])})
    }

    /// Creates the probability distribution from thw eights in weighted actions
    /// with gamma value for MAB
    func generateProbabilityDistribution(for cache:[Int], withGamma gamma: Double) -> [Double] {
        return cache.map({self.probability(for: cache, withAction: self[$0], withGamma: gamma)})
    }

    /// Total weight sum of the weighted actions
    func totalWeights(_ cache:[Int]) -> Double {
        return cache.map({ self[$0].weight }).reduce(0, +)
    }

    /// Total occurence sum of the weighted actions
    var totalOccurences: Double {
        let total = Double(self.map({ $0.invocationCount }).reduce(0, +)) 
        return total > 0.0 ? total : Double(self.count)
    }

    func totalprogramsFound() -> Double {
        let val = Double(self.map({ $0.programsFound }).reduce(0, +)) 
        return val == 0 ? 1 : val 
    }

    /// Generates an enumerated array for Program
    func generateEnumeratedProgramList(for cache:[Int]) -> [(index: Int, weightedActionIndex: Int)] {
        return cache.enumerated().map({(index: $0.offset, weightedActionIndex: $0.element)})
    }
}

public class ProgramMultiArmedBandit {

    /// Defines the critical mass threshold of fuzz loop iterations to consider for evaluation
    public var critMassThreshold: Int
    /// Restart threshold
    private let restartThreshold: Int = 100_000
    /// Defines max cache size
    public let maxCacheSize: Int
    /// Defines the min number of mutations for a program
    public let minMutationsPerSample: Int
    /// Defines the threshold at which we regenerate the cache
    public let regenerateThreshold: Int
    /// Defines the current cache regeneration counter
    public var cacheRegenerateCounter: Int
    /// Defines the epochs(r) reached where a guess is made for the best action
    public var epochs: Int
    /// Defines number of trials(t) elapsed in MAB
    public var trials: Int
    /// Defines gamma for the execution of Exp3.1 
    public var gamma: Double
    /// Current threshold for epoch change
    public var epochThreshold: Double
    /// The array of weighted actions for the weighted list items
    private var weightedActions: [ProgramWeightedAction]
    /// Selected program chosen at random from probability distribution
    private var selectedProgram: Int
    /// Selected program index chosen at random from probability distribution
    private var selectedProgramWeightedActionIndex: Int
    /// Selected cache index chosen at random from probability distribution
    private var selectedProgramWeightedActionCacheIndex: Int
    /// Cache of Program Weighted Actions
    private var cache: [Int] 
    /// Set of available programs that haven't had min number of mutations
    private var availablePrograms: Set<Int>
    public var covScoreInitial: Double
    

    /// takes a weighted list of program indexes
    init(critMassThreshold: Int, maxCacheSize: Int, minMutationsPerSample: Int, regenerateThreshold: Int) {
        self.epochs = 0
        self.trials = 1
        self.gamma = 1.0
        self.epochThreshold = 0.0
        self.selectedProgram = -1
        self.selectedProgramWeightedActionIndex = -1
        self.selectedProgramWeightedActionCacheIndex = -1
        self.covScoreInitial = 0.0

        self.critMassThreshold = critMassThreshold
        self.maxCacheSize = maxCacheSize
        self.minMutationsPerSample = minMutationsPerSample
        self.regenerateThreshold = regenerateThreshold

        // Since we start with an empty corpus
        self.weightedActions = []
        self.availablePrograms = []
        self.cache = []
        self.cacheRegenerateCounter = regenerateThreshold
    }

    /// Coverage Score for MAB instance
    public func programsFoundMAB() -> Double {
        return weightedActions.totalprogramsFound()
    }

    /// The totalWeight sum of the weighted actions
    private var totalWeights: Double {
        return weightedActions.totalWeights(cache)
    }

    /// The totalOccurences sum of the weighted actions
    private var totalOccurences: Double {
        return weightedActions.totalOccurences
    }

    /// Evaluates the new weightedList weights in response to the randomly chosen elements reward
    public func updateWeightedActionsIfEpochNotReached() {
        if !epochReached() {
            let action = weightedActions[selectedProgramWeightedActionIndex]
            let gammaValue = self.gamma
            let newWeight = weightedActions.newWeight(for:self.cache, withSelectedAction: action, andGamma: gammaValue)
            self.weightedActions[action.index].weight = newWeight
        }
    }

    /// Update trials and Totalestimated rewards if epoch not reached
    public func updateTotalEstimatedRewardIfEpochNotReached() {
        if !epochReached() {
            let action = weightedActions[selectedProgramWeightedActionIndex]
            let estimatedReward = weightedActions.estimatedReward(for:self.cache, withAction: action, withGamma: self.gamma)
            self.weightedActions[action.index].estimatedTotalReward += estimatedReward
        }
    }

    /// Update trials and Totalestimated rewards if epoch not reached
    public func updateTrialsIfEpochNotReached() {
        if !epochReached() {
            self.trials += 1
        }
    }

    /// Restart MAB if there are fewer available programs than the max cache size
    /// and the total weighted actions is greater than the max cache size
    public func restartThresholdReached(_ iterations: Int) -> Bool {
        if availablePrograms.count < maxCacheSize && weightedActions.count > maxCacheSize {
            return true
        }
        return false
    }

    public func restartMAB() {
        assert(weightedActions.count != 0, "Cannot have empty list of actions!")
        self.trials = 1
        self.gamma = getGamma(bestAction: bestAction())
        self.selectedProgramWeightedActionIndex = -1
        self.selectedProgramWeightedActionCacheIndex = -1
        for (idx, _) in weightedActions.enumerated() {
            self.weightedActions[idx].weight = 1.0
            self.weightedActions[idx].programsFound = 0
            self.weightedActions[idx].latestReward = 0.0
            self.weightedActions[idx].previousReward = 0.0
            self.weightedActions[idx].invocationCount = 1
            self.weightedActions[idx].age = 0
            self.weightedActions[idx].sumOfSquaredRewards = 0.0
            self.weightedActions[idx].sumOfRewards = 0.0
            self.weightedActions[idx].estimatedTotalReward = 0.0

            availablePrograms.insert(idx)
        }

        var candidates = Set<Int>()
        while candidates.count < maxCacheSize {
            candidates.insert(availablePrograms.randomElement()!)
        }
        self.cache = candidates.map({ $0 })
    }

    public func addProgramWeightedAction(programIndex:Int) {
        let index = weightedActions.count
        weightedActions.append(ProgramWeightedAction(
            programIndex:programIndex, 
            index:index, 
            weight: 1.0, 
            programsFound: 1,
            latestReward: 0.0,
            previousReward: 0.0, 
            invocationCount: 1,
            age: 0,
            sumOfSquaredRewards: 0.0,
            sumOfRewards: 0.0,
            estimatedTotalReward: 0.0))
        
        // Append programs to the available program pool
        availablePrograms.insert(index)

        // Append programs to the cache if it isn't full
        if cache.count < maxCacheSize  {
            cache.append(index)
        }
    }

    /// Evaluates if the epoch(r) is reached for the new gamma value (gamma(r))
    public func epochReached() -> Bool {
        let action = weightedActions.programActionWithMaxEstimatedTotalReward(for: cache)
        let bestAction = bestAction()
        self.gamma = getGamma(bestAction: bestAction)
        self.epochThreshold = bestAction - (Double(self.cache.count)/self.gamma)

        // Check if the estimated reward is less than or equal to the difference between guess for a bestAction (g(r)) and tune gamma.
        // restarting Exp3 at the beginning of each epoch.
        if action.estimatedTotalReward <= self.epochThreshold {
            return false
        }
        return true
    }

    /// Increment the epoch(r) 
    public func epochCountUpdate() {
        self.epochs += 1
    }

    /// Evaluate if the num of programs selected has reached a critical mass threshold
    public func critMassProgramsReached(_ numProgramSelections: Int) -> Bool {
       if numProgramSelections % self.critMassThreshold == 0 {
            return true
        }
        return false
    }

    public func rescaleCacheWeights() {
        let max = cache.map({ weightedActions[$0].weight }).max()!
        let min = cache.map({ weightedActions[$0].weight }).min()!
        let lowerWeightBound = 1.0
        let upperWeightBound = 2.0 * Double(maxCacheSize) 

        guard max > min else { return }

        for idx in cache {
            self.weightedActions[idx].weight = lowerWeightBound + (((weightedActions[idx].weight - min)*(upperWeightBound - lowerWeightBound))/(max - min))
        }

        // Decrement the cache regeneration counter
        self.cacheRegenerateCounter -= 1
    }

    public func shouldRegenerateCache() -> Bool {
        return !epochReached() && cacheRegenerateCounter <= 0
    }

    /// Once we have a min number of programs in a corpus we generate a cache of programs that we perform mab on
    /// This is done to improve performance rather than running mab over the entire corpus.
    public func regenerateCache() {
        // Reset counter
        cacheRegenerateCounter = regenerateThreshold

        // Since we are going to regenerate the cache with new programs, we also reset the epoch counter and gamma.
        self.trials = 1
        self.epochs = 0
        self.selectedProgramWeightedActionIndex = -1
        self.selectedProgramWeightedActionCacheIndex = -1

        print("Regenerating cache!")
        var candidates = Set<Int>()
        while candidates.count < maxCacheSize {
            // TODO: Maybe we can do better than random element selection?
            // Previous attempts to use a global average of programs found hasn't worked.
            let idx = availablePrograms.randomElement()!
            if !cache.contains(idx) {
                candidates.insert(idx)
            }
        }
        self.cache = candidates.map({ $0 })
        for idx in self.cache {
            print("Adding \(idx) to cache")
            self.weightedActions[idx].programsFound = 0
            self.weightedActions[idx].invocationCount = 1
            self.weightedActions[idx].latestReward = 0.0
            self.weightedActions[idx].previousReward = 0.0
            self.weightedActions[idx].sumOfSquaredRewards = 0.0
            self.weightedActions[idx].sumOfRewards = 0.0
            self.weightedActions[idx].estimatedTotalReward = 0.0
        }

        // Rescale weights
        let max = cache.map({ weightedActions[$0].weight }).max()!
        let min = cache.map({ weightedActions[$0].weight }).min()!
        let lowerWeightBound = 1.0
        let upperWeightBound = 2.0 * Double(maxCacheSize) 

        guard max > min else { return }

        for idx in cache {
            self.weightedActions[idx].weight = lowerWeightBound + (((weightedActions[idx].weight - min)*(upperWeightBound - lowerWeightBound))/(max - min))
        }
    }

    //Reset Max total estimated reward for the cache at epoch change
    public func resetMaxEstimatedTotalRewardForCache() {
        weightedActions[weightedActions.programActionWithMaxEstimatedTotalReward(for: cache).index].estimatedTotalReward = 0.0

        // Reset the regenerate cache counter since we have reached an epoch
        cacheRegenerateCounter = regenerateThreshold
    }

    /// Displays Stats on the current state of the weighted list
    public func toString() -> String {
        var stats = ""
        cache.forEach { index in
                stats += "P#\(weightedActions[index].programIndex) ".padding(toLength: 10, withPad: " ", startingAt: 0)
                stats += "Weight: \(String(format: "%.3f%", weightedActions[index].weight)), programsFound: \(String(weightedActions[index].programsFound)), invocationCount: \(weightedActions[index].invocationCount), estimatedTotalReward: \(String(format: "%.4f%", weightedActions[index].estimatedTotalReward)), sumOfSquaredRewards: \(String(format: "%.4f%", weightedActions[index].sumOfSquaredRewards)), sumOfRewards: \(String(format: "%.4f%", weightedActions[index].sumOfRewards))\n"
        }
        return stats
    }

    /// Generate a JSON string for the program stats
    public func toJSON() -> String {
        var stats = "\"Programs\":{"
        cache.forEach { index in
            stats += "\"\(weightedActions[index].programIndex)\":{"
            stats += "\"Weight\": \(String(format: "%.3f%", weightedActions[index].weight)), \"programsFound\": \(String(weightedActions[index].programsFound)), \"invocationCount\": \(weightedActions[index].invocationCount), \"estimatedTotalReward\": \(String(format: "%.4f%", weightedActions[index].estimatedTotalReward)), \"sumOfSquaredRewards\": \(String(format: "%.4f%", weightedActions[index].sumOfSquaredRewards)), \"sumOfRewards\": \(String(format: "%.4f%", weightedActions[index].sumOfRewards))},"
        }
        stats += "}"
        return stats
    }

    /// Selects a random element according to MAB Exp3 algorithm
    public func randomElement() -> Int {
        //Set selectedProgramCacheIndex for weighted Actions
        (self.selectedProgramWeightedActionCacheIndex, self.selectedProgramWeightedActionIndex, self.selectedProgram) = selectProgramWithProbabilityDistribution() 
        
        // Remove the program from available programs if it has reached minMutationsPerSample
        if weightedActions[selectedProgramWeightedActionIndex].age >= minMutationsPerSample {
            availablePrograms.remove(weightedActions[selectedProgramWeightedActionIndex].index)
        } else {
            // Increment the age of the selected program
            weightedActions[selectedProgramWeightedActionIndex].age += 1
        }

        return selectedProgram
    }

    /// Selects a program to splice from the program cache
    public func randomElementForSplicing() -> Int {
        let enumeratedList = weightedActions.generateEnumeratedProgramList(for: cache)
        let probabilities = weightedActions.generateProbabilityDistribution(for: cache)
        let (index, _) = choose(from: enumeratedList, withProbabilityDistribution: probabilities)
        return weightedActions[index].programIndex
    }

    /// Creates the random item selection array on the calculated MAB arm probability distribution 
    private func selectProgramWithProbabilityDistribution() ->  (Int, Int, Int) {
        let enumeratedList = weightedActions.generateEnumeratedProgramList(for: cache)
        let bestAction = bestAction()
        self.gamma = getGamma(bestAction: bestAction)
        let probabilitiesWithGamma = weightedActions.generateProbabilityDistribution(for: cache, withGamma: self.gamma)
        let choice:(index:Int, weightedActionIndex:Int) = choose(from: enumeratedList, withProbabilityDistribution: probabilitiesWithGamma)
        return (choice.index, choice.weightedActionIndex, weightedActions[choice.index].programIndex)
    }
    
    // Epoch(r) driven by guess for reward g(r) = ((K*ln(K))/(e − 1))*4^r to drive the gamma selection 
    private func bestAction() -> Double {
        //K*ln(K)
        let numerator = cache.isEmpty ? Double(weightedActions.count)*log(Double(weightedActions.count)): Double(self.cache.count)*log(Double(self.cache.count))
        // e-1
        let denominator = exp(1.0) - 1.0

        //g(r) = ((K*ln(K))/weightedActions[index].invocationCount += 1(e − 1))*4^r
        return (numerator / denominator) * pow(4.0,Double(self.epochs))
    }

    /// Defines the gamma value that guides the MAB algorithm
    private func getGamma(bestAction: Double) -> Double {
        //g(r) value
        let bestGuessEstimate = bestAction
        //upperbound for gamma 
        // K*ln(K)
        let numerator = cache.isEmpty ? Double(weightedActions.count)*log(Double(weightedActions.count)): Double(self.cache.count)*log(Double(self.cache.count))
        // (e-1)*g(r)
        let denominator = (exp(1.0) - 1.0) * Double(bestGuessEstimate)
        
        // min[1,sqrt((K*ln(K))/((e-1)*g(r)))]
        let upperBound = sqrt(numerator/denominator)
        return [1.0,upperBound].min()!
    }

    /// Called when execution of a program is successful
    public func evaluateProgramSuccess() {
        // Recent new programs found
        self.weightedActions[selectedProgramWeightedActionIndex].programsFound += 1
        weightedActions[selectedProgramWeightedActionIndex].invocationCount += 1
    }

    /// Called when an execution of a program does not succeed
    public func evaluateProgramFailure() {
        weightedActions[selectedProgramWeightedActionIndex].invocationCount += 1
    }

    public func evaluateTotal(iterations: Int) {
        let index = selectedProgramWeightedActionIndex

        //average programs generated per iteration
        let avgProgramsGeneratedPerIteration = (Double(weightedActions[index].programsFound) / Double(weightedActions[index].invocationCount)) * Double(iterations)

        // update previous reward
        weightedActions[index].previousReward = weightedActions[index].latestReward

        // update sums of rewards 
        weightedActions[index].sumOfSquaredRewards += pow(avgProgramsGeneratedPerIteration, 2)
        weightedActions[index].sumOfRewards += avgProgramsGeneratedPerIteration
        
        // for every coverage found value in actual range bind it between (-1,1) for faster convergence
        weightedActions[index].latestReward = logisticNormalise(value: avgProgramsGeneratedPerIteration, index: index)
    }

    /// Standard deviation for Program
    private func standardDeviation(for index: Int) -> Double {
        let action = weightedActions[index]
        return sqrt((action.sumOfSquaredRewards / Double(action.invocationCount))-pow((action.sumOfRewards) / Double(action.invocationCount),2))
    }

    /// Shifted Logistic function to normalise value in range (-1,1) 
    /// where 0 value is normalised to 0 in the normalised range
    private func logisticNormalise(value: Double, index: Int) -> Double {
        // Logistic function : https://www.tjmahr.com/anatomy-of-a-logistic-growth-curve/
        let z = zscore(value: value, index: index)
        // Handle for e^-infinity values
        let normalised = (1.0-exp(-1.0*z.value))/(1.0+exp(-1.0*z.value))
        guard !normalised.isNaN else { return 1 }
        return (1.0-exp(-1.0*z.value))/(1.0+exp(-1.0*z.value))
    }

    /// Zscore value for normalisation function
    private func zscore(value: Double, index: Int) -> (value: Double, sign: Double) {
        let standardDeviation = standardDeviation(for: index)
        return (value: value/standardDeviation, sign: value >= 0 ? 1.0 : -1.0)
    }

    public typealias ProtobufType = [Fuzzilli_Protobuf_ProgramWeightedAction]

    /// Generates an array of program weight protobufs
    public func exportState() -> ProtobufType {
        var programWeights: ProtobufType = []

        self.weightedActions.forEach { action in
            programWeights.append(Fuzzilli_Protobuf_ProgramWeightedAction.with {
                $0.index = Int32(action.index)
                $0.weight = action.weight
                $0.age = Int32(action.age)
            })
        }

        return programWeights
    }

    /// Initialises program mab from an array of program weights
    public func importState(from proto: ProtobufType) {
        self.epochs = 0
        self.trials = 1
        self.gamma = getGamma(bestAction: bestAction())
        self.selectedProgram = -1
        self.selectedProgramWeightedActionIndex = -1
        self.selectedProgramWeightedActionCacheIndex = -1
        self.cache = []
        self.covScoreInitial = 0.0

        for (idx, program) in proto.enumerated() {
            self.weightedActions.append(ProgramWeightedAction(
                programIndex: Int(program.index),
                index: idx,
                weight: program.weight,
                programsFound: 1,
                latestReward: 0.0,
                previousReward: 0.0,
                invocationCount: 1,
                age: Int(program.age),
                sumOfSquaredRewards: 0.0,
                sumOfRewards: 0.0,
                estimatedTotalReward: 0.0))

            // Append programs to the available program pool
            if program.age < minMutationsPerSample {
                availablePrograms.insert(Int(program.index))

                // Append programs to the cache if it isn't full
                if cache.count < maxCacheSize  {
                    cache.append(Int(program.index))
                }
            }
        }
    }
}