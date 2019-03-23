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
import libforkserver

public class Forkserver: ComponentBase, ScriptRunner {
    /// Commandline arguments for the executable
    private let processArguments: [String]
    
    /// Output file to write to
    private let outputFile: FileHandle
    
    /// Read file descriptor to the forkserver process
    private var rfd: CInt = -1
    /// Write file descriptor to the forkserver process
    private var wfd: CInt = -1
    /// Output file descriptor of the forkserver process
    private var outfd: CInt = -1
    
    /// Environment variables for the child process
    private var env = [String: String]()
    
    public init(for fuzzer: Fuzzer, executable: String, processArguments: [String], processEnvironment: [String: String]) {
        // Allocate input file for the child process
        let outputFileName = URL(fileURLWithPath: "fuzzilli_script_\(fuzzer.id).js")
        if !FileManager.default.createFile(atPath: outputFileName.path, contents: nil) {
            fatalError("Could not create output file \(outputFileName.path)")
        }
        self.outputFile = try! FileHandle(forWritingTo: outputFileName)
        self.processArguments = [executable] + processArguments + [outputFileName.path]
        
        self.env = processEnvironment
        
        super.init(name: "Forkserver")
    }
    
    public func setEnvironmentVariable(_ key: String, to value: String) {
        env[key] = value
    }
    
    override func initialize() {
        for (key, value) in env {
            setenv(key, value, 1)
        }
        
        let argv = convertToCArray(processArguments)
        let server = spinup_forkserver(argv)
        rfd = server.rfd
        wfd = server.wfd
        outfd = server.outfd
        
        freeCArray(argv, numElems: processArguments.count)
    }

    public func run(_ script: String, withTimeout timeout: UInt32) -> Execution {
        outputFile.truncateFile(atOffset: 0)
        outputFile.seek(toFileOffset: 0)
        outputFile.write(script.data(using: .utf8)!)
        
        let result = forkserver_spawn(rfd, wfd, outfd, CInt(timeout))
        
        let output = String(data: Data(bytes: result.output, count: result.output_size), encoding: .utf8)!
        free(result.output)
        
        return Execution(script: script,
                         pid: Int(result.pid),
                         outcome: ExecutionOutcome.fromExitStatus(result.status),
                         termsig: Int(WTERMSIG(result.status)),
                         output: output,
                         execTime: UInt(result.exec_time))
    }
}
