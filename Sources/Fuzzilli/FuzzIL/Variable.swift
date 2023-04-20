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

/// A variable in the FuzzIL language.
///
/// Variables names (numbers) are local to a program. Different programs
/// will have the same variable names referring to different things.
public struct Variable: Hashable, CustomStringConvertible {
    // We assume that programs will always have less than 64k variables
    private let num: UInt16?

    public init(number: Int) {
        self.num = UInt16(number)
    }

    public init() {
        self.num = nil
    }

    public var number: Int {
        return Int(num!)
    }

    public var description: String {
        return identifier
    }

    public var identifier: String {
        return "v\(number)"
    }

    public static func ==(lhs: Variable, rhs: Variable) -> Bool {
        return lhs.number == rhs.number
    }

    public static func isValidVariableNumber(_ number: Int) -> Bool {
        return UInt16(exactly: number) != nil
    }
}

extension Variable: Comparable {
    public static func <(lhs: Variable, rhs: Variable) -> Bool {
        return lhs.number < rhs.number
    }
}
