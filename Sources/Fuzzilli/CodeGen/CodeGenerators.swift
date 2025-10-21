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

// Generator stubs for disposable and async-disposable variables.
func disposableVariableGeneratorStubs(
        inContext contextRequirement : Context,
        withSymbol symbolProperty : String,
        genDisposableVariable : @escaping (ProgramBuilder, Variable) -> Void) -> [GeneratorStub] {
    return [
        GeneratorStub(
            "DisposableObjectLiteralBeginGenerator",
            inContext: .single(contextRequirement),
            provides: [.objectLiteral]
        ) { b in
            // Ensure we have the desired symbol below.
            b.createSymbolProperty(symbolProperty)
            b.emit(BeginObjectLiteral())
        },
        GeneratorStub(
            "DisposableObjectLiteralComputedMethodBeginGenerator",
            inContext: .single(.objectLiteral),
            provides: [.javascript, .subroutine, .method]
        ) { b in
            // It should be safe to assume that we find at least the
            // desired symbol we created above.
            let symbol = b.randomVariable(forUseAs: .jsSymbol)
            let parameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
            b.emit(
                BeginObjectLiteralComputedMethod(
                    parameters: parameters.parameters),
                withInputs: [symbol])
        },
        GeneratorStub(
            "DisposableObjectLiteralComputedMethodEndGenerator",
            inContext: .single([.javascript, .subroutine, .method]),
            provides: [.objectLiteral]
        ) { b in
            b.maybeReturnRandomJsVariable(0.9)
            b.emit(EndObjectLiteralComputedMethod())
        },
        GeneratorStub(
            "DisposableObjectLiteralEndGenerator",
            inContext: .single(.objectLiteral)
        ) { b in
            let disposableVariable = b.emit(EndObjectLiteral()).output
            genDisposableVariable(b, disposableVariable)
        },
    ]
}

