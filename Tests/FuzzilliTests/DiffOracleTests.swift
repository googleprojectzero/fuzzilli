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

import Testing

@testable import Fuzzilli

struct DiffOracleTests {

    @Test
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
        #expect(DiffOracle.relate(dump, with: dump))
    }

    @Test
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

        #expect(DiffOracle.relate(optFull, with: unopt))
    }

    @Test
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
        #expect(DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(DiffOracle.relate(opt, with: unopt))
    }

    @Test
    func testNonMaterializedArgument() {
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
            a0:<non-materialized>
            a1:OtherVal

            """

        #expect(DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(!DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(!DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(!DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(!DiffOracle.relate(opt, with: unopt))
    }

    @Test
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

        #expect(DiffOracle.relate(opt, with: unopt))
    }

    @Test
    func testRegisterPersistence() {
        // Scenario:
        // 1. We set r0=A, r1=B (m:2) in the first frame.
        // 2. In the second frame we only use r0 (m:1). r1 is NOT in the frame, but should exist in backing store.
        // 3. Go back to having two registers (m:2) in the third frame. r1 should still be B (inherited from frame 0).

        let trace = """
            ---I
            b:10
            f:1
            n:0
            m:2
            r0:A
            r1:B

            ---M
            b:20
            m:1
            r0:A_Prime

            ---I
            b:30
            m:2
            r0:A_Prime

            """

        let expectedLastFrame = """
            ---I
            b:30
            f:1
            n:0
            m:2
            r0:A_Prime
            r1:B

            """
        #expect(DiffOracle.relate(expectedLastFrame, with: trace))
    }

    @Test
    func testMissingValueInjection() {
        // Scenario:
        // Frame 1: m=1, r0=A
        // Frame 2: m=3. The parser must grow the buffer. r1 and r2 should be "<missing>".

        let trace = """
            ---I
            b:10
            f:1
            n:0
            m:1
            r0:A

            ---I
            b:20
            m:3

            """

        // Explicitly check that r1 and r2 are missing in the expanded frame.
        let explicitMissing = """
            ---I
            b:20
            f:1
            n:0
            m:3
            r0:A
            r1:<missing>
            r2:<missing>

            """

        #expect(DiffOracle.relate(explicitMissing, with: trace))
    }

    @Test
    func testFarJumpInRegisterIndex() {
        // Scenario: A frame references a high register index directly without defining intermediate ones.
        // Buffer should auto-grow and fill with <missing>.

        let trace = """
            ---I
            b:10
            f:1
            n:0
            m:10
            r9:Z

            """

        // This frame should have r0...r8 as <missing> and r9 as Z.
        let expected = """
            ---I
            b:10
            f:1
            n:0
            m:10
            r0:<missing>
            r1:<missing>
            r2:<missing>
            r3:<missing>
            r4:<missing>
            r5:<missing>
            r6:<missing>
            r6:<missing>
            r7:<missing>
            r8:<missing>
            r9:Z

            """

        #expect(DiffOracle.relate(expected, with: trace))
    }

    @Test
    func testEmptyStringValueParsing() {
        let unopt = """
            ---I
            b:10
            f:1
            n:0
            m:6
            r0:ValA
            r5:

            """

        let opt = """
            ---I
            b:10
            f:1
            n:0
            m:6
            r0:ValA
            r5:

            """

        #expect(
            DiffOracle.relate(opt, with: unopt),
            "Should handle empty register values (e.g. 'r5:') without crashing")
    }
}
