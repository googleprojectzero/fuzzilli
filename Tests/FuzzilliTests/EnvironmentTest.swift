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

import XCTest
@testable import Fuzzilli

class EnvironmentTests: XCTestCase {

    func testJSEnvironmentConsistency() {
        // The constructor will already perform various consistency checks, so we don't repeat them here.
        let _ = JavaScriptEnvironment(additionalBuiltins: [:], additionalObjectGroups: [])
    }

    /// Test all the builtin objects that are reachable from the global this.
    /// (This does not include anything that needs a constructor to be called.)
    func testJSEnvironmentLive() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--harmony", "--experimental-wasm-rab-integration", "--wasm-test-streaming"])
        let jsProg = buildAndLiftProgram(withLiftingOptions: [.includeComments]) { b in
            let jsEnvironment = b.fuzzer.environment
            var seenTypeGroups = Set<String>()
            var propertiesToCheck: [(Variable, String, String)] = []
            let enqueueProperties = {(builtin: Variable, path: String, type: ILType) in
                if type.group == nil || seenTypeGroups.insert(type.group!).inserted {
                    propertiesToCheck.append(contentsOf:
                        type.properties.sorted().map {(builtin, $0, "\(path).\($0)")} +
                        type.methods.sorted().map {(builtin, $0, "\(path).\($0)")})
                }
            }
            let handleBuiltin = {builtin, path in
                // Do something with the builtin to check that it exists (even if it might not have any
                // registered properties or methods).
                // The .LogicOr is only done for error reporting, e.g.:
                //   TypeError: Cannot read properties of undefined (reading 'exists')
                //   v168.message2.exists || "(new URIError()).message2";
                b.binary(b.getProperty("exists", of: builtin), b.loadString(path), with: .LogicOr)
                // Enqueue its properties and methods.
                let type = b.type(of: builtin)
                enqueueProperties(builtin, path, type)
                if type.Is(.constructor()), let signature = type.constructorSignature {
                    // If the object is default-constructible, instantiate it.
                    // Otherwise we can't know how to construct a valid instance.
                    if (signature.parameters.allSatisfy {$0.isOptionalParameter}) {
                        let instance = b.construct(builtin)
                        enqueueProperties(instance, "(new \(path)())", b.type(of: instance))
                    }
                }
            }
            for builtinName in jsEnvironment.builtins.sorted() where builtinName != "undefined" {
                handleBuiltin(b.createNamedVariable(forBuiltin: builtinName), builtinName)
            }
            let blockList : Set = ["arguments", "caller"]
            while let (builtinVar, name, path) = propertiesToCheck.popLast() {
                if blockList.contains(name) { continue }
                let builtin = b.getProperty(name, of: builtinVar)
                // If a property can be undefined or null, skip validating that it exists.
                if !b.type(of: builtin).MayBe(.nullish) {
                    handleBuiltin(builtin, path)
                }
            }
        }
        // No output expected, all builtins should exist.
        testForOutput(program: jsProg, runner: runner, outputString: "")
    }
}
