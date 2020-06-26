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
class OperationCache {
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

// Errors that can occur during protobuf conversion.
public enum ProtobufDecodingError: Error {
    case invalidInstructionError(String)
    case invalidTypeError(String)
    case invalidProgramError(String)
    case invalidCorpusError(String)
}
