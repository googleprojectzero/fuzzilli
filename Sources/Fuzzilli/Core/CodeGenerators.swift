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

//
// Code generators.
//
// These insert one or more instructions into a program.
//
public typealias CodeGenerator = (_ b: ProgramBuilder) -> ()

public func IntegerLiteralGenerator(_ b: ProgramBuilder) {
    b.loadInt(b.genInt())
}

public func FloatLiteralGenerator(_ b: ProgramBuilder) {
    b.loadFloat(b.genFloat())
}

public func StringLiteralGenerator(_ b: ProgramBuilder) {
    b.loadString(b.genString())
}

public func BooleanLiteralGenerator(_ b: ProgramBuilder) {
    b.loadBool(Bool.random())
}

public func UndefinedValueGenerator(_ b: ProgramBuilder) {
    b.loadUndefined()
}

public func NullValueGenerator(_ b: ProgramBuilder) {
    b.loadNull()
}

public func ObjectLiteralGenerator(_ b: ProgramBuilder) {
    var initialProperties = [String: Variable]()
    for _ in 0..<Int.random(in: 0..<10) {
        initialProperties[b.genPropertyName()] = b.randVar()
    }
    b.createObject(with: initialProperties)
}

public func ArrayLiteralGenerator(_ b: ProgramBuilder) {
    var initialValues = [Variable]()
    for _ in 0..<Int.random(in: 0..<5) {
        initialValues.append(b.randVar())
    }
    b.createArray(with: initialValues)
}

public func ObjectLiteralWithSpreadGenerator(_ b: ProgramBuilder) {
    var initialProperties = [String: Variable]()
    var spreads = [Variable]()
    for _ in 0..<Int.random(in: 0..<10) {
        withProbability(0.5, do: {
            initialProperties[b.genPropertyName()] = b.randVar()
        }, else: {
            spreads.append(b.randVar())
        })
    }
    b.createObject(with: initialProperties, andSpreading: spreads)
}

public func ArrayLiteralWithSpreadGenerator(_ b: ProgramBuilder) {
    var initialValues = [Variable]()
    for _ in 0..<Int.random(in: 0..<5) {
        initialValues.append(b.randVar())
    }
    
    // Pick some random inputs to spread.
    let spreads = initialValues.map({ _ in Bool.random() })
    
    b.createArray(with: initialValues, spreading: spreads)
}

public func BuiltinGenerator(_ b: ProgramBuilder) {
    b.loadBuiltin(b.genBuiltinName())
}

public func FunctionDefinitionGenerator(_ b: ProgramBuilder) {
    // For functions, we always generate one random instruction and one return instruction as function body.
    // This ensures that generating one random instruction does not accidentially generate multiple instructions
    // (which increases the likelyhood of runtime exceptions), but also generates somewhat useful functions.
    b.defineFunction(numParameters: Int.random(in: 2...5), isJSStrictMode: probability(0.2), hasRestParam: probability(0.2)) { _ in
        b.generate()
        b.doReturn(value: b.randVar())
    }
}

public func PropertyRetrievalGenerator(_ b: ProgramBuilder) {
    let object = b.randVar(ofType: .MaybeObject)
    let propertyName = b.genPropertyName()
    
    b.loadProperty(propertyName, of: object)
}

public func PropertyAssignmentGenerator(_ b: ProgramBuilder) {
    let object = b.randVar(ofType: .MaybeObject)
    
    let propertyName = b.genPropertyName()
    let value = b.randVar()
    b.storeProperty(value, as: propertyName, on: object)
}

public func PropertyRemovalGenerator(_ b: ProgramBuilder) {
    let object = b.randVar(ofType: .MaybeObject)
    let propertyName = b.genPropertyName()
    
    b.deleteProperty(propertyName, of: object)
}

public func ElementRetrievalGenerator(_ b: ProgramBuilder) {
    let array = b.randVar(ofType: .MaybeObject)
    let index = b.genIndex()
    b.loadElement(index, of: array)
}

