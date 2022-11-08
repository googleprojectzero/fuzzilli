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


// The settings here strive to achieve a correctness rate of around 75%. Empirically, this appears to be roughly optimal:
// higher than that, and samples are too similar to each other, lower than that, and too many samples are invalid.
// TODO evaluate this independently for every mutator.

let defaultMaxSimultaneousMutations = 7
let defaultMaxSimultaneousCodeGenerations = 3
let defaultCodeGenerationAmount = 5      // This must be at least ProgramBuilder.minBudgetForRecursiveCodeGeneration
