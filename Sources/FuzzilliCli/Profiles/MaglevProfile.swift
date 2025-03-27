import Fuzzilli

fileprivate let GcGenerator = CodeGenerator("GcGenerator") { b in
    let type = b.loadString(probability(0.25) ? "major" : "minor")
    let execution = b.loadString(probability(0.5) ? "sync" : "async")
    b.callFunction(b.callFunction(b.createNamedVariable(forBuiltin: "gc")), withArgs: [b.createObject(with: ["type": type, "execution": execution])])
}

fileprivate let ForceOSRThroughLoopGenerator = RecursiveCodeGenerator("ForceOSRThroughLoopGenerator") { b in
    let numIterations = 100
    b.buildRepeatLoop(n: numIterations) { i in
        b.buildRecursive()
        let selectedIteration = withEqualProbability({
            assert(numIterations > 10)
            return Int.random(in: (numIterations - 10)..<numIterations)
        }, {
            return Int.random(in: 0..<numIterations)
        })
        let cond = b.compare(i, with: b.loadInt(Int64(selectedIteration)), using: .equal)
        b.buildIf(cond) {
            b.eval("%OptimizeOsr()")
        }
    }
}

fileprivate let MapTransitionFuzzer = ProgramTemplate("MapTransitionFuzzer") { b in
    let propertyNames = b.fuzzer.environment.customProperties
    assert(Set(propertyNames).isDisjoint(with: b.fuzzer.environment.customMethods))

    assert(propertyNames.contains("a"))
    let objType = ILType.object(withProperties: ["a"])

    func randomProperties(in b: ProgramBuilder) -> ([String], [Variable]) {
        if !b.hasVisibleVariables {
            b.loadInt(b.randomInt())
        }

        var properties = ["a"]
        var values = [b.randomVariable()]
        for _ in 0..<3 {
            let property = chooseUniform(from: propertyNames)
            guard !properties.contains(property) else { continue }
            properties.append(property)
            values.append(b.randomVariable())
        }
        assert(Set(properties).count == values.count)
        return (properties, values)
    }

    let primitiveValueGenerator = ValueGenerator("PrimitiveValue") { b, n in
        for _ in 0..<n {
            withEqualProbability({
                b.loadInt(b.randomInt())
            }, {
                b.loadFloat(b.randomFloat())
            }, {
                b.loadString(b.randomString())
            })
        }
    }
    let createObjectGenerator = ValueGenerator("CreateObject") { b, n in
        for _ in 0..<n {
            let (properties, values) = randomProperties(in: b)
            let obj = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectMakerGenerator = ValueGenerator("ObjectMaker") { b, n in
        let f = b.buildPlainFunction(with: b.randomParameters()) { args in
            let (properties, values) = randomProperties(in: b)
            let o = b.createObject(with: Dictionary(uniqueKeysWithValues: zip(properties, values)))
            b.doReturn(o)
        }
        for _ in 0..<n {
            let obj = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectConstructorGenerator = ValueGenerator("ObjectConstructor") { b, n in
        let c = b.buildConstructor(with: b.randomParameters()) { args in
            let this = args[0]
            let (properties, values) = randomProperties(in: b)
            for (p, v) in zip(properties, values) {
                b.setProperty(p, of: this, to: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(c, withArgs: b.randomArguments(forCalling: c))
            assert(b.type(of: obj).Is(objType))
        }
    }
    let objectClassGenerator = ValueGenerator("ObjectClassGenerator") { b, n in
        let superclass = b.hasVisibleVariables && probability(0.5) ? b.randomVariable(ofType: .constructor()) : nil
        let (properties, values) = randomProperties(in: b)
        let cls = b.buildClassDefinition(withSuperclass: superclass) { cls in
            for (p, v) in zip(properties, values) {
                cls.addInstanceProperty(p, value: v)
            }
        }
        for _ in 0..<n {
            let obj = b.construct(cls)
            assert(b.type(of: obj).Is(objType))
        }
    }
    let propertyLoadGenerator = CodeGenerator("PropertyLoad", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.getProperty(chooseUniform(from: propertyNames), of: obj)
    }
    let propertyStoreGenerator = CodeGenerator("PropertyStore", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        let numProperties = Int.random(in: 1...3)
        for _ in 0..<numProperties {
            b.setProperty(chooseUniform(from: propertyNames), of: obj, to: b.randomVariable())
        }
    }
    let propertyConfigureGenerator = CodeGenerator("PropertyConfigure", inputs: .required(objType)) { b, obj in
        assert(b.type(of: obj).Is(objType))
        b.configureProperty(chooseUniform(from: propertyNames), of: obj, usingFlags: PropertyFlags.random(), as: .value(b.randomVariable()))
    }
    let functionDefinitionGenerator = RecursiveCodeGenerator("FunctionDefinition") { b in
        var parameters = b.randomParameters()
        let haveVisibleObjects = b.visibleVariables.contains(where: { b.type(of: $0).Is(objType) })
        if probability(0.5) && haveVisibleObjects {
            parameters = .parameters(.plain(objType), .plain(objType), .anything, .anything)
        }

        let f = b.buildPlainFunction(with: parameters) { params in
            b.buildRecursive()
            b.doReturn(b.randomVariable())
        }

        for _ in 0..<3 {
            b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
        }
    }
    let functionCallGenerator = CodeGenerator("FunctionCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let rval = b.callFunction(f, withArgs: b.randomArguments(forCalling: f))
    }
    let constructorCallGenerator = CodeGenerator("ConstructorCall", inputs: .required(.constructor())) { b, c in
        assert(b.type(of: c).Is(.constructor()))
        let rval = b.construct(c, withArgs: b.randomArguments(forCalling: c))
     }
    let functionJitCallGenerator = CodeGenerator("FunctionJitCall", inputs: .required(.function())) { b, f in
        assert(b.type(of: f).Is(.function()))
        let args = b.randomArguments(forCalling: f)
        b.buildRepeatLoop(n: 100) { _ in
            b.callFunction(f, withArgs: args)
        }
    }

    let prevCodeGenerators = b.fuzzer.codeGenerators
    b.fuzzer.setCodeGenerators(WeightedList<CodeGenerator>([
        (primitiveValueGenerator,     2),
        (createObjectGenerator,       1),
        (objectMakerGenerator,        1),
        (objectConstructorGenerator,  1),
        (objectClassGenerator,        1),

        (propertyStoreGenerator,      10),
        (propertyLoadGenerator,       10),
        (propertyConfigureGenerator,  5),
        (functionDefinitionGenerator, 2),
        (functionCallGenerator,       3),
        (constructorCallGenerator,    2),
        (functionJitCallGenerator,    2)
    ]))

    b.buildPrefix()
    b.build(n: 100, by: .generating)

    b.fuzzer.setCodeGenerators(prevCodeGenerators)
    b.build(n: 10)

    for obj in b.visibleVariables where b.type(of: obj).Is(objType) {
        b.eval("%HeapObjectVerify(%@)", with: [obj])
    }
}

fileprivate let ForceMaglevCompilationGenerator = CodeGenerator("ForceMaglevCompilationGenerator", inputs: .required(.function())) { b, f in
    assert(b.type(of: f).Is(.function()))
    let arguments = b.randomArguments(forCalling: f)

    b.callFunction(f, withArgs: arguments)

    b.eval("%PrepareFunctionForOptimization(%@)", with: [f])

    b.callFunction(f, withArgs: arguments)
    b.callFunction(f, withArgs: arguments)

    b.eval("%OptimizeMaglevOnNextCall(%@)", with: [f])

    b.callFunction(f, withArgs: arguments)
}

let maglevProfile = Profile(
    processArgs: { (randomize) in 
        var args = [
            "--expose-gc",
            "--omit-quit",
            "--allow-natives-syntax",
            "--fuzzing",
            "--jit-fuzzing",
            "--future",
            "--harmony",
            "--js-staging",
            "--concurrent-maglev-max-threads=1",
            "--no-concurrent_recompilation",
        ]

        guard randomize else { return args; }

        return args;
    },

    processEnv: [:],
    maxExecsBeforeRespawn: 1000,
    timeout: 250,

    codePrefix: """
    fuzzilli(\"FUZZILLI_PROBABILITY\", 0.2);

    // -------- BEGIN --------
    """,
    codeSuffix: "",

    ecmaVersion: ECMAScriptVersion.es6,
    startupTests: [
        ("fuzzilli('FUZZILLI_PRINT', 'test')", .shouldSucceed),

        ("fuzzilli('FUZZILLI_CRASH', 0)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 1)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 2)", .shouldCrash),
        ("fuzzilli('FUZZILLI_CRASH', 3)", .shouldCrash),
    ],

    additionalCodeGenerators: [
        (GcGenerator, 10),
        (ForceMaglevCompilationGenerator, 5),
        (ForceOSRThroughLoopGenerator, 5),
    ],
    additionalProgramTemplates: WeightedList<ProgramTemplate>([
        (MapTransitionFuzzer,    1),
    ]),

    disabledCodeGenerators: [],
    disabledMutators: [],

    additionalBuiltins: [
        "gc" : .function([] => (.undefined | .jsPromise))
    ],

    additionalObjectGroups: [],
    optionalPostProcessor: nil
)