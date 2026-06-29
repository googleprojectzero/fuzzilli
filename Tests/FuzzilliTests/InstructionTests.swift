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

@Suite struct InstructionTests {
    @Test func testDestructAndReassignTargetMapping() {
        // Pattern: ({ [computedKey]: target1 = default1, "foo": target2, ...target3 } = obj);
        // Inputs will be:
        // [0] obj
        // [1] computedKey (read)
        // [2] target1 (reassigned)
        // [3] default1 (read)
        // [4] target2 (reassigned)
        // [5] target3 (reassigned)
        let properties = [
            DestructuringPattern.ObjectProperty(
                key: .computed, target: .flatBinding, hasDefaultValue: true),
            DestructuringPattern.ObjectProperty(
                key: .string("foo"), target: .flatBinding, hasDefaultValue: false),
        ]
        let pattern = DestructuringPattern.ObjectPattern(
            properties: properties, hasRestElement: true)
        let destructPattern = DestructuringPattern.object(pattern)

        let op = DestructAndReassign(pattern: destructPattern, numInputs: 6)

        #expect(op.isTarget.count == 6)

        // input 0 is always the object, never a target
        #expect(!op.isTarget[0])

        // input 1 is the computed key -> NOT a target
        #expect(!op.isTarget[1])

        // input 2 is the flatBinding for computed key -> IS a target
        #expect(op.isTarget[2])

        // input 3 is the default value -> NOT a target
        #expect(!op.isTarget[3])

        // input 4 is the flatBinding for "foo" -> IS a target
        #expect(op.isTarget[4])

        // input 5 is the rest element -> IS a target
        #expect(op.isTarget[5])
    }
}
