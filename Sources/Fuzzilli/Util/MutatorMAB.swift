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

struct MutatorWeightedAction {
    let mutator: Mutator
    let index: Int
    var weight: Double

    // Original current reward
    var newCoverageFound: Double
    // Normalised current reward x(t) for a mutator
    var latestReward: Double
    // Previous recorded normalised reward
    var previousReward: Double

    // Total coverage found by a mutator
    var totalCoverageFound: Double
    // Count of muatator invocation 
    var invocationCount: Int

    // Original reward sums essential for performing normalisation used to get standard deviation
    // Accumulated sum of original reward squared
    var sumOfSquaredRewards: Double
    // Accumulated sum of original reward
    var sumOfRewards: Double

    // G^(t+1) = Accumulated sum of x^(t) the total reward of a mutator for MAB
    var estimatedTotalReward: Double
    
}

extension Array where Element == MutatorWeightedAction {
    /// Returns the probability of the mutator in the array
    func probability(forAction action: MutatorWeightedAction) -> Double {
        return action.weight/Double(self.totalWeights)
    }

    /// Returns the probability of the mutator in the array
    func probability(forAction action: MutatorWeightedAction, withGamma gamma: Double) -> Double {
       return ((1.0-gamma) * (action.weight / self.totalWeights)) + (gamma / Double(self.count)) 
    }
    
    /// Returns the estimated reward x^(t) of the mutator in the array with gamma
    func estimatedReward(forAction action: MutatorWeightedAction, withGamma gamma: Double) -> Double {
        let reward = action.latestReward
        let probability = self.probability(forAction: action, withGamma: gamma)
        let estimatedReward = Double(reward) / Double(probability)
        return estimatedReward
    }

    /// Returns the new evaluated weight for the weighted action of the action in the array for a given gamma 
    func newWeight(forSelectedAction action: MutatorWeightedAction, andGamma gamma: Double) -> Double {
        return action.weight * exp(gamma*(estimatedReward(forAction:action,withGamma: gamma)/Double(self.count)))
    }

    /// Identifies and returns the max estimated reward in the weighted action array
    func mutatorActionWithMaxEstimatedTotalReward() -> MutatorWeightedAction {
        let action = self.max{$0.estimatedTotalReward < $1.estimatedTotalReward}
        return action!
    }

    /// Creates the probability distribution from thw eights in weighted actions
    func generateProbabilityDistribution() -> [Double] {
        return self.map({probability(forAction: $0)})
    }

    /// Creates the probability distribution from thw eights in weighted actions
    /// with gamma value for MAB
    func generateProbabilityDistribution(withGamma gamma: Double) -> [Double] {
        return self.map({probability(forAction: $0, withGamma: gamma)})
    }

    /// Total weight sum of the weighted actions
    var totalWeights: Double {
        return self.map({ $0.weight }).reduce(0, +)
    }

    /// Total occurence sum of the weighted actions
    var totalOccurences: Double {
        let total = Double(self.map({ $0.invocationCount }).reduce(0, +)) 
        return total > 0.0 ? total : Double(self.count)
    }

    func totalCoverageMAB() -> Double {
        let val = Double(self.map({ $0.totalCoverageFound }).reduce(0, +)) 
        return val == 0 ? 1 : val 
    }

    /// Generates an enumerated array for mutator
    func generateEnumeratedMutatorList() -> [(index: Int, mutator: Mutator)] {
        return self.map({(index: $0.index, mutator: $0.mutator)})
    }
    
    var maxWeight: Double {
        let action = self.max{$0.weight < $1.weight}
        return action!.weight
    }

    var minWeight: Double {
        let action = self.min{$0.weight < $1.weight}
        return action!.weight

    }

}

/// Tracker for capturing mutation calls and coverage
typealias SimultaneousMutationTracker = (index: Int, calls: Int, newCoverageFound: Double)

public class MutatorMultiArmedBandit {

    /// Defines the critical mass threshold of fuzz loop iterations to consider for evaluation
    public var critMassThreshold: Int = 500
    /// Restart threshold
    public let restartThreshold: Int = 300_000
    /// Defines the epochs(r) reached where a guess is made for the best action
    public var epochs: Int
    /// Defines number of trials(t) elapsed in MAB
    public var trials: Int
    /// Defines gamma for the execution of Exp3.1 
    public var gamma: Double
    /// Current threshold for epoch change
    public var epochThreshold: Double
    /// The array of weighted actions for the weighted list items
    private var weightedActions: [MutatorWeightedAction]
    /// Selected mutator chosen at random from probability distribution
    private var selectedMutator: Mutator
    /// Selected mutator index chosen at random from probability distribution
    private var selectedMutatorIndex: Int
    /// Track simultaneous mutations
    private var simultaneousMutations:  [SimultaneousMutationTracker]
    /// Get coverage Score at the Begining of fuzzOne
    public var covScoreInitial: Double
    

