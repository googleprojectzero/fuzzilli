import XCTest
@testable import Fuzzilli

class AbstractInterpreterTests: XCTestCase {
    
    func testBasicTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let intVar = b.loadInt(42)
        let floatVar = b.loadFloat(13.37)
        let stringVar = b.loadString("foobar")
        let boolVar = b.loadBool(true)
        
        XCTAssertEqual(.integer, b.type(of: intVar))
        XCTAssertEqual(.float, b.type(of: floatVar))
        XCTAssertEqual(.string, b.type(of: stringVar))
        XCTAssertEqual(.boolean, b.type(of: boolVar))
        
        let sum = b.binary(intVar, stringVar, with: .Add)
        XCTAssertEqual(.primitive, b.type(of: sum))
        
    }
    
    func testObjectTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let intVar = b.loadInt(42)
        let obj = b.createObject(with: ["foo": intVar])
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
        
        b.storeProperty(intVar, as: "bar", on: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))
        
        b.storeProperty(intVar, as: "baz", on: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))
        
        b.deleteProperty("foo", of: obj)
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["bar", "baz"]))
        
        let method = b.defineFunction(withSignature: [] => .object()) { params in }
        XCTAssertEqual(b.type(of: method), .function([] => .object()))
        let obj2 = b.createObject(with: ["foo": intVar, "m1": method, "bar": intVar, "m2": method])
        XCTAssertEqual(b.type(of: obj2), .object(withProperties: ["foo", "bar"], withMethods: ["m1", "m2"]))
    }
    
    func testParameterTypeTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let signature = [.string, .object(), .opt(.number)] => .float
        let f = b.defineFunction(withSignature: signature) { params in
            XCTAssertEqual(b.type(of: params[0]), .string)
            XCTAssertEqual(b.type(of: params[1]), .object())
            XCTAssertEqual(b.type(of: params[2]), .number | .undefined)
        }
        XCTAssertEqual(b.type(of: f), .function(signature))
        
        let signature2 = [.integer, .anything...] => .float
        let f2 = b.defineFunction(withSignature: signature2) { params in
            XCTAssertEqual(b.type(of: params[0]), .integer)
            XCTAssertEqual(b.type(of: params[1]), .object())
        }
        XCTAssertEqual(b.type(of: f2), .function(signature2))
    }
    
    func testPhiTracking() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let intVar = b.loadInt(42)
        let phi = b.phi(intVar)
        XCTAssertEqual(b.type(of: phi), .phi(of: .integer))
        
        let floatVar = b.loadFloat(13.37)
        b.copy(floatVar, to: phi)
        XCTAssertEqual(b.type(of: phi), .phi(of: .float))
        
        let objVar = b.createObject(with: ["foo": intVar])
        b.copy(objVar, to: phi)
        XCTAssertEqual(b.type(of: phi), .phi(of: .object(withProperties: ["foo"])))
    }
    
    func testIfElseHandling() {
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        
        let intVar = b.loadInt(42)
        let phi = b.phi(intVar)
        let obj = b.createObject(with: ["foo": intVar])
        
        b.beginIf(intVar) {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.storeProperty(intVar, as: "bar", on: obj)
            b.storeProperty(intVar, as: "baz", on: obj)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "baz"]))
            
            let stringVar = b.loadString("foobar")
            b.copy(stringVar, to: phi)
            XCTAssertEqual(b.type(of: phi), .phi(of: .string))
        }
        b.beginElse {
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
            b.storeProperty(intVar, as: "bar", on: obj)
            b.storeProperty(intVar, as: "bla", on: obj)
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar", "bla"]))
            
            XCTAssertEqual(b.type(of: phi), .phi(of: .integer))
            let floatVar = b.loadFloat(13.37)
            b.copy(floatVar, to: phi)
        }
        b.endIf()
        
        XCTAssertEqual(b.type(of: intVar), .integer)
        XCTAssertEqual(b.type(of: phi), .phi(of: .string | .float))
        XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))
    }
    
    func testLoopAndFunctionHandling() {
        for i in 0..<6 {
            let fuzzer = makeMockFuzzer()
            let b = fuzzer.makeBuilder()
            
            let intVar1 = b.loadInt(0)
            let intVar2 = b.loadInt(100)
            let intVar3 = b.loadInt(42)
            let stringVar = b.loadString("foobar")
            let phi = b.phi(stringVar)
            let obj = b.createObject(with: ["foo": stringVar])
            
            func body() {
                XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
                b.storeProperty(intVar1, as: "bar", on: obj)
                
                
                XCTAssertEqual(b.type(of: phi), .phi(of: .string))
                let floatVar = b.loadFloat(13.37)
                b.copy(floatVar, to: phi)
                
                XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo", "bar"]))
                XCTAssertEqual(b.type(of: phi), .phi(of: .float))
            }
            
            // Select loop type
            switch i {
            case 0:
                b.forLoop(intVar1, .lessThan, intVar2, .Add, intVar3) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .primitive)
                    body()
                }
            case 1:
                b.whileLoop(intVar1, .lessThan, intVar2) {
                    body()
                }
            case 2:
                b.doWhileLoop(intVar1, .lessThan, intVar2) {
                    body()
                }
            case 3:
                b.forInLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .string)
                    body()
                }
            case 4:
                b.forOfLoop(obj) { loopVar in
                    XCTAssertEqual(b.type(of: loopVar), .unknown)
                    body()
                }
            case 5:
                b.defineFunction(withSignature: FunctionSignature.forUnknownFunction) { _ in
                    body()
                }
            default:
                assert(false)
            }
            
            XCTAssertEqual(b.type(of: intVar1), .integer)
            XCTAssertEqual(b.type(of: intVar2), .integer)
            XCTAssertEqual(b.type(of: intVar3), .integer)
            XCTAssertEqual(b.type(of: stringVar), .string)
            XCTAssertEqual(b.type(of: phi), .phi(of: .string | .float))
            XCTAssertEqual(b.type(of: obj), .object(withProperties: ["foo"]))
        }
    }
    
    func testBuiltinTypeInference() {
        let builtinAType = Type.integer
        let builtinBType = Type.object(ofGroup: "B", withProperties: ["foo", "bar"], withMethods: ["m1", "m2"])
        let builtinCType = Type.function([] => .number)
        
        let env = MockEnvironment(builtins: [
            "A": builtinAType,
            "B": builtinBType,
            "C": builtinCType
        ])
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        let va = b.loadBuiltin("A")
        let vb = b.loadBuiltin("B")
        let vc = b.loadBuiltin("C")
        
        XCTAssertEqual(b.type(of: va), builtinAType)
        XCTAssertEqual(b.type(of: vb), builtinBType)
        XCTAssertEqual(b.type(of: vc), builtinCType)
    }
    
    func testPropertyTypeInference() {
        let propFooType = Type.float
        let propBarType = Type.function([] => .unknown)
        let propBazType = Type.object(withProperties: ["a", "b", "c"])
        let propertiesByGroup: [String: [String: Type]] = [
            "B": [
                "foo": propFooType,
                "bar": propBarType
            ],
            "C": [
                "baz": propBazType,
            ]
        ]
        
        let builtins: [String: Type] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]
        
        let env = MockEnvironment(builtins: builtins, propertiesByGroup: propertiesByGroup)
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        // Test program-wide property inference
        b.setType(ofProperty: "a", to: .integer)
        b.setType(ofProperty: "b", to: .object(ofGroup: "B"))
        
        let aObj = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: aObj), .unknown)
        let bObj = b.loadBuiltin("B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))
        
        // Program-wide property types can always be inferred.
        var p = b.loadProperty("a", of: aObj)
        XCTAssertEqual(b.type(of: p), .integer)
        p = b.loadProperty("b", of: aObj)
        XCTAssertEqual(b.type(of: p), .object(ofGroup: "B"))
        p = b.loadProperty("b", of: bObj)
        XCTAssertEqual(b.type(of: p), .object(ofGroup: "B"))
        
        // Test inference of property types from the environment
        // .foo and .bar are both known for B objects
        p = b.loadProperty("foo", of: bObj)
        XCTAssertEqual(b.type(of: p), propFooType)
        p = b.loadProperty("bar", of: bObj)
        XCTAssertEqual(b.type(of: p), propBarType)
        
        // But .baz is only known on C objects
        p = b.loadProperty("baz", of: bObj)
        XCTAssertEqual(b.type(of: p), .unknown)
        
        let cObj = b.loadBuiltin("C")
        p = b.loadProperty("baz", of: cObj)
        XCTAssertEqual(b.type(of: p), propBazType)
        
        // No property types are known for A objects though.
        p = b.loadProperty("foo", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
        p = b.loadProperty("bar", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
        p = b.loadProperty("baz", of: aObj)
        XCTAssertEqual(b.type(of: p), .unknown)
    }
    
    func testMethodTypeInference() {
        let m1Signature = [] => .float
        let m2Signature = [.string] => .object(ofGroup: "X")
        let methodsByGroup: [String: [String: FunctionSignature]] = [
            "B": [
                "m1": m1Signature,
            ],
            "C": [
                "m2": m2Signature,
            ]
        ]
        
        let builtins: [String: Type] = [
            "B": .object(ofGroup: "B"),
            "C": .object(ofGroup: "C")
        ]
        
        let env = MockEnvironment(builtins: builtins, methodsByGroup: methodsByGroup)
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        // Test method signature inference of program-wide methods.
        b.setSignature(ofMethod: "m3", to: [] => .integer)
        
        let aObj = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: aObj), .unknown)
        let bObj = b.loadBuiltin("B")
        XCTAssertEqual(b.type(of: bObj), .object(ofGroup: "B"))
        
        var r = b.callMethod("m3", on: aObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .integer)
        r = b.callMethod("m3", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .integer)
        
        // Test inference of per-group methods.
        r = b.callMethod("m1", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .float)
        
        r = b.callMethod("m2", on: bObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .unknown)
        
        let cObj = b.loadBuiltin("C")
        r = b.callMethod("m2", on: cObj, withArgs: [])
        XCTAssertEqual(b.type(of: r), .object(ofGroup: "X"))
    }
    
    func testConstructorTypeInference() {
        let aConstructorType = Type.constructor([.anything...] => .object(ofGroup: "A"))
        let builtins: [String: Type] = [
            "A": aConstructorType,
        ]
        
        let env = MockEnvironment(builtins: builtins)
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
    
        let A = b.loadBuiltin("A")
        XCTAssertEqual(b.type(of: A), aConstructorType)
        
        // For a known constructor, the resulting type can be inferred
        let a = b.construct(A, withArgs: [])
        XCTAssertEqual(b.type(of: a), .object(ofGroup: "A"))
        
        // For an unknown constructor, the result will be .object()
        let C = b.loadBuiltin("C")
        let c = b.construct(C, withArgs: [])
        XCTAssertEqual(b.type(of: c), .object())
    }
    
    func testReturnTypeInference() {
        let aFunctionType = Type.function([.anything...] => .primitive)
        let builtins: [String: Type] = [
            "a": aFunctionType,
        ]
        
        let env = MockEnvironment(builtins: builtins)
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        let a = b.loadBuiltin("a")
        XCTAssertEqual(b.type(of: a), aFunctionType)
        
        // For a known function, the resulting type can be inferred
        var r = b.callFunction(a, withArgs: [])
        XCTAssertEqual(b.type(of: r), .primitive)
        
        // For an unknown function, the result will be .unknown
        let c = b.loadBuiltin("c")
        r = b.callFunction(c, withArgs: [])
        XCTAssertEqual(b.type(of: r), .unknown)
    }
    
    func testPrimitiveTypesOverride() {
        let env = MockEnvironment(builtins: [:])
        env.intType = .integer + .object(ofGroup: "Number")
        env.floatType = .float + .object(ofGroup: "Number")
        env.booleanType = .boolean + .object(ofGroup: "Number")
        env.stringType = .string + .object(ofGroup: "Number")
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        let iv = b.loadInt(42)
        let fv = b.loadFloat(13.37)
        let bv = b.loadBool(true)
        let sv = b.loadString("foobar")
        
        XCTAssertEqual(b.type(of: iv), env.intType)
        XCTAssertEqual(b.type(of: fv), env.floatType)
        XCTAssertEqual(b.type(of: bv), env.booleanType)
        XCTAssertEqual(b.type(of: sv), env.stringType)
    }
    
    func testArryCreation() {
        let env = MockEnvironment(builtins: [:])
        env.arrayType = .object(ofGroup: "Array")
        
        let fuzzer = makeMockFuzzer(environment: env)
        let b = fuzzer.makeBuilder()
        
        let a = b.createArray(with: [])
        XCTAssertEqual(b.type(of: a), .object(ofGroup: "Array"))
    }
}

extension AbstractInterpreterTests {
    static var allTests : [(String, (AbstractInterpreterTests) -> () throws -> Void)] {
        return [
            ("testBasicTypeTracking", testBasicTypeTracking),
            ("testObjectTypeTracking", testObjectTypeTracking),
            ("testParameterTypeTracking", testParameterTypeTracking),
            ("testPhiTracking", testPhiTracking),
            ("testPropertyTypeInference", testPropertyTypeInference),
            ("testMethodTypeInference", testMethodTypeInference),
            ("testConstructorTypeInference", testConstructorTypeInference),
            ("testReturnTypeInference", testReturnTypeInference),
            ("testBuiltinTypeInference", testBuiltinTypeInference),
        ]
    }
}
