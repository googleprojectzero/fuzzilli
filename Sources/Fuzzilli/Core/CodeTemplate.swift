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

public class CodeTemplate {
    public let name: String

    public var stats = ProgramGeneratorStats()

    private let f: (ProgramBuilder) -> ()

    init(_ name: String, _ f: @escaping (_: ProgramBuilder) -> ()) {
        self.name = name
        self.f = f
    }

    func run(in b: ProgramBuilder) {
        f(b)
    }

    /// Generate an array of random function signatures
    static func generateRandomFunctionSignatures(forFuzzer fuzzer: Fuzzer, n: Int) -> [FunctionSignature] {
        var signatures = [FunctionSignature]()
        signatures.append(CodeTemplate.generateSignature(forFuzzer: fuzzer, n: Int.random(in: 0...3)))
        return signatures
    }

    /// This function generates and sets property types for the global properties
    static func generateRandomPropertyTypes(forBuilder b: ProgramBuilder) {
        for _ in 0..<5 {
            let name = chooseUniform(from: b.fuzzer.environment.customPropertyNames.dropLast())
            b.setType(ofProperty: name, to: CodeTemplate.generateType(forFuzzer: b.fuzzer, forProperty: name))
        }
    }

    /// Generate and set random method types for global method names.
    static func generateRandomMethodTypes(forBuilder b: ProgramBuilder, n: Int) {
        for _ in 0..<n {
            b.setSignature(ofMethod: chooseUniform(from:
                b.fuzzer.environment.methodNames), to: CodeTemplate.generateSignature(forFuzzer:
                b.fuzzer, n: Int.random(in: 0..<3)))
        }
    }

    /// Generate a random type to use in e.g. function signatures.
    /// This function should only emit types that can be constructed by ProgramBuilder.generateVariable.
    static func generateType(forFuzzer fuzzer: Fuzzer, forProperty property: String = "") -> Type {
        return withEqualProbability(
            // Choose a basic type
            { () -> Type in
                chooseUniform(from: [.integer, .float, .boolean, .bigint])
            },
            // Choose an array
            {
                return .object(ofGroup: "Array")
            },
            // choose a complicated object
            {
                var properties: [String] = []
                var methods: [String] = []

                // Generate random properties
                for _ in 1..<3 {
                    let candidates = fuzzer.environment.customPropertyNames.filter({ $0 >= property })
                    properties.append(chooseUniform(from: candidates))
                }

                // Generate random methods
                for _ in 1..<3 {
                    methods.append(chooseUniform(from: fuzzer.environment.methodNames))
                }

                return .object(withProperties: properties, withMethods: methods)
            })
            // TODO: emit functions here as well?
    }

    /// Generate a random function signature.
    static func generateSignature(forFuzzer fuzzer: Fuzzer, n: Int) -> FunctionSignature {
        var params: [Type] = []
        for _ in 0..<n {
            params.append(generateType(forFuzzer: fuzzer))
        }

        let returnType = generateType(forFuzzer: fuzzer)

        return FunctionSignature(expects: params, returns: returnType)
    }
}

