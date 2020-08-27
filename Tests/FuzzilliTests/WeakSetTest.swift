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

import XCTest
@testable import Fuzzilli

class WeakSetTests: XCTestCase {

    func testWeakSetInsert() {
        var weakSet = WeakSet<TypeExtension>()

        func makeTestTypeExtension() -> TypeExtension {
            return TypeExtension(properties: ["prop"], methods: [], signature: nil)!
        }

        func addLocalVariable(to deduplicationSet: inout WeakSet<TypeExtension>) {
            let localTypeExtension = makeTestTypeExtension()
            let insertionResult = deduplicationSet.insert(localTypeExtension)

            XCTAssert(deduplicationSet.contains(makeTestTypeExtension()))
            XCTAssert(insertionResult.inserted)
            XCTAssert(insertionResult.memberAfterInsert === localTypeExtension)
        }
        addLocalVariable(to: &weakSet)
        // Local function variable is no longer in set 
        XCTAssertFalse(weakSet.contains(makeTestTypeExtension()))

        let typeExtension1 = makeTestTypeExtension(), typeExtension2 = makeTestTypeExtension()

        let insertionResult1 = weakSet.insert(typeExtension1)
        XCTAssert(weakSet.contains(makeTestTypeExtension()))
        XCTAssert(insertionResult1.inserted)
        XCTAssert(insertionResult1.memberAfterInsert === typeExtension1)

        let insertionResult2 = weakSet.insert(typeExtension2)
        // No insertion happened
        XCTAssertFalse(insertionResult2.inserted)
        // Originally inserted element was returned
        XCTAssert(insertionResult2.memberAfterInsert === typeExtension1)

        // LocalVariable is still in set even it is nil
        XCTAssertEqual(weakSet.totalCount, 2)
        weakSet.removeNils()
        // We removed variables that got out of scope and therefore were nils
        XCTAssertEqual(weakSet.totalCount, 1)
    }

    func testWeakSetDisappearedElements() {
        var weakSet = WeakSet<TypeExtension>()

        func addLocalVariables(to deduplicationSet: inout WeakSet<TypeExtension>) {
            let localTypeExtension1 = TypeExtension(properties: ["prop1"], methods: [], signature: nil)!
            let localTypeExtension2 = TypeExtension(properties: ["prop2"], methods: [], signature: nil)!
            let insertionResult1 = deduplicationSet.insert(localTypeExtension1)

            XCTAssert(deduplicationSet.contains(localTypeExtension1))
            XCTAssert(insertionResult1.inserted)
            XCTAssert(insertionResult1.memberAfterInsert === localTypeExtension1)

            let insertionResult2 = deduplicationSet.insert(localTypeExtension2)

            XCTAssert(deduplicationSet.contains(localTypeExtension2))
            XCTAssert(insertionResult2.inserted)
            XCTAssert(insertionResult2.memberAfterInsert === localTypeExtension2)
        }

        addLocalVariables(to: &weakSet)

        // Both of the added local variables were destructed and are in set as nils
        XCTAssertEqual(weakSet.totalCount, 2)
        weakSet.removeNils()
        // Both of the added local variables were removed after clean up
        XCTAssertEqual(weakSet.totalCount, 0)
    }
}

extension WeakSetTests {
    static var allTests : [(String, (WeakSetTests) -> () throws -> Void)] {
        return [
            ("testWeakSetInsert", testWeakSetInsert),
            ("testWeakSetDisappearedElements", testWeakSetDisappearedElements),
        ]
    }
}
