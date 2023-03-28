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

public class ProgramTemplate: Contributor {
    private let f: (ProgramBuilder) -> ()

    public init(_ name: String, _ f: @escaping (_: ProgramBuilder) -> ()) {
        self.f = f
        super.init(name: name)
    }

    public func generate(in b: ProgramBuilder) {
        assert(b.mode == .conservative)
        f(b)
    }

    /// Generate an array of random function signatures
    public static func generateRandomFunctionSignatures(forFuzzer fuzzer: Fuzzer, n: Int) -> [Signature] {
        var signatures = [Signature]()
        for _ in 0..<n {
            signatures.append(ProgramTemplate.generateSignature(forFuzzer: fuzzer, n: Int.random(in: 0...3)))
        }
        return signatures
    }

    /// Generate a random type to use in e.g. function signatures.
    /// This function should only emit types that can be constructed by ProgramBuilder.generateVariable.
    public static func generateType(forFuzzer fuzzer: Fuzzer, forProperty property: String = "") -> JSType {
        return withEqualProbability(
            // Choose a basic type
            { () -> JSType in
                chooseUniform(from: [.integer, .float, .boolean, .bigint, .string])
            },
            // Choose an array
            {
                return .object(ofGroup: "Array")
            },
            // choose a complicated object
            {
                var properties: [String] = []
                var methods: [String] = []

                // Generate random properties, but only if there is no custom group.
                // We filter the candidates to avoid cycles in our objects.
                // TODO: we should remove this "no-cycle" restriction here, and let `generateVariable`
                // handle these cases. We should also allow groups with custom properties/methods.
                for _ in 1..<3 {
                    let candidates = fuzzer.environment.customProperties.filter({ $0 > property })
                    if !candidates.isEmpty {
                        properties.append(chooseUniform(from: candidates))
                    }
                }

                // Generate random methods
                for _ in 1..<3 {
                    methods.append(chooseUniform(from: fuzzer.environment.customMethods))
                }

                return .object(withProperties: properties, withMethods: methods)
            })
    }

    /// Generate a random function signature.
    public static func generateSignature(forFuzzer fuzzer: Fuzzer, n: Int) -> Signature {
        var params: ParameterList = []
        for _ in 0..<n {
            params.append(.plain(generateType(forFuzzer: fuzzer)))
        }

        let returnType = generateType(forFuzzer: fuzzer)

        return Signature(expects: params, returns: returnType)
    }
}

