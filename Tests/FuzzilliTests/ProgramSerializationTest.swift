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

import Testing

@testable import Fuzzilli

func testAndCompareSerialization(program: Program) {
    let data1 = try! program.asProtobuf().serializedData()
    let data2 = try! program.asProtobuf().serializedData()
    // We need to compare on a binary level as the Protobuf datastructure can contain floats for i.e. LoadFloat and Constf64 instructions. If those contain a NaN, they won't be equal to one another although we only care about their binary representation being equal.
    #expect(data1 == data2)

    let proto1 = try! Fuzzilli_Protobuf_Program(serializedBytes: data1)
    let proto2 = try! Fuzzilli_Protobuf_Program(serializedBytes: data2)

    let copy1 = try! Program(from: proto1)
    let copy2 = try! Program(from: proto2)
    #expect(copy1 == copy2)
    #expect(copy1 == program)
    #expect(FuzzILLifter().lift(copy1) == FuzzILLifter().lift(program))
}

@Suite struct ProgramSerializationTests {
    @Test func testProtobufSerialization() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            for _ in 0..<10 {
                b.buildPrefix()
                b.build(n: 100, by: .generating)
                let program = b.finalize()
                testAndCompareSerialization(program: program)
            }
        }
    }

    @Test func testProtobufSerializationWithWasmModule() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            for _ in 0..<10 {
                b.buildPrefix()
                b.wasmDefineTypeGroup {
                    b.build(n: 20, by: .generating)
                }
                b.buildWasmModule { wasmModule in
                    b.build(n: 50, by: .generating)
                }
                let program = b.finalize()
                testAndCompareSerialization(program: program)
            }
        }
    }

    @Test func testProtobufSerializationWithOperationCache() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            let op = LoadInteger(value: 42)

            b.append(Instruction(op, output: b.nextVariable()))
            b.loadString("foobar")
            b.append(Instruction(op, output: b.nextVariable()))
            b.loadFloat(13.37)
            b.append(Instruction(op, output: b.nextVariable()))

            let complexOp = BinaryOperation(.Add)
            b.append(Instruction(complexOp, output: b.nextVariable(), inputs: [v(0), v(1)]))
            b.loadNull()
            b.append(Instruction(complexOp, output: b.nextVariable(), inputs: [v(1), v(2)]))
            b.loadUndefined()
            b.append(Instruction(complexOp, output: b.nextVariable(), inputs: [v(2), v(3)]))

            let program = b.finalize()
            #expect(
                program.code[0].op === program.code[2].op
                    && program.code[0].op === program.code[4].op)
            #expect(
                program.code[5].op === program.code[7].op
                    && program.code[5].op === program.code[9].op)

            let encodingCache = OperationCache.forEncoding()
            let decodingCache = OperationCache.forDecoding()

            var proto = program.asProtobuf(opCache: encodingCache)
            let data = try! proto.serializedData()
            proto = try! Fuzzilli_Protobuf_Program(serializedBytes: data)
            let copy = try! Program(from: proto, opCache: decodingCache)

            #expect(program == copy)
            #expect(copy.code[0].op !== program.code[0].op)
            #expect(copy.code[0].op === copy.code[2].op && copy.code[0].op === copy.code[4].op)
            #expect(copy.code[5].op === copy.code[7].op && copy.code[5].op === copy.code[9].op)
        }
    }

    // As our equality operation is based on the protobuf representation, we do these tests here.
    @Test func testProgramEquality() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            for _ in 0..<10 {
                b.buildPrefix()
                b.build(n: 100, by: .generating)
                let p1 = b.finalize()
                #expect(p1 == p1)

                b.append(p1)
                let p2 = b.finalize()
                #expect(p1 == p2)
            }
        }
    }

    @Test func testProgramInequality() {
        let fuzzer = makeMockFuzzer()
        fuzzer.sync {
            let b = fuzzer.makeBuilder()

            // A simple test with same instructions but different constants,
            b.loadFloat(13.37)
            b.loadInt(42)
            let p1 = b.finalize()

            b.loadFloat(13.37)
            b.loadInt(43)
            let p2 = b.finalize()

            #expect(p1 != p2)

            // A general test with random instruction: we can guarantee that two programs are not equal if they lift to different code, so test that for randomly generated programs.
            for _ in 0..<100 {
                b.buildPrefix()
                b.build(n: Int.random(in: 1...10), by: .generating)
                let p1 = b.finalize()

                b.buildPrefix()
                b.build(n: Int.random(in: 1...10), by: .generating)
                let p2 = b.finalize()

                let code1 = fuzzer.lifter.lift(p1)
                let code2 = fuzzer.lifter.lift(p2)
                if code1 != code2 {
                    #expect(p1 != p2)
                }
            }
        }
    }

    @Test func testProtobufVersioning() throws {
        let fuzzer = makeMockFuzzer()
        try fuzzer.sync {
            let b = fuzzer.makeBuilder()
            b.loadInt(42)
            let program = b.finalize()

            var proto = program.asProtobuf()
            #expect(proto.version == Program.protobufVersion)

            // Deserializing a protobuf with the correct version number should pass.
            #expect(throws: Never.self) {
                try Program(from: proto)
            }

            // Deserializing a protobuf with version 0 (e.g., the version field does not exist, as in legacy protobufs) should fail.
            proto.version = 0
            let error1 = try #require(throws: Error.self) {
                _ = try Program(from: proto)
            }
            if case .programDecodingError(let msg) = error1 as? FuzzilliError {
                #expect(msg.contains("Incompatible protobuf version"))
            } else {
                Issue.record("Unexpected error type: \(error1)")
            }

            // Deserializing a protobuf with an incompatible version number should fail.
            proto.version = Program.protobufVersion + 1
            let error2 = try #require(throws: Error.self) {
                _ = try Program(from: proto)
            }
            if case .programDecodingError(let msg) = error2 as? FuzzilliError {
                #expect(msg.contains("Incompatible protobuf version"))
            } else {
                Issue.record("Unexpected error type: \(error2)")
            }
        }
    }
}
