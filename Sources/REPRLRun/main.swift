import Foundation
import libreprl

func convertToCArray(_ array: [String]) -> UnsafeMutablePointer<UnsafePointer<Int8>?> {
    print("Converting array to C array: \(array)")
    let buffer = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity: array.count + 1)
    for (i, str) in array.enumerated() {
        buffer[i] = UnsafePointer(str.withCString(strdup))
    }
    buffer[array.count] = nil
    return buffer
}

func printREPRLOutput(_ ctx: OpaquePointer?) {
    let fuzzout = String(cString: reprl_fetch_fuzzout(ctx))
    let stdout = String(cString: reprl_fetch_stdout(ctx))
    let stderr = String(cString: reprl_fetch_stderr(ctx))

    print("========== Fuzzout ==========")
    print(fuzzout)
    print("========== Stdout ==========")
    print(stdout)
    print("========== Stderr ==========")
    print(stderr)
}

if CommandLine.arguments.count < 2 {
    print("Usage: \(CommandLine.arguments[0]) path/to/js_shell [args, ...]")
    exit(0)
}

print("Creating REPRL context...")
let ctx = libreprl.reprl_create_context()
if ctx == nil {
    print("Failed to create REPRL context??")
    exit(1)
}

let argv = convertToCArray(Array(CommandLine.arguments[1...]))
let envp = convertToCArray([])

print("Initializing REPRL context with argv: \(CommandLine.arguments[1...])")
if reprl_initialize_context(ctx, argv, envp, /* capture_stdout: */ 1, /* capture stderr: */ 1) != 0 {
    print("Failed to initialize REPRL context: \(String(cString: reprl_get_last_error(ctx)))")
    printREPRLOutput(ctx)
    exit(1)
} else {
    print("REPRL context initialized successfully.")
}

func execute(_ script: String) -> (status: Int32, exec_time: UInt64) {
    var exec_time: UInt64 = 0
    var status: Int32 = 0
    print("Executing script: \(script)")
    script.withCString { ptr in
        status = reprl_execute(ctx, ptr, UInt64(script.utf8.count), 1_000_000, &exec_time, 0)
    }
    print("Execution result: status = \(status), exec_time = \(exec_time)")
    printREPRLOutput(ctx)
    return (status, exec_time)
}

func runREPRLTests() {
    print("Running REPRL tests...")
    var numFailures = 0

    func expect_success(_ code: String) {
        print("Expecting success for code: \(code)")
        if execute(code).status != 0 {
            print("Execution of \"\(code)\" failed")
            numFailures += 1
        } else {
            print("Success for code: \(code)")
        }
    }

    func expect_failure(_ code: String) {
        print("Expecting failure for code: \(code)")
        if execute(code).status == 0 {
            print("Execution of \"\(code)\" unexpectedly succeeded")
            numFailures += 1
        } else {
            print("Failure as expected for code: \(code)")
        }
    }

    expect_success("42")
    expect_failure("throw 42")

    expect_success("globalProp = 42; Object.prototype.foo = \"bar\";")
    expect_success("if (typeof(globalProp) !== 'undefined') throw 'failure'")
    expect_success("if (typeof(({}).foo) !== 'undefined') throw 'failure'")

    if execute("async function foo() {}").status == 0 {
        expect_failure("async function fail() { throw 42; }; fail()")
        expect_success("42")
        expect_failure("async function fail() { throw 42; }; fail()")
        expect_success("async function fail() { throw 42; }; let p = fail(); p.catch(function(){})")
    }

    if numFailures == 0 {
        print("All tests passed!")
    } else {
        print("Not all tests passed. REPRL support may not be properly implemented.")
    }
}

print("Checking if REPRL works...")
if execute("").status != 0 {
    print("Initial script execution failed, REPRL support does not appear to be working")
    printREPRLOutput(ctx)
    exit(1)
} else {
    print("Initial REPRL check passed.")
}

runREPRLTests()

print("Enter code to run, then hit enter to execute it")
while true {
    print("> ", terminator: "")
    guard let code = readLine(strippingNewline: false) else {
        print("Bye")
        break
    }

    print("Executing user input code...")
    let (status, exec_time) = execute(code)

    if status < 0 {
        print("Error during script execution: \(String(cString: reprl_get_last_error(ctx))). REPRL support in the target probably isn't working correctly...")
        printREPRLOutput(ctx)
        continue
    }

    print("Execution finished with status \(status) (signaled: \(RIFSIGNALED(status) != 0), timed out: \(RIFTIMEDOUT(status) != 0)) and took \(exec_time / 1000)ms")
}

