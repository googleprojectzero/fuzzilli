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

import Foundation
import Testing

@testable import Fuzzilli

@Suite struct ProgramCoverageEvaluatorTests {
    private static let numEdges: UInt32 = 64
    private static let bitmapSize: UInt32 = 8
    private static let headerSize = 12

    /// Creates a serialized coverage state in the format of ProgramCoverageEvaluator.exportState().
    private func makeCoverageState(foundEdges: UInt32, virginBits: [UInt8], crashBits: [UInt8])
        -> Data
    {
        var data = Data()
        var numEdges = Self.numEdges
        var bitmapSize = Self.bitmapSize
        var foundEdges = foundEdges
        data.append(Data(bytes: &numEdges, count: 4))
        data.append(Data(bytes: &bitmapSize, count: 4))
        data.append(Data(bytes: &foundEdges, count: 4))
        data.append(contentsOf: virginBits)
        data.append(contentsOf: crashBits)
        return data
    }

    /// Returns a bitmap in which only the given edges are covered (i.e. their bits are cleared).
    /// As in libcoverage, edge 0 is a dummy edge whose bit is always cleared in the virgin bits.
    private func makeBitmap(coveredEdges: [Int], isVirginBitmap: Bool = true) -> [UInt8] {
        var bitmap = [UInt8](repeating: 0xFF, count: Int(Self.bitmapSize))
        for edge in (isVirginBitmap ? [0] : []) + coveredEdges {
            bitmap[edge / 8] &= ~(1 << UInt8(edge % 8))
        }
        return bitmap
    }

    @Test func testCoverageStateMerging() {
        let state1 = makeCoverageState(
            foundEdges: 1, virginBits: makeBitmap(coveredEdges: [1]),
            crashBits: makeBitmap(coveredEdges: [], isVirginBitmap: false))
        let state2 = makeCoverageState(
            foundEdges: 2, virginBits: makeBitmap(coveredEdges: [2, 9]),
            crashBits: makeBitmap(coveredEdges: [3], isVirginBitmap: false))

        let merged = ProgramCoverageEvaluator.mergeCoverageStates([state1, state2])
        #expect(merged.count == state1.count)

        let mergedNumEdges = merged.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
        let mergedBitmapSize = merged.withUnsafeBytes {
            $0.load(fromByteOffset: 4, as: UInt32.self)
        }
        let mergedFoundEdges = merged.withUnsafeBytes {
            $0.load(fromByteOffset: 8, as: UInt32.self)
        }
        #expect(mergedNumEdges == Self.numEdges)
        #expect(mergedBitmapSize == Self.bitmapSize)
        // The union of the covered edges, excluding the dummy edge 0.
        #expect(mergedFoundEdges == 3)

        let headerSize = Self.headerSize
        let bitmapSize = Int(Self.bitmapSize)
        let mergedVirginBits = [UInt8](merged[headerSize..<(headerSize + bitmapSize)])
        let mergedCrashBits = [UInt8](merged[(headerSize + bitmapSize)...])
        #expect(mergedVirginBits == makeBitmap(coveredEdges: [1, 2, 9]))
        #expect(mergedCrashBits == makeBitmap(coveredEdges: [3], isVirginBitmap: false))
    }

    @Test func testMergingSingleCoverageState() {
        let state = makeCoverageState(
            foundEdges: 1, virginBits: makeBitmap(coveredEdges: [5]),
            crashBits: makeBitmap(coveredEdges: [], isVirginBitmap: false))
        #expect(ProgramCoverageEvaluator.mergeCoverageStates([state]) == state)
    }

    @Test func testMergingEqualCoverageStates() {
        // The header's found edges must match the covered edges, as the merge recomputes them.
        let state = makeCoverageState(
            foundEdges: 3, virginBits: makeBitmap(coveredEdges: [1, 9, 17]),
            crashBits: makeBitmap(coveredEdges: [3], isVirginBitmap: false))
        #expect(ProgramCoverageEvaluator.mergeCoverageStates([state, state]) == state)
    }

    @Test func testMergingUnalignedCoverageStates() {
        // Serialized states can be slices of a larger buffer (e.g. of a decoded protobuf message), so
        // they don't necessarily start at index zero or at an aligned address.
        let state = makeCoverageState(
            foundEdges: 1, virginBits: makeBitmap(coveredEdges: [5]),
            crashBits: makeBitmap(coveredEdges: [], isVirginBitmap: false))
        let buffer = Data([0xAB]) + state
        let slice = buffer[1...]
        #expect(slice.startIndex == 1)
        #expect(ProgramCoverageEvaluator.mergeCoverageStates([slice, state]) == state)
    }

    @Test func testSerializedStateHeader() {
        typealias Header = ProgramCoverageEvaluator.SerializedStateHeader
        let header = Header(numEdges: Self.numEdges, bitmapSize: Self.bitmapSize, foundEdges: 3)
        let serialized = header.serialized()
        #expect(serialized.count == Header.size)
        #expect(Header(of: serialized) == header)
        #expect(header.stateSize == Header.size + 2 * Int(Self.bitmapSize))

        // The header layout matches the one of the states built by makeCoverageState().
        let state = makeCoverageState(
            foundEdges: 3, virginBits: makeBitmap(coveredEdges: [1, 2, 3]),
            crashBits: makeBitmap(coveredEdges: [], isVirginBitmap: false))
        #expect(Header(of: state) == header)
        #expect(state.prefix(Header.size) == serialized)

        #expect(Header(of: Data(count: Header.size - 1)) == nil)
    }

    @Test func testMergingNoCoverageStates() {
        #expect(ProgramCoverageEvaluator.mergeCoverageStates([]).isEmpty)
    }
}