    /// takes a weighted list (e.g. fuzzer.mutators)
    init(actions weightedItems: WeightedList<Mutator>) {
        assert(weightedItems.count != 0, "Cannot have empty list of actions!")
        self.epochs = 0
        self.trials = 1
        self.gamma = 1.0
        self.epochThreshold = 0.0
        self.selectedMutator = Mutator()
        self.selectedMutatorIndex = -1
        self.covScoreInitial = 0.0

        self.weightedActions = weightedItems.elems.enumerated().map({MutatorWeightedAction(
                mutator: $0.element.element, 
                index:$0.offset, 
                weight: Double($0.element.weight), 
                newCoverageFound: 0.0,
                latestReward: 0.0,
                previousReward: 0.0, 
                totalCoverageFound:0.0,
                invocationCount: 1,
                sumOfSquaredRewards: 0.0,
                sumOfRewards: 0.0,
                estimatedTotalReward: 0.0)})  
        self.simultaneousMutations = weightedItems.elems.enumerated().map({(index: $0.offset, calls: 0, newCoverageFound: 0.0)})
    }
    
    public func restartThresholdReached(_ iterations: Int) -> Bool {
        if iterations % restartThreshold == 0 {
            return true
        }
        return false
    }

    // Restart MAB to preserve algorithm stability over indefinite fuzzing runs
    public func restartMAB() {
        assert(weightedActions.count != 0, "Cannot have empty list of actions!")
        self.epochs = 0
        self.trials = 1
        self.gamma = getGamma(bestAction: bestAction())
        self.selectedMutator = Mutator()
        self.selectedMutatorIndex = -1
        //TODO: consider removal as its a debug feature
        self.covScoreInitial = 0.0 
        let max = weightedActions.maxWeight
        let min = weightedActions.minWeight
        let lowerWeightBound = 1.0
        let upperWeightBound = 2.0 * Double(weightedActions.count) 
        for (idx, _) in weightedActions.enumerated() {
            //Scale the weight values
            self.weightedActions[idx].weight = max > min ? lowerWeightBound + (((weightedActions[idx].weight - min)*(upperWeightBound - lowerWeightBound))/(max - min)) : self.weightedActions[idx].weight
            self.weightedActions[idx].newCoverageFound = 0.0
            self.weightedActions[idx].latestReward = 0.0
            self.weightedActions[idx].previousReward = 0.0
            self.weightedActions[idx].totalCoverageFound = 0.0
            self.weightedActions[idx].invocationCount = 1
            self.weightedActions[idx].sumOfSquaredRewards = 0.0
            self.weightedActions[idx].sumOfRewards = 0.0
            self.weightedActions[idx].estimatedTotalReward = 0.0
        }
        self.simultaneousMutations = weightedActions.map({(index: $0.index, calls: 0, newCoverageFound: 0.0)})
    }
    
    // Reset MAB at epoch change
    public func resetMaxEstimatedTotalReward() {
        // Reset max total estimated reward
        weightedActions[weightedActions.mutatorActionWithMaxEstimatedTotalReward().index].estimatedTotalReward = 0.0
    }

    /// Rescale weights
    public func rescaleWeights() {
        let max = weightedActions.maxWeight
        let min = weightedActions.minWeight

        guard max > min else { return }

        let lowerWeightBound = 1.0
        let upperWeightBound = 2.0 * Double(weightedActions.count) 
        for (idx, _) in weightedActions.enumerated() {
            //Scale the weight values
            self.weightedActions[idx].weight = lowerWeightBound + (((weightedActions[idx].weight - min)*(upperWeightBound - lowerWeightBound))/(max - min))
        }
    }

    /// Coverage Score for MAB instance
    public func coverageScoreMAB() -> Double {
        return weightedActions.totalCoverageMAB()
    }

    /// The Total simultaneous mutations
    private var totalCalls: Double {
        return Double(self.simultaneousMutations.map({ $0.calls }).reduce(0, +)) 
    }

    public func resetSimultaneousMutationTracker() {
        self.simultaneousMutations = weightedActions.map({(index: $0.index, calls: 0, newCoverageFound: 0.0)})
    }

    /// The totalWeight sum of the weighted actions
    private var totalWeights: Double {
        return weightedActions.totalWeights
    }

    /// The totalOccurences sum of the weighted actions
    private var totalOccurences: Double {
        return weightedActions.totalOccurences
    }

