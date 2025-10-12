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

// Protocol for objects that have a corresponding Protobuf message.
protocol ProtobufConvertible {
    associatedtype ProtobufType

    func asProtobuf() -> ProtobufType
    init(from protobuf: ProtobufType) throws
}

// Cache for protobuf conversion.
// This enables "compressed" protobuf encoding in which duplicate
// messages can be replaced with the index of the first occurance
// of the message in the serialized data.
// This requires deterministic serialization to work correctly, i.e.
// the nth encoded message must also be the nth decode message.
class ProtoCache<T: AnyObject> {
    // Maps elements to their number in the protobuf message.
    private var indices: [ObjectIdentifier: Int]? = nil
    // Maps indices to their elements.
    private var elements = [T]()

    private init(useIndicesMap: Bool = true) {
        if useIndicesMap {
            indices = [:]
        }
    }

    static func forEncoding() -> ProtoCache {
        return ProtoCache(useIndicesMap: true)
    }

    static func forDecoding() -> ProtoCache {
        // The lookup dict is not needed for decoding
        return ProtoCache(useIndicesMap: false)
    }

    func get(_ i: Int) -> T? {
        if !elements.indices.contains(i) {
            return nil
        }
        return elements[i]
    }

    func get(_ k: T) -> Int? {
        return indices?[ObjectIdentifier(k)]
    }

    func add(_ ext: T) {
        let id = ObjectIdentifier(ext)
        if indices != nil && !indices!.keys.contains(id) {
            indices?[id] = elements.count
        }
        elements.append(ext)
    }
}

typealias OperationCache = ProtoCache<Operation>

public func encodeProtobufCorpus<T: Collection>(_ programs: T) throws -> Data where T.Element == Program  {
    // This does streaming serialization to keep memory usage as low as possible.
    // Also, this uses the operation compression feature of our protobuf representation:
    // when the same operation occurs multiple times in the corpus, every subsequent
    // occurance in the protobuf is simply the index of instruction with the first occurance.
    //
    // The binary format is simply
    //    [ program1 | program2 | ... | programN ]
    // where every program is encoded as
    //    [ size without padding in bytes as uint32 | serialized program protobuf | padding ]
    // The padding ensures 4 byte alignment of every program.
    //
    // This must be deterministic due to the use of protobuf caches (see ProtoCache struct).

    var buf = Data()
    let opCache = OperationCache.forEncoding()
    for program in programs {
        let proto = program.asProtobuf(opCache: opCache)
        let serializedProgram = try proto.serializedData()
        var size = UInt32(serializedProgram.count).littleEndian
        buf.append(Data(bytes: &size, count: 4))
        buf.append(serializedProgram)
        // Align to 4 bytes
        buf.append(Data(count: align(buf.count, to: 4)))
    }
    return buf
}

public func decodeProtobufCorpus(_ buffer: Data) throws -> [Program]{
    let opCache = OperationCache.forDecoding()
    var offset = buffer.startIndex

    var newPrograms = [Program]()
    while offset + 4 <= buffer.endIndex {
        let value = buffer.withUnsafeBytes { $0.load(fromByteOffset: offset - buffer.startIndex, as: UInt32.self) }
        let size = Int(UInt32(littleEndian: value))
        offset += 4
        guard offset + size <= buffer.endIndex else {
            throw FuzzilliError.corpusImportError("Serialized corpus appears to be corrupted")
        }
        let data = buffer.subdata(in: offset..<offset+size)
        offset += size + align(size, to: 4)
        let proto = try Fuzzilli_Protobuf_Program(serializedBytes: data)
        let program = try Program(from: proto, opCache: opCache)
        newPrograms.append(program)
    }
    return newPrograms
}

// Make UUIDs convertible to Data, used for protobuf conversion
extension UUID {
    var uuidData: Data {
        return withUnsafePointer(to: uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: uuid))
        }
    }

    init?(uuidData: Data) {
        guard uuidData.count == 16 else {
            return nil
        }

        var uuid: uuid_t = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &uuid) {
            $0.copyBytes(from: uuidData)
        }
        self.init(uuid: uuid)
    }
}
