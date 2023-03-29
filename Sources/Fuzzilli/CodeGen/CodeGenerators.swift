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
    //
    // Value Generators: Code Generators that generate one or more new values.
    //
    // These behave like any other CodeGenerator in that they will be randomly chosen to generate code
    // and have a weight assigned to them to determine how frequently they are selected, but in addition
    // ValueGenerators are also used to "bootstrap" code generation by creating some initial variables
    // that following code can then operate on.
    //
    // These:
    //  - Must be able to run when there are no visible variables.
    //  - Together should cover all "interesting" types that generated programs should operate on.
    //  - Should generate |n| different values of the same type, but may generate fewer.
    //  - Should only generate values whose types can be inferred statically.
    //
    ValueGenerator("IntegerGenerator") { b, n in
        for _ in 0..<n {
            b.loadInt(b.randomInt())
        }
    },

    ValueGenerator("BigIntGenerator") { b, n in
        for _ in 0..<n {
            b.loadBigInt(b.randomInt())
        }
    },

    ValueGenerator("RegExpGenerator") { b, n in
        for _ in 0..<n {
            b.loadRegExp(b.randomRegExpPattern(), RegExpFlags.random())
        }
    },

    ValueGenerator("FloatGenerator") { b, n in
        for _ in 0..<n {
            b.loadFloat(b.randomFloat())
        }
    },

    ValueGenerator("StringGenerator") { b, n in
        for _ in 0..<n {
            b.loadString(b.randomString())
        }
    },

    ValueGenerator("BooleanGenerator") { b, n in
        // It's probably not too useful to generate multiple boolean values here.
        b.loadBool(Bool.random())
    },

    ValueGenerator("UndefinedGenerator") { b, n in
        // There is only one 'undefined' value, so don't generate it multiple times.
        b.loadUndefined()
    },

    ValueGenerator("NullGenerator") { b, n in
        // There is only one 'null' value, so don't generate it multiple times.
        b.loadNull()
    },

    ValueGenerator("ArrayGenerator") { b, n in
        // If we can only generate empty arrays, then only create one such array.
        if !b.hasVisibleVariables {
            b.createArray(with: [])
        } else {
            for _ in 0..<n {
                let initialValues = (0..<Int.random(in: 1...5)).map({ _ in b.randomVariable() })
                b.createArray(with: initialValues)
            }
        }
    },

    ValueGenerator("IntArrayGenerator") { b, n in
        for _ in 0..<n {
            let values = (0..<Int.random(in: 1...10)).map({ _ in b.randomInt() })
            b.createIntArray(with: values)
        }
    },

    ValueGenerator("FloatArrayGenerator") { b, n in
        for _ in 0..<n {
            let values = (0..<Int.random(in: 1...10)).map({ _ in b.randomFloat() })
            b.createFloatArray(with: values)
        }
    },

    ValueGenerator("BuiltinObjectInstanceGenerator") { b, n in
        let builtin = chooseUniform(from: ["Array", "Map", "WeakMap", "Set", "WeakSet", "Date"])
        let constructor = b.loadBuiltin(builtin)
        if builtin == "Array" {
            let size = b.loadInt(b.randomSize())
            b.construct(constructor, withArgs: [size])
        } else {
            // TODO could add arguments here if possible. Until then, just generate a single value.
            b.construct(constructor)
        }
    },

    ValueGenerator("TypedArrayGenerator") { b, n in
        for _ in 0..<n {
            let size = b.loadInt(b.randomSize())
            let constructor = b.loadBuiltin(
                chooseUniform(
                    from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"]
                )
            )
            b.construct(constructor, withArgs: [size])
        }
    },

    ValueGenerator("ObjectBuilderFunctionGenerator") { b, n in
        let maxProperties = 4
        assert(b.fuzzer.environment.customProperties.count >= maxProperties)
        let properties = Array(b.fuzzer.environment.customProperties.shuffled().prefix(Int.random(in: 1...maxProperties)))

        // TODO: can we support RecursiveValueGenerators instead and then replace this with the ObjectLiteralGenerator generator?
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            // TODO: we'll always have variables available here: the function we're generating. Maybe we should somehow "hide" that variable since it's not super useful.
            var values = b.randomVariables(upTo: properties.count)
            while values.count < properties.count {
                // For now just use random integer properties if there are no/not enough visible variables.
                values.append(b.loadInt(b.randomInt()))
            }
            let o = b.buildObjectLiteral { obj in
                for (property, value) in zip(properties, values) {
                    obj.addProperty(property, as: value)
                }
            }
            b.doReturn(o)
        }

        assert(b.type(of: f).signature != nil)
        assert(b.type(of: f).signature!.outputType.Is(.object(withProperties: properties)))

        for _ in 0..<n {
            let args = b.randomArguments(forCalling: f)
            b.callFunction(f, withArgs: args)
        }
    },

    ValueGenerator("ObjectConstructorGenerator") { b, n in
        let maxProperties = 4
        assert(b.fuzzer.environment.customProperties.count >= maxProperties)
        let properties = Array(b.fuzzer.environment.customProperties.shuffled().prefix(Int.random(in: 1...maxProperties)))

        // TODO: same Q as above
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            // TODO: we'll always have variables available here: the function we're generating and |this|. Maybe we should somehow "hide" these variables since they're not super useful.
            let this = args[0]
            var values = b.randomVariables(upTo: properties.count)
            while values.count < properties.count {
                // For now just use random integer properties if there are no/not enough visible variables.
                values.append(b.loadInt(b.randomInt()))
            }
            for (property, value) in zip(properties, values) {
                b.setProperty(property, of: this, to: value)
            }
        }

        assert(b.type(of: c).signature != nil)
        assert(b.type(of: c).signature!.outputType.Is(.object(withProperties: properties)))

        for _ in 0..<n {
            let args = b.randomArguments(forCalling: c)
            b.construct(c, withArgs: args)
        }
    },

    // TODO: do we also want a ObjectClassGenerator?

    ValueGenerator("TrivialFunctionGenerator") { b, n in
        // Generating more than one function has a fairly high probability of generating
        // essentially identical functions, so we just generate one.
        let maybeReturnValue = b.hasVisibleVariables ? b.randomVariable() : nil
        b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            if let returnValue = maybeReturnValue {
                b.doReturn(returnValue)
            }
        }
    },

    //
    // "Regular" Code Generators.
    //
    // These are used to generate all sorts of code constructs, from simple values to
    // complex control-flow. They can also perform recursive code generation, for
    // example to generate code to fill the bodies of generated blocks. Further, these
    // generators may fail and produce no code at all.
    //
    // Regular code generators can assume that there are visible variables that can
    // be used as inputs, and they can request to receive input variables of particular
    // types. These input types should be chosen in a way that leads to the generation
    // of "meaningful" code, but the generators should still be able to produce correct
    // code (i.e. code that doesn't result in a runtime exception) if they receive
    // input values of different types.
    // For example, when generating a property load, the input type should be .object()
    // (so that the property load is meaningful), but if the input type may be null or
    // undefined, the property load should be guarded (i.e. use `?.` instead of `.`) to
    // avoid raising an exception at runtime.
    //

    CodeGenerator("ThisGenerator") { b in
        b.loadThis()
    },

    CodeGenerator("ArgumentsGenerator", inContext: .subroutine) { b in
        assert(b.context.contains(.subroutine))
        b.loadArguments()
    },

    RecursiveCodeGenerator("ObjectLiteralGenerator") { b in
        b.buildObjectLiteral() { obj in
            b.buildRecursive()
        }
    },

    CodeGenerator("ObjectLiteralPropertyGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added to this literal.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentObjectLiteral.hasProperty(propertyName)

        b.currentObjectLiteral.addProperty(propertyName, as: b.randomVariable())
    },

    CodeGenerator("ObjectLiteralElementGenerator", inContext: .objectLiteral, input: .anything) { b, value in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentObjectLiteral.hasElement(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        b.currentObjectLiteral.addElement(index, as: value)
    },

    CodeGenerator("ObjectLiteralComputedPropertyGenerator", inContext: .objectLiteral, input: .anything) { b, value in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomVariable()
            attempts += 1
        } while b.currentObjectLiteral.hasComputedProperty(propertyName)

        b.currentObjectLiteral.addComputedProperty(propertyName, as: value)
    },

    CodeGenerator("ObjectLiteralCopyPropertiesGenerator", inContext: .objectLiteral, input: .object()) { b, object in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))
        b.currentObjectLiteral.copyProperties(from: object)
    },

    CodeGenerator("ObjectLiteralPrototypeGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // There should only be one __proto__ field in an object literal.
        guard !b.currentObjectLiteral.hasPrototype else { return }

        let proto = b.randomVariable(forUseAs: .object()) ?? b.randomVariable()
        b.currentObjectLiteral.setPrototype(to: proto)
    },

    RecursiveCodeGenerator("ObjectLiteralMethodGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a method that hasn't already been added to this literal.
        var methodName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomCustomMethodName()
            attempts += 1
        } while b.currentObjectLiteral.hasMethod(methodName)

        b.currentObjectLiteral.addMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ObjectLiteralComputedMethodGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a computed method name that hasn't already been added to this literal.
        var methodName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomVariable()
            attempts += 1
        } while b.currentObjectLiteral.hasComputedMethod(methodName)

        b.currentObjectLiteral.addComputedMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ObjectLiteralGetterGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentObjectLiteral.hasProperty(propertyName) || b.currentObjectLiteral.hasGetter(for: propertyName)

        b.currentObjectLiteral.addGetter(for: propertyName) { this in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ObjectLiteralSetterGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentObjectLiteral.hasProperty(propertyName) || b.currentObjectLiteral.hasSetter(for: propertyName)

        b.currentObjectLiteral.addSetter(for: propertyName) { this, v in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ClassDefinitionGenerator") { b in
        // Possibly pick a superclass
        var superclass: Variable? = nil
        if probability(0.5) {
            // The superclass must be a constructor (or null), otherwise a type error will be raised at runtime.
            superclass = b.randomVariable(ofType: .constructor())
        }

        b.buildClassDefinition(withSuperclass: superclass) { cls in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ClassConstructorGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        guard !b.currentClassDefinition.hasConstructor else {
            // There must only be one constructor
            return
        }

        b.currentClassDefinition.addConstructor(with: b.randomParameters()) { _ in
            // Derived classes must call `super()` before accessing this, but non-derived classes must not call `super()`.
            if b.currentClassDefinition.isDerivedClass {
                let signature = b.currentSuperConstructorType().signature ?? Signature.forUnknownFunction
                let args = b.randomArguments(forCallingFunctionOfSignature: signature)
                b.callSuperConstructor(withArgs: args)
            }
            b.buildRecursive()
        }
    },

    CodeGenerator("ClassInstancePropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added to this literal.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasInstanceProperty(propertyName)

        var value: Variable? = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addInstanceProperty(propertyName, value: value)
    },

    CodeGenerator("ClassInstanceElementGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.hasInstanceElement(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        let value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addInstanceElement(index, value: value)
    },

    CodeGenerator("ClassInstanceComputedPropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomVariable()
            attempts += 1
        } while b.currentClassDefinition.hasInstanceComputedProperty(propertyName)

        let value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addInstanceComputedProperty(propertyName, value: value)
    },

    RecursiveCodeGenerator("ClassInstanceMethodGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a method that hasn't already been added to this class.
        var methodName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomCustomMethodName()
            attempts += 1
        } while b.currentClassDefinition.hasInstanceMethod(methodName)

        b.currentClassDefinition.addInstanceMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ClassInstanceGetterGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasInstanceProperty(propertyName) || b.currentClassDefinition.hasInstanceGetter(for: propertyName)

        b.currentClassDefinition.addInstanceGetter(for: propertyName) { this in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ClassInstanceSetterGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasInstanceProperty(propertyName) || b.currentClassDefinition.hasInstanceSetter(for: propertyName)

        b.currentClassDefinition.addInstanceSetter(for: propertyName) { this, v in
            b.buildRecursive()
        }
    },

    CodeGenerator("ClassStaticPropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added to this literal.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasStaticProperty(propertyName)

        var value: Variable? = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addStaticProperty(propertyName, value: value)
    },

    CodeGenerator("ClassStaticElementGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.hasStaticElement(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        let value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addStaticElement(index, value: value)
    },

    CodeGenerator("ClassStaticComputedPropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomVariable()
            attempts += 1
        } while b.currentClassDefinition.hasStaticComputedProperty(propertyName)

        let value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addStaticComputedProperty(propertyName, value: value)
    },

    RecursiveCodeGenerator("ClassStaticInitializerGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        b.currentClassDefinition.addStaticInitializer { this in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ClassStaticMethodGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a method that hasn't already been added to this class.
        var methodName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomCustomMethodName()
            attempts += 1
        } while b.currentClassDefinition.hasStaticMethod(methodName)

        b.currentClassDefinition.addStaticMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ClassStaticGetterGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasStaticProperty(propertyName) || b.currentClassDefinition.hasStaticGetter(for: propertyName)

        b.currentClassDefinition.addStaticGetter(for: propertyName) { this in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    RecursiveCodeGenerator("ClassStaticSetterGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasStaticProperty(propertyName) || b.currentClassDefinition.hasStaticSetter(for: propertyName)

        b.currentClassDefinition.addStaticSetter(for: propertyName) { this, v in
            b.buildRecursive()
        }
    },

    CodeGenerator("ClassPrivateInstancePropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a private field that hasn't already been added to this literal.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasPrivateField(propertyName)

        var value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addPrivateInstanceProperty(propertyName, value: value)
    },

    RecursiveCodeGenerator("ClassPrivateInstanceMethodGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a private field that hasn't already been added to this class.
        var methodName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomCustomMethodName()
            attempts += 1
        } while b.currentClassDefinition.hasPrivateField(methodName)

        b.currentClassDefinition.addPrivateInstanceMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    CodeGenerator("ClassPrivateStaticPropertyGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a private field that hasn't already been added to this literal.
        var propertyName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomCustomPropertyName()
            attempts += 1
        } while b.currentClassDefinition.hasPrivateField(propertyName)

        var value = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addPrivateStaticProperty(propertyName, value: value)
    },

    RecursiveCodeGenerator("ClassPrivateStaticMethodGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Try to find a private field that hasn't already been added to this class.
        var methodName: String
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            methodName = b.randomCustomMethodName()
            attempts += 1
        } while b.currentClassDefinition.hasPrivateField(methodName)

        b.currentClassDefinition.addPrivateStaticMethod(methodName, with: b.randomParameters()) { args in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
    },

    CodeGenerator("ArrayWithSpreadGenerator") { b in
        var initialValues = [Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            initialValues.append(b.randomVariable())
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
            interpolatedValues.append(b.randomVariable())
        }

        var parts = [String]()
        for _ in 0...interpolatedValues.count {
            // For now we generate random strings
            parts.append(b.randomString())
        }
        b.createTemplateString(from: parts, interpolating: interpolatedValues)
    },

    CodeGenerator("StringNormalizeGenerator") { b in
        let form = b.loadString(
            chooseUniform(
                from: ["NFC", "NFD", "NFKC", "NFKD"]
            )
        )
        let string = b.loadString(b.randomString())
        b.callMethod("normalize", on: string, withArgs: [form])
    },

    // We don't treat this as a ValueGenerator since it doesn't create a new value, it only accesses an existing one.
    CodeGenerator("BuiltinGenerator") { b in
        b.loadBuiltin(b.randomBuiltin())
    },

    RecursiveCodeGenerator("PlainFunctionGenerator") { b in
        let f = b.buildPlainFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("ArrowFunctionGenerator") { b in
        b.buildArrowFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("GeneratorFunctionGenerator") { b in
        let f = b.buildGeneratorFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            if probability(0.5) {
                b.yield(b.randomVariable())
            } else {
                b.yieldEach(b.randomVariable())
            }
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("AsyncFunctionGenerator") { b in
        let f = b.buildAsyncFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("AsyncArrowFunctionGenerator") { b in
        b.buildAsyncArrowFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            b.doReturn(b.randomVariable())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("AsyncGeneratorFunctionGenerator") { b in
        let f = b.buildAsyncGeneratorFunction(with: b.randomParameters(), isStrict: probability(0.1)) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            if probability(0.5) {
                b.yield(b.randomVariable())
            } else {
                b.yieldEach(b.randomVariable())
            }
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    CodeGenerator("PropertyRetrievalGenerator", input: .object()) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("PropertyAssignmentGenerator", input: .object()) { b, obj in
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // If this is an existing property with a specific type, try to find a variable with a matching type.
        var propertyType = b.type(ofProperty: propertyName, on: obj)
        assert(propertyType == .anything || b.type(of: obj).properties.contains(propertyName))
        guard let value = b.randomVariable(forUseAs: propertyType) else { return }

        // TODO: (here and below) maybe wrap in try catch if obj may be nullish?
        b.setProperty(propertyName, of: obj, to: value)
    },

    CodeGenerator("PropertyUpdateGenerator", input: .object()) { b, obj in
        let propertyName: String
        // Change an existing property
        propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number) ?? b.randomVariable()
        b.updateProperty(propertyName, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("PropertyRemovalGenerator", input: .object()) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteProperty(propertyName, of: obj, guard: true)
    },

    CodeGenerator("PropertyConfigurationGenerator", input: .object()) { b, obj in
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.25) {
            propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // Getter/Setters must be functions or else a runtime exception will be raised.
        withEqualProbability({
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getterSetter(getterFunc, setterFunc))
        })
    },

    CodeGenerator("ElementRetrievalGenerator", input: .object()) { b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator("ElementAssignmentGenerator", input: .object()) { b, obj in
        let index = b.randomIndex()
        let value = b.randomVariable()
        b.setElement(index, of: obj, to: value)
    },

    CodeGenerator("ElementUpdateGenerator", input: .object()) { b, obj in
        let index = b.randomIndex()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number) ?? b.randomVariable()
        b.updateElement(index, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ElementRemovalGenerator", input: .object()) { b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator("ElementConfigurationGenerator", input: .object()) { b, obj in
        let index = b.randomIndex()
        withEqualProbability({
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureElement(index, of: obj, usingFlags: PropertyFlags.random(), as: .getterSetter(getterFunc, setterFunc))
        })
    },

    CodeGenerator("ComputedPropertyRetrievalGenerator", input: .object()) { b, obj in
        let propertyName = b.randomVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("ComputedPropertyAssignmentGenerator", input: .object()) { b, obj in
        let propertyName = b.randomVariable()
        let value = b.randomVariable()
        b.setComputedProperty(propertyName, of: obj, to: value)
    },

    CodeGenerator("ComputedPropertyUpdateGenerator", input: .object()) { b, obj in
        let propertyName = b.randomVariable()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number) ?? b.randomVariable()
        b.updateComputedProperty(propertyName, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ComputedPropertyRemovalGenerator", input: .object()) { b, obj in
        let propertyName = b.randomVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("ComputedPropertyConfigurationGenerator", input: .object()) { b, obj in
        let propertyName = b.randomVariable()
        withEqualProbability({
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .getter(getterFunc))
        }, {
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
            b.configureComputedProperty(propertyName, of: obj, usingFlags: PropertyFlags.random(), as: .setter(setterFunc))
        }, {
            guard let getterFunc = b.randomVariable(ofType: .function()) else { return }
            guard let setterFunc = b.randomVariable(ofType: .function()) else { return }
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
        let prop = b.randomVariable()
        b.testIn(prop, obj)
    },

    CodeGenerator("MethodCallGenerator", input: .object()) { b, obj in
        if let methodName = b.type(of: obj).randomMethod() {
            // TODO: here and below, if we aren't finding arguments of compatible types, we probably still need a try-catch guard.
            let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
            b.callMethod(methodName, on: obj, withArgs: arguments)
        } else {
            // Wrap the call into try-catch as there is a large probability that it'll be invalid and cause an exception.
            // If it is valid, the try-catch will probably be removed by the minimizer later on.
            let methodName = b.randomMethodName()
            let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
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

        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callMethod(methodName, on: obj, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("ComputedMethodCallGenerator", input: .object()) { b, obj in
        if let methodName = b.type(of: obj).randomMethod() {
            let method = b.loadString(methodName)
            let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
            b.callComputedMethod(method, on: obj, withArgs: arguments)
        } else {
            let methodName = b.randomMethodName()
            let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
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
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callComputedMethod(method, on: obj, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("FunctionCallGenerator", input: .function()) { b, f in
        let arguments = b.randomArguments(forCalling: f)
        if b.type(of: f).Is(.function()) {
            b.callFunction(f, withArgs: arguments)
        } else {
            b.buildTryCatchFinally(tryBody: {
                b.callFunction(f, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("ConstructorCallGenerator", input: .constructor()) { b, c in
        let arguments = b.randomArguments(forCalling: c)
        if b.type(of: c).Is(.constructor()) {
            b.construct(c, withArgs: arguments)
        } else {
            b.buildTryCatchFinally(tryBody: {
                b.construct(c, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("FunctionCallWithSpreadGenerator", input: .function()) { b, f in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.callFunction(f, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("ConstructorCallWithSpreadGenerator", input: .constructor()) { b, c in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading is likely to lead to a runtime exception if the argument isn't iterable, so wrap this in try-catch.
        b.buildTryCatchFinally(tryBody: {
            b.construct(c, withArgs: arguments, spreading: spreads)
        }, catchBody: { _ in })
    },

    CodeGenerator("SubroutineReturnGenerator", inContext: .subroutine, input: .anything) { b, val in
        assert(b.context.contains(.subroutine))
        if probability(0.9) {
            b.doReturn(val)
        } else {
            b.doReturn()
        }
    },

    CodeGenerator("YieldGenerator", inContext: .generatorFunction, input: .anything) { b, val in
        assert(b.context.contains(.generatorFunction))
        if probability(0.5) {
            if probability(0.9) {
                b.yield(val)
            } else {
                b.yield()
            }
        } else {
            // TODO only do this when the value is iterable?
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

    CodeGenerator("TernaryOperationGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        let condition = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.ternary(condition, lhs, rhs)
    },

    CodeGenerator("UpdateGenerator", input: .anything) { b, val in
        let target = b.randomVariable()
        b.reassign(target, to: val, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("DupGenerator") { b in
        b.dup(b.randomVariable())
    },

    CodeGenerator("ReassignmentGenerator", input: .anything) { b, val in
        // TODO try to find a replacement with a compatible type and make sure it's a different variable.
        let target = b.randomVariable()
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

        b.destruct(arr, selecting: indices, lastIsRest: probability(0.33))
    },

    CodeGenerator("DestructArrayAndReassignGenerator", input: .iterable) {b, arr in
        var candidates: [Variable] = []
        var indices: [Int64] = []
        for idx in 0..<Int64.random(in: 0..<5) {
            withProbability(0.7) {
                indices.append(idx)
                candidates.append(b.randomVariable())
            }
        }
        b.destruct(arr, selecting: indices, into: candidates, lastIsRest: probability(0.33))
    },

    CodeGenerator("DestructObjectGenerator", input: .object()) { b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).randomProperty(), !properties.contains(prop) {
                properties.insert(prop)
            } else {
                properties.insert(b.randomCustomPropertyName())
            }
        }

        b.destruct(obj, selecting: properties.sorted(), hasRestElement: probability(0.33))
    },

    CodeGenerator("DestructObjectAndReassignGenerator", input: .object()) { b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).randomProperty(), !properties.contains(prop) {
                properties.insert(prop)
            } else {
                properties.insert(b.randomCustomPropertyName())
            }
        }

        var candidates = properties.map{ _ in
            b.randomVariable()
        }

        let hasRestElement = probability(0.33)
        if hasRestElement {
            candidates.append(b.randomVariable())
        }

        b.destruct(obj, selecting: properties.sorted(), into: candidates, hasRestElement: hasRestElement)
    },

    CodeGenerator("ComparisonGenerator", inputs: (.anything, .anything)) { b, lhs, rhs in
        b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
    },

    CodeGenerator("SuperMethodCallGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        if let methodName = superType.randomMethod() {
            let arguments = b.randomArguments(forCallingMethod: methodName, on: superType)
            b.callSuperMethod(methodName, withArgs: arguments)
        } else {
            // Wrap the call into try-catch as there's a large probability that it will be invalid and cause an exception.
            let methodName = b.randomMethodName()
            let arguments = b.randomArguments(forCallingMethod: methodName, on: superType)
            b.buildTryCatchFinally(tryBody: {
                b.callSuperMethod(methodName, withArgs: arguments)
            }, catchBody: { _ in })
        }
    },

    CodeGenerator("PrivatePropertyRetrievalGenerator", inContext: .classMethod, input: .object()) { b, obj in
        // Accessing a private class property that has not been declared in the active class definition is a syntax error (i.e. wrapping the access in try-catch doesn't help).
        // As such, we're using the active class definition object to obtain the list of private property names that are guaranteed to exist in the class that is currently being defined.
        guard !b.currentClassDefinition.existingPrivateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.existingPrivateProperties)
        // Since we don't know whether the private property will exist or not (we don't track private properties in our type inference),
        // always wrap these accesses in try-catch since they'll be runtime type errors if the property doesn't exist.
        b.buildTryCatchFinally(tryBody: {
            b.getPrivateProperty(propertyName, of: obj)
        }, catchBody: { e in })
    },

    CodeGenerator("PrivatePropertyAssignmentGenerator", inContext: .classMethod, inputs: (.object(), .anything)) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.existingPrivateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.existingPrivateProperties)
        b.buildTryCatchFinally(tryBody: {
            b.setPrivateProperty(propertyName, of: obj, to: value)
        }, catchBody: { e in })
    },

    CodeGenerator("PrivatePropertyUpdateGenerator", inContext: .classMethod, inputs: (.object(), .anything)) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.existingPrivateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.existingPrivateProperties)
        b.buildTryCatchFinally(tryBody: {
            b.updatePrivateProperty(propertyName, of: obj, with: value, using: chooseUniform(from: BinaryOperator.allCases))
        }, catchBody: { e in })
    },

    CodeGenerator("PrivateMethodCallGenerator", inContext: .classMethod, input: .object()) { b, obj in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.existingPrivateMethods.isEmpty else { return }
        let methodName = chooseUniform(from: b.currentClassDefinition.existingPrivateMethods)
        b.buildTryCatchFinally(tryBody: {
            let args = b.randomArguments(forCallingFunctionOfSignature: Signature.forUnknownFunction)
            b.callPrivateMethod(methodName, on: obj, withArgs: args)
        }, catchBody: { e in })
    },

    CodeGenerator("SuperPropertyRetrievalGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        // Emit a property load
        let propertyName = superType.randomProperty() ?? b.randomCustomPropertyName()
        b.getSuperProperty(propertyName)
    },

    CodeGenerator("SuperPropertyAssignmentGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName = superType.randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // TODO: we could try to determine if the type of this property is known and then try to find a compatible variable.
        b.setSuperProperty(propertyName, to: b.randomVariable())
    },

    CodeGenerator("SuperPropertyUpdateGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        let propertyName = superType.randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number) ?? b.randomVariable()
        b.updateSuperProperty(propertyName, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
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
            candidates.append(b.randomVariable())
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
        let loopVar = b.loadInt(0)
        b.buildWhileLoop({ b.compare(loopVar, with: b.loadInt(Int64.random(in: 0...10)), using: .lessThan) }) {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }
    },

    RecursiveCodeGenerator("DoWhileLoopGenerator") { b in
        let loopVar = b.loadInt(0)
        b.buildDoWhileLoop(do: {
            b.buildRecursive()
            b.unary(.PostInc, loopVar)
        }, while: { b.compare(loopVar, with: b.loadInt(Int64.random(in: 0...10)), using: .lessThan) })
    },

    RecursiveCodeGenerator("SimpleForLoopGenerator") { b in
        b.buildForLoop(i: { b.loadInt(0) }, { i in b.compare(i, with: b.loadInt(Int64.random(in: 0...10)), using: .lessThan) }, { i in b.unary(.PostInc, i) }) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ComplexForLoopGenerator") { b in
        if probability(0.5) {
            // Generate a for-loop without any loop variables.
            let counter = b.loadInt(10)
            b.buildForLoop({}, { b.unary(.PostDec, counter) }) {
                b.buildRecursive()
            }
        } else {
            // Generate a for-loop with two loop variables.
            // TODO could also generate loops with even more loop variables?
            b.buildForLoop({ return [b.loadInt(0), b.loadInt(10)] }, { vs in b.compare(vs[0], with: vs[1], using: .lessThan) }, { vs in b.unary(.PostInc, vs[0]); b.unary(.PostDec, vs[0]) }) { _ in
                b.buildRecursive()
            }
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
        b.buildRepeatLoop(n: numIterations) { _ in
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
        let v = b.randomVariable()
        b.throwException(v)
    },

    //
    // Language-specific Generators
    //

    CodeGenerator("WellKnownPropertyLoadGenerator", input: .object()) { b, obj in
        let Symbol = b.loadBuiltin("Symbol")
        let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
        let propertyName = b.getProperty(name, of: Symbol)
        b.getComputedProperty(propertyName, of: obj)
    },

    CodeGenerator("WellKnownPropertyStoreGenerator", input: .object()) { b, obj in
        let Symbol = b.loadBuiltin("Symbol")
        let name = chooseUniform(from: ["isConcatSpreadable", "iterator", "match", "replace", "search", "species", "split", "toPrimitive", "toStringTag", "unscopables"])
        let propertyName = b.getProperty(name, of: Symbol)
        let val = b.randomVariable()
        b.setComputedProperty(propertyName, of: obj, to: val)
    },

    CodeGenerator("PrototypeAccessGenerator", input: .object()) { b, obj in
        b.getProperty("__proto__", of: obj)
    },

    CodeGenerator("PrototypeOverwriteGenerator", inputs: (.object(), .object())) { b, obj, proto in
        b.setProperty("__proto__", of: obj, to: proto)
    },

    CodeGenerator("CallbackPropertyGenerator", inputs: (.object(), .function())) { b, obj, callback in
        // TODO add new callbacks like Symbol.toPrimitive?
        let propertyName = chooseUniform(from: ["valueOf", "toString"])
        b.setProperty(propertyName, of: obj, to: callback)
    },

    CodeGenerator("MethodCallWithDifferentThisGenerator", inputs: (.object(), .object())) { b, obj, this in
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        let Reflect = b.loadBuiltin("Reflect")
        let args = b.createArray(with: arguments)
        b.callMethod("apply", on: Reflect, withArgs: [b.getProperty(methodName, of: obj), this, args])
    },

    RecursiveCodeGenerator("WeirdClassGenerator") { b in
        // See basically https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Classes/Private_class_fields#examples
        let base = b.buildPlainFunction(with: .parameters(n: 1)) { args in
            b.doReturn(b.randomVariable())
        }
        b.buildClassDefinition(withSuperclass: base) { cls in
            b.buildRecursive()
        }
    },

    CodeGenerator("ProxyGenerator", input: .object()) { b, target in
        var candidates = Set(["getPrototypeOf", "setPrototypeOf", "isExtensible", "preventExtensions", "getOwnPropertyDescriptor", "defineProperty", "has", "get", "set", "deleteProperty", "ownKeys", "apply", "call", "construct"])

        var handlerProperties = [String: Variable]()
        for _ in 0..<Int.random(in: 0..<candidates.count) {
            let hook = chooseUniform(from: candidates)
            candidates.remove(hook)
            handlerProperties[hook] = b.randomVariable(ofType: .function())
        }
        let handler = b.createObject(with: handlerProperties)

        let Proxy = b.loadBuiltin("Proxy")

        b.construct(Proxy, withArgs: [target, handler])
    },

    RecursiveCodeGenerator("PromiseGenerator") { b in
        let handler = b.buildPlainFunction(with: .parameters(n: 2)) { _ in
            // TODO could provide type hints here for the parameters.
            b.buildRecursive()
        }
        let promiseConstructor = b.loadBuiltin("Promise")
        b.construct(promiseConstructor, withArgs: [handler])
    },

    // Tries to change the length property of some object
    CodeGenerator("LengthChangeGenerator", input: .object()) { b, obj in
        let newLength: Variable
        if probability(0.5) {
            // Shrink
            newLength = b.loadInt(Int64.random(in: 0..<3))
        } else {
            // (Probably) grow
            newLength = b.loadInt(b.randomIndex())
        }
        b.setProperty("length", of: obj, to: newLength)
    },

    // Tries to change the element kind of an array
    CodeGenerator("ElementKindChangeGenerator", input: .anything) { b, obj in
        let value = b.randomVariable()
        b.setElement(Int64.random(in: 0..<10), of: obj, to: value)
    },

    // Generates a JavaScript 'with' statement
    RecursiveCodeGenerator("WithStatementGenerator", input: .object()) { b, obj in
        b.buildWith(obj) {
            withProbability(0.5, do: { () -> Void in
                let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
                b.loadNamedVariable(propertyName)
            }, else: { () -> Void in
                let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
                let value = b.randomVariable()
                b.storeNamedVariable(propertyName, value)
            })
            b.buildRecursive()
        }
    },

    CodeGenerator("NamedVariableLoadGenerator") { b in
        // We're using the custom property names set from the environment for named variables.
        // It's not clear if there's something better since that set should be relatively small
        // (increasing the probability that named variables will be reused), and it also makes
        // sense to use property names if we're inside a `with` statement.
        b.loadNamedVariable(b.randomCustomPropertyName())
    },

    CodeGenerator("NamedVariableStoreGenerator") { b in
        let value = b.randomVariable()
        b.storeNamedVariable(b.randomCustomPropertyName(), value)
    },

    CodeGenerator("NamedVariableDefinitionGenerator") { b in
        let value = b.randomVariable()
        b.defineNamedVariable(b.randomCustomPropertyName(), value)
    },

    RecursiveCodeGenerator("EvalGenerator") { b in
        let code = b.buildCodeString() {
            b.buildRecursive()
        }
        let eval = b.loadBuiltin("eval")
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
        let Math = b.loadBuiltin("Math")

        var values = b.randomVariables(upTo: Int.random(in: 1...3))
        for _ in 0..<Int.random(in: 1...2) {
            values.append(b.loadInt(b.randomInt()))
        }
        for _ in 0..<Int.random(in: 0...1) {
            values.append(b.loadFloat(b.randomFloat()))
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

    RecursiveCodeGenerator("ImitationGenerator", input: .anything) { b, orig in
        // Build an object that imitates the given value.
        // The newly created object can be used in place of the original value, but may behave
        // differently in subtle (or less subtle) ways. For example it may behave like a primitive
        // value but execute arbitrary code when accessed via a valueOf/toPrimitive callback. Or it
        // may behave like a builtin object type (e.g. plain Array or TypedArray) but may use a
        // different internal representation.
        let imitation: Variable

        if b.type(of: orig).Is(.primitive) {
            // Create an object with either a 'valueOf' or '@@toPrimitive' callback returning the original value.
            if probability(0.5) {
                imitation = b.buildObjectLiteral { obj in
                    obj.addMethod("valueOf", with: .parameters(n: 0)) { _ in
                        b.buildRecursive(n: 3)
                        b.doReturn(orig)
                    }
                }
            } else {
                let toPrimitive = b.getProperty("toPrimitive", of: b.loadBuiltin("Symbol"))
                imitation = b.buildObjectLiteral { obj in
                    obj.addComputedMethod(toPrimitive, with: .parameters(n: 0)) { _ in
                        b.buildRecursive(n: 3)
                        b.doReturn(orig)
                    }
                }
            }
        } else if b.type(of: orig).Is(.function() | .constructor()) {
            // Wrap the original value in a proxy with no handlers. The ProbingMutator should be able to add relevant handlers later on.
            // A lot of functions are also objects, so we could handle them either way. However, it probably makes more sense to handle
            // them as a function since they would otherwise no longer be callable.
            let handler = b.createObject(with: [:])
            let Proxy = b.loadBuiltin("Proxy")
            imitation = b.construct(Proxy, withArgs: [orig, handler])
        } else if b.type(of: orig).Is(.object()) {
            // Either make a class that extends that object's constructor or make a new object with the original object as prototype.
            if probability(0.5) {
                let constructor = b.getProperty("constructor", of: orig)
                let cls = b.buildClassDefinition(withSuperclass: constructor) { _ in
                    b.buildRecursive(n: 3)
                }
                imitation = b.construct(cls, withArgs: b.randomArguments(forCalling: cls))
            } else {
                imitation = b.buildObjectLiteral { obj in
                    obj.setPrototype(to: orig)
                    b.buildRecursive(n: 3)
                }
            }
        }  else {
            // The type of the input value is probably unknown (or a weird union) that can anyway not be used very meaningfully,
            // so it's probably not worth trying to imitate it somehow.
            return
        }

        // Explicitly set the type of the imitation to that of the original value as the static type inference will usually
        // not be able to figure out that they are compatible. Also in case the original value is a primitive value, the imitation
        // will (correctly) be determined to be a .object(), but we don't actually want that here, so we override the type.
        b.setType(ofVariable: imitation, to: b.type(of: orig))
        assert(b.type(of: imitation) == b.type(of: orig))
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
            b.doReturn(b.randomVariable())
        }
        b.buildRepeatLoop(n: numIterations) { i in
            b.buildIf(b.compare(i, with: lastIteration, using: .equal)) {
                b.buildRecursive(block: 3, of: 3, n: 3)
            }
            var args = [i]
            for _ in 0..<numParameters - 1 {
                args.append(b.randomVariable())
            }
            b.callFunction(f, withArgs: args)
        }
    },

    CodeGenerator("ResizableArrayBufferGenerator", input: .anything) { b, v in
        let size = b.randomSize()
        var maxSize = b.randomSize()
        if maxSize < size {
            maxSize = size
        }
        let ArrayBuffer = b.loadBuiltin("ArrayBuffer")
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.loadBuiltin(
            chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator("GrowableSharedArrayBufferGenerator", input: .anything) { b, v in
        let size = b.randomSize()
        var maxSize = b.randomSize()
        if maxSize < size {
            maxSize = size
        }
        let ArrayBuffer = b.loadBuiltin("SharedArrayBuffer")
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.loadBuiltin(
            chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator("FastToSlowPropertiesGenerator", input: .object()) {b, o in
        // Build a loop that adds computed properties to an object which forces its
        // properties to transition from "fast properties" to "slow properties".
        // 32 seems to be enough for V8, which seems to be controlled by
        // kFastPropertiesSoftLimit.
        b.buildRepeatLoop(n: 32) { i in
            let prefixStr = b.loadString("p");
            let propertyName = b.binary(prefixStr, i, with: .Add)
            b.setComputedProperty(propertyName, of: o, to: i)
        }
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
