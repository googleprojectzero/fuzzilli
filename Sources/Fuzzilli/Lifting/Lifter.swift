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

/// Lifts a FuzzIL program to the target language.
public protocol Lifter {
    func lift(_ program: Program, withOptions options: LiftingOptions) -> String
}

extension Lifter {
    public func lift(_ program: Program) -> String {
        return lift(program, withOptions: [])
    }
}

public struct LiftingOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let dumpTypes = LiftingOptions(rawValue: 1 << 0)
    public static let minify = LiftingOptions(rawValue: 1 << 1)
    public static let collectTypes = LiftingOptions(rawValue: 1 << 2)
    public static let includeComments = LiftingOptions(rawValue: 1 << 3)
}
