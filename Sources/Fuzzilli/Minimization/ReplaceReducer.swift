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

// Attempts to replace "complex" instructions with simpler instructions.
struct ReplaceReducer: Reducer {
    func reduce(_ code: inout Code, with verifier: ReductionVerifier) {
        simplifyFunctionDefinitions(&code, with: verifier)
        simplifySimpleInstructions(&code, with: verifier)
    }

    func simplifyFunctionDefinitions(_ code: inout Code, with verifier: ReductionVerifier) {
        // Try to turn "fancy" functions into plain functions
        for group in Blocks.findAllBlockGroups(in: code) {
            guard let begin = group.begin.op as? BeginAnyFunction else { continue }
            Assert(group.end.op is EndAnyFunction)
            if begin is BeginPlainFunction { continue }

            let newBegin = Instruction(BeginPlainFunction(signature: begin.signature, isStrict: begin.isStrict), inouts: group.begin.inouts)
            let newEnd = Instruction(EndPlainFunction())
            verifier.tryReplacements([(group.head, newBegin), (group.tail, newEnd)], in: &code)
        }
    }

    func simplifySimpleInstructions(_ code: inout Code, with verifier: ReductionVerifier) {
        // Miscellaneous simplifications, mostly turning SomeOpWithSpread into SomeOp since spread operations are less "mutation friendly" (somewhat low value, high chance of producing invalid code)
        for instr in code {
            var newOp: Operation? = nil
            switch instr.op {
            case let op as CreateObjectWithSpread:
                if op.numSpreads == 0 {
                    newOp = CreateObject(propertyNames: op.propertyNames)
                }
            case let op as CreateArrayWithSpread:
                newOp = CreateArray(numInitialValues: op.numInputs)
            case let op as CallFunctionWithSpread:
                newOp = CallFunction(numArguments: op.numArguments)
            case let op as ConstructWithSpread:
                newOp = Construct(numArguments: op.numArguments)
            case let op as CallMethodWithSpread:
                newOp = CallMethod(methodName: op.methodName, numArguments: op.numArguments)
            case let op as CallComputedMethodWithSpread:
                newOp = CallComputedMethod(numArguments: op.numArguments)
            case let op as Construct:
                // Prefer simple function calls over constructor calls if there's no difference
                newOp = CallFunction(numArguments: op.numArguments)
            // Prefer non strict functions over strict ones
            case let op as BeginPlainFunction:
                if op.isStrict {
                    newOp = BeginPlainFunction(signature: op.signature, isStrict: false)
                }
            case let op as BeginArrowFunction:
                if op.isStrict {
                    newOp = BeginArrowFunction(signature: op.signature, isStrict: false)
                }
            case let op as BeginGeneratorFunction:
                if op.isStrict {
                    newOp = BeginGeneratorFunction(signature: op.signature, isStrict: false)
                }
            case let op as BeginAsyncFunction:
                if op.isStrict {
                    newOp = BeginAsyncFunction(signature: op.signature, isStrict: false)
                }
            case let op as BeginAsyncGeneratorFunction:
                if op.isStrict {
                    newOp = BeginAsyncGeneratorFunction(signature: op.signature, isStrict: false)
                }
            default:
                break
            }

            if let op = newOp {
                verifier.tryReplacing(instructionAt: instr.index, with: Instruction(op, inouts: instr.inouts), in: &code)
            }
        }
    }
}
