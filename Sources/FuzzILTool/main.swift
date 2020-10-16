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
let protoBufFileExtension = ".fuzzil.protobuf"

let jsPrefix = ""
let jsSuffix = ""

let jsLifter = JavaScriptLifter(prefix: jsPrefix,
                suffix: jsSuffix,
                inliningPolicy: InlineOnlyLiterals(),
                ecmaVersion: ECMAScriptVersion.es6)
let fuzzILLifter = FuzzILLifter()

// Loads a serialized FuzzIL program from the given file
func loadProgram(from path: String) throws -> Program {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let proto = try Fuzzilli_Protobuf_Program(serializedData: data)
    let program = try Program(from: proto)
    return program
}

func loadAllPrograms(in dirPath: String) -> [(filename: String, program: Program)] {
    var isDir: ObjCBool = false
    if !FileManager.default.fileExists(atPath: dirPath, isDirectory:&isDir) || !isDir.boolValue {
        print("\(path) is not a directory!")
        exit(-1)
    }

    let fileEnumerator = FileManager.default.enumerator(atPath: dirPath)
    var results = [(String, Program)]()
    while let filename = fileEnumerator?.nextObject() as? String {
        guard filename.hasSuffix(protoBufFileExtension) else { continue }
        let path = dirPath + "/" + filename
        do {
            let program = try loadProgram(from: path)
            results.append((filename, program))
        } catch FuzzilliError.programDecodingError(let reason) {
            print("Failed to load program \(path): \(reason)")
        } catch {
            print("Failed to load program \(path) due to unexpected error: \(error)")
        }
    }
    return results
}

// Take a program and lifts it to JavaScript
func liftToJS(_ prog: Program) -> String {
    let res = jsLifter.lift(prog)
    return res.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Take a program and lifts it to FuzzIL's text format
func liftToFuzzIL(_ prog: Program) -> String {
    let res = fuzzILLifter.lift(prog)
    return res.trimmingCharacters(in: .whitespacesAndNewlines)
}

// Loads all .fuzzil.protobuf files in a directory, and lifts them to JS
// Returns the number of files successfully converted
func liftAllPrograms(in dirPath: String, with lifter: Lifter, fileExtension: String) -> Int {
    var numLiftedPrograms = 0
    for (filename, program) in loadAllPrograms(in: dirPath) {
        let newFilePath = "\(dirPath)/\(filename.dropLast(protoBufFileExtension.count))\(fileExtension)"
        let content = lifter.lift(program)
        do {
            try content.write(to: URL(fileURLWithPath: newFilePath), atomically: false, encoding: String.Encoding.utf8)
            numLiftedPrograms += 1
        } catch {
            print("Failed to write file \(newFilePath): \(error)")
        }
    }
    return numLiftedPrograms
}

func loadProgramOrExit(from path: String) -> Program {
    do {
        return try loadProgram(from: path)
    } catch {
        print("Failed to load program from \(path): \(error)")
        exit(-1)
    }
}

let args = Arguments.parse(from: CommandLine.arguments)

if args["-h"] != nil || args["--help"] != nil || args.numPositionalArguments != 1 || args.numOptionalArguments != 1 {
    print("""
          Usage:
          \(args.programName) option path

          Options:
              --liftToFuzzIL         : Lifts the given protobuf program to FuzzIL's text format and prints it
              --liftToJS             : Lifts the given protobuf program to JS and prints it
              --liftCorpusToJS       : Loads all .fuzzil.protobuf files in a directory and lifts them to .js files in that same directory
              --dumpProtobuf         : Dumps the raw content of the given protobuf file
              --dumpProgram          : Dumps the internal representation of the program stored in the given protobuf file
              --checkCorpus          : Attempts to load all .fuzzil.protobuf files in a directory and checks if they are statically valid
          """)
    exit(0)
}

let path = args[0]

// Covert a single IL protobuf file to FuzzIL's text format and print to stdout
if args.has("--liftToFuzzIL") {
    let program = loadProgramOrExit(from: path)
    print(liftToFuzzIL(program))
}

// Covert a single IL protobuf file to JS and print to stdout
else if args.has("--liftToJS") {
    let program = loadProgramOrExit(from: path)
    print(liftToJS(program))
}

// Lift all protobuf programs to JavaScript
else if args.has("--liftCorpusToJS") {
    let numLiftedPrograms = liftAllPrograms(in: path, with: jsLifter, fileExtension: jsFileExtension)
    print("Lifted \(numLiftedPrograms) programs to JS")
}

// Pretty print just the protobuf, without trying to load as a program
// This allows the debugging of produced programs that are not syntactically valid
else if args.has("--dumpProtobuf") {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let proto = try Fuzzilli_Protobuf_Program(serializedData: data)
    dump(proto, maxDepth: 3)
}

// Pretty print a protobuf as a program on stdout
else if args.has("--dumpProgram") {
    let program = loadProgramOrExit(from: path)
    dump(program)
}

// Combine multiple protobuf programs into a single corpus file
else if args.has("--checkCorpus") {
    let numPrograms = loadAllPrograms(in: path).count
    print("Successfully loaded \(numPrograms) programs")
}

else {
    print("Invalid option: \(args.unusedOptionals.first!)")
    exit(-1)
}
