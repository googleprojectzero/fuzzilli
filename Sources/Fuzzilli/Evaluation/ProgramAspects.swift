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

/// Aspects of a program that make it special.
public class ProgramAspects: CustomStringConvertible {
    let outcome: ExecutionOutcome
    let hasFeedbackNexusDelta: Bool
    let hasOptimizationDelta: Bool

    public init(outcome: ExecutionOutcome, hasFeedbackNexusDelta: Bool = false, hasOptimizationDelta: Bool = false) {
        self.outcome = outcome
        self.hasFeedbackNexusDelta = hasFeedbackNexusDelta
        self.hasOptimizationDelta = hasOptimizationDelta
    }

    public var description: String {
        var desc = "execution outcome \(outcome)"
        if hasFeedbackNexusDelta {
            desc += " with feedback nexus delta"
        }
        if hasOptimizationDelta {
            desc += " with optimization delta"
        }
        return desc
    }

    // The total number of aspects
    public var count: UInt32 {
        return hasFeedbackNexusDelta ? 1 : 0
    }
}
