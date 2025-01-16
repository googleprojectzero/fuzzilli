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

import Foundation
import libreprl

/// Read-Eval-Print-Reset-Loop: a script runner that reuses the same process for multiple
/// scripts, but resets the global state in between executions.
public class REPRL: ComponentBase, ScriptRunner {
    /// Kill and restart the child process after this many script executions
    private let maxExecsBeforeRespawn: Int

    /// Commandline arguments for the executable
    public private(set) var processArguments: [String]

    /// Environment variables for the child process
    private var env = [String]()

    /// Number of script executions since start of child process
    private var execsSinceReset = 0

    /// Number of execution failures since the last successfully executed program
    private var recentlyFailedExecutions = 0

    /// The opaque REPRL context used by the C library
    fileprivate var reprlContext: OpaquePointer? = nil

    /// Essentially counts the number of run() invocations
    fileprivate var lastExecId = 0

    /// Buffer to hold scripts, this lets us debug issues that arise if
    /// previous scripts corrupted any state which is discovered in
    /// future executions. This is only used if diagnostics mode is enabled.
    private var scriptBuffer = String()

    public init(executable: String, processArguments: [String], processEnvironment: [String: String], maxExecsBeforeRespawn: Int) {
        self.processArguments = [executable] + processArguments
        self.maxExecsBeforeRespawn = maxExecsBeforeRespawn
        super.init(name: "REPRL")

        for (key, value) in processEnvironment {
            env.append(key + "=" + value)
        }
    }

    override func initialize() {
        reprlContext = libreprl.reprl_create_context()
        if reprlContext == nil {
            logger.fatal("Failed to create REPRL context")
        }

        let argv = convertToCArray(processArguments)
        let envp = convertToCArray(env)

        if reprl_initialize_context(reprlContext, argv, envp, /* capture stdout */ 1, /* capture stderr: */ 1) != 0 {
            logger.fatal("Failed to initialize REPRL context: \(String(cString: reprl_get_last_error(reprlContext)))")
        }

        freeCArray(argv, numElems: processArguments.count)
        freeCArray(envp, numElems: env.count)

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            reprl_destroy_context(self.reprlContext)
        }
    }

    public func setEnvironmentVariable(_ key: String, to value: String) {
        env.append(key + "=" + value)
    }

    public func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        // Log the current script into the buffer if diagnostics are enabled.
        if fuzzer.config.enableDiagnostics {
            self.scriptBuffer += script + "\n"
        }

        lastExecId += 1

        let execution = REPRLExecution(from: self)

        guard script.count <= REPRL_MAX_DATA_SIZE else {
            logger.error("Script too large to execute. Assuming timeout...")
            execution.outcome = .timedOut
            return execution
        }

        execsSinceReset += 1
        var freshInstance: Int32 = 0
        if execsSinceReset > maxExecsBeforeRespawn {
            freshInstance = 1
            execsSinceReset = 0
            if fuzzer.config.enableDiagnostics {
                scriptBuffer.removeAll(keepingCapacity: true)
            }
        }

        var execTime: UInt64 = 0        // In microseconds
        let timeout = UInt64(timeout) * 1000        // In microseconds
        var status: Int32 = 0
        script.withCString { ptr in
            status = reprl_execute(reprlContext, ptr, UInt64(script.utf8.count), UInt64(timeout), &execTime, freshInstance)
            // If we fail, we retry after a short timeout and with a fresh instance. If we still fail, we give up trying
            // to execute this program. If we repeatedly fail to execute any program, we abort.
            if status < 0 {
                logger.warning("Script execution failed: \(String(cString: reprl_get_last_error(reprlContext))). Retrying in 1 second...")
                if fuzzer.config.enableDiagnostics {
                    fuzzer.dispatchEvent(fuzzer.events.DiagnosticsEvent, data: (name: "REPRLFail", content: scriptBuffer.data(using: .utf8)!))
                }
                Thread.sleep(forTimeInterval: 1)
                status = reprl_execute(reprlContext, ptr, UInt64(script.utf8.count), UInt64(timeout), &execTime, 1)
            }
        }

        if status < 0 {
            logger.error("Script execution failed again: \(String(cString: reprl_get_last_error(reprlContext))). Giving up")
            // If we weren't able to successfully execute a script in the last N attempts, abort now...
            recentlyFailedExecutions += 1
            if recentlyFailedExecutions >= 10 {
                logger.fatal("Too many consecutive REPRL failures")
            }
            execution.outcome = .failed(1)
            return execution
        }
        recentlyFailedExecutions = 0

        if RIFEXITED(status) != 0 {
            let code = REXITSTATUS(status)
            if code == 0 {
                execution.outcome = .succeeded
            } else {
                execution.outcome = .failed(Int(code))
            }
        } else if RIFSIGNALED(status) != 0 {
            execution.outcome = .crashed(Int(RTERMSIG(status)))
        } else if RIFTIMEDOUT(status) != 0 {
            execution.outcome = .timedOut
        } else {
            fatalError("Unknown REPRL exit status \(status)")
        }
        execution.execTime = Double(execTime) / 1_000_000

        return execution
    }
}

class REPRLExecution: Execution {
    private var cachedStdout: String? = nil
    private var cachedStderr: String? = nil
    private var cachedFuzzout: String? = nil

    private unowned let reprl: REPRL
    private let execId: Int

    var outcome = ExecutionOutcome.succeeded
    var execTime: TimeInterval = 0

    init(from reprl: REPRL) {
        self.reprl = reprl
        self.execId = reprl.lastExecId
    }

    // The output streams (stdout, stderr, fuzzout) can only be accessed before
    // the next REPRL execution. This function can be used to verify that.
    private var outputStreamsAreValid: Bool {
        return execId == reprl.lastExecId
    }

    var stdout: String {
        assert(outputStreamsAreValid)
        if cachedStdout == nil {
            cachedStdout = String(cString: reprl_fetch_stdout(reprl.reprlContext))
        }
        return cachedStdout!
    }

    var stderr: String {
        assert(outputStreamsAreValid)
        if cachedStderr == nil {
            cachedStderr = String(cString: reprl_fetch_stderr(reprl.reprlContext))
        }
        return cachedStderr!
    }

    var fuzzout: String {
        assert(outputStreamsAreValid)
        if cachedFuzzout == nil {
            cachedFuzzout = String(cString: reprl_fetch_fuzzout(reprl.reprlContext))
        }
        return cachedFuzzout!
    }
}
