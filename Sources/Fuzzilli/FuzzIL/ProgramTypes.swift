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
// Store known types for program variables at specific instructions
public struct TypeIndexPair: Equatable {
    public let index: Int
    public let type: Type

    public init(index: Int, type: Type){
        self.index = index
        self.type = type
    }

    public static func == (lhs: TypeIndexPair, rhs: TypeIndexPair) -> Bool {
        return lhs.index == rhs.index && lhs.type == rhs.type
    }
}

public struct ProgramTypes: Equatable, Sequence {
    private var types = VariableMap<[TypeIndexPair]>()

    public init () {}

    public init (from types: VariableMap<[TypeIndexPair]>) {
        self.types = types
    }

    // Create structure in simple case, when we have only types on definition
    public init (from types: VariableMap<Type>, in program: Program) {
        let analyzer = VariableAnalyzer(for: program)
        for (variable, type) in types {
            setType(of: variable, to: type, at: analyzer.definition(of: variable).index)
        }
    }

    public static func == (lhs: ProgramTypes, rhs: ProgramTypes) -> Bool {
        return lhs.types == rhs.types
    }

    // Save type of given variable
    public mutating func setType(of variable: Variable, to type: Type, at instrIndex: Int) {
        // Initialize type structure for given variable if not already
        if types[variable] == nil {
            types[variable] = []
        }
        let typeIndexPair = TypeIndexPair(index: instrIndex, type: type)
        // Check if we update type of instruction in the middle
        if let insertionIndex = types[variable]!.firstIndex(where: { $0.index >= instrIndex }) {
            if types[variable]![insertionIndex].index == instrIndex {
                // Overwrite old type
                types[variable]![insertionIndex] = typeIndexPair
            } else {
                // Add new type information at instrIndex
                types[variable]!.insert(typeIndexPair, at: insertionIndex)
            }
        } else {
            types[variable]!.append(typeIndexPair)
        }
    }

    // Get type of variable at current instruction
    public func getType(of variable: Variable, at instrIndex: Int) -> Type {
        return types[variable]?.last(where: { $0.index <= instrIndex })?.type ?? .unknown
    }

    public func makeIterator() -> VariableMap<[TypeIndexPair]>.Iterator {
        return types.makeIterator()
    }
}