//
// Code generators.
//
// These insert one or more instructions into a program.
//
public let CodeGenerators: [CodeGenerator] = [
    //
    // Value Generators: Code Generators that generate one or more new values, i.e. they have a `produces` annotation.
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

    CodeGenerator("IntegerGenerator", produces: [.integer]) { b in
        b.loadInt(b.randomInt())
    },

    CodeGenerator("BigIntGenerator", produces: [.bigint]) { b in
        b.loadBigInt(b.randomInt())
    },

    CodeGenerator("FloatGenerator", produces: [.float]) { b in
        b.loadFloat(b.randomFloat())
    },

    CodeGenerator("StringGenerator", produces: [.string]) { b in
        b.loadString(b.randomString())
    },

    CodeGenerator("BooleanGenerator", produces: [.boolean]) { b in
        // It's probably not too useful to generate multiple boolean values here.
        b.loadBool(Bool.random())
    },

    CodeGenerator("UndefinedGenerator", produces: [.undefined]) { b in
        // There is only one 'undefined' value, so don't generate it multiple times.
        b.loadUndefined()
    },

    CodeGenerator("NullGenerator", produces: [.undefined]) { b in
        // There is only one 'null' value, so don't generate it multiple times.
        b.loadNull()
    },

    CodeGenerator("ArrayGenerator", produces: [.jsArray]) { b in
        // If we can only generate empty arrays, then only create one such array.
        if !b.hasVisibleVariables {
            b.createArray(with: [])
        } else {
            let initialValues = (0..<Int.random(in: 1...5)).map({ _ in
                b.randomJsVariable()
            })
            b.createArray(with: initialValues)
        }
    },

    CodeGenerator("IntArrayGenerator", produces: [.jsArray]) { b in
        let values = (0..<Int.random(in: 1...10)).map({ _ in b.randomInt() })
        b.createIntArray(with: values)
    },

    CodeGenerator("FloatArrayGenerator", produces: [.jsArray]) { b in
        let values = (0..<Int.random(in: 1...10)).map({ _ in b.randomFloat() })
        b.createFloatArray(with: values)
    },

    CodeGenerator("BuiltinObjectInstanceGenerator", produces: [.object()]) {
        b in
        let builtin = chooseUniform(from: [
            "Array", "Map", "WeakMap", "Set", "WeakSet", "Date",
        ])
        let constructor = b.createNamedVariable(forBuiltin: builtin)
        if builtin == "Array" {
            let size = b.loadInt(b.randomSize(upTo: 0x1000))
            b.construct(constructor, withArgs: [size])
        } else {
            // TODO could add arguments here if possible. Until then, just generate a single value.
            b.construct(constructor)
        }
    },

    CodeGenerator("BuiltinObjectPrototypeCallGenerator") { b in
        // TODO: It would be nice to type more prototypes and extend this list.
        let builtinName = chooseUniform(from: [
            "Promise", "Date", "Array", "ArrayBuffer", "SharedArrayBuffer", "String"])
        let builtin = b.createNamedVariable(forBuiltin: builtinName)
        let prototype = b.getProperty("prototype", of: builtin)
        let prototypeType = b.type(of: prototype)
        let choiceCount = prototypeType.numProperties + prototypeType.numMethods
        guard choiceCount != 0 else {
            fatalError("\(builtinName).prototype has no known properties or methods (type: \(prototypeType))")
        }
        let useProperty = Int.random(in: 0..<choiceCount) < prototypeType.numProperties
        let fctName = (useProperty ? prototypeType.properties : prototypeType.methods).randomElement()!
        let fct = b.getProperty(fctName, of: prototype)
        let fctType = b.type(of: fct)
        let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: fct)
        let receiverType = fctType.receiver ?? prototypeType
        let desiredReceiverType = fctType.receiver ?? prototypeType
        let receiver = b.randomVariable(forUseAs: desiredReceiverType)
        let needGuard = (!fctType.Is(.function()) && !fctType.Is(.unboundFunction()))
            || !b.type(of: receiver).Is(receiverType) || !matches
        if Bool.random() {
            b.callMethod("call", on: fct, withArgs: [receiver] + arguments, guard: needGuard)
        } else {
            b.callMethod("apply", on: fct, withArgs: [receiver, b.createArray(with: arguments)], guard: needGuard)
        }
    },

    CodeGenerator("BuiltinTemporalGenerator") { b in
        let _ = chooseUniform(from: [b.constructTemporalInstant, b.constructTemporalDuration,
                             b.constructTemporalTime, b.constructTemporalYearMonth, b.constructTemporalMonthDay,
                             b.constructTemporalDate, b.constructTemporalDateTime, b.constructTemporalZonedDateTime])()
    },
    CodeGenerator("TypedArrayGenerator", produces: [.object()]) { b in
        let size = b.loadInt(b.randomSize(upTo: 0x1000))
        let constructor = b.createNamedVariable(
            forBuiltin: chooseUniform(
                from: [
                    "Uint8Array", "Int8Array", "Uint16Array", "Int16Array",
                    "Uint32Array", "Int32Array", "Float32Array", "Float64Array",
                    "Uint8ClampedArray", "BigInt64Array", "BigUint64Array",
                ]
            )
        )
        b.construct(constructor, withArgs: [size])
    },

    CodeGenerator("BuiltinIntlGenerator") { b in
        let _ = chooseUniform(from: [b.constructIntlDateTimeFormat, b.constructIntlCollator, b.constructIntlListFormat, b.constructIntlNumberFormat, b.constructIntlPluralRules, b.constructIntlRelativeTimeFormat, b.constructIntlSegmenter])()
    },

    CodeGenerator("HexGenerator") { b in
        let hexValues = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f", "A", "B", "C", "D", "E", "F"]

        let uint8ArrayBuiltin = b.createNamedVariable(forBuiltin: "Uint8Array")

        withEqualProbability({
                // Generate Uint8Array construction from hex string.
                var s = ""
                for _ in 0..<Int.random(in: 1...40) {
                    s += chooseUniform(from: hexValues)
                    s += chooseUniform(from: hexValues)
                }
                let hex = b.loadString(s)

                if probability(0.5) {
                    b.callMethod("fromHex", on: uint8ArrayBuiltin, withArgs: [hex])
                } else {
                    let target = b.construct(uint8ArrayBuiltin, withArgs: [b.loadInt(Int64.random(in: 0...0x100))])
                    b.callMethod("setFromHex", on: target, withArgs: [hex])
                }
            }, {
                // Generate hex String construction from Uint8Array.
                let values = (0..<Int.random(in: 1...20)).map {_ in b.loadInt(Int64.random(in: 0...0xFF))}
                let bytes = b.callMethod("of", on: uint8ArrayBuiltin, withArgs: values)
                b.callMethod("toHex", on: bytes, withArgs: [])
            }
        )
    },

    CodeGenerator("Base64Generator") { b in
        let base64Alphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "/"]
        let base64URLAlphabet = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "_"]

        let uint8ArrayBuiltin = b.createNamedVariable(forBuiltin: "Uint8Array")

        withEqualProbability({
                var options = [String: Variable]()
                let alphabet = chooseUniform(from: [base64Alphabet, base64URLAlphabet])

                options["alphabet"] = b.loadString((alphabet == base64Alphabet) ? "base64" : "base64url")
                options["lastChunkHandling"] = b.loadString(
                    chooseUniform(
                        from: ["loose", "strict", "stop-before-partial"]
                    )
                )

                var s = ""
                for _ in 0..<Int.random(in: 1...32) * 4 {
                    s += chooseUniform(from: alphabet)
                }

                // Extend by 0, 1, or 2 bytes.
                switch (Int.random(in: 0...3)) {
                    case 1:
                        s += base64Alphabet[Int.random(in: 0...63)]
                        s += base64Alphabet[Int.random(in: 0...63) & 0x30]
                        s += "=="
                        break

                    case 2:
                        s += base64Alphabet[Int.random(in: 0...63)]
                        s += base64Alphabet[Int.random(in: 0...63)]
                        s += base64Alphabet[Int.random(in: 0...63) & 0x3C]
                        s += "="
                        break

                    default:
                        break
                }

                let base64 = b.loadString(s)

                let optionsObject = b.createObject(with: options)
                if probability(0.5) {
                    b.callMethod("fromBase64", on: uint8ArrayBuiltin, withArgs: [base64, optionsObject])
                } else {
                    let target = b.construct(uint8ArrayBuiltin, withArgs: [b.loadInt(Int64.random(in: 0...0x100))])
                    b.callMethod("setFromBase64", on: target, withArgs: [base64, optionsObject])
                }
            }, {
                let values = (0..<Int.random(in: 1...64)).map {_ in b.loadInt(Int64.random(in: 0...0xFF))}
                let bytes = b.callMethod("of", on: uint8ArrayBuiltin, withArgs: values)
                b.callMethod("toBase64", on: bytes, withArgs: [])
            }
        )
    },

    CodeGenerator("RegExpGenerator", produces: [.jsRegExp]) { b in
        let (regexpPattern, flags) = b.randomRegExpPatternAndFlags()
        b.loadRegExp(regexpPattern, flags)
    },

    // TODO(cffsmith): If we had a way to pass variables to elements of a list of CodeGenerators, we could pass the `o` and the `f` variables.
    // We can pass the `f` variable right now with the `b.lastFunctionVariable` but we cannot pass `o`.
    CodeGenerator("ObjectBuilderFunctionGenerator") {
        b in
        var objType = ILType.object()
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            if !b.hasVisibleVariables {
                // Just create some random number- or string values for the object to use.
                for _ in 0..<3 {
                    withEqualProbability(
                        {
                            b.loadInt(b.randomInt())
                        },
                        {
                            b.loadFloat(b.randomFloat())
                        },
                        {
                            b.loadString(b.randomString())
                        })
                }
            }

            let o = b.buildObjectLiteral { obj in
                b.buildRecursive(n: Int.random(in: 0...10))
            }

            objType = b.type(of: o)

            b.doReturn(o)
        }

        assert(b.type(of: f).signature != nil)
        assert(b.type(of: f).signature!.outputType.Is(objType))

        for _ in 0..<Int.random(in: 5...10) {
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }
    },

    CodeGenerator("ObjectConstructorGenerator", produces: [.constructor()]) {
        b in
        let maxProperties = 3
        assert(b.fuzzer.environment.customProperties.count >= maxProperties)
        let properties = Array(
            b.fuzzer.environment.customProperties.shuffled().prefix(
                Int.random(in: 1...maxProperties)))

        // Define a constructor function...
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]

            // We don't want |this| to be used as property value, so hide it.
            b.hide(this)

            // Add a few random properties to the |this| object.
            for property in properties {
                let value =
                    b.hasVisibleVariables
                    ? b.randomJsVariable() : b.loadInt(b.randomInt())
                b.setProperty(property, of: this, to: value)
            }
        }

        assert(b.type(of: c).signature != nil)
        assert(
            b.type(of: c).signature!.outputType.Is(
                .object(withProperties: properties)))

        // and create a few instances with it.
        for _ in 0..<Int.random(in: 1...4) {
            b.construct(c, withArgs: b.randomArguments(forCalling: c))
        }
    },

    CodeGenerator("ClassDefinitionGenerator", produces: [.constructor()]) { b in
        // Possibly pick a superclass. The superclass must be a constructor (or null), otherwise a type error will be raised at runtime.
        var superclass: Variable? = nil
        if probability(0.5) && b.hasVisibleVariables {
            superclass = b.randomVariable(ofType: .constructor())
        }

        // If there are no visible variables, create some random number- or string values first, so they can be used for example as property values.
        if !b.hasVisibleVariables {
            for _ in 0..<3 {
                withEqualProbability(
                    {
                        b.loadInt(b.randomInt())
                    },
                    {
                        b.loadFloat(b.randomFloat())
                    },
                    {
                        b.loadString(b.randomString())
                    })
            }
        }

        // Create the class.
        let c = b.buildClassDefinition(withSuperclass: superclass, isExpression: probability(0.3)) { cls in
            b.buildRecursive(n: defaultCodeGenerationAmount)
        }

        // And construct a few instances of it.
        for _ in 0..<Int.random(in: 1...4) {
            b.construct(c, withArgs: b.randomArguments(forCalling: c))
        }
    },

    CodeGenerator("TrivialFunctionGenerator", produces: [.function()]) { b in
        // Generating more than one function has a fairly high probability of generating
        // essentially identical functions, so we just generate one.
        let maybeReturnValue =
            b.hasVisibleVariables ? b.randomJsVariable() : nil
        b.buildPlainFunction(with: .parameters(n: 0)) { _ in
            if let returnValue = maybeReturnValue {
                b.doReturn(returnValue)
            }
        }
    },

    CodeGenerator("TimeZoneIdGenerator") { b in
        if Bool.random() {
            b.randomTimeZone()
        } else {
            b.randomUTCOffset(mayHaveSeconds: true)
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

    CodeGenerator("ArgumentsAccessGenerator", inContext: .single(.subroutine)) { b in
        b.loadArguments()
    },

    CodeGenerator("FunctionWithArgumentsAccessGenerator", [
        GeneratorStub("FunctionWithArgumentsAccessBeginGenerator",
                      provides: [.subroutine, .javascript]) { b in
            let randomParameters = probability(0.5) ? .parameters(n: 0) : b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginPlainFunction(parameters: randomParameters.parameters, functionName: nil))
            b.loadArguments()
        },
        GeneratorStub("FunctionWithArgumentsAccessEndGenerator", inContext: .single([.javascript, .subroutine])) { b in
            // Ideally we would like to return the arguments Variable from above here.
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndPlainFunction())
            let args = b.randomJsVariables(n: Int.random(in: 0...5))
            b.callFunction(f, withArgs: args)
        },
    ]),

    CodeGenerator(
        "DisposableVariableGenerator",
        disposableVariableGeneratorStubs(
            inContext: .subroutine,
            withSymbol: "dispose") { b, variable in
                b.loadDisposableVariable(variable)
            }),

    CodeGenerator(
        "AsyncDisposableVariableGenerator",
        disposableVariableGeneratorStubs(
            inContext: .asyncFunction,
            withSymbol: "asyncDispose") { b, variable in
                b.loadAsyncDisposableVariable(variable)
            }),

    CodeGenerator(
        "ObjectLiteralGenerator",
        [
            GeneratorStub(
                "ObjectLiteralBeginGenerator", provides: [.objectLiteral]
            ) { b in
                b.emit(BeginObjectLiteral())
            },
            GeneratorStub(
                "ObjectLiteralEndGenerator", inContext: .single(.objectLiteral)
            ) { b in
                b.emit(EndObjectLiteral())
            },
        ]),

    CodeGenerator("ObjectLiteralPropertyGenerator", inContext: .single(.objectLiteral)) {
        b in

        // Try to find a property that hasn't already been added to this literal.
        let propertyName = b.generateString(b.randomCustomPropertyName,
            notIn: b.currentObjectLiteral.properties)
        b.currentObjectLiteral.addProperty(
            propertyName, as: b.randomJsVariable())
    },

    CodeGenerator(
        "ObjectLiteralElementGenerator", inContext: .single(.objectLiteral), inputs: .one
    ) { b, value in
        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentObjectLiteral.elements.contains(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        b.currentObjectLiteral.addElement(index, as: value)
    },

    CodeGenerator(
        "ObjectLiteralComputedPropertyGenerator", inContext: .single(.objectLiteral),
        inputs: .one
    ) { b, value in
        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            if attempts >= 10 {
                // Could not find anything.
                // Since this CodeGenerator does not produce anything it is fine to bail.
                return
            }
            propertyName = b.randomJsVariable()
            attempts += 1
        } while b.currentObjectLiteral.computedProperties.contains(propertyName)
        b.currentObjectLiteral.addComputedProperty(propertyName, as: value)
    },

    CodeGenerator(
        "ObjectLiteralCopyPropertiesGenerator", inContext: .single(.objectLiteral),
        inputs: .preferred(.object())
    ) { b, object in
        b.currentObjectLiteral.copyProperties(from: object)
    },

    CodeGenerator("ObjectLiteralPrototypeGenerator", inContext: .single(.objectLiteral))
    { b in
        // There should only be one __proto__ field in an object literal.
        guard !b.currentObjectLiteral.hasPrototype else { return }

        let proto = b.randomVariable(forUseAs: .object())
        b.currentObjectLiteral.setPrototype(to: proto)
    },

    CodeGenerator(
        "ObjectLiteralMethodGenerator",
        [
            GeneratorStub(
                "ObjectLiteralMethodBeginGenerator", inContext: .single(.objectLiteral),
                provides: [.javascript, .subroutine, .method]
            ) { b in
                // Try to find a method that hasn't already been added to this literal.
                let methodName = b.generateString(b.randomCustomMethodName,
                    notIn: b.currentObjectLiteral.methods)

                let randomParameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(
                    randomParameters.parameterTypes)
                b.emit(
                    BeginObjectLiteralMethod(
                        methodName: methodName,
                        parameters: randomParameters.parameters))
            },
            GeneratorStub("ObjectLiteralMethodEndGenerator", inContext: .single([.javascript, .subroutine, .method])) { b in
                b.emit(EndObjectLiteralMethod())
            },
        ]),

    CodeGenerator(
        "ObjectLiteralComputedMethodGenerator",
        [
            GeneratorStub(
                "ObjectLiteralComputedMethodBeginGenerator",
                inContext: .single(.objectLiteral),
                provides: [.javascript, .subroutine, .method]
            ) { b in
                // Try to find a computed method name that hasn't already been added to this literal.

                var methodName: Variable
                var attempts = 0
                repeat {
                    methodName = b.randomJsVariable()
                    if attempts >= 10 {
                        // This might lead to having two computed methods with the same name (so one
                        // will overwrite the other).
                        break
                    }
                    attempts += 1
                } while b.currentObjectLiteral.computedMethods.contains(
                    methodName)
                let parameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
                b.emit(
                    BeginObjectLiteralComputedMethod(
                        parameters: parameters.parameters),
                    withInputs: [methodName])
            },
            GeneratorStub(
                "ObjectLiteralComputedMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method]),
                inputs: .one
            ) { b, inp in
                b.doReturn(inp)
                b.emit(EndObjectLiteralComputedMethod())

            },
        ]),

    CodeGenerator(
        "ObjectLiteralGetterGenerator",
        [
            GeneratorStub(
                "ObjectLiteralGetterBeginGenerator",
                inContext: .single(.objectLiteral),
                provides: [.javascript, .subroutine, .method]
            ) { b in
                // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentObjectLiteral.properties + b.currentObjectLiteral.getters)
                b.emit(BeginObjectLiteralGetter(propertyName: propertyName))

            },
            GeneratorStub(
                "ObjectLiteralGetterEndGenerator",
                inContext: .single([.javascript, .subroutine, .method]),
                inputs: .one
            ) { b, inp in
                b.doReturn(inp)
                b.emit(EndObjectLiteralGetter())
            },
        ]),

    CodeGenerator(
        "ObjectLiteralSetterGenerator",
        [
            GeneratorStub(
                "ObjectLiteralSetterBeginGenerator",
                inContext: .single(.objectLiteral),
                provides: [.javascript, .subroutine, .method]
            ) { b in
                // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentObjectLiteral.properties + b.currentObjectLiteral.setters)
                b.emit(BeginObjectLiteralSetter(propertyName: propertyName))
            },
            GeneratorStub(
                "ObjectLiteralSetterEndGenerator",
                inContext: .single([.javascript, .subroutine, .method])
            ) { b in
                b.emit(EndObjectLiteralSetter())
            },
        ]),

    CodeGenerator(
        "ClassConstructorGenerator",
        [
            GeneratorStub(
                "ClassConstructorBeginGenerator",
                inContext: .single(.classDefinition),
                provides: []
            ) { b in

                guard !b.currentClassDefinition.hasConstructor else {
                    // There must only be one constructor
                    // If we bail here, we are *not* in .javaScript context so we cannot provide it here for other chains.
                    return
                }

                let randomParameters = b.randomParameters()

                b.setParameterTypesForNextSubroutine(
                    randomParameters.parameterTypes)

                let args = b.emit(
                    BeginClassConstructor(
                        parameters: randomParameters.parameters)
                ).innerOutputs

                let this = args[0]
                // Derived classes must call `super()` before accessing this, but non-derived classes must not call `super()`.
                if b.currentClassDefinition.isDerivedClass {
                    b.hide(this)  // We need to hide |this| so it isn't used as argument for `super()`
                    let signature =
                        b.currentSuperConstructorType().signature
                        ?? Signature.forUnknownFunction
                    let args = b.randomArguments(
                        forCallingFunctionWithSignature: signature)
                    b.callSuperConstructor(withArgs: args)
                    b.unhide(this)
                }
            },
            GeneratorStub(
                "ClassConstructorEndGenerator",
                // This can run in either context and will do different things
                // depending on if the previous generator succeeded.
                inContext: .either([.javascript, .classDefinition])
            ) { b in
                if b.context.contains(.javascript) {
                    b.emit(EndClassConstructor())
                }
            },
        ]),

    CodeGenerator("ClassInstancePropertyGenerator", inContext: .single(.classDefinition))
    { b in
        // Try to find a property that hasn't already been added to this literal.
        let propertyName = b.generateString(b.randomCustomPropertyName,
            notIn: b.currentClassDefinition.instanceProperties)

        var value: Variable? = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addInstanceProperty(propertyName, value: value)
    },

    CodeGenerator("ClassInstanceElementGenerator", inContext: .single(.classDefinition))
    { b in
        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.instanceElements.contains(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        let value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addInstanceElement(index, value: value)
    },

    CodeGenerator(
        "ClassInstanceComputedPropertyGenerator", inContext: .single(.classDefinition)
    ) { b in
        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else { return }
            propertyName = b.randomJsVariable()
            attempts += 1
        } while b.currentClassDefinition.instanceComputedProperties.contains(
            propertyName)

        let value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addInstanceComputedProperty(
            propertyName, value: value)
    },

    CodeGenerator(
        "ClassInstanceMethodGenerator",
        [
            GeneratorStub(
                "ClassInstanceMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a method that hasn't already been added to this class.
                let methodName = b.generateString(b.randomCustomMethodName,
                    notIn: b.currentClassDefinition.instanceMethods)

                let parameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
                b.emit(
                    BeginClassInstanceMethod(
                        methodName: methodName,
                        parameters: parameters.parameters))
            },
            GeneratorStub(
                "ClassInstanceMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassInstanceMethod())
            },
        ]),

    CodeGenerator(
        "ClassInstanceComputedMethodGenerator",
        [
            GeneratorStub(
                "ClassInstanceComputedMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a method that hasn't already been added to this class.
                var methodName = b.randomJsVariable()
                var attempts = 0
                repeat {
                    guard attempts < 10 else { break }
                    methodName = b.randomJsVariable()
                    attempts += 1
                } while b.currentClassDefinition.instanceComputedMethods.contains(
                    methodName)

                let parameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
                b.emit(
                    BeginClassInstanceComputedMethod(
                        parameters: parameters.parameters),
                    withInputs: [methodName])
            },
            GeneratorStub(
                "ClassInstanceComputedMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassInstanceComputedMethod())
            },
        ]),

    CodeGenerator(
        "ClassInstanceGetterGenerator",
        [
            GeneratorStub(
                "ClassInstanceGetterBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentClassDefinition.instanceProperties
                         + b.currentClassDefinition.instanceGetters)
                b.emit(BeginClassInstanceGetter(propertyName: propertyName))
            },
            GeneratorStub(
                "ClassInstanceGetterEndGenerator", inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.doReturn(b.randomJsVariable())
                b.emit(EndClassInstanceGetter())
            },
        ]),

    CodeGenerator(
        "ClassInstanceSetterGenerator",
        [
            GeneratorStub(
                "ClassInstanceSetterBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentClassDefinition.instanceProperties
                         + b.currentClassDefinition.instanceSetters)
                b.emit(BeginClassInstanceSetter(propertyName: propertyName))
            },
            GeneratorStub(
                "ClassInstanceSetterEndGenerator",
                inContext: .single([.javascript, .method, .subroutine, .classMethod])
            ) { b in
                b.emit(EndClassInstanceSetter())
            },

        ]),

    CodeGenerator("ClassStaticPropertyGenerator", inContext: .single(.classDefinition)) {
        b in
        // Try to find a property that hasn't already been added to this literal.
        let propertyName = b.generateString(b.randomCustomPropertyName,
            notIn: b.currentClassDefinition.staticProperties)

        var value: Variable? = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addStaticProperty(propertyName, value: value)
    },

    CodeGenerator("ClassStaticElementGenerator", inContext: .single(.classDefinition)) {
        b in
        // Select an element that hasn't already been added to this literal.
        var index = b.randomIndex()
        while b.currentClassDefinition.staticElements.contains(index) {
            // We allow integer overflows here since we could get Int64.max as index, and its not clear what should happen instead in that case.
            index &+= 1
        }

        let value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addStaticElement(index, value: value)
    },

    CodeGenerator(
        "ClassStaticComputedPropertyGenerator", inContext: .single(.classDefinition)
    ) { b in
        // Try to find a computed property that hasn't already been added to this literal.
        var propertyName: Variable
        var attempts = 0
        repeat {
            guard attempts < 10 else {
                // We are in .classDefinition context here and cannot create new JavaScript variables, so just bail here.
                return
            }
            propertyName = b.randomJsVariable()
            attempts += 1
        } while b.currentClassDefinition.staticComputedProperties.contains(
            propertyName)

        let value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addStaticComputedProperty(
            propertyName, value: value)
    },

    CodeGenerator(
        "ClassStaticInitializerGenerator",
        [
            GeneratorStub(
                "ClassStaticInitializerBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .method, .classMethod]
            ) { b in
                b.emit(BeginClassStaticInitializer())
            },
            GeneratorStub(
                "ClassStaticInitializerEndGenerator",
                inContext: .single([.javascript, .method, .classMethod])
            ) { b in
                b.emit(EndClassStaticInitializer())
            },
        ]),

    CodeGenerator(
        "ClassStaticMethodGenerator",
        [
            GeneratorStub(
                "ClassStaticMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .method, .subroutine, .classMethod]
            ) { b in
                // Try to find a method that hasn't already been added to this class.
                let methodName = b.generateString(b.randomCustomMethodName,
                    notIn: b.currentClassDefinition.staticMethods)
                let parameters = b.randomParameters()

                b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
                b.emit(
                    BeginClassStaticMethod(
                        methodName: methodName,
                        parameters: parameters.parameters))

            },
            GeneratorStub(
                "ClassStaticMethodEndGenerator",
                inContext: .single([.javascript, .classMethod, .subroutine, .method])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassStaticMethod())
            },
        ]),

    CodeGenerator(
        "ClassStaticComputedMethodGenerator",
        [
            GeneratorStub(
                "ClassStaticComputedMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a method that hasn't already been added to this class.
                var methodName = b.randomJsVariable()
                var attempts = 0
                repeat {
                    guard attempts < 10 else { break }
                    methodName = b.randomJsVariable()
                    attempts += 1
                } while b.currentClassDefinition.staticComputedMethods.contains(
                    methodName)

                let parameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(parameters.parameterTypes)
                b.emit(
                    BeginClassStaticComputedMethod(
                        parameters: parameters.parameters),
                    withInputs: [methodName])
            },
            GeneratorStub(
                "ClassStaticComputedMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassStaticComputedMethod())
            },
        ]),

    CodeGenerator(
        "ClassStaticGetterGenerator",
        [
            GeneratorStub(
                "ClassStaticGetterBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a property that hasn't already been added and for which a getter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentClassDefinition.staticProperties
                         + b.currentClassDefinition.staticGetters)
                b.emit(BeginClassStaticGetter(propertyName: propertyName))
            },
            GeneratorStub(
                "ClassStaticGetterEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.doReturn(b.randomJsVariable())
                b.emit(EndClassStaticGetter())
            },
        ]),

    CodeGenerator(
        "ClassStaticSetterGenerator",
        [
            GeneratorStub(
                "ClassStaticSetterBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a property that hasn't already been added and for which a setter has not yet been installed.
                let propertyName = b.generateString(b.randomCustomPropertyName,
                    notIn: b.currentClassDefinition.staticProperties
                         + b.currentClassDefinition.staticSetters)
                b.emit(BeginClassStaticSetter(propertyName: propertyName))
            },
            GeneratorStub(
                "ClassStaticSetterEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.emit(EndClassStaticSetter())
            },
        ]),

    CodeGenerator(
        "ClassPrivateInstancePropertyGenerator", inContext: .single(.classDefinition)
    ) { b in
        // Try to find a private field that hasn't already been added to this literal.
        let propertyName = b.generateString(b.randomCustomPropertyName,
            notIn: b.currentClassDefinition.privateFields)

        var value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addPrivateInstanceProperty(
            propertyName, value: value)
    },

    CodeGenerator(
        "ClassPrivateInstanceMethodGenerator",
        [
            GeneratorStub(
                "ClassPrivateInstanceMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a private field that hasn't already been added to this class.
                let methodName = b.generateString(b.randomCustomMethodName,
                    notIn: b.currentClassDefinition.privateFields)
                let parameters = b.randomParameters()
                b.emit(
                    BeginClassPrivateInstanceMethod(
                        methodName: methodName,
                        parameters: parameters.parameters))
            },
            GeneratorStub(
                "ClassPrivateInstanceMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassPrivateInstanceMethod())
            },
        ]),

    CodeGenerator(
        "ClassPrivateStaticPropertyGenerator", inContext: .single(.classDefinition)
    ) { b in
        // Try to find a private field that hasn't already been added to this literal.
        let propertyName = b.generateString(b.randomCustomPropertyName,
            notIn: b.currentClassDefinition.privateFields)
        var value = probability(0.5) ? b.randomJsVariable() : nil
        b.currentClassDefinition.addPrivateStaticProperty(
            propertyName, value: value)
    },

    CodeGenerator(
        "ClassPrivateStaticMethodGenerator",
        [
            GeneratorStub(
                "ClassPrivateStaticMethodBeginGenerator",
                inContext: .single(.classDefinition),
                provides: [.javascript, .subroutine, .method, .classMethod]
            ) { b in
                // Try to find a private field that hasn't already been added to this class.
                let methodName = b.generateString(b.randomCustomMethodName,
                    notIn: b.currentClassDefinition.privateFields)
                let parameters = b.randomParameters()
                b.emit(
                    BeginClassPrivateStaticMethod(
                        methodName: methodName,
                        parameters: parameters.parameters))
            },
            GeneratorStub(
                "ClassPrivateStaticMethodEndGenerator",
                inContext: .single([.javascript, .subroutine, .method, .classMethod])
            ) { b in
                b.maybeReturnRandomJsVariable(0.9)
                b.emit(EndClassPrivateStaticMethod())
            },

        ]),

    // Setting the input to one, makes this *not* a value generator, as we use b.randomJsVariable inside.
    CodeGenerator(
        "ArrayWithSpreadGenerator",
        inputs: .one,
        produces: [.jsArray]
    ) { b, _ in
        var initialValues = [Variable]()
        for _ in 0..<Int.random(in: 0...5) {
            initialValues.append(b.randomJsVariable())
        }

        // Pick some random inputs to spread.
        let spreads = initialValues.map({ el in
            probability(0.75) && b.type(of: el).Is(.iterable)
        })

        b.createArray(with: initialValues, spreading: spreads)
    },

    CodeGenerator(
        "TemplateStringGenerator",
        inputs: .one,
        produces: [.jsString]
    ) { b, _ in
        var interpolatedValues = [Variable]()
        for _ in 1..<Int.random(in: 1...5) {
            interpolatedValues.append(b.randomJsVariable())
        }

        var parts = [String]()
        for _ in 0...interpolatedValues.count {
            // For now we generate random strings
            parts.append(b.randomString())
        }
        b.createTemplateString(from: parts, interpolating: interpolatedValues)
    },

    CodeGenerator(
        "StringNormalizeGenerator",
        produces: [.jsString]
    ) { b in
        let form = b.loadString(
            chooseUniform(
                from: ["NFC", "NFD", "NFKC", "NFKD"]
            )
        )
        let string = b.loadString(b.randomString())
        b.callMethod("normalize", on: string, withArgs: [form])
    },

    CodeGenerator("BuiltinGenerator") { b in
        b.createNamedVariable(forBuiltin: b.randomBuiltin())
    },

    CodeGenerator("NamedVariableGenerator") { b in
        // We're using the custom property names set from the environment for named variables.
        // It's not clear if there's something better since that set should be relatively small
        // (increasing the probability that named variables will be reused), and it also makes
        // sense to use property names if we're inside a `with` statement.
        let name = b.randomCustomPropertyName()
        let declarationMode = chooseUniform(
            from: NamedVariableDeclarationMode.allCases)
        if declarationMode != .none {
            b.createNamedVariable(
                name, declarationMode: declarationMode,
                initialValue: b.randomJsVariable())
        } else {
            b.createNamedVariable(name, declarationMode: declarationMode)
        }
    },

    CodeGenerator("BuiltinOverwriteGenerator", inputs: .one) { b, value in
        let builtin = b.createNamedVariable(
            b.randomBuiltin(), declarationMode: .none)
        b.reassign(builtin, to: value)
    },

    CodeGenerator("PlainFunctionGenerator", [
        GeneratorStub("PlainFunctionBeginGenerator", provides: [.javascript, .subroutine]) { b in
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginPlainFunction(parameters: randomParameters.parameters, functionName: nil))
        },
        GeneratorStub("PlainFunctionEndGenerator", inContext: .single([.javascript, .subroutine])) { b in
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndPlainFunction())
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        },
    ]),

    CodeGenerator("StrictModeFunctionGenerator", [
        GeneratorStub("StrictModeFunctionBeginGenerator", provides: [.subroutine, .javascript]) { b in
            // We could consider having a standalone DirectiveGenerator, but probably most of the time it won't do anything meaningful.
            // We could also consider keeping a list of known directives in the JavaScriptEnvironment, but currently we only use 'use strict'.
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginPlainFunction(parameters: randomParameters.parameters, functionName: nil))
            b.directive("use strict")
        },
        GeneratorStub("StrictModeFunctionEndGenerator", inContext: .single([.javascript, .subroutine])) { b in
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndPlainFunction())
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        },
    ]),

    CodeGenerator(
        "ArrowFunctionGenerator",
        [
            GeneratorStub(
                "ArrowFunctionBeginGenerator",
                provides: [.subroutine, .javascript]
            ) { b in
                let randomParameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(
                    randomParameters.parameterTypes)
                b.emit(
                    BeginArrowFunction(parameters: randomParameters.parameters))
            },
            GeneratorStub(
                "ArrowFunctionEndGenerator",
                inContext: .single([.javascript, .subroutine])
            ) { b in
                b.emit(EndArrowFunction())
                // These are "typically" used as arguments, so we don't directly generate a call operation here.
            },
        ]),

    CodeGenerator("GeneratorFunctionGenerator", [
        GeneratorStub("GeneratorFunctionBeginGenerator", provides: [.generatorFunction, .subroutine, .javascript]) { b in
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginGeneratorFunction(parameters: randomParameters.parameters, functionName: nil))
        },
        GeneratorStub("GeneratorFunctionEndGenerator", inContext: .single([.generatorFunction, .subroutine, .javascript])) { b in
            if probability(0.5) {
                b.yield(b.randomJsVariable())
            } else {
                let randomVariables = b.randomJsVariables(
                    n: Int.random(in: 1...5))
                let array = b.createArray(with: randomVariables)
                b.yieldEach(array)
            }
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndGeneratorFunction())
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        },
    ]),

    CodeGenerator("AsyncFunctionGenerator", [
        GeneratorStub("AsyncFunctionBeginGenerator", provides: [.javascript, .subroutine, .asyncFunction]) { b in
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginAsyncFunction(parameters: randomParameters.parameters, functionName: nil))
        },
        GeneratorStub("AsyncFunctionEndGenerator", inContext: .single([.javascript, .subroutine, .asyncFunction])) { b in
            b.await(b.randomJsVariable())
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndAsyncFunction())
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        },
    ]),

    CodeGenerator(
        "AsyncArrowFunctionGenerator",
        [
            GeneratorStub(
                "AsyncArrowFunctionBeginGenerator",
                provides: [.javascript, .asyncFunction]
            ) { b in
                let randomParameters = b.randomParameters()
                b.setParameterTypesForNextSubroutine(
                    randomParameters.parameterTypes)
                b.emit(
                    BeginAsyncArrowFunction(
                        parameters: randomParameters.parameters))
            },
            GeneratorStub(
                "AsyncArrowFunctionAwaitGenerator",
                inContext: .single([.javascript, .asyncFunction]),
                provides: [.javascript, .asyncFunction]
            ) { b in
                b.await(b.randomJsVariable())
            },
            GeneratorStub(
                "AsyncArrowFunctionEndGenerator",
                inContext: .single([.javascript, .asyncFunction])
            ) { b in
                // These are "typically" used as arguments, so we don't directly generate a call operation here.
                b.doReturn(b.randomJsVariable())
                b.emit(EndAsyncArrowFunction())
            },
        ]),

    // This should likely be a Generator.
    // Cannot mark this as producing, as that would turn this into a value generator, but we call into .build.
    CodeGenerator("AsyncGeneratorFunctionGenerator", [
        GeneratorStub("AsyncGeneratorFunctionBeginGenerator", provides: [.javascript, .subroutine, .asyncFunction, .generatorFunction]) { b in
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginAsyncGeneratorFunction(
                    parameters: randomParameters.parameters, functionName: nil))
        },
        GeneratorStub("AsyncGeneratorFunctionEndGenerator", inContext: .single([.javascript, .subroutine, .generatorFunction, .asyncFunction])) { b in
            b.await(b.randomJsVariable())
            if probability(0.5) {
                b.yield(b.randomJsVariable())
            } else {
                let randomVariables = b.randomJsVariables(
                    n: Int.random(in: 1...5))
                let array = b.createArray(with: randomVariables)
                b.yieldEach(array)
            }
            b.doReturn(b.randomJsVariable())
            let f = b.lastFunctionVariable
            b.emit(EndAsyncGeneratorFunction())
            let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
            b.callFunction(f, withArgs: arguments, guard: !matches)
        },
    ]),

    CodeGenerator("PropertyRetrievalGenerator", inputs: .preferred(.object())) {
        b, obj in
        let propertyName =
            b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getProperty(propertyName, of: obj, guard: needGuard)
    },

    // Tries to return a "method" as a function via a property access.
    // A method can always also just be retrieved without calling it, however, note that this has
    // implications on the receiver:
    //   let x = {f() { return this; }};
    //   console.log(x.f() === x); // true
    //   let y = x.f;
    //   console.log(y() === x); // false
    CodeGenerator("MethodAsPropertyRetrievalGenerator", inputs: .preferred(.object())) { b, obj in
        let type = b.type(of: obj)
        let propertyName = type.randomMethod() ?? type.randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator("PropertyAssignmentGenerator", inputs: .preferred(.object()))
    { b, obj in
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName =
                b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // If this is an existing property with a specific type, try to find a variable with a matching type.
        var propertyType = b.type(ofProperty: propertyName, on: obj)
        assert(
            propertyType == .jsAnything
                || b.type(of: obj).properties.contains(propertyName))
        let value = b.randomVariable(forUseAs: propertyType)

        let needGuard = b.type(of: obj).MayBe(.nullish)

        b.setProperty(propertyName, of: obj, to: value, guard: needGuard)
    },

    CodeGenerator("PropertyUpdateGenerator", inputs: .preferred(.object())) {
        b, obj in
        let propertyName: String
        // Change an existing property
        propertyName =
            b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateProperty(
            propertyName, of: obj, with: rhs,
            using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("PropertyRemovalGenerator", inputs: .preferred(.object())) {
        b, obj in
        let propertyName =
            b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteProperty(propertyName, of: obj, guard: true)
    },

    CodeGenerator(
        "PropertyConfigurationGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.25) {
            propertyName =
                b.type(of: obj).randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // Getter/Setters must be functions or else a runtime exception will be raised.
        withEqualProbability(
            {
                b.configureProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .value(b.randomJsVariable()))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getter(getterFunc))
            },
            {
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .setter(setterFunc))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getterSetter(getterFunc, setterFunc))
            })
    },

    CodeGenerator("ElementRetrievalGenerator", inputs: .preferred(.object())) {
        b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator("ElementAssignmentGenerator", inputs: .preferred(.object())) {
        b, obj in
        let index = b.randomIndex()
        let value = b.randomJsVariable()
        b.setElement(index, of: obj, to: value)
    },

    CodeGenerator("ElementUpdateGenerator", inputs: .preferred(.object())) {
        b, obj in
        let index = b.randomIndex()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateElement(
            index, of: obj, with: rhs,
            using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("ElementRemovalGenerator", inputs: .preferred(.object())) {
        b, obj in
        let index = b.randomIndex()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteElement(index, of: obj, guard: needGuard)
    },

    CodeGenerator(
        "ElementConfigurationGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let index = b.randomIndex()
        withEqualProbability(
            {
                b.configureElement(
                    index, of: obj, usingFlags: PropertyFlags.random(),
                    as: .value(b.randomJsVariable()))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureElement(
                    index, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getter(getterFunc))
            },
            {
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureElement(
                    index, of: obj, usingFlags: PropertyFlags.random(),
                    as: .setter(setterFunc))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureElement(
                    index, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getterSetter(getterFunc, setterFunc))
            })
    },

    CodeGenerator(
        "ComputedPropertyRetrievalGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.randomJsVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator(
        "ComputedPropertyAssignmentGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.randomJsVariable()
        let value = b.randomJsVariable()
        b.setComputedProperty(propertyName, of: obj, to: value)
    },

    CodeGenerator(
        "ComputedPropertyUpdateGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.randomJsVariable()
        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateComputedProperty(
            propertyName, of: obj, with: rhs,
            using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator(
        "ComputedPropertyRemovalGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.randomJsVariable()
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.deleteComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator(
        "ComputedPropertyConfigurationGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.randomJsVariable()
        withEqualProbability(
            {
                b.configureComputedProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .value(b.randomJsVariable()))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureComputedProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getter(getterFunc))
            },
            {
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureComputedProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .setter(setterFunc))
            },
            {
                guard let getterFunc = b.randomVariable(ofType: .function())
                else { return }
                guard let setterFunc = b.randomVariable(ofType: .function())
                else { return }
                b.configureComputedProperty(
                    propertyName, of: obj, usingFlags: PropertyFlags.random(),
                    as: .getterSetter(getterFunc, setterFunc))
            })
    },

    CodeGenerator("TypeTestGenerator", inputs: .one) { b, val in
        let type = b.typeof(val)
        // Also generate a comparison here, since that's probably the only interesting thing you can do with the result.
        let rhs = b.loadString(
            chooseUniform(from: JavaScriptEnvironment.jsTypeNames))
        b.compare(type, with: rhs, using: .strictEqual)
    },

    CodeGenerator("VoidGenerator", inputs: .one) { b, val in
        b.void(val)
    },

    CodeGenerator(
        "InstanceOfGenerator", inputs: .preferred(.jsAnything, .constructor())
    ) { b, val, cls in
        b.testInstanceOf(val, cls)
    },

    CodeGenerator("InGenerator", inputs: .preferred(.object())) { b, obj in
        let prop = b.randomJsVariable()
        b.testIn(prop, obj)
    },

    CodeGenerator("MethodCallGenerator", inputs: .preferred(.object())) {
        b, obj in
        let methodName: String
        let needGuard: Bool
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
        b.callMethod(methodName, on: obj, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator(
        "MethodCallWithSpreadGenerator", inputs: .preferred(.object())
    ) { b, obj in
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(
            n: Int.random(in: 3...5))
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        var needGuard = false
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callMethod(
            methodName, on: obj, withArgs: arguments, spreading: spreads,
            guard: needGuard)
    },

    CodeGenerator("ComputedMethodCallGenerator", inputs: .preferred(.object()))
    { b, obj in
        let methodName: String
        let needGuard: Bool
        if let existingMethod = b.type(of: obj).randomMethod() {
            methodName = existingMethod
            needGuard = false
        } else {
            methodName = b.randomMethodName()
            needGuard = true
        }
        let method = b.loadString(methodName)
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        b.callComputedMethod(
            method, on: obj, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator(
        "ComputedMethodCallWithSpreadGenerator", inputs: .preferred(.object())
    ) { b, obj in
        guard let methodName = b.type(of: obj).randomMethod() else { return }

        let method = b.loadString(methodName)
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(
            n: Int.random(in: 3...5))
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        var needGuard = false
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callComputedMethod(
            method, on: obj, withArgs: arguments, spreading: spreads,
            guard: needGuard)
    },

    CodeGenerator("FunctionCallGenerator", inputs: .preferred(.function())) { b, f in
        let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: f)
        b.callFunction(f, withArgs: arguments, guard: !matches)
    },

    CodeGenerator("ConstructorCallGenerator", inputs: .preferred(.constructor())) { b, c in
        let (arguments, matches) = b.randomArguments(forCallingGuardableFunction: c)
        let needGuard = b.type(of: c).MayNotBe(.constructor()) || !matches
        b.construct(c, withArgs: arguments, guard: needGuard)
    },

    CodeGenerator(
        "FunctionCallWithSpreadGenerator", inputs: .preferred(.function())
    ) { b, f in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(
            n: Int.random(in: 3...5))
        var needGuard = b.type(of: f).MayNotBe(.function())
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.callFunction(
            f, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator(
        "ConstructorCallWithSpreadGenerator", inputs: .preferred(.constructor())
    ) { b, c in
        let (arguments, spreads) = b.randomCallArgumentsWithSpreading(
            n: Int.random(in: 3...5))
        var needGuard = b.type(of: c).MayNotBe(.constructor())
        // Spreading requires the spread values to be iterable, otherwise an exception will be raised.
        for (arg, spread) in zip(arguments, spreads) where spread == true {
            needGuard = needGuard || b.type(of: arg).MayNotBe(.iterable)
        }
        b.construct(
            c, withArgs: arguments, spreading: spreads, guard: needGuard)
    },

    CodeGenerator("UnboundFunctionCallGenerator", inputs: .preferred(.unboundFunction())) { b, f in
        let (arguments, argsMatch) = b.randomArguments(forCallingGuardableFunction: f)
        let fctType = b.type(of: f)
        let (receiver, recMatches) = b.randomVariable(forUseAsGuarded: fctType.receiver ?? .object())
        let needGuard = fctType.MayNotBe(.unboundFunction()) || !argsMatch || !recMatches
        // For simplicity we just hard-code the call function. If this was a separate IL
        // instruction, the JSTyper could infer the result type.
        b.callMethod("call", on: f, withArgs: [receiver] + arguments, guard: needGuard)
    },

    CodeGenerator("UnboundFunctionApplyGenerator", inputs: .preferred(.unboundFunction())) { b, f in
        let (arguments, argsMatch) = b.randomArguments(forCallingGuardableFunction: f)
        let fctType = b.type(of: f)
        let (receiver, recMatches) = b.randomVariable(forUseAsGuarded: fctType.receiver ?? .object())
        let needGuard = fctType.MayNotBe(.unboundFunction()) || !argsMatch || !recMatches
        // For simplicity we just hard-code the apply function. If this was a separate IL
        // instruction, the JSTyper could infer the result type.
        b.callMethod("apply", on: f, withArgs: [receiver, b.createArray(with: arguments)], guard: needGuard)
    },

    CodeGenerator("UnboundFunctionBindGenerator", inputs: .required(.unboundFunction())) { b, f in
        let arguments = b.randomArguments(forCalling: f)
        let fctType = b.type(of: f)
        let receiver = b.randomVariable(forUseAs: fctType.receiver ?? .object())
        let boundArgs = [receiver] + arguments
        b.bindFunction(f, boundArgs: Array(boundArgs[0..<Int.random(in: 0...boundArgs.count)]))
    },

    CodeGenerator("FunctionBindGenerator", inputs: .required(.function())) { b, f in
        let arguments = b.randomArguments(forCalling: f)
        let fctType = b.type(of: f)
        let receiver = b.randomVariable(forUseAs: .object())
        let boundArgs = [receiver] + arguments
        b.bindFunction(f, boundArgs: Array(boundArgs[0..<Int.random(in: 0...boundArgs.count)]))
    },

    CodeGenerator(
        "SubroutineReturnGenerator", inContext: .single(.subroutine), inputs: .one
    ) { b, val in
        if probability(0.9) {
            b.doReturn(val)
        } else {
            b.doReturn()
        }
    },

    CodeGenerator("YieldGenerator", inContext: .single(.generatorFunction), inputs: .one)
    { b, val in
        if probability(0.9) {
            b.yield(val)
        } else {
            b.yield()
        }
    },

    CodeGenerator(
        "YieldEachGenerator", inContext: .single(.generatorFunction),
        inputs: .required(.iterable)
    ) { b, val in
        b.yieldEach(val)
    },

    CodeGenerator("AwaitGenerator", inContext: .single(.asyncFunction), inputs: .one) {
        b, val in
        b.await(val)
    },

    CodeGenerator("UnaryOperationGenerator", inputs: .one) { b, val in
        b.unary(chooseUniform(from: UnaryOperator.allCases), val)
    },

    CodeGenerator("BinaryOperationGenerator", inputs: .two) { b, lhs, rhs in
        b.binary(lhs, rhs, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("TernaryOperationGenerator", inputs: .two) { b, lhs, rhs in
        let condition = b.compare(
            lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
        b.ternary(condition, lhs, rhs)
    },

    CodeGenerator("UpdateGenerator", inputs: .one) { b, v in
        let newValue = b.randomVariable(forUseAs: b.type(of: v))
        b.reassign(
            newValue, to: v, with: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator("DupGenerator") { b in
        b.dup(b.randomJsVariable())
    },

    CodeGenerator("ReassignmentGenerator", inputs: .one) { b, v in
        let newValue = b.randomVariable(forUseAs: b.type(of: v))
        guard newValue != v else { return }
        b.reassign(newValue, to: v)
    },

    CodeGenerator("DestructArrayGenerator", inputs: .preferred(.iterable)) {
        b, arr in
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

    CodeGenerator(
        "DestructArrayAndReassignGenerator", inputs: .preferred(.iterable)
    ) { b, arr in
        var candidates: [Variable] = []
        var indices: [Int64] = []
        for idx in 0..<Int64.random(in: 0..<5) {
            withProbability(0.7) {
                indices.append(idx)
                candidates.append(b.randomJsVariable())
            }
        }
        b.destruct(
            arr, selecting: indices, into: candidates,
            lastIsRest: probability(0.33))
    },

    CodeGenerator("DestructObjectGenerator", inputs: .preferred(.object())) {
        b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).randomProperty(),
                !properties.contains(prop)
            {
                properties.insert(prop)
            } else {
                properties.insert(b.randomCustomPropertyName())
            }
        }

        b.destruct(
            obj, selecting: properties.sorted(),
            hasRestElement: probability(0.33))
    },

    CodeGenerator(
        "DestructObjectAndReassignGenerator", inputs: .preferred(.object())
    ) { b, obj in
        var properties = Set<String>()
        for _ in 0..<Int.random(in: 1...3) {
            if let prop = b.type(of: obj).randomProperty(),
                !properties.contains(prop)
            {
                properties.insert(prop)
            } else {
                properties.insert(b.randomCustomPropertyName())
            }
        }

        var candidates = properties.map { _ in
            b.randomJsVariable()
        }

        let hasRestElement = probability(0.33)
        if hasRestElement {
            candidates.append(b.randomJsVariable())
        }

        b.destruct(
            obj, selecting: properties.sorted(), into: candidates,
            hasRestElement: hasRestElement)
    },

    CodeGenerator("ComparisonGenerator", inputs: .two) { b, lhs, rhs in
        b.compare(
            lhs, with: rhs, using: chooseUniform(from: Comparator.allCases))
    },

    CodeGenerator("SuperMethodCallGenerator", inContext: .single(.method)) { b in
        let superType = b.currentSuperType()
        if let methodName = superType.randomMethod() {
            let arguments = b.randomArguments(
                forCallingMethod: methodName, on: superType)
            b.callSuperMethod(methodName, withArgs: arguments)
        } else {
            // Wrap the call into try-catch as there's a large probability that it will be invalid and cause an exception.
            let methodName = b.randomMethodName()
            let arguments = b.randomArguments(
                forCallingMethod: methodName, on: superType)
            b.buildTryCatchFinally(
                tryBody: {
                    b.callSuperMethod(methodName, withArgs: arguments)
                }, catchBody: { _ in })
        }
    },

    CodeGenerator(
        "PrivatePropertyRetrievalGenerator", inContext: .single(.classMethod),
        inputs: .preferred(.object())
    ) { b, obj in
        // Accessing a private class property that has not been declared in the active class definition is a syntax error (i.e. wrapping the access in try-catch doesn't help).
        // As such, we're using the active class definition object to obtain the list of private property names that are guaranteed to exist in the class that is currently being defined.
        guard !b.currentClassDefinition.privateProperties.isEmpty else {
            return
        }
        let propertyName = chooseUniform(
            from: b.currentClassDefinition.privateProperties)
        // Since we don't know whether the private property will exist or not (we don't track private properties in our type inference),
        // always wrap these accesses in try-catch since they'll be runtime type errors if the property doesn't exist.
        b.buildTryCatchFinally(
            tryBody: {
                b.getPrivateProperty(propertyName, of: obj)
            }, catchBody: { e in })
    },

    CodeGenerator(
        "PrivatePropertyAssignmentGenerator", inContext: .single(.classMethod),
        inputs: .preferred(.object(), .jsAnything)
    ) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateProperties.isEmpty else {
            return
        }
        let propertyName = chooseUniform(
            from: b.currentClassDefinition.privateProperties)
        b.buildTryCatchFinally(
            tryBody: {
                b.setPrivateProperty(propertyName, of: obj, to: value)
            }, catchBody: { e in })
    },

    CodeGenerator(
        "PrivatePropertyUpdateGenerator", inContext: .single(.classMethod),
        inputs: .preferred(.object(), .jsAnything)
    ) { b, obj, value in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateProperties.isEmpty else {
            return
        }
        let propertyName = chooseUniform(
            from: b.currentClassDefinition.privateProperties)
        b.buildTryCatchFinally(
            tryBody: {
                b.updatePrivateProperty(
                    propertyName, of: obj, with: value,
                    using: chooseUniform(from: BinaryOperator.allCases))
            }, catchBody: { e in })
    },

    CodeGenerator(
        "PrivateMethodCallGenerator", inContext: .single(.classMethod),
        inputs: .preferred(.object())
    ) { b, obj in
        // See LoadPrivatePropertyGenerator for an explanation.
        guard !b.currentClassDefinition.privateMethods.isEmpty else { return }
        let methodName = chooseUniform(
            from: b.currentClassDefinition.privateMethods)
        b.buildTryCatchFinally(
            tryBody: {
                let args = b.randomArguments(
                    forCallingFunctionWithSignature: Signature
                        .forUnknownFunction)
                b.callPrivateMethod(methodName, on: obj, withArgs: args)
            }, catchBody: { e in })
    },

    CodeGenerator("SuperPropertyRetrievalGenerator", inContext: .single(.method)) { b in
        let superType = b.currentSuperType()
        // Emit a property load
        let propertyName =
            superType.randomProperty() ?? b.randomCustomPropertyName()
        b.getSuperProperty(propertyName)
    },

    CodeGenerator("SuperPropertyAssignmentGenerator", inContext: .single(.method)) { b in
        let superType = b.currentSuperType()
        let propertyName: String
        // Either change an existing property or define a new one
        if probability(0.5) {
            propertyName =
                superType.randomProperty() ?? b.randomCustomPropertyName()
        } else {
            propertyName = b.randomCustomPropertyName()
        }

        // TODO: we could try to determine if the type of this property is known and then try to find a compatible variable.
        b.setSuperProperty(propertyName, to: b.randomJsVariable())
    },

    CodeGenerator("ComputedSuperPropertyRetrievalGenerator", inContext: .single(.method))
    { b in
        let superType = b.currentSuperType()
        let property = b.randomJsVariable()
        b.getComputedSuperProperty(property)
    },

    CodeGenerator(
        "ComputedSuperPropertyAssignmentGenerator", inContext: .single(.method)
    ) { b in
        let superType = b.currentSuperType()
        let property = b.randomJsVariable()
        b.setComputedSuperProperty(property, to: b.randomJsVariable())
    },

    CodeGenerator("SuperPropertyUpdateGenerator", inContext: .single(.method)) { b in
        let superType = b.currentSuperType()
        let propertyName =
            superType.randomProperty() ?? b.randomCustomPropertyName()

        // TODO: for now we simply look for numbers, since those probably make the most sense for binary operations. But we may also want BigInts or strings sometimes.
        let rhs = b.randomVariable(forUseAs: .number)
        b.updateSuperProperty(
            propertyName, with: rhs,
            using: chooseUniform(from: BinaryOperator.allCases))
    },

    CodeGenerator(
        "IfElseGenerator",
        [
            GeneratorStub("BeginIfGenerator", inputs: .preferred(.boolean)) {
                b, cond in
                b.emit(BeginIf(inverted: false), withInputs: [cond])
            },
            GeneratorStub("BeginElseGenerator") { b in
                b.emit(BeginElse())
            },
            GeneratorStub("EndIfGenerator") { b in
                b.emit(EndIf())
            },
        ]),

    CodeGenerator(
        "CompareWithIfElseGenerator",
        [
            GeneratorStub("CompareWithIfElseBeginGenerator", inputs: .two) {
                b, lhs, rhs in
                let cond = b.compare(
                    lhs, with: rhs,
                    using: chooseUniform(from: Comparator.allCases))
                b.emit(BeginIf(inverted: false), withInputs: [cond])
            },
            GeneratorStub("BeginElseGenerator") { b in
                b.emit(BeginElse())
            },
            GeneratorStub("EndIfGenerator") { b in
                b.emit(EndIf())
            },
        ]),

    CodeGenerator(
        "SwitchBlockGenerator",
        [
            GeneratorStub(
                "SwitchBlockBeginGenerator",
                inputs: .one,
                provides: [.switchBlock]
            ) { b, cond in
                b.emit(BeginSwitch(), withInputs: [cond])
            },
            GeneratorStub(
                "SwitchBlockEndGenerator",
                inContext: .single(.switchBlock)
            ) { b in
                b.emit(EndSwitch())
            },
        ]),

    CodeGenerator(
        "SwitchCaseGenerator",
        [
            GeneratorStub(
                "SwitchCaseBeginGenerator",
                inContext: .single(.switchBlock),
                inputs: .one, provides: [.switchCase, .javascript]
            ) { b, v in
                b.emit(BeginSwitchCase(), withInputs: [v])
            },
            GeneratorStub(
                "SwitchCaseEndGenerator",
                inContext: .single([.switchCase, .javascript])
            ) { b in
                b.emit(EndSwitchCase(fallsThrough: probability(0.1)))
            },
        ]),

    // TODO: this can produce an invalid sample if the switch case has a default case already.
    // Check if we can abort, but right now this isn't allowed to fail.
    CodeGenerator(
        "SwitchDefaultCaseGenerator",
        [
            GeneratorStub(
                "SwitchDefaultCaseBeginGenerator",
                inContext: .single(.switchBlock)
            ) { b in
                guard !b.currentSwitchBlock.hasDefaultCase else { return }
                b.emit(BeginSwitchDefaultCase())
            },
            GeneratorStub(
                "SwitchDefaultCaseEndGenerator",
                inContext: .either([[.switchBlock], [.switchCase, .javascript]])
            ) { b in
                // Since we can be in either context, we only close this default case if we need to.
                if b.context.contains(.switchCase) {
                    b.emit(EndSwitchCase(fallsThrough: probability(0.1)))
                }
            },
        ]),

    CodeGenerator("SwitchCaseBreakGenerator", inContext: .single(.switchCase)) { b in
        b.switchBreak()
    },

    CodeGenerator(
        "WhileLoopGenerator",
        [
            GeneratorStub(
                "WhileLoopBeginGenerator",
                provides: [.loop, .javascript]
            ) { b in
                let loopVar = b.loadInt(0)
                b.emit(BeginWhileLoopHeader())
                let cond = b.compare(
                    loopVar, with: b.loadInt(Int64.random(in: 0...10)),
                    using: .lessThan)
                b.emit(BeginWhileLoopBody(), withInputs: [cond])
                b.unary(.PostInc, loopVar)
            },
            GeneratorStub(
                "WhileLoopEndGenerator",
                inContext: .single([.loop, .javascript])
            ) { b in
                b.emit(EndWhileLoop())
            },
        ]),

    CodeGenerator("DoWhileLoopGenerator") { b in
        let loopVar = b.loadInt(0)
        b.buildDoWhileLoop(
            do: {
                b.buildRecursive(n: defaultCodeGenerationAmount)
                b.unary(.PostInc, loopVar)
            },
            while: {
                b.compare(
                    loopVar, with: b.loadInt(Int64.random(in: 0...10)),
                    using: .lessThan)
            })
    },

    CodeGenerator(
        "SimpleForLoopGenerator",
        [
            GeneratorStub(
                "SimpleForLoopBeginInitializerGenerator",
                provides: [.loop, .javascript]
            ) { b in
                b.emit(BeginForLoopInitializer())
                let i = b.loadInt(0)
                var loopVar = b.emit(
                    BeginForLoopCondition(numLoopVariables: 1), withInputs: [i]
                ).innerOutput
                let cond = b.compare(
                    loopVar, with: b.loadInt(Int64.random(in: 0...1)),
                    using: .lessThan)
                loopVar =
                    b.emit(
                        BeginForLoopAfterthought(numLoopVariables: 1),
                        withInputs: [cond]
                    ).innerOutput
                b.unary(.PostInc, loopVar)
                b.emit(BeginForLoopBody(numLoopVariables: 1))
            },
            // TODO(cffsmith): Clean up idea: wrap this in some static method on the GeneratorGenerator such that we can just do `.withEndGenerator(EndForLoopGenerator)` or something like that! :)
            GeneratorStub(
                "SimpleForLoopEndGenerator",
                inContext: .single([.javascript, .loop])
            ) { b in
                b.emit(EndForLoop())
            },
        ]),

    // TODO: rethink if we want to convert this into a CodeGenerator with multiple parts.
    CodeGenerator("ComplexForLoopGenerator") { b in
        if probability(0.5) {
            // Generate a for-loop without any loop variables.
            let counter = b.loadInt(10)
            b.buildForLoop({}, { b.unary(.PostDec, counter) }) {
                b.buildRecursive(n: 4)
            }
        } else {
            // Generate a for-loop with two loop variables.
            // TODO could also generate loops with even more loop variables?
            b.buildForLoop(
                { return [b.loadInt(0), b.loadInt(10)] },
                { vs in b.compare(vs[0], with: vs[1], using: .lessThan) },
                { vs in
                    b.unary(.PostInc, vs[0])
                    b.unary(.PostDec, vs[1])
                }
            ) { _ in
                b.buildRecursive(n: 4)
            }
        }
    },

    CodeGenerator(
        "ForInLoopGenerator",
        [
            GeneratorStub(
                "ForInLoopBeginGenerator",
                inputs: .preferred(.object()),
                provides: [.loop, .javascript]
            ) { b, obj in
                b.emit(
                    BeginForInLoop(), withInputs: [obj]
                )
            },
            GeneratorStub(
                "ForInLoopEndGenerator",
                inContext: .single([.loop, .javascript])
            ) { b in
                b.emit(EndForInLoop())
            },
        ]),

    CodeGenerator(
        "ForOfLoopGenerator",
        [
            GeneratorStub(
                "ForOfLoopBeginGenerator",
                inputs: .preferred(.iterable),
                provides: [.loop, .javascript]
            ) { b, obj in
                b.emit(BeginForOfLoop(), withInputs: [obj])
            },
            GeneratorStub(
                "ForOfLoopEndGenerator",
                inContext: .single([.loop, .javascript])
            ) { b in
                b.emit(EndForOfLoop())
            },
        ]),

    CodeGenerator(
        "ForOfWithDestructLoopGenerator",
        [
            GeneratorStub(
                "ForOfWithDestructLoopBeginGenerator",
                inputs: .preferred(.iterable),
                provides: [.loop, .javascript]
            ) { b, obj in
                var indices: [Int64] = []
                for idx in 0..<Int64.random(in: 1..<5) {
                    withProbability(0.8) {
                        indices.append(idx)
                    }
                }

                if indices.isEmpty {
                    indices = [0]
                }

                b.emit(
                    BeginForOfLoopWithDestruct(
                        indices: indices, hasRestElement: probability(0.2)),
                    withInputs: [obj])
            },
            GeneratorStub(
                "ForOfWithDestructLoopEndGenerator",
                inContext: .single([.loop, .javascript])
            ) { b in
                b.emit(EndForOfLoop())
            },
        ]),

    CodeGenerator(
        "RepeatLoopGenerator",
        [
            GeneratorStub(
                "RepeatLoopBeginGenerator",
                produces: [.number], provides: [.loop, .javascript]
            ) { b in
                let numIterations = Int.random(in: 2...100)

                b.emit(BeginRepeatLoop(iterations: numIterations))
            },
            GeneratorStub(
                "RepeatLoopEndGenerator",
                inContext: .single([.loop, .javascript])
            ) { b in
                b.emit(EndRepeatLoop())
            },
        ]),

    CodeGenerator("LoopBreakGenerator", inContext: .single(.loop)) { b in
        b.loopBreak()
    },

    CodeGenerator("ContinueGenerator", inContext: .single(.loop)) { b in
        b.loopContinue()
    },

    CodeGenerator(
        "TryCatchFinallyGenerator",
        [
            GeneratorStub(
                "BeginTryGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginTry())
            },
            GeneratorStub(
                "BeginCatchGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginCatch())
            },
            GeneratorStub(
                "BeginFinallyGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginFinally())
            },
            GeneratorStub(
                "EndTryCatchFinallyGenerator",
                inContext: .single(.javascript)
            ) { b in
                b.emit(EndTryCatchFinally())
            },
        ]),

    CodeGenerator(
        "TryCatchGenerator",
        [
            GeneratorStub(
                "BeginTryGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginTry())
            },
            GeneratorStub(
                "BeginCatchGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginCatch())
            },
            GeneratorStub(
                "EndTryCatchFinallyGenerator",
                inContext: .single(.javascript)
            ) { b in
                b.emit(EndTryCatchFinally())
            },
        ]),

    CodeGenerator(
        "TryCatchGenerator",
        [
            GeneratorStub(
                "BeginTryGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginTry())
            },
            GeneratorStub(
                "BeginFinallyGenerator",
                inContext: .single(.javascript),
                provides: [.javascript]
            ) { b in
                b.emit(BeginFinally())
            },
            GeneratorStub(
                "EndTryCatchFinallyGenerator",
                inContext: .single(.javascript)
            ) { b in
                b.emit(EndTryCatchFinally())
            },
        ]),

    CodeGenerator("ThrowGenerator") { b in
        let v = b.randomJsVariable()
        b.throwException(v)
    },

    //
    // Language-specific Generators
    //

    CodeGenerator(
        "WellKnownPropertyLoadGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.createSymbolProperty(
            chooseUniform(from: JavaScriptEnvironment.wellKnownSymbols))
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getComputedProperty(propertyName, of: obj, guard: needGuard)
    },

    CodeGenerator(
        "WellKnownPropertyStoreGenerator", inputs: .preferred(.object())
    ) { b, obj in
        let propertyName = b.createSymbolProperty(
            chooseUniform(from: JavaScriptEnvironment.wellKnownSymbols))
        let val = b.randomJsVariable()
        b.setComputedProperty(propertyName, of: obj, to: val)
    },

    CodeGenerator("PrototypeAccessGenerator", inputs: .preferred(.object())) { b, obj in
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.getProperty("__proto__", of: obj, guard: needGuard)
    },

    CodeGenerator("PrototypeOverwriteGenerator", inputs: .preferred(.object(), .object())) { b, obj, proto in
        // Check for obj == proto to reduce the chance of cyclic prototype chains.
        let needGuard = b.type(of: obj).MayBe(.nullish) || obj == proto
        b.setProperty("__proto__", of: obj, to: proto, guard: needGuard)
    },

    CodeGenerator(
        "CallbackPropertyGenerator", inputs: .preferred(.object(), .function())
    ) { b, obj, callback in
        // TODO add new callbacks like Symbol.toPrimitive?
        let propertyName = chooseUniform(from: ["valueOf", "toString"])
        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.setProperty(propertyName, of: obj, to: callback, guard: needGuard)
    },

    CodeGenerator(
        "MethodCallWithDifferentThisGenerator",
        inputs: .preferred(.object(), .object())
    ) { b, obj, this in
        guard let methodName = b.type(of: obj).randomMethod() else { return }
        let arguments = b.randomArguments(forCallingMethod: methodName, on: obj)
        let Reflect = b.createNamedVariable(forBuiltin: "Reflect")
        let args = b.createArray(with: arguments)
        b.callMethod(
            "apply", on: Reflect,
            withArgs: [b.getProperty(methodName, of: obj), this, args])
    },

    CodeGenerator(
        "ConstructWithDifferentNewTargetGenerator",
        inputs: .preferred(.constructor(), .constructor())
    ) { b, newTarget, constructor in
        let reflect = b.createNamedVariable(forBuiltin: "Reflect")
        let arguments = [
            constructor,
            b.createArray(with: b.randomArguments(forCalling: constructor)),
            newTarget,
        ]
        b.callMethod("construct", on: reflect, withArgs: arguments)
    },

    CodeGenerator(
        "WeirdClassGenerator",
        [
            GeneratorStub(
                "WeirdClassBeginGenerator",
                provides: [.classDefinition]
            ) { b in
                // See basically https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Classes/Private_class_fields#examples
                let base = b.buildPlainFunction(with: .parameters(n: 1)) {
                    args in
                    b.doReturn(b.randomJsVariable())
                }
                b.emit(
                    BeginClassDefinition(hasSuperclass: true, isExpression: probability(0.3)),
                    withInputs: [base])
            },
            GeneratorStub(
                "WeirdClassGenerator",
                inContext: .single(.classDefinition)
            ) { b in
                b.emit(EndClassDefinition())
            },
        ]
    ),

    CodeGenerator("ProxyGenerator", inputs: .preferred(.object())) {
        b, target in
        var candidates = Set([
            "getPrototypeOf", "setPrototypeOf", "isExtensible",
            "preventExtensions", "getOwnPropertyDescriptor", "defineProperty",
            "has", "get", "set", "deleteProperty", "ownKeys", "apply", "call",
            "construct",
        ])

        var handlerProperties = [String: Variable]()
        for _ in 0..<Int.random(in: 0..<candidates.count) {
            let hook = chooseUniform(from: candidates)
            candidates.remove(hook)
            handlerProperties[hook] = b.randomVariable(ofType: .function())
        }
        let handler = b.createObject(with: handlerProperties)

        let Proxy = b.createNamedVariable(forBuiltin: "Proxy")
        b.hide(Proxy)  // We want the proxy to be used by following code generators, not the Proxy constructor
        b.construct(Proxy, withArgs: [target, handler])
    },

    CodeGenerator("PromiseGenerator", [
        GeneratorStub("PromiseBeginGenerator", provides: [.subroutine, .javascript]) { b in
            let randomParameters = b.randomParameters()
            b.setParameterTypesForNextSubroutine(
                randomParameters.parameterTypes)
            b.emit(
                BeginPlainFunction(parameters: randomParameters.parameters, functionName: nil))

        },
        GeneratorStub("PromiseEndGenerator", inContext: .single([.subroutine, .javascript])) { b in
            let handler = b.lastFunctionVariable
            b.emit(EndPlainFunction())
            let Promise = b.createNamedVariable(forBuiltin: "Promise")
            b.hide(Promise)  // We want the promise to be used by following code generators, not the Promise constructor
            b.construct(Promise, withArgs: [handler])
        },
    ]),

    // Tries to change the length property of some object
    CodeGenerator("LengthChangeGenerator", inputs: .preferred(.object())) {
        b, obj in
        let newLength: Variable
        if probability(0.5) {
            // Shrink
            newLength = b.loadInt(Int64.random(in: 0..<3))
        } else {
            // (Probably) grow
            newLength = b.loadInt(b.randomIndex())
        }

        let needGuard = b.type(of: obj).MayBe(.nullish)
        b.setProperty("length", of: obj, to: newLength, guard: needGuard)
    },

    // Tries to change the element kind of an array
    CodeGenerator("ElementKindChangeGenerator", inputs: .one) { b, obj in
        let value = b.randomJsVariable()
        b.setElement(Int64.random(in: 0..<10), of: obj, to: value)
    },

    // Generates a JavaScript 'with' statement
    CodeGenerator(
        "WithStatementGenerator",
        [
            GeneratorStub(
                "WithStatementBeginGenerator",
                inputs: .preferred(.object())
            ) { b, obj in
                b.emit(BeginWith(), withInputs: [obj])
                for i in 1...3 {
                    let propertyName =
                        b.type(of: obj).randomProperty()
                        ?? b.randomCustomPropertyName()
                    b.createNamedVariable(propertyName, declarationMode: .none)
                }
            },
            GeneratorStub(
                "WithStatementEndGenerator"
            ) { b in
                b.emit(EndWith())
            },
        ]),

    CodeGenerator("EvalGenerator", [
        GeneratorStub("EvalBeginGenerator", provides: [.javascript]) { b in
            b.emit(BeginCodeString())
        },
        GeneratorStub("EvalEndGenerator") { b in
            let code = b.lastFunctionVariable
            b.emit(EndCodeString())
            let eval = b.createNamedVariable(forBuiltin: "eval")
            b.callFunction(eval, withArgs: [code])
        },
    ]),

    CodeGenerator(
        "BlockStatementGenerator",
        [
            GeneratorStub("BlockStatementBeginGenerator") { b in
                b.emit(BeginBlockStatement())
            },
            GeneratorStub("BlockStatementEndGenerator") { b in
                b.emit(EndBlockStatement())
            },
        ]),

    CodeGenerator("NumberComputationGenerator") { b in
        // Generate a sequence of 3-7 random number computations on a couple of existing variables and some newly created constants.
        let numComputations = Int.random(in: 3...7)

        // Common mathematical operations are exposed through the Math builtin in JavaScript.
        let Math = b.createNamedVariable(forBuiltin: "Math")
        b.hide(Math)  // Following code generators should use the numbers generated below, not the Math object.

        var values = b.randomJsVariables(upTo: Int.random(in: 1...3))
        for _ in 0..<Int.random(in: 1...2) {
            values.append(b.loadInt(b.randomInt()))
        }
        for _ in 0..<Int.random(in: 0...1) {
            values.append(b.loadFloat(b.randomFloat()))
        }

        for _ in 0..<numComputations {
            withEqualProbability(
                {
                    values.append(
                        b.binary(
                            chooseUniform(from: values),
                            chooseUniform(from: values),
                            with: chooseUniform(from: BinaryOperator.allCases)))
                },
                {
                    values.append(
                        b.unary(
                            chooseUniform(from: UnaryOperator.allCases),
                            chooseUniform(from: values)))
                },
                {
                    // This can fail in tests, which lack the full JavaScriptEnvironment
                    guard let method = b.type(of: Math).randomMethod() else {
                        return
                    }
                    var args = [Variable]()
                    let sig = chooseUniform(
                        from: b.methodSignatures(of: method, on: Math))
                    for _ in 0..<sig.numParameters {
                        args.append(chooseUniform(from: values))
                    }
                    b.callMethod(method, on: Math, withArgs: args)
                })
        }
    },

    CodeGenerator("ImitationGenerator", inputs: .one) { b, orig in
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
                let toPrimitive = b.createSymbolProperty("toPrimitive")
                imitation = b.buildObjectLiteral { obj in
                    obj.addComputedMethod(toPrimitive, with: .parameters(n: 0))
                    { _ in
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
                let cls = b.buildClassDefinition(withSuperclass: constructor, isExpression: probability(0.3)) {
                    _ in
                    b.buildRecursive(n: 3)
                }
                imitation = b.construct(
                    cls, withArgs: b.randomArguments(forCalling: cls))
            } else {
                imitation = b.buildObjectLiteral { obj in
                    obj.setPrototype(to: orig)
                    b.buildRecursive(n: 3)
                }
            }
        } else {
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
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)]
        )
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.createNamedVariable(
            forBuiltin: chooseUniform(
                from: [
                    "Uint8Array", "Int8Array", "Uint16Array", "Int16Array",
                    "Uint32Array", "Int32Array", "Float32Array", "Float64Array",
                    "Uint8ClampedArray", "BigInt64Array", "BigUint64Array",
                    "DataView",
                ]
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
        let options = b.createObject(with: ["maxByteLength": b.loadInt(maxSize)]
        )
        let ab = b.construct(ArrayBuffer, withArgs: [b.loadInt(size), options])

        let View = b.createNamedVariable(
            forBuiltin: chooseUniform(
                from: [
                    "Uint8Array", "Int8Array", "Uint16Array", "Int16Array",
                    "Uint32Array", "Int32Array", "Float32Array", "Float64Array",
                    "Uint8ClampedArray", "BigInt64Array", "BigUint64Array",
                    "DataView",
                ]
            )
        )
        b.construct(View, withArgs: [ab])
    },

    CodeGenerator(
        "FastToSlowPropertiesGenerator", inputs: .preferred(.object())
    ) { b, o in
        // Build a loop that adds computed properties to an object which forces its
        // properties to transition from "fast properties" to "slow properties".
        // 32 seems to be enough for V8, which seems to be controlled by
        // kFastPropertiesSoftLimit.
        b.buildRepeatLoop(n: 32) { i in
            let prefixStr = b.loadString("p")
            let propertyName = b.binary(prefixStr, i, with: .Add)
            b.setComputedProperty(propertyName, of: o, to: i)
        }
    },

    // This code generator tries to build complex chains of similar objects. In V8 and other JS engines this will usually lead to
    // a tree of object shapes. This generator tries to emit code that helps to find bugs such as crbug.com/1412487 or crbug.com/1470668.
    // This generator could be generalized even further in the future.
    CodeGenerator("ObjectHierarchyGenerator", inputs: .four) {
        b, prop0, prop1, prop2, prop3 in
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

    CodeGenerator("IteratorGenerator", produces: [.iterable]) { b in
        let iteratorSymbol = b.createSymbolProperty("iterator")
        b.hide(iteratorSymbol)
        let iterableObject = b.buildObjectLiteral { obj in
            obj.addComputedMethod(iteratorSymbol, with: .parameters(n: 0)) {
                _ in
                let counter = b.loadInt(10)
                let iterator = b.buildObjectLiteral { obj in
                    obj.addMethod("next", with: .parameters(n: 0)) { _ in
                        b.unary(.PostDec, counter)
                        let done = b.compare(
                            counter, with: b.loadInt(0), using: .equal)
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

    CodeGenerator("LoadNewTargetGenerator", inContext: .single(.subroutine)) { b in
        b.loadNewTarget()
    },

    // TODO: think about merging this with the regular ConstructorCallGenerator.
    CodeGenerator(
        "ApiConstructorCallGenerator", inputs: .required(.constructor())
    ) { b, c in
        let signature = b.type(of: c).signature ?? Signature.forUnknownFunction

        b.buildTryCatchFinally(
            tryBody: {
                let args = b.findOrGenerateArguments(forSignature: signature)
                b.construct(c, withArgs: args)
            }, catchBody: { _ in })
    },

    // TODO: think about merging this with the regular MethodCallGenerator.
    CodeGenerator("ApiMethodCallGenerator", inputs: .required(.object())) {
        b, o in
        let methodName = b.type(of: o).randomMethod() ?? b.randomMethodName()

        let signature = chooseUniform(
            from: b.methodSignatures(of: methodName, on: o))

        b.buildTryCatchFinally(
            tryBody: {
                let args = b.findOrGenerateArguments(forSignature: signature)
                b.callMethod(methodName, on: o, withArgs: args)
            }, catchBody: { _ in })
    },

    CodeGenerator("ApiFunctionCallGenerator", inputs: .required(.function())) {
        b, f in
        let signature = b.type(of: f).signature ?? Signature.forUnknownFunction

        b.buildTryCatchFinally(
            tryBody: {
                let args = b.findOrGenerateArguments(forSignature: signature)
                b.callFunction(f, withArgs: args)
            }, catchBody: { _ in })
    },
]

extension Array where Element == GeneratorStub {
    public func get(_ name: String) -> GeneratorStub {
        for generator in self {
            if generator.name == name {
                return generator
            }
        }
        fatalError("Unknown code generator \(name)")
    }
}
