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

print("Enter code to run, then hit enter to execute it")
while true {
    print("> ", terminator: "")
    guard let code = readLine(strippingNewline: false) else {
        print("Bye")
        break
    }
    
    var exec_time: UInt64 = 0
    var status: Int32 = 0
    code.withCString {
        status = reprl_execute(ctx, $0, UInt64(code.count), 1000, &exec_time, 0)
    }
    
    if status < 0 {
        print("Error during script execution: \(String(cString: reprl_get_last_error(ctx))). REPRL support in the target probably isn't working correctly...")
        continue
    }
    
    print("Execution finished with status \(status) (signaled: \(RIFSIGNALED(status) != 0), timed out: \(RIFTIMEDOUT(status) != 0)) and took \(exec_time)ms")
    print("========== Fuzzout ==========\n\(String(cString: reprl_fetch_fuzzout(ctx)))")
    print("========== Stdout ==========\n\(String(cString: reprl_fetch_stdout(ctx)))")
    print("========== Stderr ==========\n\(String(cString: reprl_fetch_stderr(ctx)))")
}
