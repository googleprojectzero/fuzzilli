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
    public let indent: Int

    /// Special characters we cannot delete whitespaces around
    /// They can be part of variable name (_, $) or script can subtract negative number
    private static let specialCharacters: [Character] = ["_", "$", "-"]
    
    /// The current script code.
    var code = ""
    
    /// The current number of spaces to use for indention.
    private var currentIndention: Int = 0

    private let minifyOutput: Bool

    public init (minifyOutput: Bool = false, indent: Int = 4) {
        self.minifyOutput = minifyOutput
        self.indent = minifyOutput ? 0 : indent
    }

    /// If minify mode is turned on, remove whitespaces around characters
    /// which cannot occur in JS variable names
    mutating func emitFormattedLine<S: StringProtocol>(_ line: S) {
        if !self.minifyOutput {
            code += String(repeating: " ", count: currentIndention) + line + "\n"
            return
        }

        func canRemoveWhitespaces(_ c: Character) -> Bool {
            return !c.isLetter && !c.isNumber && !ScriptWriter.specialCharacters.contains(c)
        }

        for c in line {
            if c == " " && !code.isEmpty && canRemoveWhitespaces(code.last!) {
                continue
            }

            if canRemoveWhitespaces(c) && code.last == " " {
                code.removeLast()
            }

            code.append(c)
        }
    }
    
    /// Emit one line of code.
    mutating func emit<S: StringProtocol>(_ line: S) {
        Assert(!line.contains("\n"))
        emitFormattedLine(line)
    }
    
    /// Emit an expression statement.
    mutating func emit(_ expr: Expression) {
        emit(expr.text + ";")
    }
    
    /// Emit a comment.
    mutating func emitComment(_ comment: String) {
        guard !self.minifyOutput else { return }

        for line in comment.split(separator: "\n") {
            emit("// " + line)
        }
    }
    
    /// Emit one or more lines of code.
    mutating func emitBlock(_ block: String) {
        for line in block.split(separator: "\n") {
            emit(line)
        }
    }
    
    /// Increase the indention level of the following code by one.
    mutating func increaseIndentionLevel() {
        currentIndention += self.indent
    }
    
    /// Decrease the indention level of the following code by one.
    mutating func decreaseIndentionLevel() {
        currentIndention -= self.indent
        Assert(currentIndention >= 0)
    }
}
