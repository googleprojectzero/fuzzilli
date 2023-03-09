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

struct ScriptWriter {
    /// How many spaces to use per indention level.
    public let indent: String

    /// Whether to include comments in the output.
    /// Comment removal is best effort and will currently generally only remove comments if the comment is the only content of the line.
    public let stripComments: Bool

    /// The current script code.
    public private(set) var code = ""

    /// The current number of spaces to use for indention.
    private var currentIndention: String = ""

    /// Whether to include line numbers in the output.
    private let includeLineNumbers: Bool

    /// Current line, used when including line numbers in the output.
    public private(set) var currentLineNumber = 0

    public init (stripComments: Bool = false, includeLineNumbers: Bool = false, indent: Int = 4, initialIndentionLevel: Int = 0) {
        self.indent = String(repeating: " ", count: indent)
        self.currentIndention = String(repeating: " ", count: indent * initialIndentionLevel)
        self.stripComments = stripComments
        self.includeLineNumbers = includeLineNumbers
    }

    /// Emit one line of code.
    mutating func emit<S: StringProtocol>(_ line: S) {
        assert(!line.contains("\n"))
        currentLineNumber += 1
        if includeLineNumbers { code += "\(String(format: "%3i", currentLineNumber)). " }
        code += currentIndention + line + "\n"
    }

    /// Emit a comment.
    mutating func emitComment(_ comment: String) {
        guard !stripComments else { return }
        guard !comment.isEmpty else { return }

        for line in comment.split(separator: "\n", omittingEmptySubsequences: false) {
            emit("// " + line)
        }
    }

    /// Emit one or more lines of code.
    mutating func emitBlock(_ block: String) {
        guard !block.isEmpty else { return }
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if stripComments {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedLine.hasPrefix("//") || (trimmedLine.hasPrefix("/*") && trimmedLine.hasSuffix("*/")) {
                    continue
                }
            }
            emit(line)
        }
    }

    /// Increase the indention level of the following code by one.
    mutating func increaseIndentionLevel(by numLevels: Int = 1) {
        assert(numLevels > 0)
        for _ in 0..<numLevels {
            currentIndention += indent
        }
    }

    /// Decrease the indention level of the following code by one.
    mutating func decreaseIndentionLevel() {
        assert(currentIndention.count >= indent.count)
        currentIndention.removeLast(indent.count)
    }
}
