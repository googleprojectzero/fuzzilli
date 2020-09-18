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
/// * An instruction always produces a new output variable
///
public final class Program {
    /// The immutable code of this program.
    public let code: Code
    
    /// The parent program that was used to construct this program.
    /// This is mostly only used when inspection mode is enabled to reconstruct
    /// the "history" of a program.
    public private(set) var parent: Program? = nil
    
    /// Comments attached to this program
    public var comments = ProgramComments()

    /// Current type information combined from available sources
    public var types = ProgramTypes()

    /// Result of runtime type collection execution, by default there was none.
    public var typeCollectionStatus = TypeCollectionStatus.notAttempted
    
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
    public convenience init(code: Code, parent: Program? = nil, types: ProgramTypes = ProgramTypes(), comments: ProgramComments = ProgramComments()) {
        self.init(with: code)
        self.types = types
        self.comments = comments
        self.parent = parent
    }

    public func type(of variable: Variable, after instrIndex: Int) -> Type {
        return types.getType(of: variable, after: instrIndex)
    }

    public func type(of variable: Variable, before instrIndex: Int) -> Type {
        return types.getType(of: variable, after: instrIndex - 1)
    }

    /// The number of instructions in this program.
    public var size: Int {
        return code.count
    }

    /// Indicates whether this program is empty.
    public var isEmpty: Bool {
        return size == 0
    }

    var hasTypeInformation: Bool {
        return !types.isEmpty
    }
    
    public func clearParent() {
        parent = nil
    }
}

extension Program: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_Program

    func asProtobuf(opCache: OperationCache? = nil, typeCache: TypeCache? = nil) -> ProtobufType {
        return ProtobufType.with {
            $0.uuid = id.uuidData
            $0.code = code.map({ $0.asProtobuf(with: opCache) })
            $0.types = types.asProtobuf(with: typeCache)
            $0.typeCollectionStatus = Fuzzilli_Protobuf_TypeCollectionStatus(rawValue: Int(typeCollectionStatus.rawValue))!

            if !comments.isEmpty {
                $0.comments = comments.asProtobuf()
            }

            if let parent = parent {
                $0.parent = parent.asProtobuf(opCache: opCache, typeCache: typeCache)
            }
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(opCache: nil, typeCache: nil)
    }
    
    convenience init(from proto: ProtobufType, opCache: OperationCache? = nil, typeCache: TypeCache? = nil) throws {
        var code = Code()
        for protoInstr in proto.code {
            code.append(try Instruction(from: protoInstr, with: opCache))
        }

        guard code.isStaticallyValid() else {
            throw FuzzilliError.programDecodingError("Decoded code is not statically valid")
        }

        self.init(code: code, types: try ProgramTypes(from: proto.types, with: typeCache))

        self.typeCollectionStatus = TypeCollectionStatus(rawValue: UInt8(proto.typeCollectionStatus.rawValue)) ?? .notAttempted

        if let uuid = UUID(uuidData: proto.uuid) {
            self.id = uuid
        }

        self.comments = try ProgramComments(from: proto.comments)

        if proto.hasParent {
            self.parent = try Program(from: proto.parent, opCache: opCache, typeCache: typeCache)
        }
    }
    
    public convenience init(from proto: ProtobufType) throws {
        try self.init(from: proto, opCache: nil, typeCache: nil)
    }
}
