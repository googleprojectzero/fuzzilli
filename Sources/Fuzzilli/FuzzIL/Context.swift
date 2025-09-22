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
public struct Context: OptionSet, Hashable, CaseIterable {
    public static var allCases: [Context] = [
        .javascript,
        .subroutine,
        .generatorFunction,
        .asyncFunction,
        .method,
        .classMethod,
        .loop,
        .objectLiteral,
        .classDefinition,
        .switchBlock,
        .switchCase,
        .wasm,
        .wasmFunction,
        .wasmTypeGroup,
        .empty,
    ]

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Default javascript context.
    public static let javascript        = Context(rawValue: 1 << 0)
    // Inside a subroutine (function, constructor, method, ...) definition.
    // This for example means that doing `return` or accessing `arguments` is allowed.
    public static let subroutine        = Context(rawValue: 1 << 1)
    // Inside a generator function definition.
    // This for example means that `yield` and `yield*` are allowed.
    public static let generatorFunction = Context(rawValue: 1 << 2)
    // Inside an async function definition.
    // This for example means that `await` is allowed.
    public static let asyncFunction     = Context(rawValue: 1 << 3)
    // Inside a method.
    // This for example means that access to `super` is allowed.
    public static let method            = Context(rawValue: 1 << 4)
    // Inside a class method.
    // This for example means that access to private properties is allowed.
    public static let classMethod       = Context(rawValue: 1 << 5)
    // Inside a loop.
    public static let loop              = Context(rawValue: 1 << 6)
    // Inside an object literal.
    public static let objectLiteral     = Context(rawValue: 1 << 7)
    // Inside a class definition.
    public static let classDefinition   = Context(rawValue: 1 << 8)
    // Inside a switch block.
    public static let switchBlock       = Context(rawValue: 1 << 9)
    // Inside a switch case.
    public static let switchCase        = Context(rawValue: 1 << 10)
    // Inside a wasm module
    public static let wasm              = Context(rawValue: 1 << 11)
    // Inside a function in a wasm module
    public static let wasmFunction      = Context(rawValue: 1 << 12)
    // Inside a wasm recursive type group definition.
    public static let wasmTypeGroup     = Context(rawValue: 1 << 13)

    public static let empty             = Context([])
    
    public var inWasm: Bool {
        self.contains(.wasm) || self.contains(.wasmFunction)
    }
}

extension Context: CustomStringConvertible {
    public var description: String {
        var strings: [String] = []
        if self.contains(.javascript) {
            strings.append(".javascript")
        }
        if self.contains(.subroutine) {
            strings.append(".subroutine")
        }
        if self.contains(.generatorFunction) {
            strings.append(".generatorFunction")
        }
        if self.contains(.asyncFunction) {
            strings.append(".asyncFunction")
        }
        if self.contains(.method) {
            strings.append(".method")
        }
        if self.contains(.classMethod) {
            strings.append(".classMethod")
        }
        if self.contains(.loop) {
            strings.append(".loop")
        }
        if self.contains(.objectLiteral) {
            strings.append(".objectLiteral")
        }
        if self.contains(.classDefinition) {
            strings.append(".classDefinition")
        }
        if self.contains(.switchBlock) {
            strings.append(".switchBlock")
        }
        if self.contains(.switchCase) {
            strings.append(".switchCase")
        }
        if self.contains(.wasm) {
            strings.append(".wasm")
        }
        if self.contains(.wasmFunction) {
            strings.append(".wasmFunction")
        }
        if self.contains(.wasmTypeGroup) {
            strings.append(".wasmTypeGroup")
        }
        return strings.joined(separator: " | ")
    }
}