public func ElementAssignmentGenerator(_ b: ProgramBuilder) {
    let array = b.randVar(ofType: .MaybeObject)
    let index = b.genIndex()
    let value = b.randVar()
    b.storeElement(value, at: index, of: array)
}

public func ElementRemovalGenerator(_ b: ProgramBuilder) {
    let array = b.randVar(ofType: .MaybeObject)
    let index = b.genIndex()
    b.deleteElement(index, of: array)
}

public func ComputedPropertyAssignmentGenerator(_ b: ProgramBuilder) {
    let object = b.randVar(ofType: .MaybeObject)
    
    let propertyName = b.randVar()
    let value = b.randVar()
    b.storeComputedProperty(value, as: propertyName, on: object)
}

public func ComputedPropertyRetrievalGenerator(_ b: ProgramBuilder) {
    let object = b.randVar()
    let propertyName = b.randVar()
    
    b.loadComputedProperty(propertyName, of: object)
}

public func ComputedPropertyRemovalGenerator(_ b: ProgramBuilder) {
    let object = b.randVar()
    let propertyName = b.randVar()
    
    b.deleteComputedProperty(propertyName, of: object)
}

public func TypeTestGenerator(_ b: ProgramBuilder) {
    let v = b.randVar()
    let type = b.doTypeof(v)
    
    // Also generate a comparison here, since that's probably the only interesting thing you can do with the result.
    let rhs = b.loadString(chooseUniform(from: JavaScriptEnvironment.jsTypeNames))
    b.compare(type, rhs, with: .strictEqual)
}

public func InstanceOfGenerator(_ b: ProgramBuilder) {
    let lhs = b.randVar()
    let rhs = b.randVar()
    b.doInstanceOf(lhs, rhs)
}

public func InGenerator(_ b: ProgramBuilder) {
    let lhs = b.randVar()
    let rhs = b.randVar()
    b.doIn(lhs, rhs)
}

public func generateCallArguments(_ b: ProgramBuilder, n: Int) -> [Variable] {
    var arguments = [Variable]()
    for _ in 0..<n {
        arguments.append(b.randVar())
    }
    return arguments
}

public func MethodCallGenerator(_ b: ProgramBuilder) {
    let object = b.randVar(ofType: .MaybeObject)
    let methodName = b.genMethodName()
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))
    
    b.callMethod(methodName, on: object, withArgs: arguments)
}

public func FunctionCallGenerator(_ b: ProgramBuilder) {
    let function = b.randVar(ofType: .Function)
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))
    
    b.callFunction(function, withArgs: arguments)
}
public func FunctionReturnGenerator(_ b: ProgramBuilder) {
    if b.isInFunction {
        b.doReturn(value: b.randVar())
    }
}

public func ConstructorCallGenerator(_ b: ProgramBuilder) {
    // Want to also call builtin constructors here
    let constructor = b.randVar(ofType: .MaybeFunction)
    let arguments = generateCallArguments(b, n: Int.random(in: 2...5))
    
    b.construct(constructor, withArgs: arguments)
}

public func FunctionCallWithSpreadGenerator(_ b: ProgramBuilder) {
    let function = b.randVar(ofType: .Function)
    let arguments = generateCallArguments(b, n: Int.random(in: 1...5))
    
    // Pick some random arguments to spread.
    let spreads = arguments.map({ _ in Bool.random() })
    
    b.callFunction(function, withArgs: arguments, spreading: spreads)
}

public func UnaryOperationGenerator(_ b: ProgramBuilder) {
    let input = b.randVar()
    b.unary(chooseUniform(from: allUnaryOperators), input)
}

public func BinaryOperationGenerator(_ b: ProgramBuilder) {
    let lhs = b.randVar()
    let rhs = b.randVar()
    b.binary(lhs, rhs, with: chooseUniform(from: allBinaryOperators))
}

public func PhiGenerator(_ b: ProgramBuilder) {
    b.phi(b.randVar())
}

public func ReassignmentGenerator(_ b: ProgramBuilder) {
    if let output = b.randPhi() {
        let input = b.randVar()
        b.copy(input, to: output)
    }
}

