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
/// scripts but resets the global state in between
public class REPRL: ComponentBase, ScriptRunner {
    /// Kill and restart the child process after this many script executions
    private let maxExecsBeforeRespawn = 100
    
    /// Commandline arguments for the executable
    private let processArguments: [String]
    
    /// The PID of the child process
    private var pid: Int32 = 0
    
    /// Read file descriptor of the control pipe
    private var crfd: CInt = 0
    /// Write file descriptor of the control pipe
    private var cwfd: CInt = 0
    /// Read file descriptor of the data pipe
    private var drfd: CInt = 0
    /// Write file descriptor of the data pipe
    private var dwfd: CInt = 0
    
    /// Environment variables for the child process
    private var env = [String]()
    
    /// Number of script executions since start of child process
    private var execsSinceReset = 0
    
    public init(executable: String, processArguments: [String], processEnvironment: [String: String]) {
        self.processArguments = [executable] + processArguments
        super.init(name: "REPRL")
        
        for (key, value) in processEnvironment {
            env.append(key + "=" + value)
        }
    }
    
    override func initialize() {
        // We need to ignore SIGPIPE since we are writing to a pipe
        // without checking if our child is still alive before.
        signal(SIGPIPE, SIG_IGN)
        
        respawn(shouldKill: false)
        
        // Kill child processes on shutdown
        addEventListener(for: fuzzer.events.Shutdown) {
            self.killChild()
        }
    }
    
    public func setEnvironmentVariable(_ key: String, to value: String) {
        env.append(key + "=" + value)
    }
    
    private func killChild() {
        if pid != 0 {
            kill(pid, SIGKILL)
            var exitCode: Int32 = 0
            waitpid(pid, &exitCode, 0)
        }
    }
    
    private func respawn(shouldKill: Bool) {
        if pid != 0 {
            if shouldKill {
                killChild()
            }
            close(crfd)
            close(cwfd)
            close(drfd)
            close(dwfd)
        }
        
        let argv = convertToCArray(processArguments)
        let envp = convertToCArray(env)
        
        var success = false
        var child = reprl_child_process()
        for _ in 0..<100 {
            if reprl_spawn_child(argv, envp, &child) == 0 {
                success = true
                break
            }
            sleep(1)
        }
        if !success {
            logger.fatal("Failed to spawn REPRL child process")
        }
        
        pid = child.pid
        crfd = child.crfd
        cwfd = child.cwfd
        drfd = child.drfd
        dwfd = child.dwfd
        
        freeCArray(argv, numElems: processArguments.count)
        freeCArray(envp, numElems: env.count)
        
        execsSinceReset = 0
    }
    
    public func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        execsSinceReset += 1
        
        if execsSinceReset > maxExecsBeforeRespawn {
            respawn(shouldKill: true)
        }
        
        var result = reprl_result()
        
        let code = script.data(using: .utf8)!
        let res = code.withUnsafeBytes { (bytes: UnsafePointer<Int8>) -> CInt in
            return reprl_execute_script(pid, crfd, cwfd, drfd, dwfd, CInt(timeout), bytes, Int64(code.count), &result)
        }
        
        if res != 0 {
            // Execution failed somehow. Need to respawn and retry
            sleep(1)
            respawn(shouldKill: true)
            return run(script, withTimeout: timeout)
        }
        
        if result.child_died != 0 {
            respawn(shouldKill: false)
        }
        
        let output = String(data: Data(bytes: result.output, count: result.output_size), encoding: .utf8)!
        free(result.output)
        
        return Execution(script: script,
                         pid: Int(pid),
                         outcome: ExecutionOutcome.fromExitStatus(result.status),
                         termsig: Int(WTERMSIG(result.status)),
                         output: output,
                         execTime: UInt(result.exec_time))
    }
}
