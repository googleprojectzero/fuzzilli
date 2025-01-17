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

import XCTest
@testable import Fuzzilli

func testAndCompareSerialization(program: Program) {
    var proto1 = program.asProtobuf()
    var proto2 = program.asProtobuf()
    XCTAssertEqual(proto1, proto2)

    let data1 = try! proto1.serializedData()
    let data2 = try! proto2.serializedData()

    proto1 = try! Fuzzilli_Protobuf_Program(serializedBytes: data1)
    proto2 = try! Fuzzilli_Protobuf_Program(serializedBytes: data2)
    XCTAssertEqual(proto1, proto2)

    let copy1 = try! Program(from: proto1)
    let copy2 = try! Program(from: proto2)
    XCTAssertEqual(copy1, copy2)
    XCTAssertEqual(copy1, program)
    XCTAssertEqual(FuzzILLifter().lift(copy1), FuzzILLifter().lift(program))
}

class ProgramSerializationTests: XCTestCase {
    func testProtobufSerialization() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.build(n: 100, by: .generating)
            let program = b.finalize()
            testAndCompareSerialization(program: program)
        }
    }

    func testProtobufSerializationWithWasmModule() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.buildWasmModule { wasmModule in
                b.build(n: 50, by: .generating)
            }
            let program = b.finalize()
            testAndCompareSerialization(program: program)
        }
    }

    func testProtobufSerializationWithOperationCache() {
        let fuzzer = makeMockFuzzer()
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
        XCTAssert(program.code[0].op === program.code[2].op &&
                  program.code[0].op === program.code[4].op)
        XCTAssert(program.code[5].op === program.code[7].op &&
                  program.code[5].op === program.code[9].op)

        let encodingCache = OperationCache.forEncoding()
        let decodingCache = OperationCache.forDecoding()

        var proto = program.asProtobuf(opCache: encodingCache)
        let data = try! proto.serializedData()
        proto = try! Fuzzilli_Protobuf_Program(serializedBytes: data)
        let copy = try! Program(from: proto, opCache: decodingCache)

        XCTAssertEqual(program, copy)
        XCTAssert(copy.code[0].op !== program.code[0].op)
        XCTAssert(copy.code[0].op === copy.code[2].op &&
                  copy.code[0].op === copy.code[4].op)
        XCTAssert(copy.code[5].op === copy.code[7].op &&
                  copy.code[5].op === copy.code[9].op)
    }

    // As our equality operation is based on the protobuf representation, we do these tests here.
    func testProgramEquality() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
            b.buildPrefix()
            b.build(n: 100, by: .generating)
            let p1 = b.finalize()
            XCTAssertEqual(p1, p1)

            b.append(p1)
            let p2 = b.finalize()
            XCTAssertEqual(p1, p2)
        }
    }

    func testProgramInequality() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // A simple test with same instructions but different constants,
        b.loadFloat(13.37)
        b.loadInt(42)
        let p1 = b.finalize()

        b.loadFloat(13.37)
        b.loadInt(43)
        let p2 = b.finalize()

        XCTAssertNotEqual(p1, p2)

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
                XCTAssertNotEqual(p1, p2)
            }
        }

    }
}