public func ComparisonGenerator(_ b: ProgramBuilder) {
    let lhs = b.randVar()
    let rhs = b.randVar()
    b.compare(lhs, rhs, with: chooseUniform(from: allComparators))
}

public func IfStatementGenerator(_ b: ProgramBuilder) {
    // Optionally create some kind of comparison as well
    withProbability(0.5) {
        b.run(chooseUniform(from: [ComparisonGenerator, ComparisonGenerator, TypeTestGenerator, InstanceOfGenerator]))
    }
    
    let cond = b.randVar(ofType: .Boolean)
    let phi = b.phi(b.randVar())
    b.beginIf(cond) {
        b.generate()
        b.copy(b.randVar(), to: phi)
    }
    b.beginElse() {
        b.generate()
        b.copy(b.randVar(), to: phi)
    }
    b.endIf()
}

public func WhileLoopGenerator(_ b: ProgramBuilder) {
    let start = b.loadInt(0)
    let end = b.loadInt(Int.random(in: 0...10))
    let loopVar = b.phi(start)
    b.whileLoop(loopVar, .lessThan, end) {
        b.generate()
        let newLoopVar = b.unary(.Inc, loopVar)
        b.copy(newLoopVar, to: loopVar)
    }
}

public func DoWhileLoopGenerator(_ b: ProgramBuilder) {
    let start = b.loadInt(0)
    let end = b.loadInt(Int.random(in: 0...10))
    let loopVar = b.phi(start)
    b.doWhileLoop(loopVar, .lessThan, end) {
        b.generate()
        let newLoopVar = b.unary(.Inc, loopVar)
        b.copy(newLoopVar, to: loopVar)
    }
}

public func ForLoopGenerator(_ b: ProgramBuilder) {
    let start = b.loadInt(0)
    let end = b.loadInt(Int.random(in: 0...10))
    let step = b.loadInt(1)
    b.forLoop(start, .lessThan, end, .Add, step) { _ in
        b.generate()
    }
}

public func ForInLoopGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    b.forInLoop(obj) { _ in
        b.generate()
    }
}

public func ForOfLoopGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    b.forOfLoop(obj) { _ in
        b.generate()
    }
}

public func BreakGenerator(_ b: ProgramBuilder) {
    if b.isInLoop {
        b.doBreak()
    }
}

public func ContinueGenerator(_ b: ProgramBuilder) {
    if b.isInLoop {
        b.doContinue()
    }
}

public func TryCatchGenerator(_ b: ProgramBuilder) {
    let v = b.phi(b.randVar())
    b.beginTry() {
        b.generate()
        b.copy(b.randVar(), to: v)
    }
    b.beginCatch() { _ in
        b.generate()
        b.copy(b.randVar(), to: v)
    }
    b.endTryCatch()
}

public func ThrowGenerator(_ b: ProgramBuilder) {
    let v = b.randVar()
    b.throwException(v)
}

//
// Language-specific Generators
//

public func TypedArrayGenerator(_ b: ProgramBuilder) {
    let size = b.loadInt(Int.random(in: 0...0x10000))
    let constructor = b.loadBuiltin(chooseUniform(from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "DataView"]))
    b.construct(constructor, withArgs: [size])
}

public func FloatArrayGenerator(_ b: ProgramBuilder) {
    let value = b.loadFloat(13.37)
    b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
}

public func IntArrayGenerator(_ b: ProgramBuilder) {
    let value = b.loadInt(1337)
    b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
}

public func ObjectArrayGenerator(_ b: ProgramBuilder) {
    let value = b.createObject(with: [:])
    b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
}

public func WellKnownPropertyLoadGenerator(_ b: ProgramBuilder) {
    let Symbol = b.loadBuiltin("Symbol")
    let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
    let pname = b.loadProperty(name, of: Symbol)
    let obj = b.randVar(ofType: .MaybeObject)
    b.loadComputedProperty(pname, of: obj)
}

