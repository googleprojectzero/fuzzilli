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
import Fuzzilli

let jsFileExtension = ".js"
let protoBufFileExtension = ".il.protobuf"

let corpus = Corpus(minSize: 1000, maxSize: 1000000, minMutationsPerSample: 600)
let jsPrefix = """
               """
let jsSuffix = """
               """
let lifter = JavaScriptLifter(prefix: jsPrefix,
                suffix: jsSuffix,
                inliningPolicy: NeverInline(),
                ecmaVersion: ECMAScriptVersion.es6,
                environment: JavaScriptEnvironment(additionalBuiltins: [:], additionalObjectGroups: []))


func importFuzzILState(data: Data) throws {
    let state = try Fuzzilli_Protobuf_FuzzerState(serializedData: data)
    try corpus.importState(state.corpus)
}

// Takes a path, and stores each program to an individual file in that folder
func dumpProtobufs(dumpPath: String) throws {
    // Check if folder exists. If not, make it
    do {
        try FileManager.default.createDirectory(atPath: dumpPath, withIntermediateDirectories: true)
    } catch {
        print("Failed to create directory for protobuf splitting. Is folder \(dumpPath) configured correctly?")
        exit(-1)
    }
    // Write each program as a protobuf to individual files
    var prog_index = 0
    for prog in corpus {
        let name = "prog_\(prog_index).il.protobuf"
        let progURL = URL(fileURLWithPath: "\(dumpPath)/\(name)")
        do {
            let serializedProg = try prog.asProtobuf().serializedData()
            try serializedProg.write(to: progURL)
        } catch {
            print("Failed to serialize program. Skipping")
        }
        prog_index += 1
    }
}

// Read in a protobuf
func readProtoToString(path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let proto = try Fuzzilli_Protobuf_Program(serializedData: data)
    var resString = String()
    dump(proto, to:&resString, maxDepth: 3)
    return resString
}

// Convert a serialized protobuf file to a FuzzIL program
func protobufToProgram(path: String) throws -> Program {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let proto = try Fuzzilli_Protobuf_Program(serializedData: data)
    let program = try Program(from: proto)
    return program
}

