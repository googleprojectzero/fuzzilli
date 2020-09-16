// Copyright 2020 Google LLC
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

public struct ProgramGeneratorStats {
    private var validSamples = 0
    private var invalidSamples = 0

    mutating func producedValidSample() {
        validSamples += 1
    }

    mutating func producedInvalidSample() {
        invalidSamples += 1
    }

    var correctnessRate: Double {
        let totalSamples = validSamples + invalidSamples
        guard totalSamples > 0 else { return 1.0 }
        return Double(validSamples) / Double(totalSamples)
    }

    // TODO: Maybe also add a counter to track how often it generated new coverage?
}
