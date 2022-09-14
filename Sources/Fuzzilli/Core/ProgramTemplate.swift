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

public class ProgramTemplate {
    /// Name of this ProgramTemplate. Mostly used for statistical purposes.
    public let name: String

    /// Stats for this ProgramTemplate. Mostly to compute correctness rates.
    public var stats = ProgramProducerStats()

    private let f: (ProgramBuilder) -> ()

    public init(_ name: String, _ f: @escaping (_: ProgramBuilder) -> ()) {
        self.name = name
        self.f = f
    }

    public func generate(in b: ProgramBuilder) {
        Assert(b.mode == .conservative)
        f(b)
    }

    /// Generate an array of random function signatures
    public static func generateRandomFunctionSignatures(forFuzzer fuzzer: Fuzzer, n: Int) -> [FunctionSignature] {
        var signatures = [FunctionSignature]()
        for _ in 0..<n {
            signatures.append(ProgramTemplate.generateSignature(forFuzzer: fuzzer, n: Int.random(in: 0...3)))
        }
        return signatures
    }

    /// This function generates and sets property types for the global properties
    public static func generateRandomPropertyTypes(forBuilder b: ProgramBuilder) {
        // generate types for half of the available property names.
        for i in 0..<b.fuzzer.environment.customPropertyNames.count/2 {
            let name = Array(b.fuzzer.environment.customPropertyNames)[i]
            b.setType(ofProperty: name, to: ProgramTemplate.generateType(forFuzzer: b.fuzzer, forProperty: name))
        }
    }

    /// Generate and set random method types for global method names.
    public static func generateRandomMethodTypes(forBuilder b: ProgramBuilder, n: Int) {
        for _ in 0..<n {
            let method = chooseUniform(from: b.fuzzer.environment.customMethodNames)
            let signature = ProgramTemplate.generateSignature(forFuzzer: b.fuzzer, n: Int.random(in: 0..<3))
            b.setSignature(ofMethod: method, to: signature)
        }
    }

    /// Generate a random type to use in e.g. function signatures.
    /// This function should only emit types that can be constructed by ProgramBuilder.generateVariable.
    public static func generateType(forFuzzer fuzzer: Fuzzer, forProperty property: String = "") -> Type {
        return withEqualProbability(
            // Choose a basic type
            { () -> Type in
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

                var group: String? = nil
                if probability(0.1) {
                    group = chooseUniform(from: fuzzer.environment.constructables)
                } else {
                    // Generate random properties, but only if there is no custom group.
                    // We filter the candidates to avoid cycles in our objects.
                    // TODO: we should remove this "no-cycle" restriction here, and let `generateVariable`
                    // handle these cases. We should also allow groups with custom properties/methods.
                    for _ in 1..<3 {
                        let candidates = fuzzer.environment.customPropertyNames.filter({ $0 > property })
                        if !candidates.isEmpty {
                            properties.append(chooseUniform(from: candidates))
                        }
                    }

                    // Generate random methods
                    for _ in 1..<3 {
                        methods.append(chooseUniform(from: fuzzer.environment.customMethodNames))
                    }
                }

                return .object(ofGroup: group, withProperties: properties, withMethods: methods)
            })
    }

    /// Generate a random function signature.
    public static func generateSignature(forFuzzer fuzzer: Fuzzer, n: Int) -> FunctionSignature {
        var params: [Parameter] = []
        for _ in 0..<n {
            params.append(.plain(generateType(forFuzzer: fuzzer)))
        }

        let returnType = generateType(forFuzzer: fuzzer)

        return FunctionSignature(expects: params, returns: returnType)
    }
}

