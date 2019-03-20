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
    static let indent = 4
    
    /// The current script code.
    var code = ""
    
    /// The current number of spaces to use for indention.
    private var indention: Int = 0
    
    /// Emits one line of code.
    mutating func emit<S: StringProtocol>(_ line: S) {
        assert(!line.contains("\n"))
        code += String(repeating: " ", count: indention) + line + "\n"
    }
    
    /// Emits an expression statement.
    mutating func emit(_ expr: Expression) {
        emit(expr.text + ";")
    }
    
    /// Emits one or more lines of code.
    mutating func emitBlock(_ block: String) {
        for line in block.split(separator: "\n") {
            emit(line)
        }
    }
    
    /// Increases the indention level by one.
    mutating func increaseIndentionLevel() {
        indention += ScriptWriter.indent
    }
    
    /// Decreases the indention level by one.
    mutating func decreaseIndentionLevel() {
        indention -= ScriptWriter.indent
        assert(indention >= 0)
    }
}
