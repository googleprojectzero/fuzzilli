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
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // Default script context
    public static let script            = Context(rawValue: 1 << 0)
    // Inside a function definition
    public static let function          = Context(rawValue: 1 << 1)
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
    public static let switchCase        = Context(rawValue: 1 << 7)

    public static let empty             = Context([])
}