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
    //  - Must only generate values whose types can be inferred statically.
    //  - Should generate |n| different values of the same type, but may generate fewer.
    //  - May be recursive, for example to fill bodies of newly created blocks.
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
        let constructor = b.createNamedVariable(forBuiltin: builtin)
        if builtin == "Array" {
            let size = b.loadInt(b.randomSize(upTo: 0x1000))
            b.construct(constructor, withArgs: [size])
        } else {
            // TODO could add arguments here if possible. Until then, just generate a single value.
            b.construct(constructor)
        }
    },

    ValueGenerator("TypedArrayGenerator") { b, n in
        for _ in 0..<n {
            let size = b.loadInt(b.randomSize(upTo: 0x1000))
            let constructor = b.createNamedVariable(
                forBuiltin: chooseUniform(
                    from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array"]
                )
            )
            b.construct(constructor, withArgs: [size])
        }
    },

    ValueGenerator("RegExpGenerator") { b, n in
        // TODO: this could be a ValueGenerator but currently has a fairly high failure rate.
        for _ in 0..<n {
            let (regexpPattern, flags) = b.randomRegExpPatternAndFlags()
            b.loadRegExp(regexpPattern, flags)
        }
    },

    RecursiveValueGenerator("ObjectBuilderFunctionGenerator") { b, n in
        var objType = ILType.object()
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            if !b.hasVisibleVariables {
                // Just create some random number- or string values for the object to use.
                for _ in 0..<3 {
                    withEqualProbability({
                        b.loadInt(b.randomInt())
                    }, {
                        b.loadFloat(b.randomFloat())
                    }, {
                        b.loadString(b.randomString())
                    })
                }
            }

            let o = b.buildObjectLiteral() { obj in
                b.buildRecursive()
                // TODO: it would be nice if our type inference could figure out getters/setters as well.
                objType = .object(withProperties: obj.properties, withMethods: obj.methods)
            }

            b.doReturn(o)
        }

        assert(b.type(of: f).signature != nil)
        assert(b.type(of: f).signature!.outputType.Is(objType))

        for _ in 0..<n {
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }
    },

    ValueGenerator("ObjectConstructorGenerator") { b, n in
        let maxProperties = 3
        assert(b.fuzzer.environment.customProperties.count >= maxProperties)
        let properties = Array(b.fuzzer.environment.customProperties.shuffled().prefix(Int.random(in: 1...maxProperties)))

        // Define a constructor function...
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]

            // We don't want |this| to be used as property value, so hide it.
            b.hide(this)

            // Add a few random properties to the |this| object.
            for property in properties {
                let value = b.hasVisibleVariables ? b.randomVariable() : b.loadInt(b.randomInt())
                b.setProperty(property, of: this, to: value)
            }
        }

        assert(b.type(of: c).signature != nil)
        assert(b.type(of: c).signature!.outputType.Is(.object(withProperties: properties)))

        // and create a few instances with it.
        for _ in 0..<n {
            b.construct(c, withArgs: b.randomArguments(forCalling: c))
        }
    },

    RecursiveValueGenerator("ClassDefinitionGenerator") { b, n in
        // Possibly pick a superclass. The superclass must be a constructor (or null), otherwise a type error will be raised at runtime.
        var superclass: Variable? = nil
        if probability(0.5) && b.hasVisibleVariables {
            superclass = b.randomVariable(ofType: .constructor())
        }

        // If there are no visible variables, create some random number- or string values first, so they can be used for example as property values.
        if !b.hasVisibleVariables {
            for _ in 0..<3 {
                withEqualProbability({
                    b.loadInt(b.randomInt())
                }, {
                    b.loadFloat(b.randomFloat())
                }, {
                    b.loadString(b.randomString())
                })
            }
        }

        // Create the class.
        let c = b.buildClassDefinition(withSuperclass: superclass) { cls in
            b.buildRecursive()
        }

        // And construct a few instances of it.
        for _ in 0..<n {
            b.construct(c, withArgs: b.randomArguments(forCalling: c))
        }
    },

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

    CodeGenerator("ArgumentsAccessGenerator", inContext: .subroutine) { b in
        assert(b.context.contains(.subroutine))
        b.loadArguments()
    },

    RecursiveCodeGenerator("FunctionWithArgumentsAccessGenerator") { b in
        let parameterCount = probability(0.5) ? 0 : Int.random(in: 1...4)

        let f = b.buildPlainFunction(with: .parameters(n: parameterCount)) { args in
            let arguments = b.loadArguments()
            b.buildRecursive()
            b.doReturn(arguments)
        }

        let args = b.randomVariables(n: Int.random(in: 0...5))
        b.callFunction(f, withArgs: args)
    },

    CodeGenerator("DisposableVariableGenerator", inContext: .subroutine, inputs: .one) { b, val in
        assert(b.context.contains(.subroutine))
        let dispose = b.getProperty("dispose", of: b.createNamedVariable(forBuiltin: "Symbol"));
        let disposableVariable = b.buildObjectLiteral { obj in
            obj.addProperty("value", as: val)
            obj.addComputedMethod(dispose, with: .parameters(n:0)) { args in
                b.doReturn(b.randomVariable())
            }
        }
        b.loadDisposableVariable(disposableVariable)
    },

    CodeGenerator("AsyncDisposableVariableGenerator", inContext: .asyncFunction, inputs: .one) { b, val in
        assert(b.context.contains(.asyncFunction))
        let asyncDispose = b.getProperty("asyncDispose", of: b.createNamedVariable(forBuiltin: "Symbol"))
        let asyncDisposableVariable = b.buildObjectLiteral { obj in
            obj.addProperty("value", as: val)
            obj.addComputedMethod(asyncDispose, with: .parameters(n:0)) { args in
                b.doReturn(b.randomVariable())
            }
        }
        b.loadAsyncDisposableVariable(asyncDisposableVariable)
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
        } while b.currentObjectLiteral.properties.contains(propertyName)

        b.currentObjectLiteral.addProperty(propertyName, as: b.randomVariable())
    },

    CodeGenerator("ObjectLiteralElementGenerator", inContext: .objectLiteral, inputs: .one) { b, value in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentObjectLiteral.elements.contains(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        b.currentObjectLiteral.addElement(index, as: value)
    },

    CodeGenerator("ObjectLiteralComputedPropertyGenerator", inContext: .objectLiteral, inputs: .one) { b, value in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomVariable()
            attempts += 1
        } while b.currentObjectLiteral.computedProperties.contains(propertyName)

        b.currentObjectLiteral.addComputedProperty(propertyName, as: value)
    },

    CodeGenerator("ObjectLiteralCopyPropertiesGenerator", inContext: .objectLiteral, inputs: .preferred(.object())) { b, object in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))
        b.currentObjectLiteral.copyProperties(from: object)
    },

    CodeGenerator("ObjectLiteralPrototypeGenerator", inContext: .objectLiteral) { b in
        assert(b.context.contains(.objectLiteral) && !b.context.contains(.javascript))

        // There should only be one __proto__ field in an object literal.
        guard !b.currentObjectLiteral.hasPrototype else { return }

        let proto = b.randomVariable(forUseAs: .object())
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
        } while b.currentObjectLiteral.methods.contains(methodName)

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
        } while b.currentObjectLiteral.computedMethods.contains(methodName)

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
        } while b.currentObjectLiteral.properties.contains(propertyName) || b.currentObjectLiteral.getters.contains(propertyName)

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
        } while b.currentObjectLiteral.properties.contains(propertyName) || b.currentObjectLiteral.setters.contains(propertyName)

        b.currentObjectLiteral.addSetter(for: propertyName) { this, v in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ClassConstructorGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        guard !b.currentClassDefinition.hasConstructor else {
            // There must only be one constructor
            return
        }

        b.currentClassDefinition.addConstructor(with: b.randomParameters()) { args in
            let this = args[0]
            // Derived classes must call `super()` before accessing this, but non-derived classes must not call `super()`.
            if b.currentClassDefinition.isDerivedClass {
                b.hide(this)    // We need to hide |this| so it isn't used as argument for `super()`
                let signature = b.currentSuperConstructorType().signature ?? Signature.forUnknownFunction
                let args = b.randomArguments(forCallingFunctionWithSignature: signature)
                b.callSuperConstructor(withArgs: args)
                b.unhide(this)
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
        } while b.currentClassDefinition.instanceProperties.contains(propertyName)

        var value: Variable? = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addInstanceProperty(propertyName, value: value)
    },

    CodeGenerator("ClassInstanceElementGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.instanceElements.contains(index) {
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
        } while b.currentClassDefinition.instanceComputedProperties.contains(propertyName)

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
        } while b.currentClassDefinition.instanceMethods.contains(methodName)

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
        } while b.currentClassDefinition.instanceProperties.contains(propertyName) || b.currentClassDefinition.instanceGetters.contains(propertyName)

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
        } while b.currentClassDefinition.instanceProperties.contains(propertyName) || b.currentClassDefinition.instanceSetters.contains(propertyName)

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
        } while b.currentClassDefinition.staticProperties.contains(propertyName)

        var value: Variable? = probability(0.5) ? b.randomVariable() : nil
        b.currentClassDefinition.addStaticProperty(propertyName, value: value)
    },

    CodeGenerator("ClassStaticElementGenerator", inContext: .classDefinition) { b in
        assert(b.context.contains(.classDefinition) && !b.context.contains(.javascript))

        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.staticElements.contains(index) {
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
        } while b.currentClassDefinition.staticComputedProperties.contains(propertyName)

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
        } while b.currentClassDefinition.staticMethods.contains(methodName)

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
        } while b.currentClassDefinition.staticProperties.contains(propertyName) || b.currentClassDefinition.staticGetters.contains(propertyName)

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
        } while b.currentClassDefinition.staticProperties.contains(propertyName) || b.currentClassDefinition.staticSetters.contains(propertyName)

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
        } while b.currentClassDefinition.privateFields.contains(propertyName)

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
        } while b.currentClassDefinition.privateFields.contains(methodName)

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
        } while b.currentClassDefinition.privateFields.contains(propertyName)

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
        } while b.currentClassDefinition.privateFields.contains(methodName)

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
        b.createNamedVariable(forBuiltin: b.randomBuiltin())
    },

    CodeGenerator("NamedVariableGenerator") { b in
        // We're using the custom property names set from the environment for named variables.
        // It's not clear if there's something better since that set should be relatively small
        // (increasing the probability that named variables will be reused), and it also makes
        // sense to use property names if we're inside a `with` statement.
        let name = b.randomCustomPropertyName()
        let declarationMode = chooseUniform(from: NamedVariableDeclarationMode.allCases)
        if declarationMode != .none {
            b.createNamedVariable(name, declarationMode: declarationMode, initialValue: b.randomVariable())
        } else {
            b.createNamedVariable(name, declarationMode: declarationMode)
        }
    },

    CodeGenerator("BuiltinOverwriteGenerator", inputs: .one) { b, value in
        let builtin = b.createNamedVariable(b.randomBuiltin(), declarationMode: .none)
        b.reassign(builtin, to: value)
    },

    RecursiveCodeGenerator("PlainFunctionGenerator") { b in
        let f = b.buildPlainFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("StrictModeFunctionGenerator") { b in
        // We could consider having a standalone DirectiveGenerator, but probably most of the time it won't do anything meaningful.
        // We could also consider keeping a list of known directives in the Environment, but currently we only use 'use strict'.
        let f = b.buildPlainFunction(with: b.randomParameters()) { _ in
            b.directive("use strict")
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("ArrowFunctionGenerator") { b in
        b.buildArrowFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("GeneratorFunctionGenerator") { b in
        let f = b.buildGeneratorFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            if probability(0.5) {
                b.yield(b.randomVariable())
            } else {
                let randomVariables = b.randomVariables(n: Int.random(in: 1...5))
                let array = b.createArray(with: randomVariables)
                b.yieldEach(array)
            }
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("AsyncFunctionGenerator") { b in
        let f = b.buildAsyncFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    RecursiveCodeGenerator("AsyncArrowFunctionGenerator") { b in
        b.buildAsyncArrowFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            b.doReturn(b.randomVariable())
        }
        // These are "typically" used as arguments, so we don't directly generate a call operation here.
    },

    RecursiveCodeGenerator("AsyncGeneratorFunctionGenerator") { b in
        let f = b.buildAsyncGeneratorFunction(with: b.randomParameters()) { _ in
            b.buildRecursive()
            b.await(b.randomVariable())
            if probability(0.5) {
                b.yield(b.randomVariable())
            } else {
                let randomVariables = b.randomVariables(n: Int.random(in: 1...5))
                let array = b.createArray(with: randomVariables)
                b.yieldEach(array)
            }
            b.doReturn(b.randomVariable())
        }
        b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    },

    CodeGenerator("PropertyRetrievalGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("PropertyAssignmentGenerator", inputs: .preferred(.object())) { b, obj in
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
        let value = b.randomVariable(forUseAs: propertyType)

        // TODO: (here and below) maybe wrap in try catch if obj may be nullish?
        b.setProperty(propertyName, of: obj, to: value)
    },

    CodeGenerator("PropertyUpdateGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName: String
        // Change an existing property
        propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateProperty(propertyName, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("PropertyRemovalGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteProperty(propertyName, of: obj, guard: true)
    },

    CodeGenerator("PropertyConfigurationGenerator", inputs: .preferred(.object())) { b, obj in
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

    CodeGenerator("ElementRetrievalGenerator", inputs: .preferred(.object())) { b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator("ElementAssignmentGenerator", inputs: .preferred(.object())) { b, obj in
        let index = b.randomIndex()
        let value = b.randomVariable()
        b.setElement(index, of: obj, to: value)
    },

    CodeGenerator("ElementUpdateGenerator", inputs: .preferred(.object())) { b, obj in
        let index = b.randomIndex()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateElement(index, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ElementRemovalGenerator", inputs: .preferred(.object())) { b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator("ElementConfigurationGenerator", inputs: .preferred(.object())) { b, obj in
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

    CodeGenerator("ComputedPropertyRetrievalGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.randomVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("ComputedPropertyAssignmentGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.randomVariable()
        let value = b.randomVariable()
        b.setComputedProperty(propertyName, of: obj, to: value)
    },

    CodeGenerator("ComputedPropertyUpdateGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.randomVariable()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateComputedProperty(propertyName, of: obj, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ComputedPropertyRemovalGenerator", inputs: .preferred(.object())) { b, obj in
        let propertyName = b.randomVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("ComputedPropertyConfigurationGenerator", inputs: .preferred(.object())) { b, obj in
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

    CodeGenerator("TypeTestGenerator", inputs: .one) { b, val in
        let type = b.typeof(val)
        // Also generate a comparison here, since that's probably the only interesting thing you can do with the result.
        let rhs = b.loadString(chooseUniform(from: JavaScriptEnvironment.jsTypeNames))
        b.compare(type, with: rhs, using: .strictEqual)
    },

    CodeGenerator("VoidGenerator", inputs: .one) { b, val in
        b.void(val)
    },

    CodeGenerator("InstanceOfGenerator", inputs: .preferred(.anything, .constructor())) { b, val, cls in
        b.testInstanceOf(val, cls)
    },

    CodeGenerator("InGenerator", inputs: .preferred(.object())) { b, obj in
        let prop = b.randomVariable()
        b.testIn(prop, obj)
    },

    CodeGenerator("MethodCallGenerator", inputs: .preferred(.object())) { b, obj in
        let methodName: String, needGuard: Bool
        if let existingMethod = b.type(of: obj).randomMethod() {
            methodName = existingMethod
            needGuard = false
        } else {
            // Guard against runtime exceptions as there is a large probability that the method doesn't exist.
            methodName = b.randomMethodName()
            needGuard = true
        }
        // TODO: here and below, if we aren't finding arguments of compatible types, we probably still need a guard.
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        b.callMethod(methodName, on: obj, withArgs: arguments, guard: true)
    },

    CodeGenerator("MethodCallWithSpreadGenerator", inputs: .preferred(.object())) { b, obj in
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        var needGuard = false
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callMethod(methodName, on: obj, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator("ComputedMethodCallGenerator", inputs: .preferred(.object())) { b, obj in
        let methodName: String, needGuard: Bool
        if let existingMethod = b.type(of: obj).randomMethod() {
            methodName = existingMethod
            needGuard = false
        } else {
            methodName = b.randomMethodName()
            needGuard = true
        }
        let method = b.loadString(methodName)
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        b.callComputedMethod(method, on: obj, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator("ComputedMethodCallWithSpreadGenerator", inputs: .preferred(.object())) { b, obj in
        guard let methodName = b.type(of: obj).randomMethod() else { return }

        let method = b.loadString(methodName)
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        var needGuard = false
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callComputedMethod(method, on: obj, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator("FunctionCallGenerator", inputs: .preferred(.function())) { b, f in
        let arguments = b.randomArguments(forCalling: f)
        // TODO: we may also need guarding if the arguments aren't compatible with the expected ones
        let needGuard = b.type(of: f).MayNotBe(.function())
        b.callFunction(f, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator("ConstructorCallGenerator", inputs: .preferred(.constructor())) { b, c in
        let arguments = b.randomArguments(forCalling: c)
        // TODO: we may also need guarding if the arguments aren't compatible with the expected ones
        let needGuard = b.type(of: c).MayNotBe(.constructor())
        b.construct(c, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator("FunctionCallWithSpreadGenerator", inputs: .preferred(.function())) { b, f in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        var needGuard = b.type(of: f).MayNotBe(.function())
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callFunction(f, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator("ConstructorCallWithSpreadGenerator", inputs: .preferred(.constructor())) { b, c in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(n: Int.random(in: 3...5))
        var needGuard = b.type(of: c).MayNotBe(.constructor())
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.construct(c, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator("SubroutineReturnGenerator", inContext: .subroutine, inputs: .one) { b, val in
        assert(b.context.contains(.subroutine))
        if probability(0.9) {
            b.doReturn(val)
        } else {
            b.doReturn()
        }
    },

    CodeGenerator("YieldGenerator", inContext: .generatorFunction, inputs: .one) { b, val in
        assert(b.context.contains(.generatorFunction))
        if probability(0.9) {
            b.yield(val)
        } else {
            b.yield()
        }
    },

    CodeGenerator("YieldEachGenerator", inContext: .generatorFunction, inputs: .required(.iterable)) { b, val in
        assert(b.context.contains(.generatorFunction))
        b.yieldEach(val)
    },

    CodeGenerator("AwaitGenerator", inContext: .asyncFunction, inputs: .one) { b, val in
        assert(b.context.contains(.asyncFunction))
        b.await(val)
    },

    CodeGenerator("UnaryOperationGenerator", inputs: .one) { b, val in
        b.unary(chooseUniform(from: UnaryOperator.allCases), val)
    },

    CodeGenerator("BinaryOperationGenerator", inputs: .two) { b, lhs, rhs in
        b.binary(lhs, rhs, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("TernaryOperationGenerator", inputs: .two) { b, lhs, rhs in
        let condition = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.ternary(condition, lhs, rhs)
    },

    CodeGenerator("UpdateGenerator", inputs: .one) { b, v in
        let newValue = b.randomVariable(forUseAs: b.type(of: v))
        b.reassign(newValue, to: v, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("DupGenerator") { b in
        b.dup(b.randomVariable())
    },

    CodeGenerator("ReassignmentGenerator", inputs: .one) { b, v in
        let newValue = b.randomVariable(forUseAs: b.type(of: v))
        guard newValue != v else { return }
        b.reassign(newValue, to: v)
    },

    CodeGenerator("DestructArrayGenerator", inputs: .preferred(.iterable)) { b, arr in
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

    CodeGenerator("DestructArrayAndReassignGenerator", inputs: .preferred(.iterable)) {b, arr in
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

    CodeGenerator("DestructObjectGenerator", inputs: .preferred(.object())) { b, obj in
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

    CodeGenerator("DestructObjectAndReassignGenerator", inputs: .preferred(.object())) { b, obj in
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

    CodeGenerator("ComparisonGenerator", inputs: .two) { b, lhs, rhs in
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

    CodeGenerator("PrivatePropertyRetrievalGenerator", inContext: .classMethod, inputs: .preferred(.object())) { b, obj in
        // Accessing a private class property that has not been declared in the active class definition is a syntax error (i.e. wrapping the access in try-catch doesn't help).
        // As such, we're using the active class definition object to obtain the list of private property names that are guaranteed to exist in the class that is currently being defined.
        guard !b.currentClassDefinition.privateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.privateProperties)
        // Since we don't know whether the private property will exist or not (we don't track private properties in our type inference),
        // always wrap these accesses in try-catch since they'll be runtime type errors if the property doesn't exist.
        b.buildTryCatchFinally(tryBody: {
            b.getPrivateProperty(propertyName, of: obj)
        }, catchBody: { e in })
    },

    CodeGenerator("PrivatePropertyAssignmentGenerator", inContext: .classMethod, inputs: .preferred(.object(), .anything)) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.privateProperties)
        b.buildTryCatchFinally(tryBody: {
            b.setPrivateProperty(propertyName, of: obj, to: value)
        }, catchBody: { e in })
    },

    CodeGenerator("PrivatePropertyUpdateGenerator", inContext: .classMethod, inputs: .preferred(.object(), .anything)) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateProperties.isEmpty else { return }
        let propertyName = chooseUniform(from: b.currentClassDefinition.privateProperties)
        b.buildTryCatchFinally(tryBody: {
            b.updatePrivateProperty(propertyName, of: obj, with: value, using: chooseUniform(from: BinaryOperator.allCases))
        }, catchBody: { e in })
    },

    CodeGenerator("PrivateMethodCallGenerator", inContext: .classMethod, inputs: .preferred(.object())) { b, obj in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateMethods.isEmpty else { return }
        let methodName = chooseUniform(from: b.currentClassDefinition.privateMethods)
        b.buildTryCatchFinally(tryBody: {
            let args = b.randomArguments(forCallingFunctionWithSignature: Signature.forUnknownFunction)
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

    CodeGenerator("ComputedSuperPropertyRetrievalGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        let property = b.randomVariable()
        b.getComputedSuperProperty(property)
    },

    CodeGenerator("ComputedSuperPropertyAssignmentGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        let property = b.randomVariable()
        b.setComputedSuperProperty(property, to: b.randomVariable())
    },

    CodeGenerator("SuperPropertyUpdateGenerator", inContext: .method) { b in
        let superType = b.currentSuperType()
        let propertyName = superType.randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateSuperProperty(propertyName, with: rhs, using: chooseUniform(from: BinaryOperator.allCases))
    },

    RecursiveCodeGenerator("IfElseGenerator", inputs: .preferred(.boolean) ){ b, cond in
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive(block: 1, of: 2)
        }, elseBody: {
            b.buildRecursive(block: 2, of: 2)
        })
    },

    RecursiveCodeGenerator("CompareWithIfElseGenerator", inputs: .two) { b, lhs, rhs in
        let cond = b.compare(lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.buildIfElse(cond, ifBody: {
            b.buildRecursive(block: 1, of: 2)
        }, elseBody: {
            b.buildRecursive(block: 2, of: 2)
        })
    },

    RecursiveCodeGenerator("SwitchBlockGenerator", inputs: .one) { b, cond in
        b.buildSwitch(on: cond) { cases in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("SwitchCaseGenerator", inContext: .switchBlock, inputs: .one) { b, v in
        b.currentSwitchBlock.addCase(v, fallsThrough: probability(0.1)) {
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("SwitchDefaultCaseGenerator", inContext: .switchBlock) { b in
        guard !b.currentSwitchBlock.hasDefaultCase else { return }
        b.currentSwitchBlock.addDefaultCase(fallsThrough: probability(0.1)) {
            b.buildRecursive()
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
            b.buildForLoop({ return [b.loadInt(0), b.loadInt(10)] }, { vs in b.compare(vs[0], with: vs[1], using: .lessThan) }, { vs in b.unary(.PostInc, vs[0]); b.unary(.PostDec, vs[1]) }) { _ in
                b.buildRecursive()
            }
        }
    },

    RecursiveCodeGenerator("ForInLoopGenerator", inputs: .preferred(.object())) { b, obj in
        b.buildForInLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ForOfLoopGenerator", inputs: .preferred(.iterable)) { b, obj in
        b.buildForOfLoop(obj) { _ in
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("ForOfWithDestructLoopGenerator", inputs: .preferred(.iterable)) { b, obj in
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

    CodeGenerator("WellKnownPropertyLoadGenerator", inputs: .preferred(.object())) { b, obj in
        let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
        // The Symbol constructor is just a "side effect" of this generator and probably shouldn't be used by following generators.
        b.hide(Symbol)
        let name = chooseUniform(from: JavaScriptEnvironment.wellKnownSymbols)
        let propertyName = b.getProperty(name, of: Symbol)
        b.getComputedProperty(propertyName, of: obj)
    },

    CodeGenerator("WellKnownPropertyStoreGenerator", inputs: .preferred(.object())) { b, obj in
        let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
        b.hide(Symbol)
        let name = chooseUniform(from: JavaScriptEnvironment.wellKnownSymbols)
        let propertyName = b.getProperty(name, of: Symbol)
        let val = b.randomVariable()
        b.setComputedProperty(propertyName, of: obj, to: val)
    },

    CodeGenerator("PrototypeAccessGenerator", inputs: .preferred(.object())) { b, obj in
        b.getProperty("__proto__", of: obj)
    },

    CodeGenerator("PrototypeOverwriteGenerator", inputs: .preferred(.object(), .object())) { b, obj, proto in
        b.setProperty("__proto__", of: obj, to: proto)
    },

    CodeGenerator("CallbackPropertyGenerator", inputs: .preferred(.object(), .function())) { b, obj, callback in
        // TODO add new callbacks like Symbol.toPrimitive?
        let propertyName = chooseUniform(from: ["valueOf", "toString"])
        b.setProperty(propertyName, of: obj, to: callback)
    },

    CodeGenerator("MethodCallWithDifferentThisGenerator", inputs: .preferred(.object(), .object())) { b, obj, this in
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        let Reflect = b.createNamedVariable(forBuiltin: "Reflect")
        let args = b.createArray(with: arguments)
        b.callMethod("apply", on: Reflect, withArgs: [b.getProperty(methodName, of: obj), this, args])
    },

    CodeGenerator("ConstructWithDifferentNewTargetGenerator", inputs: .preferred(.constructor(), .constructor())) { b, newTarget, constructor  in
        let reflect = b.createNamedVariable(forBuiltin: "Reflect")
        let arguments = [constructor, b.createArray(with: b.randomArguments(forCalling: constructor)), newTarget]
        b.callMethod("construct", on: reflect, withArgs: arguments)
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

    CodeGenerator("ProxyGenerator", inputs: .preferred(.object())) { b, target in
        var candidates = Set(["getPrototypeOf", "setPrototypeOf", "isExtensible", "preventExtensions", "getOwnPropertyDescriptor", "defineProperty", "has", "get", "set", "deleteProperty", "ownKeys", "apply", "call", "construct"])

        var handlerProperties = [String: Variable]()
        for _ in 0..<Int.random(in: 0..<candidates.count) {
            let hook = chooseUniform(from: candidates)
            candidates.remove(hook)
            handlerProperties[hook] = b.randomVariable(ofType: .function())
        }
        let handler = b.createObject(with: handlerProperties)

        let Proxy = b.createNamedVariable(forBuiltin: "Proxy")
        b.hide(Proxy)// We want the proxy to be used by following code generators, not the Proxy constructor
        b.construct(Proxy, withArgs: [target, handler])
    },

    RecursiveCodeGenerator("PromiseGenerator") { b in
        let handler = b.buildPlainFunction(with: .parameters(n: 2)) { _ in
            // TODO could provide type hints here for the parameters.
            b.buildRecursive()
        }
        let Promise = b.createNamedVariable(forBuiltin: "Promise")
        b.hide(Promise)   // We want the promise to be used by following code generators, not the Promise constructor
        b.construct(Promise, withArgs: [handler])
    },

    // Tries to change the length property of some object
    CodeGenerator("LengthChangeGenerator", inputs: .preferred(.object())) { b, obj in
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
    CodeGenerator("ElementKindChangeGenerator", inputs: .one) { b, obj in
        let value = b.randomVariable()
        b.setElement(Int64.random(in: 0..<10), of: obj, to: value)
    },

    // Generates a JavaScript 'with' statement
    RecursiveCodeGenerator("WithStatementGenerator", inputs: .preferred(.object())) { b, obj in
        b.buildWith(obj) {
            for i in 1...3 {
                let propertyName = b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
                b.createNamedVariable(propertyName, declarationMode: .none)
            }
            b.buildRecursive()
        }
    },

    RecursiveCodeGenerator("EvalGenerator") { b in
        let code = b.buildCodeString() {
            b.buildRecursive()
        }
        let eval = b.createNamedVariable(forBuiltin: "eval")
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
        let Math = b.createNamedVariable(forBuiltin: "Math")
        b.hide(Math)        // Following code generators should use the numbers generated below, not the Math object.

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
                let sig = chooseUniform(from: b.methodSignatures(of: method, on: Math))
                for _ in 0..<sig.numParameters {
                    args.append(chooseUniform(from: values))
                }
                b.callMethod(method, on: Math, withArgs: args)
            })
        }
    },

    RecursiveCodeGenerator("ImitationGenerator", inputs: .one) { b, orig in
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
                let toPrimitive = b.getProperty("toPrimitive", of: b.createNamedVariable(forBuiltin: "Symbol"))
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
            let Proxy = b.createNamedVariable(forBuiltin: "Proxy")
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

        // TODO(cffsmith): Make the type inference strong enough such that the
        // inferred type is close enough to the original type.
        // assert(b.type(of: imitation) == b.type(of: orig))
    },

    CodeGenerator("ResizableArrayBufferGenerator", inputs: .one) { b, v in
        let size = b.randomSize(upTo: 0x1000)
        var maxSize = b.randomSize()
        if maxSize < size {
            maxSize = size
        }
        let ArrayBuffer = b.createNamedVariable(forBuiltin: "ArrayBuffer")
        b.hide(ArrayBuffer)
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.createNamedVariable(
            forBuiltin: chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator("GrowableSharedArrayBufferGenerator", inputs: .one) { b, v in
        let size = b.randomSize(upTo: 0x1000)
        var maxSize = b.randomSize()
        if maxSize < size {
            maxSize = size
        }
        let ArrayBuffer = b.createNamedVariable(forBuiltin: "SharedArrayBuffer")
        b.hide(ArrayBuffer)
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)])
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.createNamedVariable(
            forBuiltin: chooseUniform(
                from: ["Uint8Array", "Int8Array", "Uint16Array", "Int16Array", "Uint32Array", "Int32Array", "Float32Array", "Float64Array", "Uint8ClampedArray", "BigInt64Array", "BigUint64Array", "DataView"]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator("FastToSlowPropertiesGenerator", inputs: .preferred(.object())) { b, o in
        // Build a loop that adds computed properties to an object which forces its
        // properties to transition from "fast properties" to "slow properties".
        // 32 seems to be enough for V8, which seems to be controlled by
        // kFastPropertiesSoftLimit.
        b.buildRepeatLoop(n: 32) { i in
            let prefixStr = b.loadString("p");
            let propertyName = b.binary(prefixStr, i, with: .Add)
            b.setComputedProperty(propertyName, of: o, to: i)
        }
    },

    // This code generator tries to build complex chains of similar objects. In V8 and other JS engines this will usually lead to
    // a tree of object shapes. This generator tries to emit code that helps to find bugs such as crbug.com/1412487 or crbug.com/1470668.
    // This generator could be generalized even further in the future.
    CodeGenerator("ObjectHierarchyGenerator", inputs: .four) { b, prop0, prop1, prop2, prop3 in
        var propertyNames = Array(b.fuzzer.environment.customProperties)
        assert(propertyNames.count >= 4)
        propertyNames.shuffle()

        let obj0 = b.createObject(with: [:])
        b.setProperty(propertyNames[0], of: obj0, to: prop0)

        let obj1 = b.createObject(with: [:])
        b.setProperty(propertyNames[0], of: obj1, to: prop0)
        b.setProperty(propertyNames[1], of: obj1, to: prop1)

        let obj2 = b.createObject(with: [:])
        b.setProperty(propertyNames[0], of: obj2, to: prop0)
        b.setProperty(propertyNames[1], of: obj2, to: prop1)
        b.setProperty(propertyNames[2], of: obj2, to: prop2)

        let obj3 = b.createObject(with: [:])
        b.setProperty(propertyNames[0], of: obj3, to: prop0)
        b.setProperty(propertyNames[1], of: obj3, to: prop1)

        // Either set the same property with a different type (compared to obj2),
        // or a different property than obj2.
        if probability(0.5) {
            b.setProperty(propertyNames[2], of: obj3, to: prop3)
        } else {
            b.setProperty(propertyNames[3], of: obj3, to: prop3)
        }
    },

    CodeGenerator("IteratorGenerator") { b in
        let Symbol = b.createNamedVariable(forBuiltin: "Symbol")
        b.hide(Symbol)
        let iteratorSymbol = b.getProperty("iterator", of: Symbol)
        b.hide(iteratorSymbol)
        let iterableObject = b.buildObjectLiteral { obj in
            obj.addComputedMethod(iteratorSymbol, with: .parameters(n: 0)) { _ in
                let counter = b.loadInt(10)
                let iterator = b.buildObjectLiteral { obj in
                    obj.addMethod("next", with: .parameters(n: 0)) { _ in
                        b.unary(.PostDec, counter)
                        let done = b.compare(counter, with: b.loadInt(0), using: .equal)
                        let result = b.buildObjectLiteral { obj in
                            obj.addProperty("done", as: done)
                            obj.addProperty("value", as: counter)
                        }
                        b.doReturn(result)
                    }
                }
                b.doReturn(iterator)
            }
        }

        // Manually mark the object as iterable as our static type inference cannot determine that.
        b.setType(ofVariable: iterableObject, to: .iterable + .object())
    },

    CodeGenerator("LoadNewTargetGenerator", inContext: .subroutine) { b in
        assert(b.context.contains(.subroutine))
        b.loadNewTarget()
    },

    // TODO: think about merging this with the regular ConstructorCallGenerator.
    CodeGenerator("ApiConstructorCallGenerator", inputs: .required(.constructor())) { b, c in
        let signature = b.type(of: c).signature ?? Signature.forUnknownFunction

        b.buildTryCatchFinally(tryBody: {
            let args = b.findOrGenerateArguments(forSignature: signature)
            b.construct(c, withArgs: args)
        }, catchBody: { _ in })
    },

    // TODO: think about merging this with the regular MethodCallGenerator.
    CodeGenerator("ApiMethodCallGenerator", inputs: .required(.object())) { b, o in
        let methodName = b.type(of: o).randomMethod() ?? b.randomMethodName()

        let signature = chooseUniform(from: b.methodSignatures(of: methodName, on: o))

        b.buildTryCatchFinally(tryBody: {
            let args = b.findOrGenerateArguments(forSignature: signature)
            b.callMethod(methodName, on: o, withArgs: args)
        }, catchBody: { _ in })
    },

    CodeGenerator("ApiFunctionCallGenerator", inputs: .required(.function())) { b, f in
        let signature = b.type(of: f).signature ?? Signature.forUnknownFunction

        b.buildTryCatchFinally(tryBody: {
            let args = b.findOrGenerateArguments(forSignature: signature)
            b.callFunction(f, withArgs: args)
        }, catchBody: { _ in })
    },
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
