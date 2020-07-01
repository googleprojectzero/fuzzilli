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
    private let maxExecsBeforeRespawn = 1000
    
    /// Commandline arguments for the executable
    private let processArguments: [String]
    
    /// Environment variables for the child process
    private var env = [String]()
    
    /// Number of script executions since start of child process
    private var execsSinceReset = 0
    
    /// Number of execution failures since the last successfully executed program
    private var recentlyFailedExecutions = 0
    
    private var reprlContext: OpaquePointer? = nil
    
    public init(executable: String, processArguments: [String], processEnvironment: [String: String]) {
        self.processArguments = [executable] + processArguments
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
        
        if reprl_initialize_context(reprlContext, argv, envp, /* capture_stdout: */ 0, /* capture stderr: */ 1) != 0 {
            logger.fatal("Failed to initialize REPRL context: \(String(cString: reprl_get_last_error(reprlContext)))")
        }
        
        freeCArray(argv, numElems: processArguments.count)
        freeCArray(envp, numElems: env.count)

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) {
            reprl_destroy_context(self.reprlContext)
        }
    }
    
    public func setEnvironmentVariable(_ key: String, to value: String) {
        env.append(key + "=" + value)
    }
    
    public func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        let execution = REPRLExecution(in: reprlContext)
        
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
        }
                
        var execTime: Int64 = 0
        var status: Int32 = 0
        script.withCString {
            status = reprl_execute(reprlContext, $0, Int64(script.count), Int64(timeout), &execTime, freshInstance)
            // If we fail, we retry after a short timeout and with a fresh instance. If we still fail, we give up trying
            // to execute this program. If we repeatedly fail to execute any program, we abort.
            if status < 0 {
                logger.warning("Script execution failed: \(String(cString: reprl_get_last_error(reprlContext))). Retrying in 1 second...")
                sleep(1)
                status = reprl_execute(reprlContext, $0, Int64(script.count), Int64(timeout), &execTime, 1)
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
        execution.execTime = UInt(clamping: execTime)
                
        return execution
    }
}

class REPRLExecution: Execution {
    private var cachedStdout: String? = nil
    private var cachedStderr: String? = nil
    private var cachedFuzzout: String? = nil
    private let reprlContext: OpaquePointer?
    
    var outcome = ExecutionOutcome.succeeded
    var execTime: UInt = 0
    
    init(in ctx: OpaquePointer?) {
        reprlContext = ctx
    }
    
    var stdout: String {
        if cachedStdout == nil {
            cachedStdout = String(cString: reprl_fetch_stdout(reprlContext))
        }
        return cachedStdout!
    }
    
    var stderr: String {
        if cachedStderr == nil {
            cachedStderr = String(cString: reprl_fetch_stderr(reprlContext))
        }
        return cachedStderr!
    }
    
    var fuzzout: String {
        if cachedFuzzout == nil {
            cachedFuzzout = String(cString: reprl_fetch_fuzzout(reprlContext))
        }
        return cachedFuzzout!
    }
}
