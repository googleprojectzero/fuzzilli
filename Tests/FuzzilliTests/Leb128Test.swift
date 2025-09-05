// Copyright 2024 Google LLC
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

class Leb128Tests: XCTestCase {
    func testUnsignedEncode() {
        let encoded = Leb128.unsignedEncode(624485);
        XCTAssertEqual(encoded.map({ String(format: "%02hhx", $0)}).joined(), "e58e26")
    }
}
