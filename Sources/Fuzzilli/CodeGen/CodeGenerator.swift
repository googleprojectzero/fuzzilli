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

protocol GeneratorAdapter {
    var expectedNumberOfInputs: Int { get }
    func run(in b: ProgramBuilder, with inputs: [Variable])
}

public typealias ValueGeneratorFunc = (ProgramBuilder, Int) -> ()
fileprivate struct ValueGeneratorAdapter: GeneratorAdapter {
    let expectedNumberOfInputs = 0
    let f: ValueGeneratorFunc
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.isEmpty)
        f(b, GeneratorStub.numberOfValuesToGenerateByValueGenerators)
    }
}

public typealias GeneratorFuncNoArgs = (ProgramBuilder) -> ()
fileprivate struct GeneratorAdapterNoArgs: GeneratorAdapter {
    let expectedNumberOfInputs = 0
    let f: GeneratorFuncNoArgs
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.isEmpty)
        f(b)
    }
}

public typealias GeneratorFunc1Arg = (ProgramBuilder, Variable) -> ()
fileprivate struct GeneratorAdapter1Arg: GeneratorAdapter {
    let expectedNumberOfInputs = 1
    let f: GeneratorFunc1Arg
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.count == 1)
        f(b, inputs[0])
    }
}

public typealias GeneratorFunc2Args = (ProgramBuilder, Variable, Variable) -> ()
fileprivate struct GeneratorAdapter2Args: GeneratorAdapter {
    let expectedNumberOfInputs = 2
    let f: GeneratorFunc2Args
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.count == 2)
        f(b, inputs[0], inputs[1])
    }
}

public typealias GeneratorFunc3Args = (ProgramBuilder, Variable, Variable, Variable) -> ()
fileprivate struct GeneratorAdapter3Args: GeneratorAdapter {
    let expectedNumberOfInputs = 3
    let f: GeneratorFunc3Args
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.count == 3)
        f(b, inputs[0], inputs[1], inputs[2])
    }
}

public typealias GeneratorFunc4Args = (ProgramBuilder, Variable, Variable, Variable, Variable) -> ()
fileprivate struct GeneratorAdapter4Args: GeneratorAdapter {
    let expectedNumberOfInputs = 4
    let f: GeneratorFunc4Args
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        assert(inputs.count == 4)
        f(b, inputs[0], inputs[1], inputs[2], inputs[3])
    }
}

public class GeneratorStub: Contributor {
    /// Whether this code generator is a value generator. A value generator will create at least one new variable containing
    /// a newly created value (e.g. a primitive value or some kind of object). Further, value generators must be able to
    /// run even if there are no existing variables. This way, they can be used to "bootstrap" code generation.
    public var isValueStub: Bool {
        self.inputs.isEmpty && !self.produces.isEmpty
    }

    /// How many different values of the same type ValueGenerators should aim to generate.
    public static let numberOfValuesToGenerateByValueGenerators = 3

    /// Describes the inputs expected by a CodeGenerator.
    public struct Inputs {
        /// How the inputs should be treated.
        public enum Mode {
            /// The default: the code generator would like to receive inputs of the specified
            /// type but it can also operate on inputs of other types, in particular on inputs
            /// of unknown types. This ensures that most variables can be used as inputs.
            case loose
            /// In this mode, the code generator will only be invoked with inputs that are
            /// statically known to have the desired types. In particular, no variables of
            /// unknown types will be used (unless the input type is .jsAnything).
            case strict
        }

        public let types: [ILType]
        public let mode: Mode
        public var count: Int {
            return types.count
        }

        public var isEmpty: Bool {
            types.count == 0
        }

        // No inputs.
        public static var none: Inputs {
            return Inputs(types: [], mode: .loose)
        }

        // One input of type .jsAnything
        public static var one: Inputs {
            return Inputs(types: [.jsAnything], mode: .loose)
        }

        // One input of a wasmPrimitive and it has to be strict to ensure type correctness.
        public static var oneWasmPrimitive: Inputs {
            return Inputs(types: [.wasmPrimitive], mode: .strict)
        }

        public static var oneWasmNumericalPrimitive: Inputs {
            return Inputs(types: [.wasmNumericalPrimitive], mode: .strict)
        }

        // Two inputs of type .jsAnything
        public static var two: Inputs {
            return Inputs(types: [.jsAnything, .jsAnything], mode: .loose)
        }

        // Three inputs of type .jsAnything
        public static var three: Inputs {
            return Inputs(types: [.jsAnything, .jsAnything, .jsAnything], mode: .loose)
        }

        // Four inputs of type .jsAnything
        public static var four: Inputs {
            return Inputs(types: [.jsAnything, .jsAnything, .jsAnything, .jsAnything], mode: .loose)
        }


