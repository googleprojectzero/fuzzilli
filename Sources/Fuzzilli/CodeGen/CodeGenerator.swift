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
        f(b, CodeGenerator.numberOfValuesToGenerateByValueGenerators)
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

public class CodeGenerator: Contributor {
    /// Whether this code generator is a value generator. A value generator will create at least one new variable containing
    /// a newly created value (e.g. a primitive value or some kind of object). Further, value generators must be able to
    /// run even if there are no existing variables. This way, they can be used to "bootstrap" code generation.
    public let isValueGenerator: Bool

    /// How many different values of the same type ValueGenerators should aim to generate.
    public static let numberOfValuesToGenerateByValueGenerators = 3

    /// Whether this code generator is recursive, i.e. will generate further code for example to generate the body of a block.
    /// This is used to determie whether to run a certain code generator. For example, if only a few more instructions should
    /// be generated during program building, calling a recursive code generator will likely result in too many instructions.
    public let isRecursive: Bool

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
            /// unknown types will be used (unless the input type is .anything).
            case strict
        }

        public let types: [ILType]
        public let mode: Mode
        public var count: Int {
            return types.count
        }

        // No inputs.
        public static var none: Inputs {
            return Inputs(types: [], mode: .loose)
        }

        // One input of type .anything
        public static var one: Inputs {
            return Inputs(types: [.anything], mode: .loose)
        }

        // One input of a wasmPrimitive and it has to be strict to ensure type correctness.
        public static var oneWasmPrimitive: Inputs {
            return Inputs(types: [.wasmPrimitive], mode: .strict)
        }

        public static var oneWasmNumericalPrimitive: Inputs {
            return Inputs(types: [.wasmNumericalPrimitive], mode: .strict)
        }

        // Two inputs of type .anything
        public static var two: Inputs {
            return Inputs(types: [.anything, .anything], mode: .loose)
        }

        // Three inputs of type .anything
        public static var three: Inputs {
            return Inputs(types: [.anything, .anything, .anything], mode: .loose)
        }

        // Four inputs of type .anything
        public static var four: Inputs {
            return Inputs(types: [.anything, .anything, .anything, .anything], mode: .loose)
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

    /// The contexts in which this code generator can run.
    /// This code generator will only be executed if requiredContext.isSubset(of: currentContext)
    public let requiredContext: Context

    /// Warpper around the actual generator function called.
    private let adapter: GeneratorAdapter

    fileprivate init(name: String, isValueGenerator: Bool, isRecursive: Bool, inputs: Inputs, context: Context, adapter: GeneratorAdapter) {
        assert(!isValueGenerator || context.isValueBuildableContext)
        assert(!isValueGenerator || inputs.count == 0)
        assert(inputs.count == adapter.expectedNumberOfInputs)

        self.isValueGenerator = isValueGenerator
        self.isRecursive = isRecursive
        self.inputs = inputs
        self.requiredContext = context
        self.adapter = adapter
        super.init(name: name)
    }

    /// Execute this code generator, generating new code at the current position in the ProgramBuilder.
    /// Returns the number of generated instructions.
    public func run(in b: ProgramBuilder, with inputs: [Variable]) -> Int {
        let codeSizeBeforeGeneration = b.indexOfNextInstruction()
        adapter.run(in: b, with: inputs)
        let codeSizeAfterGeneration = b.indexOfNextInstruction()
        assert(codeSizeAfterGeneration >= codeSizeBeforeGeneration)
        return codeSizeAfterGeneration - codeSizeBeforeGeneration
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, _ f: @escaping GeneratorFuncNoArgs) {
        self.init(name: name, isValueGenerator: false, isRecursive: false, inputs: .none, context: context, adapter: GeneratorAdapterNoArgs(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, inputs: Inputs, _ f: @escaping GeneratorFunc1Arg) {
        assert(inputs.count == 1)
        self.init(name: name, isValueGenerator: false, isRecursive: false, inputs: inputs, context: context, adapter: GeneratorAdapter1Arg(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, inputs: Inputs, _ f: @escaping GeneratorFunc2Args) {
        assert(inputs.count == 2)
        self.init(name: name, isValueGenerator: false, isRecursive: false, inputs: inputs, context: context, adapter: GeneratorAdapter2Args(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, inputs: Inputs, _ f: @escaping GeneratorFunc3Args) {
        assert(inputs.count == 3)
        self.init(name: name, isValueGenerator: false, isRecursive: false, inputs: inputs, context: context, adapter: GeneratorAdapter3Args(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, inputs: Inputs, _ f: @escaping GeneratorFunc4Args) {
        assert(inputs.count == 4)
        self.init(name: name, isValueGenerator: false, isRecursive: false, inputs: inputs, context: context, adapter: GeneratorAdapter4Args(f: f))
    }
}

// Constructors for recursive CodeGenerators.
public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, _ f: @escaping GeneratorFuncNoArgs) -> CodeGenerator {
    return CodeGenerator(name: name, isValueGenerator: false, isRecursive: true, inputs: .none, context: context, adapter: GeneratorAdapterNoArgs(f: f))
}

public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, inputs: CodeGenerator.Inputs, _ f: @escaping GeneratorFunc1Arg) -> CodeGenerator {
    assert(inputs.count == 1)
    return CodeGenerator(name: name, isValueGenerator: false, isRecursive: true, inputs: inputs, context: context, adapter: GeneratorAdapter1Arg(f: f))
}

public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, inputs: CodeGenerator.Inputs, _ f: @escaping GeneratorFunc2Args) -> CodeGenerator {
    assert(inputs.count == 2)
    return CodeGenerator(name: name, isValueGenerator: false, isRecursive: true, inputs: inputs, context: context, adapter: GeneratorAdapter2Args(f: f))
}

// Constructors for ValueGenerators. A ValueGenerator is a CodeGenerator that produces one or more variables containing newly created values/objects.
// Further, a ValueGenerator must be able to run when there are no existing variables so that it can be used to bootstrap code generation.
public func ValueGenerator(_ name: String, _ f: @escaping ValueGeneratorFunc) -> CodeGenerator {
    return CodeGenerator(name: name, isValueGenerator: true, isRecursive: false, inputs: .none, context: .javascript, adapter: ValueGeneratorAdapter(f: f))
}

public func ValueGenerator(_ name: String, inContext context: Context, _ f: @escaping ValueGeneratorFunc) -> CodeGenerator {
    return CodeGenerator(name: name, isValueGenerator: true, isRecursive: false, inputs: .none, context: context, adapter: ValueGeneratorAdapter(f: f))
}

public func RecursiveValueGenerator(_ name: String, _ f: @escaping ValueGeneratorFunc) -> CodeGenerator {
    return CodeGenerator(name: name, isValueGenerator: true, isRecursive: true, inputs: .none, context: .javascript, adapter: ValueGeneratorAdapter(f: f))
}
