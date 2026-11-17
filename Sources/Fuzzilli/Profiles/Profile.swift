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

public struct Profile {
    /// How optimized and reference executions are compared in differential mode.
    public enum DifferentialMode: Equatable {
        /// Compare the IR/frame dumps produced by a Dumpling-enabled V8 build.
        /// Requires the target to support `--maglev-dumping`, `--dump-out-filename`, etc.
        case dump
        /// Execute the program in both runners and compare their observable output.
        /// Works with a standard `v8_fuzzilli` build (no Dumpling support needed).
        case output
    }

    public let processArgs: (_ randomize: Bool, _ isWasmEnabled: Bool) -> [String]
    // if not nil, then this is profile for differential fuzzing
    public let processArgsReference: [String]?
    public let processEnv: [String: String]
    public let maxExecsBeforeRespawn: Int
    // Timeout either by value or interval in milliseconds.
    public let timeout: Timeout
    public let codePrefix: String
    public let codeSuffix: String
    public let ecmaVersion: ECMAScriptVersion

    // JavaScript code snippets that are executed at startup time to ensure that Fuzzilli and the target engine are configured correctly.
    public let startupTests: [(String, ExpectedStartupTestResult)]

    public let additionalCodeGenerators: [(CodeGenerator, Int)]
    public let additionalProgramTemplates: WeightedList<ProgramTemplate>

    public let disabledCodeGenerators: [String]
    public let disabledMutators: [String]

    public let additionalBuiltins: [String: ILType]
    public let additionalObjectGroups: [ObjectGroup]
    public let additionalEnumerations: [ILType]
    public let additionalOptionsBags: [OptionsBag]

    // An optional post-processor that is executed for every sample generated for fuzzing and can modify it.
    public let optionalPostProcessor: FuzzingPostProcessor?

    /// How differential executions are compared. Defaults to the existing Dumpling-based mode.
    /// Declared as `var` (with a default) so that it is part of the memberwise initializer.
    public var differentialMode: DifferentialMode = .dump

    public var isDifferential: Bool {
        return processArgsReference != nil
    }
}

public let profiles = [
    "qtjs": qtjsProfile,
    "qjs": qjsProfile,
    "jsc": jscProfile,
    "spidermonkey": spidermonkeyProfile,
    "v8": v8Profile,
    "v8Maglev": v8MaglevDifferentialProfile,
    "v8Sandbox": v8SandboxProfile,
    "v8Dumpling": v8DumplingProfile,
    "duktape": duktapeProfile,
    "jerryscript": jerryscriptProfile,
    "xs": xsProfile,
    "v8holefuzzing": v8HoleFuzzingProfile,
    "serenity": serenityProfile,
    "njs": njsProfile,
]