        // A number of inputs that should have the specified type, but may also be of a wider, or even different, type.
        // This should usually be used instead of .required since it will ensure that also variables of unknown type can
        // be used as inputs during code generation.
        public static func preferred(_ types: ILType...) -> Inputs {
            assert(!types.isEmpty)
            return Inputs(types: types, mode: .loose)
        }

        // A number of inputs that must have the specified type.
        // Only use this if the code generator cannot do anything meaningful if it receives a value of the wrong type.
        public static func required(_ types: ILType...) -> Inputs {
            assert(!types.isEmpty)
            return Inputs(types: types, mode: .strict)
        }
    }
    /// The inputs expected by this generator.
    public let inputs: Inputs

    /// The types this CodeGenerator produces
    /// ProgramBuilding will assert that these types are (newly) available after running this CodeGenerator.
    public let produces: [ILType]

    public enum ContextRequirement {
        // If this GeneratorStub has a single Context requirement, which may still be comprised of multiple Context values.
        // E.g. .single([.javascript | .method]) or .single([.javascript, .method]) (they're equivalent).
        case single(Context)
        // If this GeneratorStub has any one of the Context requirements.
        // E.g. .either([.javascript, .classDefinition]) which is basically either one of .javascript or .classDefinition
        case either([Context])

        var isSingle : Bool {
            self.getSingle() != nil
        }

        var isJavascript: Bool {
            self.getSingle() == .javascript
        }

        func getSingle() -> Context? {
            switch self {
                case .single(let ctx):
                    return ctx
                default:
                    return nil
            }
        }

        // Whether the ContextRequirement is satisified for the given (current) context.
        func satisfied(by context: Context) -> Bool {
            switch self {
                case .single(let ctx):
                    return ctx.isSubset(of: context)
                case .either(let ctxs):
                    // We do this check here since we cannot check on construction whether we have used .either correctly.
                    assert(ctxs.count > 1, "Something seems wrong, one should have more than a single context here")
                    // Any of the Contexts needs to be satisfied.
                    return ctxs.contains(where: { ctx in
                        ctx.isSubset(of: context)
                    })
            }
        }

        // Whether the provided Context is exactly the required context.
        // Usually this means that if it is `.either` all the those Contexts need to be there.
        // This is used in consistency checking in `ContextGraph` initialization where a previous generator might open multiple contexts.
        func matches(_ context: Context) -> Bool {
            switch self {
                case .single(let ctx):
                    return ctx == context
                case .either(let ctxs):
                    // We do this check here since we cannot check on construction whether we have used .either correctly.
                    assert(ctxs.count > 1, "Something seems wrong, one should have more than a single context here")
                    // All contexts need to be in the current context.
                    return ctxs.allSatisfy { ctx in
                        ctx.isSubset(of: context)
                    }
            }
        }
    }

    /// The contexts in which this code generator can run.
    /// This is an Array of subsets of Contexts, one of them has to be runnable.
    /// An invariant is now, that a Generator *cannot* `provide` any Context if it might open either one of multiple Contexts.
    /// We are checking the other direction of this in the initialization of `ContextGraph`.
    /// This code generator will only be executed if any requiredContext.isSubset(of: currentContext)
    public let requiredContext: ContextRequirement

    /// The context that is provided by running this Generator.
    /// This is always a list of the single contexts that are provided, e.g. [.javascript]
    public let providedContext: [Context]

    /// Warpper around the actual generator function called.
    private let adapter: GeneratorAdapter

    fileprivate init(name: String, inputs: Inputs, produces: [ILType] = [], context: ContextRequirement, providedContext: [Context] = [], adapter: GeneratorAdapter) {

        self.inputs = inputs
        self.produces = produces
        self.requiredContext = context
        self.providedContext = providedContext
        self.adapter = adapter
        super.init(name: name)

        assert(inputs.count == adapter.expectedNumberOfInputs)
    }

    /// Execute this code generator, generating new code at the current position in the ProgramBuilder.
    /// Returns the number of generated instructions.
    public func run(in b: ProgramBuilder, with inputs: [Variable]) -> Int {
        let codeSizeBeforeGeneration = b.indexOfNextInstruction()
        adapter.run(in: b, with: inputs)
        self.invoked()
        let codeSizeAfterGeneration = b.indexOfNextInstruction()
        let addedInstructions = codeSizeAfterGeneration - codeSizeBeforeGeneration
        self.addedInstructions(addedInstructions)
        return addedInstructions
    }

    public convenience init(_ name: String, inContext context: ContextRequirement = .single(.javascript), produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFuncNoArgs) {
        self.init(name: name, inputs: .none, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapterNoArgs(f: f))
    }

