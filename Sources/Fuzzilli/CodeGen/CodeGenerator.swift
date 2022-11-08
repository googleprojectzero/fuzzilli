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
    func run(in b: ProgramBuilder, with inputs: [Variable])
}

public typealias GeneratorFuncNoArgs = (ProgramBuilder) -> ()
fileprivate struct GeneratorAdapterNoArgs: GeneratorAdapter {
    let f: GeneratorFuncNoArgs
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        f(b)
    }
}

public typealias GeneratorFunc1Arg = (ProgramBuilder, Variable) -> ()
fileprivate struct GeneratorAdapter1Arg: GeneratorAdapter {
    let f: GeneratorFunc1Arg
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        f(b, inputs[0])
    }
}

public typealias GeneratorFunc2Args = (ProgramBuilder, Variable, Variable) -> ()
fileprivate struct GeneratorAdapter2Args: GeneratorAdapter {
    let f: GeneratorFunc2Args
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        f(b, inputs[0], inputs[1])
    }
}

public class CodeGenerator: Contributor {
    /// The name of this code generator
    public let name: String

    /// Whether this code generator is recursive, i.e. will generate further code for example to generate the body of a block.
    /// This is used to determie whether to run a certain code generator. For example, if only a few more instructions should
    /// be generated during program building, calling a recursive code generator will likely result in too many instructions.
    public let isRecursive: Bool

    /// Types of input variables that are required for
    /// this code generator to run.
    public let inputTypes: [JSType]

    /// The contexts in which this code generator can run.
    /// This code generator will only be executed if requiredContext.isSubset(of: currentContext)
    public let requiredContext: Context

    /// Warpper around the actual generator function called.
    private let adapter: GeneratorAdapter

    fileprivate init(name: String, isRecursive: Bool, inputTypes: [JSType], context: Context = .javascript, adapter: GeneratorAdapter) {
        self.name = name
        self.isRecursive = isRecursive
        self.inputTypes = inputTypes
        self.requiredContext = context
        self.adapter = adapter
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
        self.init(name: name, isRecursive: false, inputTypes: [], context: context, adapter: GeneratorAdapterNoArgs(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, input type: JSType, _ f: @escaping GeneratorFunc1Arg) {
        self.init(name: name, isRecursive: false, inputTypes: [type], context: context, adapter: GeneratorAdapter1Arg(f: f))
    }

    public convenience init(_ name: String, inContext context: Context = .javascript, inputs types: (JSType, JSType), _ f: @escaping GeneratorFunc2Args) {
        self.init(name: name, isRecursive: false, inputTypes: [types.0, types.1], context: context, adapter: GeneratorAdapter2Args(f: f))
    }
}

// Constructors for recursive CodeGenerators.
public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, _ f: @escaping GeneratorFuncNoArgs) -> CodeGenerator {
    return CodeGenerator(name: name, isRecursive: true, inputTypes: [], context: context, adapter: GeneratorAdapterNoArgs(f: f))
}
public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, input type: JSType, _ f: @escaping GeneratorFunc1Arg) -> CodeGenerator {
    return CodeGenerator(name: name, isRecursive: true, inputTypes: [type], context: context, adapter: GeneratorAdapter1Arg(f: f))
}
public func RecursiveCodeGenerator(_ name: String, inContext context: Context = .javascript, inputs types: (JSType, JSType), _ f: @escaping GeneratorFunc2Args) -> CodeGenerator {
    return CodeGenerator(name: name, isRecursive: true, inputTypes: [types.0, types.1], context: context, adapter: GeneratorAdapter2Args(f: f))
}

