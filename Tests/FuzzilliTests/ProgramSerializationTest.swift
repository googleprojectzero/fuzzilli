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

class ProgramSerializationTests: XCTestCase {
    func testProtobufSerialization() {
        let fuzzer = makeMockFuzzer()

        for _ in 0..<100 {
            let b = fuzzer.makeBuilder()

            b.generate(n: 100)

            let program = b.finalize()

            var proto1 = program.asProtobuf()
            var proto2 = program.asProtobuf()
            XCTAssertEqual(proto1, proto2)
            
            let data1 = try! proto1.serializedData()
            let data2 = try! proto2.serializedData()
            XCTAssertEqual(data1, data2)
            
            proto1 = try! Fuzzilli_Protobuf_Program(serializedData: data1)
            proto2 = try! Fuzzilli_Protobuf_Program(serializedData: data2)
            XCTAssertEqual(proto1, proto2)
            
            let copy1 = try! Program(from: proto1)
            let copy2 = try! Program(from: proto2)
            XCTAssertEqual(copy1, copy2)
            XCTAssertEqual(copy1, program)
        }
    }
    
    func testProtobufSerializationWithOperationCache() {
         let fuzzer = makeMockFuzzer()
        
        let b = fuzzer.makeBuilder()
        
        let op = LoadInteger(value: 42)
        
        b.append(Instruction(operation: op, output: b.nextVariable()))
        b.append(Instruction(operation: op, output: b.nextVariable()))
        b.append(Instruction(operation: op, output: b.nextVariable()))
        
        let encodingCache = OperationCache.forEncoding()
        let decodingCache = OperationCache.forDecoding()
        
        let program = b.finalize()
        XCTAssert(program[0].operation === program[1].operation && program[0].operation === program[2].operation)
        
        var proto = program.asProtobuf(with: encodingCache)
        let data = try! proto.serializedData()
        proto = try! Fuzzilli_Protobuf_Program(serializedData: data)
        let copy = try! Program(from: proto, with: decodingCache)
        
        XCTAssertEqual(program, copy)
        XCTAssert(copy[0].operation !== program[0].operation)
        XCTAssert(copy[0].operation === copy[1].operation && copy[0].operation === copy[2].operation)
     }
    
    // As our equality operation is based on the protobuf representation, we do these tests here.
    func testProgramEquality() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<100 {
            b.generate(n: 100)
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
        
        // First, a simple test with same instructions but different constants,
        b.loadFloat(13.37)
        b.loadInt(42)
        let p1 = b.finalize()
        
        b.loadFloat(13.37)
        b.loadInt(43)
        let p2 = b.finalize()
        
        XCTAssertNotEqual(p1, p2)
        
        // Next, a test with the same instructions but different function signature,
        b.definePlainFunction(withSignature: [.integer] => .integer) {_ in }
        let p3 = b.finalize()
        
        b.definePlainFunction(withSignature: [.integer] => .float) {_ in }
        let p4 = b.finalize()
        
        XCTAssertNotEqual(p3, p4)
        
        // Finally, we can also guarantee that two programs are not equal if they lift to different code, so test that for randomly generated programs.
        for _ in 0..<1000 {
            b.generate(n: Int.random(in: 0..<10))
            let p1 = b.finalize()
            
            b.generate(n: Int.random(in: 0..<10))
            let p2 = b.finalize()
            
            let code1 = fuzzer.lifter.lift(p1)
            let code2 = fuzzer.lifter.lift(p2)
            if code1 != code2 {
                XCTAssertNotEqual(p1, p2)
            }
        }
        
    }
}

extension ProgramSerializationTests {
    static var allTests : [(String, (ProgramSerializationTests) -> () throws -> Void)] {
        return [
            ("testProtobufSerialization", testProtobufSerialization),
            ("testProtobufSerializationWithOperationCache", testProtobufSerializationWithOperationCache),
            ("testProgramEquality", testProgramEquality),
            ("testProgramInequality", testProgramInequality)
        ]
    }
}
