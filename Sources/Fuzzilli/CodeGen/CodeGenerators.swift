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

    CodeGenerator("StringNormalizeGenerator") { b in
        let form = b.loadString(
            chooseUniform(
                from: ["NFC", "NFD", "NFKC", "NFKD"]
            )
        )
        let string = b.loadString(b.genString())
        b.callMethod("normalize", on: string, withArgs: [form])
    },

    CodeGenerator("BuiltinGenerator") { b in
        b.loadBuiltin(b.genBuiltinName())
    },

    RecursiveCodeGenerator("PlainFunctionGenerator") { b in
        let f = b.buildPlainFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randVar())
        }
        b.callFunction(f, withArgs: b.generateCallArguments(for: f))
    },

    RecursiveCodeGenerator("ArrowFunctionGenerator") { b in
        b.buildArrowFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randVar())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("GeneratorFunctionGenerator") { b in
        let f = b.buildGeneratorFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            if probability(0.5) {
                b.yield(b.randVar())
            } else {
                b.yieldEach(b.randVar())
            }
            b.doReturn(b.randVar())
        }
        b.callFunction(f, withArgs: b.generateCallArguments(for: f))
    },

    RecursiveCodeGenerator("AsyncFunctionGenerator") { b in
        let f = b.buildAsyncFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            b.doReturn(b.randVar())
        }
        b.callFunction(f, withArgs: b.generateCallArguments(for: f))
    },

    RecursiveCodeGenerator("AsyncArrowFunctionGenerator") { b in
        b.buildAsyncArrowFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            b.doReturn(b.randVar())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("AsyncGeneratorFunctionGenerator") { b in
        let f = b.buildAsyncGeneratorFunction(with: b.generateFunctionParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randVar())
            if probability(0.5) {
                b.yield(b.randVar())
            } else {
                b.yieldEach(b.randVar())
            }
            b.doReturn(b.randVar())
        }
        b.callFunction(f, withArgs: b.generateCallArguments(for: f))
    },

    RecursiveCodeGenerator("ConstructorGenerator") { b in
        let c = b.buildConstructor(with: b.generateFunctionParameters()) { _ in
            b.buildRecursive()
        }
        b.construct(c, withArgs: b.generateCallArguments(for: c))
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
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callMethod(methodName, on: obj, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
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
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callComputedMethod(method, on: obj, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("FunctionCallGenerator", input: .function()) { b, f in
        guard let arguments = b.randCallArguments(for: f) else { return }
        if b.type(of: f).Is(.function()) {
            b.callFunction(f, withArgs: arguments)
        } else {
            b.buildTryCatchFinally(tryBody: {
                b.callFunction(f, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("ConstructorCallGenerator", input: .constructor()) { b, c in
        guard let arguments = b.randCallArguments(for: c) else { return }
        if b.type(of: c).Is(.constructor()) {
            b.construct(c, withArgs: arguments)
        } else {
            b.buildTryCatchFinally(tryBody: {
                b.construct(c, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("FunctionCallWithSpreadGenerator", input: .function()) { b, f in
        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callFunction(f, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("ConstructorCallWithSpreadGenerator", input: .constructor()) { b, c in
        let (arguments, spreads) = b.randCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.construct(c, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
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
        // TODO try to find a replacement with a compatible type and make sure it's a different variable.
        let target = b.randVar()
        b.reassign(target, to: val)
    },

    CodeGenerator("DestructArrayGenerator", input: .iterable) { b, arr in
        // Fuzzilli generated arrays can have a length ranging from 0 to 10 elements,
        // We want to ensure that 1) when destructing arrays we are usually within this length range
        // and 2) The probability with which we select indices allows defining atleast 2-3 variables.
        var indices: [Int64] = []
        for idx in 0..<Int64.random(in: 0..<5) {
            withProbability(0.7) {
                indices.append(idx)
            }
        }

        b.destruct(arr, selecting: indices, hasRestElement: probability(0.2))
    },

    CodeGenerator("DestructArrayAndReassignGenerator", input: .iterable) {b, arr in
        var candidates: [Variable] = []
        var indices: [Int64] = []
        for idx in 0..<Int64.random(in: 0..<5) {
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

    RecursiveCodeGenerator("ClassGenerator") { b in
        // Possibly pick a superclass
        var superclass: Variable? = nil
        if probability(0.5) {
            superclass = b.randVar(ofConservativeType: .constructor())
        }

        let numProperties = Int.random(in: 1...3)
        let numMethods = Int.random(in: 1...3)

        b.buildClass(withSuperclass: superclass) { cls in
            cls.defineConstructor(with: b.generateFunctionParameters()) { _ in
                // Must call the super constructor if there is a superclass
                if let superConstructor = superclass {
                    let arguments = b.randCallArguments(for: superConstructor) ?? []
                    b.callSuperConstructor(withArgs: arguments)
                }

                b.buildRecursive(block: 1, of: numMethods + 1)
            }

            for _ in 0..<numProperties {
                cls.defineProperty(b.genPropertyNameForWrite())
            }

            for i in 0..<numMethods {
                cls.defineMethod(b.genMethodName(), with: b.generateFunctionParameters()) { _ in
                    b.buildRecursive(block: 2 + i, of: numMethods + 1)
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

    RecursiveCodeGenerator("IfElseGenerator", input: .boolean) { b, cond in
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive(block: 1, of: 2)
        }, elseBody: {
            b.buildRecursive(block: 2, of: 2)
        })
    },

    RecursiveCodeGenerator("CompareWithIfElseGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        let cond = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive(block: 1, of: 2)
        }, elseBody: {
            b.buildRecursive(block: 2, of: 2)
        })
    },

    RecursiveCodeGenerator("SwitchCaseGenerator", inContext: .switchBlock, input: .anything) { b, caseVar in
        b.buildSwitchCase(forCase: caseVar, fallsThrough: probability(0.1)) {
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("SwitchBlockGenerator", input: .anything) { b, cond in
        var candidates: [Variable] = []

        // Generate a minimum of three cases (including a potential default case)
        for _ in 0..<Int.random(in: 3...5) {
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
                        b.buildRecursive(block: idx + 1, of: candidates.count)
                    }
                } else {
                    cases.add(val, fallsThrough: probability(0.1)) {
                        b.buildRecursive(block: idx + 1, of: candidates.count)
                    }
                }
            }
        }
    },

    CodeGenerator("SwitchCaseBreakGenerator", inContext: .switchCase) { b in
        b.switchBreak()
    },

    RecursiveCodeGenerator("WhileLoopGenerator") { b in
        let loopVar = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        b.buildWhileLoop(loopVar, .lessThan, end) {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }
    },

    RecursiveCodeGenerator("DoWhileLoopGenerator") { b in
        let loopVar = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        b.buildDoWhileLoop(loopVar, .lessThan, end) {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }
    },

    RecursiveCodeGenerator("ForLoopGenerator") { b in
        let start = b.reuseOrLoadInt(0)
        let end = b.reuseOrLoadInt(Int64.random(in: 0...10))
        let step = b.reuseOrLoadInt(1)
        b.buildForLoop(start, .lessThan, end, .Add, step) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ForInLoopGenerator", input: .object()) { b, obj in
        b.buildForInLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ForOfLoopGenerator", input: .iterable) { b, obj in
        b.buildForOfLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ForOfWithDestructLoopGenerator", input: .iterable) { b, obj in
        // Don't run this generator in conservative mode, until we can track array element types
        guard b.mode != .conservative else { return }
        var indices: [Int64] = []
        for idx in 0..<Int64.random(in: 1..<5) {
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

    RecursiveCodeGenerator("RepeatLoopGenerator") { b in
        let numIterations = Int.random(in: 2...100)
        b.buildRepeat(n: numIterations) { _ in
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

    RecursiveCodeGenerator("TryCatchGenerator") { b in
        // Build either try-catch-finally, try-catch, or try-finally
        withEqualProbability({
            // try-catch-finally
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive(block: 1, of: 3)
            }, catchBody: { _ in
                b.buildRecursive(block: 2, of: 3)
            }, finallyBody: {
                b.buildRecursive(block: 3, of: 3)
            })
        }, {
            // try-catch
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive(block: 1, of: 2)
            }, catchBody: { _ in
                b.buildRecursive(block: 2, of: 2)
            })
        }, {
            // try-finally
            b.buildTryCatchFinally(tryBody: {
                b.buildRecursive(block: 1, of: 2)
            }, finallyBody: {
                b.buildRecursive(block: 2, of: 2)
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
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"]
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
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        guard let arguments = b.randCallArguments(forMethod: methodName, on: obj) else { return }
        let Reflect = b.reuseOrLoadBuiltin("Reflect")
        let args = b.createArray(with: arguments)
        b.callMethod("apply", on: Reflect, withArgs: [b.loadProperty(methodName, of: obj), this, args])
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

    RecursiveCodeGenerator("PromiseGenerator") { b in
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
    RecursiveCodeGenerator("WithStatementGenerator", input: .object()) { b, obj in
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

    RecursiveCodeGenerator("EvalGenerator") { b in
        let code = b.buildCodeString() {
            b.buildRecursive()
        }
        let eval = b.reuseOrLoadBuiltin("eval")
        b.callFunction(eval, withArgs: [code])
    },

    RecursiveCodeGenerator("BlockStatementGenerator") { b in
        b.blockStatement() {
            b.buildRecursive()
        }
    },

    CodeGenerator("NumberComputationGenerator") { b in
        // Generate a sequence of 3-7 random number computations on a couple of existing variables and some newly created constants.
        let numComputations = Int.random(in: 3...7)

        // Common mathematical operations are exposed through the Math builtin in JavaScript.
        let Math = b.reuseOrLoadBuiltin("Math")

        var values = b.randVars(upTo: Int.random(in: 1...3))
        for _ in 0..<Int.random(in: 1...2) {
            values.append(b.loadInt(b.genInt()))
        }
        for _ in 0..<Int.random(in: 0...1) {
            values.append(b.loadFloat(b.genFloat()))
        }

        for _ in 0..<numComputations {
            withEqualProbability({
                values.append(b.binary(chooseUniform(from: values), chooseUniform(from: values), with: chooseUniform(from: BinaryOperator.allCases)))
            }, {
                values.append(b.unary(chooseUniform(from: UnaryOperator.allCases), chooseUniform(from: values)))
            }, {
                // This can fail in tests, which lack the full JavaScriptEnvironment
                guard let method = b.type(of: Math).randomMethod() else { return }
                var args = [Variable]()
                for _ in 0..<b.methodSignature(of: method, on: Math).numParameters {
                    args.append(chooseUniform(from: values))
                }
                b.callMethod(method, on: Math, withArgs: args)
            })
        }
    },

    // TODO maybe this should be a ProgramTemplate instead?
    RecursiveCodeGenerator("JITFunctionGenerator") { b in
        let numIterations = 100

        let lastIteration = b.loadInt(Int64(numIterations) - 1)
        let numParameters = Int.random(in: 2...4)
        let f = b.buildPlainFunction(with: .parameters(n: numParameters)) { args in
            let i = args[0]
            b.buildIf(b.compare(i, with: lastIteration, using: .equal)) {
                b.buildRecursive(block: 1, of: 3, n: 3)
            }
            b.buildRecursive(block: 2, of: 3)
            b.doReturn(b.randVar())
        }
        b.buildRepeat(n: numIterations) { i in
            b.buildIf(b.compare(i, with: lastIteration, using: .equal)) {
                b.buildRecursive(block: 3, of: 3, n: 3)
            }
            var args = [i]
            for _ in 0..<numParameters - 1 {
                args.append(b.randVar())
            }
            b.callFunction(f, withArgs: args)
        }
    },

    CodeGenerator("ResizableArrayBufferGenerator", input: .anything) { b, v in
        let size = Int64.random(in: 0...0x1000)
        let maxSize = Int64.random(in: size...0x1000000)
        let ArrayBuffer = b.reuseOrLoadBuiltin("ArrayBuffer")
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.reuseOrLoadBuiltin(
            chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator("GrowableSharedArrayBufferGenerator", input: .anything) { b, v in
        let size = Int64.random(in: 0...0x1000)
        let maxSize = Int64.random(in: size...0x1000000)
        let ArrayBuffer = b.reuseOrLoadBuiltin("SharedArrayBuffer")
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.reuseOrLoadBuiltin(
            chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
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
