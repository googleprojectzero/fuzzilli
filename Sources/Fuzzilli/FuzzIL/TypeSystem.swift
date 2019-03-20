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

/// Types that a variable can have.
///
/// FuzzIL currently only supports a very limited system of types
/// that can trivially be computed statically.
public struct Type: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    // Could be anything
    public static let Unknown  = Type(rawValue: 1 << 0)
    
    // It definitely is an integer
    public static let Integer  = Type(rawValue: 1 << 1)
    
    /// It definitely is a floating point number
    public static let Float    = Type(rawValue: 1 << 2)
    
    /// It definitely is a string
    public static let String   = Type(rawValue: 1 << 3)
    
    // It definitely is a boolean value
    public static let Boolean  = Type(rawValue: 1 << 4)
    
    // It definitely is a boolean value
    public static let Object   = Type(rawValue: 1 << 5)
    
    // It definitely is a function
    public static let Function = Type(rawValue: 1 << 6)
    
    // Combined Types
    public static let MaybeObject = Type([.Unknown, .Object])
    public static let MaybeFunction = Type([.Unknown, .Function])
}
