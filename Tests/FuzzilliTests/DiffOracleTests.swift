// Copyright 2026 Google LLC
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

final class DiffOracleTests: XCTestCase {

    func testSimpleIdentity() {
        let dump = """
        ---I
        b:10
        f:1
        x:100
        n:1
        m:1
        a0:10
        r0:20

        """
        // Should match itself
        XCTAssertTrue(DiffOracle.relate(dump, with: dump))
    }

    func testIncrementalParsingLogic() {
        // This tests if the second frame correctly inherits 'f:1', 'n:1', 'm:1' from the first frame
        // and only updates 'b' and 'x'.
        let unopt = """
        ---I
        b:10
        f:1
        x:100
        n:1
        m:1
        a0:10
        r0:20

        ---I
        b:20
        x:200

        """

        // Even if we explicitly write out the full state in the "Opt" input,
        // it should match the incremental "Unopt" input if parsing works correctly.
        let optFull = """
        ---I
        b:10
        f:1
        x:100
        n:1
        m:1
        a0:10
        r0:20

        ---I
        b:20
        f:1
        x:200
        n:1
        m:1
        a0:10
        r0:20

        """

        XCTAssertTrue(DiffOracle.relate(optFull, with: unopt))
    }


    func testOptimizedOutAccumulator() {
        let unopt = """
        ---I
        b:10
        f:1
        x:SecretValue
        n:0
        m:0

        """

        let opt = """
        ---I
        b:10
        f:1
        x:<optimized_out>
        n:0
        m:0

        """

        // <optimized_out> in Opt should match distinct value in Unopt
        XCTAssertTrue(DiffOracle.relate(opt, with: unopt))
    }

    func testOptimizedOutArgument() {
        let unopt = """
        ---I
        b:10
        f:1
        x:0
        n:2
        m:0
        a0:RealVal
        a1:OtherVal

        """

        let opt = """
        ---I
        b:10
        f:1
        x:0
        n:2
        m:0
        a0:<optimized_out>
        a1:OtherVal

        """

        XCTAssertTrue(DiffOracle.relate(opt, with: unopt))
    }

    func testArgumentMismatch() {
        let unopt = """
        ---I
        b:10
        f:1
        x:0
        n:1
        m:0
        a0:ValueA

        """

        let opt = """
        ---I
        b:10
        f:1
        x:0
        n:1
        m:0
        a0:ValueB

        """

        XCTAssertFalse(DiffOracle.relate(opt, with: unopt))
    }

    func testRegisterMismatch() {
        let unopt = """
        ---I
        b:10
        f:1
        x:0
        n:0
        m:1
        r0:ValueA

        """

        let opt = """
        ---I
        b:10
        f:1
        x:0
        n:0
        m:1
        r0:ValueB

        """

        XCTAssertFalse(DiffOracle.relate(opt, with: unopt))
    }


    func testSkipsUnoptimizedFrames() {
        // Scenario: Unoptimized dump has extra intermediate steps (frames at offset 20 and 30).
        // Optimized dump only snapshots offset 10 and 40. This is valid.
        let unopt = """
        ---I
        b:10
        f:1
        n:0
        m:0

        ---I
        b:20

        ---I
        b:30

        ---I
        b:40

        """

        let opt = """
        ---I
        b:10
        f:1
        n:0
        m:0

        ---I
        b:40

        """

        XCTAssertTrue(DiffOracle.relate(opt, with: unopt))
    }

    func testOrderMatters() {
        // Scenario: Opt dump tries to match b:40 BEFORE b:10. This is invalid.
        // The relatation consumes the unopt stream forward.
        let unopt = """
        ---I
        b:10
        f:1
        n:0
        m:0

        ---I
        b:40

        """

        let opt = """
        ---I
        b:40
        f:1
        n:0
        m:0

        ---I
        b:10

        """

        XCTAssertFalse(DiffOracle.relate(opt, with: unopt))
    }

    func testBytecodeOffsetMismatch() {
        let unopt = """
        ---I
        b:10
        f:1
        n:0
        m:0

        """

        let opt = """
        ---I
        b:99
        f:1
        n:0
        m:0

        """

        XCTAssertFalse(DiffOracle.relate(opt, with: unopt))
    }

    func testArrayResizeUpdateValues() {
        // Tests the logic in `updateValues` where it handles missing or excess values
        // when n counts change between frames.

        let unopt = """
        ---I
        b:10
        f:1
        n:1
        m:0
        a0:A

        ---I
        b:20
        n:2
        a1:B

        """

        // This opt dump expects a0 to still be A (carried over) and a1 to be B.
        let opt = """
        ---M
        b:10
        f:1
        n:1
        m:0
        a0:A

        ---M
        b:20
        n:2
        a0:A
        a1:B

        """

        XCTAssertTrue(DiffOracle.relate(opt, with: unopt))
    }
}
