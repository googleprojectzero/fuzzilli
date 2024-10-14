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

/// Immutable unit of code that can, amongst others, be lifted, executed, scored, (de)serialized, and serve as basis for mutations.
///
/// A Program's code is guaranteed to have a number of static properties, as checked by code.isStaticallyValid():
/// * All input variables must have previously been defined
/// * Variables have increasing numbers starting at zero and there are no holes
/// * Variables are only used while they are visible (the block they were defined in is still active)
/// * Blocks are balanced and the opening and closing operations match (e.g. BeginIf is closed by EndIf)
/// * The outputs of an instruction are always new variables and never overwrite an existing variable
///
public final class Program {
    /// The immutable code of this program.
    public let code: Code

    /// The parent program that was used to construct this program.
    /// This is mostly only used when inspection mode is enabled to reconstruct
    /// the "history" of a program.
    public private(set) var parent: Program? = nil

    /// Comments attached to this program.
    public var comments = ProgramComments()

    /// Everything that contributed to this program. This is not preserved across protobuf serialization.
    public var contributors = Contributors()

    /// Each program has a unique ID to identify it even accross different fuzzer instances.
    public private(set) lazy var id = UUID()

    /// Constructs an empty program.
    public init() {
        self.code = Code()
        self.parent = nil
    }

    /// Constructs a program with the given code. The code must be statically valid.
    public init(with code: Code) {
        assert(code.isStaticallyValid())
        self.code = code
    }

    /// Construct a program with the given code and type information.
    public convenience init(code: Code, parent: Program? = nil, comments: ProgramComments = ProgramComments(), contributors: Contributors = Contributors()) {
        // We should never see instructions with set flags here, as Flags are currently only used temporarily (e.g. Minimizer)
        assert(code.allSatisfy { instr in instr.flags == Instruction.Flags.empty })
        self.init(with: code)
        self.comments = comments
        self.contributors = contributors
        self.parent = parent
    }

    /// The number of instructions in this program.
    public var size: Int {
        return code.count
    }

    /// Indicates whether this program is empty.
    public var isEmpty: Bool {
        return size == 0
    }

    public func clearParent() {
        parent = nil
    }

    // Create and return a deep copy of this program.
    public func copy() -> Program {
        let proto = self.asProtobuf()
        return try! Program(from: proto)
    }

    public var containsWasm: Bool {
        for instr in code {
            if instr.op is WasmOperation {
                return true
            }
        }

        return false
    }

    /// This function can be invoked from the debugger to store a program that throws an assertion to disk.
    /// The idea is to then use the FuzzILTool to lift the program, which can help debug Fuzzilli issues.
    public func storeToDisk(atPath path: String) {
        assert(path.hasSuffix(".fzil"))
        do {
            let pb = try self.asProtobuf().serializedData()
            let url = URL(fileURLWithPath: path)
            try pb.write(to: url)
        } catch {
            fatalError("Failed to serialize program to protobuf: \(error)")
        }
    }

    /// This convienience initializer helps to load a program from disk. This can be helpful for debugging purposes.
    convenience init(fromPath path: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let pb = try Fuzzilli_Protobuf_Program(serializedBytes: data)
            try self.init(from: pb)
        } catch {
            fatalError("Failed to create program from protobuf: \(error)")
        }
    }
}

extension Program: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_Program

    func asProtobuf(opCache: OperationCache? = nil) -> ProtobufType {
        return ProtobufType.with {
            $0.uuid = id.uuidData
            $0.code = code.map({ $0.asProtobuf(with: opCache) })

            if !comments.isEmpty {
                $0.comments = comments.asProtobuf()
            }

            if let parent = parent {
                $0.parent = parent.asProtobuf(opCache: opCache)
            }
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(opCache: nil)
    }

    convenience init(from proto: ProtobufType, opCache: OperationCache? = nil) throws {
        var code = Code()
        for (i, protoInstr) in proto.code.enumerated() {
            do {
                code.append(try Instruction(from: protoInstr, with: opCache))
            } catch FuzzilliError.instructionDecodingError(let reason) {
                throw FuzzilliError.programDecodingError("could not decode instruction #\(i): \(reason)")
            }
        }

        do {
            try code.check()
        } catch FuzzilliError.codeVerificationError(let reason) {
            throw FuzzilliError.programDecodingError("decoded code is not statically valid: \(reason)")
        }

        self.init(code: code)

        if let uuid = UUID(uuidData: proto.uuid) {
            self.id = uuid
        }

        self.comments = ProgramComments(from: proto.comments)

        if proto.hasParent {
            self.parent = try Program(from: proto.parent, opCache: opCache)
        }
    }

    public convenience init(from proto: ProtobufType) throws {
        try self.init(from: proto, opCache: nil)
    }
}
