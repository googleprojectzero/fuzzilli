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

import Foundation

/// Comments that can be attached to a Program.
public struct ProgramComments {
    private static let headerIndex = Int32(-1)
    private static let footerIndex = Int32(-2)

    public enum CommentPosition {
        case header
        case footer
        case instruction(Int)

        fileprivate func toKey() -> Int32 {
            switch self {
            case .header:
                return ProgramComments.headerIndex
            case .footer:
                return ProgramComments.footerIndex
            case .instruction(let index):
                assert(index >= 0 && index <= UInt16.max)
                return Int32(index + 2)
            }
        }
    }

    private var comments: [Int32:String] = [:]

    public init() {}

    public var isEmpty: Bool {
        return comments.isEmpty
    }

    public func at(_ position: CommentPosition) -> String? {
        let key = position.toKey()
        return comments[key]
    }

    public mutating func add(_ content: String, at position: CommentPosition) {
        let key = position.toKey()

        var comment = ""
        if let currentContent = comments[key] {
            comment += currentContent + "\n"
        }
        comment += content

        comments[key] = comment
    }

    public mutating func removeAll() {
        comments.removeAll()
    }
}

extension ProgramComments: ProtobufConvertible {
    public typealias ProtobufType = [Int32: String]

    public func asProtobuf() -> ProtobufType {
        return comments
    }

    public init(from protobuf: ProtobufType) {
        self.comments = protobuf
    }
}
