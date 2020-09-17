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
            setType(of: variable, to: type, at: analyzer.definition(of: variable).index, quality: quality)
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

    // Save type of given variable
    public mutating func setType(of variable: Variable, to type: Type, at instrIndex: Int, quality: TypeQuality) {
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

    // Get type of variable at current instruction
    public func getType(of variable: Variable, at instrIndex: Int) -> Type {
        return types[variable]?.last(where: { $0.index <= instrIndex })?.type ?? .unknown
    }

    // Filter out only runtime types
    public func onlyRuntimeTypes() -> ProgramTypes {
        var runtimeTypes = ProgramTypes()
        for (variable, instrTypes) in types {
            for typeInfo in instrTypes {
                guard typeInfo.quality == .runtime else { continue }

                runtimeTypes.setType(
                    of: variable, to: typeInfo.type, at: typeInfo.index, quality: .runtime
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
    public typealias ProtobufType = [UInt32: Fuzzilli_Protobuf_InstrTypes]

    func asProtobuf() -> ProtobufType {
        var protobuf = ProtobufType()
        for (variable, instrTypes) in self {
            var protobufInstrTypes = Fuzzilli_Protobuf_InstrTypes()
            for typeInfo in instrTypes {
                protobufInstrTypes.typeInfo.append(typeInfo.asProtobuf())
            }
            protobuf[UInt32(variable.number)] = protobufInstrTypes
        }

        return protobuf
    }

    public init(from proto: ProtobufType) throws {
        self.init()
        for (varNumber, instrTypes) in proto {
            for typeInfo in instrTypes.typeInfo {
                setType(
                    of: Variable(number: Int(varNumber)),
                    to: try Type(from: typeInfo.type),
                    at: Int(typeInfo.index),
                    quality: TypeQuality(rawValue: UInt8(typeInfo.quality.rawValue)) ?? .inferred
                )
            }
        }
    }
}
