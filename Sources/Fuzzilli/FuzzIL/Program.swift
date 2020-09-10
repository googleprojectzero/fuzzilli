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

    /// Runtype types of variables
    public var runtimeTypes = ProgramTypes()

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

    /// The number of instructions in this program.
    var size: Int {
        return code.count
    }

    /// Indicates whether this program is empty.
    var isEmpty: Bool {
        return size == 0
    }
}

extension Program: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_Program

    func asProtobuf(with opCache: OperationCache?) -> ProtobufType {
        return ProtobufType.with {
            $0.instructions = code.map({ $0.asProtobuf(with: opCache) })
            for (variable, instrMap) in runtimeTypes {
                $0.runtimeTypes[UInt32(variable.number)] = Fuzzilli_Protobuf_TypeMap()
                for typeData in instrMap {
                    $0.runtimeTypes[UInt32(variable.number)]!.typeMap[UInt32(typeData.index)] = typeData.type.asProtobuf()
                }
            }
            $0.typeCollectionStatus = Fuzzilli_Protobuf_TypeCollectionStatus(rawValue: typeCollectionStatus.rawValue)!
        }
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }
    
    public convenience init(from proto: ProtobufType, with opCache: OperationCache?) throws {
        var code = Code()
        for protoInstr in proto.instructions {
            code.append(try Instruction(from: protoInstr, with: opCache))
        }

        guard code.isStaticallyValid() else {
            throw FuzzilliError.programDecodingError("Decoded code is not statically valid")
        }

        self.init(with: code)

        for (varNumber, instrMap) in proto.runtimeTypes {
            for (instrIndex, protoType) in instrMap.typeMap {
                runtimeTypes.setType(
                    of: Variable(number: Int(varNumber)),
                    to: try Type(from: protoType),
                    at: Int(instrIndex)
                )
            }
        }

        self.typeCollectionStatus = TypeCollectionStatus(rawValue: proto.typeCollectionStatus.rawValue)
    }
    
    public convenience init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}