    public convenience init(_ name: String, inContext context: ContextRequirement = .single(.javascript), inputs: Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc1Arg) {
        assert(inputs.count == 1)
        self.init(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter1Arg(f: f))
    }

    public convenience init(_ name: String, inContext context: ContextRequirement = .single(.javascript), inputs: Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc2Args) {
        assert(inputs.count == 2)
        self.init(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter2Args(f: f))
    }

    public convenience init(_ name: String, inContext context: ContextRequirement = .single(.javascript), inputs: Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc3Args) {
        assert(inputs.count == 3)
        self.init(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter3Args(f: f))
    }

    public convenience init(_ name: String, inContext context: ContextRequirement = .single(.javascript), inputs: Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc4Args) {
        assert(inputs.count == 4)
        self.init(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter4Args(f: f))
    }
}

public class CodeGenerator {
    let parts: [GeneratorStub]
    public let name: String
    // This is a pre-calculated array of contexts that is provided by this CodeGenerator
    // Here, I think we might have different Contexts that each yield point could provide, e.g. [.javascript | .subroutine, .wasmFunction]. Unsure if there is a situation where this matters? instead of having .javascript | .subroutine | .wasmFunction?
    public let providedContexts: [Context]


    public init(_ name: String, _ generators: [GeneratorStub]) {
        self.parts = generators
        self.name = name

        // Calculate all contexts provided at any time by this CodeGenerator.
        var ctxSet = Set<Context>()
        generators.forEach { gen in
            gen.providedContext.forEach { ctx in
                ctxSet.insert(ctx)
            }
        }

        self.providedContexts = Array(ctxSet)
    }

    // This essentially means that all stubs have no requirements.
    // Usually there is only a single element in the CodeGenerator if it is a ValueGenerator.
    public var isValueGenerator: Bool {
        return self.parts.allSatisfy {$0.isValueStub}
    }

    // This is the context required by the first part of the CodeGenerator.
    public var requiredContext: Context {
        // This has to be a single one for the first Generator.
        // Current limitation of the Generation Logic.
        assert(self.parts.first!.requiredContext.isSingle)
        return self.parts.first!.requiredContext.getSingle()!
    }

    // TODO(cffsmith): Maybe return an array of ILType Arrays, essentially describing at which yield point which type is available?
    // This would allow us to maybe use "innerOutputs" to find suitable points to insert other Generators (that require such types).
    // Slight complication is that some variables will only be in scope inside the CodeGenerator, e.g. if there is an EndWasmModule somewhere all Wasm variables will go out of scope.
    public var produces: [ILType] {
        return self.parts.last!.produces
    }

    public var head: GeneratorStub {
        return self.parts.first!
    }

    // The tail of this CodeGenerator.
    public var tail: Array<GeneratorStub>.SubSequence {
        return self.parts[1...]
    }

    public var expandedName : String {
        if self.name == "Synthetic" {
            return "Synthetic(\(self.parts.map{$0.name}.joined(separator: ",")))"
        } else {
            return self.name
        }
    }

    public convenience init(_ name: String, inContext context: GeneratorStub.ContextRequirement = .single(.javascript), produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFuncNoArgs) {
        self.init(name, [GeneratorStub(name: name, inputs: .none, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapterNoArgs(f: f))])
    }

    public convenience init(_ name: String, inContext context: GeneratorStub.ContextRequirement = .single(.javascript), inputs: GeneratorStub.Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc1Arg) {
        assert(inputs.count == 1)
        self.init(name, [GeneratorStub(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter1Arg(f: f))])
    }

    public convenience init(_ name: String, inContext context: GeneratorStub.ContextRequirement = .single(.javascript), inputs: GeneratorStub.Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc2Args) {
        assert(inputs.count == 2)
        self.init(name, [GeneratorStub(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter2Args(f: f))])
    }

    public convenience init(_ name: String, inContext context: GeneratorStub.ContextRequirement = .single(.javascript), inputs: GeneratorStub.Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc3Args) {
        assert(inputs.count == 3)
        self.init(name, [GeneratorStub(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter3Args(f: f))])
    }

    public convenience init(_ name: String, inContext context: GeneratorStub.ContextRequirement = .single(.javascript), inputs: GeneratorStub.Inputs, produces: [ILType] = [], provides: [Context] = [], _ f: @escaping GeneratorFunc4Args) {
        assert(inputs.count == 4)
        self.init(name, [GeneratorStub(name: name, inputs: inputs, produces: produces, context: context, providedContext: provides, adapter: GeneratorAdapter4Args(f: f))])
    }
}

extension CodeGenerator: CustomStringConvertible {
    public var description: String {
        let names = self.parts.map { $0.name }
        return names.joined(separator: ",")
    }
}