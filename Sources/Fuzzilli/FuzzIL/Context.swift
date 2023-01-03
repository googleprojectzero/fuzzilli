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

/// Current context in the program
public struct Context: OptionSet {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Default javascript context
    public static let javascript        = Context(rawValue: 1 << 0)
    // Inside a subroutine (function, constructor, method, ...) definition
    public static let subroutine        = Context(rawValue: 1 << 1)
    // Inside a generator function definition
    public static let generatorFunction = Context(rawValue: 1 << 2)
    // Inside an async function definition
    public static let asyncFunction     = Context(rawValue: 1 << 3)
    // Inside a loop
    public static let loop              = Context(rawValue: 1 << 4)
    // Inside a with statement
    public static let with              = Context(rawValue: 1 << 5)
    // Inside a class definition
    public static let classDefinition   = Context(rawValue: 1 << 6)
    // Inside a switch block
    public static let switchBlock       = Context(rawValue: 1 << 7)
    // Inside a switch case
    public static let switchCase        = Context(rawValue: 1 << 8)

    public static let empty             = Context([])
}
