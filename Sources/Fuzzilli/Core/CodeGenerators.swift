// Copyright 2020 Google LLC
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
public let CodeGenerators: [CodeGenerator] = [
    CodeGenerator("IntegerGenerator") { b in
        b.loadInt(b.genInt())
    },

    CodeGenerator("BigIntGenerator") { b in
        b.loadBigInt(b.genInt())
    },

    CodeGenerator("RegExpGenerator") { b in
        b.loadRegExp(b.genRegExp(), b.genRegExpFlags())
    },

    CodeGenerator("FloatGenerator") { b in
        b.loadFloat(b.genFloat())
    },

    CodeGenerator("StringGenerator") { b in
        b.loadString(b.genString())
    },

    CodeGenerator("BooleanGenerator") { b in
        b.loadBool(Bool.random())
    },

    CodeGenerator("UndefinedGenerator") { b in
        b.loadUndefined()
    },

    CodeGenerator("NullGenerator") { b in
        b.loadNull()
    },

    CodeGenerator("ThisGenerator") { b in
        b.loadThis()
    },

    CodeGenerator("ArgumentsGenerator", inContext: .subroutine) { b in
        assert(b.context.contains(.subroutine))
        b.loadArguments()
    },

    CodeGenerator("ObjectGenerator") { b in
        var initialProperties = [String: Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            let propertyName = b.genPropertyNameForWrite()
            var type = b.type(ofProperty: propertyName)
            initialProperties[propertyName] = b.randVar(ofType: type) ?? b.generateVariable(ofType: type)
        }
        b.createObject(with: initialProperties)
    },

    CodeGenerator("ArrayGenerator") { b in
        var initialValues = [Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            initialValues.append(b.randVar())
        }
        b.createArray(with: initialValues)
    },

    CodeGenerator("ObjectWithSpreadGenerator") { b in
        var initialProperties = [String: Variable]()
        var spreads = [Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            withProbability(0.5, do: {
                let propertyName = b.genPropertyNameForWrite()
                var type = b.type(ofProperty: propertyName)
                initialProperties[propertyName] = b.randVar(ofType: type) ?? b.generateVariable(ofType: type)
            }, else: {
                spreads.append(b.randVar())
            })
        }
        b.createObject(with: initialProperties, andSpreading: spreads)
    },

    CodeGenerator("ArrayWithSpreadGenerator") { b in
        var initialValues = [Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            initialValues.append(b.randVar())
        }

        // Pick some random inputs to spread.
        let spreads = initialValues.map({ el in
            probability(0.75) && b.type(of: el).Is(.iterable)
        })

        b.createArray(with: initialValues, spreading: spreads)
    },

    CodeGenerator("TemplateStringGenerator") { b in
        var interpolatedValues = [Variable]()
        for _ in 1..<Int.random(in: 1...5) {
            interpolatedValues.append(b.randVar())
        }

        var parts = [String]()
        for _ in 0...interpolatedValues.count {
            // For now we generate random strings
            parts.append(b.genString())
        }
        b.createTemplateString(from: parts, interpolating: interpolatedValues)
    },

    CodeGenerator("BuiltinGenerator") { b in
        b.loadBuiltin(b.genBuiltinName())
    },

    CodeGenerator("PlainFunctionGenerator") { b in
        b.buildPlainFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("ArrowFunctionGenerator") { b in
        b.buildArrowFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("GeneratorFunctionGenerator") { b in
        b.buildGeneratorFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            if probability(0.5) {
                b.yield(b.randVar())
            } else {
                b.yieldEach(b.randVar())
            }
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("AsyncFunctionGenerator") { b in
        b.buildAsyncFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("AsyncArrowFunctionGenerator") { b in
        b.buildAsyncArrowFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("AsyncGeneratorFunctionGenerator") { b in
        b.buildAsyncGeneratorFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            if probability(0.5) {
                b.yield(b.randVar())
            } else {
                b.yieldEach(b.randVar())
            }
            b.doReturn(b.randVar())
        }
    },

    CodeGenerator("ConstructorGenerator") { b in
        b.buildConstructor(with: b.generateFunctionParameters()) { _ in
            b.buildRecursive()
        }
    },

    CodeGenerator("PropertyRetrievalGenerator", input: .object()) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.genPropertyNameForRead()
        b.loadProperty(propertyName, of: obj)
    },

    CodeGenerator("PropertyAssignmentGenerator", input: .object()) { b, obj in
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName = b.type(of: obj).randomProperty() ?? b.genPropertyNameForWrite()
        } else {
            propertyName = b.genPropertyNameForWrite()
        }
        var propertyType = b.type(ofProperty: propertyName)
        let value = b.randVar(ofType: propertyType) ?? b.generateVariable(ofType: propertyType)
        b.storeProperty(value, as: propertyName, on: obj)
    },

    CodeGenerator("StorePropertyWithBinopGenerator", input: .object()) { b, obj in
        let propertyName: String
        // Change an existing property
        propertyName = b.type(of: obj).randomProperty() ?? b.genPropertyNameForWrite()

        var propertyType = b.type(ofProperty: propertyName)
        let value = b.randVar(ofType: propertyType) ?? b.generateVariable(ofType: propertyType)
        b.storeProperty(value, as: propertyName, with: chooseUniform(from: BinaryOperator.allCases), on: obj)
    },

    CodeGenerator("PropertyRemovalGenerator", input: .object()) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.genPropertyNameForWrite()
        b.deleteProperty(propertyName, of: obj)
    },


    CodeGenerator("PropertyConfigurationGenerator", input: .object()) { b, obj in
        let propertyName = b.genPropertyNameForWrite()
        withEqualProbability({
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randVar()))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getterSetter(getterFunc, setterFunc))
        })
    },

    CodeGenerator("ElementRetrievalGenerator", input: .object()) { b, obj in
        let index = b.genIndex()
        b.loadElement(index, of: obj)
    },

    CodeGenerator("ElementAssignmentGenerator", input: .object()) { b, obj in
        let index = b.genIndex()
        let value = b.randVar()
        b.storeElement(value, at: index, of: obj)
    },

    CodeGenerator("StoreElementWithBinopGenerator", input: .object()) { b, obj in
        let index = b.genIndex()
        let value = b.randVar()
        b.storeElement(value, at: index, with: chooseUniform(from: BinaryOperator.allCases), of: obj)
    },

    CodeGenerator("ElementRemovalGenerator", input: .object()) { b, obj in
        let index = b.genIndex()
        b.deleteElement(index, of: obj)
    },

    CodeGenerator("ElementConfigurationGenerator", input: .object()) { b, obj in
        let index = b.genIndex()
        withEqualProbability({
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randVar()))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .getterSetter(getterFunc, setterFunc))
        })
    },

    CodeGenerator("ComputedPropertyRetrievalGenerator", input: .object()) { b, obj in
        let propertyName = b.randVar()
        b.loadComputedProperty(propertyName, of: obj)
    },

    CodeGenerator("ComputedPropertyAssignmentGenerator", input: .object()) { b, obj in
        let propertyName = b.randVar()
        let value = b.randVar()
        b.storeComputedProperty(value, as: propertyName, on: obj)
    },

    CodeGenerator("StoreComputedPropertyWithBinopGenerator", input: .object()) { b, obj in
        let propertyName = b.randVar()
        let value = b.randVar()
        b.storeComputedProperty(value, as: propertyName, with: chooseUniform(from: BinaryOperator.allCases), on: obj)
    },

    CodeGenerator("ComputedPropertyRemovalGenerator", input: .object()) { b, obj in
        let propertyName = b.randVar()
        b.deleteComputedProperty(propertyName, of: obj)
    },

    CodeGenerator("ComputedPropertyConfigurationGenerator", input: .object()) { b, obj in
        let propertyName = b.randVar()
        withEqualProbability({
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randVar()))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randVar(ofType: .function()) else { return }
            guard let setterFunc = b.randVar(ofType: .function()) else { return }
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getterSetter(getterFunc, setterFunc))
        })
    },

    CodeGenerator("TypeTestGenerator", input: .anything) { b, val in
        let type = b.typeof(val)
        // Also generate a comparison here, since that's probably the only interesting thing you can do with the result.
        let rhs = b.loadString(chooseUniform(from: JavaScriptEnvironment.jsTypeNames))
        b.compare(type, with: rhs, using: .strictEqual)
    },

    CodeGenerator("InstanceOfGenerator", inputs: (.anything, .function() | .constructor())) { b, val, cls in
        b.testInstanceOf(val, cls)
    },

    CodeGenerator("InGenerator", input: .object()) { b, obj in
        let prop = b.randVar()
        b.testIn(prop, obj)
    },

    CodeGenerator("MethodCallGenerator", input: .object()) { b, obj in
        if let methodName = b.type(of: obj).randomMethod() {
            guard let arguments = b.randCallArguments(forMethod: methodName, on: obj) else { return }
            b.callMethod(methodName, on: obj, withArgs: arguments)
        } else {
            // Wrap the call into try-catch as there is a large probability that it'll be invalid and cause an exception.
            // If it is valid, the try-catch will probably be removed by the minimizer later on.
            let methodName = b.genMethodName()
            guard let arguments = b.randCallArguments(forMethod: methodName, on: obj) else { return }
            b.buildTryCatchFinally(tryBody: {
                b.callMethod(methodName, on: obj, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("MethodCallWithSpreadGenerator", input: .object()) { b, obj in
        // We cannot currently track element types of Arrays and other Iterable objects and so cannot properly determine argument types when spreading.
        // For that reason, we don't run this CodeGenerator in conservative mode
        guard b.mode != .conservative else { return }
        guard let methodName = b.type(of: obj).randomMethod() else { return }

        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        b.callMethod(methodName, on: obj, withArgs: arguments, spreading: spreads)
    },

    CodeGenerator("ComputedMethodCallGenerator", input: .object()) { b, obj in
        if let methodName = b.type(of: obj).randomMethod() {
            let method = b.loadString(methodName)
            guard let arguments = b.randCallArguments(forMethod: methodName, on: obj) else { return }
            b.callComputedMethod(method, on: obj, withArgs: arguments)
        } else {
            let methodName = b.genMethodName()
            guard let arguments = b.randCallArguments(forMethod: methodName, on: obj) else { return }
            let method = b.loadString(methodName)
            b.buildTryCatchFinally(tryBody: {
                b.callComputedMethod(method, on: obj, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("ComputedMethodCallWithSpreadGenerator", input: .object()) { b, obj in
        // We cannot currently track element types of Arrays and other Iterable objects and so cannot properly determine argument types when spreading.
        // For that reason, we don't run this CodeGenerator in conservative mode
        guard b.mode != .conservative else { return }
        guard let methodName = b.type(of: obj).randomMethod() else { return }

        let method = b.loadString(methodName)
        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        b.callComputedMethod(method, on: obj, withArgs: arguments, spreading: spreads)
    },

    CodeGenerator("FunctionCallGenerator", input: .function()) { b, f in
        guard let arguments = b.randCallArguments(for: f) else { return }
        b.callFunction(f, withArgs: arguments)
    },

    CodeGenerator("ConstructorCallGenerator", input: .constructor()) { b, c in
        guard let arguments = b.randCallArguments(for: c) else { return }
        b.construct(c, withArgs: arguments)
    },

    CodeGenerator("FunctionCallWithSpreadGenerator", input: .function()) { b, f in
        // We cannot currently track element types of Arrays and other Iterable objects and so cannot properly determine argument types when spreading.
        // For that reason, we don't run this CodeGenerator in conservative mode
        guard b.mode != .conservative else { return }

        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))

        b.callFunction(f, withArgs: arguments, spreading: spreads)
    },

    CodeGenerator("ConstructorCallWithSpreadGenerator", input: .constructor()) { b, c in
        // We cannot currently track element types of Arrays and other Iterable objects and so cannot properly determine argument types when spreading.
        // For that reason, we don't run this CodeGenerator in conservative mode
        guard b.mode != .conservative else { return }

        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))

        b.construct(c, withArgs: arguments, spreading: spreads)
    },

    CodeGenerator("SubroutineReturnGenerator", inContext: .subroutine, input: .anything) { b, val in
        assert(b.context.contains(.subroutine))
        b.doReturn(val)
    },

    CodeGenerator("YieldGenerator", inContext: .generatorFunction, input: .anything) { b, val in
        assert(b.context.contains(.generatorFunction))
        if probability(0.5) {
            b.yield(val)
        } else {
            b.yieldEach(val)
        }
    },

    CodeGenerator("AwaitGenerator", inContext: .asyncFunction, input: .anything) { b, val in
        assert(b.context.contains(.asyncFunction))
        b.await(val)
    },

    CodeGenerator("UnaryOperationGenerator", input: .anything) { b, val in
        b.unary(chooseUniform(from: UnaryOperator.allCases), val)
    },

    CodeGenerator("BinaryOperationGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        b.binary(lhs, rhs, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ReassignWithBinopGenerator", input: .anything) { b, val in
        let target = b.randVar()
        b.reassign(target, to: val, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("DupGenerator") { b in
        b.dup(b.randVar())
    },

    CodeGenerator("ReassignmentGenerator", input: .anything) { b, val in
        let target = b.randVar()
        b.reassign(target, to: val)
    },

    CodeGenerator("DestructArrayGenerator", input: .iterable) { b, arr in
        // Fuzzilli generated arrays can have a length ranging from 0 to 10 elements,
        // We want to ensure that 1) when destructing arrays we are usually within this length range
        // and 2) The probability with which we select indices allows defining atleast 2-3 variables.
        var indices: [Int] = []
        for idx in 0..<Int.random(in: 0..<5) {
            withProbability(0.7) {
                indices.append(idx)
            }
        }

        b.destruct(arr, selecting: indices, hasRestElement: probability(0.2))
    },

    CodeGenerator("DestructArrayAndReassignGenerator", input: .iterable) {b, arr in
        var candidates: [Variable] = []
        var indices: [Int] = []
        for idx in 0..<Int.random(in: 0..<5) {
            withProbability(0.7) {
                indices.append(idx)
                candidates.append(b.randVar())
            }
        }
        b.destruct(arr, selecting: indices, into: candidates, hasRestElement: probability(0.2))
    },

    CodeGenerator("DestructObjectGenerator", input: .object()) { b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).properties.randomElement(), !properties.contains(prop) {
                properties.insert(prop)
            } else {
                properties.insert(b.genPropertyNameForRead())
            }
        }

        let hasRestElement = probability(0.2)

        b.destruct(obj, selecting: properties.sorted(), hasRestElement: hasRestElement)
    },

    CodeGenerator("DestructObjectAndReassignGenerator", input: .object()) { b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).properties.randomElement(), !properties.contains(prop) {
                properties.insert(prop)
            } else {
                properties.insert(b.genPropertyNameForRead())
            }
        }

        var candidates = properties.map{ _ in
            b.randVar()
        }

        let hasRestElement = probability(0.2)
        if hasRestElement {
            candidates.append(b.randVar())
        }

        b.destruct(obj, selecting: properties.sorted(), into: candidates, hasRestElement: hasRestElement)
    },

    CodeGenerator("ComparisonGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
    },

    CodeGenerator("ConditionalOperationGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        let condition = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.conditional(condition, lhs, rhs)
    },

    CodeGenerator("ClassGenerator") { b in
        // Possibly pick a superclass
        var superclass: Variable? = nil
        if probability(0.5) {
            superclass = b.randVar(ofConservativeType: .constructor())
        }

        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: b.generateFunctionParameters()) { _ in
                // Must call the super constructor if there is a superclass
                if let superConstructor = superclass {
                    let arguments = b.randCallArguments(for: superConstructor) ?? []
                    b.callSuperConstructor(withArgs: arguments)
                }

                b.buildRecursive()
            }

            let numProperties = Int.random(in: 1...3)
            for _ in 0..<numProperties {
                cls.defineProperty(b.genPropertyNameForWrite())
            }

            let numMethods = Int.random(in: 1...3)
            for _ in 0..<numMethods {
                cls.defineMethod(b.genMethodName(), with: b.generateFunctionParameters()) { _ in
                    b.buildRecursive()
                }
            }
        }
    },

    CodeGenerator("SuperMethodCallGenerator", inContext: .classDefinition) { b in
        let superType = b.currentSuperType()
        if let methodName = superType.randomMethod() {
            guard let arguments = b.randCallArguments(forMethod: methodName, on: superType) else { return }
            b.callSuperMethod(methodName, withArgs: arguments)
        } else {
            // Wrap the call into try-catch as there's a large probability that it will be invalid and cause an exception.
            let methodName = b.genMethodName()
            guard let arguments = b.randCallArguments(forMethod: methodName, on: superType) else { return }
            b.buildTryCatchFinally(tryBody: {
                b.callSuperMethod(methodName, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    // Loads a property on the super object
    CodeGenerator("LoadSuperPropertyGenerator", inContext: .classDefinition) { b in
        let superType = b.currentSuperType()
        // Emit a property load
        let propertyName = superType.randomProperty() ?? b.genPropertyNameForRead()
        b.loadSuperProperty(propertyName)
    },

    // Stores a property on the super object
    CodeGenerator("StoreSuperPropertyGenerator", inContext: .classDefinition) { b in
        let superType = b.currentSuperType()
        // Emit a property store
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName = superType.randomProperty() ?? b.genPropertyNameForWrite()
        } else {
            propertyName = b.genPropertyNameForWrite()
        }
        var propertyType = b.type(ofProperty: propertyName)
        // TODO unify the .unknown => .anything conversion
        if propertyType == .unknown {
            propertyType = .anything
        }
        let value = b.randVar(ofType: propertyType) ?? b.generateVariable(ofType: propertyType)
        b.storeSuperProperty(value, as: propertyName)
    },

    // Stores a property with a binary operation on the super object
    CodeGenerator("StoreSuperPropertyWithBinopGenerator", inContext: .classDefinition) { b in
        let superType = b.currentSuperType()
        // Emit a property store
        let propertyName = superType.randomProperty() ?? b.genPropertyNameForWrite()

        var propertyType = b.type(ofProperty: propertyName)
        // TODO unify the .unknown => .anything conversion
        if propertyType == .unknown {
            propertyType = .anything
        }
        let value = b.randVar(ofType: propertyType) ?? b.generateVariable(ofType: propertyType)
        b.storeSuperProperty(value, as: propertyName, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("IfElseGenerator", input: .boolean) { b, cond in
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive()
        }, elseBody: {
            b.buildRecursive()
        })
    },

    CodeGenerator("CompareWithIfElseGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        let cond = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive()
        }, elseBody: {
            b.buildRecursive()
        })
    },

    CodeGenerator("SwitchCaseGenerator", inContext: .switchBlock, input: .anything) { b, caseVar in
        b.buildSwitchCase(forCase: caseVar, fallsThrough: probability(0.1)) {
            b.buildRecursive()
        }
    },

    CodeGenerator("SwitchBlockGenerator", input: .anything) { b, cond in
        var candidates: [Variable] = []

        // Generate a minimum of three cases (including a potential default case)
        for _ in 0..<Int.random(in: 3...8) {
            candidates.append(b.randVar())
        }

        // If this is set, the selected candidate becomes the default case
        var defaultCasePosition = -1
        if probability(0.8) {
            defaultCasePosition = Int.random(in: 0..<candidates.count)
        }

        b.buildSwitch(on: cond) { cases in
            for (idx, val) in candidates.enumerated() {
                if idx == defaultCasePosition {
                    cases.addDefault(fallsThrough: probability(0.1)) {
                        b.buildRecursive()
                    }
                } else {
                    cases.add(val, fallsThrough: probability(0.1)) {
                        b.buildRecursive()
                    }
                }
            }
        }
    },

    CodeGenerator("SwitchCaseBreakGenerator", inContext: .switchCase) { b in
        b.switchBreak()
    },

    CodeGenerator("WhileLoopGenerator") { b in
        let loopVar = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        b.buildWhileLoop(loopVar, .lessThan, end) {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }
    },

    CodeGenerator("DoWhileLoopGenerator") { b in
        let loopVar = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        b.buildDoWhileLoop(loopVar, .lessThan, end) {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }
    },

    CodeGenerator("ForLoopGenerator") { b in
        let start = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        let step = b.reuseOrLoadInt(1)
        b.buildForLoop(start, .lessThan, end, .Add, step) { _ in
            b.buildRecursive()
        }
    },

    CodeGenerator("ForInLoopGenerator", input: .object()) { b, obj in
        b.buildForInLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    CodeGenerator("ForOfLoopGenerator", input: .iterable) { b, obj in
        b.buildForOfLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    CodeGenerator("ForOfWithDestructLoopGenerator", input: .iterable) { b, obj in
        // Don't run this generator in conservative mode, until we can track array element types
        guard b.mode != .conservative else { return }
        var indices: [Int] = []
        for idx in 0..<Int.random(in: 1..<5) {
            withProbability(0.8) {
                indices.append(idx)
            }
        }

        if indices.isEmpty {
            indices = [0]
        }

        b.buildForOfLoop(obj, selecting: indices, hasRestElement: probability(0.2)) { _ in
            b.buildRecursive()
        }
    },

    CodeGenerator("LoopBreakGenerator", inContext: .loop) { b in
        b.loopBreak()
    },

    CodeGenerator("ContinueGenerator", inContext: .loop) { b in
        assert(b.context.contains(.loop))
        b.loopContinue()
    },

    CodeGenerator("TryCatchGenerator") { b in
        // Build either try-catch-finally, try-catch, or try-finally
        withEqualProbability({
            // try-catch-finally
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive()
            }, catchBody: { _ in
                b.buildRecursive()
            }, finallyBody: {
                b.buildRecursive()
            })
        }, {
            // try-catch
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive()
            }, catchBody: { _ in
                b.buildRecursive()
            })
        }, {
            // try-finally
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive()
            }, finallyBody: {
                b.buildRecursive()
            })
        })
    },

    CodeGenerator("ThrowGenerator") { b in
        let v = b.randVar()
        b.throwException(v)
    },

    //
    // Language-specific Generators
    //

    CodeGenerator("TypedArrayGenerator") { b in
        let size = b.loadInt(Int64.random(in: 0...0x10000))
        let constructor = b.reuseOrLoadBuiltin(
            chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray"]
            )
        )
        b.construct(constructor, withArgs: [size])
    },

    CodeGenerator("FloatArrayGenerator") { b in
        let value = b.reuseOrLoadAnyFloat()
        b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
    },

    CodeGenerator("IntArrayGenerator") { b in
        let value = b.reuseOrLoadAnyInt()
        b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
    },

    CodeGenerator("ObjectArrayGenerator") { b in
        let value = b.createObject(with: [:])
        b.createArray(with: Array(repeating: value, count: Int.random(in: 1...5)))
    },

    CodeGenerator("WellKnownPropertyLoadGenerator", input: .object()) { b, obj in
        let Symbol = b.reuseOrLoadBuiltin("Symbol")
        let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
        let pname = b.loadProperty(name, of: Symbol)
        b.loadComputedProperty(pname, of: obj)
    },

    CodeGenerator("WellKnownPropertyStoreGenerator", input: .object()) { b, obj in
        let Symbol = b.reuseOrLoadBuiltin("Symbol")
        let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
        let pname = b.loadProperty(name, of: Symbol)
        let val = b.randVar()
        b.storeComputedProperty(val, as: pname, on: obj)
    },

    CodeGenerator("PrototypeAccessGenerator", input: .object()) { b, obj in
        b.loadProperty("__proto__", of: obj)
    },

    CodeGenerator("PrototypeOverwriteGenerator", inputs: (.object(), .object())) { b, obj, proto in
        b.storeProperty(proto, as: "__proto__", on: obj)
    },

    CodeGenerator("CallbackPropertyGenerator", inputs: (.object(), .function())) { b, obj, callback in
        // TODO add new callbacks like Symbol.toPrimitive?
        let propertyName = chooseUniform(from: ["valueOf", "toString"])
        b.storeProperty(callback, as: propertyName, on: obj)
    },

    CodeGenerator("MethodCallWithDifferentThisGenerator", inputs: (.object(), .object())) { b, obj, this in
        var methodName = b.type(of: obj).randomMethod()
        if methodName == nil {
            guard b.mode != .conservative else { return }
            methodName = b.genMethodName()
        }
        guard let arguments = b.randCallArguments(forMethod: methodName!, on: obj) else { return }
        let Reflect = b.reuseOrLoadBuiltin("Reflect")
        let args = b.createArray(with: arguments)
        b.callMethod("apply", on: Reflect, withArgs: [b.loadProperty(methodName!, of: obj), this, args])
    },

    CodeGenerator("ProxyGenerator", input: .object()) { b, target in
        var candidates = Set(["getPrototypeOf", "setPrototypeOf", "isExtensible", "preventExtensions", "getOwnPropertyDescriptor", "defineProperty", "has", "get", "set", "deleteProperty", "ownKeys", "apply", "call", "construct"])

        var handlerProperties = [String: Variable]()
        for _ in 0..<Int.random(in: 0..<candidates.count) {
            let hook = chooseUniform(from: candidates)
            candidates.remove(hook)
            handlerProperties[hook] = b.randVar(ofType: .function())
        }
        let handler = b.createObject(with: handlerProperties)

        let Proxy = b.reuseOrLoadBuiltin("Proxy")

        b.construct(Proxy, withArgs: [target, handler])
    },

    CodeGenerator("PromiseGenerator") { b in
        let handler = b.buildPlainFunction(with: .parameters(n: 2)) { _ in
            // TODO could provide type hints here for the parameters.
            b.buildRecursive()
        }
        let promiseConstructor = b.reuseOrLoadBuiltin("Promise")
        b.construct(promiseConstructor, withArgs: [handler])
    },

    // Tries to change the length property of some object
    CodeGenerator("LengthChangeGenerator", input: .object()) { b, obj in
        let newLength: Variable
        if probability(0.5) {
            // Shrink
            newLength = b.reuseOrLoadInt(Int64.random(in: 0..<3))
        } else {
            // (Probably) grow
            newLength = b.reuseOrLoadInt(b.genIndex())
        }
        b.storeProperty(newLength, as: "length", on: obj)
    },

    // Tries to change the element kind of an array
    CodeGenerator("ElementKindChangeGenerator", input: .object()) { b, obj in
        let value = b.randVar()
        b.storeElement(value, at: Int64.random(in: 0..<10), of: obj)
    },

    // Generates a JavaScript 'with' statement
    CodeGenerator("WithStatementGenerator", input: .object()) { b, obj in
        b.buildWith(obj) {
            withProbability(0.5, do: { () -> Void in
                b.loadFromScope(id: b.genPropertyNameForRead())
            }, else: { () -> Void in
                let value = b.randVar()
                b.storeToScope(value, as: b.genPropertyNameForWrite())
            })
            b.buildRecursive()
        }
    },

    CodeGenerator("LoadFromScopeGenerator", inContext: .with) { b in
        assert(b.context.contains(.with))
        b.loadFromScope(id: b.genPropertyNameForRead())
    },

    CodeGenerator("StoreToScopeGenerator", inContext: .with) { b in
        assert(b.context.contains(.with))
        let value = b.randVar()
        b.storeToScope(value, as: b.genPropertyNameForWrite())
    },

    CodeGenerator("EvalGenerator") { b in
        let code = b.buildCodeString() {
            b.buildRecursive()
        }
        let eval = b.reuseOrLoadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])
    },

    CodeGenerator("BlockStatementGenerator") { b in
        b.blockStatement(){
            b.buildRecursive()
        }
    },

    CodeGenerator("MathOperationGenerator") { b in
        let Math = b.reuseOrLoadBuiltin("Math")
        // This can fail in tests, which lack the full JavaScriptEnvironment
        guard let method = b.type(of: Math).randomMethod() else { return }
        let args = b.generateCallArguments(forMethod: method, on: Math)
        b.callMethod(method, on: Math, withArgs: args)
    }
]

extension Array where Element == CodeGenerator {
    public func get(_ name: String) -> CodeGenerator {
        for generator in self {
            if generator.name == name {
                return generator
            }
        }
        fatalError("Unknown code generator \(name)")
    }
}
