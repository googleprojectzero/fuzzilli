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

public struct ProgramTypes: Equatable, Sequence {
    private var types = VariableMap<[TypeInfo]>()

    public init () {}

    public init (from types: VariableMap<[TypeInfo]>) {
        self.types = types
    }

    // Create structure in simple case, when we have only types on definition
    public init (from types: VariableMap<(Type, TypeQuality)>, in program: Program) {
        let analyzer = VariableAnalyzer(for: program)
        for (variable, (type, quality)) in types {
            setType(of: variable, to: type, after: analyzer.definition(of: variable).index, quality: quality)
        }
    }

    // Create structure in simple case, when we have only types on definition with given quality
    public init (from types: VariableMap<Type>, in program: Program, quality: TypeQuality) {
        var typesWithQuality = VariableMap<(Type, TypeQuality)>()
        for (variable, type) in types {
            typesWithQuality[variable] = (type, quality)
        }

        self.init(from: typesWithQuality, in: program)
    }

    public static func == (lhs: ProgramTypes, rhs: ProgramTypes) -> Bool {
        return lhs.types == rhs.types
    }

    // Save type of given variable after given instruction
    public mutating func setType(of variable: Variable, to type: Type, after instrIndex: Int, quality: TypeQuality) {
        // Initialize type structure for given variable if not already
        if types[variable] == nil {
            types[variable] = []
        }
        let typeInfo = TypeInfo(index: instrIndex, type: type, quality: quality)
        // Check if we update type of instruction in the middle
        if let insertionIndex = types[variable]!.firstIndex(where: { $0.index >= instrIndex }) {
            if types[variable]![insertionIndex].index == instrIndex {
                // Overwrite old type
                types[variable]![insertionIndex] = typeInfo
            } else {
                // Add new type information at instrIndex
                types[variable]!.insert(typeInfo, at: insertionIndex)
            }
        } else {
            types[variable]!.append(typeInfo)
        }
    }

    // Get type of variable after given instruction
    public func getType(of variable: Variable, after instrIndex: Int) -> Type {
        if let variableTypes = types[variable] {
            Assert(variableTypes[0].index <= instrIndex, "Queried type of variable before its definition")
            return variableTypes.last(where: { $0.index <= instrIndex })!.type
        } else {
            return .unknown
        }
    }

    // Filter out only runtime types
    public func onlyRuntimeTypes() -> ProgramTypes {
        var runtimeTypes = ProgramTypes()
        for (variable, instrTypes) in types {
            for typeInfo in instrTypes {
                guard typeInfo.quality == .runtime else { continue }

                runtimeTypes.setType(
                    of: variable, to: typeInfo.type, after: typeInfo.index, quality: .runtime
                )
            }
        }
        return runtimeTypes
    }

    // Format ProgramTypes struct so searching for type changes at instruction is easier
    public func indexedByInstruction(for program: Program) -> [[(Variable, Type)]] {
        var typesMap: [[(Variable, Type)]] = Array(repeating: [], count: program.size)
        for (variable, instrTypes) in types {
            for typeInfo in instrTypes {
                typesMap[typeInfo.index].append((variable, typeInfo.type))
            }
        }
        return typesMap
    }

    public func makeIterator() -> VariableMap<[TypeInfo]>.Iterator {
        return types.makeIterator()
    }

    public var isEmpty: Bool {
        return types.isEmpty
    }
}

extension ProgramTypes: ProtobufConvertible {
    public typealias ProtobufType = [Fuzzilli_Protobuf_TypeInfo]

    func asProtobuf(with typeCache: TypeCache?) -> ProtobufType {
        var proto = ProtobufType()
        for (variable, instrTypes) in self {
            for typeInfo in instrTypes {
                proto.append(Fuzzilli_Protobuf_TypeInfo.with {
                    $0.variable = UInt32(variable.number)
                    $0.index = UInt32(typeInfo.index)
                    $0.type = typeInfo.type.asProtobuf(with: typeCache)
                    $0.quality = Fuzzilli_Protobuf_TypeQuality(rawValue: Int(typeInfo.quality.rawValue))!
                })
            }
        }

        return proto
    }

    public func asProtobuf() -> ProtobufType {
        return asProtobuf(with: nil)
    }

    init(from proto: ProtobufType, with typeCache: TypeCache?) throws {
        self.init()
        for protoTypeInfo in proto {
            guard Variable.isValidVariableNumber(Int(clamping: protoTypeInfo.variable)) else {
                throw FuzzilliError.typeDecodingError("invalid variable in program types")
            }
            guard let quality = TypeQuality(rawValue: UInt8(protoTypeInfo.quality.rawValue)) else {
                throw FuzzilliError.typeDecodingError("invalid type quality in program types")
            }
            setType(
                of: Variable(number: Int(protoTypeInfo.variable)),
                to: try Type(from: protoTypeInfo.type, with: typeCache),
                after: Int(protoTypeInfo.index),
                quality: quality
            )
        }
    }

    public init(from proto: ProtobufType) throws {
        try self.init(from: proto, with: nil)
    }
}
