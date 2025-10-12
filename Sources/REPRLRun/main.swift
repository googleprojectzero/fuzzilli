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

import Foundation
import libreprl

func convertToCArray(_ array: [String]) -> UnsafeMutablePointer<UnsafePointer<Int8>?> {
    let buffer = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity: array.count + 1)
    for (i, str) in array.enumerated() {
        buffer[i] = UnsafePointer(str.withCString(strdup))
    }
    buffer[array.count] = nil
    return buffer
}

if CommandLine.arguments.count < 2 {
    print("Usage: \(CommandLine.arguments[0]) path/to/js_shell [args, ...]")
    exit(0)
}


let ctx = libreprl.reprl_create_context()
if ctx == nil {
    print("Failed to create REPRL context??")
    exit(1)
}

let argv = convertToCArray(Array(CommandLine.arguments[1...]))
let envp = convertToCArray([])
if reprl_initialize_context(ctx, argv, envp, /* capture_stdout: */ 1, /* capture stderr: */ 1) != 0 {
    print("Failed to initialize REPRL context: \(String(cString: reprl_get_last_error(ctx)))")
}

func execute(_ script: String) -> (status: Int32, exec_time: UInt64) {
    var exec_time: UInt64 = 0
    var status: Int32 = 0
    script.withCString { ptr in
        status = reprl_execute(ctx, ptr, UInt64(script.utf8.count), 1_000_000, &exec_time, 0)
    }
    return (status, exec_time)
}

func runREPRLTests() {
    print("Running REPRL tests...")
    var numFailures = 0

    func expect_success(_ code: String) {
        if execute(code).status != 0 {
            print("Execution of \"\(code)\" failed")
            numFailures += 1
        }
    }

    func expect_failure(_ code: String) {
        if execute(code).status == 0 {
            print("Execution of \"\(code)\" unexpectedly succeeded")
            numFailures += 1
        }
    }

    expect_success("42")
    expect_failure("throw 42")

    // Verify that existing state is property reset between executions
    expect_success("globalProp = 42; Object.prototype.foo = \"bar\";")
    expect_success("if (typeof(globalProp) !== 'undefined') throw 'failure'")
    expect_success("if (typeof(({}).foo) !== 'undefined') throw 'failure'")

    // Verify that rejected promises are properly reset between executions
    // Only if async functions are available
    if execute("async function foo() {}").status == 0 {
        expect_failure("async function fail() { throw 42; }; fail()")
        expect_success("42")
        expect_failure("async function fail() { throw 42; }; fail()")
        expect_success("async function fail() { throw 42; }; let p = fail(); p.catch(function(){})")
    }

    if numFailures == 0 {
        print("All tests passed!")
    } else {
        print("Not all tests passed. That means REPRL support likely isn't properly implemented in the target engine")
    }
}

// Check whether REPRL works at all
if execute("").status != 0 {
    print("Script execution failed, REPRL support does not appear to be working")
    exit(1)
}

// Run a couple of tests now
runREPRLTests()

print("Enter code to run, then hit enter to execute it")
while true {
    print("> ", terminator: "")
    guard let code = readLine(strippingNewline: false) else {
        print("Bye")
        break
    }

    let (status, exec_time) = execute(code)

    if status < 0 {
        print("Error during script execution: \(String(cString: reprl_get_last_error(ctx))). REPRL support in the target probably isn't working correctly...")
        continue
    }

    print("Execution finished with status \(status) (signaled: \(RIFSIGNALED(status) != 0), timed out: \(RIFTIMEDOUT(status) != 0)) and took \(exec_time / 1000)ms")
    print("========== Fuzzout ==========\n\(String(cString: reprl_fetch_fuzzout(ctx)))")
    print("========== Stdout ==========\n\(String(cString: reprl_fetch_stdout(ctx)))")
    print("========== Stderr ==========\n\(String(cString: reprl_fetch_stderr(ctx)))")
}