    /// Evaluates the new weightedList weights in response to the randomly chosen elements reward
    public func updateWeightedActionsIfEpochNotReached() {
        if !epochReached() {
            if totalCalls > 0{
                for (index,calls,_) in self.simultaneousMutations where calls > 0 {
                    let action = weightedActions[index]
                    let gammaValue = self.gamma
                    let newWeight = weightedActions.newWeight(forSelectedAction: action, andGamma: gammaValue)
                    self.weightedActions[action.index].weight = newWeight
                }
            }
        }
    }

    /// Update trials and Totalestimated rewards if epoch not reached
    public func updateTotalEstimatedRewardIfEpochNotReached() {
        if !epochReached() {
            if totalCalls > 0 {
                for (index,calls,_) in self.simultaneousMutations where calls > 0 {
                    let action = weightedActions[index]
                    let estimatedReward = weightedActions.estimatedReward(forAction: action, withGamma: self.gamma)
                    self.weightedActions[action.index].estimatedTotalReward += estimatedReward
                }
            }
        }
    }
    /// Update trials and Totalestimated rewards if epoch not reached
    public func updateTrialsIfEpochNotReached() {
        if !epochReached() {
            self.trials += 1
        }
    }

    /// Evaluates if the epoch(r) is reached for the new gamma value (gamma(r))
    public func epochReached() -> Bool {
        let action = weightedActions.mutatorActionWithMaxEstimatedTotalReward()
        let bestAction = bestAction()
        self.gamma = getGamma(bestAction: bestAction)
        self.epochThreshold = bestAction - (Double(self.weightedActions.count)/self.gamma)

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


    /// Evaluate if the threshold iterations of the fuzzer is reached
    public func critMassIterationsReached(_ iterations: Int) -> Bool {
       if iterations % self.critMassThreshold == 0 {
            return true
        }
        return false
    }

    /// Identifies the current selected mutator
    public func selectedMutatorType() -> Mutator {
        return self.selectedMutator
    }

    /// Displays Stats on the current state of the weighted list
    public func toString() -> String {
        var stats = ""
        weightedActions.forEach { action in
            stats += "\(action.mutator.name) ".padding(toLength: 26, withPad: " ", startingAt: 0)
            stats += "Weight: \(String(format: "%.3f%", action.weight)), totalCoverageFound: \(String(format: "%.4f%", action.totalCoverageFound)), invocationCount: \(action.invocationCount), estimatedTotalReward: \(String(format: "%.4f%", action.estimatedTotalReward)), sumOfSquaredRewards: \(String(format: "%.4f%", action.sumOfSquaredRewards)), sumOfRewards: \(String(format: "%.4f%", action.sumOfRewards))\n"
        }
        return stats
    }

    /// Generate a JSON string for the mutator stats
    public func toJSON() -> String {
        var stats = "\"Mutators\":{"
        weightedActions.forEach { action in
            stats += "\"\(action.mutator.name)\":{"
            stats += "\"Weight\": \(String(format: "%.3f%", action.weight)), \"CoverageFound\": \(String(format: "%.4f%", action.newCoverageFound)), \"invocationCount\": \(action.invocationCount), \"Correctness Rate\": \"\(String(format: "%.2f%%", action.mutator.stats.correctnessRate * 100))\", \"estimatedTotalReward\": \(String(format: "%.4f%", action.estimatedTotalReward)), \"sumOfSquaredRewards\": \(String(format: "%.4f%", action.sumOfSquaredRewards)), \"sumOfRewards\": \(String(format: "%.4f%", action.sumOfRewards))},"
        }
        stats += "}"
        return stats
    }

    /// Selects a random element according to MAB Exp3 algorithm
    public func randomElement(mode: BestActionMode) -> Mutator {
        (self.selectedMutatorIndex, self.selectedMutator) = selectMutatorWithProbabilityDistribution(mode: mode)
        if selectedMutatorIndex != -1 {
            self.simultaneousMutations[selectedMutatorIndex].calls += 1
        }
        return selectedMutator
    }


    /// Creates the random item selection array on the calculated MAB arm probability distribution 
    private func selectMutatorWithProbabilityDistribution(mode: BestActionMode) ->  (Int, Mutator) {
        let enumeratedList = self.weightedActions.generateEnumeratedMutatorList()
        switch mode {
            case .other:
                let probabilities = self.weightedActions.generateProbabilityDistribution()
                return choose(from: enumeratedList, withProbabilityDistribution: probabilities)
            case .epoch:
                let bestAction = bestAction()
                self.gamma = getGamma(bestAction: bestAction)
                let probabilitiesWithGamma = self.weightedActions.generateProbabilityDistribution(withGamma: self.gamma)
                return choose(from: enumeratedList, withProbabilityDistribution: probabilitiesWithGamma)
        }
    }

    public enum BestActionMode {
        case epoch
        case other
    }

    // Epoch(r) driven by guess for reward g(r) = ((K*ln(K))/(e − 1))*4^r to drive the gamma selection 
    private func bestAction() -> Double {
        //K*ln(K)
        let numerator = Double(weightedActions.count)*log(Double(weightedActions.count))
        // e-1
        let denominator = exp(1.0) - 1.0

        //g(r) = ((K*ln(K))/(e − 1))*4^r
        return (numerator / denominator) * pow(4.0,Double(self.epochs))
    }

    /// Defines the gamma value that guides the MAB algorithm
    private func getGamma(bestAction: Double) -> Double {
        //g(r) value
        let bestGuessEstimate = bestAction
        //upperbound for gamma 
        // K*ln(K)
        let numerator = Double(weightedActions.count) * log(Double(weightedActions.count))
        // (e-1)*g(r)
        let denominator = (exp(1.0) - 1.0) * Double(bestGuessEstimate)
        
        // min[1,sqrt((K*ln(K))/((e-1)*g(r)))]
        let upperBound = sqrt(numerator/denominator)
        return [1.0,upperBound].min()!
    }

    /// Called when execution of a mutator is successful
    public func evaluateMutationSuccess(newCoverageFound: Double) {
        if self.simultaneousMutations[selectedMutatorIndex].calls > 0 {
            self.simultaneousMutations[selectedMutatorIndex].newCoverageFound += newCoverageFound
        }
    }

    public func evaluateTotal(iterations: Int) {
        if totalCalls > 0 {
            for (index, calls, newCoverageFound) in self.simultaneousMutations where calls > 0 {
                // Update coverage found for mutator
                weightedActions[index].totalCoverageFound += newCoverageFound
                // Recent coverage found for mutator
                weightedActions[index].newCoverageFound = newCoverageFound
                // Update mutator invocation count
                weightedActions[index].invocationCount += calls

                //average coverage 
                let newAvgCoverage = newCoverageFound/Double(calls)
                let globalAvgCoverage = weightedActions[index].totalCoverageFound == 0.0 ? 1.0 : weightedActions[index].totalCoverageFound / Double(weightedActions[index].invocationCount)

                // calculate the iterations for coverage growth 
                let iterationsForCoverageGrowth = (newAvgCoverage / globalAvgCoverage) * Double(iterations)

                // update previous reward
                weightedActions[index].previousReward = weightedActions[index].latestReward

                // update sums of rewards 
                weightedActions[index].sumOfSquaredRewards += pow(iterationsForCoverageGrowth, 2)
                weightedActions[index].sumOfRewards += iterationsForCoverageGrowth
                
                // for every coverage found value in actual range bind it between (-1,1) for faster convergence
                weightedActions[index].latestReward = logisticNormalise(value: iterationsForCoverageGrowth, index: index)
            }
        } 
    }

    /// Called when execution of a mutator fails
    public func evaluateMutationFailure() {
        self.simultaneousMutations[selectedMutatorIndex].newCoverageFound += 0.0
    }

    /// Standard deviation for Mutator
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

    public typealias ProtobufType = [Fuzzilli_Protobuf_WeightedAction]

    /// Generates an array of mutator weight protobufs
    public func exportState() -> ProtobufType {
        var mutatorWeights: ProtobufType = []

        self.weightedActions.forEach { action in
            mutatorWeights.append(Fuzzilli_Protobuf_WeightedAction.with {
                $0.index = Int32(action.index)
                $0.weight = action.weight
            })
        }

        return mutatorWeights
    }

    /// Initialises mutator mab from an array of mutator weights
    public func importState(from proto: ProtobufType) {
        self.epochs = 0
        self.trials = 1
        self.gamma = getGamma(bestAction: bestAction())
        self.selectedMutator = Mutator()
        self.selectedMutatorIndex = -1
        self.covScoreInitial = 0.0

        for (idx, mutator) in proto.enumerated() {
            self.weightedActions[idx].weight = mutator.weight
            self.weightedActions[idx].newCoverageFound = 0.0
            self.weightedActions[idx].latestReward = 0.0
            self.weightedActions[idx].previousReward = 0.0
            self.weightedActions[idx].totalCoverageFound = 0.0
            self.weightedActions[idx].invocationCount = 1
            self.weightedActions[idx].sumOfSquaredRewards = 0.0
            self.weightedActions[idx].sumOfRewards = 0.0
            self.weightedActions[idx].estimatedTotalReward = 0.0
        }
    }
}
