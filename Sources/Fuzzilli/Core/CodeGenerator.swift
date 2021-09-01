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
        return f(b)
    }
}

public typealias GeneratorFunc1Arg = (ProgramBuilder, Variable) -> ()
fileprivate struct GeneratorAdapter1Arg: GeneratorAdapter {
    let f: GeneratorFunc1Arg
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        return f(b, inputs[0])
    }
}

public typealias GeneratorFunc2Args = (ProgramBuilder, Variable, Variable) -> ()
fileprivate struct GeneratorAdapter2Args: GeneratorAdapter {
    let f: GeneratorFunc2Args
    func run(in b: ProgramBuilder, with inputs: [Variable]) {
        return f(b, inputs[0], inputs[1])
    }
}

public struct CodeGenerator {
    /// The name of this code generator
    public let name: String

    /// Types of input variables that are required for
    /// this code generator to run.
    public let inputTypes: [Type]

    /// The contexts in which this code generator can run.
    /// This code generator will only be executed if requiredContext.isSubset(of: currentContext)
    public let requiredContext: Context

    /// Warpper around the actual generator function called.
    private let adapter: GeneratorAdapter

    private init(name: String, inputTypes: [Type], context: Context = .script, adapter: GeneratorAdapter) {
        self.name = name
        self.inputTypes = inputTypes
        self.requiredContext = context
        self.adapter = adapter
    }

    /// Execute this code generator, generating new code at the current position in the ProgramBuilder.
    public func run(in b: ProgramBuilder, with inputs: [Variable]) {
        return adapter.run(in: b, with: inputs)
    }

    public init(_ name: String, inContext context: Context = .script, _ f: @escaping GeneratorFuncNoArgs) {
        self.init(name: name, inputTypes: [], context: context, adapter: GeneratorAdapterNoArgs(f: f))
    }

    public init(_ name: String, inContext context: Context = .script, input type: Type, _ f: @escaping GeneratorFunc1Arg) {
        self.init(name: name, inputTypes: [type], context: context, adapter: GeneratorAdapter1Arg(f: f))
    }

    public init(_ name: String, inContext context: Context = .script, inputs types: (Type, Type), _ f: @escaping GeneratorFunc2Args) {
        self.init(name: name, inputTypes: [types.0, types.1], context: context, adapter: GeneratorAdapter2Args(f: f))
    }
}
