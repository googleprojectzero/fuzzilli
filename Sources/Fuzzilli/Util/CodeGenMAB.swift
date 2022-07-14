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

struct CodeGenWeightedAction {
    let codeGenerator: CodeGenerator
    let index: Int
    var weight: Double

    // Original current reward
    var newCoverageFound: Double
    // Normalised current reward x(t) for a mutator
    var latestReward: Double
    // Previous recorded normalised reward
    var previousReward: Double

    //Total coverage found by a mutator
    var totalCoverageFound: Double
    // Count of muatator invocation 
    var invocationCount: Int
    

    // Original reward sums essential for performing normalisation used to get standard deviation
    //Accumulated sum of original reward squared
    var sumOfSquaredRewards: Double
    //Accumulated sum of original reward
    var sumOfRewards: Double

    // G^(t+1) = Accumulated sum of x^(t) the total reward of a mutator for MAB
    var estimatedTotalReward: Double

    func requiredContext(isSubsetOf context: Context) -> Bool {
        return self.codeGenerator.requiredContext.isSubset(of: context)
    }
}

extension Array where Element == CodeGenWeightedAction {
    /// Returns the probability of the CodeGenerator in the array
    func probability(forAction action: CodeGenWeightedAction) -> Double {
        return action.weight/Double(self.totalWeights)
    }

    /// Returns the probability of the CodeGenerator in the array
    func probability(forAction action: CodeGenWeightedAction, withGamma gamma: Double) -> Double {
        return ((1.0-gamma) * (action.weight / self.totalWeights)) + (gamma / Double(self.count)) 
    }

    /// Returns the estimated reward x^(t) of the CodeGenerator in the array
    func estimatedReward(forAction action: CodeGenWeightedAction, withGamma gamma: Double) -> Double {
        let reward = action.latestReward
        let probability = self.probability(forAction: action, withGamma: gamma)
        let estimatedReward = Double(reward) / Double(probability)
        return estimatedReward
    }

    /// Returns the new evaluated weight for the weighted action of the action in the array for a given gamma 
    func newWeight(forSelectedAction action: CodeGenWeightedAction, andGamma gamma: Double) -> Double {
        return action.weight * exp(gamma*(estimatedReward(forAction: action, withGamma: gamma)/Double(self.count)))
    }

    /// Generates an enumerated array for CodeGenerator
    func generateEnumeratedCodeGenList() -> [(index: Int, codeGenerator: CodeGenerator)] {
        return self.map({(index: $0.index, codeGenerator: $0.codeGenerator)})
    }

    /// Creates the probability distribution from thw eights in weighted actions
    func generateProbabilityDistribution() -> [Double] {
        return self.map({probability(forAction: $0)})
    }

    /// Creates the probability distribution from th weights in weighted actions
    /// with gamma value for MAB
    func generateProbabilityDistribution(withGamma gamma: Double) -> [Double] {
        return self.map({probability(forAction: $0, withGamma: gamma)})
    }

    /// Identifies and returns the max estimated reward in the weighted action array
    func codeGeneratorActionWithMaxEstimatedTotalReward() -> CodeGenWeightedAction {
        let action = self.max{$0.estimatedTotalReward < $1.estimatedTotalReward}
        return action!
    }

    /// Total weight sum of the weighted actions
    var totalWeights: Double {
        return self.map({ $0.weight }).reduce(0, +)
    }

