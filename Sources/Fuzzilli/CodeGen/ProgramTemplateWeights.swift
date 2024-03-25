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

/// Default weights for the builtin program templates.
public let programTemplateWeights = [
    "Codegen100":            2,
    "Codegen50":             2,
    "WasmCodegen50":         2,
    "WasmCodegen100":        2,
    "MixedJsAndWasm1":       2,
    "MixedJsAndWasm2":       2,
    "JSPI":                  2,
    "JIT1Function":          3,
    "JIT2Functions":         3,
    "JITTrickyFunction":     2,
    "JSONFuzzer":            1,
]