// Take a program and lifts it to a JS script
func liftToJS(prog: Program) -> String {
    let res = lifter.lift(prog)
    return res.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Prints a Fuzzilli program as a string
func getPrettyStringProgram(program: Program) -> String {
    var resString = String()
    dump(program, to: &resString)
    return resString.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Takes all .il.protobuf files in a directory, and lifts them to JS
// Returns the number of files successfully converted
func compileAllProtosToJS(dirPath: String) throws -> Int {
    let fileEnumerator = FileManager.default.enumerator(atPath: dirPath)
    var count = 0
    while let fileName = fileEnumerator?.nextObject() as? String {
        guard fileName.hasSuffix(protoBufFileExtension) else { continue }
        let fullPath = dirPath + fileName
        let prog = try protobufToProgram(path: fullPath)
        let jsProgString = liftToJS(prog: prog)
        let newFilePath = dirPath + String(fileName.dropLast(protoBufFileExtension.count)) + jsFileExtension
        try jsProgString.write(to: URL(fileURLWithPath: newFilePath), atomically: false, encoding: String.Encoding.utf8)
        count += 1
    }
    return count
}

// Provided a directory with a bunch of protobuf files, combine them all into a corpus file for consumption by Fuzzilli
func combineProtobufs(dirPath: String, outputFile: String) throws -> Int {
    let fileEnumerator = FileManager.default.enumerator(atPath: dirPath)
    var failed_count = 0
    var progs = [Program]()
    while let fileName = fileEnumerator?.nextObject() as? String {
        guard fileName.hasSuffix(protoBufFileExtension) else { continue }
        let fullPath = dirPath + fileName
        var prog = Program()
        do {
            prog = try protobufToProgram(path: fullPath)
            progs.append(prog)
        } catch {
            print("Failed to convert to program \(fileName) with error \(error)")
            failed_count += 1
            continue
        }
    }

    let buf = try encodeProtobufCorpus(progs)
    let url = URL(fileURLWithPath: outputFile)
    try buf.write(to: url)
    print("Successfully converted \(progs.count) failed \(failed_count)")
    return progs.count
}

let args = Arguments.parse(from: CommandLine.arguments)

if args["-h"] != nil || args["--help"] != nil || args.numPositionalArguments != 0 {
    print("""
          Usage:
          \(args.programName) [options] 

          Options:
              --fuzzILState=path          : Path of a FuzzIL state file 
              --splitState=path           : Splits out a fuzzil profile into individual protobuf programs in specified file
              --combineBuffs=path         : Combines all encoded protobufs in a folder into a single fuzzilli state.
              --ILToJS=path               : Takes a single protobuf file and converts it to JS     
              --printProtobufAsProg=path  : Takes a single protobuf file and pretty prints it as a Fuzzilli program
              --printProtobuf=path        : Takes a single protobuf file and pretty prints it as a Protobuf
              --dirILToJS=path            : Takes all of the .il.protobuf files in an directory, and produces .js files in that same directory  
              --combineProtoDir=path      : combines all of the .il.protobuf files in a directory into a corpus.bin file for consumption by Fuzzilli
          """)
    exit(0)
}


let fuzzILPath = args["--fuzzILState"]
let splitStatePath = args["--splitState"]
let combineBuffsPath = args["--combineBuffs"]
let ilToJSPath = args["--ILToJS"]
let printProtoAsProgPath = args["--printProtobufAsProg"]
let printProtoPath = args["--printProtobuf"]
let dirILToJS = args["--dirILToJS"]
let combineDir = args["--combineProtoDir"]

if splitStatePath != nil && fuzzILPath == nil {
    print("Splitting state requires fuzzILState to be set")
    exit(-1)
}

// Split out an already built state
if let splitPath = splitStatePath, let statePath = fuzzILPath {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        try importFuzzILState(data: data)
        try dumpProtobufs(dumpPath: splitPath)
    } catch {
        print("Failed to import FuzzIL State with \(error)")
        exit(-1)
    }
}

// Covert a single IL protobuf file to JS and print to stdout
else if let ilPath = ilToJSPath {
    var prog = Program()
    do {
        prog = try protobufToProgram(path: ilPath)
    } catch {
        print("Failed to load il proto \(ilPath) with error \(error)")
        exit(-1)
    }
    let jsProgString = liftToJS(prog: prog)
    print(jsProgString)
}

// Pretty print just the protobuf, without trying to load as a program
// This allows the debugging of produced programs that are not syntactically valid
else if let printPath = printProtoPath {
    let res = try readProtoToString(path: printPath)
    print(res)
}


// Pretty print a protobuf as a program on stdout
else if let printPath = printProtoAsProgPath {
    var prog = Program()
    do {
        prog = try protobufToProgram(path: printPath)
    } catch {
        print("Failed to load il proto \(printPath) with error \(error)")
        exit(-1)
    }
    let prettyProgString = getPrettyStringProgram(program: prog)
    print(prettyProgString)
}

// Produce JS files from protobufs
else if let dirPath = dirILToJS {
    var isDir : ObjCBool = false
    if !FileManager.default.fileExists(atPath: dirPath, isDirectory:&isDir) || !isDir.boolValue {
        print("Provided directory \(dirPath) is not a valid directory path")
        exit(-1)
    }
    do {
        let numConverted = try compileAllProtosToJS(dirPath: dirPath)
        print("Successfully converted \(numConverted) files")
    } catch {
        print("Failed to compile protos with error \(error)")
        exit(-1)
    }
}

// Combine a bunch of protobufs into a state json
else if let dirPath = combineDir {
    var isDir : ObjCBool = false
    if !FileManager.default.fileExists(atPath: dirPath, isDirectory:&isDir) || !isDir.boolValue {
        print("Provided directory \(dirPath) is not a valid directory path")
        exit(-1)
    }
    do {
        let numConverted = try combineProtobufs(dirPath: dirPath, outputFile: "corpus.bin")
        print("Successfully combined \(numConverted) files into corpus.bin")
    } catch {
        print("Failed to combine protos with error \(error)")
        exit(-1)
    }
}

else {
    print("Please enter a command to use")
    exit(-1)
}