    /// Total occurence sum of the weighted actions
    var totalOccurences: Int {
        let total = self.map({ $0.invocationCount }).reduce(0, +)
        return total > 0 ? total : self.count
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

/// Tracker for capturing CodeGenerator calls and coverage
typealias RecursiveGeneratorCallTracker = (index: Int, calls: Int, newCoverageFound: Double)

public class CodeGenMultiArmedBandit {
    /// Defines the critical mass threshold of code generator invocations to consider for evaluation
    public var critMassThreshold: Int = 500
    /// Restart threshold
    private let restartThreshold: Int = 300_000
    /// Defines the epochs(r) reached where a guess is made for the best action
    public var epochs: Int
    /// Defines number of trials(t) elapsed in MAB
    public var trials: Int
    /// Defines gamma for the execution of Exp3.1 
    public var gamma: Double
    /// Current threshold for epoch change
    public var epochThreshold: Double
    /// The array of weighted actions for the weighted list items
    private var weightedActions: [CodeGenWeightedAction]
    /// Selected CodeGenerator chosen at random from probability distribution
    public var selectedCodeGenerator: CodeGenerator
    /// Selected CodeGenerator index chosen at random from probability distribution
    private var selectedCodeGeneratorIndex: Int
    /// Counters for recursive code gen calls
    private var recursiveGenerateCalls: [RecursiveGeneratorCallTracker]
    /// Dictionary for weighted actions and its context
    private var requiredContextLookup:[Context:[CodeGenWeightedAction]]
    /// Elapsed Invocations
    public var elapsedInvocations:Int

    /// takes a weighted list (e.g. fuzzer.CodeGenerator)
    init(actions weightedItems: WeightedList<CodeGenerator>) {
        assert(weightedItems.count != 0, "Cannot have empty list of actions!")
        self.epochs = 0
        self.trials = 1
        self.gamma = 1.0
        self.epochThreshold = 0.0
        self.selectedCodeGenerator = CodeGenerator("Empty") { _ in 
            fatalError("Unknown code generator")
        }
        self.selectedCodeGeneratorIndex = -1
        self.requiredContextLookup = [:]
        self.elapsedInvocations = 0
        self.weightedActions = weightedItems.elems.enumerated().map({CodeGenWeightedAction(
            codeGenerator: $0.element.element, 
            index: $0.offset, 
            weight: Double($0.element.weight),
            newCoverageFound: 0.0,
            latestReward: 0.0,
            previousReward: 0.0, 
            totalCoverageFound:0.0,
            invocationCount: 1, 
            sumOfSquaredRewards: 0.0,
            sumOfRewards: 0.0,
            estimatedTotalReward: 0.0)})      
        self.recursiveGenerateCalls = weightedItems.elems.enumerated().map({(index: $0.offset, calls: 0, newCoverageFound: 0.0)})
        
        for context in Context.allContexts {
            var availableGenerators: [CodeGenWeightedAction] = [] 
            for action in weightedActions {
                if action.codeGenerator.requiredContext.isSubset(of: context) {
                    availableGenerators.append(action)
                }
            }
            self.requiredContextLookup[context] = availableGenerators
        }
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
        self.selectedCodeGenerator = CodeGenerator("Empty") { _ in fatalError("Unknown code generator") }
        self.selectedCodeGeneratorIndex = -1
        self.elapsedInvocations = self.totalOccurences
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
        self.recursiveGenerateCalls = weightedActions.map({RecursiveGeneratorCallTracker(index: $0.index, calls: 0, newCoverageFound: 0.0)})
    }

    // Reset MAB at epoch change
    public func resetMaxEstimatedTotalReward() {
        // Reset Max total estimated reward
        self.weightedActions[weightedActions.codeGeneratorActionWithMaxEstimatedTotalReward().index].estimatedTotalReward = 0.0
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

    /// The Total recursive codegen calls
    private var totalCalls: Double {
        return Double(self.recursiveGenerateCalls.map({$0.calls}).reduce(0, +)) 
    }

    /// The totalWeight sum of the weighted actions
    private var totalWeights: Double {
        return weightedActions.totalWeights
    }

    /// The totalOccurences sum of the weighted actions
    public var totalOccurences: Int {
        return weightedActions.totalOccurences
    }

    /// Evaluates the new weightedList weights in response to the randomly chosen elements reward
    public func updateWeightedActionsIfEpochNotReached() {
        if !codeGenEpochReached() {
            if totalCalls > 0 {
                for (index, calls, _) in self.recursiveGenerateCalls where calls > 0 {
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
        if !codeGenEpochReached() {
            if totalCalls > 0 {
                for (index, calls, _) in self.recursiveGenerateCalls where calls > 0 {
                    let action = weightedActions[index]
                    let estimatedReward = weightedActions.estimatedReward(forAction: action, withGamma: self.gamma)
                    self.weightedActions[action.index].estimatedTotalReward += estimatedReward
                }
            }
        }
    }

    /// Update trials and Totalestimated rewards if epoch not reached
    public func updateTrialsIfEpochNotReached() {
        if !codeGenEpochReached() {
            self.trials += 1
        }
    }

    /// Evaluates if the epoch(r) is reached for the new gamma value (gamma(r))
    public func codeGenEpochReached() -> Bool {
        let action = weightedActions.codeGeneratorActionWithMaxEstimatedTotalReward()
        let bestAction = bestAction()
        self.gamma = getGamma(bestAction: bestAction)
        self.epochThreshold = bestAction - (Double(self.weightedActions.count)/self.gamma)

        // Check if the estimated reward is less than or equal to the difference between guess for a bestAction (gr) and tune gamma.
        // restarting Exp3 at the beginning of each epoch.
        if action.estimatedTotalReward <= self.epochThreshold {
            return false
        }
        return true
    }

    /// Reset recursive call counters
    public func resetRecursiveGenerateCallsTracker(_ iterations: Int) {
        self.recursiveGenerateCalls = weightedActions.map({RecursiveGeneratorCallTracker(index: $0.index, calls: 0, newCoverageFound: 0.0)})
    }

    /// Increment the epoch(r) 
    public func codeGenEpochCountUpdate() {
        self.epochs += 1
    }

    /// Evaluate if the threshold iterations of the fuzzer is reached
    public func critMassIterationsReached(_ iterations: Int) -> Bool {
       if iterations % self.critMassThreshold == 0 {
            return true
        }
        return false
    }

    /// Displays Stats on the current state of the weighted list
    public func toString() -> String {
        var stats = ""
        weightedActions.forEach { action in
            stats += "\(action.codeGenerator.name) ".padding(toLength: 44, withPad: " ", startingAt: 0)
            stats += "Weight: \(String(format: "%.3f%", action.weight)), totalCoverageFound: \(String(format: "%.8f%", action.totalCoverageFound)), invocationCount: \(action.invocationCount), estimatedTotalReward: \(String(format: "%.4f", action.estimatedTotalReward)), sumOfSquaredRewards: \(String(format: "%.4f%", action.sumOfSquaredRewards)), sumOfRewards: \(String(format: "%.4f%", action.sumOfRewards))\n"
        }
        return stats
    }

    /// Generate a JSON string for the code gen stats
    public func toJSON() -> String {
        var stats = "\"CodeGenerators\":{"
        weightedActions.forEach { action in
            stats += "\"\(action.codeGenerator.name)\":{"
            stats += "\"Weight\": \(String(format: "%.3f%", action.weight)), \"totalCoverageFound\": \(String(format: "%f", action.totalCoverageFound)), \"invocationCount\": \(action.invocationCount), \"estimatedTotalReward\": \(String(format: "%.4f%", action.estimatedTotalReward)), \"sumOfSquaredRewards\": \(String(format: "%.4f%", action.sumOfSquaredRewards)), \"sumOfRewards\": \(String(format: "%.4f%", action.sumOfRewards))},"
        }
        stats += "}"
        return stats
    }

    /// Selects a random element according to MAB Exp3 algorithm
    public func randomElement(mode: BestActionMode, withContext context: Context) -> CodeGenerator {
        self.elapsedInvocations = self.totalOccurences
        (self.selectedCodeGeneratorIndex, self.selectedCodeGenerator) = selectCodeGeneratorWithProbabilityDistribution(mode: mode, withContext: context)
        if selectedCodeGeneratorIndex != -1 {
            self.recursiveGenerateCalls[selectedCodeGeneratorIndex].calls += 1
        }
        return selectedCodeGenerator
    }

    /// Creates the random item selection array on the calculated MAB arm probability distribution 
    private func selectCodeGeneratorWithProbabilityDistribution(mode: BestActionMode, withContext context: Context) ->  (index:Int,CodeGenerator) {
        //Filter the weighted actions with the required context
        let filteredList = self.requiredContextLookup.getWeightedActionsSubset(of: context)
        // The empty code generator is returned if there are no available candidates
        if filteredList.isEmpty {
            return (-1,CodeGenerator("Empty") { _ in fatalError("Unknown code generator") })
        }
        let enumeratedList = filteredList.generateEnumeratedCodeGenList()
        switch mode {
            case  .other:
                let probabilities = filteredList.generateProbabilityDistribution()
                return choose(from: enumeratedList, withProbabilityDistribution: probabilities)
            case .epoch:
                // TODO: This best action selection should take into account the context the actions is being selected for.
                let bestAction = bestAction()
                self.gamma = getGamma(bestAction: bestAction)
                let probabilitiesWithGamma = filteredList.generateProbabilityDistribution(withGamma: self.gamma)
                return choose(from: enumeratedList, withProbabilityDistribution: probabilitiesWithGamma)
        }
    }

    public enum BestActionMode {
        case epoch
        case other
    }

    private func bestAction() -> Double {
        //K*ln(K)
        let numerator = Double(weightedActions.count)*log(Double(weightedActions.count))
        // e-1
        let denominator = exp(1.0) - 1.0
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
        let upperBound = sqrt(numerator/denominator)
        return [1.0,upperBound].min()!
    }

    /// Called when execution of a code generator is successful
    public func evaluateCodeGenSuccess(newCoverageFound: Double) {
        for (index,calls,_) in self.recursiveGenerateCalls where calls > 0 {
            self.recursiveGenerateCalls[index].newCoverageFound += newCoverageFound
        }
    }

    public func evaluateTotal(iterations: Int) {
        if totalCalls > 0 {
            for (index, calls, newCoverageFound) in self.recursiveGenerateCalls where calls > 0 {
                // Update coverage associated with CodeGenerator
                weightedActions[index].totalCoverageFound += newCoverageFound 
                // Update current coverage associated with CodeGenerator
                weightedActions[index].newCoverageFound = newCoverageFound 
                // Update CodeGenerator invocation count
                weightedActions[index].invocationCount += calls

                //average coverage 
                let newAvgCoverage = newCoverageFound/Double(calls)
                let globalAvgCoverage = weightedActions[index].totalCoverageFound == 0.0 ? 1.0 : weightedActions[index].totalCoverageFound / Double(weightedActions[index].invocationCount)

                // calculate the iterations for coverage growth associated with the CodeGenerator
                let iterationsForCoverageGrowth = (newAvgCoverage / globalAvgCoverage) * Double(iterations)
                // update previous reward
                weightedActions[index].previousReward = weightedActions[index].latestReward

                // update sums of rewards 
                weightedActions[index].sumOfSquaredRewards += pow(iterationsForCoverageGrowth, 2)
                weightedActions[index].sumOfRewards += iterationsForCoverageGrowth
                
                // reward for CodeGenerator from the iterations for coverage growth associated with the CodeGenerator
                // for every coverage found value in actual range bind it between (-1,1) for faster convergence
                weightedActions[index].latestReward = logisticNormalise(value: iterationsForCoverageGrowth, index: index)
            }
        } 
    }

    /// Standard deviation for CodeGenerator
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
        return (value:value/standardDeviation,sign:value >= 0 ? 1.0 : -1.0)
    }

    public typealias ProtobufType = [Fuzzilli_Protobuf_WeightedAction]

    /// Generates an array of codegen weight protobufs
    public func exportState() -> ProtobufType {
        var codeGenWeights: ProtobufType = []

        self.weightedActions.forEach { action in
            codeGenWeights.append(Fuzzilli_Protobuf_WeightedAction.with {
                $0.index = Int32(action.index)
                $0.weight = action.weight
            })
        }

        return codeGenWeights
    }

    /// Initialises mutator mab from an array of codegen weights
    public func importState(from proto: ProtobufType) {
        self.epochs = 0
        self.trials = 1
        self.gamma = getGamma(bestAction: bestAction())
        self.selectedCodeGenerator = CodeGenerator("Empty") { _ in fatalError("Unknown code generator") }
        self.selectedCodeGeneratorIndex = -1
        self.elapsedInvocations = self.totalOccurences

        for (idx, codeGen) in proto.enumerated() {
            self.weightedActions[idx].weight = codeGen.weight
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

extension Dictionary where Key == Context, Value == [CodeGenWeightedAction] {
    /// Lookup for context specific CodeGenerators
    func getWeightedActionsSubset(of context: Context) -> [CodeGenWeightedAction] {
        var availableGenerators:[CodeGenWeightedAction] = []
        for key in self.keys {
            if key.isSubset(of: context){
                availableGenerators.append(contentsOf: self[key] ?? [])
            }
        }
        return availableGenerators
    }
}