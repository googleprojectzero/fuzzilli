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

/// Minimizes programs.
///
/// Executes various program reduces to shrink a program in size while retaining its special aspects.
public class Minimizer: ComponentBase {
    private let minimizeToFixpoint: Bool
    
    public init(minimizeToFixpoint: Bool) {
        self.minimizeToFixpoint = minimizeToFixpoint
        super.init(name: "Minimizer")
    }
    
    // Minimize the given program as much as possible while still preserving its special aspects.
    // The given program will not be changed by this function, rather a copy will be made.
    func minimize(_ program: Program, withAspects aspects: ProgramAspects) -> Program {
        let verifier = ReductionVerifier(for: aspects, of: fuzzer)
        var current = program.copy()
        
        repeat {
            verifier.didReduce = false
            
            // Schedule reducers.
            // Currently we minimize corpus samples less aggressively than crashes.
            // It is unclear whether this is beneficial or not, but it seems harder
            // for mutators to "recover" features removed by the more aggressive
            // reducers later on, so we avoid them for corpus samples.
            let reducers: [Reducer]
            if aspects.outcome == .crashed {
                reducers = [CallArgumentReducer(), ReplaceReducer(), GenericInstructionReducer(), BlockReducer(), InliningReducer(fuzzer)]
            } else {
                reducers = [ReplaceReducer(), GenericInstructionReducer(), BlockReducer(), InliningReducer(fuzzer)]
            }
            
            for reducer in reducers {
                current = reducer.reduce(current, with: verifier)
            }
        } while verifier.didReduce && minimizeToFixpoint
        
        // Most reducers replace instructions with NOPs instead of deleting them for performance.
        // Remove those NOPs now.
        current.normalize()

        return current
    }
}
