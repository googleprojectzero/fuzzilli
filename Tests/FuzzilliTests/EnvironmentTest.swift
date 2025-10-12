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

    /// Test that all interesting properties on the globalThis object are registered as builtins.
    func testJSEnvironmentRegisteredBuiltins() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .user, withArguments: [])
        let liveTestConfig = Configuration(logLevel: .error, enableInspection: true)
        let fuzzer = makeMockFuzzer(config: liveTestConfig, environment: JavaScriptEnvironment())
        let b = fuzzer.makeBuilder()

        let globalThis = b.createNamedVariable(forBuiltin: "globalThis")
        let object = b.createNamedVariable(forBuiltin: "Object")
        let names = b.callMethod("getOwnPropertyNames", on: object, withArgs: [globalThis])
        let namesString = b.callMethod("join", on: names, withArgs: [b.loadString(",")])
        b.callFunction(b.createNamedVariable(forBuiltin: "output"), withArgs: [namesString])

        let prog = b.finalize()
        let jsProg = fuzzer.lifter.lift(prog, withOptions: [])
        let jsEnvironment = b.fuzzer.environment
        let result = testExecuteScript(program: jsProg, runner: runner)
        XCTAssert(result.isSuccess, "\(result.error)\n\(result.output)")
        var output = result.output
        XCTAssertEqual(output.removeLast(), "\n")

        // Global builtins available in d8 that should not be fuzzed.
        let skipped = [
            "fuzzilli", "testRunner", "quit", "load", "read", "readline", "readbuffer",
            "writeFile", "write", "print", "printErr", "version", "os", "d8", "arguments", "Realm"
        ]
        // Global builtins that we probably should register but haven't done so, yet.
        let TODO = [
            "globalThis",
            "Iterator",
            "setTimeout",
            "console",
            "escape",
            "unescape",
            "encodeURIComponent",
            "encodeURI",
            "decodeURIComponent",
            "decodeURI",
            // https://github.com/tc39/proposal-ecmascript-sharedmem/tree/main
            "Atomics",
            // https://github.com/tc39/proposal-explicit-resource-management
            "DisposableStack",
            "AsyncDisposableStack",
            // https://github.com/tc39/proposal-float16array
            "Float16Array",
            // Web APIs
            "performance",
            "Worker",
        ]
        let ignore = Set(skipped + TODO)

        for builtin in output.split(separator: ",") where !ignore.contains(String(builtin)) {
            XCTAssert(jsEnvironment.builtins.contains(String(builtin)),
                "Unregistered builtin \(builtin)")
        }
    }

    func convertTypedArrayToHex(_ b: ProgramBuilder, _ array: Variable) -> Variable {
        let toHex = b.buildArrowFunction(with: .parameters(n: 1)) { args in
            let hex = b.callMethod("toString", on: args[0], withArgs: [b.loadInt(16)])
            let hexPadded = b.callMethod("padStart", on: hex, withArgs: [b.loadInt(2), b.loadString("0")])
            b.doReturn(hexPadded)
        }
        let untypedArray = b.construct(b.createNamedVariable(forBuiltin: "Array"),
            withArgs: [array], spreading: [true])
        let hexArray = b.callMethod("map", on: untypedArray, withArgs: [toHex])
        return b.callMethod("join", on: hexArray, withArgs: [b.loadString("")])
    }

    func testBase64OptionsBag() throws {
        let runner = try GetJavaScriptExecutorOrSkipTest(type: .any, withArguments: ["--js-base-64"])
        let jsProg = buildAndLiftProgram { b in
            let arrayConstructor = b.createNamedVariable(forBuiltin: "Uint8Array")
            // Whatever the options object looks like, it should construct something valid.
            // With the provided input string, the actual options should not matter.
            let options = b.createOptionsBag(OptionsBag.fromBase64Settings)
            let inputString = b.loadString("qxI0VniQq83v")
            let array = b.callMethod("fromBase64", on: arrayConstructor, withArgs: [inputString, options])
            XCTAssert(b.type(of: array).Is(.object(ofGroup: "Uint8Array")))
            let outputFunc = b.createNamedVariable(forBuiltin: "output")
            b.callFunction(outputFunc, withArgs: [convertTypedArrayToHex(b, array)])

            let options2 = b.createOptionsBag(OptionsBag.fromBase64Settings)
            let inputString2 = b.loadString("uq3erb7v")
            b.callMethod("setFromBase64", on: array, withArgs: [inputString2, options2])
            b.callFunction(outputFunc, withArgs: [convertTypedArrayToHex(b, array)])
        }
        testForOutput(program: jsProg, runner: runner,
            outputString: "ab1234567890abcdef\nbaaddeadbeefabcdef\n")
    }
}
