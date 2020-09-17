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
public enum TypeQuality: UInt8 {
    case inferred
    case runtime
}

// Store known types for program variables at specific instructions
public struct TypeInfo: Equatable {
    private let _index: UInt16
    public let type: Type
    public let quality: TypeQuality
    public var index: Int {
        return Int(_index)
    }

    public init(index: Int, type: Type, quality: TypeQuality) {
        self._index = UInt16(index)
        self.type = type
        self.quality = quality
    }

    public static func == (lhs: TypeInfo, rhs: TypeInfo) -> Bool {
        return lhs._index == rhs._index && lhs.type == rhs.type && lhs.quality == rhs.quality
    }
}

extension TypeInfo: ProtobufConvertible {
    public typealias ProtobufType = Fuzzilli_Protobuf_TypeInfo

    func asProtobuf() -> ProtobufType {
        return ProtobufType.with {
            $0.index = UInt32(index)
            $0.type = type.asProtobuf()
            $0.quality = Fuzzilli_Protobuf_TypeQuality(rawValue: Int(quality.rawValue))!
        }
    }

    public init(from proto: ProtobufType) throws {
        self._index = UInt16(proto.index)
        self.type = try Type(from: proto.type)
        self.quality = TypeQuality(rawValue: UInt8(proto.quality.rawValue)) ?? .inferred
    }
}
