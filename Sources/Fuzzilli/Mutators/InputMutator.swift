// Copyright 2019 Google LLC
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

/// A mutator that changes the input variables of instructions in a program.
public class InputMutator: BaseInstructionMutator {
    /// Whether this instance is type aware or not.
    /// A type aware InputMutator will attempt to find "compatible" replacement
    /// variables, which have roughly the same type as the replaced variable.
    public let typeAwareness: TypeAwareness

    private let logger: Logger

    public enum TypeAwareness {
        case loose
        case aware
    }

    public init(typeAwareness: TypeAwareness) {
        self.typeAwareness = typeAwareness
        self.logger = Logger(withLabel: "InputMutator \(String(describing: typeAwareness))")
        var maxSimultaneousMutations = defaultMaxSimultaneousMutations
        // A type aware instance can be more aggressive. Based on simple experiments and
        // the mutator correctness rates, it can very roughly be twice as aggressive.
        switch self.typeAwareness {
        case .aware:
            maxSimultaneousMutations *= 2
        default:
            break
        }
        super.init(
            name: "InputMutator (\(String(describing: self.typeAwareness)))",
            maxSimultaneousMutations: maxSimultaneousMutations)
    }

    public override func canMutate(_ instr: Instruction) -> Bool {
        if instr.isNotInputMutable {
            // This is currently the case for some WasmInstructions that have to adhere to
            // more rules than just strict typing, e.g. WasmStoreGlobal/WasmLoadGlobal
            // Also the case for wasmReassign.
            return false
        }

        return instr.numInputs > 0
    }

    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {
        var inouts = b.adopt(instr.inouts)

        // Replace one input
        let selectedInput = Int.random(in: 0..<instr.numInputs)
        // Inputs to block end instructions must be taken from the outer scope since the scope
        // closed by the instruction is currently still active.
        let replacement: Variable?

        let type = b.type(of: inouts[selectedInput])

        // In Wasm we need strict typing, so there is no notion of loose or aware.
        if b.context.contains(.wasm) || b.context.contains(.wasmFunction)
            || b.context.contains(.wasmTypeGroup)
        {
            replacement = findWasmReplacement(
                forInput: selectedInput, of: instr, in: inouts, b)
        } else if !type.MayBe(.jsAnything) {
            // When the input type is not a JS variable, we cannot call randomJSVariable or randomVariable(forUseAs: ) as those might return any JS variable.
            replacement = b.randomVariable(ofType: type)
        } else {
            switch self.typeAwareness {
            case .loose:
                replacement = b.randomJsVariable()
            case .aware:
                replacement = b.randomVariable(forUseAs: type)
            }
        }

        if let replacement = replacement {
            b.trace(
                "Replacing input \(selectedInput) (\(inouts[selectedInput])) with \(replacement)")
            inouts[selectedInput] = replacement
        }

        b.append(Instruction(instr.op, inouts: inouts))
    }

    private func findWasmReplacement(
        forInput selectedInput: Int,
        of instr: Instruction,
        in inouts: [Variable],
        _ b: ProgramBuilder
    ) -> Variable? {
        let type = b.type(of: inouts[selectedInput])

        // TODO(mliedtke): For type definitions we need a lot of consistency. E.g. the signature
        // flowing into the block begin operation and the block end operation need to be in
        // sync.
        if type.Is(.wasmTypeDef()) {
            return inouts[selectedInput]
        }

        // Try instruction-specific mutations first.
        if let replacement = findInstructionSpecificWasmReplacement(
            forInput: selectedInput, of: instr, in: inouts, b)
        {
            return replacement
        }

        return b.randomVariable(ofType: type)
    }

    private func findInstructionSpecificWasmReplacement(
        forInput selectedInput: Int,
        of instr: Instruction,
        in inouts: [Variable],
        _ b: ProgramBuilder
    ) -> Variable? {
        switch instr.op.opcode {
        case .wasmRefGetDesc,
            .wasmStructGet,
            .wasmStructSet,
            .wasmArrayGet,
            .wasmArraySet:
            // Input 0 is always the target struct or array reference.
            guard selectedInput == 0 else { return nil }
            let currentType = b.type(of: inouts[selectedInput])
            guard case .Index(let desc, let wasExact) = currentType.wasmReferenceType!.kind else {
                fatalError("Expected index reference type for \(inouts[selectedInput])")
            }
            // Possibly replace the (possibly non-nullable) index ref with a nullable one,
            // preserving exactness if the original input was exact.
            let typeDesc = desc.get()!
            let nullableType = ILType.wasmIndexRef(typeDesc, nullability: true, isExact: wasExact)
            return b.randomVariable(ofType: nullableType)
        case .wasmArrayLen:
            return b.randomVariable(ofType: .wasmArrayRef())
        default:
            return nil
        }
    }
}
