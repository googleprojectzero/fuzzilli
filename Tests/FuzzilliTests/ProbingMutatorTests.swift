// Copyright 2026 Google LLC
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

import XCTest

@testable import Fuzzilli

class ProbingMutatorTests: XCTestCase {
    func testProbingMutatorBasic() {
        let runner = MockScriptRunner()
        let config = Configuration(logLevel: .error)
        let fuzzer = makeMockFuzzer(config: config, runner: runner)

        let mutator = ProbingMutator()

        let b = fuzzer.makeBuilder()
        let v0 = b.createObject(with: [:])
        let f = b.createNamedVariable(forBuiltin: "SomeBuiltin")
        b.callFunction(f, withArgs: [v0])
        let program = b.finalize()

        // Original program:
        // const v0 = {};
        // const v1 = SomeBuiltin;
        // v1(v0);

        // We might insert the probe in different places in the program:
        // const v0 = Probe({});
        // const v1 = SomeBuiltin;
        // v1(v0);
        // or:
        // const v0 = {};
        // const v1 = Probe(SomeBuiltin);
        // v1(v0);

        // Inject probing results: we tried to load "bar" which did not exist. (We insert the results for both v0 and v1, since the probe can be inserted in two different places.)
        let resultsJSON =
            "{\"v0\": {\"loads\": {\"bar\": 0}, \"stores\": {}}, \"v1\": {\"loads\": { \"bar\": 0}, \"stores\": {}}}"
        runner.fuzzoutToReturn = "PROBING_RESULTS: \(resultsJSON)\n"

        let mutatedProgram = mutator.mutate(program, using: b, for: fuzzer)
        XCTAssertNotNil(mutatedProgram)
        let lifted = fuzzer.lifter.lift(mutatedProgram!)

        // We inserted a line which assigns something to the property "bar".
        // There are several options how this could be done, e.g.,
        // const v0 = {};
        // function f1() { ... }
        // Object.defineProperty(v0, "bar", { ..., get: f1 });
        // or:
        // const v0 = {};
        // v0.bar = ...;
        XCTAssert(lifted.contains("bar"))
    }

    func testProbingMutatorForBundle() {
        let runner = MockScriptRunner()
        let config = Configuration(logLevel: .error, generateBundle: true)
        let fuzzer = makeMockFuzzer(config: config, runner: runner)

        let mutator = ProbingMutator()

        let b = fuzzer.makeBuilder()

        let module = b.buildBundleModule(name: "a.mjs") {
            let v0 = b.loadInt(83)
            b.exportVariables(variables: [v0], exportNames: ["exp0"])
        }

        b.buildBundleModuleEntryPoint {
            let _ = b.importVariables(module: module, importNames: ["exp0"])
        }

        let program = b.finalize()

        // Mutation failed since the program doesn't contain any JavaScript variables.
        XCTAssertNil(mutator.mutate(program, using: b, for: fuzzer))
    }
}
