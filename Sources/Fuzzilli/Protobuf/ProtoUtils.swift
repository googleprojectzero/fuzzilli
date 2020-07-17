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

// Operation cache for protobuf conversion.
// This enables the "compressed" protobuf program encoding in
// which an duplicate operation can be replaced with the index
// its first occurance in the serialized data.
public class OperationCache {
    // Maps Operations to the index of their owning instruction in the output data.
    private var indices: [ObjectIdentifier: Int]? = nil
    // Maps indices to their operation.
    private var operations = [Operation]()
    
    private init(useIndicesMap: Bool = true) {
        if useIndicesMap {
            indices = [:]
        }
    }
    
    static func forEncoding() -> OperationCache {
        return OperationCache(useIndicesMap: true)
    }
    
    static func forDecoding() -> OperationCache {
        // The lookup dict is not needed for decoding
        return OperationCache(useIndicesMap: false)
    }
    
    func get(_ i: Int) -> Operation? {
        if !operations.indices.contains(i) {
            return nil
        }
        return operations[i]
    }
    
    func get(_ k: Operation) -> Int? {
        return indices?[ObjectIdentifier(k)]
    }
    
    func add(_ operation: Operation) {
        let id = ObjectIdentifier(operation)
        if indices != nil && !indices!.keys.contains(id) {
            indices?[id] = operations.count
        }
        operations.append(operation)
    }
}

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

    var buf = Data()
    let opCache = OperationCache.forEncoding()
    for program in programs {
        let proto = program.asProtobuf(with: opCache)
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
    var offset = 0
    
    var newPrograms = [Program]()
    while offset + 4 < buffer.count {
        let value = buffer.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        let size = Int(UInt32(littleEndian: value))
        offset += 4
        guard offset + size <= buffer.count else {
            throw FuzzilliError.corpusImportError("Invalid program size in corpus")
        }
        let data = buffer.subdata(in: offset..<offset+size)
        offset += size + align(size, to: 4)
        let proto = try Fuzzilli_Protobuf_Program(serializedData: data)
        let program = try Program(from: proto, with: opCache)
        newPrograms.append(program)
    }
    return newPrograms
}

