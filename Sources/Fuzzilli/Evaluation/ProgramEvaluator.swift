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

public protocol ProgramEvaluator: Component {
    /// Evaluates a program.
    ///
    /// - Parameter execution: An execution of the program to evaluate.
    /// - Returns: The programs special aspects if it has any, nil otherwise.
    func evaluate(_ execution: Execution) -> ProgramAspects?
    
    /// Evaluates a crash.
    ///
    /// - Parameter execution: An execution of the program to evaluate.
    /// - Returns: the programs special aspects if it has any, nil otherwise.
    func evaluateCrash(_ execution: Execution) -> ProgramAspects?
    
    /// Checks whether a program has the given aspects.
    func hasAspects(_ execution: Execution, _ aspects: ProgramAspects) -> Bool
    
    /// The current, accumulated score of all seen samples. E.g. total coverage.
    var currentScore: Double { get }
    
    /// Export the current state of this evaluator so it can be replicated.
    func exportState() -> Data
    
    /// Import a previously exported state.
    func importState(_ state: Data) throws

    // Resets the provided aspects and executes the program a second time.
    // If aspects are successfully collected from the second execution, returns
    // the intersection of the initally provided aspects with the aspects from the 
    // second execution. If it fails at any point, returns nil
    func evaluateAndIntersect(_ program: Program, with aspects: ProgramAspects) -> ProgramAspects?

    /// Resets the internal state
    func resetState()
}