public func WellKnownPropertyStoreGenerator(_ b: ProgramBuilder) {
    let Symbol = b.loadBuiltin("Symbol")
    let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
    let pname = b.loadProperty(name, of: Symbol)
    let obj = b.randVar(ofType: .MaybeObject)
    let val = b.randVar()
    b.storeComputedProperty(val, as: pname, on: obj)
}

public func PrototypeAccessGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    b.loadProperty("__proto__", of: obj)
}

public func PrototypeOverwriteGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    let proto = b.randVar(ofType: .MaybeObject)
    b.storeProperty(proto, as: "__proto__", on: obj)
}

public func CallbackPropertyGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    let callback = b.randVar(ofType: .Function)
    let propertyName = chooseUniform(from: ["valueOf", "toString"])
    b.storeProperty(callback, as: propertyName, on: obj)
}

public func PropertyAccessorGenerator(_ b: ProgramBuilder) {
    let receiver = b.randVar(ofType: .MaybeObject)
    let propertyName = probability(0.5) ? b.loadString(b.genPropertyName()) : b.loadInt(b.genIndex())
    
    var initialProperties = [String: Variable]()
    withEqualProbability({
        initialProperties = ["get": b.randVar(ofType: .Function)]
    }, {
        initialProperties = ["set": b.randVar(ofType: .Function)]
    }, {
        initialProperties = ["get": b.randVar(ofType: .Function), "set": b.randVar(ofType: .Function)]
    })
    let descriptor = b.createObject(with: initialProperties)
    
    let Object = b.loadBuiltin("Object")
    b.callMethod("defineProperty", on: Object, withArgs: [receiver, propertyName, descriptor])
}

public func ProxyGenerator(_ b: ProgramBuilder) {
    let target = b.randVar()
    
    var candidates = Set(["getPrototypeOf", "setPrototypeOf", "isExtensible", "preventExtensions", "getOwnPropertyDescriptor", "defineProperty", "has", "get", "set", "deleteProperty", "ownKeys", "apply", "call", "construct"])
    
    var handlerProperties = [String: Variable]()
    for _ in 0..<Int.random(in: 0..<candidates.count) {
        let hook = chooseUniform(from: candidates)
        candidates.remove(hook)
        handlerProperties[hook] = b.randVar(ofType: .Function)
    }
    let handler = b.createObject(with: handlerProperties)
    
    let Proxy = b.loadBuiltin("Proxy")
    
    b.construct(Proxy, withArgs: [target, handler])
}

// Tries to change the length property of some object
public func LengthChangeGenerator(_ b: ProgramBuilder) {
    let target = b.randVar(ofType: .MaybeObject)
    let newLength: Variable
    if probability(0.5) {
        newLength = b.loadInt(Int.random(in: 0..<3))
    } else {
        newLength = b.loadInt(b.genIndex())
    }
    b.storeProperty(newLength, as: "length", on: target)
}

// Tries to change the element kind of an array
public func ElementKindChangeGenerator(_ b: ProgramBuilder) {
    let target = b.randVar(ofType: .MaybeObject)
    let value = b.randVar()
    b.storeElement(value, at: Int.random(in: 0..<3), of: target)
}

// Generates a JavaScript 'with' statement
public func WithStatementGenerator(_ b: ProgramBuilder) {
    let obj = b.randVar(ofType: .MaybeObject)
    b.with(obj) {
        withProbability(0.5, do: { () -> Void in
            b.loadFromScope(id: b.genPropertyName())
        }, else: { () -> Void in
            let value = b.randVar()
            b.storeToScope(value, as: b.genPropertyName())
        })
        b.generate()
    }
}

public func LoadFromScopeGenerator(_ b: ProgramBuilder) {
    guard b.isInWithStatement else {
        return
    }
    b.loadFromScope(id: b.genPropertyName())
}

public func StoreToScopeGenerator(_ b: ProgramBuilder) {
    guard b.isInWithStatement else {
        return
    }
    let value = b.randVar()
    b.storeToScope(value, as: b.genPropertyName())
}
