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

    /// Current type information combined from available sources
    public var types = ProgramTypes()

    /// Result of runtime type collection execution, by default there was none.
    public var typeCollectionStatus = TypeCollectionStatus.notAttempted

    /// Constructs an empty program.
    public init() {
        self.code = Code()
    }

    /// Constructs a program with the given code. The code must be statically valid.
    public init(with code: Code) {
        assert(code.isStaticallyValid())
        self.code = code
    }

    /// Construct a program with the given code and type information.
    public convenience init(code: Code, types: ProgramTypes) {
        self.init(with: code)
        self.types = types
    }

    public func type(of variable: Variable, after instrIndex: Int) -> Type {
        return types.getType(of: variable, after: instrIndex)
    }

    public func type(of variable: Variable, before instrIndex: Int) -> Type {
        return types.getType(of: variable, after: instrIndex - 1)
    }

    /// The number of instructions in this program.
    var size: Int {
        return code.count
    }

    /// Indicates whether this program is empty.
    var isEmpty: Bool {
        return size == 0
    }

    var hasTypeInformation: Bool {
        return !types.isEmpty
    }
}

extension Program: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_Program

    func asProtobuf(opCache: OperationCache? = nil, typeCache: TypeCache? = nil) -> ProtobufType {
        return ProtobufType.with {
            $0.instructions = code.map({ $0.asProtobuf(with: opCache) })
            $0.types = types.asProtobuf(with: typeCache)
            $0.typeCollectionStatus = Fuzzilli_Protobuf_TypeCollectionStatus(rawValue: Int(typeCollectionStatus.rawValue))!
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(opCache: nil, typeCache: nil)
    }
    
    convenience init(from proto: ProtobufType, opCache: OperationCache? = nil, typeCache: TypeCache? = nil) throws {
        var code = Code()
        for protoInstr in proto.instructions {
            code.append(try Instruction(from: protoInstr, with: opCache))
        }

        guard code.isStaticallyValid() else {
            throw FuzzilliError.programDecodingError("Decoded code is not statically valid")
        }

        self.init(code: code, types: try ProgramTypes(from: proto.types, with: typeCache))

        self.typeCollectionStatus = TypeCollectionStatus(rawValue: UInt8(proto.typeCollectionStatus.rawValue)) ?? .notAttempted
    }
    
    public convenience init(from proto: ProtobufType) throws {
        try self.init(from: proto, opCache: nil, typeCache: nil)
    }
}
