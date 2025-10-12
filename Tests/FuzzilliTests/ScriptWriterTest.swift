// Copyright 2025 Google LLC
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

import XCTest
@testable import Fuzzilli

class ScriptWriterTest: XCTestCase {

    func testLineSplitting() {
        var w = ScriptWriter(indent: 2, initialIndentionLevel: 0, maxLineLength: 10)
        w.emit("My name is Ozymandias, king of kings. Look on my works, ye Mighty, and despair!")
        let expected = """
        My name is
        Ozymandias
        , king of
        kings.
        Look on my
        works, ye
        Mighty,
        and
        despair!

        """
        XCTAssertEqual(expected, w.code)
    }

    func testLineSplittingWithIndentation() {
        var w = ScriptWriter(indent: 2, initialIndentionLevel: 0, maxLineLength: 8)
        w.emit("My name is Ozymandias,")
        w.increaseIndentionLevel()
        w.emit("king of kings.")
        w.decreaseIndentionLevel()
        w.emit("Look on my works, ye Mighty,")
        w.increaseIndentionLevel()
        w.emit("and despair!")
        w.decreaseIndentionLevel()
        let expected = """
        My name
        is
        Ozymandi
        as,
          king
          of
          kings.
        Look on
        my
        works,
        ye
        Mighty,
          and
          despai
          r!

        """
        XCTAssertEqual(expected, w.code)
    }

    func testLineSplittingMultiSpace() {
      var w = ScriptWriter(indent: 2, initialIndentionLevel: 0, maxLineLength: 8)
      let str = (0...10).map {"\($0)\(String(repeating: " ", count: $0))"}.joined()
      w.emit(str)
      let expected = """
      01 2  3
      4    5
      6      7
      8
      9
      10

      """
      XCTAssertEqual(expected, w.code)
    }
}
