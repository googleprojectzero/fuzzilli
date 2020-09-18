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

        for _ in 0..<10 {
            let b = fuzzer.makeBuilder()

            b.generate(n: 100)

            let program = b.finalize()

            var proto1 = program.asProtobuf()
            var proto2 = program.asProtobuf()
            XCTAssertEqual(proto1, proto2)
            
            let data1 = try! proto1.serializedData()
            let data2 = try! proto2.serializedData()
            
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
        proto = try! Fuzzilli_Protobuf_Program(serializedData: data)
        let copy = try! Program(from: proto, opCache: decodingCache)

        XCTAssertEqual(program, copy)
        XCTAssert(copy.code[0].op !== program.code[0].op)
        XCTAssert(copy.code[0].op === copy.code[2].op &&
                  copy.code[0].op === copy.code[4].op)
        XCTAssert(copy.code[5].op === copy.code[7].op &&
                  copy.code[5].op === copy.code[9].op)
    }

    func testProtobufSerializationWithTypeCache() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        // Dummy code so the variables all exists and we can assign types to them
        let Magic = b.loadBuiltin("Magic")
        b.callMethod("makeObject", on: Magic, withArgs: [])
        b.callMethod("makeObject", on: Magic, withArgs: [])
        b.callMethod("makeObject2", on: Magic, withArgs: [])
        b.callMethod("makeObject2", on: Magic, withArgs: [])
        b.callMethod("makeInt", on: Magic, withArgs: [])
        b.callMethod("makeFunc", on: Magic, withArgs: [])
        b.callMethod("makeFunc", on: Magic, withArgs: [])
        b.callMethod("makeObject", on: Magic, withArgs: [])
        b.callMethod("makeObject2", on: Magic, withArgs: [])
        b.callMethod("makeNumberObject", on: Magic, withArgs: [])
        let program = b.finalize()

        let objType = Type.object(ofGroup: "foobar", withProperties: ["a", "b", "c"], withMethods: ["f", "g", "h"])
        let objType2 = Type.object(ofGroup: "bar", withProperties: ["x", "y", "z"])
        let objType3 = Type.object(ofGroup: "baz")

        // Make a type with the same TypeExtension as objType but a different base type
        let mergedType = objType + .integer
        XCTAssertNotEqual(objType, mergedType)
        var uniqueExtensions = Set<TypeExtension>()
        let _ = objType.uniquified(with: &uniqueExtensions)
        let numObjType = mergedType.uniquified(with: &uniqueExtensions)
        XCTAssertEqual(numObjType, mergedType)
        // We should only have one type extension in the set
        XCTAssert(uniqueExtensions.count == 1)

        let signature = [.integer, .float] => objType

        let types = VariableMap<Type>([
            0: .object(),
            1: objType,
            2: objType,
            3: objType2,
            4: objType3,
            5: .integer,
            6: .function(signature),
            7: .function(signature),
            8: objType,
            9: objType2,
            10: numObjType
        ])
        program.types = ProgramTypes(from: types, in: program, quality: .runtime)

        let encodingCache = TypeCache.forEncoding()
        let decodingCache = TypeCache.forDecoding()

        var proto = program.asProtobuf(typeCache: encodingCache)
        let data = try! proto.serializedData()
        proto = try! Fuzzilli_Protobuf_Program(serializedData: data)
        let copy = try! Program(from: proto, typeCache: decodingCache)

        XCTAssertEqual(program, copy)
        XCTAssert(program.types == copy.types)
    }
    
    // As our equality operation is based on the protobuf representation, we do these tests here.
    func testProgramEquality() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()

        for _ in 0..<10 {
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
        for _ in 0..<100 {
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
            ("testProtobufSerializationWithTypeCache", testProtobufSerializationWithTypeCache),
            ("testProgramEquality", testProgramEquality),
            ("testProgramInequality", testProgramInequality)
        ]
    }
}
